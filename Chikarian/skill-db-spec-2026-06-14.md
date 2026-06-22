# チカリアン スキルDB化 実装仕様書（2026-06-14）— Claude Code実装用

> 目的：do_gacha の固定スキル付与・do_boss_battle のスキル計算に必要な「スキルのDB化」を実装するための詳細仕様。
> **数値の正＝chikarian-skills-numbers.md / balance §3。本書の数値はそこから転記（全て仮・調整対象）。構造・キー・適用ルールは本書で確定。**
> 発動率は確定：N85% / R75% / SR65%（SSR・特殊は各個別）。SPスキルとSSR-M2はLv強化なし（固定）。

---

## 0. 全体方針

- スキルの「効果量・発動率・Lv伸び・効果タイプ」を **skill_master テーブル**に持つ（DBが正・クライアントは読取りのみ・書込み不可）。
- do_boss_battle（サーバRPC）が skill_master を参照し、effect_type ごとに分岐して計算（不正対策C：計算は全てサーバ）。
- card_skills.skill_key は skill_master.skill_key を参照（FK）。
- **計算順は skills-numbers の2段階を採用**（【装備】【本体】%で土台→【総合】%で倍化・同種加算→デッキ全体→三すくみ）。balance §3 の「×スキル発動補正」は簡略表記とみなし、実体は本書 §7 の手順。

---

## 1. skill_key 命名規則【確定】

- 英小文字＋アンダースコア。**名称に依存させない**（ネーミングが変わってもキーは不変）。
- グループ依存：`{rare}_{type}_{group}`（type=sougou/hontai/soubi、group=hana/ha/shin/ken/tate/tsue）
- 連奏：`sr_kyousou_{g1}_{g2}`
- 特殊・SP・めしべ・非戦闘：`{rare}_{固有}` / `meshibe_{rare}_{固有}` / `sp_{固有}` / `n_util_{固有}`

---

## 2. skill_master テーブル【確定・DDL】

```sql
create table if not exists public.skill_master (
  skill_key       text primary key,
  display_name    text not null,
  rarity          text not null check (rarity in ('n','r','sr','ssr','sp')),
  is_meshibe      boolean not null default false,
  effect_type     text not null,          -- §4の値
  target_scope    text not null check (target_scope in ('self','group','group2','deck_all','enemy')),
  target_group    text,                   -- hana/ha/shin/ken/tate/tsue or null
  target_group2   text,                   -- 連奏の2つ目 or null
  activation_rate numeric not null,       -- 0..1（常時=1.0）
  base_value      numeric not null,       -- Lv1効果量（§4で意味が変わる）
  per_lv_value    numeric not null default 0, -- Lv1あたり伸び
  lv_upgradable   boolean not null default true,
  is_battle       boolean not null default true,  -- false=戦闘で効かない(探索系)
  notes           text
);
alter table public.skill_master enable row level security;
drop policy if exists skill_master_select_all on public.skill_master;
create policy skill_master_select_all on public.skill_master
  for select to authenticated using (true);   -- マスタは全員読取り可・書込みポリシー無し＝不可
```

- card_skills.skill_key に FK を張る（任意・推奨）：
  `alter table public.card_skills add constraint card_skills_skill_key_fk foreign key (skill_key) references public.skill_master(skill_key);`
  ※ 既存の card_skills が空なら問題なし。

---

## 3. skill_master データ【skills-numbers から転記・全数値仮】

> グループ依存は6グループ（hana/ha/shin/ken/tate/tsue）に展開。連奏は6ペア。
> base_value の意味は effect_type ごとに §4 参照（%は小数：+24%→0.24、×1.90→1.90）。

### N帯（発動0.85）
| skill_key | display | effect_type | scope | group | base | per_lv | 備考 |
|---|---|---|---|---|---|---|---|
| n_sougou_{g} ×6 | 〇焔 | sougou_pct | group | 各 | 0.24 | 0.0153 | 総合+24% |
| n_hontai_{g} ×6 | 〇の礎 | hontai_pct | group | 各 | 1.42 | 0.059 | 本体+142%（損失軽減込みでN総合×と等価・案2）|

