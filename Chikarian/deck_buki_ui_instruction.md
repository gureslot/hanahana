# Claude Code 指示書：デッキ編成画面に武気充填UI（ゲージ表示＋±/最大/空＋質選択）

対象：`Chikarian/index.html`。HEAD 4b3f768 基準。
目的：DeckScreen に「各カードの充填ゲージ表示／タップで微調整モーダル（装備の質・±1・最大充填・空にする）／デッキ単位の最大充填・空にする／武気プール残」を追加。武気の付け外しをデッキ画面で完結させる。
方針：**追加のみ**。既存のスロット描画・aspectRatio・picker・commit 等は不変。ゲージはスロット行の**直下に並行行**で出す（カード下部の badges と重ねない）。質アンロックは鍛冶屋Lv（getKajiyaOrders の claimed 最大）準拠＝EquipView と同基準。容量・色は既存 top-level の bukiCapacity / BUKI_COLOR を再利用。equip_buki(id,quality,amount) は amount=0→空 / 大量→最大 / loaded±1→微調整。
編集は7箇所、すべて文字列アンカー一致。

---

## 編集1：bukiS スタイルを追加（DeckBadges の直前にトップレベルで挿入）

【検索（厳密一致）】
```
function DeckBadges({ info }) {
```
【置換】
```
const bukiS = {
  deckBtns: { display: 'flex', gap: 8, justifyContent: 'center', alignItems: 'center', flexWrap: 'wrap', marginTop: 10 },
  fillBtn: { fontFamily: 'inherit', fontSize: 11, fontWeight: 800, color: '#bfe3ff', background: 'rgba(40,60,80,.6)', border: '1px solid rgba(120,200,255,.45)', borderRadius: 10, padding: '7px 12px', cursor: 'pointer' },
  emptyBtn: { fontFamily: 'inherit', fontSize: 11, fontWeight: 800, color: '#ffc7b0', background: 'rgba(70,40,30,.6)', border: '1px solid rgba(255,150,110,.45)', borderRadius: 10, padding: '7px 12px', cursor: 'pointer' },
  off: { opacity: .4, cursor: 'default' },
  poolTag: { fontSize: 11, color: '#ffe39a' },
  row: { display: 'flex', gap: 10, padding: '0 4px 4px', justifyContent: 'center' },
  cell: { flex: 1, maxWidth: 128, display: 'flex', flexDirection: 'column', gap: 3, background: 'none', border: 'none', padding: 0, fontFamily: 'inherit', cursor: 'pointer' },
  gauge: { height: 6, borderRadius: 3, background: 'rgba(255,255,255,.14)', overflow: 'hidden' },
  lab: { fontSize: 10, color: '#cdb488', textAlign: 'center', whiteSpace: 'nowrap' },
  spLab: { fontSize: 9, color: '#7a6a8a', textAlign: 'center' },
  scrim: { position: 'fixed', inset: 0, zIndex: 300, background: 'rgba(4,3,6,.72)', display: 'flex', alignItems: 'flex-end', justifyContent: 'center' },
  sheet: { width: '100%', maxWidth: 480, background: 'linear-gradient(180deg,#1a0e16,#120a12)', borderTop: '2px solid rgba(232,194,90,.5)', borderRadius: '18px 18px 0 0', padding: '16px 16px 22px', boxShadow: '0 -8px 30px rgba(0,0,0,.6)' },
  title: { fontSize: 15, fontWeight: 800, color: GOLD_HI, textAlign: 'center' },
  cap: { fontSize: 12, color: '#cdb488', textAlign: 'center', marginTop: 4 },
  bigGauge: { height: 10, borderRadius: 5, background: 'rgba(255,255,255,.14)', overflow: 'hidden', margin: '8px 0 12px' },
  qrow: { display: 'flex', gap: 6, justifyContent: 'center' },
  q: { flex: 1, maxWidth: 92, fontFamily: 'inherit', fontSize: 11, color: GOLD_HI, background: PANEL, border: BORDER, borderRadius: 10, padding: '6px 2px', cursor: 'pointer', lineHeight: 1.3 },
  qOn: { background: 'linear-gradient(180deg,rgba(255,228,154,.26),rgba(232,181,77,.14))', boxShadow: '0 0 10px rgba(255,200,90,.3)' },
  qLock: { opacity: .4, cursor: 'default' },
  pmRow: { display: 'flex', gap: 8, justifyContent: 'center', alignItems: 'center', marginTop: 14 },
  pm: { width: 52, fontFamily: 'inherit', fontSize: 22, fontWeight: 800, color: GOLD_HI, background: PANEL, border: BORDER, borderRadius: 12, padding: '8px 0', cursor: 'pointer' },
  mid: { flex: 1, maxWidth: 130, fontFamily: 'inherit', fontSize: 12, fontWeight: 700, color: GOLD_HI, background: PANEL, border: BORDER, borderRadius: 12, padding: '10px 4px', cursor: 'pointer' },
  close: { display: 'block', width: '100%', marginTop: 16, fontFamily: 'inherit', fontSize: 13, color: '#b6a890', background: 'none', border: 'none', cursor: 'pointer' },
};

function DeckBadges({ info }) {
```

