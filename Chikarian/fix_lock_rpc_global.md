# Chikarian 修正：LOCK_RPC_AVAILABLE をグローバル定義（強化合成 真っ暗の修正）

対象: `Chikarian/index.html`（このファイルのみ）。SQL実行は不要。

`KyokaScreen` が参照している `LOCK_RPC_AVAILABLE` が `CardDetail` 関数内のローカル定義しか無く、強化合成でカードを選んだ瞬間に `ReferenceError` で画面が落ちていた。グローバルに1つ定義する。

検索文字列が **1回だけ出現** することを確認してから置換すること。

### 編集（グローバルLOCK定義を追加）

**検索:**
```jsx
const DAILY_MAX = 1000;
```

**置換:**
```jsx
const DAILY_MAX = 1000;
const LOCK_RPC_AVAILABLE = false;   // ロック切替RPC(0023)が本番適用されたら true に。強化合成のactionsがこれを参照しており、未定義だとカード選択時に真っ暗になる
```
