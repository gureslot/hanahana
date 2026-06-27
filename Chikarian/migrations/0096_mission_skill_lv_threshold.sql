-- ============================================================
-- Chikarian migration 0096: スキルLvミッションの閾値を現実的な値へ（Lv5/10/20 → Lv3/5/7）
-- 土台: 0020 の mission_master（a_skill_5 / a_skill_10 / a_skill_20・condition_type=max_skill_lv）。
--       a_skill_* は 0020 以降未変更（0037/0040/0061/0093 はいずれも未対象＝確認済み）。
--
-- 背景: スキルLv10／Lv20 は到達が遠すぎて非現実的（report）。canon-03 §8 では主力スキル Lv5-10 が
--       約90日（クリア期間）の目安＝Lv20 は想定を大きく超過、Lv10 も終盤ぎりぎり。達成の節目報酬は
--       残しつつ、到達可能なラダー（Lv3／Lv5／Lv7）へ引き下げる。
--
-- 変更点（title と threshold のみ・mission_key/category/tier/condition_type/reward は温存・UPDATE冪等）:
--   a_skill_5  : 'スキルLv5'  / 5  → 'スキルLv3' / 3
--   a_skill_10 : 'スキルLv10' / 10 → 'スキルLv5' / 5
--   a_skill_20 : 'スキルLv20' / 20 → 'スキルLv7' / 7
--   報酬（虹1・赤10）は据え置き。
--
-- canon: canon-06 §6 / canon-04 §7 の達成ミッション表を本値へ追従（canon 反映は保留中の 0089–0092 と同じ納品でまとめて更新）。
-- 注意: 既に claim 済みは遡及しない（claim は1回限り・本変更は今後の判定/表示に適用）。
--       タイトルは mission_master から表示されるため、クライアント変更は不要（master 再取得で新タイトル反映）。
-- ============================================================

update public.mission_master set title = 'スキルLv3', threshold = 3 where mission_key = 'a_skill_5';
update public.mission_master set title = 'スキルLv5', threshold = 5 where mission_key = 'a_skill_10';
update public.mission_master set title = 'スキルLv7', threshold = 7 where mission_key = 'a_skill_20';

-- 確認用（任意・適用後）:
--   select mission_key, title, threshold, reward from public.mission_master
--   where mission_key in ('a_skill_5','a_skill_10','a_skill_20') order by tier;
