-- =============================================================================
-- 0003 : claim_saishu(n) ＝ 採取（カメラ点滅→チカリウム）RPC
-- 出典: balance §8（PER_BLINK=10・DAILY_MAX=1000・0時リセット）/ spec §2,§4
-- 方針: A案＝日次上限のみで防御（+10刻み・nチェック・秒制限なし）。
--       行ロックで同時申告の二重付与を防止。
-- 実行: SQL Editor に貼って Run（create or replace で上書き・再実行可）。
-- 呼び方(クライアント): supabase.rpc('claim_saishu', { n: 5 })
-- =============================================================================

create or replace function public.claim_saishu(n integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid   uuid := auth.uid();
  today date := (now() at time zone 'Asia/Tokyo')::date;   -- JST当日
  PER_BLINK constant integer := 10;     -- balance §8
  DAILY_MAX constant integer := 1000;   -- balance §8
  prof          public.profiles;
  cur_today     integer;
  remaining     integer;
  grant_blinks  integer;
  granted       integer;
  new_chikarium bigint;
  new_today     integer;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;
  if n is null or n < 1 then
    raise exception 'invalid blink count';   -- 点滅0以下の申告は拒否
  end if;

  -- 行ロック（同時申告の二重付与防止）
  select * into prof from public.profiles where id = uid for update;
  if not found then
    raise exception 'profile not initialized';  -- ログイン後 initialize_profile 済み前提
  end if;

  -- 0時リセット（JST）: 保存日付 < 今日 ならカウント0から
  if prof.saishu_date < today then
    cur_today := 0;
  else
    cur_today := prof.saishu_today;
  end if;

  -- 付与量 = min(申告点滅, 残り枠) × 10（上限超過は自動clamp・overflow安全）
  remaining    := DAILY_MAX - cur_today;            -- 0..1000（常に10の倍数）
  grant_blinks := least(n, remaining / PER_BLINK);
  if grant_blinks < 0 then grant_blinks := 0; end if;
  granted      := grant_blinks * PER_BLINK;

  new_chikarium := prof.chikarium + granted;
  new_today     := cur_today + granted;

  update public.profiles
     set chikarium    = new_chikarium,
         saishu_today = new_today,
         saishu_date  = today
   where id = uid;

  -- ミッション配線: 週ミッション「採取累計5000」等のカウンタへ実増分を加算（migration 0020）。
  -- granted は日次1000上限でクランプ後の実増分（要求値 n ではない）。0なら0加算で実害なし。
  -- _chikarian_mission_bump は security definer 専用＝本RPCが security definer のため呼べる。
  perform public._chikarian_mission_bump(uid, 'saishu', granted);

  return jsonb_build_object(
    'granted',         granted,            -- 今回付与（上限到達時は0）
    'chikarium',       new_chikarium,      -- 付与後の総チカリウム
    'saishu_today',    new_today,          -- 本日累計
    'daily_max',       DAILY_MAX,
    'daily_remaining', DAILY_MAX - new_today
  );
end;
$$;

revoke all on function public.claim_saishu(integer) from public;
grant execute on function public.claim_saishu(integer) to authenticated;
