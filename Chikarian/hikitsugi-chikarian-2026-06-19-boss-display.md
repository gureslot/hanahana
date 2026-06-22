# チカリアン 引き継ぎ（2026-06-19・ボス時間制＋カード表示の章）

> このmdは新スレッドの冒頭に貼る用。**会話履歴に依存せず**、canon（KB）＋このmdを権威ソースとして続行できるように書いてある。数値は本番前の暫定が多い。

---

## 0. 大前提（毎回守る運用ルール）
- **repoが常に正**（`C:\Users\justi\projects\hanahana\Chikarian`）。チャットにコード添付せず、**repo経由 or Claude Code に読ませる**。GitHub Pages（gureslot/hanahana、パス `Chikarian/`）で配信。
- 役割分担：**このアシスタント（Claude）が設計・SQL執筆・仕様策定**を担当、**Claude Code が実ファイル編集＋commit/push**。**SQLはユーザーが Supabase SQL Editor に貼って適用**（Claude Codeはファイルとコミットのみ）。
- **資産が動く処理は全てサーバRPC、全テーブルRLS有効、認証=Google。**
- 確定値の上書き禁止／停止指示遵守／運用§11厳守。
- 応答は**敬体**。ユーザーは簡潔（「1」「OK」「次」）。**各判断ポイントに具体推薦を1つ**。長い説明・不要な複雑さは避ける。
- **実装ファイル照合が最優先**：設計仮定の前に必ず該当 canon と SQL を読む。前提の発明は厳禁（ユーザーが最重要視）。

### ファイル取得のコツ（重要）
- **`/mnt/project` は KB のミラーで“古くなる”**。最新の実ファイルは **raw で取得**：
  `https://raw.githubusercontent.com/gureslot/hanahana/main/Chikarian/index.html`（`chikarian-api.js` も同様）。**github.io は bash から不可**。GitHub API はレート制限が速い。
- **migrations の置き場が不統一**：0035 は `Chikarian/migrations/0035_*.sql`（raw 200）だが **0042 は `migrations/` に無く 404**。**0042 は KB（/mnt/project）にしか無い**ことがある。SQLを base にする時は **KB か raw のどちらにあるか先に確認**。
- canon（canon-00〜07）・sim-*・meta-changelog は **KBのみ（repo未コミット）**。これは「実装/配信の正=repo、設計/意図の最新=KB+チャット」という**意図的な軸**（meta-changelog に記録済み）。差分＝「決まったが未着地」の作業キュー。

### 技術スタック / ローカル
- React/Babel SPA（**index.html 単一ファイル＝一枚岩**）、Supabase（RLS下のRPC）、GitHub Pages。
- ローカル：`python -m http.server 5500` → `http://127.0.0.1:5500/index.html`（file:// はOAuth不可）。
- **毎回の落とし穴：push後は必ずハードリロード（Ctrl+Shift+R）**。古いキャッシュで「直ってるのに再現」が頻発（特に chikarian-api.js）。
- **Babelの構文チェックは実行時 ReferenceError を捕まえない**。画面が真っ暗＝大抵 **props 分割代入漏れ／削除した変数への参照**。コンソールのエラーを見る／コンポーネントの signature と本文を grep。

---

## 1. 確定済みの主要設計値（変更禁止）
- デッキコスト上限：**11**。レアコスト **N1/R2/SR3/SSR5/SP4**（card_key 末尾で判定）。
- ★式：`総合=(装備項+本体)×(1+0.10×★)`、本体はLvのみ（★非依存）。
- 三すくみ：有利×1.2／不利×0.8（乗算）。戦闘＝純粋決定論（戦力比較のみ・確率なし）、引分は敗北扱い・表示"Draw"。
- 装備項 = **loaded_buki × 枠攻撃力(qatk)**。本体はLv依存。武気はバトルで損失率ぶん減（SPは無傷）。
- 武気：`cards.loaded_buki`（込めた武気＝枠数）、`cards.quality`（crude/refined/enchanted/holy・SP=NULL）、プール `renkiden.buki_stored`。充填RPC **`equip_buki(card_id, quality, 枠数)`**（非破壊：現状をプールに戻して引き直す。amount=0でアンロード）。qatk: crude7/refined15/enchanted33/holy73。
- SPカード本体ベース3,200（MAX9,600）。竜気覚醒×4.0／哀慟の眼×0.25（発動5%・コスト4）。
- インベントリ上限 `least(200+100×cleared_stage, 1000)`。
- デッキ本数 `least(2 + cleared_stage/2, 6)`。
- **デッキは「1カード＝1デッキ・共有不可」**（canon-06）。`decks` テーブル（user_id, deck_no, slot1/2/3_card_id）。
- 探索：SPカード不可、門番は本体戦闘力のみ。占有ロック＝`cards.tansaku_deck_no`。EXP は各カードに全量付与。
- 探索の停止＝`collect_tansaku`（蓄積回収＝デッキ解放。“破棄”は無い）。ボスのキャンセル＝`cancel_boss_sortie`（挑戦回数返却）。
- スキルLvは青天井（クリスタル合成）。スキル移植：レア制限なし。めしべスキルはめしべ間のみ／通常スキルはめしべ空きへ可（逆不可）。

