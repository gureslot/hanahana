# Chikarian バッチ：転移の素材カード選択に並び替え（レア/Lv/本体/属性/武器）
対象: `Chikarian/index.html`（このファイルのみ）。SQL不要。`function SkillView` の転移タブ内です。

## 何を入れるか
- 素材グリッドの上に並び替えボタン（レア／Lv／本体／属性／武器）。同じボタン再押下で昇順/降順トグル。既定はレア降順（SSRが上）。
- すべて card_key・カード値から算出（追加のサーバ取得なし）。固定スキルのレア・対象属性はカードのレア・属性とほぼ一致するため、実用上「対象属性別」の役割も兼ねます。
- 同値はサブキーで本体降順（属性/武器でまとめつつ強い順）。表示のみで挙動・サーバ判定は不変。

各編集は **検索文字列が1回だけ出現** することを確認してから置換。

---

### 編集 転S1 tSort/tDir状態
**検索:**
```jsx
  const [tResult, setTResult] = useState(null);
```
**置換:**
```jsx
  const [tResult, setTResult] = useState(null);
  const [tSort, setTSort] = useState('rarity');   // 転移素材の並び替え
  const [tDir, setTDir] = useState('desc');
```

### 編集 転S2 素材ソートUI+並び替え
**検索:**
```jsx
                <div className="sk-seclabel">素材カードを選ぶ（ロック/SPは不可・素材は消滅）</div>
                <div className="sk-grid">
                  {(cards || []).filter(c => c.id !== base.id && !c.locked && !c.card_key.endsWith('_sp') && c.boss_deck_no == null && c.tansaku_deck_no == null).map(c => (
                    <div key={c.id} style={{ outline: srcId === c.id ? '2px solid #c7a14e' : 'none', borderRadius: 10 }}>
                      <CardThumb card={c} small onClick={() => pickSrc(c.id)} />
                      <div style={{ fontSize: 8, lineHeight: 1.2, textAlign: 'center', color: '#cdb488', marginTop: 1 }}>{cardFullName(c)}</div>
                    </div>
                  ))}
                </div>
```
**置換:**
```jsx
                <div className="sk-seclabel">素材カードを選ぶ（ロック/SPは不可・素材は消滅）</div>
                <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, alignItems: 'center', margin: '0 0 6px' }}>
                  <span style={{ fontSize: 10, color: '#7d7160' }}>並び替え</span>
                  {[['rarity', 'レア'], ['lv', 'Lv'], ['body', '本体'], ['attr', '属性'], ['weap', '武器']].map(([k, l]) => (
                    <button key={k} onClick={() => { if (tSort === k) setTDir(d => d === 'asc' ? 'desc' : 'asc'); else { setTSort(k); setTDir('desc'); } }} style={{ fontFamily: 'inherit', fontSize: 11, fontWeight: 700, padding: '4px 9px', borderRadius: 10, cursor: 'pointer', border: '1px solid ' + (tSort === k ? '#c7a14e' : '#3a2c22'), background: tSort === k ? 'linear-gradient(180deg,#ecd28a,#c7a14e)' : '#181210', color: tSort === k ? '#0c0a09' : '#b6a890' }}>{l}{tSort === k ? (tDir === 'asc' ? ' ▲' : ' ▼') : ''}</button>
                  ))}
                </div>
                <div className="sk-grid">
                  {(() => {
                    const RR = { n: 0, r: 1, sr: 2, ssr: 3, sp: 4 }, AO = { hana: 0, ha: 1, shin: 2 }, WO = { ken: 0, tate: 1, tsue: 2 };
                    const dir = tDir === 'asc' ? 1 : -1, key = ['lv', 'body', 'attr', 'weap'].includes(tSort) ? tSort : 'rar';
                    return (cards || [])
                      .filter(c => c.id !== base.id && !c.locked && !c.card_key.endsWith('_sp') && c.boss_deck_no == null && c.tansaku_deck_no == null)
                      .map(c => { const pk = parseCardKey(c.card_key); const pt = (c.card_key || '').split('_'); return { c, body: computeStats(c).body, rar: RR[pk.rarity] != null ? RR[pk.rarity] : 0, attr: AO[pk.attrKey] != null ? AO[pk.attrKey] : 9, weap: WO[pt[3]] != null ? WO[pt[3]] : 9, lv: c.lv || 1 }; })
                      .sort((a, b) => { const d = (a[key] - b[key]) * dir; return d !== 0 ? d : (b.body - a.body); })
                      .map(({ c }) => (
                        <div key={c.id} style={{ outline: srcId === c.id ? '2px solid #c7a14e' : 'none', borderRadius: 10 }}>
                          <CardThumb card={c} small onClick={() => pickSrc(c.id)} />
                          <div style={{ fontSize: 8, lineHeight: 1.2, textAlign: 'center', color: '#cdb488', marginTop: 1 }}>{cardFullName(c)}</div>
                        </div>
                      ));
                  })()}
                </div>
```
