# Chikarian バッチ：探索2バグ修正 + 放置報酬「一括回収」
対象: `Chikarian/index.html`（このファイルのみ）。SQL実行は不要。
各編集は **検索文字列が1回だけ出現** することを確認してから置換。

## 探索（TansakuScreen）
- #7 探索中の青ぐるぐるが3か所同時稼働でも1か所しか点かない → 全デッキを見て表示。ノードタップで該当デッキを自動選択。
- #8 デッキにカードが無くても探索できる → 出発ボタンに空デッキガード＋デッキ選択に「カードなし」表示。

## 放置報酬（HouchiScreen）
- #9 「全デッキ一括回収」ボタンを追加（探索中の全デッキを順に回収）。

---

### 編集 探①decks state追加
**検索:**
```jsx
  const [states, setStates] = useState(null);
  const [deckNo, setDeckNo] = useState(1);
  const [openNode, setOpenNode] = useState(null);   // 開いているノード(depthキー) or null
```
**置換:**
```jsx
  const [states, setStates] = useState(null);
  const [decks, setDecks] = useState([]);
  const [deckNo, setDeckNo] = useState(1);
  const [openNode, setOpenNode] = useState(null);   // 開いているノード(depthキー) or null
```

### 編集 探②decks取得
**検索:**
```jsx
  const doStart = () => { const depth = openNode; setOpenNode(null); run(() => ChikarianAPI.startTansaku(deckNo, 1, depth), '探索を開始しました'); };
```
**置換:**
```jsx
  useEffect(() => { (async () => { try { setDecks(await ChikarianAPI.getDecks() || []); } catch (e) {} })(); }, []);   // デッキ編成（空デッキ判定用）
  const doStart = () => { const depth = openNode; setOpenNode(null); run(() => ChikarianAPI.startTansaku(deckNo, 1, depth), '探索を開始しました'); };
```

### 編集 探③全デッキで探索中表示+タップ自動選択
**検索:**
```jsx
        {DEPTHS.map(d => {
          const pos = TAN_NODES[d.key]; if (!pos) return null;
          const nodeBusy = curKey === d.key;
          return (
            <div key={d.key} className={'tan-node' + (nodeBusy ? ' busy' : '')} style={{ left: pos.left, top: pos.top }} onClick={() => setOpenNode(d.key)}>
              <div className="tan-dot" /><div className="tan-lbl">{pos.name}</div>
            </div>
          );
        })}
```
**置換:**
```jsx
        {DEPTHS.map(d => {
          const pos = TAN_NODES[d.key]; if (!pos) return null;
          const owner = (states || []).find(s => { const di = depthInfo(s.depth); return di && di.key === d.key; });   // この深さを探索中のデッキ（全デッキ対象）
          const nodeBusy = !!owner;
          return (
            <div key={d.key} className={'tan-node' + (nodeBusy ? ' busy' : '')} style={{ left: pos.left, top: pos.top }} onClick={() => { if (owner) setDeckNo(owner.deck_no); setOpenNode(d.key); }}>
              <div className="tan-dot" /><div className="tan-lbl">{pos.name}</div>
            </div>
          );
        })}
```

### 編集 探④selDeckCards算出
**検索:**
```jsx
  const cur = states.find(s => s.deck_no === deckNo) || null;            // 選択中デッキの探索状態（1デッキ＝1探索）
```
**置換:**
```jsx
  const cur = states.find(s => s.deck_no === deckNo) || null;            // 選択中デッキの探索状態（1デッキ＝1探索）
  const selDeckRow = (decks || []).find(d => d.deck_no === deckNo);
  const selDeckCards = selDeckRow ? [selDeckRow.slot1_card_id, selDeckRow.slot2_card_id, selDeckRow.slot3_card_id].filter(Boolean).length : 0;   // 選択中デッキの編成枚数（空デッキ判定）
```

