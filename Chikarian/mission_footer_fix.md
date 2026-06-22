# Chikarian 修正：ミッションの「ホームへ戻る」が押せない件（footerをmisS.body内側へ）

対象: `Chikarian/index.html`（このファイルのみ）。SQL不要。先に適用した mission_report_style の不具合修正です。

## 原因
- 報告書は footer が `repS.body` の内側（スクロールと同じ重なり文脈・後ろのDOMで前面に乗る）。
- ミッションは元の戻るが `misS.body` の外側（S.rootの子）にあったため、置いた footer もそこに入り、`misS.body`（zIndex:2）が前面に来てリストが footer を覆い、押せなくなっていた（footerにz-index無し）。

## 直し方
- ミッションの footer を `misS.body` の内側（リスト直後・misS.body閉じの直前）へ移動。これで報告書と同じく前面に乗り、リスト下端は footer のグラデに溶ける（侵食しない・▼がフェード）。misS.list は既に padding-bottom 90px で footer 分の余白を確保済み。

検索が1回だけ出現することを確認してから置換。検索の `repS.footer` 行は**6字下げ**（ミッション側）で、報告書側の8字下げとは別物です。

### 編集：footerをmisS.body内側へ移動
**検索:**
```jsx
      </div>
      <div style={repS.footer}><button onClick={back} style={repS.footBack}>ホームへ戻る</button></div>
    </div>
```
**置換:**
```jsx
        <div style={repS.footer}><button onClick={back} style={repS.footBack}>ホームへ戻る</button></div>
      </div>
    </div>
```
