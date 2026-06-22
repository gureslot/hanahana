# Chikarian バッチ：強化合成/転移の堅牢化 + 三すくみ2バッジ化
対象: `Chikarian/index.html`（このファイルのみ）。SQL実行は不要。
各編集は **検索文字列が1回だけ出現** することを確認してから置換（④aは置換先が空＝削除）。

### 編集 ①三すくみを属性/武器2バッジ化
**検索:**
```jsx
                              {(() => { const f = cardSukumiVsBoss(c, bm); if (Math.abs(f - 1) < 0.001) return null; const adv = f > 1; return <div style={{ position: 'absolute', top: 3, right: 3, zIndex: 3, fontSize: 9, fontWeight: 800, padding: '1px 5px', borderRadius: 6, color: '#fff', background: adv ? 'rgba(38,132,58,.94)' : 'rgba(168,40,52,.94)', border: '1px solid ' + (adv ? 'rgba(150,230,160,.7)' : 'rgba(255,150,150,.7)'), boxShadow: '0 1px 3px rgba(0,0,0,.6)' }}>{adv ? '有利' : '不利'}</div>; })()}
```
**置換:**
```jsx
                              {(() => {
                                if (/_sp$/.test(c.card_key || '') || !bm) return null;
                                const p = (c.card_key || '').split('_');
                                const mAttr = p[1] === 'meshibe' ? 'shin' : p[2];
                                const mWeap = p[1] === 'meshibe' ? 'tsue' : p[3];
                                let aF = 1, wF = 1;
                                (bm.attrs || []).forEach(ea => { aF *= sukumiFactor(mAttr, ea); });
                                (bm.weapons || []).forEach(ew => { wF *= sukumiFactor(mWeap, ew); });
                                const chip = (label, f) => { if (Math.abs(f - 1) < 0.001) return null; const adv = f > 1; return <span style={{ fontSize: 8, fontWeight: 800, padding: '1px 4px', borderRadius: 5, color: '#fff', whiteSpace: 'nowrap', background: adv ? 'rgba(38,132,58,.95)' : 'rgba(168,40,52,.95)', border: '1px solid ' + (adv ? 'rgba(150,230,160,.7)' : 'rgba(255,150,150,.7)'), boxShadow: '0 1px 2px rgba(0,0,0,.6)' }}>{label}{adv ? '有利' : '不利'}</span>; };
                                const aC = chip('属', aF), wC = chip('武', wF);
                                if (!aC && !wC) return null;
                                return <div style={{ position: 'absolute', top: 3, right: 3, zIndex: 3, display: 'flex', flexDirection: 'column', gap: 2, alignItems: 'flex-end' }}>{aC}{wC}</div>;
                              })()}
```

---

## ⑥ 探索中/出撃中カードを選べないように（CARD_IN_TANSAKUの根治）
強化合成picker・★強化材料・転移材料で、ボス出撃中/探索中のカードをグレーアウト＝選択不可/除外。ロック中は解除のため選択可のまま。

### 編集 ⑥a 強化picker getStatusで出撃/探索を無効化
**検索:**
```jsx
  const getStatus = (c) => ({ disabled: false, dim: false, tag: c.locked ? 'ロック中' : null });
```
**置換:**
```jsx
  const getStatus = (c) => {
    if (c.boss_deck_no != null) return { disabled: true, dim: true, tag: '出撃中', reason: 'ボスに出撃中のため強化・転移できません' };
    if (c.tansaku_deck_no != null) return { disabled: true, dim: true, tag: '探索中', reason: '探索に出撃中のため強化・転移できません' };
    return { disabled: false, dim: false, tag: c.locked ? 'ロック中' : null };
  };
```

### 編集 ⑥b リストでdisabledを選択不可
**検索:**
```jsx
                    <button key={c.id} onClick={() => setSel(c.id)} style={{ ...cpS.li, ...(sel === c.id ? cpS.liSel : {}), ...(st.dim ? { opacity: .45 } : {}) }}>
```
**置換:**
```jsx
                    <button key={c.id} onClick={() => { if (!st.disabled) setSel(c.id); }} disabled={!!st.disabled} style={{ ...cpS.li, ...(sel === c.id ? cpS.liSel : {}), ...(st.dim ? { opacity: .45 } : {}), ...(st.disabled ? { cursor: 'default' } : {}) }}>
```

