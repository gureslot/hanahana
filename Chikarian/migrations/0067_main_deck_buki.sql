-- ============================================================
-- Chikarian migration 0067: メインデッキ制（武気・ボス出撃はデッキ1のみ）
--   canon-06 §4-1（2026-06-22 確定）／canon-04 §7。
--
--   背景: 武気は「デッキ編成中のカード」に保持される実装だったため、全デッキ(最大6本×3枚)に
--         武気を積めて「取り出し可能な武気倉庫」になり、練気殿の保管上限(Lv5=7,000)が事実上
--         無効化されていた（デッキ群の収容量 > 上限）。武気を消費するのはボス戦だけ・探索は武気
--         不使用なので、武気を込められるデッキを「メインデッキ＝デッキ1」1本に限定する。
--
--   本ファイルの内容（基底＝現行最新版を一字一句ベースに最小改修）:
--     (0) ヘルパ _chikarian_reclaim_nonmain_buki(uid)：デッキ1に編成されていない武気付きカードの
--         loaded_buki×枠コスト(1/3/9/27 = 現行 equip_buki と同値)をプールへ返却し loaded_buki=0。
--     (1) equip_buki（基底=0034）：p_amount>0 のときカードがデッキ1編成でなければ CARD_NOT_IN_MAIN_DECK。
--     (2) start_boss_battle（基底=0054）：p_deck_no<>1 なら NOT_MAIN_DECK。
--         ※テストハック（日次上限OFF・travel_sec 10/15/30）は 0054 のまま温存（本番前=Phase5 で復帰）。
--     (3) update_deck（基底=0050）：旧A-2返却（条件=どのデッキにも残らない／コスト=旧1/2/4/8）を撤廃し、
--         編成更新後に (0) のヘルパを呼ぶ。これで「武気はデッキ1のみ」を強制＋返却コストを 1/3/9/27 に是正。
--         （0050 のコメントは「0017と同値(1/2/4/8)」と記すが 0017 は 0031 で上書き済み＝精製以上で武気が
--           目減りしていた不整合を本ファイルで解消。）
--     (4) swap_main_deck(p_other_deck_no)【新規】：デッキ1↔対象デッキ(2..max)のスロットを原子的に入れ替え、
--         デッキ1を離れたカードの武気を (0) で返却。占有中(探索/ボス出撃)は CARD_IN_TANSAKU で拒否。
--     (5) 移行(1回)：既存の全ユーザに (0) を流し、非メインデッキの武気をプールへ返却（超過は没収せず許容
--         ＝整合は equip_buki/即生産が上限到達中だけ止まる挙動と同じ・buki_stored に上限CHECKは無い）。
--
--   前提: 0034/0050/0054 適用済み。create or replace ＝再実行可。
--   クライアント: 新エラー NOT_MAIN_DECK / CARD_NOT_IN_MAIN_DECK の和文 ＋ ボス画面のメインデッキ化は
--                 別途クライアント増分で対応（本ファイルはサーバのみ）。
-- ============================================================

-- ===== (0) ヘルパ：非メイン(デッキ1以外)の武気をプールへ返却し loaded_buki=0 =====
-- 返却量 = loaded_buki(枠) × 枠コスト(quality: crude1/refined3/enchanted9/holy27 = 現行 equip_buki と同値)。
-- 「デッキ1に編成中のカード」だけ武気を保持できる（canon-06 §4-1）。冪等：実行後は非メインの武気は0。
create or replace function public._chikarian_reclaim_nonmain_buki(p_uid uuid)
returns numeric
language plpgsql
as $$
declare
  v_reclaim numeric := 0;
