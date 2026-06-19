# Chikarian/ ファイルインベントリ

_自動生成（generated）。生成日: 2026-06-19 ／ 生成元: `find` + `git status`_

- 対象: `Chikarian/` 配下の全ファイル（隠しファイル・`.git/`・`node_modules/`・この `_filelist.md` を除外）
- 総ファイル数: **224**

## フォルダ別 件数サマリ

| フォルダ | 件数 | 主な内容 |
|---|---:|---|
| (ルート直下) | 54 | 仕様 .md / モック *-mockup.html / index.html / .js / .sql |
| dev/ | 1 | 開発用コンソール |
| images/ | 123 | カード絵・背景・ボタン・アイコン・マップ |
| migrations/ | 40 | Supabase スキーマ/RPC（連番 SQL） |
| sounds/ | 6 | BGM / 効果音 |

## ⚠ 未コミットファイル（git status）

コミット時点のワーキングツリー状態。記号: `??`=未追跡 / `M`=変更 / `D`=削除（インデックスから消えている）。

### ?? 未追跡（untracked・47 件）

- `_filelist.md`
- `auth-test-v2.html`
- `balance-chikarian-2026-06-10-0150.local.bak`
- `balance-gacha-rate-update-2026-06-13.md`
- `boss-attr-sukumi-2026-06-14.md`
- `boss-map-prompts-2026-06-09-1708.md`
- `cards-chikarian-2026-06-10-0150.local.bak`
- `chatgpt-naming-prompt.md`
- `chikarian-crystal-exchange.md`
- `chikarian-dev.html`
- `chikarian-skill-design-confirmed.md`
- `chikarian-skills-expected-value.md`
- `chikarian-skills-for-naming.md`
- `chikarian-skills-numbers.md`
- `chikarian-worldview.md`
- `design-updates-2026-06-13.md`
- `dev/`
- `hikitsugi-chikarian-2026-06-10-0150.local.bak`
- `images/exp_book_l.png`
- `images/exp_book_m.png`
- `images/exp_book_s.png`
- `images/exp_book_xl.png`
- `migrations/0001_init_schema.sql`
- `migrations/0002_initialize_profile.sql`
- `migrations/0003_claim_saishu.sql`
- `migrations/0004_do_gacha.sql`
- `migrations/0005_update_deck.sql`
- `migrations/0006_skill_master.sql`
- `migrations/0007_do_gacha_skills.sql`
- `migrations/0008_do_boss_battle.sql`
- `migrations/0009_use_exp_book.sql`
- `migrations/0010_boss_master.sql`
- `migrations/0011_do_boss_battle_sukumi.sql`
- `migrations/0012_do_kyoka.sql`
- `migrations/0013_do_skill_teni.sql`
- `migrations/0014_do_skill_rensei.sql`
- `migrations/0015_renkiden.sql`
- `migrations/0016_kajiya.sql`
- `migrations/0017_equip_buki.sql`
- `migrations/0018_tansaku_expbook.sql`
- `migrations/0019_card_exchange.sql`
- `migrations/0020_missions.sql`
- `migrations/0021_mission_hooks.sql`
- `migrations/0022_profiles_init.sql`
- `migrations/0023_set_card_lock.sql`
- `migrations/0024_fix_tansaku_depth.sql`
- `skill-db-spec-2026-06-14.md`

### M 変更（modified・1 件）

- `cards-chikarian-2026-06-10-0150.md`

### D 削除（deleted・12 件）

_旧配置のルート直下 .sql。`migrations/` へ移設され、ルート側が削除扱い（移設先は上の ?? に未追跡として存在）。_

- `0001_init_schema.sql`
- `0002_initialize_profile.sql`
- `0003_claim_saishu.sql`
- `0004_do_gacha.sql`
- `0005_update_deck.sql`
- `0006_skill_master.sql`
- `0007_do_gacha_skills.sql`
- `0008_do_boss_battle.sql`
- `0009_use_exp_book.sql`
- `0010_boss_master.sql`
- `0011_do_boss_battle_sukumi.sql`
- `0023_set_card_lock.sql`

## migrations/（連番 SQL・40件）

連番範囲: **0001〜0040**（欠番なし）。0001〜0024 は未追跡（`migrations/` へ移設直後）、0025〜0040 は追跡済み。