---

## 2. いま完了していること（このスレッドまで）
### ボス＝時間制出撃（往路→到着→復路→解放）※下の3が今回の核
- 旧「即時 do_boss_battle」→**時間制出撃**へ移行済み（0042）。出撃→往路→到着で**戦闘＆報告書記録**→**復路**→デッキ解放。**撃ちっぱなし**（手動「結果を見る」廃止・結果ポップアップ廃止）。結果は既存**戦闘報告書(BattleLogView)** にボス名＋イラスト付きで自動記録。
- マップのノードピン＝`ic_map_subboss`(中ボス)/`ic_map_boss`(面ボス)。ボスイラスト `boss_<面>_<役割>.png` は**報告書**に表示。
- 出撃シートで**デッキを内容（カード絵＋名前＋総合戦力 computeStats）つき**で選択。出撃ピル（左上）にゲージ。キャンセル＝経過分だけ折り返し（`return_until = now()+経過`）。
- **ホームでも毎秒判定で自動回収**（pass①のD修正済み）。`bossLivePhase`/`bossSortieName` はモジュール関数。
- デッキ重複バグ修正（0043）：update_deck に**クロスデッキ排他**（編成カードを他デッキから自動で外す＝移動）＋既存二重編成の一度きり掃除。クライアントは**保存ボタン廃止＝即確定**、他デッキ在籍カードは**移動確認モーダル**、同一デッキ重複＆**探索/出撃中カードはグレーアウト**。
- 出撃/探索の管理：**ホームのピルから／編成画面のバナーから**キャンセル（帰還）・回収して戻す（pass①のA・C）。

### カード表示（pass① items 5・6・7／コミット f0eb6c6・実機未確認）
- **レアバッジ廃止**（CardThumb 左上の RAR_LABEL オーバーレイ削除）。**名前に付与**：`cardFullName(card)=RAR_LABEL+name+attr+weap`（例「SSRめしべだけマン芯杖」）。使用：CardDetail タイトル／出撃シートのデッキ内容名／カード選択パネル各サムネ下。CardThumb 下帯は Lv/★ のみ。
- **カード枠を2:3に統一**（5/7→2/3）：CardThumb・zukan item・zukan detail・deck slot・CSS .gcard・CSS .boss-deck2Empty。ボスイラスト(1:1)・報告書(4/3)は未変更。
- **帰還/回収に確認モーダル**：DeckScreen バナーのボタン（boss=帰還/tansaku=回収）に「はい/いいえ」。ホームのピル管理シートにも同様。

---

## 3. 【最優先・新スレッドで最初にやる】未適用の作業
> いずれも私が成果物を出し済み。**SQLはユーザーがSupabaseに貼る／クライアントはClaude Codeに渡す**。push後ハードリロードで実機確認。

### (A) SQL 0044：ボス所要時間を役割別テスト値に
- ファイル：`0044_boss_travel_by_role.sql`（成果物として出力済み。中身は start_boss_battle を 0042 base で再定義し travel_sec を役割分岐）。
- 値：**中ボスA=10s / 中ボスB=15s / 面ボス=30s**。本番値 a=1200/b=1500/boss=1800 はコメント併記（暫定）。
- **テストハック**：このファイルでは**1日3回制限をコメントアウト（OFF）**（現行ライブと整合）。本番で復活。
- **未適用なら Supabase で Run。**

### (B) SQL 0045：ボスに「復路（帰り道）」を追加（←ユーザーの直近要望の核）
- ファイル：`0045_boss_return_leg.sql`（出力済み）。`collect_boss_result` を差し替え。
- 仕様：**到着時に即解放しない**。到着で `do_boss_battle(...,true)`（戦闘＋報告書）→ `is_returning=true, return_until = started_at + 2×travel_sec`（復路＝往路と同じ）。**復路ぶん経ってから解放**。離席で往復とも過ぎていれば回収時に戦闘＋即解放(home:true)。`get_boss_sorties`/`cancel`/`start` は変更不要。
- **未適用なら Supabase で Run。**

