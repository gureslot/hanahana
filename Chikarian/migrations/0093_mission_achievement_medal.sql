-- ============================================================
-- Chikarian migration 0093: 達成ミッション メダル圧縮（序盤過剰の解消）
-- 土台: 0020 の mission_master（seed）。達成・ウィークリーのメダルは 0020 以降未変更
--       （0061 はデイリー＋w_all のみ／0037・0040 は報酬 jsonb を触らない＝raw確認済み）。
--
-- 背景: 達成（恒常・1回）のメダルが序盤に過大。1周目で達成メダル合計 ≈335,000
--       （a_clear 8面×20,000=160,000 ／ a_zukan 4種×25,000=100,000 ／ a_kajiya 3段×25,000=75,000）。
--       特に「図鑑10/20種」「鍛冶屋Lv2」は早期に容易＝報告の「序盤に数万メダル」の主因。
--
-- canon: canon-06 §6・canon-04 §7（デイリーは 0061 で 8,000→2,500 に圧縮済み。本変更は達成も
--        同方針＝早期を薄く・後半を厚く）。※canon-06 §6 / canon-04 §7 の達成メダル表は本ファイルの
--        値へ追従させる（canon 反映は保留中の 0089–0092 と同じ納品でまとめて更新）。
--
-- 変更点（reward jsonb をメダルのみ差し替え・非medalキー= c_rainbow / buki は温存・UPDATE冪等）:
--   a_clear  : 面1-3=3,000 / 面4-5=6,000 / 面6-8=10,000        合計 51,000（旧 160,000）
--   a_zukan  : 10種=2,000 / 20種=3,000 / 30種=5,000 / 41種=10,000  合計 20,000（旧 100,000）
--   a_kajiya : Lv2=3,000 / Lv3=5,000 / Lv4=8,000                合計 16,000（旧 75,000）
--   → 達成メダル合計 ≈87,000（旧 335,000）。
--
-- 据え置き（本ファイルでは変更しない）:
--   ・ウィークリー（w_boss 10,000・w_kyoka 8,000・w_all 12,000）＝週次の反復収入であり「序盤の一括過剰」ではない（canon 0061 方針を踏襲）。
--   ・a_power_* / a_skill_*（メダル無し）。
--   ・全クリスタル（c_blue/c_red/c_rainbow）・武気・恩寵石＝今回はメダルのみ調整（虹の供給調整は canon-03 §10 で別途）。
--
-- 注意: 既に claim 済みのミッションには遡及しない（claim は1回限り・本変更は今後の受取にのみ適用）。
-- ============================================================

-- a_clear（面クリア）：早期を薄く・後半を厚く（buki:1000・c_rainbow:2 は温存）
update public.mission_master set reward = '{"c_rainbow":2,"medal":3000,"buki":1000}'  where mission_key = 'a_clear_1';
update public.mission_master set reward = '{"c_rainbow":2,"medal":3000,"buki":1000}'  where mission_key = 'a_clear_2';
update public.mission_master set reward = '{"c_rainbow":2,"medal":3000,"buki":1000}'  where mission_key = 'a_clear_3';
update public.mission_master set reward = '{"c_rainbow":2,"medal":6000,"buki":1000}'  where mission_key = 'a_clear_4';
update public.mission_master set reward = '{"c_rainbow":2,"medal":6000,"buki":1000}'  where mission_key = 'a_clear_5';
update public.mission_master set reward = '{"c_rainbow":2,"medal":10000,"buki":1000}' where mission_key = 'a_clear_6';
update public.mission_master set reward = '{"c_rainbow":2,"medal":10000,"buki":1000}' where mission_key = 'a_clear_7';
update public.mission_master set reward = '{"c_rainbow":2,"medal":10000,"buki":1000}' where mission_key = 'a_clear_8';

-- a_zukan（図鑑収集）：10/20種は早期に容易＝薄く・41種コンプは厚め（c_rainbow:3 は温存）
update public.mission_master set reward = '{"c_rainbow":3,"medal":2000}'  where mission_key = 'a_zukan_10';
update public.mission_master set reward = '{"c_rainbow":3,"medal":3000}'  where mission_key = 'a_zukan_20';
update public.mission_master set reward = '{"c_rainbow":3,"medal":5000}'  where mission_key = 'a_zukan_30';
update public.mission_master set reward = '{"c_rainbow":3,"medal":10000}' where mission_key = 'a_zukan_41';

-- a_kajiya（装備の質の解放）：解放は cleared_stage ゲート＋メダル費あり＝報酬を圧縮（c_rainbow:2 は温存）
update public.mission_master set reward = '{"c_rainbow":2,"medal":3000}' where mission_key = 'a_kajiya_2';
update public.mission_master set reward = '{"c_rainbow":2,"medal":5000}' where mission_key = 'a_kajiya_3';
update public.mission_master set reward = '{"c_rainbow":2,"medal":8000}' where mission_key = 'a_kajiya_4';

-- 確認用（任意・適用後に SELECT で目視）:
--   select mission_key, reward from public.mission_master
--   where mission_key like 'a_clear_%' or mission_key like 'a_zukan_%' or mission_key like 'a_kajiya_%'
--   order by mission_key;
