-- =============================================================================
-- 0006 : skill_master テーブル（スキルのDB化）＋ 45スキル投入 ＋ card_skills FK
-- 出典: skill-db-spec-2026-06-14.md §2(DDL)・§3(データ)・§4(effect_type)
--        数値の正＝chikarian-skills-numbers.md / balance §3（本書の値は転記＝全て仮）
-- 実行: SQL Editor に貼って Run（create ... if not exists / drop ... if exists で冪等）。
--
-- 【方針（0001 のセキュリティモデルに合わせる）】
--   * マスタは全 authenticated が SELECT 可・書込みポリシー無し＝クライアントからの
--     INSERT/UPDATE/DELETE は RLS で全拒否（spec §0・§2）。更新は SQL Editor / 本マイグレーションのみ。
--   * effect_type ごとの計算は do_boss_battle(0008) が分岐して行う（§4）。
--
-- 【発動率（確定・spec 冒頭）】N=0.85 / R=0.75 / SR=0.65（特殊は個別）。SSR・特殊・SP・めしべは個別。
-- 【Lv効果量】value(Lv) = base_value + per_lv_value*(Lv-1)。lv_upgradable=false は base 固定。
-- 【Lv強化なし（固定）】SPスキル3種 と SSR-M2(=meshibe_ssr_tenkei 天啓) は lv_upgradable=false。
--
-- 【※真に未定義だった値の決め打ち（spec §3 が数値を持たなかった箇所・全て仮・要調整）】
--   - ssr_haen.per_lv_value = 1.1   … spec「(倍率で+5.5%/Lv相当)」→ base20 × 0.055 ≒ 1.1/Lv と解釈
--   - ssr_kyoumei.per_lv_value = 0  … spec「(他スキル比)」＝Lv伸びの数値未定義 → 仮0（lv_upgradable自体はtrue）
--   - n_util_senri.base_value = 0.30 … spec「(仮)」＝未記載 → n_util_houjou と同値で仮置き
--   いずれも numbers/balance 確定後に UPDATE で差し替え可。
-- =============================================================================


-- ============================== 1. skill_master =============================
create table if not exists public.skill_master (
  skill_key       text primary key,
  display_name    text not null,
  rarity          text not null check (rarity in ('n','r','sr','ssr','sp')),
  is_meshibe      boolean not null default false,
  effect_type     text not null,                                   -- §4の値
  target_scope    text not null check (target_scope in ('self','group','group2','deck_all','enemy')),
  target_group    text,                                            -- hana/ha/shin/ken/tate/tsue or null
  target_group2   text,                                            -- 連奏の2つ目 or null
  activation_rate numeric not null,                                -- 0..1（常時=1.0）
  base_value      numeric not null,                                -- Lv1効果量（§4で意味が変わる）
  per_lv_value    numeric not null default 0,                      -- Lv1あたり伸び
  lv_upgradable   boolean not null default true,
  is_battle       boolean not null default true,                   -- false=戦闘で効かない(探索系)
  notes           text
);

alter table public.skill_master enable row level security;
drop policy if exists skill_master_select_all on public.skill_master;
create policy skill_master_select_all on public.skill_master
  for select to authenticated using (true);   -- 全員読取り可・書込みポリシー無し＝不可


-- ============================== 2. 45スキル投入 ==============================
-- 冪等のため on conflict do update（再実行で最新値に揃う）。
insert into public.skill_master
  (skill_key, display_name, rarity, is_meshibe, effect_type, target_scope, target_group, target_group2,
   activation_rate, base_value, per_lv_value, lv_upgradable, is_battle, notes)
