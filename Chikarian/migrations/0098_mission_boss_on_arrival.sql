-- ============================================================
-- Chikarian migration 0098: デイリー「ボス挑戦」を出撃時点→到着時点の達成に変更
--   canon-06 §6（ミッション）／canon-06 §4（ボス時間制出撃）〔2026-09-06・ユーザー指示〕
--
--   背景: mission_master d_boss（condition_type='boss_attempt_today'）は
--         profiles.boss_count_today を読んでいた。これは start_boss_battle（＝出撃）が
--         1日3回の上限を消費するために加算するカウンタで、出発した瞬間に +1 される。
--         そのため「ボス挑戦」が到着前に達成扱いになっていた。
--
--   変更: boss_attempt_today の進捗評価を battle_logs の当日行数に差し替える。
--         battle_logs は do_boss_battle（＝到着時の戦闘解決）が勝敗を問わず1戦1行 insert するため、
--         「到着した時点で達成」と一致する。boss_win_week（既に battle_logs 基準）と同型。
--
--   非変更: start_boss_battle は無改変（boss_count_today＝1日3回の上限管理は出撃時消費のまま）。
--           mission_master の d_boss 行（title/threshold/reward）も無改変。
--
--   実装方針（安全のため逐語ベース）: 適用済み最新版（0097）の claim_mission /
--     get_mission_progress を逐語複製し、boss_attempt_today の分岐1か所のみ差し替え。
--   前提: 0097 適用済み。実行: SQL Editor に貼って Run（create or replace＝冪等）。
--   クライアント変更不要（進捗はサーバの get_mission_progress が返す）。
-- ============================================================

