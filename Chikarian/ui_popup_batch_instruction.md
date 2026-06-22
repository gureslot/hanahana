# Claude Code 統合指示書：UIポップアップ／スキル表示パス（一括適用）

対象：`Chikarian/index.html`（⑩⑪適用後・HEAD基準）。**全10編集を文字列アンカー一致で順次適用**してください。各 検索文字列は本文中に**1回だけ**出現します。修正版を文脈込みで Babel(JSX) パース検証済み。`chikarian-api.js` の変更はありません。

## 目的（ユーザー確定）
- **ページ遷移を減らす**：強化合成の中間カード詳細ページ廃止／ボスのカードタップは詳細ページでなく**ポップアップ**。
- **スキルを各画面で見せる**：読み取り専用ポップアップ `CardPopup`（カード絵＋Lv/★＋本体戦闘力＋充填＋**スキル名・効果・Lv**／操作ボタンなし）を新設し、ボス・デッキ・交換所のカードから開けるように。
- **交換所で育成済みが分かる**：各カードに **Lv/★** を表示＋ⓘでスキル確認。
- **「選ぶ」ボタンをスクロール不要に**：左右ピッカーの操作ボタンを下部固定。

---

## 編集1. CardPicker：右パネルを「スクロール領域＋固定フッター」化＋actions対応（cpS+CardPicker 全置換）

