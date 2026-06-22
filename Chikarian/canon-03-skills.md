# canon-03-skills — スキル全定義・計算順・強化/転移/交換【唯一の正(canon)】

> スキルの定義（skill_master）・effect_type・計算処理順・固定/転移/錬成・天啓・SP固定3種・クリスタル交換所の唯一の正。
> 凡例：**【確定】**=構造・ルールは動かさない／**【仮】**=数値は調整対象（効果量・倍率・コスト等）／**【決定/実装差分】**=設計確定だが repo 実装が旧＝要追従。
> 数値の正＝`chikarian-skills-numbers.md`／`balance §3`（全て仮）。構造・キー・適用ルール＝本書。
> 主出典：`chikarian-skill-design-confirmed.md`／`skills-numbers`／`skills-expected-value`／`skill-db-spec-2026-06-14.md`／`skill-kyoka-tenni-spec`／`chikarian-crystal-exchange.md`＋実装 0006/0008/0011/0013/0014/0019。
> 相互参照：★強化の**素材ルール**＝canon-02／★式・成功率・コスト・★消費カーブ＝**canon-04**／三すくみ**係数**＝**canon-05**／UI・施設・ミッション供給＝**canon-06**。

---

## 1. スキルの基本【確定】
- 1カード＝**固定1（slot0）＋空き2（slot1/2）＝計3**。固定はガチャでランダム付与・**変更不可**。空き2の埋め方＝**転移**（§9）。
- 効き先＝**対象グループ（属性/武器）に該当する味方カードの合計戦力**（個別カードでない）。偏重デッキ（例：花3枚）では花スキルがデッキ全員に効く。
- **確率発動**（毎戦ブレる・常時発動は一部）。**強化で伸びるのは効果量のみ・発動率は固定**（青天井）。
- **同スキル制限**：同一スキルは1デッキに**1個まで**（同種は別スキルなら可。例：花葉連奏と花芯連奏は別）。
- **発動率【確定】**：**N85% / R75% / SR65%**。SSR・SP・特殊・めしべは個別（§2）。
- 表示（編成/図鑑）＝発動前の素の総合戦力。実戦闘力（発動込み）はボス戦/修練場のみ。

## 2. skill_master 全定義【DB=正・client読取りのみ｜0006・skill-db-spec §2-3／数値=仮】
- 列：skill_key(PK)／display／rarity／is_meshibe／effect_type(§3)／target_scope(self/group/group2/deck_all/enemy)／target_group(2)／activation_rate(0-1)／base_value(Lv1効果量)／per_lv_value／lv_upgradable／is_battle。
- `card_skills.skill_key` は FK。base/per_lv の%は小数（+24%→0.24・×4.0→4.0）。グループ依存は6グループ展開、連奏は6ペア。

