# Claude Code 指示書：SE 初回タップ高速化 ＋ 錬成/転移/鍛冶への SE 配線

対象：`Chikarian/cksound.js`（変更1）と `Chikarian/index.html`（変更2〜4）。HEAD（cksound.js Web Audio 化・commit 6139be8 適用後）基準。

背景：
1. 現状 SE の先読みデコードを初回操作ハンドラ `_seUnlock` の中で開始しているため、**最初のタップと同時にデコードが走り、そのタップ分の音が遅れる**。`decodeAudioData` は AudioContext が suspended でも実行できるので、起動時（タイトル/オープニング段階）に先読みを始めれば、ホーム到達時にはバッファ用意済み＝**最初のタップも即時化**できる。AudioContext の解除（無音 warm up）だけはブラウザ仕様上ユーザー操作が必須だが一瞬で、タイトル画面のタップで済む。
2. 既存音源 `se_enhance_success` / `se_enhance_fail` は現状 強化（kyoka・`index.html` の KyokaView）でのみ使用。**錬成（`do_skill_rensei` は `success` を返す＝強化と同型）・転移・鍛冶受取は結果 SE が無音**のため、同じ2音を流用して配線する。

注意：**マウントが会話中に更新され、現時点で index.html の現物を指示側から再確認できていない**。各アンカーは適用前に現物と厳密一致するか必ず照合し、**不一致なら編集せず報告**すること。追加はいずれも既存ロジック不変の1行（前後）挿入のみ。成否判定・消費・スキル移動・解放処理はすべてサーバ RPC のまま不変、クライアントは SE を鳴らすだけ。

---

## 変更1（cksound.js）：起動時に SE 先読みデコードを開始

【検索（厳密一致）】
```
  window.addEventListener('pointerdown', _seUnlock);
  window.addEventListener('touchstart', _seUnlock);
  window.addEventListener('keydown', _seUnlock);
```
【置換】
```
  window.addEventListener('pointerdown', _seUnlock);
  window.addEventListener('touchstart', _seUnlock);
  window.addEventListener('keydown', _seUnlock);
  // 起動時に先読みデコード開始（初回タップ前にバッファを用意＝最初のタップも即時化）。decodeAudioData は AudioContext が suspended でも実行可。
  _PRELOAD.forEach(function (n) { _decode(n).catch(function () {}); });
```

※ `_seUnlock` 内の既存 `_PRELOAD` ループはそのまま残す（`_decode` はキャッシュ/進行中 Promise を返すため二重デコードにはならず、起動時デコード失敗時のフォールバックとして機能する）。

---

## 変更2（index.html）：錬成の成功/失敗 SE（強化と同型）

`do_skill_rensei` は `jsonb` の `success` を返すため、kyoka と同一方式で `res.success` を分岐に使う。`const res = await ...` と `setRResult(res)` の間に SE 呼び出しを1つ挿入。

【検索（厳密一致）】
```
      const res = await ChikarianAPI.doSkillRensei(base.id, selSlot, color); setRResult(res); await loadBase(); await refreshAll();
```
【置換】
```
      const res = await ChikarianAPI.doSkillRensei(base.id, selSlot, color); if (window.CKSound) CKSound.play(res && res.success ? 'se_enhance_success' : 'se_enhance_fail'); setRResult(res); await loadBase(); await refreshAll();
```
※ 行頭の空白は現物に合わせること。

---

## 変更3（index.html）：転移の成功 SE（成否確率なし＝成功時のみ）

転移は失敗が例外（SP_NOT_TRANSFERABLE 等）として throw され catch で flash 表示される型。よって `await` が解決した＝成功時のみ `se_enhance_success` を鳴らす（fail SE なし）。`await` 行の直後に1行追加。

【検索（厳密一致）】
```
      const res = await ChikarianAPI.doSkillTeni(srcId, srcSlot, base.id, dstSlot);
```
【置換】
```
      const res = await ChikarianAPI.doSkillTeni(srcId, srcSlot, base.id, dstSlot);
      if (window.CKSound) CKSound.play('se_enhance_success');  // 転移成功（失敗は throw→catch されるため SE なし）
```
※ 行頭の空白は現物に合わせること。

---

## 変更4（index.html）：鍛冶受取の成功 SE

鍛冶受取（解放）は成否確率なし。共有ヘルパ `run()` の内部は変更せず、渡す関数を async でラップして**受取成功時のみ** `se_enhance_success` を鳴らす（claim が throw した場合は SE 前に脱出）。

【検索（厳密一致）】
```
onClick={() => run(() => ChikarianAPI.claimKajiya(inProgress.id), '解放しました')}
```
【置換】
```
onClick={() => run(async () => { const _r = await ChikarianAPI.claimKajiya(inProgress.id); if (window.CKSound) CKSound.play('se_enhance_success'); return _r; }, '解放しました')}
```

---

## 確認事項
- **アンカー照合**：変更2〜4の3アンカーは適用前に現物と厳密一致を確認。一致しなければ編集せず、現行の該当ハンドラ（`rensei()` / `teni()` / 鍛冶 claim ボタン）の逐語を報告すること（並列作業で変わっている可能性に備える）。
- 先読み対象は cksound.js の `_PRELOAD`（se_tap / se_back / se_card_flip / se_enhance_success / se_enhance_fail）。変更1により起動時からデコードが進む。SE オフ時もデコードのみ走る（音は出ない＝挙動不変。オン切替後すぐ即時化される利点）。
- 変更1により AudioContext が起動時に suspended で生成される。**出力（音）は従来どおり初回ユーザー操作後のみ**。万一 iOS 等で起動時生成に問題が出た場合は、変更1で追加した2行のみ撤去すれば従来（gesture 時デコード）へ戻せる。
- 錬成＝`res.success` で成功/失敗 SE。転移・鍛冶受取＝成功（await 解決）時のみ `se_enhance_success`、失敗はエラー＝catch で flash 表示され SE なし。
- 構文確認（node --check または babel）→ `git diff` で変更1〜4の4ハンク（各数行）のみを確認 → commit & push → Ctrl+Shift+R。
- 動作確認：①タイトル画面をタップ→ホームへ。**ホームの最初のタップで `se_tap` が遅延なく鳴る**こと（初回タップ高速化）。②錬成 成功/失敗で各 SE、③転移 成功で SE、④鍛冶「受け取る（解放）」で SE が即時鳴ること。スマホ（特に iOS Safari）でも初回タップ後に遅延が無いこと。
