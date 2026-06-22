# Claude Code 指示書：CardDetail カードイラストの潰れ修正

対象：`Chikarian/index.html`。HEAD 75232d7 基準。
症状：図鑑→カードタップの詳細(CardDetail)で、上部の大カード絵が薄く潰れる（zS.dCard の aspectRatio がグリッド外でも当該環境で効かず高さ0付近にcollapse）。図鑑グリッドと同じ padding-top ハックで確実に直す。編集2箇所・文字列アンカー一致。

## 編集1：zS.dCard を幅コンテナ化（aspectRatio 撤去）
枠線/背景/角丸/影は ZDetailArt 側（内側）へ移すため、dCard は幅指定のみにする。

【検索（厳密一致）】
```
  dCard: { width: '66%', maxWidth: 240, aspectRatio: '2/3', borderRadius: 14, overflow: 'hidden', border: '2px solid rgba(232,194,90,.6)', background: '#241018', position: 'relative', boxShadow: '0 6px 24px rgba(0,0,0,.5)' },
```
【置換】
```
  dCard: { width: '66%', maxWidth: 240, position: 'relative' },
```

## 編集2：ZDetailArt を padding-top ハックの自己完結ボックスに置換
内側 div を paddingTop:'150%'（親=dCard の幅基準で 2:3 高さ確定）にし、絵/フォールバックを absolute inset:0 で敷く。

【検索（厳密一致・関数まるごと）】
```jsx
function ZDetailArt({ cardKey, info }) {
  const [err, setErr] = useState(false);
  if (err) return <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: 6, textAlign: 'center' }}><div style={{ fontSize: 34 }}>❖</div><div style={{ fontSize: 12, color: '#e7d3a6', marginTop: 4 }}>{info.name}</div>{(info.attr || info.weap) && <div style={{ fontSize: 11, color: '#cdb488' }}>{info.attr}{info.weap}</div>}</div>;
  return <img src={'./images/' + cardKey + '.png'} alt="" onError={() => setErr(true)} style={{ width: '100%', height: '100%', objectFit: 'cover' }} />;
}
```
【置換】
```jsx
function ZDetailArt({ cardKey, info }) {
  const [err, setErr] = useState(false);
  return (
    <div style={{ position: 'relative', width: '100%', paddingTop: '150%', borderRadius: 14, overflow: 'hidden', border: '2px solid rgba(232,194,90,.6)', background: '#241018', boxShadow: '0 6px 24px rgba(0,0,0,.5)' }}>
      {err
        ? <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: 6, textAlign: 'center' }}><div style={{ fontSize: 34 }}>❖</div><div style={{ fontSize: 12, color: '#e7d3a6', marginTop: 4 }}>{info.name}</div>{(info.attr || info.weap) && <div style={{ fontSize: 11, color: '#cdb488' }}>{info.attr}{info.weap}</div>}</div>
        : <img src={'./images/' + cardKey + '.png'} alt="" onError={() => setErr(true)} style={{ position: 'absolute', inset: 0, width: '100%', height: '100%', objectFit: 'cover' }} />}
    </div>
  );
}
```

## 確認
- 適用後 commit & push → Ctrl+Shift+R。図鑑→任意カード→詳細で**大カードが2:3で正しく表示**されること（潰れ解消）。
- 他の画面（CardThumb/GCard 等）は不変。