### R帯（発動0.75）
| skill_key | display | effect_type | scope | group | base | per_lv |
|---|---|---|---|---|---|---|
| r_sougou_{g} ×6 | 〇煌 | sougou_pct | group | 各 | 0.22 | 0.0333 |
| r_soubi_{g} ×6 | 〇刃 | soubi_pct | group | 各 | 0.28 | 0.0366 |

### SR帯（発動0.65、特殊は個別）
| skill_key | display | effect_type | scope | group/2 | rate | base | per_lv |
|---|---|---|---|---|---|---|---|
| sr_kyousou_{g1}_{g2} ×6 | 連奏 | kyousou_pct | group2 | 2グループ | 0.65 | 0.18 | 0.0585 |
| sr_gekirin | 逆鱗 | advantage_scaling | self | - | 0.55 | 0.25 | 0.069 | 格上(R>1)で最大+25% |
| sr_keppun | 血焚 | risk_soubi | self | - | 0.60 | 0.55 | 0.0696 | 装備+55%／武気損失2倍 |

連奏6ペア：hana_ha / ha_shin / hana_shin / ken_tate / tate_tsue / ken_tsue

### SSR帯（発動・伸びは個別）
| skill_key | display | effect_type | scope | rate | base | per_lv | lv_up |
|---|---|---|---|---|---|---|---|
| ssr_haen | 覇焔解放 | self_burst | self | 0.15 | 20 | (倍率で+5.5%/Lv相当) | true | 本体×20倍 |
| ssr_yuusei | 絶対優勢 | amplify_advantage | self | 0.40 | 0.30 | 0.1375 | true | 有利時、有利を+30%増幅 |
| ssr_ougon | 黄金律 | deck_sougou_pct | deck_all | 1.00 | 0.12 | 0.055 | true | デッキ全体総合+12%常時 |
| ssr_kyoumei | 共鳴 | meta_amplify | self | 1.00 | 0.30 | (他スキル比) | true | 自身の他スキル効果量+30% |

### めしべ専用（is_meshibe=true）
| skill_key | display | effect_type | scope | rate | base | per_lv | lv_up |
|---|---|---|---|---|---|---|---|
| meshibe_sr_hisou | 秘奏 | meshibe_group_pct | group | 0.65 | 0.189 | 0.0614 | true | 芯or杖の味方の総合+18.9% |
| meshibe_sr_banshou | 万象共鳴 | per_skill_count | self | 0.65 | 0.05 | 0.01 | true | 発動他スキル1つにつき+5% |
| meshibe_ssr_shinsou | 神奏 | meshibe_group_pct | group | 0.40 | 0.315 | 0.144 | true | 芯or杖の味方の総合+31.5% |
| meshibe_ssr_tenkei | 天啓の導き | force_activate | deck_all | 1.00 | 1 | 0 | **false** | 確定発動1つ・Lv強化なし |

### 非戦闘（N固定プール・低重み・is_battle=false）
| skill_key | display | effect_type | rate | base | lv_up | is_battle |
|---|---|---|---|---|---|---|
| n_util_houjou | 豊穣の眼 | utility_explore | 1.00 | 0.30 | true | false | 探索報酬+30% |
| n_util_senri | 千里眼 | utility_drop | 1.00 | (仮) | true | false | 探索ドロップUP |

### SP専用（固定・lv_upgradable=false）
| skill_key | display | effect_type | scope | rate | base | lv_up |
|---|---|---|---|---|---|---|
| sp_ryuki | 竜気覚醒 | deck_sougou_mult | deck_all | 0.05 | 1.90 | false | デッキ全体総合×1.90 |
| sp_aitou | 哀慟の眼 | enemy_mult | enemy | 0.05 | 0.40 | false | 敵実戦闘力×0.40 |
| sp_fushichou | 不死鳥の加護 | loss_nullify | deck_all | 0.40 | 0 | false | 敗北時デッキ武気損失0 |

---

## 4. effect_type 定義と do_boss_battle 適用ルール【確定構造】