begin
  select coalesce(sum(
           coalesce(c.loaded_buki, 0) * case c.quality
             when 'crude' then 1 when 'refined' then 3
             when 'enchanted' then 9 when 'holy' then 27 else 0 end), 0)
    into v_reclaim
    from public.cards c
   where c.user_id = p_uid
     and coalesce(c.loaded_buki, 0) > 0
     and not exists (
       select 1 from public.decks d
        where d.user_id = p_uid and d.deck_no = 1
          and c.id in (d.slot1_card_id, d.slot2_card_id, d.slot3_card_id));

  if v_reclaim > 0 then
    -- buki_stored は integer・上限CHECK無し＝超過許容（没収しない）。
    update public.renkiden
       set buki_stored = buki_stored + v_reclaim
     where user_id = p_uid;

    update public.cards c
       set loaded_buki = 0
     where c.user_id = p_uid
       and coalesce(c.loaded_buki, 0) > 0
       and not exists (
         select 1 from public.decks d
          where d.user_id = p_uid and d.deck_no = 1
            and c.id in (d.slot1_card_id, d.slot2_card_id, d.slot3_card_id));
  end if;

  return v_reclaim;
end;
$$;
revoke all on function public._chikarian_reclaim_nonmain_buki(uuid) from public, anon, authenticated;