### 編集 ⑥c ★強化材料から出撃/探索除外
**検索:**
```jsx
    if (c.id === base.id || c.locked) return false;
    if ((c.star || 0) !== star) return false;
```
**置換:**
```jsx
    if (c.id === base.id || c.locked) return false;
    if (c.boss_deck_no != null || c.tansaku_deck_no != null) return false;
    if ((c.star || 0) !== star) return false;
```

### 編集 ⑥d 転移材料から出撃/探索除外
**検索:**
```jsx
                  {(cards || []).filter(c => c.id !== base.id && !c.locked && !c.card_key.endsWith('_sp')).map(c => (
```
**置換:**
```jsx
                  {(cards || []).filter(c => c.id !== base.id && !c.locked && !c.card_key.endsWith('_sp') && c.boss_deck_no == null && c.tansaku_deck_no == null).map(c => (
```

### 編集 ③転移にスキル効果表示
**検索:**
```jsx
                          <button key={s.slot} onClick={() => setSrcSlot(s.slot)} className={'sk-slot' + (srcSlot === s.slot ? ' sel' : '')}>
                            <span className="pin">{s.slot === 0 ? '固定' : '空き' + s.slot}</span>
                            <div className="sk-sn">{skName(s.skill_key)} <span style={{ fontSize: 11, color: '#c7a14e' }}>Lv{s.skill_lv}</span></div>
                          </button>
```
**置換:**
```jsx
                          <button key={s.slot} onClick={() => setSrcSlot(s.slot)} className={'sk-slot' + (srcSlot === s.slot ? ' sel' : '')}>
                            <span className="pin">{s.slot === 0 ? '固定' : '空き' + s.slot}</span>
                            <div className="sk-sn">{skName(s.skill_key)} <span style={{ fontSize: 11, color: '#c7a14e' }}>Lv{s.skill_lv}</span></div>
                            {(() => { const m = skillMap[s.skill_key]; return m ? <div style={{ fontSize: 11, color: '#cdb488', marginTop: 3, lineHeight: 1.5, textAlign: 'left' }}><SkillEffect sk={m} lv={s.skill_lv} /></div> : null; })()}
                          </button>
```

---

## ④ 転移の「受け側の空き枠」ボタンを撤去（枠で効果は変わらないため自動選択）
空き枠ボタンを削除し、転移時は空き枠の先頭を自動使用。

### 編集 ④a 受け側空き枠UI削除
**検索:**
```jsx
                {srcId && srcSlot != null && <>
                  <div className="sk-seclabel">受け側の空き枠</div>
                  <div className="sk-dst">
                    {emptySlots.map(s => <div key={s} className={'sk-dstb' + (dstSlot === s ? ' on' : '')} onClick={() => setDstSlot(s)}>枠{s}</div>)}
                  </div>
                </>}


```
**置換:** （空＝削除）

### 編集 ④b teni guard 自動枠
**検索:**
```jsx
    if (busy || srcId == null || srcSlot == null || dstSlot == null) return; setBusy(true);
```
**置換:**
```jsx
    if (busy || srcId == null || srcSlot == null || emptySlots.length === 0) return; setBusy(true);
```

### 編集 ④b2 teni doSkillTeniに自動枠
**検索:**
```jsx
      const res = await ChikarianAPI.doSkillTeni(srcId, srcSlot, base.id, dstSlot);
```
**置換:**
```jsx
      const res = await ChikarianAPI.doSkillTeni(srcId, srcSlot, base.id, emptySlots[0]);
```

### 編集 ④c 転移ボタン活性条件
**検索:**
```jsx
                <button onClick={() => setConfirm(true)} disabled={busy || srcId == null || srcSlot == null || dstSlot == null} className="sk-cta">転移する（メダル{TENI_COST.toLocaleString()}）</button>
```
**置換:**
```jsx
                <button onClick={() => setConfirm(true)} disabled={busy || srcId == null || srcSlot == null || emptySlots.length === 0} className="sk-cta">転移する（メダル{TENI_COST.toLocaleString()}）</button>
```