values
  -- ---- N帯（発動0.85） ---- 総合+%（〇焔）×6 / 本体+%（〇の礎）×6 -----------------
  ('n_sougou_hana', '花焔', 'n', false, 'sougou_pct', 'group', 'hana', null, 0.85, 0.24, 0.0153, true, true, '総合+24%(N)'),
  ('n_sougou_ha',   '葉焔', 'n', false, 'sougou_pct', 'group', 'ha',   null, 0.85, 0.24, 0.0153, true, true, '総合+24%(N)'),
  ('n_sougou_shin', '芯焔', 'n', false, 'sougou_pct', 'group', 'shin', null, 0.85, 0.24, 0.0153, true, true, '総合+24%(N)'),
  ('n_sougou_ken',  '剣焔', 'n', false, 'sougou_pct', 'group', 'ken',  null, 0.85, 0.24, 0.0153, true, true, '総合+24%(N)'),
  ('n_sougou_tate', '盾焔', 'n', false, 'sougou_pct', 'group', 'tate', null, 0.85, 0.24, 0.0153, true, true, '総合+24%(N)'),
  ('n_sougou_tsue', '杖焔', 'n', false, 'sougou_pct', 'group', 'tsue', null, 0.85, 0.24, 0.0153, true, true, '総合+24%(N)'),
  ('n_hontai_hana', '花の礎', 'n', false, 'hontai_pct', 'group', 'hana', null, 0.85, 1.42, 0.059, true, true, '本体+142%(N・案2)'),
  ('n_hontai_ha',   '葉の礎', 'n', false, 'hontai_pct', 'group', 'ha',   null, 0.85, 1.42, 0.059, true, true, '本体+142%(N・案2)'),
  ('n_hontai_shin', '芯の礎', 'n', false, 'hontai_pct', 'group', 'shin', null, 0.85, 1.42, 0.059, true, true, '本体+142%(N・案2)'),
  ('n_hontai_ken',  '剣の礎', 'n', false, 'hontai_pct', 'group', 'ken',  null, 0.85, 1.42, 0.059, true, true, '本体+142%(N・案2)'),
  ('n_hontai_tate', '盾の礎', 'n', false, 'hontai_pct', 'group', 'tate', null, 0.85, 1.42, 0.059, true, true, '本体+142%(N・案2)'),
  ('n_hontai_tsue', '杖の礎', 'n', false, 'hontai_pct', 'group', 'tsue', null, 0.85, 1.42, 0.059, true, true, '本体+142%(N・案2)'),

  -- ---- R帯（発動0.75） ---- 総合+%（〇煌）×6 / 装備+%（〇刃）×6 -------------------
  ('r_sougou_hana', '花煌', 'r', false, 'sougou_pct', 'group', 'hana', null, 0.75, 0.22, 0.0333, true, true, '総合+22%(R)'),
  ('r_sougou_ha',   '葉煌', 'r', false, 'sougou_pct', 'group', 'ha',   null, 0.75, 0.22, 0.0333, true, true, '総合+22%(R)'),
  ('r_sougou_shin', '芯煌', 'r', false, 'sougou_pct', 'group', 'shin', null, 0.75, 0.22, 0.0333, true, true, '総合+22%(R)'),
  ('r_sougou_ken',  '剣煌', 'r', false, 'sougou_pct', 'group', 'ken',  null, 0.75, 0.22, 0.0333, true, true, '総合+22%(R)'),
  ('r_sougou_tate', '盾煌', 'r', false, 'sougou_pct', 'group', 'tate', null, 0.75, 0.22, 0.0333, true, true, '総合+22%(R)'),
  ('r_sougou_tsue', '杖煌', 'r', false, 'sougou_pct', 'group', 'tsue', null, 0.75, 0.22, 0.0333, true, true, '総合+22%(R)'),
  ('r_soubi_hana', '花刃', 'r', false, 'soubi_pct', 'group', 'hana', null, 0.75, 0.28, 0.0366, true, true, '装備+28%(R)'),
  ('r_soubi_ha',   '葉刃', 'r', false, 'soubi_pct', 'group', 'ha',   null, 0.75, 0.28, 0.0366, true, true, '装備+28%(R)'),
  ('r_soubi_shin', '芯刃', 'r', false, 'soubi_pct', 'group', 'shin', null, 0.75, 0.28, 0.0366, true, true, '装備+28%(R)'),
  ('r_soubi_ken',  '剣刃', 'r', false, 'soubi_pct', 'group', 'ken',  null, 0.75, 0.28, 0.0366, true, true, '装備+28%(R)'),
  ('r_soubi_tate', '盾刃', 'r', false, 'soubi_pct', 'group', 'tate', null, 0.75, 0.28, 0.0366, true, true, '装備+28%(R)'),
  ('r_soubi_tsue', '杖刃', 'r', false, 'soubi_pct', 'group', 'tsue', null, 0.75, 0.28, 0.0366, true, true, '装備+28%(R)'),

  -- ---- SR帯（発動0.65・特殊は個別） ---- 連奏×6 / 逆鱗 / 血焚 ---------------------
  ('sr_kyousou_hana_ha',   '花葉連奏', 'sr', false, 'kyousou_pct', 'group2', 'hana', 'ha',   0.65, 0.18, 0.0585, true, true, '2グループ総合+18%'),
  ('sr_kyousou_ha_shin',   '葉芯連奏', 'sr', false, 'kyousou_pct', 'group2', 'ha',   'shin', 0.65, 0.18, 0.0585, true, true, '2グループ総合+18%'),
  ('sr_kyousou_hana_shin', '花芯連奏', 'sr', false, 'kyousou_pct', 'group2', 'hana', 'shin', 0.65, 0.18, 0.0585, true, true, '2グループ総合+18%'),
  ('sr_kyousou_ken_tate',  '剣盾連奏', 'sr', false, 'kyousou_pct', 'group2', 'ken',  'tate', 0.65, 0.18, 0.0585, true, true, '2グループ総合+18%'),
  ('sr_kyousou_tate_tsue', '盾杖連奏', 'sr', false, 'kyousou_pct', 'group2', 'tate', 'tsue', 0.65, 0.18, 0.0585, true, true, '2グループ総合+18%'),
  ('sr_kyousou_ken_tsue',  '剣杖連奏', 'sr', false, 'kyousou_pct', 'group2', 'ken',  'tsue', 0.65, 0.18, 0.0585, true, true, '2グループ総合+18%'),
  ('sr_gekirin', '逆鱗', 'sr', false, 'advantage_scaling', 'self', null, null, 0.55, 0.25, 0.069,  true, true, '格上(R>1)で最大+25%'),
  ('sr_keppun',  '血焚', 'sr', false, 'risk_soubi',        'self', null, null, 0.60, 0.55, 0.0696, true, true, '装備+55%／武気損失2倍'),

  -- ---- SSR帯（発動・伸びは個別） -------------------------------------------------
  ('ssr_haen',    '覇焔解放', 'ssr', false, 'self_burst',       'self',     null, null, 0.15, 20,   1.1,    true, true, '本体×20倍（per_lv=1.1は仮・spec"+5.5%/Lv相当"解釈）'),
  ('ssr_yuusei',  '絶対優勢', 'ssr', false, 'amplify_advantage','self',     null, null, 0.40, 0.30, 0.1375, true, true, '有利時、有利倍率(1.5)に+0.30'),
  ('ssr_ougon',   '黄金律',   'ssr', false, 'deck_sougou_pct',  'deck_all', null, null, 1.00, 0.12, 0.055,  true, true, 'デッキ全体総合+12%常時'),
  ('ssr_kyoumei', '共鳴',     'ssr', false, 'meta_amplify',     'self',     null, null, 1.00, 0.30, 0,      true, true, '自身の他発動スキル効果量+30%（per_lv未定義＝仮0）'),

  -- ---- めしべ専用（is_meshibe=true） ---------------------------------------------
  ('meshibe_sr_hisou',    '秘奏',       'sr',  true, 'meshibe_group_pct', 'group',    null, null, 0.65, 0.189, 0.0614, true, true, '芯属性or杖武器の味方の総合+18.9%'),
  ('meshibe_sr_banshou',  '万象共鳴',   'sr',  true, 'per_skill_count',   'self',     null, null, 0.65, 0.05,  0.01,   true, true, '発動他スキル1つにつき+5%'),
  ('meshibe_ssr_shinsou', '神奏',       'ssr', true, 'meshibe_group_pct', 'group',    null, null, 0.40, 0.315, 0.144,  true, true, '芯属性or杖武器の味方の総合+31.5%(M1)'),
  ('meshibe_ssr_tenkei',  '天啓の導き', 'ssr', true, 'force_activate',    'deck_all', null, null, 1.00, 1,     0,      false, true, '確定発動1つ・Lv強化なし(SSR-M2)'),

  -- ---- 非戦闘（N固定プール・低重み・is_battle=false） ----------------------------
  ('n_util_houjou', '豊穣の眼', 'n', false, 'utility_explore', 'self', null, null, 1.00, 0.30, 0, true, false, '探索報酬+30%'),
  ('n_util_senri',  '千里眼',   'n', false, 'utility_drop',    'self', null, null, 1.00, 0.30, 0, true, false, '探索ドロップUP（base=0.30は仮・spec未記載）'),

  -- ---- SP専用（固定・lv_upgradable=false） --------------------------------------
  ('sp_ryuki',     '竜気覚醒',     'sp', false, 'deck_sougou_mult', 'deck_all', null, null, 0.05, 1.90, 0, false, true, 'デッキ全体総合×1.90（dragon）'),
  ('sp_aitou',     '哀慟の眼',     'sp', false, 'enemy_mult',       'enemy',    null, null, 0.05, 0.40, 0, false, true, '敵実戦闘力×0.40（girl）'),
  ('sp_fushichou', '不死鳥の加護', 'sp', false, 'loss_nullify',     'deck_all', null, null, 0.40, 0,    0, false, true, '敗北時デッキ武気損失0（houou）')
on conflict (skill_key) do update set
  display_name    = excluded.display_name,
  rarity          = excluded.rarity,
  is_meshibe      = excluded.is_meshibe,
  effect_type     = excluded.effect_type,
  target_scope    = excluded.target_scope,
  target_group    = excluded.target_group,
  target_group2   = excluded.target_group2,
  activation_rate = excluded.activation_rate,
  base_value      = excluded.base_value,
  per_lv_value    = excluded.per_lv_value,
  lv_upgradable   = excluded.lv_upgradable,
  is_battle       = excluded.is_battle,
  notes           = excluded.notes;


-- ============================== 3. card_skills FK ===========================
-- card_skills.skill_key → skill_master.skill_key（spec §2・推奨）。
-- 既存 card_skills は空（do_gacha 0004 は固定スキル未付与）＝FK追加で問題なし。
-- 冪等のため drop if exists → add。
alter table public.card_skills drop constraint if exists card_skills_skill_key_fk;
alter table public.card_skills
  add constraint card_skills_skill_key_fk
  foreign key (skill_key) references public.skill_master(skill_key);

-- =============================================================================
-- 件数チェック（任意）: select count(*) from public.skill_master;  -- → 45
-- =============================================================================
