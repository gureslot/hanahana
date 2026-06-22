# Claude Code 指示書：図鑑（ZukanScreen）リデザイン

対象：`Chikarian/index.html`（単一ファイル）。HEAD 75232d7 基準。
目的：図鑑のカードが薄く潰れて重なる不具合を解消し、フィルタ（属性/武器/レア/種族の切替）・ソート（レア/レベル/攻撃力）・ページめくり（24件/頁）を追加する。
編集は4箇所。すべて文字列アンカー一致で行う（行番号は参考）。**他の関数・他画面には触れない。**

---

## 編集1：zS.item（重なりの根因修正）
グリッド内で aspectRatio が align-self:stretch と衝突し高さが 0 付近に潰れていた。padding-top ハック（width比150%＝2:3）に置換する。

【検索（厳密一致）】
```
  item: { position: 'relative', width: '100%', aspectRatio: '2/3', borderRadius: 12, overflow: 'hidden', border: '2px solid rgba(232,194,90,.5)', background: '#241018', padding: 0, cursor: 'pointer' },
```
【置換】
```
  item: { position: 'relative', width: '100%', boxSizing: 'content-box', paddingTop: '150%', paddingLeft: 0, paddingRight: 0, paddingBottom: 0, borderRadius: 12, overflow: 'hidden', border: '2px solid rgba(232,194,90,.5)', background: '#241018', cursor: 'pointer', display: 'block' },
```

---

## 編集2：zS.grid（stretch保険＋下パディング縮小）
戻るボタンを下バーへ移すため底パディング84→12。alignItems:'start' を追加（stretch無効化の保険）。

【検索（厳密一致）】
```
  grid: { flex: 1, overflowY: 'auto', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, alignContent: 'start', padding: '2px 16px 84px' },
```
【置換】
```
  grid: { flex: 1, overflowY: 'auto', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 12, alignContent: 'start', alignItems: 'start', padding: '2px 16px 12px' },
```

---

## 編集3：zS に新スタイルキーを追加（ソート行・下バー・ページャ）
`filSel` 行の直後に9キーを挿入する。

【検索（厳密一致）】
```
  filSel: { background: 'linear-gradient(180deg,rgba(255,228,154,.26),rgba(232,181,77,.14))', boxShadow: '0 0 10px rgba(255,200,90,.3)' },
```
【置換】
```
  filSel: { background: 'linear-gradient(180deg,rgba(255,228,154,.26),rgba(232,181,77,.14))', boxShadow: '0 0 10px rgba(255,200,90,.3)' },
  srow: { flex: 'none', display: 'flex', alignItems: 'center', gap: 6, overflowX: 'auto', padding: '4px 14px 2px' },
  slab: { flex: 'none', fontSize: 11, color: '#a98f66', marginRight: 2 },
  sbtn: { flex: 'none', fontFamily: 'inherit', fontSize: 11, color: GOLD_HI, background: PANEL, border: BORDER, borderRadius: 14, padding: '5px 11px', cursor: 'pointer' },
  ssel: { background: 'linear-gradient(180deg,rgba(255,228,154,.26),rgba(232,181,77,.14))', boxShadow: '0 0 10px rgba(255,200,90,.3)' },
  botBar: { flex: 'none', display: 'flex', alignItems: 'center', gap: 8, padding: '8px 14px 14px' },
  back2: { flex: 'none', fontFamily: 'inherit', fontSize: 14, color: GOLD_HI, background: PANEL, border: BORDER, borderRadius: 22, padding: '9px 18px', cursor: 'pointer' },
  pgBtn: { fontFamily: 'inherit', fontSize: 13, color: GOLD_HI, background: PANEL, border: BORDER, borderRadius: 16, padding: '8px 14px', cursor: 'pointer' },
  pgOff: { opacity: .3, cursor: 'default', boxShadow: 'none' },
  pgInfo: { fontSize: 12, color: '#cdb488', minWidth: 60, textAlign: 'center' },
```

---

## 編集4：ZukanScreen 関数を全置換
関数 `function ZukanScreen(...) { ... }`（HEAD で 1283–1347 行、直後が `function CardDetail`）を**まるごと**下記に置換する。開始アンカー `function ZukanScreen({ cards, profile, refreshAll, back, flash, initialTab }) {`、終了は CardDetail 直前の `}`。

