# canon-07-schema-rpc — DBスキーマ・RPC一覧・要追従/未実装【実装の現状(canon)】

> これは **repo（実装）の現状の地図**。設計の正は canon-01〜06、本書は「repo が今どうなっているか」＋「設計とのズレ（要追従）」＋「未実装」を一覧化する。
> **repo が常に正**：`C:\Users\justi\projects\hanahana\Chikarian`（GitHub Pages: gureslot/hanahana）。チャット添付ではなく repo か Claude Code に読ませる。
> 凡例：**【確定】**＝据え置き／**【要追従】**＝実装が旧・設計値へ更新要／**【未実装】**＝SQL未起票。

---

## 0. 基本方針【確定】
- **資産が動く処理は全てサーバRPC**（チカリウム/メダル/武気/カード/★/スキル/装備）。クライアントは表示と呼び出しのみ＝**クライアントから資産を直接書かない**。
- **全テーブル RLS 有効**。**認証＝Google**。値の検証・乱数・成功判定はサーバ側。
- RPC は冪等・トランザクション内で資産更新。`for update` 等で競合制御。

## 1. テーブル（0001 ＋ 追加）

| テーブル | 役割 | 主な列 |
|---|---|---|
| profiles | ユーザー状態（1行/user） | chikarium, medal, cleared_stage, hoshou_stone, saishu_today/saishu_date, exp_book_s/m/l/xl, boss_round/boss_round_stage（0038）, **boss_round_role（0=未/1=中A済/2=中B済・0054＝面内ノード順次解放）** |
| cards | 所持カード | id, user_id, card_key, star, locked, exp, quality, loaded_buki, tansaku_deck_no（占有ロック・実装0033/0034）, boss_deck_no（ボス出撃・実装0042） |
| card_skills | カードのスキル枠 | card_id, slot(0=固定/1,2=空き), skill_key, skill_lv |
| decks | デッキ編成（最大本数=cleared_stage連動） | deck_no, slot, card_id |
| tansaku_states | 探索/放置の状態 | deck_no, depth(smallint 1/2/3), is_houchi, started_at, area/面 |
| renkiden | 練気殿（武気生産・1行/user） | lv, buki_stored(numeric), fuel_medal, last_calc_at |
| kajiya_orders | 鍛冶屋の依頼 | quality, status, finish_at |
| sp_states | SP発動日離脱 | card_id, unavailable_until(JST) |
| battle_logs | ボス/戦闘ログ | result, own_power, enemy_power, round, … |
| missions | ユーザーのミッション進捗 | mission_key, progress, claimed |
| mission_master | ミッション定義（0020） | mission_key, kind(daily/weekly/achieve), 条件, 報酬 |
| zukan | 図鑑（収集） | card_key, owned |

- skill_master / boss_master はマスタ（canon-03 §2 / canon-05）。`card_skills.skill_key`→skill_master、`boss_master.boss_key`→do_boss_battle が JOIN。

## 2. RPC一覧（0002–0046・カッコ内が最新版）
同名 RPC が複数ファイルで再定義されるものは**最新版が正**（カッコ内）。

| RPC | 機能 | 設計の正 |
|---|---|---|
| initialize_profile (0002→**0051**/0022) | 初回プロフィール作成。最新0051＝**初回配布 チカ1,000/メダル1,500/EXP本中×3/武気600(renkiden.buki_stored)/恩寵石0**（handle_new_user トリガも同値・on conflict＝一回限り） | canon-06 §0.5 |
| claim_saishu (0003) | 採取（PER_BLINK10・DAILY_MAX1000・0時） | canon-06 §1 |
| do_gacha (0004→**0029**) | ガチャ6枚/300＋固定スキル付与（pick_fixed_skill）・所持枠 least(200+100×stage,1000) | canon-02/03/06 |
| update_deck (0005→**0050**) | デッキ編成（コスト上限11・SP離脱中不可・**1カード=1デッキ排他【0043】**）。**取り外したカード（他デッキにも残らない）の武気×枠コストをプール返却＝実装済み【0050】**（移動だけは返却しない） | canon-02/06 |
| do_boss_battle (0008→**0054**) | ボス戦。最新0054＝**面内ノード順次解放(boss_round_role)**。引き分け=敗北(draw返却・0049)・3引数・離脱SP除外・三すくみ・★式0.10・SP本体3200・boss_round・ボス曲線0048・**恩寵石=面ボス初回(0054で復帰)** | canon-04/05 |
| use_exp_book (0009→**0018**) | EXP本でLv上げ（累積EXP→Lv） | canon-06 §3-5 |
| do_kyoka (0012→**0056**) | ★強化（同レア同★素材・成否で素材消費・成功率=素材Lv依存・メダル500×(★+1)）。**ロック中の本体でも強化可【0056】**（本体は消費しない＝素材保護 MATERIAL_LOCKED のみ維持） | canon-02 §6 |
| do_skill_teni (0013→**0055**) | スキル転移（空き枠へ移動・素材消滅・固定不可侵）。**埋まった枠への上書き＝可【0055】**（元スキル消滅・replaced返却） | canon-03 §9 |
| do_skill_rensei (0014→**0034**) | スキル錬成（クリスタル1色・青10/赤33/虹100%） | canon-03 §8 |
| renkiden系 (0015) | 練気殿 invest/collect/instant/upgrade | canon-06 §5-1 |
| kajiya系 (0016) | 鍛冶屋 place_kajiya_order/claim_kajiya | canon-06 §5-2 |
| equip_buki (0017→**0034**) | 装備充填（込めた武気×枠攻撃力・qatk 10/15/22/34） | canon-04 §1/§3 |
| start_tansaku (0018→**0058**) / collect_tansaku (0018→**0057**) | 探索の開始/回収（0033 占有ロック→0036 出撃ガード→**0057 レート24段**／**0058 面別解放ゲート**） | canon-06 §3 |
| do_card_exchange (0019→**0030**) | 交換所（カード→クリスタル・虹SPのみ・×2^★） | canon-03 §10 |
| do_card_exchange_bulk (**0052**) | 一括交換（0019/0030 をバッチ化・uuid[]・全レア対応・装備質/EXPは価値に含めない） | canon-03 §10 |
| claim_mission (0020) | ミッション報酬受領 | canon-06 §6 |
| set_card_lock (0023) | カードのロック切替 | canon-02 §7 |

