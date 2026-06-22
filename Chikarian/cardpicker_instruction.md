# Claude Code 指示書：⑦ 共通カードピッカー CardPicker（フィルタ＋ソート＋スキル＋本体戦闘力＋属性/武器バッジ）

対象：`Chikarian/index.html`。④適用後の HEAD 基準。
目的：デッキ枠ピッカーの4不満を解消する共通コンポーネント `CardPicker` を新設し、デッキ枠ピッカーをこれに置換する。
- (1) 左一覧に**フィルタ（属性/武器/レア/種族）＋ソート（本体戦闘力/レベル/レア・▲▼）**を追加（1000枚でも探せる）。
- (2) 右詳細に**所持スキル（固定＋移植スロット1/2：名前＋効果＋Lv）**を表示（getCardSkills＋skillMaster）。
- (3) 戦闘力を**総合→本体戦闘力**に変更（デッキ外は充填なし／他デッキ在籍は武気込みになり比較が崩れるため）。
- (4) 名前ベタ書きの属性・武器を**色付きバッジ（DeckBadges チップ）**に。※属性/武器の画像アイコン素材は存在しないため、既存の色付きバッジで「アイコン化」する。
方針：CardPicker は**自己完結スタイル `cpS`** を持ち、pickS には触れない（pickS は今後 deprecate）。選択可否・移動確認は呼び出し側（DeckScreen）が getStatus/chooseLabel/onChoose で注入。移動確認モーダルは従来どおり DeckScreen に保持（CardPicker の兄弟として描画、deckS.mScrim は position:fixed）。
編集2箇所、文字列アンカー一致。CardPicker・デッキ配線とも Babel(JSX) 検証済み。参照シンボル（S/ChikarianAPI.getSkillMaster・getCardSkills/computeStats(.body/.cap/.isSp)/parseCardKey/bukiCapacity/CardThumb/DeckBadges/DeckSlotArt/RAR_LABEL/COST_BY_RAR/GOLD_HI/deckS）すべて定義済み。新規 import 不要。

---

## 編集1：cpS ＋ CardPicker を新設（DeckBadges 定義の直前に挿入）