【検索】
```jsx
const cpS = {
  wrap: { position: 'relative', zIndex: 2, width: '100%', maxWidth: 960, boxSizing: 'border-box', margin: '0 auto', padding: '12px 8px 20px', display: 'flex', flexDirection: 'column', minHeight: '100%' },
  head: { display: 'flex', alignItems: 'center', gap: 12, marginBottom: 10 },
  title: { fontFamily: "'Shippori Mincho',serif", fontSize: 18, fontWeight: 700, color: GOLD_HI, letterSpacing: '.04em' },
  facetRow: { display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 6, alignItems: 'center' },
  chip: { padding: '4px 10px', borderRadius: 999, border: '1px solid rgba(232,194,90,.35)', background: 'rgba(20,12,16,.6)', color: '#d8c19a', fontSize: 12, cursor: 'pointer', whiteSpace: 'nowrap' },
  chipSel: { background: 'linear-gradient(180deg,#e8c25a,#b8901f)', color: '#1a1014', borderColor: '#e8c25a', fontWeight: 700 },
  sortLab: { fontSize: 11, color: '#a98f66', marginRight: 2 },
  split: { display: 'flex', gap: 8, flex: 1, minHeight: 0, width: '100%', minWidth: 0, marginTop: 4 },
  left: { flex: '0 0 38%', maxWidth: 196, minWidth: 0, boxSizing: 'border-box', overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 6, paddingRight: 4, maxHeight: '66vh' },
  empty: { color: '#a98f66', fontSize: 13, padding: 20, textAlign: 'center' },
  li: { display: 'flex', gap: 8, alignItems: 'center', padding: 6, borderRadius: 10, border: '1px solid rgba(232,194,90,.18)', background: 'rgba(20,12,16,.5)', cursor: 'pointer', textAlign: 'left', width: '100%', boxSizing: 'border-box' },
  liSel: { borderColor: '#e8c25a', background: 'rgba(232,194,90,.14)', boxShadow: '0 0 8px rgba(232,194,90,.25)' },
  liArt: { width: 54, height: 81, flex: '0 0 54px', borderRadius: 7, overflow: 'hidden', position: 'relative' },
  liInfo: { display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0 },
  liLv: { fontSize: 12, fontWeight: 700, color: '#efe2c8', whiteSpace: 'nowrap' },
  liTag: { fontSize: 10, color: '#cdb488', padding: '1px 6px', borderRadius: 6, border: '1px solid rgba(232,194,90,.25)', alignSelf: 'flex-start', whiteSpace: 'nowrap' },
  right: { flex: '1 1 0', minWidth: 0, boxSizing: 'border-box', overflowY: 'auto', overflowX: 'hidden', maxHeight: '66vh', border: '1px solid rgba(232,194,90,.2)', borderRadius: 12, background: 'rgba(14,9,12,.55)', padding: 12 },
  ph: { color: '#a98f66', fontSize: 14, textAlign: 'center', padding: '40px 10px', lineHeight: 1.8 },
  dArt: { width: 120, height: 180, margin: '0 auto 10px', borderRadius: 10, overflow: 'hidden', boxShadow: '0 4px 18px rgba(0,0,0,.5)' },
  dName: { fontFamily: "'Shippori Mincho',serif", fontSize: 16, fontWeight: 700, color: '#efe2c8', textAlign: 'center', marginBottom: 10, overflowWrap: 'anywhere' },
  dRow: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8, padding: '7px 2px', borderBottom: '1px solid rgba(232,194,90,.12)', fontSize: 13, color: '#cdb488' },
  dv: { color: '#efe2c8', fontWeight: 700, textAlign: 'right', overflowWrap: 'anywhere', minWidth: 0 },
  skTitle: { marginTop: 12, marginBottom: 6, fontSize: 13, fontWeight: 700, color: GOLD_HI, letterSpacing: '.04em' },
  skMuted: { fontSize: 12, color: '#a98f66', padding: '4px 0' },
  skList: { display: 'flex', flexDirection: 'column', gap: 6 },
  skItem: { padding: '7px 9px', borderRadius: 9, border: '1px solid rgba(232,194,90,.16)', background: 'rgba(20,12,16,.5)' },
  skHead: { fontSize: 10, color: '#a98f66', marginBottom: 2 },
  skLv: { color: '#cdb488' },
  skName: { fontSize: 13, fontWeight: 700, color: '#efe2c8', overflowWrap: 'anywhere' },
  skEff: { fontSize: 11, color: '#cdb488', marginTop: 2, lineHeight: 1.5, overflowWrap: 'anywhere', wordBreak: 'break-word' },
  skEmpty: { fontSize: 12, color: '#7a6750' },
  choose: { marginTop: 14, width: '100%', padding: 12, borderRadius: 10, border: 'none', background: 'linear-gradient(180deg,#e8c25a,#b8901f)', color: '#1a1014', fontWeight: 800, fontSize: 15, cursor: 'pointer' },
  dLock: { marginTop: 14, padding: 11, borderRadius: 10, border: '1px solid rgba(200,80,80,.4)', background: 'rgba(60,20,24,.4)', color: '#e9a6a6', fontSize: 13, textAlign: 'center' },
};

function CardPicker({ title, cards, getStatus, chooseLabel, onChoose, onClear, back, busy, flash }) {
  const [sel, setSel] = useState(null);
  const [facet, setFacet] = useState('attr');
  const [fval, setFval] = useState('all');
  const [sortField, setSortField] = useState('body');
  const [sortDir, setSortDir] = useState('desc');
  const [skillMap, setSkillMap] = useState({});
  const [selSkills, setSelSkills] = useState(null);
  const cardById = {}; (cards || []).forEach(c => { cardById[c.id] = c; });

  useEffect(() => { (async () => { try { const sm = await ChikarianAPI.getSkillMaster(); const m = {}; (sm || []).forEach(s => { m[s.skill_key] = s; }); setSkillMap(m); } catch (e) {} })(); }, []);
  useEffect(() => {
    let live = true; setSelSkills(null);
    if (sel != null) { (async () => { try { const s = await ChikarianAPI.getCardSkills(sel) || []; if (live) setSelSkills(s); } catch (e) { if (live) setSelSkills([]); } })(); }
    return () => { live = false; };
  }, [sel]);

  const rawRar = k => k.endsWith('_sp') ? 'sp' : k.split('_').pop();
  const rawAttr = k => k.endsWith('_sp') ? 'sp' : k.split('_')[2];
  const rawWeap = k => k.endsWith('_sp') ? null : k.split('_')[3];
  const rawSpec = k => k.endsWith('_sp') ? 'sp' : k.split('_')[1];
  const RAR_ORD = { n: 0, r: 1, sr: 2, ssr: 3, sp: 4 };
  const FACETS = {
    attr: { label: '属性', vals: [['hana', '花'], ['shin', '芯'], ['ha', '葉'], ['sp', 'SP']] },
    weap: { label: '武器', vals: [['ken', '剣'], ['tate', '盾'], ['tsue', '杖']] },
    rarity: { label: 'レア', vals: [['n', 'N'], ['r', 'R'], ['sr', 'SR'], ['ssr', 'SSR'], ['sp', 'SP']] },
    species: { label: '種族', vals: [['hibiscus', 'ハイビスカス'], ['meshibe', 'めしべ'], ['sp', 'SP']] },
  };
  const FACET_ORDER = ['attr', 'weap', 'rarity', 'species'];
  const matchFacet = k => fval === 'all' ? true : facet === 'attr' ? rawAttr(k) === fval : facet === 'weap' ? rawWeap(k) === fval : facet === 'rarity' ? rawRar(k) === fval : rawSpec(k) === fval;
  const items = (cards || []).filter(c => matchFacet(c.card_key));
  const bodyOf = c => computeStats(c).body;
  const sval = c => sortField === 'rarity' ? (RAR_ORD[rawRar(c.card_key)] || 0) : sortField === 'lv' ? (c.lv || 1) : bodyOf(c);
  const dir = sortDir === 'asc' ? 1 : -1;
  items.sort((a, b) => (sval(a) - sval(b)) * dir || ((RAR_ORD[rawRar(b.card_key)] || 0) - (RAR_ORD[rawRar(a.card_key)] || 0)) || a.card_key.localeCompare(b.card_key));

  const SORTS = [['body', '本体戦闘力'], ['lv', 'レベル'], ['rarity', 'レア']];
  const arrow = f => sortField === f ? (sortDir === 'asc' ? ' ▲' : ' ▼') : '';
  const onSort = k => { if (sortField === k) setSortDir(d => d === 'asc' ? 'desc' : 'asc'); else { setSortField(k); setSortDir('desc'); } };

  const selCard = sel != null ? cardById[sel] : null;
  const selStatus = selCard ? getStatus(selCard) : null;
  const selInfo = selCard ? parseCardKey(selCard.card_key) : null;
  const selStats = selCard ? computeStats(selCard) : null;
  const selCap = selCard ? bukiCapacity(selCard) : 0;
  const bySlot = {}; (selSkills || []).forEach(s => { bySlot[s.slot] = s; });

  return (
    <div style={S.root}>
      <div style={S.bg} /><div style={S.vignette} />
      <div style={cpS.wrap}>
        <div style={cpS.head}>
          <button onClick={back} style={{ ...S.lineBtn, padding: '6px 14px' }}>‹ 戻る</button>
          <div style={cpS.title}>{title}</div>
        </div>
        <div style={cpS.facetRow}>
          {FACET_ORDER.map(f => <button key={f} onClick={() => { setFacet(f); setFval('all'); }} style={{ ...cpS.chip, ...(facet === f ? cpS.chipSel : {}) }}>{FACETS[f].label}</button>)}
        </div>
        <div style={cpS.facetRow}>
          <button onClick={() => setFval('all')} style={{ ...cpS.chip, ...(fval === 'all' ? cpS.chipSel : {}) }}>すべて</button>
          {FACETS[facet].vals.map(([k, l]) => <button key={k} onClick={() => setFval(k)} style={{ ...cpS.chip, ...(fval === k ? cpS.chipSel : {}) }}>{l}</button>)}
        </div>
        <div style={cpS.facetRow}>
          <span style={cpS.sortLab}>並び替え</span>
          {SORTS.map(([k, l]) => <button key={k} onClick={() => onSort(k)} style={{ ...cpS.chip, ...(sortField === k ? cpS.chipSel : {}) }}>{l}{arrow(k)}</button>)}
        </div>
        <div style={cpS.split}>
          <div style={cpS.left}>
            {items.length === 0
              ? <div style={cpS.empty}>該当カードなし</div>
              : items.map(c => {
                  const st = getStatus(c);
                  return (
                    <button key={c.id} onClick={() => setSel(c.id)} style={{ ...cpS.li, ...(sel === c.id ? cpS.liSel : {}), ...(st.dim ? { opacity: .45 } : {}) }}>
                      <div style={cpS.liArt}><DeckSlotArt cardKey={c.card_key} /></div>
                      <div style={cpS.liInfo}>
                        <span style={cpS.liLv}>Lv{c.lv || 1}{(c.star || 0) > 0 ? ' ★' + (c.star || 0) : ''}</span>
                        {st.tag && <span style={cpS.liTag}>{st.tag}</span>}
                      </div>
                    </button>
                  );
                })}
          </div>
          <div style={cpS.right}>
            {!selCard
              ? <div style={cpS.ph}>← 左の一覧から<br />カードを選ぶと<br />詳細が出ます</div>
              : <>
                  <div style={cpS.dArt}><DeckSlotArt cardKey={selCard.card_key} /></div>
                  <div style={cpS.dName}>{RAR_LABEL[selInfo.rarity]} {selInfo.name}</div>
                  <div style={cpS.dRow}><span>レベル</span><span style={cpS.dv}>Lv {selCard.lv || 1} / 上限 {selStats.cap}</span></div>
                  <div style={cpS.dRow}><span>強化値</span><span style={cpS.dv}>★{selCard.star || 0}</span></div>
                  <div style={cpS.dRow}><span>本体戦闘力</span><span style={cpS.dv}>{selStats.body.toLocaleString()}</span></div>
                  {!selStats.isSp && <div style={cpS.dRow}><span>充填（武気）</span><span style={cpS.dv}>{(selCard.loaded_buki || 0)} / {selCap} 枠</span></div>}
                  <div style={{ ...cpS.dRow, borderBottom: 'none' }}><span>コスト</span><span style={cpS.dv}>{COST_BY_RAR[selInfo.rarity] || 0}</span></div>
                  <div style={cpS.skTitle}>スキル</div>
                  {selSkills === null
                    ? <div style={cpS.skMuted}>読込中…</div>
                    : <div style={cpS.skList}>
                        {[0, 1, 2].map(slot => {
                          if (selStats.isSp && slot > 0) return null;
                          const row = bySlot[slot]; const m = row ? skillMap[row.skill_key] : null;
                          return (
                            <div key={slot} style={cpS.skItem}>
                              <div style={cpS.skHead}>{slot === 0 ? '固定スキル' : '移植スロット' + slot}{row && <span style={cpS.skLv}>・Lv{row.skill_lv}</span>}</div>
                              {row
                                ? <><div style={cpS.skName}>{m ? m.display_name : row.skill_key}</div>{m && m.notes && <div style={cpS.skEff}>{m.notes}</div>}</>
                                : <div style={cpS.skEmpty}>（空き）</div>}
                            </div>
                          );
                        })}
                      </div>}
                  {selStatus.disabled
                    ? <div style={cpS.dLock}>{selStatus.reason || selStatus.tag || '選べません'}</div>
                    : <button onClick={() => onChoose(selCard)} disabled={busy} style={{ ...cpS.choose, ...(busy ? { opacity: .5 } : {}) }}>{typeof chooseLabel === 'function' ? chooseLabel(selCard) : chooseLabel}</button>}
                </>}
          </div>
        </div>
        {onClear && <button onClick={onClear} disabled={busy} style={{ ...S.lineBtn, marginTop: 12, alignSelf: 'center', ...(busy ? { opacity: .45 } : {}) }}>この枠を空にする</button>}
      </div>
    </div>
  );
}

```
【置換】
```jsx
const cpS = {
  wrap: { position: 'relative', zIndex: 2, width: '100%', maxWidth: 960, boxSizing: 'border-box', margin: '0 auto', padding: '12px 8px 20px', display: 'flex', flexDirection: 'column', minHeight: '100%' },
  head: { display: 'flex', alignItems: 'center', gap: 12, marginBottom: 10 },
  title: { fontFamily: "'Shippori Mincho',serif", fontSize: 18, fontWeight: 700, color: GOLD_HI, letterSpacing: '.04em' },
  facetRow: { display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 6, alignItems: 'center' },
  chip: { padding: '4px 10px', borderRadius: 999, border: '1px solid rgba(232,194,90,.35)', background: 'rgba(20,12,16,.6)', color: '#d8c19a', fontSize: 12, cursor: 'pointer', whiteSpace: 'nowrap' },
  chipSel: { background: 'linear-gradient(180deg,#e8c25a,#b8901f)', color: '#1a1014', borderColor: '#e8c25a', fontWeight: 700 },
  sortLab: { fontSize: 11, color: '#a98f66', marginRight: 2 },
  split: { display: 'flex', gap: 8, flex: 1, minHeight: 0, width: '100%', minWidth: 0, marginTop: 4 },
  left: { flex: '0 0 38%', maxWidth: 196, minWidth: 0, boxSizing: 'border-box', overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 6, paddingRight: 4, maxHeight: '66vh' },
  empty: { color: '#a98f66', fontSize: 13, padding: 20, textAlign: 'center' },
  li: { display: 'flex', gap: 8, alignItems: 'center', padding: 5, borderRadius: 10, border: '1px solid rgba(232,194,90,.18)', background: 'rgba(20,12,16,.5)', cursor: 'pointer', textAlign: 'left', width: '100%', boxSizing: 'border-box' },
  liSel: { borderColor: '#e8c25a', background: 'rgba(232,194,90,.14)', boxShadow: '0 0 8px rgba(232,194,90,.25)' },
  liArt: { width: 54, height: 81, flex: '0 0 54px', borderRadius: 7, overflow: 'hidden', position: 'relative' },
  liInfo: { display: 'flex', flexDirection: 'column', gap: 4, minWidth: 0 },
  liLv: { fontSize: 12, fontWeight: 700, color: '#efe2c8', whiteSpace: 'nowrap' },
  liTag: { fontSize: 10, color: '#cdb488', padding: '1px 6px', borderRadius: 6, border: '1px solid rgba(232,194,90,.25)', alignSelf: 'flex-start', whiteSpace: 'nowrap' },
  right: { flex: '1 1 0', minWidth: 0, boxSizing: 'border-box', maxHeight: '66vh', border: '1px solid rgba(232,194,90,.2)', borderRadius: 12, background: 'rgba(14,9,12,.55)', display: 'flex', flexDirection: 'column', overflow: 'hidden' },
  rightScroll: { flex: 1, minHeight: 0, overflowY: 'auto', overflowX: 'hidden', padding: 12 },
  rightFoot: { padding: '10px 12px', borderTop: '1px solid rgba(232,194,90,.18)', background: 'rgba(10,6,9,.6)', display: 'flex', flexDirection: 'column', gap: 8 },
  ph: { color: '#a98f66', fontSize: 14, textAlign: 'center', padding: '40px 10px', lineHeight: 1.8 },
  dArt: { width: 120, height: 180, margin: '0 auto 10px', borderRadius: 10, overflow: 'hidden', boxShadow: '0 4px 18px rgba(0,0,0,.5)' },
  dName: { fontFamily: "'Shippori Mincho',serif", fontSize: 16, fontWeight: 700, color: '#efe2c8', textAlign: 'center', marginBottom: 10, overflowWrap: 'anywhere' },
  dRow: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8, padding: '7px 2px', borderBottom: '1px solid rgba(232,194,90,.12)', fontSize: 13, color: '#cdb488' },
  dv: { color: '#efe2c8', fontWeight: 700, textAlign: 'right', overflowWrap: 'anywhere', minWidth: 0 },
  skTitle: { marginTop: 12, marginBottom: 6, fontSize: 13, fontWeight: 700, color: GOLD_HI, letterSpacing: '.04em' },
  skMuted: { fontSize: 12, color: '#a98f66', padding: '4px 0' },
  skList: { display: 'flex', flexDirection: 'column', gap: 6 },
  skItem: { padding: '7px 9px', borderRadius: 9, border: '1px solid rgba(232,194,90,.16)', background: 'rgba(20,12,16,.5)' },
  skHead: { fontSize: 10, color: '#a98f66', marginBottom: 2 },
  skLv: { color: '#cdb488' },
  skName: { fontSize: 13, fontWeight: 700, color: '#efe2c8', overflowWrap: 'anywhere' },
  skEff: { fontSize: 11, color: '#cdb488', marginTop: 2, lineHeight: 1.5, overflowWrap: 'anywhere', wordBreak: 'break-word' },
  skEmpty: { fontSize: 12, color: '#7a6750' },
  choose: { width: '100%', padding: 12, borderRadius: 10, border: 'none', background: 'linear-gradient(180deg,#e8c25a,#b8901f)', color: '#1a1014', fontWeight: 800, fontSize: 15, cursor: 'pointer' },
  dLock: { padding: 11, borderRadius: 10, border: '1px solid rgba(200,80,80,.4)', background: 'rgba(60,20,24,.4)', color: '#e9a6a6', fontSize: 13, textAlign: 'center' },
  actBtn: { width: '100%', padding: 11, borderRadius: 10, border: 'none', background: 'linear-gradient(180deg,#e8c25a,#b8901f)', color: '#1a1014', fontWeight: 800, fontSize: 14, cursor: 'pointer' },
  actLock: { background: 'rgba(20,12,16,.85)', color: GOLD_HI, border: '1.5px solid rgba(232,194,90,.5)' },
  actOff: { opacity: .4, cursor: 'default' },
};

function CardPicker({ title, cards, getStatus, chooseLabel, onChoose, onClear, actions, back, busy, flash }) {
  const [sel, setSel] = useState(null);
  const [facet, setFacet] = useState('attr');
  const [fval, setFval] = useState('all');
  const [sortField, setSortField] = useState('body');
  const [sortDir, setSortDir] = useState('desc');
  const [skillMap, setSkillMap] = useState({});
  const [selSkills, setSelSkills] = useState(null);
  const cardById = {}; (cards || []).forEach(c => { cardById[c.id] = c; });

  useEffect(() => { (async () => { try { const sm = await ChikarianAPI.getSkillMaster(); const m = {}; (sm || []).forEach(s => { m[s.skill_key] = s; }); setSkillMap(m); } catch (e) {} })(); }, []);
  useEffect(() => {
    let live = true; setSelSkills(null);
    if (sel != null) { (async () => { try { const s = await ChikarianAPI.getCardSkills(sel) || []; if (live) setSelSkills(s); } catch (e) { if (live) setSelSkills([]); } })(); }
    return () => { live = false; };
  }, [sel]);

  const rawRar = k => k.endsWith('_sp') ? 'sp' : k.split('_').pop();
  const rawAttr = k => k.endsWith('_sp') ? 'sp' : k.split('_')[2];
  const rawWeap = k => k.endsWith('_sp') ? null : k.split('_')[3];
  const rawSpec = k => k.endsWith('_sp') ? 'sp' : k.split('_')[1];
  const RAR_ORD = { n: 0, r: 1, sr: 2, ssr: 3, sp: 4 };
  const FACETS = {
    attr: { label: '属性', vals: [['hana', '花'], ['shin', '芯'], ['ha', '葉'], ['sp', 'SP']] },
    weap: { label: '武器', vals: [['ken', '剣'], ['tate', '盾'], ['tsue', '杖']] },
    rarity: { label: 'レア', vals: [['n', 'N'], ['r', 'R'], ['sr', 'SR'], ['ssr', 'SSR'], ['sp', 'SP']] },
    species: { label: '種族', vals: [['hibiscus', 'ハイビスカス'], ['meshibe', 'めしべ'], ['sp', 'SP']] },
  };
  const FACET_ORDER = ['attr', 'weap', 'rarity', 'species'];
  const matchFacet = k => fval === 'all' ? true : facet === 'attr' ? rawAttr(k) === fval : facet === 'weap' ? rawWeap(k) === fval : facet === 'rarity' ? rawRar(k) === fval : rawSpec(k) === fval;
  const items = (cards || []).filter(c => matchFacet(c.card_key));
  const bodyOf = c => computeStats(c).body;
  const sval = c => sortField === 'rarity' ? (RAR_ORD[rawRar(c.card_key)] || 0) : sortField === 'lv' ? (c.lv || 1) : bodyOf(c);
  const dir = sortDir === 'asc' ? 1 : -1;
  items.sort((a, b) => (sval(a) - sval(b)) * dir || ((RAR_ORD[rawRar(b.card_key)] || 0) - (RAR_ORD[rawRar(a.card_key)] || 0)) || a.card_key.localeCompare(b.card_key));

  const SORTS = [['body', '本体戦闘力'], ['lv', 'レベル'], ['rarity', 'レア']];
  const arrow = f => sortField === f ? (sortDir === 'asc' ? ' ▲' : ' ▼') : '';
  const onSort = k => { if (sortField === k) setSortDir(d => d === 'asc' ? 'desc' : 'asc'); else { setSortField(k); setSortDir('desc'); } };

  const selCard = sel != null ? cardById[sel] : null;
  const selStatus = selCard ? getStatus(selCard) : null;
  const selInfo = selCard ? parseCardKey(selCard.card_key) : null;
  const selStats = selCard ? computeStats(selCard) : null;
  const selCap = selCard ? bukiCapacity(selCard) : 0;
  const bySlot = {}; (selSkills || []).forEach(s => { bySlot[s.slot] = s; });

  return (
    <div style={S.root}>
      <div style={S.bg} /><div style={S.vignette} />
      <div style={cpS.wrap}>
        <div style={cpS.head}>
          <button onClick={back} style={{ ...S.lineBtn, padding: '6px 14px' }}>‹ 戻る</button>
          <div style={cpS.title}>{title}</div>
        </div>
        <div style={cpS.facetRow}>
          {FACET_ORDER.map(f => <button key={f} onClick={() => { setFacet(f); setFval('all'); }} style={{ ...cpS.chip, ...(facet === f ? cpS.chipSel : {}) }}>{FACETS[f].label}</button>)}
        </div>
        <div style={cpS.facetRow}>
          <button onClick={() => setFval('all')} style={{ ...cpS.chip, ...(fval === 'all' ? cpS.chipSel : {}) }}>すべて</button>
          {FACETS[facet].vals.map(([k, l]) => <button key={k} onClick={() => setFval(k)} style={{ ...cpS.chip, ...(fval === k ? cpS.chipSel : {}) }}>{l}</button>)}
        </div>
        <div style={cpS.facetRow}>
          <span style={cpS.sortLab}>並び替え</span>
          {SORTS.map(([k, l]) => <button key={k} onClick={() => onSort(k)} style={{ ...cpS.chip, ...(sortField === k ? cpS.chipSel : {}) }}>{l}{arrow(k)}</button>)}
        </div>
        <div style={cpS.split}>
          <div style={cpS.left}>
            {items.length === 0
              ? <div style={cpS.empty}>該当カードなし</div>
              : items.map(c => {
                  const st = getStatus(c);
                  return (
                    <button key={c.id} onClick={() => setSel(c.id)} style={{ ...cpS.li, ...(sel === c.id ? cpS.liSel : {}), ...(st.dim ? { opacity: .45 } : {}) }}>
                      <div style={cpS.liArt}><DeckSlotArt cardKey={c.card_key} /></div>
                      <div style={cpS.liInfo}>
                        <span style={cpS.liLv}>Lv{c.lv || 1}{(c.star || 0) > 0 ? ' ★' + (c.star || 0) : ''}</span>
                        {st.tag && <span style={cpS.liTag}>{st.tag}</span>}
                      </div>
                    </button>
                  );
                })}
          </div>
          <div style={cpS.right}>
            {!selCard
              ? <div style={cpS.ph}>← 左の一覧から<br />カードを選ぶと<br />詳細が出ます</div>
              : <>
                  <div style={cpS.rightScroll}>
                    <div style={cpS.dArt}><DeckSlotArt cardKey={selCard.card_key} /></div>
                    <div style={cpS.dName}>{RAR_LABEL[selInfo.rarity]} {selInfo.name}</div>
                    <div style={cpS.dRow}><span>レベル</span><span style={cpS.dv}>Lv {selCard.lv || 1} / 上限 {selStats.cap}</span></div>
                    <div style={cpS.dRow}><span>強化値</span><span style={cpS.dv}>★{selCard.star || 0}</span></div>
                    <div style={cpS.dRow}><span>本体戦闘力</span><span style={cpS.dv}>{selStats.body.toLocaleString()}</span></div>
                    {!selStats.isSp && <div style={cpS.dRow}><span>充填（武気）</span><span style={cpS.dv}>{(selCard.loaded_buki || 0)} / {selCap} 枠</span></div>}
                    <div style={{ ...cpS.dRow, borderBottom: 'none' }}><span>コスト</span><span style={cpS.dv}>{COST_BY_RAR[selInfo.rarity] || 0}</span></div>
                    <div style={cpS.skTitle}>スキル</div>
                    {selSkills === null
                      ? <div style={cpS.skMuted}>読込中…</div>
                      : <div style={cpS.skList}>
                          {[0, 1, 2].map(slot => {
                            if (selStats.isSp && slot > 0) return null;
                            const row = bySlot[slot]; const m = row ? skillMap[row.skill_key] : null;
                            return (
                              <div key={slot} style={cpS.skItem}>
                                <div style={cpS.skHead}>{slot === 0 ? '固定スキル' : '移植スロット' + slot}{row && <span style={cpS.skLv}>・Lv{row.skill_lv}</span>}</div>
                                {row
                                  ? <><div style={cpS.skName}>{m ? m.display_name : row.skill_key}</div>{m && m.notes && <div style={cpS.skEff}>{m.notes}</div>}</>
                                  : <div style={cpS.skEmpty}>（空き）</div>}
                              </div>
                            );
                          })}
                        </div>}
                  </div>
                  <div style={cpS.rightFoot}>
                    {actions
                      ? actions(selCard).map((a, i) => <button key={i} onClick={a.onClick} disabled={a.disabled} style={{ ...cpS.actBtn, ...(a.tone === 'lock' ? cpS.actLock : {}), ...(a.disabled ? cpS.actOff : {}) }}>{a.label}</button>)
                      : (selStatus.disabled
                          ? <div style={cpS.dLock}>{selStatus.reason || selStatus.tag || '選べません'}</div>
                          : <button onClick={() => onChoose(selCard)} disabled={busy} style={{ ...cpS.choose, ...(busy ? { opacity: .5 } : {}) }}>{typeof chooseLabel === 'function' ? chooseLabel(selCard) : chooseLabel}</button>)}
                  </div>
                </>}
          </div>
        </div>
        {onClear && <button onClick={onClear} disabled={busy} style={{ ...S.lineBtn, marginTop: 12, alignSelf: 'center', ...(busy ? { opacity: .45 } : {}) }}>この枠を空にする</button>}
      </div>
    </div>
  );
}

```

