# Chikarian バッチ：ロック有効化 + デッドコード削除 + ボス三すくみ有利/不利表示
対象: `Chikarian/index.html`（このファイルのみ）。SQL実行は不要（0023は適用済み前提）。
> このバッチは前回の `lock_enable_true.md`（ロックtrue化）を**内包**しています。**`lock_enable_true.md` は適用せず、本バッチだけ**を当ててください。
各編集は **検索文字列が1回だけ出現** することを確認してから置換すること（②は完全一致での削除＝置換先は空）。

---

## 【A】ロック有効化（LOCK_RPC_AVAILABLE = true）
0023(set_card_lock) 適用済みのため、強化合成のロックボタンを有効化する。

### 編集 ①ロック有効化(true)
**検索:**
```jsx
const LOCK_RPC_AVAILABLE = false;   // ロック切替RPC(0023)が本番適用されたら true に。強化合成のactionsがこれを参照しており、未定義だとカード選択時に真っ暗になる
```
**置換:**
```jsx
const LOCK_RPC_AVAILABLE = true;    // 0023(set_card_lock) 適用済み＝有効。強化合成のactions/ロックボタンが参照
```

---

## 【B】未使用のローカル定義を削除（単一の正＝グローバルに統一）
`CardDetail` 内に残っていた同名のローカル定義（図鑑が閲覧専用化された際に未使用化・スタレなコメント付き）を削除。グローバルが true・ローカルが false という矛盾を残すと将来ロックUIを再追加した時に黙って false を拾う事故になるため、消す方が安全。今は誰も参照しておらず挙動は変わらない。

### 編集 ②デッドローカル削除
**検索:**
```jsx

  // ロック切替: 専用RPCが無いため未実装（cards を直接UPDATEしない＝RLS/不正対策C）。
  // ※ chikarian-api.js / 0001-0011 にロックRPCは無い。RPCが用意されたらここを有効化する。
  const LOCK_RPC_AVAILABLE = false;

```
**置換:** （空＝この検索ブロックを削除）

---

## 【C】ボス出撃シートにカード別の有利/不利を表示
出撃シートの各カード右上に、選択中のボス（boss_master.attrs/weapons）に対する三すくみ判定を表示。**有利（緑）/不利（赤）／中立=非表示**。係数はサーバ `public.sukumi_factor`(0028) と同値（花>芯>葉>花・盾>剣>杖>盾、有利1.2・不利0.8、カード補正＝属性係数×武器係数、SPは常に中立、めしべは芯/杖）。表示のみで勝敗・補正の最終判定は従来どおりサーバ。

### 編集 ③三すくみヘルパ追加
**検索:**
```jsx
  return (RAR_LABEL[i.rarity] || '') + i.name + i.attr + i.weap;
}
```
**置換:**
```jsx
  return (RAR_LABEL[i.rarity] || '') + i.name + i.attr + i.weap;
}

// 三すくみ係数（サーバ public.sukumi_factor=0028 と同値）：花>芯>葉>花／盾>剣>杖>盾。c==e=1.0・有利1.2・不利0.8。
const SUKUMI_BEATS = { hana: 'shin', shin: 'ha', ha: 'hana', tate: 'ken', ken: 'tsue', tsue: 'tate' };
function sukumiFactor(c, e) {
  if (!c || !e || c === e) return 1.0;
  return SUKUMI_BEATS[c] === e ? 1.2 : 0.8;
}
// カードの三すくみ補正＝属性係数×武器係数（敵の各属性/武器を全乗算・§2-B方式）。SPは常に中立・めしべは芯/杖（サーバ do_boss_battle と同じ）。
function cardSukumiVsBoss(card, boss) {
  if (!card || !boss) return 1.0;
  const key = card.card_key || '';
  if (/_sp$/.test(key)) return 1.0;
  const p = key.split('_');
  const mAttr = p[1] === 'meshibe' ? 'shin' : p[2];
  const mWeap = p[1] === 'meshibe' ? 'tsue' : p[3];
  let f = 1.0;
  (boss.attrs || []).forEach(ea => { f *= sukumiFactor(mAttr, ea); });
  (boss.weapons || []).forEach(ew => { f *= sukumiFactor(mWeap, ew); });
  return f;
}
```

### 編集 ④出撃シート有利/不利バッジ
**検索:**
```jsx
                              <div style={spSet[c.id] ? { opacity: .35, filter: 'grayscale(1)' } : undefined}><CardThumb card={c} small /></div>
```
**置換:**
```jsx
                              <div style={spSet[c.id] ? { opacity: .35, filter: 'grayscale(1)' } : undefined}><CardThumb card={c} small /></div>
                              {(() => { const f = cardSukumiVsBoss(c, bm); if (Math.abs(f - 1) < 0.001) return null; const adv = f > 1; return <div style={{ position: 'absolute', top: 3, right: 3, zIndex: 3, fontSize: 9, fontWeight: 800, padding: '1px 5px', borderRadius: 6, color: '#fff', background: adv ? 'rgba(38,132,58,.94)' : 'rgba(168,40,52,.94)', border: '1px solid ' + (adv ? 'rgba(150,230,160,.7)' : 'rgba(255,150,150,.7)'), boxShadow: '0 1px 3px rgba(0,0,0,.6)' }}>{adv ? '有利' : '不利'}</div>; })()}
```
