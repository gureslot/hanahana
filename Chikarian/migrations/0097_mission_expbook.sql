-- ============================================================
-- Chikarian migration 0097: デイリー/ウィークリーの★強化を「経験の書を使う」へ差し替え
--   canon-04 §2（★は中盤以降のレバー）/ canon-06 §6（ミッション）〔2026-06-28・ユーザー承認〕
--
--   背景: ★強化はデイリー1回・ウィークリー10回ともに序盤の進行と噛み合わない（同レア同★の素材＋
--         メダル＋失敗ありで安定して回せない）。育成は安く速く回す設計（canon-04 §8）に沿い、
--         毎日確実にこなせる「経験の書を使う」に差し替える。★強化はミッションから外す（戦力育成の
--         任意行為として残る）。
--
--   変更:
--     ① 新カウンタ cnt_expbook を導入。use_exp_book が実際に消費した時（v_used>0）に
--        _chikarian_mission_bump(uid,'expbook',1) で加算（★強化/錬成と同型）。
--        ※1回の use_exp_book 呼び出し＝1加算（冊数ではない）。デイリー・ウィークリー両方が
--          cnt_expbook なので、1回使うと両方の進捗が +1（bump は同 condition_type を全件加算）。
--     ② d_kyoka（デイリー★強化）→ condition_type=cnt_expbook・title「経験の書を使う」・threshold 1（報酬据置）。
--     ③ w_kyoka（ウィークリー カード★強化）→ condition_type=cnt_expbook・title「経験の書を使う」・threshold 10（報酬据置）。
--     ④ ★強化（do_kyoka が呼ぶ bump 'kyoka'＝cnt_kyoka）は対象ミッションが無くなり no-op になる（do_kyoka は無改変・害なし）。
--
--   実装方針（安全のため逐語ベース）: 各関数は適用済みの最新版を逐語複製し、cnt_expbook の1点のみ追加:
--     ・_chikarian_mission_bump（0020）：イベント表に 'expbook'→'cnt_expbook' を追加。
--     ・use_exp_book（最新0069）：本文は0069と同一＋カード更新直後に bump 1行。
--     ・claim_mission（最新0020）：cnt_系 IN リストに 'cnt_expbook' を追加（他は同一）。
--     ・get_mission_progress（0095）：cnt_系 IN リストに 'cnt_expbook' を追加（他は同一）。
--   前提: 0069・0020・0095 適用済み。実行: SQL Editor に貼って Run（全て create or replace / UPDATE＝冪等）。
--   クライアント変更不要（タイトルは mission_master・進捗は get_mission_progress＝サーバ）。
-- ============================================================

-- ① カウンタ加算（内部専用）に expbook を追加 ----------------------------------
create or replace function public._chikarian_mission_bump(p_uid uuid, p_action text, p_amount numeric default 1)
returns void
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_ct text; m record; v_ps date;
begin
  v_ct := case p_action
    when 'kyoka'   then 'cnt_kyoka'
    when 'rensei'  then 'cnt_rensei'
    when 'saishu'  then 'cnt_saishu_week'
    when 'expbook' then 'cnt_expbook'
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