| effect_type | 適用 | 計算 |
|---|---|---|
| hontai_pct | 対象グループのカード本体戦闘力 | 本体 ×(1+base) |
| soubi_pct | 対象グループのカード装備項 | 装備項 ×(1+base) |
| sougou_pct | 対象グループのカード総合戦力 | 総合 ×(1+base)（同種加算）|
| kyousou_pct | 2グループのカード総合戦力 | 総合 ×(1+base) |
| meshibe_group_pct | 芯属性 or 杖武器の味方の総合（和集合）| 総合 ×(1+base) |
| self_burst | 自身の本体戦闘力 | 本体 ×base（base=20倍）|
| amplify_advantage | 自身（三すくみ有利時のみ）| 有利倍率(1.5)に +base |
| advantage_scaling | 自身（敵が格上時のみ）| 総合 ×(1+base×格上度)・上限base |
| risk_soubi | 自身の装備項＋損失フラグ | 装備項×(1+base)・武気損失2倍フラグ |
| deck_sougou_pct | デッキ全体総合 | 全カード総合 ×(1+base) |
| deck_sougou_mult | デッキ全体総合 | 全カード総合 ×base（×1.90）|
| meta_amplify | 自身の他発動スキルの効果量 | 他スキルeffect ×(1+base) |
| per_skill_count | 自身（発動他スキル数参照）| 総合 ×(1+base×発動他スキル数)|
| force_activate | デッキの確率スキルから1つ確定発動 | 発動判定前に1つ選び発動扱い |
| loss_nullify | 敗北時の武気損失 | 損失率=0 にする |
| enemy_mult | 敵実戦闘力 | 敵側 ×base（自軍デバフでなく敵弱体）|
| utility_explore/drop | 戦闘では無効（is_battle=false）| collect_tansaku 等で参照 |

**Lv効果量**：base_value + per_lv_value×(Lv−1)（lv_upgradable=false は base 固定）。

---

## 5. 固定スキル(slot 0)抽選プール【確定】

カードの card_key（属性/武器/レア）から候補集合を生成し、一様抽選（非戦闘のみ低重み）。

| カード | 候補生成ルール |
|---|---|
| N（属性A・武器W）| n_sougou_A, n_sougou_W, n_hontai_A, n_hontai_W ＋ n_util_houjou, n_util_senri（**低重み＝各1/4**）|
| R（属性A・武器W）| r_sougou_A, r_sougou_W, r_soubi_A, r_soubi_W |
| SR ハイビスカス（属性A・武器W）| Aを含む連奏すべて, Wを含む連奏すべて ＋ sr_gekirin, sr_keppun |
| SSR ハイビスカス | ssr_haen, ssr_yuusei, ssr_ougon, ssr_kyoumei（属性/武器無関係）|
| めしべSR | meshibe_sr_hisou, meshibe_sr_banshou から1つ（案X）|
| めしべSSR | meshibe_ssr_shinsou, meshibe_ssr_tenkei から1つ（案X）|
| SP dragon/girl/houou | sp_ryuki / sp_aitou / sp_fushichou（固定・抽選なし）|

- 「Aを含む連奏」例：A=hana → sr_kyousou_hana_ha, sr_kyousou_hana_shin。W=ken → sr_kyousou_ken_tate, sr_kyousou_ken_tsue。
- 低重み実装：通常候補の重み=4、非戦闘の重み=1（相対）。

---

## 6. do_gacha 固定スキル付与の追加【0004改修】

do_gacha のカード挿入直後（cards に insert し new_id を得た後）に追加：

1. card_key からレア・属性・武器を解析。
2. §5 のルールで候補集合を生成。
3. SP は固定キーを直接、それ以外は候補から重み付き一様抽選で skill_key を1つ決定。
4. `insert into card_skills (card_id, slot, skill_key, skill_lv) values (new_id, 0, 選択skill_key, 1);`
5. slot1/2（空き）は作らない（転移で埋める）。SP も slot0 のみ。

※ 既存カード（固定スキル未付与）への遡及付与は別関数 `backfill_fixed_skills()` を用意してもよい（任意）。

