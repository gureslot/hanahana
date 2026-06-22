# Chikarian 経験の書ポップアップ化＋★強化ロック解除＋表示修正＋帰還キャンセル修正

対象: `Chikarian/index.html`（このファイルのみ）。**SQL 0056 を Supabase で実行**（★強化のロック中本体許可）。

## 目的（4件）
1. **経験の書UIをポップアップ化**：右ペインの隠れがちなインラインパネルを撤去。★強化の横に「経験値付与」ボタンを置き、押すとポップアップで個数入力＋各サイズ投入。
2. **★強化はロック中でも可**：★強化は素材だけ消えて本体は消えないため、「（ロック中）」表示と無効化を撤去（サーバも 0056 で BASE_LOCKED 撤去・素材ロック MATERIAL_LOCKED は維持）。
3. **「次のLvまで 4200/420」修正**：cards.exp は累積総EXPが真値。進捗＝`exp − 10×lv×(lv−1)`、必要＝`20×lv`。Lv21・exp4200 なら「0 / 420」。
4. **デッキ編成のキャンセル（帰還）が ALREADY_RETURNING になるバグ**：帰還中デッキで握って「既に帰還中です」と案内＋再取得（編成画面は sortie の phase を持たないため握り対応）。

各検索は1回だけ出現することを確認してから置換してください。S2 は置換ではなく**該当ブロックを削除**です。


### 編集1：S1 state
**検索:**
```jsx
  const [selSkills, setSelSkills] = useState(null);
```
**置換:**
```jsx
  const [selSkills, setSelSkills] = useState(null);
  const [expOpen, setExpOpen] = useState(false);
  const [expQty, setExpQty] = useState(1);
```

### 編集2：S2 インラインパネル撤去
**検索:**
```jsx
                    {onUseBook && books && (() => {
                      const lv = selCard.lv || 1; const atCap = lv >= selStats.cap;
                      const need = 20 * lv; const cur = selCard.exp || 0;
                      const SZ = [['s', '小', 10], ['m', '中', 50], ['l', '大', 200], ['xl', '特大', 1000]];
                      return (
                        <div style={cpS.expBox}>
                          <div style={cpS.expTitle}>経験の書でレベルアップ</div>
                          {atCap
                            ? <div style={cpS.expCap}>Lv上限に到達しています</div>
                            : <><div style={cpS.expProg}>次のLvまで {cur} / {need}</div><div style={cpS.expBar}><div style={{ ...cpS.expFill, width: Math.min(100, Math.round(cur / need * 100)) + '%' }} /></div></>}
                          <div style={cpS.expBtns}>
                            {SZ.map(([k, lab, ev]) => { const n = books[k] || 0; const off = busy || atCap || n <= 0; return <button key={k} onClick={() => onUseBook(selCard, k)} disabled={off} style={{ ...cpS.expBtn, ...(off ? cpS.expBtnOff : {}) }}>{lab}<span style={cpS.expEv}>+{ev}</span><span style={cpS.expHave}>残{n}</span></button>; })}
                          </div>
                        </div>
                      );
                    })()}

```
→ **この検索ブロックを削除**（置換テキストなし）。

### 編集3：S3 rightFoot再構成
**検索:**
```jsx
                  <div style={cpS.rightFoot}>
                    {actions
                      ? actions(selCard).map((a, i) => <button key={i} onClick={a.onClick} disabled={a.disabled} style={{ ...cpS.actBtn, ...(a.tone === 'lock' ? cpS.actLock : {}), ...(a.disabled ? cpS.actOff : {}) }}>{a.label}</button>)
                      : (selStatus.disabled
```
**置換:**
```jsx
                  <div style={cpS.rightFoot}>
                    {actions
                      ? (onUseBook && books
                          ? (() => { const acts = actions(selCard); const first = acts[0]; const rest = acts.slice(1); return <>
                              <div style={{ display: 'flex', gap: 8 }}>
                                {first && <button onClick={first.onClick} disabled={first.disabled} style={{ ...cpS.actBtn, flex: 1, ...(first.disabled ? cpS.actOff : {}) }}>{first.label}</button>}
                                <button onClick={() => { setExpQty(1); setExpOpen(true); }} disabled={busy} style={{ ...cpS.actBtn, flex: 1, ...(busy ? cpS.actOff : {}) }}>経験値付与</button>
                              </div>
                              {rest.map((a, i) => <button key={i} onClick={a.onClick} disabled={a.disabled} style={{ ...cpS.actBtn, ...(a.tone === 'lock' ? cpS.actLock : {}), ...(a.disabled ? cpS.actOff : {}) }}>{a.label}</button>)}
                            </>; })()
                          : actions(selCard).map((a, i) => <button key={i} onClick={a.onClick} disabled={a.disabled} style={{ ...cpS.actBtn, ...(a.tone === 'lock' ? cpS.actLock : {}), ...(a.disabled ? cpS.actOff : {}) }}>{a.label}</button>))
                      : (selStatus.disabled
```