【検索（厳密一致）】
```
function DeckBadges({ info }) {
```
【置換】
```jsx
const cpS = {
  wrap: { position: 'relative', zIndex: 2, width: 'min(960px,96vw)', margin: '0 auto', padding: '14px 12px 22px', display: 'flex', flexDirection: 'column', minHeight: '100%' },
  head: { display: 'flex', alignItems: 'center', gap: 12, marginBottom: 10 },
  title: { fontFamily: "'Shippori Mincho',serif", fontSize: 18, fontWeight: 700, color: GOLD_HI, letterSpacing: '.04em' },
  facetRow: { display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 6, alignItems: 'center' },
  chip: { padding: '4px 10px', borderRadius: 999, border: '1px solid rgba(232,194,90,.35)', background: 'rgba(20,12,16,.6)', color: '#d8c19a', fontSize: 12, cursor: 'pointer', whiteSpace: 'nowrap' },
  chipSel: { background: 'linear-gradient(180deg,#e8c25a,#b8901f)', color: '#1a1014', borderColor: '#e8c25a', fontWeight: 700 },
  sortLab: { fontSize: 11, color: '#a98f66', marginRight: 2 },
  split: { display: 'flex', gap: 10, flex: 1, minHeight: 0, marginTop: 4 },
  left: { width: '40%', maxWidth: 300, minWidth: 148, overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 6, paddingRight: 4, maxHeight: '68vh' },
  empty: { color: '#a98f66', fontSize: 13, padding: 20, textAlign: 'center' },
  li: { display: 'flex', gap: 8, alignItems: 'center', padding: 6, borderRadius: 10, border: '1px solid rgba(232,194,90,.18)', background: 'rgba(20,12,16,.5)', cursor: 'pointer', textAlign: 'left', width: '100%' },
  liSel: { borderColor: '#e8c25a', background: 'rgba(232,194,90,.14)', boxShadow: '0 0 8px rgba(232,194,90,.25)' },
  liThumb: { width: 44, height: 44, flex: '0 0 44px', borderRadius: 8, overflow: 'hidden' },
  liMeta: { minWidth: 0, flex: 1 },
  liNameRow: { display: 'flex', alignItems: 'center', gap: 4 },
  liRar: { fontSize: 10, fontWeight: 800, color: GOLD_HI, flex: '0 0 auto' },
  liName: { fontSize: 12, color: '#efe2c8', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' },
  liBadges: { display: 'flex', alignItems: 'center', gap: 4, marginTop: 3, flexWrap: 'wrap' },
  liTag: { fontSize: 10, color: '#cdb488', padding: '1px 6px', borderRadius: 6, border: '1px solid rgba(232,194,90,.25)' },
  right: { flex: 1, minWidth: 0, overflowY: 'auto', maxHeight: '68vh', border: '1px solid rgba(232,194,90,.2)', borderRadius: 12, background: 'rgba(14,9,12,.55)', padding: 14 },
  ph: { color: '#a98f66', fontSize: 14, textAlign: 'center', padding: '40px 10px', lineHeight: 1.8 },
  dArt: { width: 140, height: 210, margin: '0 auto 10px', borderRadius: 10, overflow: 'hidden', boxShadow: '0 4px 18px rgba(0,0,0,.5)' },
  dNameRow: { display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, marginBottom: 8 },
  dRar: { fontSize: 13, fontWeight: 800, color: GOLD_HI },
  dName: { fontFamily: "'Shippori Mincho',serif", fontSize: 17, fontWeight: 700, color: '#efe2c8' },
  dBadges: { display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6, marginBottom: 10 },
  dRow: { display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: '7px 2px', borderBottom: '1px solid rgba(232,194,90,.12)', fontSize: 13, color: '#cdb488' },
  dv: { color: '#efe2c8', fontWeight: 700 },
  skTitle: { marginTop: 12, marginBottom: 6, fontSize: 13, fontWeight: 700, color: GOLD_HI, letterSpacing: '.04em' },
  skMuted: { fontSize: 12, color: '#a98f66', padding: '4px 0' },
  skList: { display: 'flex', flexDirection: 'column', gap: 6 },
  skItem: { padding: '7px 9px', borderRadius: 9, border: '1px solid rgba(232,194,90,.16)', background: 'rgba(20,12,16,.5)' },
  skHead: { fontSize: 10, color: '#a98f66', marginBottom: 2 },
  skLv: { color: '#cdb488' },
  skName: { fontSize: 13, fontWeight: 700, color: '#efe2c8' },
  skEff: { fontSize: 11, color: '#cdb488', marginTop: 2, lineHeight: 1.5 },
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

function DeckBadges({ info }) {
```

---

## 編集2：デッキ枠ピッカーのブロックを CardPicker 呼び出しへ全置換

`if (picking !== null) { … }` ブロック（左サムネ＋右詳細＋移動確認モーダルを内包）を、CardPicker 呼び出し＋移動確認モーダルへ置換する。

