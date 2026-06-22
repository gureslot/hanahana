-- =============================================================================
-- 0048 : ボス戦力曲線を canon-05 §1（確定スケール・×M方式）へ更新
--   実装 0010 が旧「8面120,000系（×1.40前提）」のまま＝canon が「唯一の大型未実装」と明記。
--   本表（面1=3,200…面8=129,300／中A=面ボス×0.80・中B=面ボス×0.90）へ base_power を更新する。
--   ※更新は base_power のみ。属性/武器（attrs/weapons）は canon-05 §3＝0010 と一致＝不変。
--   ※スケール・形は確定。各面の細値は完全シミュで微調整余地（canon-05 §1 但し書き）。
--   ※敵戦力＝base_power×周回数 は do_boss_battle（0046）側で解決。本ファイルはデータ更新のみ・再実行可。
--   実行：SQL Editor に貼って Run。前提：0010 適用済み（boss_master 行が存在）。
-- =============================================================================
update public.boss_master b set base_power = v.bp
from (values
  ('boss_1_a',      2560), ('boss_1_b',      2880), ('boss_1_boss',     3200),
  ('boss_2_a',      4400), ('boss_2_b',      4950), ('boss_2_boss',     5500),
  ('boss_3_a',      8800), ('boss_3_b',      9900), ('boss_3_boss',    11000),
  ('boss_4_a',     18880), ('boss_4_b',     21240), ('boss_4_boss',    23600),
  ('boss_5_a',     37200), ('boss_5_b',     41850), ('boss_5_boss',    46500),
  ('boss_6_a',     54720), ('boss_6_b',     61560), ('boss_6_boss',    68400),
  ('boss_7_a',     77280), ('boss_7_b',     86940), ('boss_7_boss',    96600),
  ('boss_8_a',    103440), ('boss_8_b',    116370), ('boss_8_boss',   129300)
) as v(boss_key, bp)
where b.boss_key = v.boss_key;

-- 確認（任意）：更新後の値を面順に表示
-- select boss_key, stage, role, base_power from public.boss_master order by stage, role;
