# Claude Code 指示書：⑪ 建物「交換所」タブ＋一括交換（File 2）

対象2ファイル：`Chikarian/chikarian-api.js`（編集1・2）と `Chikarian/index.html`（編集3〜5）。文字列アンカー一致。編集5箇所。ExchangeTab は Babel(JSX) 検証済み。
前提：Supabase に `0052_card_exchange_bulk.sql`（一括交換RPC）が適用済みであること。
目的（ユーザー確定）：交換所を1枚ずつではなく、**建物に「交換所」タブを新設し、一覧から複数選択→一括交換**にする。レート/価値はサーバ準拠（getExchangeRates）。ロック中・探索/ボス出撃中は除外。破壊的操作のため確認モーダルあり。

---

## 【chikarian-api.js】編集1：doCardExchangeBulk ラッパーを追加

【検索（厳密一致）】
```
  const doCardExchange  = (cardId)                         => rpc('do_card_exchange',  { p_card_id: cardId });
```
【置換】
```
  const doCardExchange  = (cardId)                         => rpc('do_card_exchange',  { p_card_id: cardId });
  const doCardExchangeBulk = (cardIds)                     => rpc('do_card_exchange_bulk', { p_card_ids: cardIds }); // 0052: 一括交換
```

---

## 【chikarian-api.js】編集2：エクスポートに doCardExchangeBulk を追加

【検索（厳密一致）】
```
    startTansaku, collectTansaku, useExpBook, doCardExchange, claimMission,
```
【置換】
```
    startTansaku, collectTansaku, useExpBook, doCardExchange, doCardExchangeBulk, claimMission,
```

---

## 【index.html】編集3：exS ＋ ExchangeTab を TatemonoScreen の直前に挿入