---

## 編集2. KyokaScreen：強化合成をインライン操作化（CardDetailページ廃止／関数全置換）

【検索】
```jsx
function KyokaScreen({ cards, profile, refreshAll, back, flash }) {
  const [baseCard, setBaseCard] = useState(null);
  const [skillMap, setSkillMap] = useState({});
  const cardById = {}; (cards || []).forEach(c => { cardById[c.id] = c; });
  useEffect(() => { (async () => { try { const sm = await ChikarianAPI.getSkillMaster(); const m = {}; (sm || []).forEach(s => { m[s.skill_key] = s; }); setSkillMap(m); } catch (e) {} })(); }, []);
  // 強化合成＝カードを選ぶ→カード詳細（★強化／スキル強化・転移）。refreshAll 後も最新を反映するため cardById から都度引く。
  const cur = baseCard ? cardById[baseCard.id] : null;
  if (cur) {
    return <CardDetail card={cur} cards={cards} profile={profile} skillMap={skillMap} refreshAll={refreshAll} back={() => setBaseCard(null)} onSelect={setBaseCard} flash={flash} />;
  }
  const getStatus = (c) => { const locked = !!c.locked; return { disabled: locked, dim: locked, tag: locked ? 'ロック中' : null }; };
  return <CardPicker title="強化するカードを選ぶ" cards={cards} getStatus={getStatus} chooseLabel="このカードを選ぶ" onChoose={(c) => setBaseCard(c)} back={back} flash={flash} />;
}
```
【置換】
```jsx
function KyokaScreen({ cards, profile, refreshAll, back, flash }) {
  const [card, setCard] = useState(null);
  const [mode, setMode] = useState(null);
  const [skillMap, setSkillMap] = useState({});
  const [busy, setBusy] = useState(false);
  const cardById = {}; (cards || []).forEach(c => { cardById[c.id] = c; });
  useEffect(() => { (async () => { try { const sm = await ChikarianAPI.getSkillMaster(); const m = {}; (sm || []).forEach(s => { m[s.skill_key] = s; }); setSkillMap(m); } catch (e) {} })(); }, []);
  // 強化合成＝カードを選ぶ→右パネルの操作ボタン（★強化／スキル強化・転移／ロック）を直接実行。中間のカード詳細ページは廃止。
  const cur = card ? cardById[card.id] : null;
  if (mode === 'kyoka' && cur) return <KyokaView base={cur} cards={cards} profile={profile} refreshAll={refreshAll} onBack={() => setMode(null)} flash={flash} />;
  if (mode === 'skill' && cur) return <SkillView base={cur} cards={cards} profile={profile} skillMap={skillMap} refreshAll={refreshAll} onBack={() => setMode(null)} flash={flash} />;
  const getStatus = (c) => ({ disabled: false, dim: false, tag: c.locked ? 'ロック中' : null });
  async function toggleLock(c) {
    if (!LOCK_RPC_AVAILABLE) { flash('ロック切替には専用RPCが必要です（0023適用後に有効化）'); return; }
    setBusy(true);
    try { await ChikarianAPI.setCardLock(c.id, !c.locked); await refreshAll(); } catch (e) { flash(errMsg(e)); } finally { setBusy(false); }
  }
  const actions = (c) => {
    const isSp = c.card_key.endsWith('_sp');
    return [
      { label: '★強化' + (c.locked ? '（ロック中）' : ''), disabled: busy || !!c.locked, onClick: () => { setCard(c); setMode('kyoka'); } },
      { label: 'スキル強化・転移' + (isSp ? '（SP不可）' : ''), disabled: busy || isSp, onClick: () => { setCard(c); setMode('skill'); } },
      { label: c.locked ? '🔒 ロック解除' : '🔓 ロックする', tone: 'lock', disabled: busy || !LOCK_RPC_AVAILABLE, onClick: () => toggleLock(c) },
    ];
  };
  return <CardPicker title="強化するカードを選ぶ" cards={cards} getStatus={getStatus} actions={actions} back={back} busy={busy} flash={flash} />;
}

```

