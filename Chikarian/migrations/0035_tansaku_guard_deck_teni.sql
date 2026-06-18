-- ============================================================
-- Chikarian migration 0035: 占有ロック拒否チェック（CARD_IN_TANSAKU）を資産RPCに追加（2/3）
--   canon-06 §3-4 占有ロック / canon-07 §4「未実装」（B-2方式の第二段・続き）
--
--   0034 のヘルパ _chikarian_assert_not_in_tansaku(card_id) を使う（0034 適用済み前提）。
--   本ファイル(0035)対象：
--     ・update_deck(0005)   …(a) 新たに編成するカードが探索中なら拒否（ループ内）
--                            (b) このデッキが探索中（現編成カードが出発中）なら編成変更を拒否
--                            ＝出発中デッキの編成変更も、出発中カードの新規編成も両方塞ぐ。
--     ・do_skill_teni(0013) … 転移の素材(src)・対象(dst) いずれも探索中なら拒否。
--   続き：do_boss_battle(0032)・start_tansaku(0033 自己チェック)＝0036。
--   ※各RPCは最新版（update_deck=0005 / do_skill_teni=0013）を base に再定義。
--   前提: 0033（cards.tansaku_deck_no）＋0034（ヘルパ）適用済み。
-- ============================================================

-- ===== update_deck（0005）＋ CARD_IN_TANSAKU =====
create or replace function public.update_deck(
  p_deck_no integer,
  p_slot1 uuid default null,
  p_slot2 uuid default null,
  p_slot3 uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  today date := (now() at time zone 'Asia/Tokyo')::date;
  prof public.profiles;
  max_decks int;
  slots uuid[];
  nonnull uuid[];
  c record;
  total_cost int := 0;
  card_count int := 0;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  select * into prof from public.profiles where id = uid for update;
  if not found then raise exception 'profile not initialized'; end if;

  -- 1. デッキ本数の解放検証
  max_decks := least(2 + (prof.cleared_stage / 2), 6);   -- cleared_stageはsmallint→整数除算
  if p_deck_no < 1 or p_deck_no > max_decks then
    raise exception 'deck % not unlocked (max %)', p_deck_no, max_decks;
  end if;

  -- 占有ロック(a)：このデッキが探索中（現編成カードが出発中）なら編成変更を拒否（canon-06 §3-4）
  if exists (
    select 1 from public.decks d
    join public.cards ca
      on ca.id in (d.slot1_card_id, d.slot2_card_id, d.slot3_card_id)
    where d.user_id = uid and d.deck_no = p_deck_no and ca.tansaku_deck_no is not null
  ) then
    raise exception 'CARD_IN_TANSAKU';
  end if;

  slots := array[p_slot1, p_slot2, p_slot3];

  -- 非nullスロットだけ抽出
  select array_agg(s) into nonnull
  from unnest(slots) as s
  where s is not null;

  if nonnull is not null then
    -- 3. 重複なし（非nullの中に重複があればエラー）
    if (select count(*) from unnest(nonnull)) <> (select count(distinct x) from unnest(nonnull) as x) then
      raise exception 'duplicate card in deck';
    end if;

    -- 2,4,5 を1ループで検証
    for c in
      select id, card_key, user_id from public.cards where id = any(nonnull)
    loop
      -- 2. 所持検証（自分のカードか）
      if c.user_id <> uid then
        raise exception 'card % not owned', c.id;
      end if;

      -- 占有ロック(b)：探索中カードは新たに編成できない（canon-06 §3-4）
      perform public._chikarian_assert_not_in_tansaku(c.id);

      -- 4. SP離脱中でないか
      if exists (
        select 1 from public.sp_states sp
        where sp.card_id = c.id and sp.unavailable_until >= today
      ) then
        raise exception 'card % is SP-unavailable today', c.id;
      end if;

      -- 5. コスト加算（card_key末尾サフィックスでレア→コスト）
      total_cost := total_cost + case
        when c.card_key like '%\_ssr' escape '\' then 5
        when c.card_key like '%\_sp'  escape '\' then 4
        when c.card_key like '%\_sr'  escape '\' then 3
        when c.card_key like '%\_r'   escape '\' then 2
        when c.card_key like '%\_n'   escape '\' then 1
        else 0  -- 想定外キーは0（cards.md外）。必要ならraiseに変更可
      end;

      card_count := card_count + 1;
    end loop;

    -- 指定IDのうち、自分のカードとして見つからなかったものがあればエラー
    if card_count <> (select count(*) from unnest(nonnull)) then
      raise exception 'some cards not found / not owned';
    end if;

    -- 5. コスト上限
    if total_cost > 11 then
      raise exception 'deck cost % exceeds limit 11', total_cost;
    end if;
  end if;

  -- 検証通過 → デッキ更新（無ければ作成）
  insert into public.decks (user_id, deck_no, slot1_card_id, slot2_card_id, slot3_card_id)
  values (uid, p_deck_no, p_slot1, p_slot2, p_slot3)
  on conflict (user_id, deck_no)
  do update set slot1_card_id = excluded.slot1_card_id,
                slot2_card_id = excluded.slot2_card_id,
                slot3_card_id = excluded.slot3_card_id;

  return jsonb_build_object(
    'deck_no', p_deck_no,
    'slots', jsonb_build_array(p_slot1, p_slot2, p_slot3),
    'total_cost', total_cost,
    'cost_limit', 11,
    'max_decks', max_decks
  );
end;
$$;

revoke all on function public.update_deck(integer, uuid, uuid, uuid) from public;
grant execute on function public.update_deck(integer, uuid, uuid, uuid) to authenticated;


-- ===== do_skill_teni（0013）＋ CARD_IN_TANSAKU =====
create or replace function public.do_skill_teni(
  p_src_id   uuid,
  p_src_slot integer,
  p_dst_id   uuid,
  p_dst_slot integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_cost integer := 3000;        -- balance §3（仮）
  v_src record;
  v_dst record;
  v_skill record;
  v_medal_have bigint;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_src_id = p_dst_id then raise exception 'SAME_CARD'; end if;
  if p_dst_slot not in (1, 2) then raise exception 'DST_SLOT_INVALID'; end if;  -- 0=固定は不可侵

  select * into v_src from public.cards where id = p_src_id and user_id = v_uid for update;
  if not found then raise exception 'SRC_NOT_FOUND'; end if;
  select * into v_dst from public.cards where id = p_dst_id and user_id = v_uid for update;
  if not found then raise exception 'DST_NOT_FOUND'; end if;

  if public._chikarian_rarity(v_src.card_key) = 'sp' then raise exception 'SP_NOT_TRANSFERABLE'; end if;
  if public._chikarian_rarity(v_dst.card_key) = 'sp' then raise exception 'SP_NO_SLOT'; end if;
  if v_src.locked then raise exception 'SRC_LOCKED'; end if;

  -- 占有ロック：探索中カードは転移の素材(src)/対象(dst)にできない（canon-06 §3-4）
  perform public._chikarian_assert_not_in_tansaku(p_src_id);
  perform public._chikarian_assert_not_in_tansaku(p_dst_id);

  -- 取り出すスキル（固定slot0でも可）
  select skill_key, skill_lv into v_skill
    from public.card_skills where card_id = p_src_id and slot = p_src_slot;
  if not found then raise exception 'SRC_SKILL_NOT_FOUND'; end if;

  -- 受け側の空き枠確認（既に埋まっていれば不可）
  perform 1 from public.card_skills where card_id = p_dst_id and slot = p_dst_slot;
  if found then raise exception 'DST_SLOT_OCCUPIED'; end if;

  -- メダル検証・消費
  select medal into v_medal_have from public.profiles where id = v_uid for update;
  if v_medal_have < v_cost then raise exception 'INSUFFICIENT_MEDAL'; end if;
  update public.profiles set medal = medal - v_cost where id = v_uid;

  -- スキルを受け側へ挿入（Lv持ち込み）→ 素材カード（全スキル）消滅
  insert into public.card_skills (card_id, slot, skill_key, skill_lv)
    values (p_dst_id, p_dst_slot, v_skill.skill_key, v_skill.skill_lv);
  delete from public.card_skills where card_id = p_src_id;
  delete from public.cards where id = p_src_id and user_id = v_uid;

  return jsonb_build_object(
    'moved_skill',     v_skill.skill_key,
    'moved_lv',        v_skill.skill_lv,
    'dst_id',          p_dst_id,
    'dst_slot',        p_dst_slot,
    'medal_spent',     v_cost,
    'medal_remaining', v_medal_have - v_cost
  );
end;
$$;

revoke all on function public.do_skill_teni(uuid, integer, uuid, integer) from public, anon;
grant execute on function public.do_skill_teni(uuid, integer, uuid, integer) to authenticated;
