# Claude Code 指示書：⑩ ピッカー再設計＋強化合成導線＋バッジ撤去

対象：`Chikarian/index.html`。HEAD（⑨適用後）基準。文字列アンカー一致。編集4箇所。すべて Babel(JSX) 検証済み。
目的（ユーザー確定）：
- 強化合成 → カードを選ぶ → **カード詳細**（★強化／スキル強化・転移）に接続（装備＝充填はデッキ画面と重複で撤去・交換所は建物へ移動予定）。
- CardPicker 左一覧を**カード絵主体**に（名前・属性/武器バッジ撤去、絵を大きく＋Lv/★＋状態のみ）。詳細からも属性/武器バッジ撤去。
- カード絵に属性（宝石）と武器（剣/盾/杖）が既出のため、**属性アイコン/バッジは撤去**（DeckBadges を CardPicker・デッキ枠で不使用に）。

---

## 編集1：cpS ＋ CardPicker を再設計版へ全置換（左=カード絵主体・バッジ撤去）

【検索（厳密一致・ブロック全体）】
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
  liThumb: { width: 40, height: 40, flex: '0 0 40px', borderRadius: 8, overflow: 'hidden' },
  liMeta: { minWidth: 0, flex: 1 },
  liNameRow: { display: 'flex', alignItems: 'center', gap: 4 },
  liRar: { fontSize: 10, fontWeight: 800, color: GOLD_HI, flex: '0 0 auto' },
  liName: { fontSize: 12, color: '#efe2c8', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', minWidth: 0 },
  liBadges: { display: 'flex', alignItems: 'center', gap: 4, marginTop: 3, flexWrap: 'wrap' },
  liTag: { fontSize: 10, color: '#cdb488', padding: '1px 6px', borderRadius: 6, border: '1px solid rgba(232,194,90,.25)' },
  right: { flex: '1 1 0', minWidth: 0, boxSizing: 'border-box', overflowY: 'auto', overflowX: 'hidden', maxHeight: '66vh', border: '1px solid rgba(232,194,90,.2)', borderRadius: 12, background: 'rgba(14,9,12,.55)', padding: 12 },
  ph: { color: '#a98f66', fontSize: 14, textAlign: 'center', padding: '40px 10px', lineHeight: 1.8 },
  dArt: { width: 108, height: 162, margin: '0 auto 10px', borderRadius: 10, overflow: 'hidden', boxShadow: '0 4px 18px rgba(0,0,0,.5)' },
  dNameRow: { display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, marginBottom: 8, flexWrap: 'wrap' },
  dRar: { fontSize: 13, fontWeight: 800, color: GOLD_HI },
  dName: { fontFamily: "'Shippori Mincho',serif", fontSize: 16, fontWeight: 700, color: '#efe2c8', overflowWrap: 'anywhere' },
  dBadges: { display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, marginBottom: 10 },
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
                  const info = parseCardKey(c.card_key);
                  return (
                    <button key={c.id} onClick={() => setSel(c.id)} style={{ ...cpS.li, ...(sel === c.id ? cpS.liSel : {}), ...(st.dim ? { opacity: .45 } : {}) }}>
                      <div style={cpS.liThumb}><CardThumb card={c} small /></div>
                      <div style={cpS.liMeta}>
                        <div style={cpS.liNameRow}><span style={cpS.liRar}>{RAR_LABEL[info.rarity]}</span><span style={cpS.liName}>{info.name}</span></div>
                        <div style={cpS.liBadges}><DeckBadges info={info} />{st.tag && <span style={cpS.liTag}>{st.tag}</span>}</div>
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
                  <div style={cpS.dNameRow}><span style={cpS.dRar}>{RAR_LABEL[selInfo.rarity]}</span><span style={cpS.dName}>{selInfo.name}</span></div>
                  <div style={cpS.dBadges}><DeckBadges info={selInfo} /></div>
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

---

## 編集2：KyokaScreen を CardPicker→CardDetail 接続版へ全置換

【検索（厳密一致・関数全体）】
```jsx
function KyokaScreen({ cards, profile, refreshAll, back, flash }) {
  const [baseId, setBaseId] = useState(null);
  const [sel, setSel] = useState(null);
  const cardById = {}; (cards || []).forEach(c => { cardById[c.id] = c; });
  // 強化後も本体は残る（★+1）。最新 cards を反映するため cardById から都度引く。
  if (baseId && cardById[baseId]) {
    return <KyokaView base={cardById[baseId]} cards={cards} profile={profile} refreshAll={refreshAll} onBack={() => setBaseId(null)} flash={flash} />;
  }
  const list = (cards || []);
  const selCard = sel ? cardById[sel] : null;
  const selInfo = selCard ? parseCardKey(selCard.card_key) : null;
  const selStats = selCard ? computeStats(selCard) : null;
  const subOf = (c) => c.locked ? 'ロック中' : ('Lv' + (c.lv || 1) + '・★' + (c.star || 0));
  return (
    <div style={S.root}>
      <div style={S.bg} /><div style={S.vignette} />
      <div style={pickS.wrap}>
        <div style={pickS.head}>
          <button onClick={back} style={{ ...S.lineBtn, padding: '6px 14px' }}>‹ 戻る</button>
          <div style={pickS.title}>強化する本体カードを選ぶ</div>
        </div>
        <div style={pickS.split}>
          <div style={pickS.left}>
            {list.length === 0
              ? <div style={pickS.empty}>所持カードがありません</div>
              : list.map(c => (
                  <button key={c.id} onClick={() => setSel(c.id)} style={{ ...pickS.li, ...(sel === c.id ? pickS.liSel : {}), ...(c.locked ? { opacity: .5 } : {}) }}>
                    <div style={pickS.liThumb}><CardThumb card={c} small /></div>
                    <div style={pickS.liMeta}>
                      <div style={pickS.liName}>{cardFullName(c)}</div>
                      <div style={pickS.liSub}>{subOf(c)}</div>
                    </div>
                  </button>
                ))}
          </div>
          <div style={pickS.right}>
            {!selCard
              ? <div style={pickS.ph}>← 左の一覧から<br />本体カードを選ぶ<br />と詳細が出ます</div>
              : <>
                  <div style={pickS.dArt}><DeckSlotArt cardKey={selCard.card_key} /></div>
                  <div style={pickS.dName}>{cardFullName(selCard)}</div>
                  <div style={pickS.dRow}><span>レベル</span><span style={pickS.dv}>Lv {selCard.lv || 1}</span></div>
                  <div style={pickS.dRow}><span>強化値（★）</span><span style={pickS.dv}>★{selCard.star || 0}</span></div>
                  <div style={{ ...pickS.dRow, borderBottom: 'none' }}><span>戦闘力（総合）</span><span style={pickS.dv}>{selStats.sougou.toLocaleString()}</span></div>
                  {selCard.locked
                    ? <div style={pickS.dLock}>ロック中（強化できません）</div>
                    : <button onClick={() => setBaseId(selCard.id)} style={pickS.choose}>このカードを強化する</button>}
                </>}
          </div>
        </div>
      </div>
    </div>
  );
}
```
【置換】
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

---

## 編集3：CardDetail の「装備（充填）」「交換所」ボタン2行を削除

【検索（厳密一致・この2行）】
```jsx
          <button style={{ ...zS.zaBtn, ...(st.isSp ? zS.zaOff : {}) }} disabled={st.isSp} onClick={() => setMode('equip')}>装備（充填）{st.isSp ? '（SP不可）' : ''}</button>
          <button style={{ ...zS.zaBtn, ...(card.locked ? zS.zaOff : {}) }} disabled={!!card.locked} onClick={() => setMode('exchange')}>交換所</button>
```
【置換】
（空＝この2行を削除。★強化／スキル強化・転移／ロック切替 の3ボタンが残る）

---

## 編集4：デッキ枠スロットの属性/武器バッジ（DeckBadges）を削除

【検索（厳密一致）】
```jsx
                      <div style={deckS.meta}><DeckBadges info={info} /></div>
```
【置換】
（空＝この1行を削除。スロットは ×・カード絵・離脱中バッジ のみ表示。直前の `const info` は未使用になるが無害）

---

## 確認事項
- CardPicker の公開API（title/cards/getStatus/chooseLabel/onChoose/onClear/back/busy/flash）は不変。デッキ枠ピッカー（DeckScreen）の呼び出しもそのまま動作。
- 左一覧＝カード絵（DeckSlotArt・54×81）＋「Lv/★」＋状態タグ（デッキN/編成中/探索中/出撃中/離脱中/ロック中）。名前・属性/武器バッジは無し。
- 詳細＝大きいカード絵＋「レア＋名前」見出し＋Lv/★/本体戦闘力/充填/コスト＋スキル（固定/移植・名前/効果/Lv）。属性/武器バッジは無し（絵に描かれているため）。
- 強化合成：home→強化合成→CardPicker（カードを選ぶ・戻る=home）→「このカードを選ぶ」→**カード詳細**（★強化／スキル強化・転移／ロック切替）。詳細の戻る=ピッカー。★強化後も最新★を反映。ロック中カードは選択不可（ロック中タグ）。
- DeckBadges/AttrIcon は CardPicker・デッキ枠で不使用になる（定義は残置・無害＝属性アイコンは画面から消える）。
- 適用後 commit & push → Ctrl+Shift+R。
