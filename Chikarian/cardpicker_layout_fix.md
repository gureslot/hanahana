# Claude Code 指示書：⑨ CardPicker レイアウト修正（右詳細のはみ出し／左の幅過多）

対象：`Chikarian/index.html`。⑦適用後の HEAD 基準。
症状：狭い画面で右の詳細欄が画面外にはみ出して見えない／左一覧が幅を取り過ぎ。
原因：cpS.wrap が `width:min(960px,96vw)` ＋ padding で box-sizing 未指定のため実幅が画面超過。左が 40%（最大300）と広い。右が縮まず・長い効果文（日本語）が折り返さずに横へあふれていた。
方針：**cpS オブジェクトを丸ごと差し替え**（CardPicker 本体・呼び出しは不変）。box-sizing 統一、左を狭く（38%・最大196）、右は `flex:1 1 0; minWidth:0; overflowX:hidden`、カード絵を縮小（108×162）、効果文/値を `overflowWrap:anywhere` で折返し。
編集1箇所、文字列アンカー一致。新 cpS は Babel(JSX) 検証済み。

---

## 編集1：cpS を修正版へ全置換

【検索（厳密一致・オブジェクト全体）】
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
```

---

## 主な変更点
- wrap：`width:min(960px,96vw)`→`width:100%; maxWidth:960; boxSizing:border-box`、padding 圧縮。
- split：`width:100%; minWidth:0` 付与（横あふれ防止）。
- left：`width:40%/maxWidth300/minWidth148`→`flex:0 0 38%; maxWidth:196; minWidth:0; boxSizing:border-box`（狭く）。
- right：`flex:1 1 0; minWidth:0; boxSizing:border-box; overflowX:hidden`（はみ出し抑止）。
- dArt：140×210→108×162（狭い右でも収まる）。
- dName/dv/skName/skEff：`overflowWrap:anywhere`（長い和文の折返し）、dRow に gap、dv は右寄せ。
- li/liThumb 等も box-sizing/縮小調整。

## 確認事項
- 機能（フィルタ/ソート/スキル表示/本体戦闘力/属性アイコン/選択可否/移動確認/この枠を空にする）は不変。スタイルのみ修正。
- 適用後 commit & push → Ctrl+Shift+R。デッキ編成→空き枠→**右の詳細が画面内に収まり**、左一覧が細くなることを確認。
