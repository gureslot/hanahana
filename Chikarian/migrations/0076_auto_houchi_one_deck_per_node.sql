-- Chikarian migration 0076: 自動探索を「1ノード1デッキ」に作り替え（run_auto_houchi 再定義）＋ノード排他トリガ
-- 土台: 0071（auto_houchi）・0062（start_tansaku／※本体は触らない）・0001（tansaku_states）。
--
-- 背景・確定（2026-06-25・ユーザー B 選択）:
--   ・探索は「1ノード=1デッキ」が正。手動 start_tansaku は実質クライアントが1ノード1デッキを担保していたが、
--     自動 run_auto_houchi（0071）だけが「全空きデッキを解放最上段の同一ノードへ一括派遣」していて矛盾していた。
--   ・修正方針: 自動探索は空きデッキを「解放最上段から1つずつ "別ノード" へ・占有ノードは回避」して散らす。
--   ・最新ノード一択でゲームが単調になるのを避ける狙い（ユーザー意図）。canon-06 §3-3 は本migrationに合わせて改訂が要る
--     （旧「最上段の通常ノードへ一括派遣・×デッキ数表示」→「1デッキずつ別ノードへ・最上段から順に」）。
--
-- 変更点:
--   (1) run_auto_houchi(): 配置ロジックを「1ユーザー=1ノード算出→全デッキ」から
--       「空きデッキ(deck_no昇順) と 解放済み通常未占有ノード(step降順) を同順位で対応＝1デッキ1ノード・最上段から」へ。
--       ・対象ノード=解放済みの通常段（面1-3=step1-9 / 面5-6=step13-18・特設4/7/8除く・gate解放 step<=gate+1）のうち "未占有" のもの。
--       ・空きデッキ数 > 空きノード数 のときは溢れたデッキは派遣されない（重ねない）。早期はノードが少ないため派遣数も少ない（仕様）。
--       ・eligibility（auto_houchi_enabled＋アイドル閾値）・advisory lock・カード占有ロック・戻り値・revoke は 0071 と同一。
--   (2) tansaku_states に BEFORE INSERT OR UPDATE トリガ: 同一 (user_id, area, depth) に別 deck_no を置けない（NODE_OCCUPIED）。
--       手動・自動どちらの経路でも1ノード1デッキをサーバで担保（start_tansaku 本体は再定義しない＝面4/7/8ゲートのリスク回避）。
--       ※既存の重なり行（旧0071で積まれた行）は既存行なので発火対象外＝そのまま残り、collect_tansaku（回収）で消える。
--         今後の派遣は (1) が散らす＋(2) が重なりを拒否するので、新たな積み重ねは起きない。
--
-- 手動適用（Supabase SQL Editor）: 0075 の後に1回実行 → schema_migrations に 0076 を登録。
-- 適用後の挙動: 自動探索が複数デッキを別々のノード（最上段から）に配置。手動でノードが埋まっていればそこは避ける。

-- =============================================================================
-- (1) run_auto_houchi: 1デッキ1ノード・最上段から散らす
-- =============================================================================
create or replace function public.run_auto_houchi()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_dispatched integer := 0;
begin
  -- 多重実行防止（cron が重なっても二重に走らせない）
  if not pg_try_advisory_xact_lock(hashtext('chikarian_auto_houchi')) then
    return 0;
  end if;

  with eligible as (
    select
      p.id                                                               as user_id,
      least(6, 2 + floor(coalesce(p.cleared_stage, 0) / 2.0)::int)       as max_decks,
      coalesce(p.cleared_stage, 0) * 3 + coalesce(p.boss_round_role, 0)  as gate
    from public.profiles p
    where p.auto_houchi_enabled = true
      and p.last_active_at + make_interval(mins => p.auto_houchi_idle_min::int) <= now()
  ),
  -- 空きデッキ（カードあり・未探索・カード非ロック）を deck_no 昇順でランク付け
  idle_decks as (
    select
      e.user_id, d.deck_no,
      row_number() over (partition by e.user_id order by d.deck_no) as drk
    from eligible e
    join public.decks d
      on d.user_id = e.user_id and d.deck_no between 1 and e.max_decks
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
  -- 解放済みの通常ノード（面1-3=step1-9 / 面5-6=step13-18・特設4/7/8除く・gate解放）のうち
  -- "未占有" のものを step 降順でランク付け（＝最上段から順に埋める）
  avail_nodes as (
    select
      e.user_id, s.step,
      row_number() over (partition by e.user_id order by s.step desc) as nrk
    from eligible e
    cross join generate_series(1, 24) as s(step)
    where s.step <= e.gate + 1                                          -- gate 解放（step1 は常時開放）
      and (s.step between 1 and 9 or s.step between 13 and 18)          -- 通常段のみ（特設 面4=10-12 / 面7=19-21 / 面8=22-24 を除外）
      and not exists (                                                  -- 既に誰か（手動/自動）が居るノードは避ける
        select 1 from public.tansaku_states ts
        where ts.user_id = e.user_id
          and ((ts.area - 1) * 3 + ts.depth) = s.step
      )
  ),
  -- 空きデッキ(昇順) ←→ 未占有ノード(降順) を同順位で対応＝1デッキ1ノード・最上段から
  -- 空きデッキ数 > 空きノード数 のとき溢れたデッキは join に乗らず派遣されない（重ねない）
  pairs as (
    select
      i.user_id, i.deck_no,
      (((a.step - 1) / 3) + 1)::smallint     as area,
      ((((a.step - 1) % 3)) + 1)::smallint   as depth
    from idle_decks i
    join avail_nodes a
      on a.user_id = i.user_id and a.nrk = i.drk
  ),
  ins as (
    insert into public.tansaku_states (user_id, deck_no, area, depth, last_collect_at, is_houchi)
    select user_id, deck_no, area, depth, now(), true from pairs
    returning user_id, deck_no
  )
  select count(*) into v_dispatched from ins;

  -- 出発したデッキの編成カードを占有ロック（tansaku_deck_no = deck_no・§3-4）。
  -- 既ロック行は除外＝今回出発分のみロック。
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

-- =============================================================================
-- (2) tansaku_states ノード排他トリガ：同一 (user_id, area, depth) に別 deck_no を置けない
--     手動 start_tansaku・自動 run_auto_houchi の両経路で1ノード1デッキを担保。
--     既存の重なり行は発火対象外（回収で解消）。新規 INSERT/UPDATE のみ検査。
-- =============================================================================
create or replace function public._chikarian_tansaku_node_exclusive()
returns trigger
language plpgsql
as $$
begin
  if exists (
    select 1 from public.tansaku_states ts
    where ts.user_id = new.user_id
      and ts.area    = new.area
      and ts.depth   = new.depth
      and ts.deck_no <> new.deck_no
  ) then
    raise exception 'NODE_OCCUPIED';   -- このノードは別のデッキが探索中
  end if;
  return new;
end;
$$;

drop trigger if exists trg_tansaku_node_exclusive on public.tansaku_states;
create trigger trg_tansaku_node_exclusive
  before insert or update on public.tansaku_states
  for each row execute function public._chikarian_tansaku_node_exclusive();