---

## 編集2：state を追加（recallConfirm の直後）

【検索（厳密一致）】
```
  const [recallConfirm, setRecallConfirm] = useState(null); // {kind:'boss'|'tansaku', deckNo} 帰還/回収の確認
```
【置換】
```
  const [recallConfirm, setRecallConfirm] = useState(null); // {kind:'boss'|'tansaku', deckNo} 帰還/回収の確認
  const [bukiEdit, setBukiEdit] = useState(null);   // 武気充填モーダル対象 card_id
  const [bukiBusy, setBukiBusy] = useState(false);
  const [pool, setPool] = useState(null);           // renkiden 武気プール
  const [kajiyaLv, setKajiyaLv] = useState(1);       // 装備の質アンロック上限
```

---

## 編集3：プール／鍛冶屋Lv 読込の useEffect を追加（deckNo リセット effect の直後）

【検索（厳密一致）】
```
  useEffect(() => { setPicking(null); setMoveConfirm(null); setRecallConfirm(null); }, [deckNo]);   // デッキ切替で編集状態をリセット
```
【置換】
```
  useEffect(() => { setPicking(null); setMoveConfirm(null); setRecallConfirm(null); }, [deckNo]);   // デッキ切替で編集状態をリセット
  useEffect(() => {
    (async () => {
      try { const r = normalizeRk(await ChikarianAPI.getRenkiden()); setPool(r ? r.buki : 0); } catch (e) { setPool(0); }
      try { const os = await ChikarianAPI.getKajiyaOrders() || []; setKajiyaLv(os.filter(o => o.claimed).reduce((mx, o) => Math.max(mx, Q_LV[o.quality] || 0), 1)); } catch (e) {}
    })();
  }, []);
```

---

## 編集4：武気ハンドラを追加（releaseTansaku 直後・if (decks === null) の前）

