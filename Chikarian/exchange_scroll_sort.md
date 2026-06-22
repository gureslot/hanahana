# Chikarian バッチ：交換所を内部スクロール化＋並び替え（レア/Lv/本体/属性/武器）
対象: `Chikarian/index.html`（このファイルのみ）。SQL不要。`function ExchangeTab` と `exS` スタイルです。

## 何を直すか
- カードリスト（exS.grid）が縦に伸びて操作しづらい問題を、リストを**内部スクロール枠**化して解消（ヘッダ/残高/操作/並び替え/一括交換バーは残り、カード一覧だけが枠内でスクロール）。高さは `calc(100dvh - 470px)`（最低180px）。
- 並び替えボタン（レア／Lv／本体／属性／武器）を追加。再押下で昇順/降順トグル、既定レア降順。card_key・カード値から算出（追加取得なし）。
- 一括交換バーは既存どおり sticky。grid が自前スクロールするため wrap の底パディングを 96→16px に縮小。
- 表示・並びのみで、交換の最終判定は従来どおりサーバ。

各編集は **検索文字列が1回だけ出現** することを確認してから置換。

---

### 編集 交X1 xSort/xDir状態
**検索:**
```jsx
  const [rates, setRates] = useState([]);
```
**置換:**
```jsx
  const [rates, setRates] = useState([]);
  const [xSort, setXSort] = useState('rarity');   // 交換所の並び替え
  const [xDir, setXDir] = useState('desc');
```

### 編集 交X2 list並び替え
**検索:**
```jsx
  const list = (cards || []);
```
**置換:**
```jsx
  const list = (() => {
    const RR = { n: 0, r: 1, sr: 2, ssr: 3, sp: 4 }, AO = { hana: 0, ha: 1, shin: 2 }, WO = { ken: 0, tate: 1, tsue: 2 };
    const dir = xDir === 'asc' ? 1 : -1, key = ['lv', 'body', 'attr', 'weap'].includes(xSort) ? xSort : 'rar';
    return (cards || [])
      .map(c => { const pk = parseCardKey(c.card_key); const pt = (c.card_key || '').split('_'); return { c, body: computeStats(c).body, rar: RR[pk.rarity] != null ? RR[pk.rarity] : 0, attr: AO[pk.attrKey] != null ? AO[pk.attrKey] : 9, weap: WO[pt[3]] != null ? WO[pt[3]] : 9, lv: c.lv || 1 }; })
      .sort((a, b) => { const d = (a[key] - b[key]) * dir; return d !== 0 ? d : (b.body - a.body); })
      .map(x => x.c);
  })();
```

### 編集 交X3 ソートUI行
**検索:**
```jsx
      <div style={exS.actions}>
        <button onClick={selectAll} style={exS.lineBtn} disabled={busy || list.length === 0}>全選択</button>
        <button onClick={clearSel} style={exS.lineBtn} disabled={busy || selIds.length === 0}>選択解除</button>
      </div>
```
**置換:**
```jsx
      <div style={exS.actions}>
        <button onClick={selectAll} style={exS.lineBtn} disabled={busy || list.length === 0}>全選択</button>
        <button onClick={clearSel} style={exS.lineBtn} disabled={busy || selIds.length === 0}>選択解除</button>
      </div>
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, alignItems: 'center', margin: '0 0 8px' }}>
        <span style={{ fontSize: 10, color: '#7d7160' }}>並び替え</span>
        {[['rarity', 'レア'], ['lv', 'Lv'], ['body', '本体'], ['attr', '属性'], ['weap', '武器']].map(([k, l]) => (
          <button key={k} onClick={() => { if (xSort === k) setXDir(d => d === 'asc' ? 'desc' : 'asc'); else { setXSort(k); setXDir('desc'); } }} style={{ fontFamily: 'inherit', fontSize: 11, fontWeight: 700, padding: '4px 9px', borderRadius: 10, cursor: 'pointer', border: '1px solid ' + (xSort === k ? '#c7a14e' : '#3a2c22'), background: xSort === k ? 'linear-gradient(180deg,#ecd28a,#c7a14e)' : '#181210', color: xSort === k ? '#0c0a09' : '#b6a890' }}>{l}{xSort === k ? (xDir === 'asc' ? ' ▲' : ' ▼') : ''}</button>
        ))}
      </div>
```

### 編集 交X4 grid内部スクロール
**検索:**
```jsx
  grid: { display: 'flex', flexWrap: 'wrap', gap: 8, justifyContent: 'flex-start' },
```
**置換:**
```jsx
  grid: { display: 'flex', flexWrap: 'wrap', gap: 8, justifyContent: 'flex-start', alignContent: 'flex-start', maxHeight: 'calc(100dvh - 470px)', minHeight: 180, overflowY: 'auto', padding: 6, borderRadius: 8, border: '1px solid rgba(232,194,90,.12)', background: 'rgba(12,8,11,.35)' },
```

### 編集 交X5 wrap底padding縮小
**検索:**
```jsx
  wrap: { padding: '4px 2px 96px' },
```
**置換:**
```jsx
  wrap: { padding: '4px 2px 16px' },
```