| skill_key | display | rarity | effect_type | scope | rate | base | per_lv | lv_up |
|---|---|---|---|---|---|---|---|---|
| n_sougou_{hana/ha/shin/ken/tate/tsue} ×6 | 〇焔 | n | sougou_pct | group | 0.85 | 0.24 | 0.0153 | ○ |
| n_hontai_{6} ×6 | 〇の礎 | n | hontai_pct | group | 0.85 | 1.42 | 0.059 | ○ |
| r_sougou_{6} ×6 | 〇煌 | r | sougou_pct | group | 0.75 | 0.22 | 0.0333 | ○ |
| r_soubi_{6} ×6 | 〇刃 | r | soubi_pct | group | 0.75 | 0.28 | 0.0366 | ○ |
| sr_kyousou_{g1}_{g2} ×6 | 連奏 | sr | kyousou_pct | group2 | 0.65 | 0.18 | 0.0585 | ○ |
| sr_gekirin | 逆鱗 | sr | advantage_scaling | self | 0.55 | 0.25 | 0.069 | ○ |
| sr_keppun | 血焚 | sr | risk_soubi | self | 0.60 | 0.55 | 0.0696 | ○ |
| ssr_haen | 覇焔解放 | ssr | self_burst | self | 0.15 | 20 | 1.1 | ○ |
| ssr_yuusei | 絶対優勢 | ssr | amplify_advantage | self | 0.40 | 0.30 | 0.1375 | ○ |
| ssr_ougon | 黄金律 | ssr | deck_sougou_pct | deck_all | 1.00 | 0.12 | 0.055 | ○ |
| ssr_kyoumei | 共鳴 | ssr | meta_amplify | self | 1.00 | 0.30 | (他スキル比) | ○ |
| meshibe_sr_hisou | 秘奏 | sr | meshibe_group_pct | group(芯or杖) | 0.65 | 0.189 | 0.0614 | ○ |
| meshibe_sr_banshou | 万象共鳴 | sr | per_skill_count | self | 0.65 | 0.05 | 0.01 | ○ |
| meshibe_ssr_shinsou | 神奏 | ssr | meshibe_group_pct | group(芯or杖) | 0.40 | 0.315 | 0.144 | ○ |
| meshibe_ssr_tenkei | 天啓の導き | ssr | force_activate | deck_all | 1.00 | 1 | 0 | **×** |
| n_util_houjou | 豊穣の眼 | n | utility_explore | (探索) | 1.00 | 0.30 | — | ○ |
| n_util_senri | 千里眼 | n | utility_drop | (探索) | 1.00 | (仮) | — | ○ |
| sp_ryuki | 竜気覚醒 | sp | deck_sougou_mult | deck_all | 0.05 | **4.0** | 0 | **×** |
| sp_aitou | 哀慟の眼 | sp | enemy_mult | enemy | 0.05 | 0.25 | 0 | **×** |
| sp_fushichou | 不死鳥の加護 | sp | loss_nullify | deck_all | 0.40 | 0 | 0 | **×** |

- is_battle=false（戦闘で無効）＝n_util_houjou / n_util_senri（探索系・§canon-06）。それ以外は true。
- **竜気覚醒 base＝4.0／哀慟の眼 base＝0.25**〔2026-06-18決定〕。**実装＝0027 で適用済**（旧 竜気2.50/1.90・哀慟0.40）。
- **【意図】** 竜気（自軍総合×）と哀慟（敵×0.25＝−75%）は**期待値を揃える調整**（「ゴールドドラゴンのスキル効果は哀慟の期待値に合わせる」〔creator-intent §5-7〕）＝どちらのSPでも勝ち筋の価値が近くなるように。発動5%の一発逆転枠。
- per_lv 等の数値は全て**仮**（skills-numbers/balance が正・調整対象）。SSR per_lv 等は期待寄与の刻みから逆算した暫定値。

## 3. effect_type 定義と適用【確定構造｜skill-db-spec §4】

| effect_type | 適用先 | 計算 |
|---|---|---|
| hontai_pct | 対象グループの本体 | 本体×(1+base) |
| soubi_pct | 対象グループの装備項 | 装備項×(1+base) |
| sougou_pct | 対象グループの総合 | 総合×(1+base)（同種加算） |
| kyousou_pct | 2グループの総合 | 総合×(1+base) |
| meshibe_group_pct | 芯属性 or 杖武器の和集合の総合 | 総合×(1+base) |
| self_burst | 自身の本体 | 本体×base（base=20倍） |
| amplify_advantage | 自身（三すくみ有利時のみ） | 有利係数に+base（+0.30・仮） |
| advantage_scaling | 自身（敵が格上時のみ） | 総合×(1+base×格上度)・上限base |
| risk_soubi | 自身の装備項＋損失フラグ | 装備項×(1+base)・武気損失2倍 |
| deck_sougou_pct | デッキ全体総合 | 全カード総合×(1+base) |
| deck_sougou_mult | デッキ全体総合 | 全カード総合×base（×4.0） |
| meta_amplify | 自身の他発動スキルの効果量 | 他スキルの効果量(+%)×(1+base) |
| per_skill_count | 自身（発動他スキル数参照） | 総合×(1+base×発動他スキル数) |
| force_activate | デッキの確率スキルから1つ確定発動 | §6（発動判定前に選定） |
| loss_nullify | 敗北時の武気損失 | 損失率=0 |
| enemy_mult | 敵の実戦闘力 | 敵側×base（敵弱体） |
| utility_explore / utility_drop | 戦闘では無効（is_battle=false） | 探索で参照（canon-06） |