---

## 編集3. CardPopup＋popS を新設（ExchangeTab 定義の直前に挿入）

【検索】
```jsx
function ExchangeTab({ profile, cards, refreshAll, flash }) {

```
【置換】
```jsx
const popS = {
  scrim: { position: 'fixed', inset: 0, background: 'rgba(0,0,0,.74)', display: 'grid', placeItems: 'center', zIndex: 120, padding: 16 },
  box: { position: 'relative', width: 'min(360px, 94vw)', maxHeight: '88vh', overflowY: 'auto', background: '#160a13', border: '1.5px solid rgba(232,194,90,.5)', borderRadius: 14, padding: '16px 16px 18px', boxShadow: '0 12px 40px rgba(0,0,0,.7)' },
  close: { position: 'absolute', top: 8, right: 10, width: 30, height: 30, borderRadius: '50%', border: '1px solid rgba(232,194,90,.4)', background: 'rgba(20,12,16,.8)', color: GOLD_HI, fontSize: 18, cursor: 'pointer', lineHeight: 1, zIndex: 2 },
  art: { width: 132, height: 198, margin: '4px auto 10px', borderRadius: 10, overflow: 'hidden', boxShadow: '0 4px 18px rgba(0,0,0,.5)' },
  name: { fontFamily: "'Shippori Mincho',serif", fontSize: 17, fontWeight: 700, color: '#efe2c8', textAlign: 'center', marginBottom: 10, overflowWrap: 'anywhere' },
  row: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8, padding: '7px 2px', borderBottom: '1px solid rgba(232,194,90,.12)', fontSize: 13, color: '#cdb488' },
  v: { color: '#efe2c8', fontWeight: 700, textAlign: 'right' },
  skTitle: { marginTop: 12, marginBottom: 6, fontSize: 13, fontWeight: 700, color: GOLD_HI },
  skMuted: { fontSize: 12, color: '#a98f66', padding: '4px 0' },
  skList: { display: 'flex', flexDirection: 'column', gap: 6 },
  skItem: { padding: '7px 9px', borderRadius: 9, border: '1px solid rgba(232,194,90,.16)', background: 'rgba(20,12,16,.5)' },
  skHead: { fontSize: 10, color: '#a98f66', marginBottom: 2 },
  skLv: { color: '#cdb488' },
  skName: { fontSize: 13, fontWeight: 700, color: '#efe2c8' },
  skEff: { fontSize: 11, color: '#cdb488', marginTop: 2, lineHeight: 1.5, overflowWrap: 'anywhere' },
  skEmpty: { fontSize: 12, color: '#7a6750' },
};

function CardPopup({ card, onClose }) {
  const [skillMap, setSkillMap] = useState({});
  const [skills, setSkills] = useState(null);
  useEffect(() => { (async () => { try { const sm = await ChikarianAPI.getSkillMaster(); const m = {}; (sm || []).forEach(s => { m[s.skill_key] = s; }); setSkillMap(m); } catch (e) {} })(); }, []);
  useEffect(() => {
    let live = true; setSkills(null);
    if (card) { (async () => { try { const s = await ChikarianAPI.getCardSkills(card.id) || []; if (live) setSkills(s); } catch (e) { if (live) setSkills([]); } })(); }
    return () => { live = false; };
  }, [card && card.id]);
  if (!card) return null;
  const info = parseCardKey(card.card_key);
  const st = computeStats(card);
  const cap = bukiCapacity(card);
  const bySlot = {}; (skills || []).forEach(s => { bySlot[s.slot] = s; });
  return (
    <div style={popS.scrim} onClick={onClose}>
      <div style={popS.box} onClick={e => e.stopPropagation()}>
        <button style={popS.close} onClick={onClose}>×</button>
        <div style={popS.art}><DeckSlotArt cardKey={card.card_key} /></div>
        <div style={popS.name}>{RAR_LABEL[info.rarity]} {info.name}</div>
        <div style={popS.row}><span>レベル</span><span style={popS.v}>Lv {card.lv || 1} / 上限 {st.cap}</span></div>
        <div style={popS.row}><span>強化値</span><span style={popS.v}>★{card.star || 0}</span></div>
        <div style={popS.row}><span>本体戦闘力</span><span style={popS.v}>{st.body.toLocaleString()}</span></div>
        {!st.isSp && <div style={popS.row}><span>充填（武気）</span><span style={popS.v}>{(card.loaded_buki || 0)} / {cap} 枠</span></div>}
        <div style={{ ...popS.row, borderBottom: 'none' }}><span>コスト</span><span style={popS.v}>{COST_BY_RAR[info.rarity] || 0}</span></div>
        <div style={popS.skTitle}>スキル</div>
        {skills === null
          ? <div style={popS.skMuted}>読込中…</div>
          : <div style={popS.skList}>
              {[0, 1, 2].map(slot => {
                if (st.isSp && slot > 0) return null;
                const r = bySlot[slot]; const m = r ? skillMap[r.skill_key] : null;
                return (
                  <div key={slot} style={popS.skItem}>
                    <div style={popS.skHead}>{slot === 0 ? '固定スキル' : '移植スロット' + slot}{r && <span style={popS.skLv}>・Lv{r.skill_lv}</span>}</div>
                    {r ? <><div style={popS.skName}>{m ? m.display_name : r.skill_key}</div>{m && m.notes && <div style={popS.skEff}>{m.notes}</div>}</> : <div style={popS.skEmpty}>（空き）</div>}
                  </div>
                );
              })}
            </div>}
      </div>
    </div>
  );
}


function ExchangeTab({ profile, cards, refreshAll, flash }) {

```

