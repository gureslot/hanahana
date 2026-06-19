-- =============================================================================
-- 0010 : boss_master テーブル（ボスの属性/武器/戦力）＋ 全21敵投入
-- 出典: boss-attr-sukumi-2026-06-14.md §3（属性/武器）/ balance §6-1（base_power・1周目）
-- 実行: SQL Editor に貼って Run（create if not exists / on conflict で冪等）。
--
-- 【方針（skill_master(0006) と同じ）】
--   * マスタ＝全 authenticated が SELECT 可・書込みポリシー無し（クライアント改竄不可）。
--   * do_boss_battle(0011) が boss_key で JOIN し、base_power×N周目＝敵戦力／attrs・weapons で三すくみ。
--
-- 【キー設計】
--   * boss_key = boss_{面1-8}_{a|b|boss}（21行）。周回(_r{N})は別行を持たず、
--     do_boss_battle 側で接尾辞 _r{N} を剥がして base_power×N で解決（属性/武器は周回でも同じ・§3）。
--   * attrs/weapons は text[]（1敵が複数属性/武器を持てる＝B方式乗算・§2）。空配列=その軸は中立。
--   * 内部キー: 花=hana / 葉=ha / 芯=shin、剣=ken / 盾=tate / 杖=tsue（§3 末尾）。
-- =============================================================================

create table if not exists public.boss_master (
  boss_key   text primary key,
  stage      smallint not null check (stage between 1 and 8),
  role       text     not null check (role in ('a','b','boss')),
  base_power numeric  not null,                 -- balance §6-1（1周目）
  attrs      text[]   not null default '{}',    -- hana/ha/shin（複数可・空=属性なし）
  weapons    text[]   not null default '{}'     -- ken/tate/tsue（複数可・空=武器なし）
);

alter table public.boss_master enable row level security;
drop policy if exists boss_master_select_all on public.boss_master;
create policy boss_master_select_all on public.boss_master
  for select to authenticated using (true);   -- 全員読取り可・書込みポリシー無し＝不可

insert into public.boss_master (boss_key, stage, role, base_power, attrs, weapons) values
  -- 1 古代樹海界（属性/武器なし＝全カード中立）
  ('boss_1_a',    1, 'a',     3000,  '{}',           '{}'),
  ('boss_1_b',    1, 'b',     5000,  '{}',           '{}'),
  ('boss_1_boss', 1, 'boss',  8000,  '{}',           '{}'),
  -- 2 黒曜山界
  ('boss_2_a',    2, 'a',    10000,  '{hana}',       '{ken}'),
  ('boss_2_b',    2, 'b',    15000,  '{hana}',       '{ken}'),
  ('boss_2_boss', 2, 'boss', 25000,  '{hana}',       '{ken,tate}'),
  -- 3 神域界
  ('boss_3_a',    3, 'a',    25000,  '{ha}',         '{tsue}'),
  ('boss_3_b',    3, 'b',    35000,  '{ha}',         '{tsue}'),
  ('boss_3_boss', 3, 'boss', 50000,  '{ha}',         '{tsue}'),
  -- 4 鋼殻要塞界
  ('boss_4_a',    4, 'a',    45000,  '{shin}',       '{tate}'),
  ('boss_4_b',    4, 'b',    60000,  '{shin}',       '{tate}'),
  ('boss_4_boss', 4, 'boss', 80000,  '{shin}',       '{tate}'),
  -- 5 雷帝界
  ('boss_5_a',    5, 'a',    65000,  '{ha}',         '{ken}'),
  ('boss_5_b',    5, 'b',    80000,  '{shin}',       '{ken}'),
  ('boss_5_boss', 5, 'boss', 90000,  '{hana}',       '{ken}'),
  -- 6 群体界
  ('boss_6_a',    6, 'a',    75000,  '{hana}',       '{tate}'),
  ('boss_6_b',    6, 'b',    90000,  '{shin}',       '{ken}'),
  ('boss_6_boss', 6, 'boss',100000,  '{ha}',         '{tsue}'),
  -- 7 幻妖界
  ('boss_7_a',    7, 'a',    90000,  '{shin}',       '{tsue}'),
  ('boss_7_b',    7, 'b',   100000,  '{ha}',         '{tsue}'),
  ('boss_7_boss', 7, 'boss',110000,  '{hana}',       '{tsue}'),
  -- 8 終幕界（複数属性/武器＝乗算で相殺）
  ('boss_8_a',    8, 'a',   100000,  '{hana,shin}',  '{ken,tsue}'),
  ('boss_8_b',    8, 'b',   110000,  '{ha,shin}',    '{tate,tsue}'),
  ('boss_8_boss', 8, 'boss',120000,  '{hana,ha}',    '{ken,tate}')
on conflict (boss_key) do update set
  stage      = excluded.stage,
  role       = excluded.role,
  base_power = excluded.base_power,
  attrs      = excluded.attrs,
  weapons    = excluded.weapons;

-- =============================================================================
-- 件数チェック（任意）: select count(*) from public.boss_master;  -- → 21
-- =============================================================================
