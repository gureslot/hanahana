-- ============================================================
-- Chikarian migration 0071: 放置自動探索（無操作トリガー）
--   canon-06 §3-3（2026-06-24 確定）。
--   放置＝探索の一モード。引き金＝「最後の操作から しきい値 経過」のサーバ時刻判定のみ
--     （= last_active_at + idle_min <= now）。アプリの開閉に非依存。
--     バックグラウンド移行は引き金にしない（切替が頻繁すぎるため）。
--   配置先＝解放最上段の通常ノード（特設 面4/7/8 を除く・最深 6-3=step18）。
--   回収は既存 collect_tansaku を流用（本migrationは「派遣」のみ追加・回収は不変）。
--
-- 内容：
--   1) profiles 列追加：auto_houchi_enabled / auto_houchi_idle_min(check 6値) / last_active_at
--   2) touch_active()               … last_active_at を now() に更新（ユーザーRPC）
--   3) set_auto_houchi(enabled,min) … 6値検証＋設定。enable 時 last_active_at=now()（ユーザーRPC）
--   4) run_auto_houchi()            … pg_cron 用の一括派遣（冪等・直叩き不可）
--   5) pg_cron 拡張の有効化＋ジョブ登録（'chikarian_auto_houchi' = '*/10 * * * *'）
--
-- 前提（適用済みであること）：
--   0001（profiles/decks/cards/tansaku_states）・0033（cards.tansaku_deck_no）
--   ・0042（cards.boss_deck_no）・0054（profiles.boss_round_role）・0064（start_tansaku）。
-- 安全性：列追加は if not exists／INSERT・UPDATE は冪等／cron は unschedule してから再登録。
--   一度の Run で完結（末尾で schema_migrations に self-register）。
-- ============================================================


-- 1) profiles 列追加 ----------------------------------------------------------
alter table public.profiles
  add column if not exists auto_houchi_enabled  boolean     not null default false;
alter table public.profiles
  add column if not exists auto_houchi_idle_min smallint    not null default 60;
alter table public.profiles
  add column if not exists last_active_at        timestamptz not null default now();

-- しきい値は 6 プリセットのみ許可（30分/1時間/3時間/6時間/12時間/24時間）。
-- 列追加直後は全行 = 60（既定）なので制約を満たす。
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.profiles'::regclass
      and conname  = 'profiles_auto_houchi_idle_min_chk'
  ) then
    alter table public.profiles
      add constraint profiles_auto_houchi_idle_min_chk
      check (auto_houchi_idle_min in (30, 60, 180, 360, 720, 1440));
  end if;
end $$;


-- 2) touch_active() : 最後の操作時刻を更新 -----------------------------------
--   クライアントが操作（タップ/キー）時に間引いて呼ぶ。これが「無操作」判定の基準。
create or replace function public.touch_active()
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  update public.profiles set last_active_at = now() where id = auth.uid();
$$;
revoke all on function public.touch_active() from public, anon;
grant execute on function public.touch_active() to authenticated;