- **do_kyoka の素材削除**：成功・失敗ともに**無条件削除**（0012確認済）。
- battle_logs / sp_states 更新は do_boss_battle 内。SP発動で sp_states.unavailable_until を当日末に。

## 2-1. ボス時間制出撃【実装0042–0049・確定2026-06-19】
仕様＝canon-05 §0-1／canon-06 §4・§7。
- テーブル `boss_sorties`(user_id, deck_no, boss_key, started_at, travel_sec, returning, return_until)・**RLS有効・直接SELECT不可**（`get_boss_sorties` 経由）。
- 列 `cards.boss_deck_no smallint`（null=自由/値=出撃中デッキ）。
- RPC：`start_boss_battle` / `collect_boss_result` / `cancel_boss_sortie` / `get_boss_sorties`。
- `do_boss_battle` を3引数化：`do_boss_battle(deck_no, boss_key, p_from_sortie boolean default false)`。**戦闘式は不変**（`p_from_sortie=true`＝collect経由で回数/フロンティア/占有をスキップ）。
- 共通ガード `_chikarian_assert_not_in_tansaku` を「**探索 or ボス出撃中なら拒否**」に拡張（各資産RPCは無改変で連動）。
- **【本番前リバート必須】**（test-mode 残存・feedback-tracker 2026-06-21）：(1) `travel_sec` テスト値 a=10/b=15/boss=30 → **本番 a=1200/b=1500/boss=1800**（`start_boss_battle` 内）。(2) `start_boss_battle` の**1日3回制限がコメントアウト中→戻す**。(3) クライアント **`BOSS_TEST_NO_LIMIT=true`→false**。
- **追補**：役割別travel（0044）／帰還レグ（0045）／離脱SP除外（0046）／引き分け=敗北・draw返却（0049）／面内ノード順次解放 boss_round_role（0054）。**do_boss_battle・start_boss_battle 最新=0054**。

## 3. 要追従【実装が旧・設計値へ更新要】
RPC/データは存在するが値・ロジックが旧。canon の設計値へ更新する。

**反映済み（旧要追従・2026-06-19 確認）**：★式 0.10・(装備項+本体)【0026/0032】／★成功率 素材Lv依存【0025】／竜気覚醒 **×4.0**・哀慟の眼 ×0.25【0027】／所持枠 200/+100/1000【0029】／ギア 枠コスト1/3/9/27・枠攻撃力10/15/22/34【0031/0032】／交換所レート 虹SPのみ・×2^★【0030】／三すくみ武器 盾>剣>杖【0028】／ボス曲線 面1=3,200…面8=129,300【0048】／引き分け=敗北・draw返却【0049】／**武気返却 A-2【0050】／初回配布【0051】／一括交換 do_card_exchange_bulk【0052】／面内ノード順次解放 boss_round_role【0054】／恩寵石=面ボス初回（0047副ボスを是正）【0054】／転移=埋まった枠へ上書き可【0055】／ロック本体の★強化可【0056】／探索レート24段ラダー＋周回半減 collect_tansaku【0057】／探索 面別解放ゲート（gate=cleared_stage×3+boss_round_role）start_tansaku【0058】**。

**残りの要追従**：