### (C) クライアント：phase別collect（0045と対・必須）
- **これが無いと新フローでデッキが永久に「帰還中」になる**（今の自動回収は1出撃 `deck_no:started_at` で1回しか collect しない＝到着で回収後、帰宅の回収がスキップ）。
- 修正：Home と BossScreen の自動回収で **collectedRef のキーに live phase を含める** → `${s.deck_no}:${s.started_at}:${L.phase}`（L=bossLivePhase）。'arrived'(到着→戦闘＋帰還中へ)と'return_done'(帰宅→解放)を**各1回ずつ** collect。collect 成功後 getBossSorties 再取得＋onRefresh。
- フラッシュ：到着(returning:true)「デッキN 到着・帰還中（報告書に記録）」／帰宅(home:true)・キャンセル(canceled:true)「デッキN 帰還」。
- 保持：fleetBoss は live phase 'out'/'returning' を数える。帰還中ゲージ分母 (return_until − started_at)/2。
- **Claude Code 指示文は前スレッド末尾にある**（コミット例: `fix(client): collect boss sortie at both arrival and home (per-phase) for return leg`）。未適用なら渡す。

> ★効率化メモ（ユーザー要望）：Claude Code の指示文には「**破壊的操作以外は止まるな／確認は既定yes**」を明記し、**独立変更は1セッションにまとめて**起動回数を減らす。触る関数・行を具体指定して探索時間を削る。

---

## 4. 次の章（区切り後にやる・独立した「表示」系）
### ② 出撃シートにカード詳細（武気充填＋スキル表示）
- 方針（ユーザー了承済み「タップで詳細でOK」）：
  - 出撃シートの各カードに**武気の充填状況**を小さく表示（quality＋loaded_buki枠／SPは「装備なし」）→出撃前に積み忘れ・半端が見える。
  - カードを**タップ→既存 CardDetail をオーバーレイ表示**（スキル＋スキルLvが見える＝詳細／「装備（充填）」ボタンから equip_buki で武気充填）。戻るで出撃シートに復帰。
  - CardDetail は BossScreen からオーバーレイで描画可（props: card, cards, profile, skillMap, refreshAll, back, flash。skillMap=getSkillMaster、他はBossScreenが保持）。
- SQL不要（equip_buki 既存）。

### 図鑑／強化レイアウト刷新（カオス解消）
- 図鑑：今の**横長フルアート重なり**が見づらい → **カード選択を左一覧＋右詳細**に統一（強化の本体選び・デッキ枠選び・スキル転移元選びを同じ形に）。図鑑リストは縦型カード＋レア/属性/武器/★を明示（※レアは名前に入った＝item5。整合をとる）。
- 強化（kyoka）画面の整理。**`kyokaS.boxEmpty`（強化の空き素材枠）が5/7のまま**（item6の6箇所リスト外）→CardThumbと並ぶので2:3に揃えるか要判断。
- これはカードが見やすくなった後にまとめて。**規模が大きいので1回の大きめ指示**で出す方針。

### カード選択パネルの名前表示（item5の積み残し）
- 4列グリッドで fontSize:8 と小さめ。長い名前（「SSRめしべだけマン芯杖」）は折り返す。**窮屈なら文字サイズ/省略表示を調整**（ユーザー確認待ち）。

---

## 5. 本番前に必ず戻すテストハック（3点）
1. **サーバ：start_boss_battle の1日3回制限がOFF**（0044 でコメントアウト。本番でコメント解除＝`if v_boss_count >= 3 then raise ...`）。
2. **クライアント：BOSS_TEST_NO_LIMIT = true**（BossScreen のテスト用バイパス。false/削除）。コミット 249c792 由来。
3. **travel_sec がテスト短縮値**（0044：a=10/b=15/boss=30）→本番 a=1200/b=1500/boss=1800（暫定・調整可）。
- 付随：**チカリウム手動投入**（`update profiles set chikarium=1000000`）はデータ投入なので戻す必要なし（残してOK）。

---

## 6. やり取り・落とし穴の学び
- **会話は遡れるが高コスト**。引き継ぎ本体は canon＋このmd。
- ボスは全工程で最も荒れた領域。**1修正ごとに実機確認**してから次へ。
- **ハンドオフ事故**：props省略でブランクスクリーン複数回（cards・refreshAll）。新規propを足したら App 側の `<Component .../>` と分割代入の両方を必ず確認。
- **PG予約語に注意**（`returning` で踏んだ→`is_returning` に改名。JSONキーは 'returning' のまま）。
- 既存RPCを再利用するSQLは**現行版をrawかKBから取得してコピー**（250行超を打ち直さない＝正しさ維持）。
- 効率化の現実：同一 index.html を複数 Claude Code で**同時編集すると衝突**。本格並列化したいなら**index.html を画面単位ファイルに分割**（一回の投資で以後ずっと並列可）。設計・SQL・仕様書きは複数スレッドで並列OK。

---

## 7. 直近のコミット
- f0eb6c6 … pass① items 5・6・7（レアバッジ廃止＋名前へ／2:3枠／帰還・回収の確認）。実機未確認。
- （その前）出撃管理 pass①A/C・D修正、0043デッキ排他＋即確定UI、0042ボス時間制、等。

## 8. ファイル一覧の作り方
- repo 全ファイルは `Chikarian/_filelist.md`（KBにあり）。images/sounds/migrations の棚卸し済み。
