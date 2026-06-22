# Claude Code 指示書：④ カード選択を「左サムネ＋右詳細」へ（モック準拠）

対象：`Chikarian/index.html`。HEAD（③適用後）基準。
目的：デッキ編成の「枠Nに入れるカード」をモック(kyoka-mockup/Image7)準拠の **左：サムネ一覧／右：詳細＋『これを選ぶ』** に作り替える。タップ即入替をやめ、名前・レア・属性・武器・Lv・戦闘力・充填を見てから確定。
方針：既存の選択可否ロジック（編成中／SP離脱中／探索中・出撃中／他デッキ＝移動確認）を**完全保持**。コミット系（commit/withSlot/setMoveConfirm）も不変。④は picker パネルのみを差し替え（③が追加したメイン表示の武気UIには触れない）。
編集4箇所、すべて文字列アンカー一致。参照シンボル（COST_BY_RAR/computeStats/bukiCapacity/DeckSlotArt/CardThumb/cardFullName/parseCardKey）は全て定義済み。新規 import 不要。構文は Babel(JSX) 検証済み。

---

## 編集1：pickS スタイルを追加（DeckBadges の直前にトップレベルで挿入）

【検索（厳密一致）】
```
function DeckBadges({ info }) {
```
【置換】
```
const pickS = {
  wrap: { position: 'relative', zIndex: 2, height: '100dvh', display: 'flex', flexDirection: 'column', padding: '14px 12px 14px' },
  head: { display: 'flex', alignItems: 'center', gap: 10, flex: 'none' },
  title: { fontSize: 15, color: GOLD_HI, fontWeight: 700 },
  split: { flex: 1, display: 'flex', gap: 10, marginTop: 12, minHeight: 0 },
  left: { flex: '0 0 42%', overflowY: 'auto', display: 'flex', flexDirection: 'column', gap: 6, paddingRight: 2 },
  empty: { textAlign: 'center', color: '#cdb488', marginTop: 30, fontSize: 12 },
  li: { display: 'flex', gap: 8, alignItems: 'center', textAlign: 'left', background: 'rgba(0,0,0,.3)', border: '1px solid rgba(232,194,90,.25)', borderRadius: 10, padding: 6, cursor: 'pointer', fontFamily: 'inherit' },
  liSel: { border: '1.5px solid rgba(255,210,90,.9)', background: 'linear-gradient(180deg,rgba(255,228,154,.18),rgba(232,181,77,.08))', boxShadow: '0 0 10px rgba(255,200,90,.25)' },
  liThumb: { flex: '0 0 40px', width: 40 },
  liMeta: { flex: 1, minWidth: 0 },
  liName: { fontSize: 10, color: GOLD_HI, fontWeight: 700, lineHeight: 1.25, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' },
  liSub: { fontSize: 9, color: '#cdb488', marginTop: 2 },
  right: { flex: 1, overflowY: 'auto', display: 'flex', flexDirection: 'column', alignItems: 'center', background: 'rgba(0,0,0,.22)', border: '1px solid rgba(232,194,90,.2)', borderRadius: 12, padding: '12px 12px 14px', minWidth: 0 },
  ph: { margin: 'auto', textAlign: 'center', color: '#a98f66', fontSize: 12, lineHeight: 1.9 },
  dArt: { width: 140, height: 210, position: 'relative', borderRadius: 10, overflow: 'hidden', border: '1.5px solid rgba(232,194,90,.5)', background: '#241018', flex: 'none' },
  dName: { fontSize: 13, fontWeight: 800, color: GOLD_HI, textAlign: 'center', marginTop: 10, lineHeight: 1.3 },
  dRow: { width: '100%', display: 'flex', justifyContent: 'space-between', fontSize: 12, color: '#cdb488', padding: '6px 2px', borderBottom: '1px dashed rgba(232,194,90,.18)' },
  dv: { color: GOLD_HI, fontWeight: 700 },
  choose: { width: '100%', marginTop: 14, fontFamily: 'inherit', fontSize: 13, fontWeight: 800, color: '#1a0f06', background: 'linear-gradient(180deg,#ffd98a,#e8a23b)', border: 'none', borderRadius: 12, padding: '12px 8px', cursor: 'pointer', lineHeight: 1.3 },
  dLock: { width: '100%', marginTop: 14, textAlign: 'center', fontSize: 12, color: '#ff9a9a', background: 'rgba(60,20,24,.5)', border: '1px solid rgba(255,120,120,.4)', borderRadius: 12, padding: '12px 8px' },
};

function DeckBadges({ info }) {
```

---

## 編集2：pickSel state を追加（kajiyaLv 行の直後）

