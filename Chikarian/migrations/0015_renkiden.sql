-- ============================================================
-- Chikarian migration 0015: 練気殿 (renkiden) — invest / collect / instant / upgrade
-- canon: balance-chikarian-2026-06-12 §11, supabase-spec §1(table6)/§2
-- 規約は 0012 に準拠。renkiden テーブルは 0001 で作成済みの前提。
--
-- モデル:
--   レート       = 0.1 × Lv  (武気/秒)
--   時間単価     = 武気1 = メダル5     （fuel_medal を消費して練成）
--   即生産単価   = 武気1 = メダル15    （時間の3倍・fuel非経由）
--   保管上限 cap = 1000 + 1500×(Lv-1)
--   強化費       = 8,000 × 現Lv
--   離席中も last_calc_at からの経過で練成。上限到達中は fuel を消費しない（損失なし）。
--   Lv強化はレート/上限とも以後即適用（settle してから Lv+1）。
--
-- 前提: renkiden の PK/一意キー = user_id（"user1行"）。profiles.medal あり。
-- ============================================================

-- 武気/燃料に端数（0.1×Lv/秒）を保持するため numeric に揃える（整数型なら広げる・既に小数型ならスキップ）。
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='renkiden'
               and column_name='buki_stored' and data_type in ('integer','bigint','smallint')) then
    alter table public.renkiden alter column buki_stored type numeric;
  end if;
  if exists (select 1 from information_schema.columns
             where table_schema='public' and table_name='renkiden'
               and column_name='fuel_medal' and data_type in ('integer','bigint','smallint')) then
    alter table public.renkiden alter column fuel_medal type numeric;
  end if;
end $$;