【検索（厳密一致・複数行）】
```
    try { await ChikarianAPI.collectTansaku(deckNo); await loadDecks(); await refreshAll(); flash('回収しました'); }
    catch (e) { flash(errMsg(e)); } finally { setBusy(false); }
  }

  if (decks === null) return <Booting />;
```
【置換】
```
    try { await ChikarianAPI.collectTansaku(deckNo); await loadDecks(); await refreshAll(); flash('回収しました'); }
    catch (e) { flash(errMsg(e)); } finally { setBusy(false); }
  }

  async function loadPool() { try { const r = normalizeRk(await ChikarianAPI.getRenkiden()); setPool(r ? r.buki : 0); } catch (e) {} }
  // 武気の付け外し（amount: 0=空 / 100000=最大 / loaded±1=微調整）。質変更は loaded 維持で再込め（サーバが返却→引直し）。
  async function applyBuki(c, quality, amount) {
    if (bukiBusy || deckSortie) return; setBukiBusy(true);
    try { await ChikarianAPI.equipBuki(c.id, quality, Math.max(0, amount)); await loadPool(); await refreshAll(); }
    catch (e) { flash(errMsg(e)); } finally { setBukiBusy(false); }
  }
  // デッキ単位の一括（最大充填 / 空にする）。SPはスキップ。
  async function fillDeck(empty) {
    if (bukiBusy || deckSortie) return; setBukiBusy(true);
    try {
      for (const id of curSlots) { const c = id && cardById[id]; if (!c || /_sp$/.test(c.card_key)) continue; await ChikarianAPI.equipBuki(c.id, c.quality || 'crude', empty ? 0 : 100000); }
      await loadPool(); await refreshAll();
    } catch (e) { flash(errMsg(e)); } finally { setBukiBusy(false); }
  }

  if (decks === null) return <Booting />;
```

---

## 編集5：デッキ単位の一括ボタン（最大充填/空にする＋プール残）を追加（3枠コメントの前）

【検索（厳密一致）】
```
        {/* 3枠（即確定：枠タップで選択／×で即空に。出撃中デッキは編集不可） */}
```
【置換】
```
        {/* デッキ単位の武気一括（最大充填 / 空にする）＋プール残 */}
        {!deckSortie && <div style={bukiS.deckBtns}>
          <button disabled={bukiBusy || busy} onClick={() => fillDeck(false)} style={{ ...bukiS.fillBtn, ...((bukiBusy || busy) ? bukiS.off : {}) }}>{bukiBusy ? '処理中…' : '⚡ 最大充填'}</button>
          <button disabled={bukiBusy || busy} onClick={() => fillDeck(true)} style={{ ...bukiS.emptyBtn, ...((bukiBusy || busy) ? bukiS.off : {}) }}>武気を空にする</button>
          {pool != null && <span style={bukiS.poolTag}>プール {pool.toLocaleString()}</span>}
        </div>}
        {/* 3枠（即確定：枠タップで選択／×で即空に。出撃中デッキは編集不可） */}
```

---

## 編集6：各カードの充填ゲージ行を追加（コスト目安コメントの前）

【検索（厳密一致）】
```
        {/* コスト目安（mockup .summary：中央寄せ・本番の文言を維持） */}
```
【置換】
```
        {/* 各カードの充填ゲージ（タップで微調整モーダル）。SP は武気なし */}
        {!deckSortie && <div style={bukiS.row}>
          {[0, 1, 2].map(slot => {
            const id = curSlots[slot]; const c = id ? cardById[id] : null;
            if (!c) return <div key={slot} style={bukiS.cell} />;
            if (/_sp$/.test(c.card_key)) return <div key={slot} style={{ ...bukiS.cell, cursor: 'default' }}><div style={bukiS.spLab}>SP・武気なし</div></div>;
            const cap = bukiCapacity(c), loaded = c.loaded_buki || 0, pct = cap > 0 ? Math.min(100, loaded / cap * 100) : 0;
            return (
              <button key={slot} disabled={busy || bukiBusy} onClick={() => setBukiEdit(c.id)} style={bukiS.cell}>
                <div style={bukiS.gauge}><div style={{ height: '100%', width: pct + '%', background: BUKI_COLOR[c.quality] || '#9a7' }} /></div>
                <div style={bukiS.lab}>武 {loaded}/{cap} ⚡</div>
              </button>
            );
          })}
        </div>}

        {/* コスト目安（mockup .summary：中央寄せ・本番の文言を維持） */}
```

---

## 編集7：武気微調整モーダルを追加（帰還/回収モーダルのコメントの前）