-- ① claim_mission（0097 逐語＋boss_attempt_today の1分岐のみ差し替え） -----------
create or replace function public.claim_mission(p_mission_key text)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_uid uuid := auth.uid();
  v_m record;
  v_ps date;
  v_day_start timestamptz;
  v_week_start timestamptz;
  v_progress numeric := 0;
  v_progress_stored numeric;
  v_claimed boolean;
  v_reward jsonb;
  v_buki numeric;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select * into v_m from public.mission_master where mission_key = p_mission_key;
  if not found then raise exception 'MISSION_NOT_FOUND'; end if;

  if v_m.category = 'daily' then
    v_ps := public._chikarian_jst_today();
  elsif v_m.category = 'weekly' then
    v_ps := date_trunc('week', (now() at time zone 'Asia/Tokyo'))::date;
  else
    v_ps := date '1970-01-01';
  end if;
  v_day_start  := (public._chikarian_jst_today())::timestamp at time zone 'Asia/Tokyo';
  v_week_start := (date_trunc('week', (now() at time zone 'Asia/Tokyo'))::date)::timestamp at time zone 'Asia/Tokyo';

  -- 進捗行を確保（カウンタ保持・claimedフラグ）
  insert into public.missions (user_id, mission_key, period_start, progress, claimed)
    values (v_uid, p_mission_key, v_ps, 0, false)
    on conflict (user_id, mission_key, period_start) do nothing;
  select progress, claimed into v_progress_stored, v_claimed
    from public.missions where user_id = v_uid and mission_key = p_mission_key and period_start = v_ps for update;
  if v_claimed then raise exception 'ALREADY_CLAIMED'; end if;

  -- 進捗を評価
  if v_m.condition_type = 'saishu_today' then
    select case when saishu_date = public._chikarian_jst_today() then coalesce(saishu_today,0) else 0 end
      into v_progress from public.profiles where id = v_uid;
  elsif v_m.condition_type = 'boss_attempt_today' then
    -- 0098: 出撃（start_boss_battle で boss_count_today を消費）ではなく
    --       「到着＝戦闘解決」で達成。battle_logs は do_boss_battle が1戦1行を記録する。
    select count(*) into v_progress from public.battle_logs
      where user_id = v_uid and fought_at >= v_day_start;
  elsif v_m.condition_type = 'gacha_today' then
    select count(*) into v_progress from public.cards
      where user_id = v_uid and obtained_at >= v_day_start;
  elsif v_m.condition_type = 'tansaku_collect_today' then
    select count(*) into v_progress from public.tansaku_states
      where user_id = v_uid and last_collect_at >= v_day_start;
  elsif v_m.condition_type = 'boss_win_week' then
    select count(*) into v_progress from public.battle_logs
      where user_id = v_uid and win = true and fought_at >= v_week_start;
  elsif v_m.condition_type = 'cleared_stage' then
    select coalesce(cleared_stage,0) into v_progress from public.profiles where id = v_uid;
  elsif v_m.condition_type = 'zukan_count' then
    select count(*) into v_progress from public.zukan where user_id = v_uid;
  elsif v_m.condition_type = 'max_skill_lv' then
    select coalesce(max(cs.skill_lv),0) into v_progress
      from public.card_skills cs join public.cards c on c.id = cs.card_id
      where c.user_id = v_uid;
  elsif v_m.condition_type = 'kajiya_lv' then
    select coalesce(max(case quality when 'holy' then 4 when 'enchanted' then 3 when 'refined' then 2 else 1 end),1)
      into v_progress from public.kajiya_orders where user_id = v_uid and claimed = true;
  elsif v_m.condition_type = 'deck_power' then
    select coalesce(max(
        public._chikarian_card_sopower(c1.card_key,c1.lv,c1.star,c1.quality,c1.loaded_buki)
       +public._chikarian_card_sopower(c2.card_key,c2.lv,c2.star,c2.quality,c2.loaded_buki)
       +public._chikarian_card_sopower(c3.card_key,c3.lv,c3.star,c3.quality,c3.loaded_buki)
      ),0) into v_progress
      from public.decks d
      left join public.cards c1 on c1.id = d.slot1_card_id
      left join public.cards c2 on c2.id = d.slot2_card_id
      left join public.cards c3 on c3.id = d.slot3_card_id
      where d.user_id = v_uid;
  elsif v_m.condition_type = 'all_daily' then
    select count(*) into v_progress
      from public.missions m join public.mission_master mm on mm.mission_key = m.mission_key
      where m.user_id = v_uid and m.period_start = v_ps and m.claimed = true
        and mm.category = 'daily' and mm.condition_type <> 'all_daily';
  elsif v_m.condition_type = 'all_weekly' then
    select count(*) into v_progress
      from public.missions m join public.mission_master mm on mm.mission_key = m.mission_key
      where m.user_id = v_uid and m.period_start = v_ps and m.claimed = true
        and mm.category = 'weekly' and mm.condition_type <> 'all_weekly';
  elsif v_m.condition_type in ('cnt_kyoka','cnt_rensei','cnt_saishu_week','cnt_expbook') then
    v_progress := coalesce(v_progress_stored, 0);
  else
    raise exception 'UNKNOWN_CONDITION';
  end if;

  if v_progress < v_m.threshold then raise exception 'NOT_COMPLETE'; end if;

  -- 報酬付与
  v_reward := v_m.reward;
  update public.profiles set
      medal           = medal           + coalesce((v_reward->>'medal')::bigint, 0),
      chikarium       = chikarium       + coalesce((v_reward->>'chikarium')::bigint, 0),
      crystal_blue    = crystal_blue    + coalesce((v_reward->>'c_blue')::int, 0),
      crystal_red     = crystal_red     + coalesce((v_reward->>'c_red')::int, 0),
      crystal_rainbow = crystal_rainbow + coalesce((v_reward->>'c_rainbow')::int, 0),
      hoshou_stone    = hoshou_stone    + coalesce((v_reward->>'hoshou')::int, 0)
    where id = v_uid;

  v_buki := coalesce((v_reward->>'buki')::numeric, 0);
  if v_buki > 0 then
    perform public._chikarian_renkiden_settle(v_uid);   -- 行確保＆精算
    update public.renkiden set buki_stored = buki_stored + v_buki where user_id = v_uid;
  end if;

  update public.missions set claimed = true, progress = v_progress
    where user_id = v_uid and mission_key = p_mission_key and period_start = v_ps;

  return jsonb_build_object(
    'mission_key', p_mission_key, 'category', v_m.category,
    'progress', v_progress, 'threshold', v_m.threshold,
    'reward', v_reward
  );
end; $$;
revoke all on function public.claim_mission(text) from public, anon;
grant execute on function public.claim_mission(text) to authenticated;