- Lv効果量＝base_value + per_lv_value×(Lv−1)（lv_upgradable=false は base 固定）。

## 4. 計算処理順【確定＝実装(0008/0011)準拠 2026-06-17】
各カードの素の値（本体＝Lv式・装備項＝込めた武気×枠攻撃力／式は canon-04）を出した後、発動スキルを次の順で適用する。

0. **発動判定**：force_activate（天啓・§6）があれば、`is_battle・force_activate以外・発動率<1` の確率スキルから**一様ランダムに1つ**を「発動確定」に追加。残りは各 activation_rate で発動可否を判定（force 対象は自身の発動率を無視して100%）。
1. **共鳴 meta_amplify**：発動した他スキルの**効果量(+%)を ×(1+0.30)** に増幅（実装＝各スキルの効果量を先に1.3倍＝設計意図「他スキル効果量+30%」と一致）。
2. **本体+% hontai_pct ＋ 自己大振り self_burst** → 本体に適用（self_burst＝本体×20。本体に掛ける順序は結果不変）。
3. **装備+% soubi_pct ＋ 血焚 risk_soubi** → 装備項に適用（血焚＝装備項×(1+0.55)＋武気損失2倍フラグ）。
4. **カード総合 ＝ 装備項 ＋ 本体**。
5. **総合×系（同種加算）**：連奏 kyousou・総合 sougou・めしべ meshibe_group・格上 advantage_scaling・発動数 per_skill_count → 総合×(1+Σ%)。
6. **黄金律 deck_sougou_pct** → 全カード総合×(1+0.12)。
7. **三すくみ**（カードごと・属性係数×武器係数の乗算B方式・**1.2/0.8/1.0**／係数の正は canon-05）。絶対優勢 amplify_advantage は有利時のみ係数に+0.30（仮）。1面・SPは中立。
8. **竜気覚醒 deck_sougou_mult** → デッキ総合×4.0。
9. **哀慟の眼 enemy_mult** → 敵の実戦闘力×0.25。
10. **勝敗**＝デッキ実戦闘力 ≥ 敵戦力（線形・決定的／canon-04・05）。
11. **損失**＝clamp(0.5×敵/自, 0.10, 1.00)。血焚→×2、不死鳥(敗北)→0。本体無傷・SPは武気なし（canon-04）。

## 5. 固定スキル抽選プール（slot0）【確定｜skill-db-spec §5】
カードの card_key（属性A・武器W・レア）から候補を生成し一様抽選（非戦闘のみ低重み）。

| カード | 候補 |
|---|---|
| N（属性A・武器W） | n_sougou_A, n_sougou_W, n_hontai_A, n_hontai_W ＋ n_util_houjou, n_util_senri（**各 低重み=1/4**） |
| R（A・W） | r_sougou_A, r_sougou_W, r_soubi_A, r_soubi_W |
| SR ハイビスカス（A・W） | Aを含む連奏すべて, Wを含む連奏すべて ＋ sr_gekirin, sr_keppun |
| SSR ハイビスカス | ssr_haen, ssr_yuusei, ssr_ougon, ssr_kyoumei（属性/武器無関係） |
| めしべSR | meshibe_sr_hisou / meshibe_sr_banshou から**1つ**（案X） |
| めしべSSR | meshibe_ssr_shinsou / meshibe_ssr_tenkei から**1つ**（案X） |
| SP（dragon/girl/houou） | sp_ryuki / sp_aitou / sp_fushichou（固定・抽選なし） |

- do_gacha はカード挿入後に slot0 を付与（slot1/2 は作らない＝転移で埋める）。SP も slot0 のみ。
- 「Aを含む連奏」例：A=hana → sr_kyousou_hana_ha, sr_kyousou_hana_shin。