-- 内部ヘルパ: 経過時間ぶんの練成を確定し last_calc_at を now() に進める。
-- 他の renkiden RPC / equip_buki から呼ぶ（クライアント直呼びは不可）。
create or replace function public._chikarian_renkiden_settle(p_uid uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r record;
  v_elapsed  numeric;     -- 経過秒
  v_rate     numeric;     -- 武気/秒
  v_cap      numeric;
  v_by_time  numeric;
  v_by_fuel  numeric;
  v_headroom numeric;
  v_add      numeric;
begin
  -- 行が無ければ初期化
  insert into public.renkiden (user_id, lv, buki_stored, fuel_medal, last_calc_at)
    values (p_uid, 1, 0, 0, now())
    on conflict (user_id) do nothing;

  select * into r from public.renkiden where user_id = p_uid for update;

  v_elapsed  := greatest(0, extract(epoch from (now() - r.last_calc_at)));
  v_rate     := 0.1 * r.lv;
  v_cap      := 1000 + 1500 * (r.lv - 1);
  v_by_time  := v_rate * v_elapsed;
  v_by_fuel  := r.fuel_medal / 5.0;                 -- 武気1=メダル5
  v_headroom := greatest(0, v_cap - r.buki_stored);
  v_add      := greatest(0, least(v_by_time, v_by_fuel, v_headroom));

  update public.renkiden
     set buki_stored  = r.buki_stored + v_add,
         fuel_medal   = r.fuel_medal - (v_add * 5.0),
         last_calc_at = now()
   where user_id = p_uid;
end;
$$;
revoke all on function public._chikarian_renkiden_settle(uuid) from public, anon, authenticated;

-- collect: 現在値に更新して状態を返す（武気は renkiden.buki_stored のプールに溜まる）
create or replace function public.collect_renkiden()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_lv integer; v_buki numeric; v_fuel numeric; v_cap numeric;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  perform public._chikarian_renkiden_settle(v_uid);
  select lv, buki_stored, fuel_medal into v_lv, v_buki, v_fuel
    from public.renkiden where user_id = v_uid;
  v_cap := 1000 + 1500 * (v_lv - 1);
  return jsonb_build_object(
    'lv', v_lv, 'buki_stored', v_buki, 'fuel_medal', v_fuel,
    'cap', v_cap, 'rate_per_sec', 0.1 * v_lv
  );
end;
$$;
revoke all on function public.collect_renkiden() from public, anon;
grant execute on function public.collect_renkiden() to authenticated;

-- invest: メダルを fuel に投入（先に settle して旧 fuel ぶんを精算→新 fuel は now から）
create or replace function public.invest_renkiden(p_medal integer)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_medal_have bigint;
  v_lv integer; v_buki numeric; v_fuel numeric; v_cap numeric;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_medal is null or p_medal <= 0 then raise exception 'INVALID_AMOUNT'; end if;

  perform public._chikarian_renkiden_settle(v_uid);

  select medal into v_medal_have from public.profiles where id = v_uid for update;
  if v_medal_have < p_medal then raise exception 'INSUFFICIENT_MEDAL'; end if;

  update public.profiles set medal = medal - p_medal where id = v_uid;
  update public.renkiden set fuel_medal = fuel_medal + p_medal where user_id = v_uid;

  select lv, buki_stored, fuel_medal into v_lv, v_buki, v_fuel
    from public.renkiden where user_id = v_uid;
  v_cap := 1000 + 1500 * (v_lv - 1);
  return jsonb_build_object(
    'lv', v_lv, 'buki_stored', v_buki, 'fuel_medal', v_fuel, 'cap', v_cap,
    'medal_invested', p_medal, 'medal_remaining', v_medal_have - p_medal
  );
end;
$$;
revoke all on function public.invest_renkiden(integer) from public, anon;
grant execute on function public.invest_renkiden(integer) to authenticated;

-- instant: 即生産（武気1=メダル15・上限内のみ）
create or replace function public.instant_renkiden(p_n integer)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_lv integer; v_buki numeric; v_cap numeric;
  v_cost bigint; v_medal_have bigint;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_n is null or p_n <= 0 then raise exception 'INVALID_AMOUNT'; end if;

  perform public._chikarian_renkiden_settle(v_uid);

  select lv, buki_stored into v_lv, v_buki from public.renkiden where user_id = v_uid for update;
  v_cap := 1000 + 1500 * (v_lv - 1);
  if v_buki + p_n > v_cap then raise exception 'EXCEEDS_CAP'; end if;

  v_cost := 15::bigint * p_n;                       -- 武気1=メダル15
  select medal into v_medal_have from public.profiles where id = v_uid for update;
  if v_medal_have < v_cost then raise exception 'INSUFFICIENT_MEDAL'; end if;

  update public.profiles set medal = medal - v_cost where id = v_uid;
  update public.renkiden set buki_stored = buki_stored + p_n where user_id = v_uid;

  return jsonb_build_object(
    'lv', v_lv, 'buki_stored', v_buki + p_n, 'cap', v_cap,
    'produced', p_n, 'medal_spent', v_cost, 'medal_remaining', v_medal_have - v_cost
  );
end;
$$;
revoke all on function public.instant_renkiden(integer) from public, anon;
grant execute on function public.instant_renkiden(integer) to authenticated;

-- upgrade: Lv+1（強化費 8,000×現Lv・settle 後に昇格＝以後レート/上限が即上がる）
create or replace function public.upgrade_renkiden()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_lv integer; v_cost bigint; v_medal_have bigint;
  v_new_lv integer; v_buki numeric; v_cap numeric;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  perform public._chikarian_renkiden_settle(v_uid);

  select lv into v_lv from public.renkiden where user_id = v_uid for update;
  v_cost := 8000::bigint * v_lv;                    -- 8,000×現Lv

  select medal into v_medal_have from public.profiles where id = v_uid for update;
  if v_medal_have < v_cost then raise exception 'INSUFFICIENT_MEDAL'; end if;

  update public.profiles set medal = medal - v_cost where id = v_uid;
  update public.renkiden set lv = lv + 1 where user_id = v_uid;

  select lv, buki_stored into v_new_lv, v_buki from public.renkiden where user_id = v_uid;
  v_cap := 1000 + 1500 * (v_new_lv - 1);
  return jsonb_build_object(
    'new_lv', v_new_lv, 'cost', v_cost, 'cap', v_cap, 'rate_per_sec', 0.1 * v_new_lv,
    'buki_stored', v_buki, 'medal_remaining', v_medal_have - v_cost
  );
end;
$$;
revoke all on function public.upgrade_renkiden() from public, anon;
grant execute on function public.upgrade_renkiden() to authenticated;
