-- ============================================================
-- Chikarian migration 0095: get_mission_progress（ミッション進捗をサーバ計算で返す・読み取り専用）
-- 土台: 0020 の claim_mission の進捗評価ロジックを「そのまま複製」した読み取り専用関数。
--
-- 背景: ミッション画面はクライアントで進捗を導出していたが、サーバ判定のミッション
--       （boss_win_week / deck_power / max_skill_lv）や、画面に未ロードのデータ依存
--       （tansaku_collect_today / zukan_count / kajiya_lv）は進捗が不明（null）になり、
--       未達でも「受取可」と緑表示→押すと NOT_COMPLETE で弾かれていた（report ④）。
--       本RPCで全ミッションの進捗をサーバ計算して返し、クライアントが正確な
--       「受取可／条件未達」を表示できるようにする（クライアントは表示のみ・サーバが正）。
--
-- 仕様:
--   ・返り値＝ jsonb オブジェクト {mission_key: {progress, threshold, claimed}, ...}（全 mission_master 分）。
--   ・period_start はカテゴリで決定（daily=JST当日 / weekly=JST週初(月) / achievement=1970-01-01）＝claim_mission と一致。
--   ・各 condition_type の進捗式は claim_mission（0020）と同一（テーブル・列・関数も同じ）。
--   ・cnt_kyoka/cnt_rensei/cnt_saishu_week は missions.progress（当期の蓄積カウンタ）を使用。
--   ・claimed は当期の missions 行から（無ければ false）。
--   ・更新は一切しない（SELECT のみ）。security definer・全クエリ user_id = auth.uid() で絞る。
--   ※ claim_mission 本体は不変（本関数は表示専用＝実際の受取判定は従来どおり claim_mission が行う）。
-- ============================================================

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
      select case when boss_date = public._chikarian_jst_today() then coalesce(boss_count_today,0) else 0 end
        into v_progress from public.profiles where id = v_uid;
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
    elsif mm.condition_type in ('cnt_kyoka','cnt_rensei','cnt_saishu_week') then
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
--   select public.get_mission_progress();
--   → {"d_saishu":{"progress":..,"threshold":100,"claimed":false}, "w_boss":{...}, ...} が返る