## 6. 天啓の導き（めしべSSR）【確定 2026-06-17｜0008】
- 効果＝**force_activate・発動率1.0**（毎戦必ず1つを確定発動）。
- 選定＝戦闘開始時、`is_battle・force_activate以外・発動率<1` の確率スキルから **一様ランダムに1つ**（**最良選択ではない**）。
- **天啓自身は force_activate＝候補から除外**＝めしべSSRは天啓の抽選候補を1つも出さない。
- Lv強化なし（効果量の概念が薄い特殊枠・SP固定と同じ扱い）。

## 7. SP固定3種【確定】（本体値・素材ルール＝canon-02）
- 竜気覚醒（dragon・5%・デッキ総合×**4.0**）／哀慟の眼（girl・5%・敵×0.25）／不死鳥の加護（houou・40%・敗北時 武気損失0）。
- **固定＝スキル強化（錬成）・転移・の対象外**・Lv強化なし（効果量固定）。通常スキルがLvで伸びると相対的に抜かれるのは許容（救済＝交換所§10）。
- **発動日離脱**：竜気/哀慟は効果が当たった時／不死鳥は敗北して損失0が適用された時＝当日デッキ離脱・0時復帰。修練場は対象外（詳細 canon-06）。

## 8. スキル強化（クリスタル錬成）【骨子確定／数値仮｜0014・skill-kyoka-tenni・crystal-exchange】
- スキルLvを1上げる＝クリスタルを**1色・C個**投げて1回挑戦（混色不可）。★強化とは別画面。
- **成功率＝色で固定**：**青10% / 赤33% / 虹100%**。失敗＝C個消失・**Lv据置**。伸びるのは効果量のみ・発動率は固定。
- **【意図】** 「虹=必ず成功／赤=中程度／青=成功しにくいが手に入りやすい・失敗してもレベルは下がらない・効果量だけ伸びレベル上限なし（やり込み）」〔creator-intent §5-7〕＝青は安価に大量入手の代わり低確率、虹は確実だが希少（SPからのみ）。失敗で下がらないのは賽の河原を避ける配慮。
- **必要個数 C ＝ ceil( 基礎カーブ(現Lv) × レア倍率 )**。
  - レア倍率【確定・実装0014】：**N2 / R4.4 / SR8.8**、SSR＝**×17.6（仮・要確定）**。めしべスキルもレアリティの倍率を使う（秘奏・万象共鳴＝SR8.8／神奏＝SSR17.6）。
  - **錬成（強化）の対象外＝lv_upgradable=false のスキルのみ＝SP固定3種（竜気/哀慟/不死鳥）＋天啓の導き**。それ以外（めしべの秘奏・万象共鳴・神奏を含む）は**強化可能**。
  - 基礎カーブ（仮）：Lv1-2=1／3-4=2／5-6=3／7-8=4／9-10=5／11-16=7/10／…／40+は1帯ごと×1.4（青天井）。詳細 skill-kyoka-tenni §1。
- 供給は交換所が主（§10）＋ミッション（canon-06）。90日（※クリア期間は見直し中・canon-04）で主力スキル Lv5-10 が目安。

## 9. スキル転移【骨子確定／数値仮｜0013・skill-kyoka-tenni】
- 素材カードの**固定/追加のどちらか1つ**のスキルを、対象カードの**空きスロット**へ**移動**（複製なし・Lv持込）。**埋まった移植枠への上書き（入替）も可【0055】**＝受け枠の既存スキルは消滅（「選ばなかったスキルも失われる」に整合）・返り値 replaced。固定 slot0 は不可侵のまま。
- 素材は**消滅**（選ばなかったスキルも失われる）。**1回1スキル**。**失敗なし**。コスト＝メダル（**仮3,000**）。
- **固定スロットは不可侵**（固定スキル変更不可は維持）。空き枠は属性/武器不問で載る。
- **SP固定は対象外**。**めしべ専用スキルはめしべ同士のみ転移可**（通常カードへは移せない／通常→めしべの空き枠は可）。
- **レア制限なし**：N/R/SR/SSR どのレアのスキルも空き枠へ移せる（実装0013にレア判定は無い）。移せないのは **SP固定スキル** と **めしべ↔通常の越境** だけ。むしろSR/SSRの強スキルを載せるのが転移の主目的。

