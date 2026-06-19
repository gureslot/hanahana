-- ============================================================
-- Chikarian migration 0020: ミッション (claim_mission) + mission_master + ヘルパ
-- canon: mission-spec-2026-06-11, balance §4/§6/§10/§12, supabase-spec §1(table10)/§2
-- 規約は 0012 に準拠。missions テーブルは 0001 作成済みの前提。
-- 進捗は「方式A」: 導出可能なものは claim 時に算出、カウンタ系（★強化/錬成/週採取）のみ
-- _chikarian_mission_bump で missions.progress に積む（0021 で do_kyoka/do_skill_rensei に hook）。
--
-- period_start: daily=JST当日 / weekly=JST週初(月) / achievement=固定(1970-01-01)。
-- 全達成ボーナスは「同カテゴリの非ボーナスを全て claim 済み」で成立。
-- 数値・報酬は全て仮（mission-spec）。報酬 jsonb キー: medal/chikarium/buki/c_blue/c_red/c_rainbow/hoshou。
-- ============================================================

-- JST当日
create or replace function public._chikarian_jst_today()
returns date language sql stable as $$
  select (now() at time zone 'Asia/Tokyo')::date;
$$;

-- カードの素の総合戦力（発動前・三すくみ/スキルなし）。deck_power 判定用。
create or replace function public._chikarian_card_sopower(
  p_card_key text, p_lv integer, p_star integer, p_quality text, p_loaded numeric
) returns numeric
language plpgsql immutable as $$
declare
  v_rare text; v_base numeric; v_cap integer; v_rL numeric; v_lv integer; v_atk integer;
begin
  if p_card_key is null then return 0; end if;
  v_rare := public._chikarian_rarity(p_card_key);
  v_lv := coalesce(p_lv, 1);
  if v_rare = 'sp' then
    v_base := case when p_card_key like '%dragon%' then 2260
                   when p_card_key like '%girl%'   then 2160
                   when p_card_key like '%houou%'  then 2060
                   else 2160 end;
    v_cap := 50; v_rL := 2.0 / (v_cap - 1);
    return v_base * (1 + (least(v_lv, v_cap) - 1) * v_rL) * (1 + 0.15 * coalesce(p_star,0));
  end if;
  case v_rare
    when 'n'   then v_base := 80;  v_cap := 30;
    when 'r'   then v_base := 200; v_cap := 40;
    when 'sr'  then v_base := 360; v_cap := 50;
    when 'ssr' then v_base := 560; v_cap := 60;
    else return 0;
  end case;
  v_rL  := 2.0 / (v_cap - 1);
  v_atk := case p_quality when 'crude' then 7 when 'refined' then 15 when 'enchanted' then 33 when 'holy' then 73 else 0 end;
  return coalesce(p_loaded,0) * v_atk
       + v_base * (1 + (least(v_lv, v_cap) - 1) * v_rL) * (1 + 0.15 * coalesce(p_star,0));
end; $$;

-- mission_master（定義）
create table if not exists public.mission_master (
  mission_key    text primary key,
  category       text not null check (category in ('daily','weekly','achievement')),
  tier           integer not null default 0,
  title          text not null,
  condition_type text not null,
  threshold      numeric not null,
  reward         jsonb not null
);
alter table public.mission_master enable row level security;
drop policy if exists mission_master_select_all on public.mission_master;
create policy mission_master_select_all on public.mission_master
  for select to authenticated using (true);