### 編集4：S4 モーダル追加
**検索:**
```jsx
}>{backLabel}</button>
        </div>
      </div>
    </div>
  );
}
```
**置換:**
```jsx
}>{backLabel}</button>
        </div>
        {expOpen && selCard && books && onUseBook && (() => {
          const lv = selCard.lv || 1; const atCap = lv >= selStats.cap;
          const thr = 10 * lv * (lv - 1); const prog = Math.max(0, (selCard.exp || 0) - thr); const need = 20 * lv;
          const SZ = [['s', '小', 10], ['m', '中', 50], ['l', '大', 200], ['xl', '特大', 1000]];
          const maxHave = Math.max(books.s || 0, books.m || 0, books.l || 0, books.xl || 0);
          return (
            <div style={cpS.modalBack} onClick={() => setExpOpen(false)}>
              <div style={cpS.modal} onClick={e => e.stopPropagation()}>
                <div style={cpS.modalTitle}>経験の書でレベルアップ</div>
                <div style={cpS.modalCard}>{RAR_LABEL[selInfo.rarity]} {selInfo.name}　Lv {lv} / {selStats.cap}</div>
                {atCap
                  ? <div style={cpS.expCap}>Lv上限に到達しています</div>
                  : <>
                      <div style={cpS.expProg}>次のLvまで {prog} / {need}</div>
                      <div style={cpS.expBar}><div style={{ ...cpS.expFill, width: Math.min(100, Math.round(prog / need * 100)) + '%' }} /></div>
                      <div style={cpS.qtyRow}>
                        <span style={cpS.qtyLab}>個数</span>
                        <button style={cpS.qtyBtn} onClick={() => setExpQty(q => Math.max(1, q - 1))} disabled={busy}>−</button>
                        <input type="number" value={expQty} min={1} onChange={e => setExpQty(Math.max(1, parseInt(e.target.value, 10) || 1))} style={cpS.qtyInput} />
                        <button style={cpS.qtyBtn} onClick={() => setExpQty(q => Math.min(Math.max(1, maxHave), q + 1))} disabled={busy}>＋</button>
                      </div>
                      <div style={cpS.expBtns}>
                        {SZ.map(([k, lab, ev]) => { const n = books[k] || 0; const off = busy || n < expQty; return <button key={k} onClick={() => onUseBook(selCard, k, expQty)} disabled={off} style={{ ...cpS.expBtn, ...(off ? cpS.expBtnOff : {}) }}>{lab}<span style={cpS.expEv}>+{ev}</span><span style={cpS.expHave}>残{n}</span></button>; })}
                      </div>
                    </>}
                <button style={cpS.modalClose} onClick={() => setExpOpen(false)}>閉じる</button>
              </div>
            </div>
          );
        })()}
      </div>
    </div>
  );
}
```

### 編集5：S5 modalスタイル
**検索:**
```jsx
  expHave: { fontSize: 10, color: '#b6a890' },
```
**置換:**
```jsx
  expHave: { fontSize: 10, color: '#b6a890' },
  modalBack: { position: 'fixed', inset: 0, zIndex: 60, background: 'rgba(0,0,0,.66)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 16 },
  modal: { width: '100%', maxWidth: 360, background: 'linear-gradient(180deg,#1a0f15,#120a10)', border: '1px solid rgba(232,194,90,.4)', borderRadius: 16, padding: '16px 16px 14px', boxShadow: '0 12px 40px rgba(0,0,0,.6)' },
  modalTitle: { fontSize: 15, fontWeight: 800, color: GOLD_HI, letterSpacing: 1, textAlign: 'center', marginBottom: 8 },
  modalCard: { fontSize: 12, color: '#d8c19a', textAlign: 'center', marginBottom: 10 },
  qtyRow: { display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, margin: '10px 0' },
  qtyLab: { fontSize: 11, color: '#b6a890' },
  qtyBtn: { fontFamily: 'inherit', fontSize: 16, fontWeight: 800, color: GOLD_HI, background: PANEL, border: BORDER, borderRadius: 8, width: 34, height: 34, cursor: 'pointer' },
  qtyInput: { width: 56, textAlign: 'center', fontFamily: 'inherit', fontSize: 15, fontWeight: 700, color: GOLD_HI, background: 'rgba(0,0,0,.3)', border: BORDER, borderRadius: 8, padding: '6px 4px' },
  modalClose: { width: '100%', marginTop: 12, fontFamily: 'inherit', fontSize: 13, fontWeight: 700, color: '#d8c19a', background: 'rgba(255,255,255,.06)', border: '1px solid rgba(232,194,90,.3)', borderRadius: 10, padding: '9px 0', cursor: 'pointer' },
```

### 編集6：S6 ★強化ロック解除
**検索:**
```jsx
      { label: '★強化' + (c.locked ? '（ロック中）' : ''), disabled: busy || !!c.locked, onClick: () => { setCard(c); setMode('kyoka'); } },
```
**置換:**
```jsx
      { label: '★強化', disabled: busy, onClick: () => { setCard(c); setMode('kyoka'); } },
```

### 編集7：S7 useBook個数
**検索:**
```jsx
  async function useBook(c, size) {
    setBusy(true);
    try { await ChikarianAPI.useExpBook(c.id, size, 1); await refreshAll(); } catch (e) { flash(errMsg(e)); } finally { setBusy(false); }
  }
```
**置換:**
```jsx
  async function useBook(c, size, qty = 1) {
    setBusy(true);
    try { await ChikarianAPI.useExpBook(c.id, size, qty); await refreshAll(); } catch (e) { flash(errMsg(e)); } finally { setBusy(false); }
  }
```

### 編集8：S8 ALREADY_RETURNING握り
**検索:**
```jsx
    try { await ChikarianAPI.cancelBossSortie(deckNo); await loadDecks(); await refreshAll(); flash('引き返します（帰還中）'); }
    catch (e) { flash(errMsg(e)); } finally { setBusy(false); }
```
**置換:**
```jsx
    try { await ChikarianAPI.cancelBossSortie(deckNo); await loadDecks(); await refreshAll(); flash('引き返します（帰還中）'); }
    catch (e) { if (String((e && e.message) || e).includes('ALREADY_RETURNING')) { await loadDecks(); await refreshAll(); flash('このデッキは既に帰還中です'); } else { flash(errMsg(e)); } } finally { setBusy(false); }
```