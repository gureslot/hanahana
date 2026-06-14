-- =============================================================================
-- 0005 : update_deck(deck_no, slot1, slot2, slot3) ＝ デッキ編成RPC
-- 出典: spec §2（所持・SP離脱中でない・重複なし）＋ 確定値（本数解放・コスト上限11）
-- 実行: SQL Editor に貼って Run（create or replace・再実行可）。
-- 呼び方: supabase.rpc('update_deck', { p_deck_no: 1, p_slot1: '<card_id>', p_slot2: null, p_slot3: null })
--
-- 検証項目（全て満たさなければ raise・更新しない）:
--   1. deck_no ≤ 編成可能本数 = 2 + floor(cleared_stage/2)（上限6）
--   2. 各 card_id が自分の所持カード
--   3. 同じ card_id を2枠以上に入れない（重複なし）
--   4. SP離脱中（sp_states.unavailable_until ≥ 今日JST）のカードは編成不可
--   5. 3枚のコスト合計 ≤ 11（N1/R2/SR3/SP4/SSR5）
-- 空きスロットは null 可（埋まっている枠だけ検証）。
-- =============================================================================

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

-- =============================================================================
-- 備考:
--  * レア→コストは card_key 末尾で判定（cardsにレア列が無いため）。
--    判定順は _ssr → _sp → _sr → _r → _n（_ssrを_srより先に・後方一致の取り違え防止）。
--    '_' は LIKE のワイルドカードなので escape '\' でリテラル扱い。
--  * SPコスト=4（SR3とSSR5の中間・2026-06-14確定）。
--  * デッキ枠は3固定（slot1/2/3）。本数上限6・解放=2+floor(cleared_stage/2)。
--  * 出撃中デッキの占有チェックは探索/戦闘RPC側で扱う（本RPCは編成のみ）。
-- =============================================================================