insert into public.mission_master (mission_key, category, tier, title, condition_type, threshold, reward) values
  -- デイリー（§2）
  ('d_saishu',  'daily', 0, '採取する',        'saishu_today',          100, '{"c_blue":5,"chikarium":30}'),
  ('d_boss',    'daily', 0, 'ボス挑戦',        'boss_attempt_today',    1,   '{"c_blue":5,"medal":2000}'),
  ('d_tansaku', 'daily', 0, '探索/放置 回収',  'tansaku_collect_today', 1,   '{"c_blue":4,"medal":1500}'),
  ('d_gacha',   'daily', 0, 'ガチャ',          'gacha_today',           1,   '{"c_blue":3}'),
  ('d_kyoka',   'daily', 0, '★強化',          'cnt_kyoka',             1,   '{"c_blue":3,"medal":1000}'),
  ('d_all',     'daily', 0, 'デイリー全達成',  'all_daily',             5,   '{"c_blue":10,"c_red":1,"medal":3500}'),
  -- ウィークリー（§3）
  ('w_boss',    'weekly', 0, 'ボス討伐',       'boss_win_week',         10,  '{"c_red":6,"medal":10000}'),
  ('w_saishu',  'weekly', 0, '採取累計',       'cnt_saishu_week',       5000,'{"c_red":5,"buki":800}'),
  ('w_kyoka',   'weekly', 0, 'カード★強化',   'cnt_kyoka',             10,  '{"c_red":5,"medal":8000}'),
  ('w_rensei',  'weekly', 0, 'スキル錬成',     'cnt_rensei',            3,   '{"c_red":4,"c_blue":20}'),
  ('w_all',     'weekly', 0, 'ウィークリー全達成','all_weekly',          4,   '{"c_red":10,"c_rainbow":1,"medal":12000}'),
  -- 達成（§4・各段別キー）
  ('a_clear_1', 'achievement', 1, '1面クリア', 'cleared_stage', 1, '{"c_rainbow":2,"medal":20000,"buki":1000}'),
  ('a_clear_2', 'achievement', 2, '2面クリア', 'cleared_stage', 2, '{"c_rainbow":2,"medal":20000,"buki":1000}'),
  ('a_clear_3', 'achievement', 3, '3面クリア', 'cleared_stage', 3, '{"c_rainbow":2,"medal":20000,"buki":1000}'),
  ('a_clear_4', 'achievement', 4, '4面クリア', 'cleared_stage', 4, '{"c_rainbow":2,"medal":20000,"buki":1000}'),
  ('a_clear_5', 'achievement', 5, '5面クリア', 'cleared_stage', 5, '{"c_rainbow":2,"medal":20000,"buki":1000}'),
  ('a_clear_6', 'achievement', 6, '6面クリア', 'cleared_stage', 6, '{"c_rainbow":2,"medal":20000,"buki":1000}'),
  ('a_clear_7', 'achievement', 7, '7面クリア', 'cleared_stage', 7, '{"c_rainbow":2,"medal":20000,"buki":1000}'),
  ('a_clear_8', 'achievement', 8, '8面クリア', 'cleared_stage', 8, '{"c_rainbow":2,"medal":20000,"buki":1000}'),
  ('a_zukan_10','achievement', 1, '図鑑10種',  'zukan_count', 10, '{"c_rainbow":3,"medal":25000}'),
  ('a_zukan_20','achievement', 2, '図鑑20種',  'zukan_count', 20, '{"c_rainbow":3,"medal":25000}'),
  ('a_zukan_30','achievement', 3, '図鑑30種',  'zukan_count', 30, '{"c_rainbow":3,"medal":25000}'),
  ('a_zukan_41','achievement', 4, '図鑑41種',  'zukan_count', 41, '{"c_rainbow":3,"medal":25000}'),
  ('a_power_20000','achievement', 1, 'デッキ戦力2万', 'deck_power', 20000, '{"c_rainbow":2,"c_red":10}'),
  ('a_power_50000','achievement', 2, 'デッキ戦力5万', 'deck_power', 50000, '{"c_rainbow":2,"c_red":10}'),
  ('a_power_90000','achievement', 3, 'デッキ戦力9万', 'deck_power', 90000, '{"c_rainbow":2,"c_red":10}'),
  ('a_skill_5', 'achievement', 1, 'スキルLv5',  'max_skill_lv', 5,  '{"c_rainbow":1,"c_red":10}'),
  ('a_skill_10','achievement', 2, 'スキルLv10', 'max_skill_lv', 10, '{"c_rainbow":1,"c_red":10}'),
  ('a_skill_20','achievement', 3, 'スキルLv20', 'max_skill_lv', 20, '{"c_rainbow":1,"c_red":10}'),
  ('a_kajiya_2','achievement', 1, '鍛冶屋Lv2',  'kajiya_lv', 2, '{"c_rainbow":2,"medal":25000}'),
  ('a_kajiya_3','achievement', 2, '鍛冶屋Lv3',  'kajiya_lv', 3, '{"c_rainbow":2,"medal":25000}'),
  ('a_kajiya_4','achievement', 3, '鍛冶屋Lv4',  'kajiya_lv', 4, '{"c_rainbow":2,"medal":25000}')
on conflict (mission_key) do nothing;

-- カウンタ加算（内部専用）。p_amount: 採取は獲得チカリウム、★強化/錬成は1。
create or replace function public._chikarian_mission_bump(p_uid uuid, p_action text, p_amount numeric default 1)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_ct text; m record; v_ps date;
begin
  v_ct := case p_action
    when 'kyoka'  then 'cnt_kyoka'
    when 'rensei' then 'cnt_rensei'
    when 'saishu' then 'cnt_saishu_week'
    else null end;
  if v_ct is null then return; end if;

  for m in select mission_key, category from public.mission_master where condition_type = v_ct loop
    v_ps := case m.category
      when 'daily'  then public._chikarian_jst_today()
      when 'weekly' then date_trunc('week', (now() at time zone 'Asia/Tokyo'))::date
      else date '1970-01-01' end;
    insert into public.missions (user_id, mission_key, period_start, progress, claimed)
      values (p_uid, m.mission_key, v_ps, p_amount, false)
      on conflict (user_id, mission_key, period_start)
      do update set progress = missions.progress + excluded.progress;
  end loop;
end; $$;
revoke all on function public._chikarian_mission_bump(uuid, text, numeric) from public, anon, authenticated;

-- ミッション報酬を受け取る
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
    select case when boss_date = public._chikarian_jst_today() then coalesce(boss_count_today,0) else 0 end
      into v_progress from public.profiles where id = v_uid;
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
  elsif v_m.condition_type in ('cnt_kyoka','cnt_rensei','cnt_saishu_week') then
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
