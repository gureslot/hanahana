# Chikarian バッチ：転移の枠選択を復活（埋まった枠は上書き）+ 錬成の消費クリスタル表示
対象: `Chikarian/index.html`（このファイルのみ）。
> **このバッチは SQL 0055（do_skill_teni の上書き対応）とセットです。** 0055 を Supabase に適用しないと、埋まった枠への転移はサーバが `DST_SLOT_OCCUPIED` で弾きます。先に 0055 を適用してください。

各編集は **検索文字列が1回だけ出現** することを確認してから置換。

## 転移：枠選択ボタンを復活し、埋まった枠は上書き（入替）
- 「空き枠がありません」で止まる問題を解消。移植枠1/2を現在の中身付きで選べるようにし、埋まっていれば上書き（元のスキルは消える）。
- 前回撤去した枠選択UI（auto-pick）を、入替対応版に作り直し。

## 錬成：消費クリスタル数を表示
- スキル枠を選ぶと、消費クリスタル数（C=ceil(基礎カーブ(Lv)×レア倍率 N2/R4.4/SR8.8/SSR17.6）・色によらず同数）を表示。所持不足なら『クリスタル不足』で押せない。式はサーバ do_skill_rensei(0014) と同一。

---

### 編集 転1a 空き枠ゲート撤去
**検索:**
```jsx
          <div className="sk-hint" style={{ color: '#b6a890' }}>受け側：{bInfo.name}（空き枠 {emptySlots.length ? emptySlots.join('・') : 'なし'}）</div>
          {emptySlots.length === 0
            ? <div className="sk-banner" style={{ color: '#e87f8f', borderColor: '#b83b4d' }}>空き枠がありません（転移先なし）</div>
            : <>
```
**置換:**
```jsx
          <div className="sk-hint" style={{ color: '#b6a890' }}>受け側：{bInfo.name}（移植枠は2つ・埋まっている枠は上書き＝元のスキルは消えます）</div>
          {<>
```

### 編集 転1b 移植先枠選択UI+ボタン活性
**検索:**
```jsx
                <button onClick={() => setConfirm(true)} disabled={busy || srcId == null || srcSlot == null || emptySlots.length === 0} className="sk-cta">転移する（メダル{TENI_COST.toLocaleString()}）</button>
```
**置換:**
```jsx
                {srcId && srcSlot != null && <>
                  <div className="sk-seclabel">移植先の枠を選ぶ（埋まっている枠は上書き）</div>
                  <div className="sk-dst">
                    {[1, 2].map(s => { const cur = bySlot[s]; const cm = cur ? skillMap[cur.skill_key] : null; return (
                      <div key={s} className={'sk-dstb' + (dstSlot === s ? ' on' : '')} onClick={() => setDstSlot(s)} style={{ flexDirection: 'column', height: 'auto', padding: '8px 4px' }}>
                        <div style={{ fontWeight: 800 }}>枠{s}</div>
                        <div style={{ fontSize: 9.5, marginTop: 3, lineHeight: 1.3, color: cur ? '#e8b07a' : '#9a8c70' }}>{cur ? '上書き：' + (cm ? cm.display_name : cur.skill_key) : '空き'}</div>
                      </div>
                    ); })}
                  </div>
                </>}
                <button onClick={() => setConfirm(true)} disabled={busy || srcId == null || srcSlot == null || dstSlot == null} className="sk-cta">転移する（メダル{TENI_COST.toLocaleString()}）</button>
```

### 編集 転1c teni guard
**検索:**
```jsx
    if (busy || srcId == null || srcSlot == null || emptySlots.length === 0) return; setBusy(true);
```
**置換:**
```jsx
    if (busy || srcId == null || srcSlot == null || dstSlot == null) return; setBusy(true);
```

### 編集 転1c2 teni dst
**検索:**
```jsx
      const res = await ChikarianAPI.doSkillTeni(srcId, srcSlot, base.id, emptySlots[0]);
```
**置換:**
```jsx
      const res = await ChikarianAPI.doSkillTeni(srcId, srcSlot, base.id, dstSlot);
```

### 編集 錬2a renseiCostヘルパ
**検索:**
```jsx
const RENSEI_RATE = { blue: 10, red: 33, rainbow: 100 };   // 確定（青10/赤33/虹100）
```
**置換:**
```jsx
const RENSEI_RATE = { blue: 10, red: 33, rainbow: 100 };   // 確定（青10/赤33/虹100）
// 錬成の消費クリスタル数（サーバ do_skill_rensei=0014 と同式）：ceil(基礎カーブ(現Lv) × レア倍率 N2/R4.4/SR8.8/SSR17.6）。色によらず同数。
function renseiCost(lv, rarity) {
  const L = Math.max(1, lv || 1);
  const base = L <= 2 ? 1 : L <= 4 ? 2 : L <= 6 ? 3 : L <= 8 ? 4 : L <= 10 ? 5 : L <= 13 ? 7 : L <= 16 ? 10 : L <= 19 ? 14 : L <= 24 ? 20 : L <= 29 ? 28 : L <= 39 ? 40 : Math.round(40 * Math.pow(1.4, Math.floor((L - 40) / 10) + 1));
  const mult = { n: 2.0, r: 4.4, sr: 8.8, ssr: 17.6 }[rarity];
  return mult ? Math.ceil(base * mult) : null;
}
```

### 編集 錬2b 消費算出
**検索:**
```jsx
  const emptySlots = [1, 2].filter(s => !bySlot[s]);
```
**置換:**
```jsx
  const emptySlots = [1, 2].filter(s => !bySlot[s]);
  const rsRow = selSlot != null ? bySlot[selSlot] : null;
  const rsM = rsRow ? skillMap[rsRow.skill_key] : null;
  const rsCost = (rsRow && rsM) ? renseiCost(rsRow.skill_lv, rsM.rarity) : null;
  const rsHave = profile ? (profile['crystal_' + color] || 0) : 0;
  const rsShort = rsCost != null && rsHave < rsCost;
```

### 編集 錬2c 消費表示
**検索:**
```jsx
          <div className="sk-hint">消費クリスタル数はサーバ算出（カーブ×レア倍率）。成功＝Lv+1／失敗＝消費のみ・Lv据置。</div>
```
**置換:**
```jsx
          {rsCost != null && <div style={{ fontSize: 13, fontWeight: 700, color: rsShort ? '#ff9a8a' : '#ecd28a', margin: '6px 0 2px', textAlign: 'center' }}>消費：{COLOR_JA[color]}クリスタル <b style={{ fontSize: 17 }}>{rsCost}</b> 個（Lv{rsRow.skill_lv}→{rsRow.skill_lv + 1}・所持 {rsHave}）{rsShort ? ' ＝不足' : ''}</div>}
          <div className="sk-hint">消費はカーブ×レア倍率で色によらず同数。成功＝Lv+1／失敗＝消費のみ・Lv据置。最終判定はサーバ。</div>
```

### 編集 錬2d ボタン不足ガード
**検索:**
```jsx
          <button onClick={rensei} disabled={busy || selSlot == null} className="sk-cta">{busy ? '錬成中…' : '錬成する'}</button>
```
**置換:**
```jsx
          <button onClick={rensei} disabled={busy || selSlot == null || rsShort} className="sk-cta">{busy ? '錬成中…' : (rsShort ? 'クリスタル不足' : '錬成する')}</button>
```
