-- ============================================================
-- Chikarian migration 0083: 自動探索ゲートを「その周の進行」基準に修正（run_auto_houchi 再定義・土台=0076）
--
-- 背景・確定（ユーザー指示 2026-06-25）：
--   手動探索のゲートは 0082 で cleared_stage → boss_round_stage に直し、「2周目は面1浅から、ボス撃破で順次解放」になった。
--   しかし自動探索 run_auto_houchi（0076）は依然 gate = cleared_stage*3 + boss_round_role（1周目専用カウンタ）を使っており、
--   2周目に入った瞬間 cleared_stage=8 → gate=24 → 放置デッキが現周のフロンティアを飛び越えて面6深などへ送られていた
--   （＝手動側の順次解放を放置経由ですり抜ける）。手動と同じく boss_round_stage 基準に揃える。
--
-- 変更点（0076 の run_auto_houchi 本体に対し1行だけ）：
--   eligible CTE の gate を
--     coalesce(p.cleared_stage, 0) * 3 + coalesce(p.boss_round_role, 0)
--   から
--     coalesce(p.boss_round_stage, 0) * 3 + coalesce(p.boss_round_role, 0)
--   へ。
--   ・1周目：boss_round_stage は cleared_stage と常に一致＝挙動不変。
--   ・2周目以降：周頭 boss_round_stage=0 → gate=0 → step1(面1浅)だけが対象。ボス撃破で前進するほど散らせるノードが増える（手動と同じ歩調）。
--   ・max_decks は cleared_stage 基準のまま（デッキ数は恒常解放＝周回で減らない）。
--   ・配置ロジック（1デッキ1ノード・最上段から散らす）・占有回避・カードロック・戻り値・revoke は 0076 と一字一句同一。
--
-- 不変：ノード排他トリガ（_chikarian_tansaku_node_exclusive / trg_tansaku_node_exclusive）は 0076 のまま＝本migrationでは触らない。
--
-- 手動適用（Supabase SQL Editor）：0076 適用済みの後に1回実行 → schema_migrations に 0083 登録（末尾の insert で自動）。
-- 注：本migration適用前に旧ゲートで面5-6などへ送られた既存の放置デッキは、回収するまでそのまま残る（既存行は再配置しない）。
--     回収後の新規派遣からは現周フロンティア基準になる。
-- ============================================================

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
      p.id                                                                  as user_id,
      least(6, 2 + floor(coalesce(p.cleared_stage, 0) / 2.0)::int)          as max_decks,
      coalesce(p.boss_round_stage, 0) * 3 + coalesce(p.boss_round_role, 0)  as gate   -- ★その周の進行（0082と同基準）。1周目は cleared_stage と一致＝挙動不変
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

-- 台帳登録（既にあればスキップ）
insert into public.schema_migrations (version) values ('0083') on conflict (version) do nothing;
