# Claude Code 指示書：⑥ 強化合成の入口を「図鑑」→「専用の本体ピッカー」へ

対象：`Chikarian/index.html`。HEAD（④適用後）基準。
背景：home「強化合成」ボタンの遷移先が現状 `ZukanScreen`（図鑑・ownedタブ）そのもの＝「強化合成のページに図鑑を使っている」状態。これを、④と同じ**左サムネ＋右詳細**の専用ピッカー `KyokaScreen` に置換する。選んだら従来の `KyokaView`（強化合成本体）へ遷移。
方針：**KyokaView 本体は不変**（ラップするだけ）。pickS スタイルは④で追加済みを再利用。CardDetail からの「★強化」導線（図鑑閲覧時）は従来どおり残す（別入口）。ロック中カードは強化不可（理由表示）。SP も本体に選べる（KyokaView が同名SP素材に対応）。
編集2箇所、文字列アンカー一致。構文は Babel(JSX) 検証済み。参照シンボル（pickS/computeStats/cardFullName/parseCardKey/CardThumb/DeckSlotArt/S）は定義済み。新規 import 不要。

---

## 編集1：KyokaScreen を追加（KyokaView の直前に挿入）

【検索（厳密一致）】
```
function KyokaView({ base, cards, profile, refreshAll, onBack, flash }) {
```
【置換】
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

function KyokaView({ base, cards, profile, refreshAll, onBack, flash }) {
```

---

## 編集2：home「強化合成」の遷移先を ZukanScreen → KyokaScreen に変更

【検索（厳密一致）】
```
    else if (screen === 'kyoka') body = <ZukanScreen cards={cards} profile={profile} refreshAll={refreshAll} initialTab="owned" back={() => setScreen('home')} flash={flash} />;
```
【置換】
```
    else if (screen === 'kyoka') body = <KyokaScreen cards={cards} profile={profile} refreshAll={refreshAll} back={() => setScreen('home')} flash={flash} />;
```

---

## 確認事項
- `KyokaScreen` は内部 state `baseId` を持ち、未選択時は本体ピッカー（左一覧＋右詳細＋「このカードを強化する」）、選択後は `<KyokaView base=… onBack={()=>setBaseId(null)}>` を表示。KyokaView の戻るで本体ピッカーへ、本体ピッカーの戻るで home へ（2段戻り）。
- 強化後も本体は残る（★+1）。`cardById` から都度引くため refreshAll 後の最新★が反映される。
- ロック中カードは左で淡色＋「ロック中」、右で「ロック中（強化できません）」＝強化不可（CardDetail の★強化 disabled と整合）。
- 図鑑(ZukanScreen)は「図鑑」ボタンからのみ起動に戻る（強化合成では使わない）。
- 適用後 commit & push → Ctrl+Shift+R。home→強化合成→**左に所持一覧・右に詳細**→「このカードを強化する」→従来の強化合成画面（素材選択→強化する）。