## 10. クリスタル交換所（カード→クリスタル）【方針確定／★0基準値=仮｜crystal-exchange・2026-06-16決定｜実装0019=旧・要追従】
- **一方向**（カード→クリスタル）。SPも交換可。**ロック中カードは交換不可**。UI・施設面は canon-06。
- **交換価値＝レアリティ×★（本体ランク）**【確定方針】。装備の質・EXP(Lv)は**含めない**。
- **色割当【2026-06-16決定・虹はSPのみ】**：N・R→青／SR・SSR→赤／**SP→虹（虹はSPからのみ）**。レア順は維持。
- **個数 ＝ ★0基準値 × 2^★（＝投入カード枚数）**。★強化は「同★素材」＝倍々消費（0012：素材★≠本体★は STAR_MISMATCH）。よって ★K のカードは **2^K 枚**ぶんの投資で、交換もその枚数ぶんを返す。

| レア(色) | ★0 | ★1 | ★2 | ★3 | ★4 |
|---|---|---|---|---|---|
| N（青） | 1 | 2 | 4 | 8 | 16 |
| R（青） | 2 | 4 | 8 | 16 | 32 |
| SR（赤） | 2 | 4 | 8 | 16 | 32 |
| SSR（赤） | 6 | 12 | 24 | 48 | 96 |
| SP（虹） | 2 | 4 | 8 | 16 | 32 |

- 設計意図：**虹は律速資源＝安易に配らない**（SR/SSRを赤へ格下げ・虹は希少なSPのみ）。青/赤は余りがちだが低レアスキルは追い越されるので問題なし。
- **★0基準値は仮**（調整対象）／**★倍率は 2^★ 固定**（投資保存＝投入枚数ぶんを返す）。
- ※旧版（N青16/R赤8/SR虹11/SSR虹45/SP虹17・★は+0.20/★・crystal-exchange-06-14）は**破棄**（+0.20/★は★1で投資割れ＝誤り）。実装0019も旧値＝**要追従**。

## 11. 出典・改訂
- 出典：skill-design-confirmed／skills-numbers／skills-expected-value／skill-db-spec-06-14／skill-kyoka-tenni-spec／crystal-exchange ＋ 実装 0006/0008/0011/0013/0014/0019。
- **2026-06-17 反映/裁定**：発動率 N85/R75/SR65／錬成レア倍率 N2/R4.4/SR8.8（めしべはレア倍率で強化可）／**錬成対象外＝SP固定3種＋天啓のみ**／交換価値＝レアリティ×★／**交換所レート＝N青1/R青2/SR赤2/SSR赤6/SP虹2・虹はSPのみ（2026-06-16決定）・★倍率=2^★（投入枚数）**／SP名「哀慟の眼」／竜気覚醒「×2.50」／三すくみ計算順は1.2/0.8（係数の正は canon-05）／**天啓＝一様ランダム選択で確定**／**計算処理順＝実装(0008/0011)準拠で確定**。
- **2026-06-18 反映**：竜気覚醒「×2.50→×4.0」／哀慟の眼「×0.40→×0.25（−75%）」（SP本体3種=3,200の統一は canon-02）。実装＝0027 で適用済。
- **実装反映済（旧要追従・2026-06-19）**：竜気×4.0【0027】／交換所レート 虹SPのみ・×2^★【0030】。三すくみ係数1.2/0.8 は 0011→**0028**（武器の輪を盾>剣>杖へ修正・skill-design A-2 の旧1.5/0.7 は不採用）。詳細は canon-07 §3。
- **仮（調整対象）**：各効果量・per_lv・Lvカーブ全般／SSR錬成倍率×17.6／自己大振り×20／絶対優勢+0.30／転移コスト3,000／千里眼効果量／**交換所の★0基準値**（★倍率は2^★で確定）。
- 統合：本 canon-03 が skills-design-confirmed／skills-numbers／skills-expected-value／skill-db-spec／skill-kyoka-tenni-spec／crystal-exchange／（命名用 skills-for-naming）を置換（**いずれも退避候補**）。
