-- ============================================================
-- Chikarian migration 0061: ミッション デイリーメダル圧縮 ＋ 週次恩寵石トリクル
-- 土台: 0020 の mission_master（INSERT は on conflict do nothing のため、変更は UPDATE で行う）。
-- canon: canon-06 §6・canon-04 §7（デイリー満了メダル ≈2,500・旧8,000は4.6倍過大）／canon-04 §2（恩寵石 週1目安）。
-- 変更点:
--   (1) デイリーのメダルのみ圧縮（計8,000→2,500）：d_boss 2000→600 / d_tansaku 1500→500 / d_kyoka 1000→400 / d_all 3500→1000。
--       ※ クリスタル(c_blue/c_red)・チカリウムは温存（満了で 青30/赤1/チカリウム30 は不変）。
--   (2) 週次恩寵石トリクル：w_all（ウィークリー全達成）に hoshou:1 を追加（claim_mission は 0020 で hoshou 対応済み）。
--   ※ ウィークリー/達成のメダル・全クリスタル・武気・他デイリーは据え置き（canon-07 §3「ウィークリー/達成は据置」）。
--   reward jsonb を「非medalキーを温存したまま」再設定（UPDATE・冪等）。
-- ============================================================

-- (1) デイリーメダル圧縮（合計 600+500+400+1000 = 2,500）。クリスタルは元の値を温存。
update public.mission_master set reward = '{"c_blue":5,"medal":600}'             where mission_key = 'd_boss';
update public.mission_master set reward = '{"c_blue":4,"medal":500}'             where mission_key = 'd_tansaku';
update public.mission_master set reward = '{"c_blue":3,"medal":400}'             where mission_key = 'd_kyoka';
update public.mission_master set reward = '{"c_blue":10,"c_red":1,"medal":1000}' where mission_key = 'd_all';

-- (2) 週次恩寵石トリクル（週1目安）：w_all に hoshou:1 を追加（メダル12,000・クリスタルは据え置き）。
update public.mission_master set reward = '{"c_red":10,"c_rainbow":1,"medal":12000,"hoshou":1}' where mission_key = 'w_all';