【検索（厳密一致）】
```
  const [kajiyaLv, setKajiyaLv] = useState(1);       // 装備の質アンロック上限
```
【置換】
```
  const [kajiyaLv, setKajiyaLv] = useState(1);       // 装備の質アンロック上限
  const [pickSel, setPickSel] = useState(null);      // ④ カード選択パネルで選択中の card_id
```

---

## 編集3：選択クリアの useEffect を追加（deckNo リセット effect の直後）

【検索（厳密一致）】
```
  useEffect(() => { setPicking(null); setMoveConfirm(null); setRecallConfirm(null); }, [deckNo]);   // デッキ切替で編集状態をリセット
```
【置換】
```
  useEffect(() => { setPicking(null); setMoveConfirm(null); setRecallConfirm(null); }, [deckNo]);   // デッキ切替で編集状態をリセット
  useEffect(() => { setPickSel(null); }, [picking]);   // ④ 枠を開き直したら選択をクリア
```

---

## 編集4：picker ブロックを全置換（if (picking !== null) { … } をまるごと）

【検索（厳密一致・複数行＝現 picker ブロック全体）】
```jsx
  if (picking !== null) {
    const list = (cards || []);
    return (
      <div style={S.root}>
        <div style={S.bg} /><div style={S.vignette} />
        <div style={{ position: 'relative', zIndex: 2, minHeight: '100dvh', display: 'flex', flexDirection: 'column', padding: '14px 12px 18px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
            <button onClick={() => setPicking(null)} style={{ ...S.lineBtn, padding: '6px 14px' }}>‹ 戻る</button>
            <div style={{ fontSize: 15, color: GOLD_HI, fontWeight: 700 }}>枠 {picking + 1} に入れるカード</div>
          </div>
          <div style={{ flex: 1, overflowY: 'auto', marginTop: 12, opacity: busy ? .6 : 1 }}>
            {list.length === 0
              ? <div style={{ textAlign: 'center', color: '#cdb488', marginTop: 30 }}>所持カードがありません</div>
              : <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4,1fr)', gap: 6 }}>
                  {list.map(c => {
                    const sameDeckOther = curSlots.some((id, i) => id === c.id && i !== picking);  // 同一デッキ内の他枠で使用中
                    const sp = spSet && spSet[c.id];
                    const sortieLocked = (c.tansaku_deck_no != null) || (c.boss_deck_no != null);   // 探索/ボス出撃中＝占有ロック
                    const otherDeck = deckNoOf(c.id);                                              // 他デッキ在籍（選べるが確認）
                    const disabled = busy || sameDeckOther || sp || sortieLocked;
                    const onClick = disabled ? undefined
                      : (otherDeck ? () => setMoveConfirm({ cardId: c.id, slot: picking, fromDeckNo: otherDeck })
                                   : () => commit(withSlot(picking, c.id)));
                    return (
                      <div key={c.id} style={{ position: 'relative', opacity: (sameDeckOther || sp || sortieLocked) ? .4 : 1 }}>
                        <CardThumb card={c} small onClick={onClick} />
                        {sp && <div style={badge('#ff6a7a')}>離脱中</div>}
                        {!sp && sortieLocked && <div style={badge('#ff6a7a')}>{c.tansaku_deck_no != null ? '探索中' : '出撃中'}</div>}
                        {!sp && !sortieLocked && sameDeckOther && <div style={badge('#888')}>編成中</div>}
                        {!sp && !sortieLocked && !sameDeckOther && otherDeck && <div style={deckS.deckMark}>デッキ{otherDeck}</div>}
                        <div style={{ fontSize: 8, lineHeight: 1.2, textAlign: 'center', color: '#cdb488', marginTop: 1 }}>{cardFullName(c)}</div>
                      </div>
                    );
                  })}
                </div>}
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

---

## 確認事項
- 既存の選択可否（編成中／離脱中／探索中・出撃中／他デッキ移動確認）と「この枠を空にする」「移動確認モーダル」は新コードに保持済み。
- 右詳細の大カードは固定枠 140×210＋既存 DeckSlotArt（slotImg=100%/100%）で表示（aspect-ratio 不使用＝崩れない）。
- 適用後 commit & push → Ctrl+Shift+R。デッキ編成→空き枠（＋）タップ→**左に一覧・右に詳細**、左でタップ→右に名前/レア/属性/武器/Lv/戦闘力/充填→「これを選ぶ」で確定。他デッキ在籍カードは「これを選ぶ（デッキN から移動）」→確認モーダル。離脱中/探索中/出撃中/編成中は理由表示で確定不可。
- ③で追加したメイン画面の武気ゲージ・モーダルには未接触（別パネル）。
