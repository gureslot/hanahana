# Chikarian バッチ：戻るナビの統一（ホーム直行=「ホームへ戻る」下中央／一段戻る=「‹ 戻る」左下）
対象: `Chikarian/index.html`（このファイルのみ）。SQL不要。

## 方針（承認済み）
- ホーム直行 → 「ホームへ戻る」を下・中央。
- 一段戻る → 「‹ 戻る」を左下。
- 内部スクロール画面では戻るをスクロール枠の外（常時表示）に。

## 主な変更
- **共有 CardPicker（強化合成・デッキのカード選択）**：左上にあった戻るを撤去し、画面下部へ移動。文脈で出し分け（props追加 backLabel/backCenter）：強化合成＝中央「ホームへ戻る」、デッキの枠選択＝左下「‹ 戻る」。これでご指摘の「左上の戻る」を解消。
- ボス・探索・ミッション・設定：絶対配置の戻る（左下）を下・中央＋「ホームへ戻る」に。
- ガチャ・編成・放置・建物・報告・採取・エラー画面：ラベルを「ホームへ戻る」に統一（中央寄せ）。
- カード詳細（装備/スキル/強化結果）：一段戻る系を「‹ 戻る」に統一。
- 図鑑：ページャと同じ下部バーにあるため、ラベルのみ「ホームへ戻る」に（位置は据置＝特例）。既に正しい ExchangeView/KyokaView の「‹ 戻る」（左下）は変更なし。
- すべて表示・配置のみで、遷移先・サーバ判定は不変。

各「検索」は記載の出現回数だけ存在することを確認してから置換（複数のものは全置換）。

---

### CP1 props
**検索:**
```jsx
function CardPicker({ title, cards, getStatus, chooseLabel, onChoose, onClear, actions, back, busy, flash }) {
```
**置換:**
```jsx
function CardPicker({ title, cards, getStatus, chooseLabel, onChoose, onClear, actions, back, busy, flash, backLabel = '‹ 戻る', backCenter = false }) {
```

### CP2 head戻る撤去
**検索:**
```jsx
        <div style={cpS.head}>
          <button onClick={back} style={{ ...S.lineBtn, padding: '6px 14px' }}>‹ 戻る</button>
          <div style={cpS.title}>{title}</div>
        </div>
```
**置換:**
```jsx
        <div style={cpS.head}>
          <div style={cpS.title}>{title}</div>
        </div>
```

### CP3 下部戻る追加
**検索:**
```jsx
        {onClear && <button onClick={onClear} disabled={busy} style={{ ...S.lineBtn, marginTop: 12, alignSelf: 'center', ...(busy ? { opacity: .45 } : {}) }}>この枠を空にする</button>}
      </div>
```
**置換:**
```jsx
        {onClear && <button onClick={onClear} disabled={busy} style={{ ...S.lineBtn, marginTop: 12, alignSelf: 'center', ...(busy ? { opacity: .45 } : {}) }}>この枠を空にする</button>}
        <div style={{ flex: 'none', marginTop: 12, display: 'flex', justifyContent: backCenter ? 'center' : 'flex-start' }}>
          <button onClick={back} style={backCenter ? { fontFamily: 'inherit', fontSize: 14, fontWeight: 800, color: GOLD_HI, background: PANEL, border: BORDER, borderRadius: 22, padding: '11px 28px', cursor: 'pointer' } : { ...S.lineBtn, padding: '8px 16px' }}>{backLabel}</button>
        </div>
      </div>
```

### CP4 Kyokaラベル
**検索:**
```jsx
  return <CardPicker title="強化するカードを選ぶ" cards={cards} getStatus={getStatus} actions={actions} back={back} busy={busy} flash={flash} />;
```
**置換:**
```jsx
  return <CardPicker title="強化するカードを選ぶ" cards={cards} getStatus={getStatus} actions={actions} back={back} busy={busy} flash={flash} backLabel="ホームへ戻る" backCenter={true} />;
```

### ABS1 boss-back中央
**検索:**
```jsx
.boss-back{position:absolute; z-index:7; left:14px; bottom:16px;
```
**置換:**
```jsx
.boss-back{position:absolute; z-index:7; left:50%; transform:translateX(-50%); bottom:16px;
```