-- ===== (1) equip_buki（基底=0034）＋ メインデッキ限定ガード =====
create or replace function public.equip_buki(
  p_card_id uuid,
  p_quality text,
  p_amount  integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_card record;
  v_rare text;
  v_cap_base numeric; v_cap_max numeric; v_lv_cap integer;
  v_capacity integer;
  v_quality_lv integer;
  v_kajiya_lv integer;
  v_new_cost integer; v_new_atk integer;
  v_old_cost integer;
  v_pool numeric;
  v_refund numeric;
  v_affordable integer;
  v_filled integer;
  v_draw numeric;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_quality not in ('crude','refined','enchanted','holy') then raise exception 'INVALID_QUALITY'; end if;
  if p_amount is null or p_amount < 0 then raise exception 'INVALID_AMOUNT'; end if;

  select * into v_card from public.cards where id = p_card_id and user_id = v_uid for update;
  if not found then raise exception 'CARD_NOT_FOUND'; end if;

  -- 占有ロック：探索中カードは充填（装備）不可（canon-06 §3-4）
  perform public._chikarian_assert_not_in_tansaku(p_card_id);

  -- メインデッキ制：武気を込められるのはデッキ1（メインデッキ）のカードのみ（canon-06 §4-1）。
  -- p_amount=0（アンロード）は在席に関わらず許容。
  if p_amount > 0 and not exists (
    select 1 from public.decks d
    where d.user_id = v_uid and d.deck_no = 1
      and p_card_id in (d.slot1_card_id, d.slot2_card_id, d.slot3_card_id)
  ) then
    raise exception 'CARD_NOT_IN_MAIN_DECK';
  end if;

  v_rare := public._chikarian_rarity(v_card.card_key);
  if v_rare = 'sp' then raise exception 'SP_NO_EQUIP'; end if;

  -- 質の解放確認
  v_quality_lv := case p_quality when 'crude' then 1 when 'refined' then 2 when 'enchanted' then 3 when 'holy' then 4 end;
  select coalesce(max(case quality when 'holy' then 4 when 'enchanted' then 3 when 'refined' then 2 else 1 end), 1)
    into v_kajiya_lv
    from public.kajiya_orders where user_id = v_uid and claimed = true;
  if v_kajiya_lv < v_quality_lv then raise exception 'QUALITY_LOCKED'; end if;

  -- 充填量（枠上限・レア別）
  case v_rare
    when 'n'   then v_cap_base := 80;  v_cap_max := 240; v_lv_cap := 30;
    when 'r'   then v_cap_base := 120; v_cap_max := 400; v_lv_cap := 40;
    when 'sr'  then v_cap_base := 160; v_cap_max := 560; v_lv_cap := 50;
    when 'ssr' then v_cap_base := 200; v_cap_max := 800; v_lv_cap := 60;
    else raise exception 'RARITY_NOT_SUPPORTED';
  end case;
  v_capacity := floor(
    v_cap_base + (v_cap_max - v_cap_base)
                 * (least(v_card.lv, v_lv_cap) - 1)::numeric / (v_lv_cap - 1)
  )::int;

  v_new_cost := case p_quality when 'crude' then 1 when 'refined' then 3 when 'enchanted' then 9 when 'holy' then 27 end;
  v_new_atk  := case p_quality when 'crude' then 10 when 'refined' then 15 when 'enchanted' then 22 when 'holy' then 34 end;

  -- 練気殿プールを精算
  perform public._chikarian_renkiden_settle(v_uid);
  select buki_stored into v_pool from public.renkiden where user_id = v_uid for update;

  -- 現在込めている武気を返却（非破壊）
  v_old_cost := case v_card.quality
                  when 'crude' then 1 when 'refined' then 3
                  when 'enchanted' then 9 when 'holy' then 27 else 0 end;
  v_refund := coalesce(v_card.loaded_buki, 0) * v_old_cost;
  v_pool := v_pool + v_refund;     -- 返却後の実効プール

  -- 込めた武気（枠）
  v_affordable := floor(v_pool / v_new_cost)::int;
  v_filled := greatest(0, least(p_amount, v_capacity, v_affordable));
  v_draw := v_filled::numeric * v_new_cost;

  -- プール確定（DB値 + 返却 - 引出）
  update public.renkiden
     set buki_stored = buki_stored + v_refund - v_draw
   where user_id = v_uid;

  -- カード更新
  update public.cards
     set quality = p_quality, loaded_buki = v_filled
   where id = p_card_id;

  return jsonb_build_object(
    'card_id',        p_card_id,
    'quality',        p_quality,
    'loaded_buki',    v_filled,                 -- 込めた武気（枠）
    'capacity',       v_capacity,
    'soubi_kou',      v_filled * v_new_atk,     -- 装備項（発動前・表示用）
    'buki_drawn',     v_draw,
    'buki_refunded',  v_refund,
    'pool_remaining', v_pool - v_draw
  );
end;
$$;
revoke all on function public.equip_buki(uuid, text, integer) from public, anon;
grant execute on function public.equip_buki(uuid, text, integer) to authenticated;

-- ===== (2) start_boss_battle（基底=0054）＋ デッキ1限定ガード =====
-- ※テストハック温存：日次上限チェックはコメントのまま／travel_sec=10/15/30（本番値はコメント・Phase5で復帰）。
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

  -- メインデッキ制：ボス出撃はデッキ1（メインデッキ）のみ（canon-06 §4-1）
  if p_deck_no <> 1 then raise exception 'NOT_MAIN_DECK'; end if;

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
  -- 面内役割の順次ゲート（フロンティア面のみ・中A→中B→面ボス）。過去面/過去周は全役割可。
  if v_round = prof.boss_round and v_stage = prof.boss_round_stage + 1 then
    if v_role = 'b'    and prof.boss_round_role < 1 then raise exception 'BOSS_LOCKED'; end if;
    if v_role = 'boss' and prof.boss_round_role < 2 then raise exception 'BOSS_LOCKED'; end if;
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
    -- SP離脱中でも出撃可：do_boss_battle で戦力から除外し、下のロックでも対象外にする（外して出撃）
  end loop;

  -- 回数 +1（消費）
  update public.profiles set boss_count_today = v_boss_count + 1, boss_date = today where id = uid;

  -- デッキの編成カードをロック（boss_deck_no = deck_no）
  update public.cards c
     set boss_deck_no = p_deck_no::smallint
    from public.decks d
   where d.user_id = uid and d.deck_no = p_deck_no
     and c.user_id = uid
     and c.id in (d.slot1_card_id, d.slot2_card_id, d.slot3_card_id)
     and not exists (select 1 from public.sp_states s where s.card_id = c.id and s.unavailable_until >= today);  -- 離脱中SPはロック対象外（連れて行かない＝外して出撃）

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

-- ===== (3) update_deck（基底=0050）：A-2返却を撤廃し編成更新後に (0) を呼ぶ =====
-- 旧A-2（条件=どのデッキにも残らない／コスト=旧1/2/4/8）を削除し、ヘルパで「デッキ1以外の武気は0」を強制。
-- これにより (a) デッキ1→他デッキへ移したカードの武気が確実に返却され（武気倉庫の抜け穴を封鎖）、
--           (b) 返却コストが現行 equip_buki と同じ 1/3/9/27 に是正される（精製以上の目減りを解消）。
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

  -- メインデッキ制（canon-06 §4-1）：編成更新後、デッキ1に居ないカードの武気をプールへ返却し0にする。
  --   ＝デッキ1から外れた／デッキ1→他デッキへ移したカードの武気を確実に返却（コスト 1/3/9/27 で是正）。
  perform public._chikarian_reclaim_nonmain_buki(uid);

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

-- ===== (4) swap_main_deck：任意デッキ(2..max)とデッキ1のスロットを入れ替えて昇格 =====
-- canon-06 §4-1「メインデッキと入れ替える」。占有中(探索/ボス出撃)は不可。
-- 入れ替え後、デッキ1を離れたカードの武気は (0) で返却（デッキ1以外に武気は残さない）。
create or replace function public.swap_main_deck(p_other_deck_no integer)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid       uuid := auth.uid();
  prof      public.profiles;
  max_decks int;
  v_d1      public.decks;
  v_dn      public.decks;
  v_reclaimed numeric;
begin
  if uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_other_deck_no is null or p_other_deck_no = 1 then raise exception 'INVALID_DECK'; end if;

  select * into prof from public.profiles where id = uid for update;
  if not found then raise exception 'profile not initialized'; end if;

  max_decks := least(2 + (prof.cleared_stage / 2), 6);
  if p_other_deck_no < 2 or p_other_deck_no > max_decks then
    raise exception 'DECK_LOCKED';
  end if;

  -- 占有中は入れ替え不可：デッキ1・対象デッキの編成カードが探索 or ボス出撃中なら拒否（canon-06 §3-4）
  if exists (
    select 1 from public.decks d
    join public.cards ca
      on ca.id in (d.slot1_card_id, d.slot2_card_id, d.slot3_card_id)
    where d.user_id = uid and d.deck_no in (1, p_other_deck_no)
      and (ca.tansaku_deck_no is not null or ca.boss_deck_no is not null)
  ) then
    raise exception 'CARD_IN_TANSAKU';
  end if;

  -- 両デッキ行を保証（無ければ空デッキで作成）してロック
  insert into public.decks (user_id, deck_no) values (uid, 1) on conflict (user_id, deck_no) do nothing;
  insert into public.decks (user_id, deck_no) values (uid, p_other_deck_no) on conflict (user_id, deck_no) do nothing;
  select * into v_d1 from public.decks where user_id = uid and deck_no = 1 for update;
  select * into v_dn from public.decks where user_id = uid and deck_no = p_other_deck_no for update;

  -- スロットを入れ替え
  update public.decks
     set slot1_card_id = v_dn.slot1_card_id,
         slot2_card_id = v_dn.slot2_card_id,
         slot3_card_id = v_dn.slot3_card_id
   where user_id = uid and deck_no = 1;
  update public.decks
     set slot1_card_id = v_d1.slot1_card_id,
         slot2_card_id = v_d1.slot2_card_id,
         slot3_card_id = v_d1.slot3_card_id
   where user_id = uid and deck_no = p_other_deck_no;

  -- メイン(デッキ1)を離れたカードの武気を返却（デッキ1以外に武気は残さない）
  v_reclaimed := public._chikarian_reclaim_nonmain_buki(uid);

  return jsonb_build_object(
    'main_deck_no',    1,
    'swapped_with',    p_other_deck_no,
    'buki_reclaimed',  v_reclaimed
  );
end;
$$;
revoke all on function public.swap_main_deck(integer) from public, anon;
grant execute on function public.swap_main_deck(integer) to authenticated;

-- ===== (5) 移行(1回)：既存ユーザの非メイン武気をプールへ返却（超過許容・冪等） =====
do $$
declare r record;
begin
  for r in select id from public.profiles loop
    perform public._chikarian_reclaim_nonmain_buki(r.id);
  end loop;
end $$;

-- ============================================================
-- 確認クエリ（任意）：デッキ1以外に武気が残っていないこと（0行が正常）
--   select c.id, c.card_key, c.loaded_buki
--   from public.cards c
--   where coalesce(c.loaded_buki,0) > 0
--     and not exists (select 1 from public.decks d
--                     where d.user_id = c.user_id and d.deck_no = 1
--                       and c.id in (d.slot1_card_id,d.slot2_card_id,d.slot3_card_id));
-- ============================================================