- `0001_init_schema.sql` — 16.1 KB
- `0002_initialize_profile.sql` — 3.3 KB
- `0003_claim_saishu.sql` — 3.3 KB
- `0004_do_gacha.sql` — 5.1 KB
- `0005_update_deck.sql` — 5.3 KB
- `0006_skill_master.sql` — 12.2 KB
- `0007_do_gacha_skills.sql` — 9.6 KB
- `0008_do_boss_battle.sql` — 19.0 KB
- `0009_use_exp_book.sql` — 4.1 KB
- `0010_boss_master.sql` — 4.2 KB
- `0011_do_boss_battle_sukumi.sql` — 18.6 KB
- `0012_do_kyoka.sql` — 4.8 KB
- `0013_do_skill_teni.sql` — 3.5 KB
- `0014_do_skill_rensei.sql` — 4.8 KB
- `0015_renkiden.sql` — 8.3 KB
- `0016_kajiya.sql` — 4.4 KB
- `0017_equip_buki.sql` — 5.1 KB
- `0018_tansaku_expbook.sql` — 9.0 KB
- `0019_card_exchange.sql` — 4.7 KB
- `0020_missions.sql` — 14.1 KB
- `0021_mission_hooks.sql` — 7.1 KB
- `0022_profiles_init.sql` — 1.6 KB
- `0023_set_card_lock.sql` — 1.4 KB
- `0024_fix_tansaku_depth.sql` — 6.2 KB
- `0025_do_kyoka_success_lv.sql` — 7.1 KB
- `0026_star_formula_010.sql` — 19.6 KB
- `0027_sp_skill_values.sql` — 1.4 KB
- `0028_sukumi_weapon_fix.sql` — 1.8 KB
- `0029_card_cap_1000.sql` — 5.4 KB
- `0030_exchange_rates.sql` — 5.5 KB
- `0031_gear_equip.sql` — 5.9 KB
- `0032_gear_qatk.sql` — 20.1 KB
- `0033_tansaku_lock.sql` — 8.2 KB
- `0034_tansaku_guard_assets.sql` — 14.7 KB
- `0035_tansaku_guard_deck_teni.sql` — 8.4 KB
- `0036_tansaku_guard_boss_start.sql` — 20.9 KB
- `0037_hoshou_supply.sql` — 17.8 KB
- `0038_boss_round.sql` — 20.1 KB
- `0039_sp_hontai_3200.sql` — 19.1 KB
- `0040_card_sopower_align.sql` — 3.6 KB

## sounds/（音源・6件＝BGM 1・SE 5）

- `bgm_home.mp3` — 3.28 MB
- `se_back.mp3` — 15.9 KB
- `se_card_flip.mp3` — 25.3 KB
- `se_enhance_fail.mp3` — 18.4 KB
- `se_enhance_success.mp3` — 37.7 KB
- `se_tap.mp3` — 28.7 KB

## images/（画像・123件）

内訳: カード絵 chara_ 41 / ボス boss_ 35（うち boss_map_ 8）/ ボタン btn_ 10 / アイコン ic_ 19 / 探索マップ tansaku_map_ 8 / 経験の書 exp_book_ 4 / その他 6。

### chara_*（カード絵・41種＝図鑑母数）

- `chara_dragon_sp.png` — 348.0 KB
- `chara_girl_sp.png` — 183.0 KB
- `chara_hibiscus_ha_ken_n.png` — 244.3 KB
- `chara_hibiscus_ha_ken_r.png` — 292.4 KB
- `chara_hibiscus_ha_ken_sr.png` — 378.7 KB
- `chara_hibiscus_ha_ken_ssr.png` — 535.1 KB
- `chara_hibiscus_ha_tate_n.png` — 263.2 KB
- `chara_hibiscus_ha_tate_r.png` — 310.7 KB
- `chara_hibiscus_ha_tate_sr.png` — 369.3 KB
- `chara_hibiscus_ha_tate_ssr.png` — 461.2 KB
- `chara_hibiscus_ha_tsue_n.png` — 243.8 KB
- `chara_hibiscus_ha_tsue_r.png` — 314.7 KB
- `chara_hibiscus_ha_tsue_sr.png` — 386.9 KB
- `chara_hibiscus_ha_tsue_ssr.png` — 435.1 KB
- `chara_hibiscus_hana_ken_n.png` — 298.7 KB
- `chara_hibiscus_hana_ken_r.png` — 251.9 KB
- `chara_hibiscus_hana_ken_sr.png` — 339.3 KB
- `chara_hibiscus_hana_ken_ssr.png` — 434.7 KB
- `chara_hibiscus_hana_tate_n.png` — 250.4 KB
- `chara_hibiscus_hana_tate_r.png` — 283.1 KB
- `chara_hibiscus_hana_tate_sr.png` — 369.9 KB
- `chara_hibiscus_hana_tate_ssr.png` — 394.3 KB
- `chara_hibiscus_hana_tsue_n.png` — 222.0 KB
- `chara_hibiscus_hana_tsue_r.png` — 266.8 KB
- `chara_hibiscus_hana_tsue_sr.png` — 369.7 KB
- `chara_hibiscus_hana_tsue_ssr.png` — 438.3 KB
- `chara_hibiscus_shin_ken_n.png` — 250.7 KB
- `chara_hibiscus_shin_ken_r.png` — 303.0 KB
- `chara_hibiscus_shin_ken_sr.png` — 354.1 KB
- `chara_hibiscus_shin_ken_ssr.png` — 433.8 KB
- `chara_hibiscus_shin_tate_n.png` — 270.7 KB
- `chara_hibiscus_shin_tate_r.png` — 292.6 KB
- `chara_hibiscus_shin_tate_sr.png` — 376.8 KB
- `chara_hibiscus_shin_tate_ssr.png` — 479.6 KB
- `chara_hibiscus_shin_tsue_n.png` — 270.3 KB
- `chara_hibiscus_shin_tsue_r.png` — 331.2 KB
- `chara_hibiscus_shin_tsue_sr.png` — 370.8 KB
- `chara_hibiscus_shin_tsue_ssr.png` — 439.7 KB
- `chara_houou_sp.png` — 351.3 KB
- `chara_meshibe_shin_tsue_sr.png` — 386.3 KB
- `chara_meshibe_shin_tsue_ssr.png` — 435.2 KB