```jsx
function ZukanScreen({ cards, profile, refreshAll, back, flash, initialTab }) {
  const PAGE_SIZE = 24;
  const [tab, setTab] = useState(initialTab || 'catalog');   // catalog | owned
  const [facet, setFacet] = useState('attr');                // attr | weap | rarity | species
  const [fval, setFval] = useState('all');                   // 選択中ファセット値 or 'all'
  const [sortField, setSortField] = useState('rarity');      // rarity | lv | atk
  const [sortDir, setSortDir] = useState('desc');            // desc | asc
  const [page, setPage] = useState(0);
  const [zukan, setZukan] = useState(null);
  const [skillMap, setSkillMap] = useState({});
  const [sel, setSel] = useState(null);
  useEffect(() => {
    (async () => {
      try { setZukan(await ChikarianAPI.getZukan() || []); } catch (e) { flash(errMsg(e)); setZukan([]); }
      try { const sm = await ChikarianAPI.getSkillMaster(); const m = {}; (sm || []).forEach(s => { m[s.skill_key] = s; }); setSkillMap(m); } catch (e) {}
    })();
  }, []);
  // 強化等で cards が更新されたら、選択中カードを最新へ同期（素材化で消えたら閉じる）
  useEffect(() => {
    setSel(prev => prev ? ((cards || []).find(c => c.id === prev.id) || null) : prev);
  }, [cards]);
  // フィルタ/ソート/タブ変更時はページを先頭へ
  useEffect(() => { setPage(0); }, [tab, facet, fval, sortField, sortDir]);

  if (sel) return <CardDetail card={sel} cards={cards} profile={profile} skillMap={skillMap} refreshAll={refreshAll} back={() => setSel(null)} onSelect={setSel} flash={flash} />;

  const collected = new Set((zukan || []).map(z => z.card_key));
  const ownedByKey = {};
  (cards || []).forEach(c => { (ownedByKey[c.card_key] = ownedByKey[c.card_key] || []).push(c); });

  // 生キー抽出（SP は属性/レア/種族='sp'・武器なし）。キー形式 chara_<種>_<attr>_<weap>_<rare> / chara_*_sp
  const rawRar = k => k.endsWith('_sp') ? 'sp' : k.split('_').pop();
  const rawAttr = k => k.endsWith('_sp') ? 'sp' : k.split('_')[2];
  const rawWeap = k => k.endsWith('_sp') ? null : k.split('_')[3];
  const rawSpec = k => k.endsWith('_sp') ? 'sp' : k.split('_')[1];   // hibiscus | meshibe
  const RAR_ORD = { n: 0, r: 1, sr: 2, ssr: 3, sp: 4 };

  const FACETS = {
    attr:    { label: '属性', vals: [['hana', '花'], ['shin', '芯'], ['ha', '葉'], ['sp', 'SP']] },
    weap:    { label: '武器', vals: [['ken', '剣'], ['tate', '盾'], ['tsue', '杖']] },
    rarity:  { label: 'レア', vals: [['n', 'N'], ['r', 'R'], ['sr', 'SR'], ['ssr', 'SSR'], ['sp', 'SP']] },
    species: { label: '種族', vals: [['hibiscus', 'ハイビスカス'], ['meshibe', 'めしべ'], ['sp', 'SP']] },
  };
  const FACET_ORDER = ['attr', 'weap', 'rarity', 'species'];
  const matchFacet = k => {
    if (fval === 'all') return true;
    if (facet === 'attr') return rawAttr(k) === fval;
    if (facet === 'weap') return rawWeap(k) === fval;
    if (facet === 'rarity') return rawRar(k) === fval;
    if (facet === 'species') return rawSpec(k) === fval;
    return true;
  };

  // 一覧（owned=各インスタンス / catalog=全41種）→ フィルタ → ソート
  let items;
  if (tab === 'owned') {
    items = (cards || []).map(c => ({ key: c.card_key, card: c, id: c.id, got: true, inst: c }));
  } else {
    items = CATALOG.map(k => { const inst = ownedByKey[k] && ownedByKey[k][0]; return { key: k, card: inst || null, id: 'cat_' + k, got: collected.has(k), inst }; });
  }
  items = items.filter(it => matchFacet(it.key));
  const sval = it => sortField === 'rarity' ? (RAR_ORD[rawRar(it.key)] != null ? RAR_ORD[rawRar(it.key)] : 0)
    : sortField === 'lv' ? (it.card ? (it.card.lv || 1) : 0)
    : (it.card ? computeStats(it.card).sougou : 0);
  const dir = sortDir === 'asc' ? 1 : -1;
  items.sort((a, b) => (sval(a) - sval(b)) * dir || ((RAR_ORD[rawRar(b.key)] || 0) - (RAR_ORD[rawRar(a.key)] || 0)) || a.key.localeCompare(b.key));

  const total = items.length;
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE));
  const pg = Math.min(page, totalPages - 1);
  const pageItems = items.slice(pg * PAGE_SIZE, pg * PAGE_SIZE + PAGE_SIZE);

  const SORTS = [['rarity', 'レアリティ'], ['lv', 'レベル'], ['atk', '攻撃力']];
  const arrow = f => sortField === f ? (sortDir === 'asc' ? ' ▲' : ' ▼') : '';

  return (
    <div style={S.root}>
      <div style={zS.bg} />
      <div style={zS.body}>
        <div style={zS.head}>図鑑</div>
        <div style={zS.tabs}>
          <button style={{ ...zS.tab, ...(tab === 'catalog' ? zS.tabSel : {}) }} onClick={() => setTab('catalog')}>図鑑</button>
          <button style={{ ...zS.tab, ...(tab === 'owned' ? zS.tabSel : {}) }} onClick={() => setTab('owned')}>所持カード（{(cards || []).length}）</button>
        </div>
        <div style={zS.filters}>
          {FACET_ORDER.map(f => <button key={f} style={{ ...zS.fil, ...(facet === f ? zS.filSel : {}) }} onClick={() => { setFacet(f); setFval('all'); }}>{FACETS[f].label}</button>)}
        </div>
        <div style={zS.filters}>
          <button style={{ ...zS.fil, ...(fval === 'all' ? zS.filSel : {}) }} onClick={() => setFval('all')}>すべて</button>
          {FACETS[facet].vals.map(([k, l]) => <button key={k} style={{ ...zS.fil, ...(fval === k ? zS.filSel : {}) }} onClick={() => setFval(k)}>{l}</button>)}
        </div>
        <div style={zS.srow}>
          <span style={zS.slab}>並び替え</span>
          {SORTS.map(([k, l]) => <button key={k} style={{ ...zS.sbtn, ...(sortField === k ? zS.ssel : {}) }} onClick={() => { if (sortField === k) setSortDir(d => d === 'asc' ? 'desc' : 'asc'); else { setSortField(k); setSortDir('desc'); } }}>{l}{arrow(k)}</button>)}
        </div>
        <div style={zS.count}>
          {tab === 'catalog'
            ? <>コンプリート <b style={{ color: '#ffe39a' }}>{collected.size}</b> / {CATALOG.length} 種</>
            : <>所持 <b style={{ color: '#ffe39a' }}>{(cards || []).length}</b> 枚</>}
          {total > 0 && <span style={{ color: '#a98f66' }}>　（{total} 件・{pg + 1}/{totalPages}）</span>}
        </div>
        {total === 0
          ? <div style={{ flex: 1, textAlign: 'center', color: '#cdb488', marginTop: 30, fontSize: 13 }}>{tab === 'owned' ? '該当する所持カードがありません' : '該当カードなし'}</div>
          : <div style={zS.grid}>
              {pageItems.map(it => {
                if (tab === 'catalog' && !it.got) return <ZCard key={it.id} placeholder />;
                return <ZCard key={it.id} cardKey={it.key} star={it.card ? (it.card.star || 0) : 0} recorded={tab === 'catalog' && !it.inst} onClick={it.card ? () => setSel(it.card) : null} />;
              })}
            </div>}
        <div style={zS.botBar}>
          <button style={zS.back2} onClick={back}>‹ 戻る</button>
          <div style={{ flex: 1 }} />
          {totalPages > 1 && <>
            <button style={{ ...zS.pgBtn, ...(pg <= 0 ? zS.pgOff : {}) }} disabled={pg <= 0} onClick={() => setPage(pg - 1)}>‹ 前</button>
            <div style={zS.pgInfo}>{pg + 1} / {totalPages}</div>
            <button style={{ ...zS.pgBtn, ...(pg >= totalPages - 1 ? zS.pgOff : {}) }} disabled={pg >= totalPages - 1} onClick={() => setPage(pg + 1)}>次 ›</button>
          </>}
        </div>
      </div>
    </div>
  );
}
```

---

## 確認事項（重要）
- ZCard / parseCardKey / computeStats / CATALOG / CardDetail は既存のまま使用。**変更しない。**
- 旧 `zS.back`（position:absolute）は未使用になるが**削除不要**（無害）。新レイアウトは `zS.back2` を下バー内で使用。
- 既存の `initialTab` プロップ・getZukan/getSkillMaster ローダー・sel 詳細遷移は維持済み。
- 編集後：commit & push → Ctrl+Shift+R でハードリロード。図鑑/所持の両タブで「2:3カードが重ならず整列・属性/武器/レア/種族で絞り込み・レア/レベル/攻撃力で昇降順・>1頁で前/次ページャ」を確認。