### JSX boss
**検索:**
```jsx
<button className="boss-back" onClick={back}>‹ 戻る</button>
```
**置換:**
```jsx
<button className="boss-back" onClick={back}>ホームへ戻る</button>
```

### ABS2 tan-back中央
**検索:**
```jsx
.tan-back{position:absolute; z-index:9; left:14px; bottom:16px;
```
**置換:**
```jsx
.tan-back{position:absolute; z-index:9; left:50%; transform:translateX(-50%); bottom:16px;
```

### JSX tan
**検索:**
```jsx
<button className="tan-back" onClick={back}>‹ 戻る</button>
```
**置換:**
```jsx
<button className="tan-back" onClick={back}>ホームへ戻る</button>
```

### ABS3 mission/settings中央
**検索:**
```jsx
back: { position: 'absolute', zIndex: 7, left: 14, bottom: 14, fontFamily: 'inherit', fontSize: 14, color: GOLD_HI, background: PANEL, border: BORDER, borderRadius: 22, padding: '10px 20px', cursor: 'pointer' }
```
**置換:**
```jsx
back: { position: 'absolute', zIndex: 7, left: '50%', transform: 'translateX(-50%)', bottom: 14, fontFamily: 'inherit', fontSize: 14, color: GOLD_HI, background: PANEL, border: BORDER, borderRadius: 22, padding: '10px 20px', cursor: 'pointer' }
```

### JSX mission
**検索:**
```jsx
<button onClick={back} style={misS.back}>‹ 戻る</button>
```
**置換:**
```jsx
<button onClick={back} style={misS.back}>ホームへ戻る</button>
```

### JSX settings
**検索:**
```jsx
<button onClick={back} style={setS.back}>‹ 戻る</button>
```
**置換:**
```jsx
<button onClick={back} style={setS.back}>ホームへ戻る</button>
```

### FLOW gacha
**検索:**
```jsx
<button onClick={back} disabled={drawing} style={{ ...S.lineBtn, marginTop: 16 }}>ホームに戻る</button>
```
**置換:**
```jsx
<button onClick={back} disabled={drawing} style={{ ...S.lineBtn, display: 'block', margin: '16px auto 0' }}>ホームへ戻る</button>
```

### FLOW saishu
**検索:**
```jsx
<button onClick={back} style={{ ...S.bigBtn, marginTop: 30 }}>ホームに戻る</button>
```
**置換:**
```jsx
<button onClick={back} style={{ ...S.bigBtn, marginTop: 30 }}>ホームへ戻る</button>
```

### FLOW deck/houchi残り
**検索:**
```jsx
>ホームに戻る</button>
```
**置換:**
```jsx
>ホームへ戻る</button>
```

### FLOW tatemono
**検索:**
```jsx
<div className="tat-backlink" onClick={back}>‹ ホームへ戻る</div>
```
**置換:**
```jsx
<div className="tat-backlink" onClick={back}>ホームへ戻る</div>
```

### FLOW report提出
**検索:**
```jsx
{submitting ? '記録中…' : 'ホームに戻る'}
```
**置換:**
```jsx
{submitting ? '記録中…' : 'ホームへ戻る'}
```

### FLOW report footer
**検索:**
```jsx
<button onClick={back} style={repS.footBack}>‹ ホームに戻る</button>
```
**置換:**
```jsx
<button onClick={back} style={repS.footBack}>ホームへ戻る</button>
```

### FLOW errboundary
**検索:**
```jsx
}}>‹ ホームに戻る</button>
```
**置換:**
```jsx
}}>ホームへ戻る</button>
```

### FLOW zukan(特例:pages有)
**検索:**
```jsx
<button style={zS.back2} onClick={back}>‹ 戻る</button>
```
**置換:**
```jsx
<button style={zS.back2} onClick={back}>ホームへ戻る</button>
```

### STEP カード詳細(equip/skill)
**検索:**
```jsx
‹ カードに戻る
```
**置換:**
```jsx
‹ 戻る
```

### STEP kyokaView結果
**検索:**
```jsx
>カードに戻る</button>
```
**置換:**
```jsx
>‹ 戻る</button>
```
