# Chikarian バッチ：放置報酬でも空デッキは「浅域で放置開始」不可に
対象: `Chikarian/index.html`（このファイルのみ）。SQL不要。
探索画面と同じく、カードが0枚のデッキでは放置開始できないようにする（HouchiScreen は decks 未取得だったので取得を追加）。
各編集は **検索文字列が1回だけ出現** することを確認してから置換。

---

### 編集 放③decks state
**検索:**
```jsx
  const [states, setStates] = useState(null);
  const [busy, setBusy] = useState(false);
  const [now, setNow] = useState(Date.now());
```
**置換:**
```jsx
  const [states, setStates] = useState(null);
  const [decks, setDecks] = useState([]);
  const [busy, setBusy] = useState(false);
  const [now, setNow] = useState(Date.now());
```

### 編集 放④decks取得
**検索:**
```jsx
  async function collectAll() {
```
**置換:**
```jsx
  useEffect(() => { (async () => { try { setDecks(await ChikarianAPI.getDecks() || []); } catch (e) {} })(); }, []);   // デッキ編成（空デッキ判定用）
  async function collectAll() {
```

### 編集 放⑤cc算出
**検索:**
```jsx
            const row = byDeck[n]; const est = tansakuEstimate(row, now); const di = row && depthInfo(row.depth);
```
**置換:**
```jsx
            const row = byDeck[n]; const est = tansakuEstimate(row, now); const di = row && depthInfo(row.depth);
            const dr = (decks || []).find(x => x.deck_no === n); const cc = dr ? [dr.slot1_card_id, dr.slot2_card_id, dr.slot3_card_id].filter(Boolean).length : 0;
```

### 編集 放⑥ピル表示
**検索:**
```jsx
                  <span style={{ ...houS.pill, ...(di ? houS.pillOn : houS.pillOff) }}>{di ? di.label + '探索中' : '未探索'}</span>
```
**置換:**
```jsx
                  <span style={{ ...houS.pill, ...(di ? houS.pillOn : houS.pillOff) }}>{di ? di.label + '探索中' : (cc === 0 ? 'カードなし' : '未探索')}</span>
```

### 編集 放⑦浅域開始ガード
**検索:**
```jsx
                  <button onClick={() => run(() => ChikarianAPI.startTansaku(n, 1, 'shallow'), '浅域で放置開始')} disabled={busy} style={{ ...S.lineBtn, flex: 1, padding: '10px 6px', ...(busy ? { opacity: .45 } : {}) }}>浅域で放置開始</button>
```
**置換:**
```jsx
                  <button onClick={() => run(() => ChikarianAPI.startTansaku(n, 1, 'shallow'), '浅域で放置開始')} disabled={busy || cc === 0} style={{ ...S.lineBtn, flex: 1, padding: '10px 6px', ...((busy || cc === 0) ? { opacity: .45 } : {}) }}>{cc === 0 ? 'カードなし' : '浅域で放置開始'}</button>
```