-- 3) set_auto_houchi() : オン/オフ＋しきい値を設定 ---------------------------
--   p_idle_min は 6 プリセットのみ。有効化時は last_active_at を now() にリセット
--   （直後に即発動しないよう「今から」カウント開始）。
create or replace function public.set_auto_houchi(
  p_enabled  boolean,
  p_idle_min integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_min smallint;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_idle_min is null or p_idle_min not in (30, 60, 180, 360, 720, 1440) then
    raise exception 'INVALID_HOUCHI_IDLE';
  end if;
  v_min := p_idle_min::smallint;

  update public.profiles
     set auto_houchi_enabled  = coalesce(p_enabled, false),
         auto_houchi_idle_min = v_min,
         last_active_at = case when coalesce(p_enabled, false) then now() else last_active_at end
   where id = v_uid;

  return jsonb_build_object('enabled', coalesce(p_enabled, false), 'idle_min', v_min);
end;
$$;
revoke all on function public.set_auto_houchi(boolean, integer) from public, anon;
grant execute on function public.set_auto_houchi(boolean, integer) to authenticated;


-- 4) run_auto_houchi() : 一括派遣（pg_cron 専用・冪等・直叩き不可） ----------
--   対象＝auto_houchi_enabled かつ last_active_at + idle_min <= now のユーザー。
--   空きデッキ（カードあり・探索/ボス出撃に出ていない・占有ロックなし）を
--   解放最上段の通常ノード（特設 面4/7/8 除く・最深 step18=6-3）へ is_houchi=true で派遣。
--   既に出ているデッキ（tansaku_states 行あり）はスキップ＝冪等。戻り値＝今回派遣したデッキ数。
create or replace function public.run_auto_houchi()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_dispatched integer := 0;
begin
  -- 多重実行防止：cron が前回分と重なっても二重に走らせない（トランザクション内ロック）
  if not pg_try_advisory_xact_lock(hashtext('chikarian_auto_houchi')) then
    return 0;
  end if;

  with eligible as (
    select
      p.id                                                                as user_id,
      least(6, 2 + floor(coalesce(p.cleared_stage, 0) / 2.0)::int)        as max_decks,
      coalesce(p.cleared_stage, 0) * 3 + coalesce(p.boss_round_role, 0)   as gate
    from public.profiles p
    where p.auto_houchi_enabled = true
      and p.last_active_at + make_interval(mins => p.auto_houchi_idle_min::int) <= now()
  ),
  targeted as (
    -- 解放最上段 step=least(24,gate+1) から特設(面4=10-12 / 面7=19-21 / 面8=22-24)を除いた
    -- 最大 step（= 面1-3:1-9 / 面5-6:13-18・最深18）へ丸める。
    select
      e.user_id,
      e.max_decks,
      (case
         when least(24, e.gate + 1) <= 9  then least(24, e.gate + 1)
         when least(24, e.gate + 1) <= 12 then 9
         when least(24, e.gate + 1) <= 18 then least(24, e.gate + 1)
         else 18
       end) as step
    from eligible e
  ),
  targeted2 as (
    select
      t.user_id,
      t.max_decks,
      (((t.step - 1) / 3) + 1)::smallint     as area,
      ((((t.step - 1) % 3)) + 1)::smallint   as depth
    from targeted t
  ),
  idle_decks as (
    select t.user_id, d.deck_no, t.area, t.depth
    from targeted2 t
    join public.decks d
      on d.user_id = t.user_id
     and d.deck_no between 1 and t.max_decks
    where (d.slot1_card_id is not null or d.slot2_card_id is not null or d.slot3_card_id is not null)
      -- 既に探索/放置に出ているデッキは除外（冪等）
      and not exists (
        select 1 from public.tansaku_states ts
        where ts.user_id = d.user_id and ts.deck_no = d.deck_no
      )
      -- 編成カードが探索/ボスで占有ロック中のデッキは除外（§3-4）
      and not exists (
        select 1 from public.cards c
        where c.user_id = d.user_id
          and c.id in (d.slot1_card_id, d.slot2_card_id, d.slot3_card_id)
          and (c.tansaku_deck_no is not null or c.boss_deck_no is not null)
      )
  ),
  ins as (
    insert into public.tansaku_states (user_id, deck_no, area, depth, last_collect_at, is_houchi)
    select user_id, deck_no, area, depth, now(), true from idle_decks
    returning user_id, deck_no
  )
  select count(*) into v_dispatched from ins;

  -- 出発したデッキの編成カードを占有ロック（tansaku_deck_no = deck_no・§3-4）。
  -- 既ロック（tansaku_deck_no/boss_deck_no が非NULL）の行は除外＝今回出発分のみロック。
  update public.cards c
     set tansaku_deck_no = d.deck_no
    from public.decks d
    join public.tansaku_states ts
      on ts.user_id = d.user_id and ts.deck_no = d.deck_no and ts.is_houchi = true
   where c.user_id = d.user_id
     and c.id in (d.slot1_card_id, d.slot2_card_id, d.slot3_card_id)
     and c.tansaku_deck_no is null
     and c.boss_deck_no   is null;

  return v_dispatched;
end;
$$;
-- バッチ実行は cron 専用＝ユーザー/匿名からは実行不可（全ユーザー走査＝権限昇格を防ぐ）
revoke all on function public.run_auto_houchi() from public, anon, authenticated;


-- 5) pg_cron：拡張の有効化＋ジョブ登録 --------------------------------------
--   ※ Supabase で既に Database > Extensions から pg_cron を有効化済みなら下の
--     create extension は no-op。SQL から有効化できない権限構成の場合はダッシュボードで有効化のこと。
create extension if not exists pg_cron;

-- 既存ジョブがあれば外してから再登録（再実行しても重複しない）
do $$
begin
  if exists (select 1 from cron.job where jobname = 'chikarian_auto_houchi') then
    perform cron.unschedule('chikarian_auto_houchi');
  end if;
end $$;

-- 10分間隔で一括派遣（しきい値は各ユーザーの auto_houchi_idle_min で判定）
select cron.schedule(
  'chikarian_auto_houchi',
  '*/10 * * * *',
  $job$ select public.run_auto_houchi(); $job$
);


-- 適用後の台帳登録（self-register・1回のRunで完結／再実行安全） -----------------
insert into public.schema_migrations (version) values ('0071') on conflict do nothing;

-- 確認用（任意）:
--   select version from public.schema_migrations where version = '0071';
--   select jobname, schedule, active from cron.job where jobname = 'chikarian_auto_houchi';
--   select public.run_auto_houchi();   -- 手動で1回回して挙動確認（対象が無ければ 0）
