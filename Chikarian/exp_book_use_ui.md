# Chikarian バッチ：経験の書（EXP本）の使用UI ＝ 強化合成で所持数表示＋使用
対象: `Chikarian/index.html`（このファイルのみ）。**SQL不要**（use_exp_book は 0009 で適用済み）。

## 何をするか
- 強化合成のカード選択（共有 CardPicker）で、選択カードの右ペインに「経験の書」セクションを追加。EXP進捗（次のLvまで cur/20×lv）＋小/中/大/特大の所持数＋使用ボタン（×1）。使用で `useExpBook(cardId,size,1)` → 全更新。Lv上限到達時は「Lv上限に到達しています」。
- props（books/onUseBook）で**強化合成のときだけ**表示（KyokaScreen から渡す）。デッキ編成の CardPicker には出さない。
- 書EXP＝小10/中50/大200/特大1000、必要EXP＝20×Lv、Lv上限＝N30/R40/SR50/SSR60・SP50、余剰は破棄（すべて 0009 のサーバ仕様どおり・クライアントは表示と呼び出しのみ）。

各「検索」が1回だけ出現することを確認してから置換。index.html 以外は変更しない。

---

### EXP1 props
**検索:**
```jsx
function CardPicker({ title, cards, getStatus, chooseLabel, onChoose, onClear, actions, back, busy, flash, backLabel = '‹ 戻る', backCenter = false }) {
```
**置換:**
```jsx
function CardPicker({ title, cards, getStatus, chooseLabel, onChoose, onClear, actions, back, busy, flash, backLabel = '‹ 戻る', backCenter = false, books = null, onUseBook = null }) {
```

### EXP2 経験の書パネル
**検索:**
```jsx
                  </div>
                  <div style={cpS.rightFoot}>
```
**置換:**
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
                  </div>
                  <div style={cpS.rightFoot}>
```

### EXP3 cpSスタイル
**検索:**
```jsx
  rightFoot: { padding: '10px 12px', borderTop: '1px solid rgba(232,194,90,.18)', background: 'rgba(10,6,9,.6)', display: 'flex', flexDirection: 'column', gap: 8 },
```
**置換:**
```jsx
  rightFoot: { padding: '10px 12px', borderTop: '1px solid rgba(232,194,90,.18)', background: 'rgba(10,6,9,.6)', display: 'flex', flexDirection: 'column', gap: 8 },
  expBox: { marginTop: 12, padding: '10px 12px', border: '1px solid rgba(232,194,90,.25)', borderRadius: 10, background: 'rgba(0,0,0,.25)' },
  expTitle: { fontSize: 12, fontWeight: 800, color: GOLD_HI, letterSpacing: 1, marginBottom: 6 },
  expCap: { fontSize: 12, color: '#b6a890', textAlign: 'center', padding: '6px 0' },
  expProg: { fontSize: 11, color: '#d8c19a', marginBottom: 4 },
  expBar: { height: 6, borderRadius: 4, background: 'rgba(255,255,255,.08)', overflow: 'hidden', marginBottom: 8 },
  expFill: { height: '100%', background: 'linear-gradient(90deg,#e8b54d,#ffe39a)' },
  expBtns: { display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 6 },
  expBtn: { fontFamily: 'inherit', fontSize: 12, fontWeight: 700, color: GOLD_HI, background: PANEL, border: BORDER, borderRadius: 10, padding: '7px 8px', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4 },
  expBtnOff: { opacity: .4, cursor: 'default' },
  expEv: { fontSize: 10, color: '#8fd3a0' },
  expHave: { fontSize: 10, color: '#b6a890' },
```

### EXP4 useBook関数
**検索:**
```jsx
    try { await ChikarianAPI.setCardLock(c.id, !c.locked); await refreshAll(); } catch (e) { flash(errMsg(e)); } finally { setBusy(false); }
  }
  const actions = (c) => {
```
**置換:**
```jsx
    try { await ChikarianAPI.setCardLock(c.id, !c.locked); await refreshAll(); } catch (e) { flash(errMsg(e)); } finally { setBusy(false); }
  }
  async function useBook(c, size) {
    setBusy(true);
    try { await ChikarianAPI.useExpBook(c.id, size, 1); await refreshAll(); } catch (e) { flash(errMsg(e)); } finally { setBusy(false); }
  }
  const actions = (c) => {
```

### EXP5 props渡し
**検索:**
```jsx
  return <CardPicker title="強化するカードを選ぶ" cards={cards} getStatus={getStatus} actions={actions} back={back} busy={busy} flash={flash} backLabel="ホームへ戻る" backCenter={true} />;
```
**置換:**
```jsx
  return <CardPicker title="強化するカードを選ぶ" cards={cards} getStatus={getStatus} actions={actions} back={back} busy={busy} flash={flash} backLabel="ホームへ戻る" backCenter={true} books={{ s: (profile && profile.exp_book_s) || 0, m: (profile && profile.exp_book_m) || 0, l: (profile && profile.exp_book_l) || 0, xl: (profile && profile.exp_book_xl) || 0 }} onUseBook={useBook} />;
```
