# Chikarian バッチ：ミッションの戻るを報告書スタイルに（下部の帯＋全幅「ホームへ戻る」）

対象: `Chikarian/index.html`（このファイルのみ）。SQL不要。`function MissionScreen` の戻るボタンです。

## 何を直すか
- ミッションのリストは既に内部スクロール（misS.list）だが、戻るが「小さい浮きピル（絶対配置）」でスクロール内容に被って見える。報告書（BattleLogView）は「下部の帯＋全幅ボタン」で見やすい。
- ミッションの戻るを、報告書と同じ `repS.footer`（下部固定の帯）＋ `repS.footBack`（全幅ボタン）に置き換えて完全一致。misS.body は relative+100dvh、misS.bg は #0a0509 で repS.footer のグラデと同色のため自然に馴染む。repS は module-level で MissionScreen から実行時に参照可能。
- 表示のみ。遷移先・サーバ判定は不変。

検索が1回だけ出現することを確認してから置換。

### 編集：ミッションの戻るを報告書 footer に
**検索:**
```jsx
      <button onClick={back} style={misS.back}>ホームへ戻る</button>
```
**置換:**
```jsx
      <div style={repS.footer}><button onClick={back} style={repS.footBack}>ホームへ戻る</button></div>
```
