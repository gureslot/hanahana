-- =============================================================================
-- 0050 : デッキから外したカードの武気をプールへ返却（A-2 / 「武気はデッキ中のみ保持」）
--   update_deck で「このデッキの旧スロットに在り、新スロットにも他デッキにも残らない」カードの
--   loaded_buki × 枠コスト(quality: crude1/refined2/enchanted4/holy8 = 0017 equip_buki と同値)を
--   renkiden.buki_stored へ返却し loaded_buki=0。デッキ間「移動」では返却しない（在籍継続）。
--   ※update_deck のみ再定義（0043 ベース）。前提：0043 適用済み。再実行可。
-- =============================================================================

-- =============================================================================
-- 0043 : デッキ編成の「1カード＝1デッキ（共有不可）」をサーバで強制
-- 出典: canon-06-gameplay.md「前提＝1カード＝1デッキ（共有不可）」
--
-- 背景:
--   update_deck(最新=0035) はデッキ内の重複は弾くが、デッキ間の排他が無い。
--   そのため同じカードをデッキ1とデッキ2の両方に編成保存できてしまっていた。
--
-- 本マイグレーションの内容:
--   (1) update_deck を 0035 ベースで再定義し、★クロスデッキ排他を1ステップ追加。
--       = これから編成する非nullカードを、同ユーザの他デッキの枠から自動で外す（＝移動）。
--   (2) 一度きりの掃除：既に二重編成されているカードを最小 deck_no に寄せて解消。
--
-- 実行: SQL Editor に貼って Run（create or replace・再実行可。掃除DOも冪等）。
-- 前提: 0033（cards.tansaku_deck_no）＋0034（ヘルパ）＋0042（boss_deck_no 対応の
--       _chikarian_assert_not_in_tansaku 拡張）適用済み。
-- =============================================================================

-- ===== update_deck（0035）＋ クロスデッキ排他 =====
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
  v_old_ids uuid[];
  v_removed uuid[];
  rc record;
  v_qcost int;
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

  -- A-2: このデッキの更新前スロット（外れたカードの武気返却判定に使う）
  select array[slot1_card_id, slot2_card_id, slot3_card_id] into v_old_ids
    from public.decks where user_id = uid and deck_no = p_deck_no;

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

      -- 占有ロック(b)：探索/ボス出撃中カードは新たに編成できない（canon-06 §3-4 / 0042）
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

  -- ★ クロスデッキ排他（1カード＝1デッキ・共有不可）：
  --   これから編成する非nullカードを、同ユーザの「他デッキ」の枠から外す（＝移動）。
  --   出撃ロックの有るカードは上の _chikarian_assert_not_in_tansaku で既に弾かれているため、
  --   ここに到達するのはロックの無いカードのみ（出撃中デッキの編成は壊さない）。
  if nonnull is not null then
    update public.decks
      set slot1_card_id = case when slot1_card_id = any(nonnull) then null else slot1_card_id end,
          slot2_card_id = case when slot2_card_id = any(nonnull) then null else slot2_card_id end,
          slot3_card_id = case when slot3_card_id = any(nonnull) then null else slot3_card_id end
      where user_id = uid
        and deck_no <> p_deck_no
        and (slot1_card_id = any(nonnull) or slot2_card_id = any(nonnull) or slot3_card_id = any(nonnull));
  end if;

  -- 検証通過 → デッキ更新（無ければ作成）
  insert into public.decks (user_id, deck_no, slot1_card_id, slot2_card_id, slot3_card_id)
  values (uid, p_deck_no, p_slot1, p_slot2, p_slot3)
  on conflict (user_id, deck_no)
  do update set slot1_card_id = excluded.slot1_card_id,
                slot2_card_id = excluded.slot2_card_id,
                slot3_card_id = excluded.slot3_card_id;

  -- A-2: このデッキから外れ、かつ新スロットにも他デッキにも残らないカードの武気をプールへ返却。
  --   返却量 = loaded_buki(枠) × 枠コスト(quality)。枠コストは 0017 equip_buki と同値(crude1/refined2/enchanted4/holy8)。
  --   デッキ間「移動」(他デッキへ在籍)では返却しない。武気はデッキ中のみ保持(canon・06-15)。
  if v_old_ids is not null then
    select array_agg(x) into v_removed
      from unnest(v_old_ids) as x
      where x is not null
        and not (x = any(coalesce(nonnull, array[]::uuid[])))
        and not exists (
          select 1 from public.decks d
          where d.user_id = uid
            and x in (d.slot1_card_id, d.slot2_card_id, d.slot3_card_id)
        );
    if v_removed is not null then
      for rc in
        select id, quality, coalesce(loaded_buki, 0) as lb
          from public.cards
          where id = any(v_removed) and user_id = uid and coalesce(loaded_buki, 0) > 0
      loop
        v_qcost := case rc.quality when 'crude' then 1 when 'refined' then 2
                                   when 'enchanted' then 4 when 'holy' then 8 else 0 end;
        if v_qcost > 0 and rc.lb > 0 then
          update public.renkiden set buki_stored = buki_stored + (rc.lb * v_qcost) where user_id = uid;
        end if;
        update public.cards set loaded_buki = 0 where id = rc.id;
      end loop;
    end if;
  end if;

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

-- =============================================================================
-- (2) 一度きりの掃除：既存の二重編成を解消
--   同じカードが複数デッキにある場合、最小 deck_no に残し、他デッキの該当枠を null に。
--   今回の SR花剣（デッキ1・2両方）は → デッキ1に残り、デッキ2から外れます。
--   外れた側は、クライアントの移動確認つきで編成し直せます。
--   冪等：二重編成が無ければ何もしない。
-- =============================================================================
do $$
declare r record;
begin
  for r in
    select user_id, card_id, min(deck_no) as keep
    from (
      select user_id, deck_no, slot1_card_id as card_id from public.decks where slot1_card_id is not null
      union all select user_id, deck_no, slot2_card_id from public.decks where slot2_card_id is not null
      union all select user_id, deck_no, slot3_card_id from public.decks where slot3_card_id is not null
    ) s
    group by user_id, card_id
    having count(*) > 1
  loop
    update public.decks
      set slot1_card_id = case when slot1_card_id = r.card_id then null else slot1_card_id end,
          slot2_card_id = case when slot2_card_id = r.card_id then null else slot2_card_id end,
          slot3_card_id = case when slot3_card_id = r.card_id then null else slot3_card_id end
      where user_id = r.user_id and deck_no <> r.keep
        and (slot1_card_id = r.card_id or slot2_card_id = r.card_id or slot3_card_id = r.card_id);
  end loop;
end $$;

-- =============================================================================
-- 確認クエリ（任意）：二重編成が残っていないこと（0行が正常）
--   select user_id, card_id, count(*)
--   from (
--     select user_id, slot1_card_id card_id from public.decks where slot1_card_id is not null
--     union all select user_id, slot2_card_id from public.decks where slot2_card_id is not null
--     union all select user_id, slot3_card_id from public.decks where slot3_card_id is not null
--   ) s group by user_id, card_id having count(*) > 1;
-- =============================================================================
