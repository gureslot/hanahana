-- =============================================================================
-- 0044 : start_boss_battle の所要時間を「役割別」に（テスト用の短縮値）
--   0042 の start_boss_battle を base に、travel_sec を役割で分岐させるだけ。
--   他のロジック（占有/所有/SP離脱/フロンティア/ロック/回数消費/出撃行作成）は不変。
--
-- ★テスト中の一時値（本番前に必ず戻す）：
--   (1) travel_sec：中ボスA=10s / 中ボスB=15s / 面ボス=30s
--       → 本番は a=1200(20分) / b=1500(25分) / boss=1800(30分)（暫定・調整可）。
--   (2) 1日3回制限：テスト中は OFF（コメントアウト）。本番で復活させる。
--       ※クライアントの BOSS_TEST_NO_LIMIT と対。両方戻すこと。
--
-- 実行: SQL Editor に貼って Run（create or replace・再実行可）。
-- =============================================================================
create or replace function public.start_boss_battle(p_deck_no integer, p_boss_key text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid        uuid := auth.uid();
  today      date := (now() at time zone 'Asia/Tokyo')::date;
  prof       public.profiles;
  v_boss_count int;
  m          text[];
  v_stage    int;
  v_role     text;
  v_round    int;
  v_deck     public.decks;
  slot_ids   uuid[];
  i          int;
  cid        uuid;
  vc         public.cards;
  v_travel_sec int;   -- ★役割別（boss_key 解析後に決定）
begin
  if uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select * into prof from public.profiles where id = uid for update;
  if not found then raise exception 'profile not initialized'; end if;

  -- 既にこのデッキが出撃中なら不可
  if exists (select 1 from public.boss_sorties where user_id = uid and deck_no = p_deck_no) then
    raise exception 'DECK_ALREADY_ON_SORTIE';
  end if;

  -- 1日3回（出撃時に消費）
  if prof.boss_date < today then v_boss_count := 0; else v_boss_count := prof.boss_count_today; end if;
  -- if v_boss_count >= 3 then raise exception 'boss daily limit reached (3/day)'; end if;   -- ★TEST: 制限OFF（本番でコメント解除）

  -- boss_key 解析
  m := regexp_match(p_boss_key, '^boss_([1-8])_(a|b|boss)(?:_r([0-9]+))?$');
  if m is null then raise exception 'invalid boss_key %', p_boss_key; end if;
  v_stage := m[1]::int; v_role := m[2]; v_round := coalesce(m[3]::int, 1);
  if v_round < 1 then v_round := 1; end if;
  if not exists (select 1 from public.boss_master where boss_key = 'boss_' || v_stage || '_' || v_role) then
    raise exception 'boss % not found in boss_master', 'boss_' || v_stage || '_' || v_role;
  end if;

  -- ★所要時間（役割別・テスト短縮値）。本番値はコメント参照。
  v_travel_sec := case v_role
                    when 'a' then 10     -- 中ボスA（本番: 1200）
                    when 'b' then 15     -- 中ボスB（本番: 1500）
                    else          30     -- 面ボス  （本番: 1800）
                  end;

  -- 周回フロンティア検証（到達点以下のみ出撃可）
  if v_round > prof.boss_round
     or (v_round = prof.boss_round and v_stage > prof.boss_round_stage + 1) then
    raise exception 'BOSS_LOCKED';
  end if;

  -- デッキ取得＋スロット検証（占有・所有・SP離脱）
  select * into v_deck from public.decks where user_id = uid and deck_no = p_deck_no;
  if not found then raise exception 'deck % not found', p_deck_no; end if;
  slot_ids := array[v_deck.slot1_card_id, v_deck.slot2_card_id, v_deck.slot3_card_id];
  if slot_ids[1] is null and slot_ids[2] is null and slot_ids[3] is null then
    raise exception 'deck % is empty', p_deck_no;
  end if;
  for i in 1..3 loop
    cid := slot_ids[i];
    if cid is null then continue; end if;
    perform public._chikarian_assert_not_in_tansaku(cid);   -- 探索中 or 他ボス出撃中なら拒否
    select * into vc from public.cards where id = cid and user_id = uid;
    if not found then raise exception 'card % not owned', cid; end if;
    if exists (select 1 from public.sp_states s where s.card_id = cid and s.unavailable_until >= today) then
      raise exception 'card % is SP-unavailable today', cid;
    end if;
  end loop;

  -- 回数 +1（消費）
  update public.profiles set boss_count_today = v_boss_count + 1, boss_date = today where id = uid;

  -- デッキの編成カードをロック（boss_deck_no = deck_no）
  update public.cards c
     set boss_deck_no = p_deck_no::smallint
    from public.decks d
   where d.user_id = uid and d.deck_no = p_deck_no
     and c.user_id = uid
     and c.id in (d.slot1_card_id, d.slot2_card_id, d.slot3_card_id);

  -- 出撃行を作成
  insert into public.boss_sorties(user_id, deck_no, boss_key, started_at, travel_sec, is_returning)
    values (uid, p_deck_no, p_boss_key, now(), v_travel_sec, false);

  return jsonb_build_object(
    'deck_no',    p_deck_no,
    'boss_key',   p_boss_key,
    'started_at', now(),
    'travel_sec', v_travel_sec,
    'arrive_at',  now() + (v_travel_sec || ' seconds')::interval
  );
end;
$$;
revoke all on function public.start_boss_battle(integer, text) from public, anon;
grant execute on function public.start_boss_battle(integer, text) to authenticated;