【検索（厳密一致）】
```
function TatemonoScreen({ profile, cards, refreshAll, back, flash }) {
```
【置換】
```jsx
const exS = {
  wrap: { padding: '4px 2px 96px' },
  head: { marginBottom: 8 },
  title: { fontFamily: "'Shippori Mincho',serif", fontSize: 18, fontWeight: 700, color: GOLD_HI },
  sub: { fontSize: 12, color: '#a98f66', marginTop: 2, lineHeight: 1.5 },
  bal: { fontSize: 12, color: '#cdb488', margin: '8px 0', padding: '6px 10px', borderRadius: 8, border: '1px solid rgba(232,194,90,.2)', background: 'rgba(20,12,16,.5)' },
  result: { fontSize: 12, color: '#bfe6c0', margin: '6px 0', padding: '8px 10px', borderRadius: 8, border: '1px solid rgba(95,165,100,.4)', background: 'rgba(24,48,28,.4)', lineHeight: 1.6 },
  actions: { display: 'flex', gap: 8, margin: '8px 0 6px' },
  lineBtn: { padding: '5px 12px', borderRadius: 8, border: '1px solid rgba(232,194,90,.4)', background: 'rgba(20,12,16,.6)', color: '#d8c19a', fontSize: 12, cursor: 'pointer' },
  empty: { color: '#a98f66', fontSize: 13, padding: 24, textAlign: 'center' },
  grid: { display: 'flex', flexWrap: 'wrap', gap: 8, justifyContent: 'flex-start' },
  card: { width: 90, padding: 4, borderRadius: 10, border: '1px solid rgba(232,194,90,.2)', background: 'rgba(20,12,16,.5)', cursor: 'pointer', textAlign: 'center', boxSizing: 'border-box' },
  cardOn: { borderColor: '#e8c25a', background: 'rgba(232,194,90,.16)', boxShadow: '0 0 8px rgba(232,194,90,.3)' },
  cardArt: { position: 'relative', width: 82, height: 123, borderRadius: 7, overflow: 'hidden', margin: '0 auto' },
  check: { position: 'absolute', top: 4, right: 4, width: 22, height: 22, borderRadius: '50%', background: 'linear-gradient(180deg,#e8c25a,#b8901f)', color: '#1a1014', fontWeight: 900, fontSize: 14, display: 'grid', placeItems: 'center', boxShadow: '0 1px 4px rgba(0,0,0,.5)' },
  cardName: { fontSize: 11, color: '#efe2c8', marginTop: 4, fontWeight: 700 },
  cardCx: { fontSize: 11, color: '#cdb488', marginTop: 1 },
  bar: { position: 'sticky', bottom: 0, marginTop: 10, padding: '10px 8px', display: 'flex', flexDirection: 'column', gap: 8, background: 'linear-gradient(180deg,rgba(14,9,12,0),rgba(14,9,12,.94) 28%)' },
  barTot: { fontSize: 13, color: '#efe2c8', textAlign: 'center' },
  exBtn: { width: '100%', padding: 12, borderRadius: 10, border: 'none', background: 'linear-gradient(180deg,#e8c25a,#b8901f)', color: '#1a1014', fontWeight: 800, fontSize: 15, cursor: 'pointer' },
  exOff: { opacity: .45, cursor: 'default' },
};

function ExchangeTab({ profile, cards, refreshAll, flash }) {
  const [rates, setRates] = useState([]);
  const [sel, setSel] = useState({});
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState(null);
  const [confirm, setConfirm] = useState(false);
  useEffect(() => { (async () => { try { setRates(await ChikarianAPI.getExchangeRates() || []); } catch (e) { setRates([]); } })(); }, []);

  // 交換可能カード（ロック中・探索/ボス出撃中は除外）
  const list = (cards || []).filter(c => !c.locked && c.tansaku_deck_no == null && c.boss_deck_no == null);
  const rateOf = (c) => (rates || []).find(r => r.rarity === parseCardKey(c.card_key).rarity) || null;
  const estOf = (c) => { const r = rateOf(c); return r ? { color: r.crystal_color, count: Math.max(0, Math.round(r.base_value_blue * (1 + (r.star_coeff || 0) * (c.star || 0)) / (r.divisor || 1))) } : null; };

  const selIds = Object.keys(sel).filter(id => sel[id]);
  const tot = { blue: 0, red: 0, rainbow: 0 };
  selIds.forEach(id => { const c = (cards || []).find(x => x.id === id); if (!c) return; const e = estOf(c); if (e) tot[e.color] = (tot[e.color] || 0) + e.count; });

  const toggle = (id) => setSel(s => ({ ...s, [id]: !s[id] }));
  const selectAll = () => { const m = {}; list.forEach(c => { m[c.id] = true; }); setSel(m); };
  const clearSel = () => setSel({});

  async function doExchange() {
    if (selIds.length === 0) { flash('交換するカードを選んでください'); return; }
    setBusy(true); setResult(null);
    try {
      const res = await ChikarianAPI.doCardExchangeBulk(selIds);
      setResult(res); setSel({});
      await refreshAll();
    } catch (e) { flash(errMsg(e)); }
    finally { setBusy(false); }
  }

  return (
    <div style={exS.wrap}>
      <div style={exS.head}>
        <div style={exS.title}>交換所</div>
        <div style={exS.sub}>不要なカードをクリスタルに交換します。複数選択して一括交換。ロック中・探索/ボス出撃中のカードは除外されます。</div>
      </div>
      <div style={exS.bal}>所持クリスタル：青 {Number((profile && profile.crystal_blue) || 0).toLocaleString()}／赤 {Number((profile && profile.crystal_red) || 0).toLocaleString()}／虹 {Number((profile && profile.crystal_rainbow) || 0).toLocaleString()}</div>
      {result && <div style={exS.result}>交換完了：{result.exchanged} 枚{result.skipped ? '（' + result.skipped + ' 枚はロック/出撃中で除外）' : ''}。獲得 青+{result.blue_gained}／赤+{result.red_gained}／虹+{result.rainbow_gained}</div>}
      <div style={exS.actions}>
        <button onClick={selectAll} style={exS.lineBtn} disabled={busy || list.length === 0}>全選択</button>
        <button onClick={clearSel} style={exS.lineBtn} disabled={busy || selIds.length === 0}>選択解除</button>
      </div>
      {list.length === 0
        ? <div style={exS.empty}>交換できるカードがありません</div>
        : <div style={exS.grid}>
            {list.map(c => {
              const e = estOf(c); const on = !!sel[c.id]; const info = parseCardKey(c.card_key);
              return (
                <button key={c.id} onClick={() => toggle(c.id)} style={{ ...exS.card, ...(on ? exS.cardOn : {}) }}>
                  <div style={exS.cardArt}><DeckSlotArt cardKey={c.card_key} />{on && <div style={exS.check}>✓</div>}</div>
                  <div style={exS.cardName}>{RAR_LABEL[info.rarity]}{(c.star || 0) > 0 ? '★' + (c.star || 0) : ''}</div>
                  <div style={exS.cardCx}>{e ? COLOR_JA[e.color] + '+' + e.count : '—'}</div>
                </button>
              );
            })}
          </div>}
      <div style={exS.bar}>
        <div style={exS.barTot}>選択 {selIds.length} 枚 ／ 見込み 青+{tot.blue}・赤+{tot.red}・虹+{tot.rainbow}</div>
        <button onClick={() => setConfirm(true)} disabled={busy || selIds.length === 0} style={{ ...exS.exBtn, ...((busy || selIds.length === 0) ? exS.exOff : {}) }}>{busy ? '交換中…' : '一括交換'}</button>
      </div>
      {confirm && (
        <div style={deckS.mScrim} onClick={() => setConfirm(false)}>
          <div style={deckS.mBox} onClick={e => e.stopPropagation()}>
            <div style={deckS.mTitle}>一括交換の確認</div>
            <div style={deckS.mMsg}>選択した {selIds.length} 枚をクリスタルに交換します。<br />カードは消滅し、元に戻せません。<br />獲得見込み：青+{tot.blue}／赤+{tot.red}／虹+{tot.rainbow}</div>
            <div style={deckS.mBtns}>
              <button style={deckS.mCancel} onClick={() => setConfirm(false)} disabled={busy}>やめる</button>
              <button style={deckS.mMove} onClick={() => { setConfirm(false); doExchange(); }} disabled={busy}>{busy ? '交換中…' : '交換する'}</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function TatemonoScreen({ profile, cards, refreshAll, back, flash }) {
```