### boss_*（ボス絵＋ボスマップ）

- `boss_1_a.png` — 436.4 KB
- `boss_1_b.png` — 400.5 KB
- `boss_1_boss.png` — 429.1 KB
- `boss_2_a.png` — 362.8 KB
- `boss_2_b.png` — 343.8 KB
- `boss_2_boss.png` — 495.9 KB
- `boss_3_a.png` — 401.3 KB
- `boss_3_b.png` — 380.5 KB
- `boss_3_boss.png` — 432.1 KB
- `boss_4_a.png` — 331.4 KB
- `boss_4_b.png` — 368.1 KB
- `boss_4_boss.png` — 333.6 KB
- `boss_5_a.png` — 375.2 KB
- `boss_5_b.png` — 397.4 KB
- `boss_5_boss.png` — 397.5 KB
- `boss_6_a.png` — 320.8 KB
- `boss_6_b.png` — 379.9 KB
- `boss_6_boss.png` — 403.5 KB
- `boss_7_a.png` — 351.9 KB
- `boss_7_b.png` — 421.9 KB
- `boss_7_boss.png` — 420.6 KB
- `boss_8_a.png` — 294.3 KB
- `boss_8_a_r2.png` — 311.5 KB
- `boss_8_b.png` — 350.1 KB
- `boss_8_b_r2.png` — 387.8 KB
- `boss_8_boss.png` — 366.8 KB
- `boss_8_boss_r2.png` — 368.5 KB
- `boss_map_1.png` — 247.2 KB
- `boss_map_2.png` — 262.0 KB
- `boss_map_3.png` — 280.2 KB
- `boss_map_4.png` — 259.3 KB
- `boss_map_5.png` — 276.8 KB
- `boss_map_6.png` — 321.7 KB
- `boss_map_7.png` — 258.1 KB
- `boss_map_8.png` — 247.8 KB

### btn_*（ホームボタン）

- `btn_boss.png` — 196.2 KB
- `btn_deck.png` — 288.7 KB
- `btn_gacha.png` — 307.4 KB
- `btn_houchi.png` — 229.8 KB
- `btn_kyoka.png` — 300.8 KB
- `btn_mission.png` — 249.1 KB
- `btn_saishu.png` — 325.6 KB
- `btn_saishu_gray.png` — 298.0 KB
- `btn_tansaku.png` — 311.1 KB
- `btn_tatemono.png` — 270.5 KB

### ic_*（アイコン）

- `ic_attr_ha.png` — 291.1 KB
- `ic_attr_hana.png` — 287.3 KB
- `ic_attr_shin.png` — 314.4 KB
- `ic_chikarium.png` — 539.5 KB
- `ic_chikarium_jewel.png` — 248.6 KB
- `ic_map_boss.png` — 391.0 KB
- `ic_map_subboss.png` — 131.6 KB
- `ic_medal.png` — 415.5 KB
- `ic_menu.png` — 89.0 KB
- `ic_mission.png` — 221.3 KB
- `ic_report.png` — 411.4 KB
- `ic_reward.png` — 227.6 KB
- `ic_settings.png` — 283.7 KB
- `ic_tatemono_kaji.png` — 366.1 KB
- `ic_tatemono_kenkyu.png` — 316.5 KB
- `ic_tatemono_renkiden.png` — 414.4 KB
- `ic_tatemono_shuren.png` — 380.9 KB
- `ic_tatemono_souko.png` — 414.6 KB
- `ic_zukan.png` — 323.7 KB