-- ② get_mission_progress（0097 逐語＋boss_attempt_today の1分岐のみ差し替え） ----
create or replace function public.get_mission_progress()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_day_start  timestamptz;
  v_week_start timestamptz;
  v_result jsonb := '{}'::jsonb;
  mm record;
  v_ps date;
  v_progress numeric;
  v_stored numeric;
  v_claimed boolean;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  v_day_start  := (public._chikarian_jst_today())::timestamp at time zone 'Asia/Tokyo';
  v_week_start := (date_trunc('week', (now() at time zone 'Asia/Tokyo'))::date)::timestamp at time zone 'Asia/Tokyo';

  for mm in select mission_key, category, condition_type, threshold from public.mission_master loop
    v_ps := case mm.category
      when 'daily'  then public._chikarian_jst_today()
      when 'weekly' then date_trunc('week', (now() at time zone 'Asia/Tokyo'))::date
      else date '1970-01-01' end;

    -- 当期の missions 行（蓄積カウンタ・受取済）
    select progress, claimed into v_stored, v_claimed
      from public.missions
      where user_id = v_uid and mission_key = mm.mission_key and period_start = v_ps;
    v_stored  := coalesce(v_stored, 0);
    v_claimed := coalesce(v_claimed, false);

    -- 進捗評価（claim_mission 0020 と同一ロジック）
    v_progress := 0;
    if mm.condition_type = 'saishu_today' then
      select case when saishu_date = public._chikarian_jst_today() then coalesce(saishu_today,0) else 0 end
        into v_progress from public.profiles where id = v_uid;
    elsif mm.condition_type = 'boss_attempt_today' then
      -- 0098: 到着（戦闘解決）で達成。claim_mission と同一ロジック。
      select count(*) into v_progress from public.battle_logs
        where user_id = v_uid and fought_at >= v_day_start;
    elsif mm.condition_type = 'gacha_today' then
      select count(*) into v_progress from public.cards
        where user_id = v_uid and obtained_at >= v_day_start;
    elsif mm.condition_type = 'tansaku_collect_today' then
      select count(*) into v_progress from public.tansaku_states
        where user_id = v_uid and last_collect_at >= v_day_start;
    elsif mm.condition_type = 'boss_win_week' then
      select count(*) into v_progress from public.battle_logs
        where user_id = v_uid and win = true and fought_at >= v_week_start;
    elsif mm.condition_type = 'cleared_stage' then
      select coalesce(cleared_stage,0) into v_progress from public.profiles where id = v_uid;
    elsif mm.condition_type = 'zukan_count' then
      select count(*) into v_progress from public.zukan where user_id = v_uid;
    elsif mm.condition_type = 'max_skill_lv' then
      select coalesce(max(cs.skill_lv),0) into v_progress
        from public.card_skills cs join public.cards c on c.id = cs.card_id
        where c.user_id = v_uid;
    elsif mm.condition_type = 'kajiya_lv' then
      select coalesce(max(case quality when 'holy' then 4 when 'enchanted' then 3 when 'refined' then 2 else 1 end),1)
        into v_progress from public.kajiya_orders where user_id = v_uid and claimed = true;
    elsif mm.condition_type = 'deck_power' then
      select coalesce(max(
          public._chikarian_card_sopower(c1.card_key,c1.lv,c1.star,c1.quality,c1.loaded_buki)
         +public._chikarian_card_sopower(c2.card_key,c2.lv,c2.star,c2.quality,c2.loaded_buki)
         +public._chikarian_card_sopower(c3.card_key,c3.lv,c3.star,c3.quality,c3.loaded_buki)
        ),0) into v_progress
        from public.decks d
        left join public.cards c1 on c1.id = d.slot1_card_id
        left join public.cards c2 on c2.id = d.slot2_card_id
        left join public.cards c3 on c3.id = d.slot3_card_id
        where d.user_id = v_uid;
    elsif mm.condition_type = 'all_daily' then
      select count(*) into v_progress
        from public.missions m join public.mission_master m2 on m2.mission_key = m.mission_key
        where m.user_id = v_uid and m.period_start = v_ps and m.claimed = true
          and m2.category = 'daily' and m2.condition_type <> 'all_daily';
    elsif mm.condition_type = 'all_weekly' then
      select count(*) into v_progress
        from public.missions m join public.mission_master m2 on m2.mission_key = m.mission_key
        where m.user_id = v_uid and m.period_start = v_ps and m.claimed = true
          and m2.category = 'weekly' and m2.condition_type <> 'all_weekly';
    elsif mm.condition_type in ('cnt_kyoka','cnt_rensei','cnt_saishu_week','cnt_expbook') then
      v_progress := v_stored;
    else
      v_progress := 0;   -- 未知の条件は0（誤って受取可にしない）。claim_mission側は UNKNOWN_CONDITION で弾く。
    end if;

    v_result := v_result || jsonb_build_object(
      mm.mission_key,
      jsonb_build_object('progress', v_progress, 'threshold', mm.threshold, 'claimed', v_claimed)
    );
  end loop;

  return v_result;
end;
$$;
revoke all on function public.get_mission_progress() from public, anon;
grant execute on function public.get_mission_progress() to authenticated;

-- 確認用（任意・適用後）:
--   -- 出撃直後（未到着）は 0 のまま／到着後に 1 になる
--   select (public.get_mission_progress()->'d_boss');
--   select count(*) from public.battle_logs
--     where user_id = auth.uid()
--       and fought_at >= (public._chikarian_jst_today())::timestamp at time zone 'Asia/Tokyo';

insert into public.schema_migrations (version) values ('0098') on conflict do nothing;