### 編集 探⑤出発に空デッキガード
**検索:**
```jsx
<button className="tan-go" onClick={doStart} disabled={busy}>{cur ? '出発（既存分は自動回収）' : '出発'}</button>
```
**置換:**
```jsx
<button className="tan-go" onClick={doStart} disabled={busy || selDeckCards === 0}>{selDeckCards === 0 ? 'デッキにカードがありません' : (cur ? '出発（既存分は自動回収）' : '出発')}</button>
```

### 編集 探⑥選択にカードなし表示
**検索:**
```jsx
                const st = byDeck[n]; const di = st && depthInfo(st.depth);
                return (
                  <div key={n} className={'tan-deck' + (n === deckNo ? ' sel' : '')} onClick={() => setDeckNo(n)}>
                    <div className="tan-dn">デッキ{n}</div>
                    <div className="tan-dp">{di ? di.label + '探索中' : '待機'}</div>
                  </div>
                );
```
**置換:**
```jsx
                const st = byDeck[n]; const di = st && depthInfo(st.depth);
                const dr = (decks || []).find(x => x.deck_no === n); const cc = dr ? [dr.slot1_card_id, dr.slot2_card_id, dr.slot3_card_id].filter(Boolean).length : 0;
                return (
                  <div key={n} className={'tan-deck' + (n === deckNo ? ' sel' : '')} onClick={() => setDeckNo(n)}>
                    <div className="tan-dn">デッキ{n}</div>
                    <div className="tan-dp">{di ? di.label + '探索中' : (cc === 0 ? 'カードなし' : '待機')}</div>
                  </div>
                );
```

### 編集 放①collectAll関数
**検索:**
```jsx
    try { await fn(); if (okMsg) flash(okMsg); await load(); await refreshAll(); }
    catch (e) { flash(errMsg(e)); }
    finally { setBusy(false); }
  }

  if (!states) return <Booting />;
```
**置換:**
```jsx
    try { await fn(); if (okMsg) flash(okMsg); await load(); await refreshAll(); }
    catch (e) { flash(errMsg(e)); }
    finally { setBusy(false); }
  }
  async function collectAll() {
    if (busy) return;
    const active = (states || []).filter(s => s.depth).map(s => s.deck_no);
    if (active.length === 0) { flash('回収できる探索がありません'); return; }
    setBusy(true);
    let totalMedal = 0, count = 0;
    try {
      for (const n of active) { try { const r = await ChikarianAPI.collectTansaku(n); if (r) { totalMedal += Number(r.medal_gain || 0); count++; } } catch (e) {} }
      flash(`一括回収：${count}件・メダル +${totalMedal.toLocaleString()}`);
      await load(); await refreshAll();
    } finally { setBusy(false); }
  }

  if (!states) return <Booting />;
```

### 編集 放②一括回収ボタン
**検索:**
```jsx
        <div style={houS.title}>放置報酬</div>
        <div style={houS.sub}>放置＝浅域での探索（貯まった分を回収）</div>
```
**置換:**
```jsx
        <div style={houS.title}>放置報酬</div>
        <div style={houS.sub}>放置＝浅域での探索（貯まった分を回収）</div>

        {(() => { const activeN = (states || []).filter(s => s.depth).length; return (
          <button onClick={collectAll} disabled={busy || activeN === 0} style={{ width: '100%', marginTop: 14, fontFamily: 'inherit', fontWeight: 800, fontSize: 14, color: '#2a160a', border: 'none', padding: '12px 6px', borderRadius: 12, cursor: (busy || activeN === 0) ? 'default' : 'pointer', background: 'linear-gradient(180deg,#ffe49a,#e8b54d 60%,#b9842f)', opacity: (busy || activeN === 0) ? .5 : 1 }}>{activeN === 0 ? '回収できる探索がありません' : ('全デッキ一括回収（探索中 ' + activeN + '）')}</button>
        ); })()}
```