### tansaku_map_*（探索マップ）

- `tansaku_map_1.png` — 271.4 KB
- `tansaku_map_2.png` — 284.7 KB
- `tansaku_map_3.png` — 329.6 KB
- `tansaku_map_4.png` — 294.0 KB
- `tansaku_map_5.png` — 280.6 KB
- `tansaku_map_6.png` — 308.3 KB
- `tansaku_map_7.png` — 294.6 KB
- `tansaku_map_8.png` — 293.9 KB

### exp_book_*（経験の書）

- `exp_book_l.png` — 530.5 KB
- `exp_book_m.png` — 535.4 KB
- `exp_book_s.png` — 535.7 KB
- `exp_book_xl.png` — 529.1 KB

### その他画像（背景・カード裏・ロゴ・カカシ）

- `card_back.png` — 358.8 KB
- `gacha-bg.png` — 163.2 KB
- `home_bg.png` — 249.4 KB
- `kakashi.png` — 94.5 KB
- `logo_title.png` — 247.2 KB
- `title_bg.png` — 203.5 KB

## dev/

- `console.html` — 16.4 KB

## ルート直下ファイル

- `auth-test-v2.html` — 4.5 KB
- `balance-apply-spec-2026-06-11.md` — 7.7 KB
- `balance-chikarian-2026-06-09-2040.md` — 22.5 KB
- `balance-chikarian-2026-06-10-0150.local.bak` — 21.4 KB
- `balance-chikarian-2026-06-10-0150.md` — 21.8 KB
- `balance-chikarian-2026-06-10-1730.md` — 38.0 KB
- `balance-chikarian-2026-06-12.md` — 41.1 KB
- `balance-gacha-rate-update-2026-06-13.md` — 2.0 KB
- `boss-attr-sukumi-2026-06-14.md` — 6.1 KB
- `boss-map-prompts-2026-06-09-1708.md` — 13.3 KB
- `boss-mockup.html` — 27.5 KB
- `cards-chikarian-2026-06-10-0150.local.bak` — 4.2 KB
- `cards-chikarian-2026-06-10-0150.md` — 5.9 KB
- `chatgpt-naming-prompt.md` — 2.4 KB
- `chikarian-api.js` — 8.1 KB
- `chikarian-crystal-exchange.md` — 5.5 KB
- `chikarian-dev.html` — 5.7 KB
- `chikarian-skill-design-confirmed.md` — 19.2 KB
- `chikarian-skills-expected-value.md` — 8.8 KB
- `chikarian-skills-for-naming.md` — 15.5 KB
- `chikarian-skills-numbers.md` — 11.2 KB
- `chikarian-worldview.md` — 6.3 KB
- `cksound.js` — 3.2 KB
- `deck-mockup.html` — 22.4 KB
- `design-updates-2026-06-13.md` — 6.9 KB
- `gacha-mockup.html` — 12.4 KB
- `hikitsugi-chikarian-2026-06-08.md` — 22.1 KB
- `hikitsugi-chikarian-2026-06-09-2040.md` — 28.6 KB
- `hikitsugi-chikarian-2026-06-10-0150.local.bak` — 29.4 KB
- `hikitsugi-chikarian-2026-06-10-0150.md` — 29.7 KB
- `hikitsugi-chikarian-2026-06-12.md` — 14.9 KB
- `home-mockup.html` — 20.0 KB
- `houchi-mockup.html` — 19.8 KB
- `index.html` — 194.8 KB
- `kyoka-mockup.html` — 31.9 KB
- `mission-mockup.html` — 9.7 KB
- `mission-spec-2026-06-11.md` — 5.2 KB
- `opening-mockup.html` — 7.3 KB
- `report-mockup.html` — 13.5 KB
- `saishu-test.html` — 24.6 KB
- `settings-mockup.html` — 5.5 KB
- `shurenjo-mockup.html` — 17.5 KB
- `shurenjo-spec-2026-06-10-0900.md` — 6.7 KB
- `skill-db-spec-2026-06-14.md` — 13.9 KB
- `skill-kyoka-tenni-spec-2026-06-11-1248.md` — 7.7 KB
- `skill-mockup.html` — 27.8 KB
- `skills-chikarian-2026-06-09-2125.md` — 17.4 KB
- `soubi-mockup.html` — 12.8 KB
- `supabase-spec-2026-06-12.md` — 6.6 KB
- `tansaku-mockup.html` — 14.4 KB
- `tatemono-mockup.html` — 18.8 KB
- `title-mockup.html` — 7.8 KB
- `verify-skill-db-2026-06-14.sql` — 6.5 KB
- `zukan-mockup.html` — 17.1 KB
