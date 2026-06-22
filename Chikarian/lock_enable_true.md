# Chikarian 修正：ロック機能を有効化（LOCK_RPC_AVAILABLE = true）

対象: `Chikarian/index.html`（このファイルのみ）。SQL実行は不要（0023 適用済み前提）。

0023(set_card_lock) を Supabase に適用済みのため、グローバルの `LOCK_RPC_AVAILABLE` を `true` にする。これで強化合成のカード選択→右パネルの「ロックする／ロック解除」ボタンが押せるようになり、押すと `ChikarianAPI.setCardLock`（= RPC `set_card_lock`）が実行される。

※ 対象は**列0のグローバル行（コメント付き）**のみ。`CardDetail` 内のインデント付きローカル定義（未使用デッドコード）は触らない。

検索文字列が **1回だけ出現** することを確認してから置換すること。

### 編集（グローバルLOCKを true 化）

**検索:**
```jsx
const LOCK_RPC_AVAILABLE = false;   // ロック切替RPC(0023)が本番適用されたら true に。強化合成のactionsがこれを参照しており、未定義だとカード選択時に真っ暗になる
```

**置換:**
```jsx
const LOCK_RPC_AVAILABLE = true;    // 0023(set_card_lock) 適用済み＝有効。強化合成のactions/ロックボタンが参照
```