【検索（厳密一致・このブロック全体）】
```jsx
  if (picking !== null) {
    const list = (cards || []);
    const stateOf = (c) => {
      const sameDeckOther = curSlots.some((id, i) => id === c.id && i !== picking);
      const sp = !!(spSet && spSet[c.id]);
      const sortieLocked = (c.tansaku_deck_no != null) || (c.boss_deck_no != null);
      const otherDeck = deckNoOf(c.id);
      const disabled = busy || sameDeckOther || sp || sortieLocked;
      return { sameDeckOther, sp, sortieLocked, otherDeck, disabled };
    };
    const subOf = (c, st) => st.sp ? '離脱中' : st.sortieLocked ? (c.tansaku_deck_no != null ? '探索中' : '出撃中') : st.sameDeckOther ? '編成中' : st.otherDeck ? ('デッキ' + st.otherDeck) : ('Lv' + (c.lv || 1));
    const selCard = pickSel ? cardById[pickSel] : null;
    const selState = selCard ? stateOf(selCard) : null;
    const selInfo = selCard ? parseCardKey(selCard.card_key) : null;
    const selStats = selCard ? computeStats(selCard) : null;
    const selCap = selCard ? bukiCapacity(selCard) : 0;
    const lockMsg = selCard && selState ? (selState.sp ? 'SP離脱中（本日）は編成できません' : selState.sortieLocked ? (selCard.tansaku_deck_no != null ? '探索に出撃中です' : 'ボスに出撃中です') : selState.sameDeckOther ? 'このデッキの別の枠で編成中です' : '選べません') : '';
    const choose = () => {
      if (!selCard || !selState || selState.disabled) return;
      if (selState.otherDeck) setMoveConfirm({ cardId: selCard.id, slot: picking, fromDeckNo: selState.otherDeck });
      else commit(withSlot(picking, selCard.id));
    };
    return (
      <div style={S.root}>
        <div style={S.bg} /><div style={S.vignette} />
        <div style={pickS.wrap}>
          <div style={pickS.head}>
            <button onClick={() => setPicking(null)} style={{ ...S.lineBtn, padding: '6px 14px' }}>‹ 戻る</button>
            <div style={pickS.title}>枠 {picking + 1} に入れるカード</div>
          </div>
          <div style={pickS.split}>
            <div style={pickS.left}>
              {list.length === 0
                ? <div style={pickS.empty}>所持カードがありません</div>
                : list.map(c => {
                    const st = stateOf(c);
                    const dim = st.sameDeckOther || st.sp || st.sortieLocked;
                    return (
                      <button key={c.id} onClick={() => setPickSel(c.id)} style={{ ...pickS.li, ...(pickSel === c.id ? pickS.liSel : {}), ...(dim ? { opacity: .45 } : {}) }}>
                        <div style={pickS.liThumb}><CardThumb card={c} small /></div>
                        <div style={pickS.liMeta}>
                          <div style={pickS.liName}>{cardFullName(c)}</div>
                          <div style={pickS.liSub}>{subOf(c, st)}</div>
                        </div>
                      </button>
                    );
                  })}
            </div>
            <div style={pickS.right}>
              {!selCard
                ? <div style={pickS.ph}>← 左の一覧から<br />カードを選ぶと<br />詳細が出ます</div>
                : <>
                    <div style={pickS.dArt}><DeckSlotArt cardKey={selCard.card_key} /></div>
                    <div style={pickS.dName}>{cardFullName(selCard)}</div>
                    <div style={pickS.dRow}><span>レベル</span><span style={pickS.dv}>Lv {selCard.lv || 1}</span></div>
                    <div style={pickS.dRow}><span>戦闘力（総合）</span><span style={pickS.dv}>{selStats.sougou.toLocaleString()}</span></div>
                    {!selStats.isSp && <div style={pickS.dRow}><span>充填（武気）</span><span style={pickS.dv}>{(selCard.loaded_buki || 0)} / {selCap} 枠</span></div>}
                    <div style={{ ...pickS.dRow, borderBottom: 'none' }}><span>コスト</span><span style={pickS.dv}>{COST_BY_RAR[selInfo.rarity] || 0}</span></div>
                    {selState.disabled
                      ? <div style={pickS.dLock}>{lockMsg}</div>
                      : <button onClick={choose} disabled={busy} style={{ ...pickS.choose, ...(busy ? { opacity: .5 } : {}) }}>{selState.otherDeck ? 'これを選ぶ（デッキ' + selState.otherDeck + 'から移動）' : 'これを選ぶ'}</button>}
                  </>}
            </div>
          </div>
          <button onClick={() => { if (!busy) commit(withSlot(picking, null)); }} disabled={busy} style={{ ...S.lineBtn, marginTop: 10, alignSelf: 'center', ...(busy ? { opacity: .45 } : {}) }}>この枠を空にする</button>
        </div>

        {/* 他デッキ移動の確認モーダル */}
        {moveConfirm && (() => {
          const mc = moveConfirm; const mcCard = cardById[mc.cardId];
          const nm = mcCard ? parseCardKey(mcCard.card_key).name : 'カード';
          return (
            <div style={deckS.mScrim} onClick={() => setMoveConfirm(null)}>
              <div style={deckS.mBox} onClick={(e) => e.stopPropagation()}>
                <div style={deckS.mTitle}>デッキ移動の確認</div>
                <div style={deckS.mMsg}>《{nm}》は デッキ{mc.fromDeckNo} に編成済みです。<br />デッキ{mc.fromDeckNo} から外して デッキ{deckNo} に移動しますか？</div>
                <div style={deckS.mBtns}>
                  <button style={deckS.mCancel} onClick={() => setMoveConfirm(null)} disabled={busy}>やめる</button>
                  <button style={deckS.mMove} onClick={() => { const m = mc; setMoveConfirm(null); commit(withSlot(m.slot, m.cardId)); }} disabled={busy}>{busy ? '移動中…' : '移動する'}</button>
                </div>
              </div>
            </div>
          );
        })()}
      </div>
    );
  }
```
【置換】
```jsx
  if (picking !== null) {
    const stateOf = (c) => {
      const sameDeckOther = curSlots.some((id, i) => id === c.id && i !== picking);
      const sp = !!(spSet && spSet[c.id]);
      const sortieLocked = (c.tansaku_deck_no != null) || (c.boss_deck_no != null);
      const otherDeck = deckNoOf(c.id);
      return { sameDeckOther, sp, sortieLocked, otherDeck };
    };
    const getStatus = (c) => {
      const st = stateOf(c);
      const dim = st.sameDeckOther || st.sp || st.sortieLocked;
      const tag = st.sp ? '離脱中' : st.sortieLocked ? (c.tansaku_deck_no != null ? '探索中' : '出撃中') : st.sameDeckOther ? '編成中' : st.otherDeck ? ('デッキ' + st.otherDeck) : null;
      const reason = st.sp ? 'SP離脱中（本日）は編成できません' : st.sortieLocked ? (c.tansaku_deck_no != null ? '探索に出撃中です' : 'ボスに出撃中です') : st.sameDeckOther ? 'このデッキの別の枠で編成中です' : '選べません';
      return { disabled: dim, dim, tag, reason };
    };
    const chooseLabel = (c) => { const ot = deckNoOf(c.id); return ot ? ('これを選ぶ（デッキ' + ot + 'から移動）') : 'これを選ぶ'; };
    const onChoose = (c) => { const ot = deckNoOf(c.id); if (ot) setMoveConfirm({ cardId: c.id, slot: picking, fromDeckNo: ot }); else commit(withSlot(picking, c.id)); };
    return (
      <>
        <CardPicker key={picking} title={'枠 ' + (picking + 1) + ' に入れるカード'} cards={cards} getStatus={getStatus} chooseLabel={chooseLabel} onChoose={onChoose} onClear={() => { if (!busy) commit(withSlot(picking, null)); }} back={() => setPicking(null)} busy={busy} flash={flash} />
        {moveConfirm && (() => {
          const mc = moveConfirm; const mcCard = cardById[mc.cardId];
          const nm = mcCard ? parseCardKey(mcCard.card_key).name : 'カード';
          return (
            <div style={deckS.mScrim} onClick={() => setMoveConfirm(null)}>
              <div style={deckS.mBox} onClick={(e) => e.stopPropagation()}>
                <div style={deckS.mTitle}>デッキ移動の確認</div>
                <div style={deckS.mMsg}>《{nm}》は デッキ{mc.fromDeckNo} に編成済みです。<br />デッキ{mc.fromDeckNo} から外して デッキ{deckNo} に移動しますか？</div>
                <div style={deckS.mBtns}>
                  <button style={deckS.mCancel} onClick={() => setMoveConfirm(null)} disabled={busy}>やめる</button>
                  <button style={deckS.mMove} onClick={() => { const m = mc; setMoveConfirm(null); commit(withSlot(m.slot, m.cardId)); }} disabled={busy}>{busy ? '移動中…' : '移動する'}</button>
                </div>
              </div>
            </div>
          );
        })()}
      </>
    );
  }
```