【検索（厳密一致）】
```
      {/* 帰還/回収の確認モーダル（moveConfirm と同じ意匠） */}
```
【置換】
```
        {/* 武気充填の微調整モーダル（質・±・最大・空） */}
        {bukiEdit && (() => {
          const c = cardById[bukiEdit]; if (!c) return null;
          const cap = bukiCapacity(c), loaded = c.loaded_buki || 0, q = c.quality || 'crude';
          const pct = cap > 0 ? Math.min(100, loaded / cap * 100) : 0;
          return (
            <div style={bukiS.scrim} onClick={() => { if (!bukiBusy) setBukiEdit(null); }}>
              <div style={bukiS.sheet} onClick={(e) => e.stopPropagation()}>
                <div style={bukiS.title}>{parseCardKey(c.card_key).name} ・武気充填</div>
                <div style={bukiS.cap}>{loaded} / {cap} 枠　｜　プール {pool != null ? pool.toLocaleString() : '—'}</div>
                <div style={bukiS.bigGauge}><div style={{ height: '100%', width: pct + '%', background: BUKI_COLOR[q] || '#9a7' }} /></div>
                <div style={bukiS.qrow}>
                  {Q_ORDER.map(qq => { const locked = Q_LV[qq] > kajiyaLv; return (
                    <button key={qq} disabled={bukiBusy || locked} onClick={() => applyBuki(c, qq, loaded)} style={{ ...bukiS.q, ...(qq === q ? bukiS.qOn : {}), ...(locked ? bukiS.qLock : {}) }}>{QUALITY_JA[qq]}{locked ? ' 🔒' : ''}<br /><small>攻{QATK[qq]}/コ{Q_COST[qq]}</small></button>
                  ); })}
                </div>
                <div style={bukiS.pmRow}>
                  <button disabled={bukiBusy || loaded <= 0} onClick={() => applyBuki(c, q, loaded - 1)} style={bukiS.pm}>−</button>
                  <button disabled={bukiBusy} onClick={() => applyBuki(c, q, 0)} style={bukiS.mid}>空にする</button>
                  <button disabled={bukiBusy} onClick={() => applyBuki(c, q, 100000)} style={bukiS.mid}>最大充填</button>
                  <button disabled={bukiBusy || loaded >= cap} onClick={() => applyBuki(c, q, loaded + 1)} style={bukiS.pm}>＋</button>
                </div>
                <button style={bukiS.close} onClick={() => { if (!bukiBusy) setBukiEdit(null); }}>閉じる</button>
              </div>
            </div>
          );
        })()}

      {/* 帰還/回収の確認モーダル（moveConfirm と同じ意匠） */}
```

---

## 確認事項
- 使用する既存シンボルは全て top-level で定義済み：`bukiCapacity` `BUKI_COLOR` `normalizeRk` `Q_ORDER` `Q_LV` `Q_COST` `QATK` `QUALITY_JA` `GOLD_HI` `PANEL` `BORDER` `ChikarianAPI.equipBuki/getRenkiden/getKajiyaOrders` `parseCardKey` `errMsg` `useState` `useEffect`。新規 import 不要。
- 既存の `EquipView`（装備ページ）と CardDetail の「装備（充填）」ボタンは**今回は残す**（DeckScreen 側の動作確認後に撤去予定）。
- 出撃中デッキ（deckSortie=true）では一括ボタン・ゲージ行・モーダルを出さない/無効化（デプロイ済み構成の武気は変更不可）。
- 構文：本指示の追加コードは Babel(JSXプラグイン)で構文検証済み。
- 適用後 commit & push → Ctrl+Shift+R。デッキ編成で「各カード下にゲージ＋『武 X/Y ⚡』」「カードのゲージをタップ→下部シートで 質/−/空/最大/＋」「デッキ上部に⚡最大充填・武気を空にする＋プール残」を確認。SP カードは「SP・武気なし」。