---

## 7. do_boss_battle 計算手順【疑似コード・構造確定／数値はマスタ/balance】

```
入力: deck_no, boss_key
1. 認証・profile行ロック。boss_count_today を JST で日次リセット判定→3回上限検証→+1。
2. deck_no のデッキ取得。各スロットのカード（cards）＋固定/空きスキル（card_skills）取得。
   SP離脱中(sp_states)のカードがいたら戦闘不可 or その枠無効（編成時に弾く前提だが二重チェック）。
3. 各カードの素の値を計算（balance §3）:
   本体戦闘力 = 基礎×(1+(Lv−1)×rL)×(1+0.15×★)   ※基礎/Lv上限=レア別(balance §3表)
   充填量・装備項 = 込めた武気(loaded_buki)×枠攻撃力(質)   ※SPは装備項0
4. スキル発動判定:
   - force_activate(天啓)があれば、デッキの確率スキルから1つ選び「発動確定」リストへ。
   - 残りの各スキルを activation_rate で乱数判定→発動リスト。
5. 発動スキルを effect_type 順に適用（§4）:
   a. hontai_pct → 本体に
   b. soubi_pct / risk_soubi → 装備項に（risk_soubiは損失2倍フラグ立て）
   c. カード総合 = 装備項 + 本体
   d. sougou_pct / kyousou_pct / meshibe_group_pct / advantage_scaling / per_skill_count → 総合に（同種加算）
   e. self_burst → 本体を×20して総合再計算（対象カードのみ）
   f. meta_amplify(共鳴) → 自身の他発動スキルのeffectを増幅（適用順注意：先に他effectを確定→共鳴で上乗せ）
   g. deck_sougou_pct(黄金律) → 全カード総合に
   h. 三すくみ（カードごと・属性/装備）：有利×1.5(+amplify_advantage)/不利×0.7/中立×1.0。1面は属性中立。SPは常に中立。
   i. deck_sougou_mult(竜気覚醒) → デッキ総合×1.90
6. デッキ実戦闘力 = Σ(各カード総合×三すくみ)。
7. 敵戦力 = balance §6-1（boss_key→面→戦力・N周目×N）。enemy_mult(哀慟)発動なら敵×0.40。
8. 勝敗 = デッキ実戦闘力 ≥ 敵戦力 ？（判定方式はbalanceに従う・必要なら確率化）。
9. 武気損失率 = clamp(0.5×(敵戦力÷自実戦闘力), 0.10, 1.00)。risk_soubi発動なら×2。
   loss_nullify(不死鳥)が発動かつ敗北なら損失率=0。本体は無傷。
10. 各カードの loaded_buki を損失率ぶん減算（SPは武気なし＝無傷）。
11. SP発動（竜気/哀慟/不死鳥が「発動」した）なら sp_states に unavailable_until=翌日 を記録（当日離脱・0時復帰）。修練場は対象外（本RPCはボスなので常に記録）。
12. 勝利なら報酬（balance §6-2/§6-3：メダル・EXP）。cleared_stage 更新条件があれば反映。
13. battle_logs に追記（boss_key, win, deck, fired_skills, rewards, loss_rate, fought_at）。
14. 返り値（jsonb）：win, 実戦闘力, 敵戦力, 発動スキル, 損失, 報酬, 更新後profile要点。
```

---

## 8. 未確定・要調整（実装時 or 後で）

- 数値は全て仮（skills-numbers/balanceが正・調整対象）。
- self_burst倍率20・各per_lv・非戦闘の重み1/4 は仮。
- 勝敗判定の方式（戦力比較が決定的か確率的か）→ balance確認（現状は実戦闘力≥敵戦力で決定的と仮定）。
- meta_amplify(共鳴)と確定発動(天啓)の適用順の細部（相互作用）。
- 報酬テーブル（balance §6-2/§6-3）の具体値。
- cleared_stage を do_boss_battle が更新するか（勝利で面クリア→+1）→ 8面・周回の扱い要確認。
- backfill_fixed_skills（既存カードへの遡及付与）を作るか。