| 項目 | 実装の旧値 | 設計値（正） | 箇所 |
|---|---|---|---|
| 練気殿 強化費 | （未設定/仮） | Lv2:3,000／Lv3:5,000／Lv4:8,000／Lv5:12,000（計28,000） | 0015 ｜canon-06 §5-1 |
| 鍛冶屋 精製コスト | （未設定/仮） | メダル5,000（魔装は1周目運用外） | 0016 ｜canon-06 §5-2 |
| 探索 戦力ゲート | start_tansaku は面別解放(0058)済み・本体戦力ゲートは無し | 探索デッキの本体戦力合計 ≥ しきい値(面f)・武気フリー（しきい値は Phase 4 後に後続migration） | 0058 ｜canon-06 §3-2 |
| ミッションメダル | デイリー計≈8,000 | デイリー満了計≈2,500（ウィークリー/達成は据置） | 0020 ｜canon-06 §6 |
| ミッション メダル | 1日≈8,000（仮） | 1日≈2,500 | 0020/0021 ｜canon-06 §6 |

- 三すくみ係数は **0028 が最新**（0011→0028 で武器の輪を盾>剣>杖へ修正・0008中立版は旧）。

## 4. 大型機能の実装状況【占有ロック/周回/恩寵石供給＝実装済み・残＝ボス曲線】
新規SQLオブジェクト／既存RPC更新を要した大型機能。占有ロック・ボス周回・恩寵石供給は **実装済み（2026-06-19 確認）**。残る未起票はボス曲線のみ（値更新は §3「残りの要追従」に集約）。

> **マイグレーション番号の方針**：番号は **0025 以降、実装する順（＝実装引き継ぎの優先順）で採番**する。**canon は特定番号を予約しない**（順序が変わっても番号のリネームで足りる）。優先順では §3 の要追従更新（★成功率＝0025／★式＝0026…）が先で、**占有ロックは後ろの番号**に来る。

- **占有ロック（B-2）【実装済み 0033/0034】**：
  - `cards.tansaku_deck_no smallint`（null=未探索/値=探索中デッキ番号）＋`start_tansaku`/`collect_tansaku` 改修＋探索中カードのバックフィル＝**実装済み**。
  - 各資産RPC（update_deck / do_kyoka / do_skill_teni / do_skill_rensei / equip_buki / do_boss_battle / start_tansaku）は**共通ガード `_chikarian_assert_not_in_tansaku` を呼ぶ**形で実装済み（探索中カードの編成/★/スキル/充填/出撃を拒否）。**0042 でこのガードを「探索 or ボス出撃中」に拡張**＝各RPCは無改変で連動（§2-1）。
  - **start_tansaku は面別解放ゲート（0058）実装済み**（gate=cleared_stage×3+boss_round_role・gate≥step−1・`EXPLORE_LOCKED`）。**本体戦闘力ゲート（面f）は未実装＝要追従**（しきい値は Phase 4 後に後続migration・canon-06 §3-2）。※SPデッキ可（4A）は維持。
- **ボス周回エンドレス（⑦）【実装済み 0038・最新0046保持】**：`profiles.boss_round`（1〜）＋`boss_round_stage`（0〜8）を 0038 で追加。do_boss_battle のフロンティア検証（到達点以下のみ・超過は `BOSS_LOCKED`）＋面ボス勝利で前進（8到達で round++・stage=0）＋ start_boss_battle 側検証も **最新0046 が保持**。敵戦力＝base_power×round。
- **恩寵石の供給【実装済み 0054＝面ボス初回=8個】**：**面ボス初回撃破ごとに1個・1周目8個**（canon-06 §6・canon-04 §2）。実装は 0037 で面ボス→0047 が副ボスへ逸脱（ユーザー決定外）→**0054 で面ボス初回へ復帰**（v_role='boss'・v_round=1・v_stage=cleared_stage+1）＝確定どおり。`claim_mission` の hoshou 対応は維持（0020 L234）。
- **ボス曲線（0010→0048）【実装済み 0048】**：boss_master.base_power を 面1=3,200…面8=129,300（中A/中B=面ボス×0.80/0.90・×M）へ更新済み。各面の細値はシミュで微調整余地。
- ※ §3 反映済みは **0025〜0058**（最新版＝do_kyoka **0056**・do_boss_battle **0054**・update_deck **0050**・do_skill_teni **0055**・initialize_profile **0051**・collect_tansaku **0057**・start_tansaku **0058**）。**残る新規マイグレーション＝探索戦力ゲート（しきい値Phase4後）・練気殿強化費・鍛冶屋精製コスト・ミッションメダル**（§3 表）＝4件。

