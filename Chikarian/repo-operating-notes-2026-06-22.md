# チカリアン 運用メモ・引き継ぎ【Claude / Claude Code 共有】2026-06-22 (rev2・Code実測ベース)

> 目的：毎回つまずく「repo レイアウト・既知の落とし穴・役割分担」を1か所に固定。Claude（チャット）の記憶は Claude Code/別文脈から見えないため repo にも残す。
> 方針：**ファイル一覧を凍結して書かない**（古くなる）。「規約（置き場の約束）」＋「現状を取り直すコマンド」＋「日付つきスナップショット」で書く。最新の実態は必ず §2 のコマンドで取り直す。
> 置き場：Chikarian/ 直下（内容が増えたら canon-00-index へ統合可）。

## 1. レイアウト規約（置き場の約束・これは durable）
- repo ルート＝hanahana（Chikarian 以外に sparebeat / hibiscus 系などの別物も同居）。**ゲーム本体は `Chikarian/` 配下**。
- **マイグレーション(.sql) ＝ `Chikarian/migrations/`**（直下ではない）。新規もここに置く・コミットする。台帳SQL(`schema_migrations_setup.sql`)も migrations/ が正（直下に置かない）。
- canon ＝ `Chikarian/canon-00〜07-*.md`（直下）。
- 単一SPA ＝ `Chikarian/index.html`／API＝`chikarian-api.js`／音声＝`cksound.js`／画像＝`Chikarian/images/`／音＝`Chikarian/sounds/`。
- *.md 指示／パッチ／スケジュール／トラッカー／spec ＝ `Chikarian/` 直下。

## 2. 現状を取り直すコマンド（一覧を信じず、毎回これで確認）
Claude Code に実行させて出力を正本にする：
- フォルダ構成：`find . -maxdepth 2 -type d -not -path '*/.git*' | sort`
- 追跡ファイル：`git ls-files | sort`
- 差分（未追跡/変更/削除）：`git status --porcelain` ＋ `git ls-files --others --exclude-standard | sort`
- 現在地：`git branch --show-current ; git log --oneline -5`
- 適用済みマイグレーション台帳（DBの正）：`select version from public.schema_migrations order by version;`

## 3. 正（canon）の所在
- **正 ＝ repo の作業ツリー（ディスク状態）**。設計＝canon-01〜07／実装の現状地図＝canon-07 §3・§4／**適用済み台帳＝DBの `schema_migrations`**。
- 重要：**git 履歴 ≠ ディスク**。canon が「実装済み」と書いていても git 未コミットの場合がある（§4 参照）。git 履歴を鵜呑みにしない。

## 4. git 状態スナップショット（2026-06-22・Code実測・HEAD=f61aeae / main）
**追跡済み（git管理下）**：migrations 0001〜0041 ＋ 0046／canon-06・canon-07（のみ）／index.html・chikarian-api.js・cksound.js／各モックアップ(*-mockup.html)／旧spec(balance-*・hikitsugi-*・mission-spec・shurenjo-spec・supabase-spec・skills-*・cards-*)／images・sounds 一式。
**未追跡（要対応・notable）**：
- **canon-00-index / canon-01-worldview / canon-02-cards / canon-03-skills / canon-04-balance / canon-05-bosses**（＝中核canonが未追跡・最優先で追跡化）。
- migrations **0042〜0045・0047〜0059**／`schema_migrations_setup.sql`（migrations/）。
- 作業docの多く：chikarian-sql-schedule・meta-changelog・feedback-tracker-2026-06-20・各 *_instruction.md/*_batch.md・spec類(skill-db-spec・design-updates・boss-attr-sukumi・chikarian-crystal-exchange・chikarian-worldview・sim-instructions-2026-06-18・tansaku-ladder-spec・tansaku_ladder_client 等)・本パッチ群(canon-06/07-s3-patch・meta-changelog-patch)。
**重複・整理対象**：
- `schema_migrations_setup.sql` が **2か所**（`Chikarian/` 直下 と `Chikarian/migrations/`）→ migrations/ を正とし直下を削除。
- **0043 重複**：`0043_deck_exclusive.sql`(正) / `0043_deck_no_share.sql`(破棄=確定事項1)。
- `schema_migrations_backfill_0058.sql`（統合版に吸収）→ 削除。
- `verify-skill-db-2026-06-14.sql`：旧パス(直下)削除・新パス(migrations/)未追跡 → 移動として確定。
- バックアップ `*.local.bak`（balance/cards/hikitsugi）→ コミットせず .gitignore 推奨。
- スクラッチ候補：`dev/console.html`・`auth-test-v2.html`・`chikarian-dev.html`・BGM(.mp3 数点)→ 追跡要否はユーザー判断。
**変更あり**：`cards-chikarian-2026-06-10-0150.md`・`sounds/bgm_home.mp3`。

## 5. 既知の落とし穴（Claudeが実際に混乱した例・要警戒）
- **KBマウント(/mnt/project)は Claude Code のコミット後も古いことがある**（実例：canon-07 が 3a1c4c6 反映前のまま）。→ 適用状況・現テキストは台帳/`git ls-files`/ライブgrepで確認。**Code編集済みファイルへの次パッチは、マウントでなく最新状態（KB再アップロード後 or 自分の前パッチ出力）を基準に**。
- **静的ファイル一覧（冒頭添付や手書きの一覧）は古い**。→ §2 のコマンドで取り直す。
- **canonの「▼実装（00xx）」表記が実コードと食い違うことがある**（実例：§5-2 がゲートを「0016実装」と誤記＝実際は0059で実装）。→ コードを読んで照合。

## 6. 役割分担・ワークフロー
- 設計判断・SQL草稿・シミュ・スケジュール＝**チャット(Claude)**。
- Supabase へのSQL適用＝**ユーザーが手動で SQLエディタ Run**（資産が動くRPCは安全のため手動）。
- repoファイルの編集／コミット＝**Claude Code**（チャット指示経由）。「repoの変更はCode担当」に一本化（二重に触らない）。
- canon の KB 反映＝**ユーザー**（Codeがcanonを直したら更新後ファイルをKB再アップロード＝Claudeの参照を同期）。
- 成果物の作法：**ファイルは中身のみ（差し替え/SQL）。Codeへの貼り付け文・手順はチャットに書く**（ファイルに埋めない）。

## 7. 確定事項・原則（抜粋・正は canon／上書き禁止）
- 0043＝deck_exclusive。deck_no_share は破棄。恩寵石＝面ボス初回＝1周8個。
- 美学＝ダークファンタジー×西洋ゴシック/バロック（深紅・黒・金・紫）。和風ではない。
- 数値はコード検算（目分量禁止）。仮値はシミュ前は暫定（確定値の上書き禁止）。
- 矛盾は「事実A vs 事実B」で提示して STOP。canon に無い仕様を発明しない／canon の規則を省略しない。