---

## 編集4. ボス出撃：カードタップの CardDetail オーバーレイ→CardPopup に差替え

【検索】
```jsx
      {detailCard && (
        <div style={{ position: 'fixed', inset: 0, zIndex: 200, overflowY: 'auto', background: '#0a0608' }}>
          <CardDetail card={detailCard} cards={cards} profile={profile} skillMap={skillMap} refreshAll={onRefresh} onSelect={setDetailCard} flash={flash}
            back={async () => { setDetailCard(null); try { await onRefresh(); } catch (e) {} }} />
        </div>
      )}

```
【置換】
```jsx
      {detailCard && <CardPopup card={detailCard} onClose={() => setDetailCard(null)} />}

```

---

## 編集5. デッキ編成：detailCard state を追加

【検索】
```jsx
  const [picking, setPicking] = useState(null); // 編集中の枠 index or null
```
【置換】
```jsx
  const [picking, setPicking] = useState(null); // 編集中の枠 index or null
  const [detailCard, setDetailCard] = useState(null); // カード詳細ポップアップ
```

---

## 編集6. デッキ編成：充填スロットに ⓘ（詳細）ボタンを追加

【検索】
```jsx
                      <div onClick={(e) => { e.stopPropagation(); if (!busy && !deckSortie) commit(withSlot(slot, null)); }} style={deckS.rm}>×</div>
                      <DeckSlotArt cardKey={c.card_key} />
```
【置換】
```jsx
                      <div onClick={(e) => { e.stopPropagation(); if (!busy && !deckSortie) commit(withSlot(slot, null)); }} style={deckS.rm}>×</div>
                      <DeckSlotArt cardKey={c.card_key} />
                      <div onClick={(e) => { e.stopPropagation(); setDetailCard(c); }} style={{ position: 'absolute', left: 4, top: 4, width: 22, height: 22, borderRadius: '50%', background: 'rgba(10,6,9,.8)', border: '1px solid rgba(232,194,90,.55)', color: '#fff3c8', fontSize: 13, lineHeight: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', zIndex: 3 }}>ⓘ</div>
```

