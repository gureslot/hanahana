-- ============================================================
-- 0027 : SP3種 確定値改定（skill_master）— 竜気覚醒 → 4.0／哀慟の眼 → 0.25
--   canon-03 §2/§7・SP改定(2026-06-18・ユーザー承認済み／§11上書き禁止は本件のみ裁定解除)
--
--   竜気覚醒 sp_ryuki  (deck_sougou_mult・デッキ全体総合×base) ：1.90 → 4.0（2.50を経ず直接）
--   哀慟の眼 sp_aitou  (enemy_mult・敵の実戦闘力×base)        ：0.40 → 0.25（−75%）
--   発動率(activation_rate=0.05)・lv_upgradable=false・発動日離脱・コスト4 は不変。
--
--   do_boss_battle は skill_master.base_value を読むだけ＝本 UPDATE のみで反映（再定義不要）。
--   ※旧 0027_ryuki_250.sql（竜気2.50）は本ファイルで置換・破棄。
--   前提: 0006（skill_master 投入）適用済み。
-- ============================================================

-- 竜気覚醒：デッキ全体総合 ×4.0（dragon・5%・発動日離脱）
update public.skill_master
   set base_value = 4.0,
       notes      = 'デッキ全体総合×4.0（dragon・2026-06-18改定・旧2.50/1.90）'
 where skill_key = 'sp_ryuki';

-- 哀慟の眼：敵の実戦闘力 ×0.25（−75%）（girl・5%・発動日離脱）
update public.skill_master
   set base_value = 0.25,
       notes      = '敵の実戦闘力×0.25＝−75%（girl・2026-06-18改定・旧0.40）'
 where skill_key = 'sp_aitou';