## 5. 適用順序の指針
- **A（既存RPC更新）→ B（新規SQL）→ C（クライアント）** の順。
- 1か所動かしたら **到達検算（canon-04/05・最大育成デッキ vs 1周目8面）** を再走。三すくみ・所持枠・発動率は相互に効くので注意。
- 探索レートは 0057 で実装済み（数値の最終分布・半減比は Phase 4 で確定／canon-05 §1）。ボス曲線は 0048 で適用済み。

## 6. 出典・改訂
- 出典：supabase-spec-2026-06-12（スキーマ部）＋ 実装 0001–0024（全SQLマイグレーション）。設計の正は canon-01〜06。
- **2026-06-17**：本書を新設し、canon-02〜06 に散在する「要追従」を §3 に集約、未実装（占有ロック・boss_round）を §4 に集約。
- **2026-06-19**：**ボス時間制出撃（実装0042）を §2-1 に追加**。占有ロック（0033/0034）を実装済みへ更新（共通ガード `_chikarian_assert_not_in_tansaku` を0042で「探索 or ボス出撃」に拡張）。実装は0042まで進行＝§2(0002–0024)・§3 のステータス表記は旧分が残るため、実装スレッドが反映時に随時更新する。
- **2026-06-19（§3 sweep）**：§3 の実装済み項目（★式/★成功率/竜気=×4.0/所持枠/ギア/交換所/三すくみ武器）を「反映済み」へ移動。§2 `update_deck` 行の「取り外しで武気返却」を訂正（A-2＝未実装）。§4 `start_tansaku` 本体戦力ゲートの「反映済み」を訂正（未実装）。残りの要追従＝ボス曲線/探索レート/初回配布/練気殿強化費/鍛冶屋精製コスト/ミッションメダル。
- **2026-06-21（0050–0056 同期）**：実装スレッドが 0050–0056 を実装＝**武気返却(0050)・初回配布(0051)・一括交換 do_card_exchange_bulk(0052)・面内ノード順次解放 boss_round_role(0054)・恩寵石=面ボス復帰(0054)・転移上書き(0055)・ロック本体★強化(0056)**。§1/§2/§3/§4 反映。最新版＝do_boss_battle 0054・update_deck 0050・do_kyoka 0056・do_skill_teni 0055・initialize_profile 0051。残り要追従＝探索レート・探索戦力ゲート・練気殿強化費・鍛冶屋精製コスト・ミッションメダル。
- **2026-06-22（0057/0058 同期）**：探索レート24段ラダー＋周回半減（collect_tansaku **0057**・`R_med=0.33+2.97×(step−1)/23`・周回半減・上限6.27/3.80）／探索 面別解放ゲート（gate=cleared_stage×3+boss_round_role・`gate≥step−1`・`EXPLORE_LOCKED`／start_tansaku **0058**）を実装済みへ。§2 版数表・§3 反映済み・§3 要追従表（探索レート行を削除・戦力ゲート行を更新）・§4 を反映。残り要追従＝探索戦力ゲート（しきい値Phase4後）・練気殿・鍛冶屋・ミッション＝4件。台帳 `schema_migrations` 0001〜0058 整備済み。
- **2026-06-19（§4 整理）**：boss_round（0038・最新0046保持）／恩寵石供給（0037・最新0046保持＋claim_mission の hoshou 対応）を **実装済み** へ更新。§4 ヘッダを実装状況ベースに改題。§1 profiles の boss_round「未実装」表記を訂正。残る大型未実装＝ボス曲線のみ（§3 と同一）。
- **2026-06-19（§2 版数更新）**：§2 RPC一覧のバージョン表記を最新版へ（do_gacha=0029・do_boss_battle=0046・do_kyoka/equip_buki/do_skill_rensei=0034・do_skill_teni=0035・start_tansaku=0036・collect_tansaku=0033・do_card_exchange=0030・update_deck=0043）。§2-1 を 0042–0046 に。
- **2026-06-19（STEP0 再同期）**：0047/0048/0049 反映。ボス曲線=**0048 実装済み**（§3反映済み/§4）。do_boss_battle 版数 0046→**0049**（引き分け=敗北・draw返却・§2/§2-1）。恩寵石は**設計=面ボス初回=8個を維持**＝**repo の0047（副ボス移管）はユーザー決定外**（→**0054 で面ボス初回へ復帰・下記 2026-06-21 項**）。
- **2026-06-19（ノード解放規則の明文化）**：面内ノードの**順次解放**（中A→中B→面ボス・1つずつ・未解放は BOSS_LOCKED）を canon-05 §0・canon-06 §4/§7 に**解放規則として明記**（モックアップ boss-mockup.html にはあったが canon 取りこぼし＝進行スレッドが面単位のみと誤読した原因）。実装（start_boss_battle/do_boss_battle のノード順ゲート）は**未実装**＝§3 残りに計上。
- 統合：本 canon-07 が supabase-spec のスキーマ/RPC部を置換（**退避候補**）。SQLファイル自体は repo の実体（退避不要・正本）。