---

## 編集7. デッキ編成：CardPopup の描画を追加

【検索】
```jsx
            </div>
          );
        })()}
      </>
```
【置換】
```jsx
            </div>
          );
        })()}
        {detailCard && <CardPopup card={detailCard} onClose={() => setDetailCard(null)} />}
      </>
```

---

## 編集8. 交換所：detailCard state を追加

【検索】
```jsx
  const [result, setResult] = useState(null);
  const [confirm, setConfirm] = useState(false);
```
【置換】
```jsx
  const [result, setResult] = useState(null);
  const [confirm, setConfirm] = useState(false);
  const [detailCard, setDetailCard] = useState(null); // カード詳細ポップアップ
```

---

## 編集9. 交換所：カードに Lv 表示＋ⓘ（詳細）ボタンを追加

【検索】
```jsx
                  <div style={exS.cardArt}><DeckSlotArt cardKey={c.card_key} />{on && <div style={exS.check}>✓</div>}</div>
                  <div style={exS.cardName}>{RAR_LABEL[info.rarity]}{(c.star || 0) > 0 ? '★' + (c.star || 0) : ''}</div>
```
【置換】
```jsx
                  <div style={exS.cardArt}><DeckSlotArt cardKey={c.card_key} />{on && <div style={exS.check}>✓</div>}<div onClick={(e) => { e.stopPropagation(); setDetailCard(c); }} style={{ position: 'absolute', left: 3, top: 3, width: 20, height: 20, borderRadius: '50%', background: 'rgba(10,6,9,.82)', border: '1px solid rgba(232,194,90,.5)', color: '#fff3c8', fontSize: 12, lineHeight: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', zIndex: 3 }}>ⓘ</div></div>
                  <div style={exS.cardName}>{RAR_LABEL[info.rarity]} Lv{c.lv || 1}{(c.star || 0) > 0 ? ' ★' + (c.star || 0) : ''}</div>
```