---

## 確認事項
- CardPicker は内部 state（sel/facet/fval/sortField/sortDir/skillMap/selSkills）を保持。`key={picking}` で枠を切替えるたび選択状態がリセットされる。
- ソート初期値＝本体戦闘力の降順。フィルタは属性/武器/レア/種族を1ファセットずつ切替（「すべて」で全件）。
- スキルは選択時に getCardSkills を非同期取得（取得中は「読込中…」）。固定（slot0）＋移植スロット1/2を表示、空きは「（空き）」、SPは移植スロットを出さない。
- 右詳細は **本体戦闘力**（computeStats.body）。充填行は非SPのみ（情報表示）。属性/武器は DeckBadges の色付きチップ。
- 選択可否（編成中/SP離脱中/探索中/出撃中＝選択不可、他デッキ＝選択可で確定時に移動確認）と「この枠を空にする」は従来どおり。移動確認モーダルは onChoose 経由で表示。
- 構文：CardPicker・置換後ブロックとも Babel(JSX) パース OK。
- 適用後 commit & push → Ctrl+Shift+R。デッキ編成→空き枠（＋）→上部にフィルタ/ソート、左に一覧、右にスキルまで含む詳細（本体戦闘力）→「これを選ぶ」。他デッキ在籍は「これを選ぶ（デッキN から移動）」→確認モーダル。