---

## 【index.html】編集4：建物のタブ配列に「交換所」を追加

【検索（厳密一致）】
```
          {[['renkiden', '練気殿'], ['kajiya', '鍛冶屋'], ['shurenjo', '修練場']].map(([k, label]) => (
```
【置換】
```
          {[['renkiden', '練気殿'], ['kajiya', '鍛冶屋'], ['shurenjo', '修練場'], ['exchange', '交換所']].map(([k, label]) => (
```

---

## 【index.html】編集5：交換所タブのレンダを追加（shurenjo の直後）

【検索（厳密一致）】
```
        {tab === 'shurenjo' && <ShurenjoView profile={profile} cards={cards} flash={flash} />}
```
【置換】
```
        {tab === 'shurenjo' && <ShurenjoView profile={profile} cards={cards} flash={flash} />}
        {tab === 'exchange' && <ExchangeTab profile={profile} cards={cards} refreshAll={refreshAll} flash={flash} />}
```

---

## 確認事項
- 交換所タブ＝所持カードをカード絵グリッドで表示→タップで複数選択（✓）→下部に「選択枚数／獲得見込み（青/赤/虹）」→「一括交換」→確認モーダル→`doCardExchangeBulk`。
- 見込みクリスタルは `getExchangeRates()`（サーバ準拠）で算出：round(base_value_blue×(1+star_coeff×★)÷divisor)。N→青/R→赤/SR・SSR・SP→虹。
- 一覧は **ロック中・探索/ボス出撃中を除外**（RPC側でも二重に安全スキップ）。交換後 refreshAll で一覧/所持クリスタルが更新。
- 確認モーダルは deckS のモーダルスタイルを流用。errMsg/COLOR_JA/RAR_LABEL/DeckSlotArt/parseCardKey は既存。
- ExchangeView（カード詳細の旧・単体交換）は⑩で導線を外したため未使用（定義は残置・無害）。
- 適用後 commit & push → Ctrl+Shift+R。建物→交換所→カード複数選択→一括交換。