---

## 編集10. 交換所：CardPopup の描画を追加

【検索】
```jsx
              <button style={deckS.mMove} onClick={() => { setConfirm(false); doExchange(); }} disabled={busy}>{busy ? '交換中…' : '交換する'}</button>
            </div>
          </div>
        </div>
      )}
    </div>

```
【置換】
```jsx
              <button style={deckS.mMove} onClick={() => { setConfirm(false); doExchange(); }} disabled={busy}>{busy ? '交換中…' : '交換する'}</button>
            </div>
          </div>
        </div>
      )}
      {detailCard && <CardPopup card={detailCard} onClose={() => setDetailCard(null)} />}
    </div>

```

---

## 適用後の確認
- 強化合成：カード選択→右下固定で **★強化／スキル強化・転移／🔓ロック**。★強化→KyokaView、スキル強化・転移→SkillView。中間のカード詳細ページは通らない。ロック中カードは★強化のみ無効（解除可）。
- ボス出撃：デッキカードのタップ→**CardPopup**（スキル表示・操作ボタンなし）。ページ遷移しない。
- デッキ編成：各カード左上の **ⓘ**→CardPopup でスキル確認（タップ本体は従来どおり枠編集）。
- 交換所：各カードに **Lv/★** 表示＋左上 **ⓘ**→CardPopup（タップ本体は選択トグル）。
- 左右ピッカー（デッキ枠）：「これを選ぶ」「この枠を空にする」が**スクロールせず**押せる。
- ⚠️ ロックボタンは現状 `LOCK_RPC_AVAILABLE=false` のため無効（タップで案内）。0023(set_card_lock) 適用済みなら別途フラグを true に。
- 適用後 commit & push → ブラウザ Ctrl+Shift+R。