-- ② use_exp_book（0069 逐語＋ミッション加算1行） -------------------------------
create or replace function public.use_exp_book(
  p_card_id uuid,
  p_size    text,
  p_count   integer default 1,
  p_allow_overshoot boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_card record;
  v_rare text; v_cap integer;
  v_per integer;
  v_bs integer; v_bm integer; v_bl integer; v_bxl integer; v_have integer;
  v_cur integer; v_max_exp integer; v_gap integer;
  v_full integer; v_remainder integer; v_needed integer;
  v_cap_books integer; v_used integer;
  v_would_overshoot boolean; v_waste integer;
  v_new_exp integer; v_new_lv integer;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_size not in ('s','m','l','xl') then raise exception 'INVALID_SIZE'; end if;
  if p_count is null or p_count <= 0 then raise exception 'INVALID_COUNT'; end if;

  select * into v_card from public.cards where id = p_card_id and user_id = v_uid for update;
  if not found then raise exception 'CARD_NOT_FOUND'; end if;

  v_per  := case p_size when 's' then 10 when 'm' then 50 when 'l' then 200 when 'xl' then 1000 end;
  v_rare := public._chikarian_rarity(v_card.card_key);
  v_cap  := case v_rare when 'n' then 30 when 'r' then 40 when 'sr' then 50 when 'ssr' then 60 when 'sp' then 50 else 60 end;

  v_cur     := coalesce(v_card.exp, 0);
  v_max_exp := 10 * v_cap * (v_cap - 1);                 -- Lv=cap（最大）の累積EXP
  if v_cur >= v_max_exp then raise exception 'ALREADY_MAX_LEVEL'; end if;

  v_gap       := v_max_exp - v_cur;
  v_full      := floor(v_gap::numeric / v_per)::int;     -- 最大を超えずに入る冊数（無駄ゼロ）
  v_remainder := v_gap - v_full * v_per;                 -- >0 なら最後の1冊は超過
  v_needed    := v_full + (case when v_remainder > 0 then 1 else 0 end);  -- 最大到達に要る最小冊数
  v_waste     := case when v_remainder > 0 then v_per - v_remainder else 0 end;  -- 超過1冊で捨てるEXP

  -- 所持取得（行ロック）
  select exp_book_s, exp_book_m, exp_book_l, exp_book_xl
    into v_bs, v_bm, v_bl, v_bxl
    from public.profiles where id = v_uid for update;
  v_have := case p_size when 's' then v_bs when 'm' then v_bm when 'l' then v_bl else v_bxl end;

  -- 消費上限：既定=v_full（無駄ゼロ）／許可時=v_needed（最大到達）。要求・所持でさらに頭打ち。
  v_cap_books := case when p_allow_overshoot then v_needed else v_full end;
  v_used := least(p_count, v_cap_books, coalesce(v_have, 0));

  -- 超過確認フラグ：許可なし＆端数あり＆要求が無駄ゼロ枠を超える（＝最大到達には超過1冊が必要）
  v_would_overshoot := (not p_allow_overshoot) and (v_remainder > 0) and (p_count > v_full);

  -- 消費（v_used 冊のみ。v_used=0 のときは消費なし＝would_overshoot をクライアントが確認）
  if v_used > 0 then
    update public.profiles set
      exp_book_s  = exp_book_s  - (case when p_size = 's'  then v_used else 0 end),
      exp_book_m  = exp_book_m  - (case when p_size = 'm'  then v_used else 0 end),
      exp_book_l  = exp_book_l  - (case when p_size = 'l'  then v_used else 0 end),
      exp_book_xl = exp_book_xl - (case when p_size = 'xl' then v_used else 0 end)
    where id = v_uid;
  end if;

  v_new_exp := least(v_cur + v_used * v_per, v_max_exp);  -- 最大でクランプ
  v_new_lv  := public._chikarian_lv_from_exp(v_new_exp, v_cap);
  update public.cards set exp = v_new_exp, lv = v_new_lv where id = p_card_id;

  -- ミッション加算（経験の書を使う・1回）：実際に消費した時のみ（0097）
  if v_used > 0 then perform public._chikarian_mission_bump(v_uid, 'expbook', 1); end if;

  return jsonb_build_object(
    'card_id',         p_card_id,
    'size',            p_size,
    'count_requested', p_count,
    'count_used',      v_used,
    'count_refunded',  p_count - v_used,        -- 未消費（無駄ゼロ枠を超えた要求分）
    'allow_overshoot', p_allow_overshoot,
    'would_overshoot', v_would_overshoot,       -- true=最大到達に超過1冊が必要（確認を出す）
    'overshoot_waste', v_waste,                 -- 超過1冊で捨てるEXP
    'gap_remaining',   v_max_exp - v_new_exp,   -- 消費後・最大までの残りEXP
    'exp_added',       v_used * v_per,
    'new_exp',         v_new_exp,
    'old_lv',          v_card.lv,
    'new_lv',          v_new_lv,
    'maxed',           (v_new_lv >= v_cap),
    'book_remaining',  coalesce(v_have, 0) - v_used
  );
end;
$$;
revoke all on function public.use_exp_book(uuid, text, integer, boolean) from public, anon;
grant execute on function public.use_exp_book(uuid, text, integer, boolean) to authenticated;

-- ③ claim_mission（0020 逐語＋cnt_系に cnt_expbook 追加） ----------------------
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

-- ④ get_mission_progress（0095 逐語＋cnt_系に cnt_expbook 追加） ----------------
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

-- ⑤ ミッション定義の差し替え（report・★強化→経験の書／報酬は据置＝UPDATEで触らない） --------
update public.mission_master
   set condition_type = 'cnt_expbook', title = '経験の書を使う', threshold = 1
 where mission_key = 'd_kyoka';

update public.mission_master
   set condition_type = 'cnt_expbook', title = '経験の書を使う', threshold = 10
 where mission_key = 'w_kyoka';

-- 確認用（任意・適用後）:
--   select mission_key, title, condition_type, threshold, reward
--     from public.mission_master where mission_key in ('d_kyoka','w_kyoka');
--   -- 経験の書を1回使う → select public.get_mission_progress(); で d_kyoka/w_kyoka の progress が +1
