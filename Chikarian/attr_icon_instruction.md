# Claude Code 指示書：⑧ 属性アイコンの実装（ic_attr_* を DeckBadges に組込み）

対象：`Chikarian/index.html`。HEAD（⑥適用後）基準。
背景：属性アイコン画像 `images/ic_attr_hana.png`(花)・`ic_attr_ha.png`(葉)・`ic_attr_shin.png`(芯) が**実在**するのに ASSETS 未登録で未使用だった。これを属性/武器バッジの中枢 `DeckBadges` に組み込み、デッキ枠および今後の CardPicker 等で属性をアイコン表示する。
注意：**武器アイコン（剣/盾/杖）は素材が存在しない**ため武器は従来どおりテキストバッジ。属性アイコンの読込失敗時はテキストバッジに自動フォールバック（onError）。
編集5箇所、文字列アンカー一致。新コンポーネント AttrIcon は Babel(JSX) 検証済み。parseCardKey に `attrKey`（属性キー hana/ha/shin）を追加（既存フィールドは不変＝後方互換）。

---

## 編集1：parseCardKey（SP）の返り値に attrKey を追加

【検索（厳密一致）】
```
    return { rarity: 'sp', name: n, attr: '', weap: '' };
```
【置換】
```
    return { rarity: 'sp', name: n, attr: '', weap: '', attrKey: '' };
```

---

## 編集2：parseCardKey（通常）の返り値に attrKey を追加

【検索（厳密一致）】
```
  return { rarity: rar, name: isMeshibe ? 'めしべだけマン' : 'ハイビスカスマン', attr: ATTR_JA[p[2]] || '', weap: WEAP_JA[p[3]] || '' };
```
【置換】
```
  return { rarity: rar, name: isMeshibe ? 'めしべだけマン' : 'ハイビスカスマン', attr: ATTR_JA[p[2]] || '', weap: WEAP_JA[p[3]] || '', attrKey: p[2] || '' };
```

---

## 編集3：ATTR_IC（属性キー→アイコンパス）を WEAP_JA の直後に追加

【検索（厳密一致）】
```
const WEAP_JA = { ken: '剣', tate: '盾', tsue: '杖' };
```
【置換】
```
const WEAP_JA = { ken: '剣', tate: '盾', tsue: '杖' };
const ATTR_IC = { hana: './images/ic_attr_hana.png', ha: './images/ic_attr_ha.png', shin: './images/ic_attr_shin.png' };
```

---

## 編集4：deckS に attrIc スタイルを追加（deckS 先頭に挿入）

【検索（厳密一致）】
```
const deckS = {
```
【置換】
```
const deckS = {
  attrIc: { width: 18, height: 18, borderRadius: '50%', objectFit: 'cover', verticalAlign: 'middle', boxShadow: '0 0 0 1px rgba(232,194,90,.45)', background: '#241018' },
```

---

## 編集5：DeckBadges を AttrIcon＋新DeckBadges に置換

【検索（厳密一致・関数全体）】
```jsx
function DeckBadges({ info }) {
  // SP は無属性＝SPバッジ、それ以外は属性＋武器バッジ（色は mockup 踏襲）
  if (info.rarity === 'sp') return <span style={{ ...deckS.badge, background: 'linear-gradient(90deg,#ffe39a,#e8b54d)' }}>SP</span>;
  return (<>
    <span style={{ ...deckS.badge, background: DECK_ATTR_COL[info.attr] || '#888' }}>{info.attr}</span>
    <span style={deckS.wbadge}>{info.weap}</span>
  </>);
}
```
【置換】
```jsx
function AttrIcon({ info }) {
  const [err, setErr] = useState(false);
  const src = ATTR_IC[info.attrKey];
  if (!src || err) return <span style={{ ...deckS.badge, background: DECK_ATTR_COL[info.attr] || '#888' }}>{info.attr}</span>;
  return <img src={src} alt={info.attr} title={info.attr} style={deckS.attrIc} onError={() => setErr(true)} />;
}
function DeckBadges({ info }) {
  // SP は無属性＝SPバッジ。属性は画像アイコン（ic_attr_*・onError時はテキストバッジ）＋武器はテキストバッジ（武器アイコン素材は未作成）
  if (info.rarity === 'sp') return <span style={{ ...deckS.badge, background: 'linear-gradient(90deg,#ffe39a,#e8b54d)' }}>SP</span>;
  return (<>
    <AttrIcon info={info} />
    <span style={deckS.wbadge}>{info.weap}</span>
  </>);
}
```

---

## 確認事項
- 属性アイコンの接尾辞＝属性キー（hana/ha/shin）。めしべは芯属性なので ic_attr_shin.png を共用（専用素材は不要）。
- AttrIcon は画像読込失敗時に従来の色付きテキストバッジへフォールバック（onError）。SPは従来どおりSPバッジ。武器は従来どおりテキストバッジ。
- DeckBadges を使う箇所（デッキ枠スロットのバッジ等）に属性アイコンが反映される。CardPicker（⑦・未適用）も DeckBadges を使うため、⑦適用後はピッカー一覧/詳細にも属性アイコンが出る。
- parseCardKey は attrKey を追加しただけで既存フィールド（rarity/name/attr/weap）は不変＝既存呼び出しに影響なし。
- 適用後 commit & push → Ctrl+Shift+R。デッキ編成画面のカードバッジが属性アイコンになることを確認。
