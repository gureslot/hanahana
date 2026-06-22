# Chikarian UI/バグ修正バッチ（13編集・index.html）
対象ファイル: `Chikarian/index.html`（単一ファイル内の `<script type="text/babel">` ブロック）
各編集は **検索文字列が全体で1回だけ出現**。上から順に文字列アンカー一致で置換してください。SQLは別途（0053）。

## 修正内容サマリ
1. **ボス名バグ（最重要）**: 正規表現 `(a|b|boss)` が面ボス `boss_X_boss` を 'b'（中ボスB）に誤マッチ → 面ボス名が全マップ/報告書で中ボスB名に化けていた。`(boss|a|b)` に修正（編集①②③）。
2. **デッキ編成ⓘ無反応**: CardPopup がデッキ本体ビューに描画されておらず、ⓘ(setDetailCard)が無反応だった。本体ビューに描画を追加（編集④）。
3. **スキル文の改善**: SP/特殊 effect_type（enemy_mult/loss_nullify/force_activate）を自然文化＋未知typeは開発メモ括弧を自動除去（ゴーストガールの「（girl・…旧0.40）」は本番で自動的に消える＝個別指示不要）。発動率を太字＋明色に（編集⑤⑥）。
4. **図鑑を閲覧専用化**: 図鑑のカード詳細から ★強化/スキル/ロック ボタンを撤去（強化は強化合成画面で実施。代表表示で強化させない）（編集⑦）。
5. **交換所NaN修正**: 旧列 base_value_blue/star_coeff/divisor 参照を `base_value × 2^★`（0030 一本化スキーマ）へ修正（編集⑧⑨）。
6. **交換所 編成中除外**: デッキ編成中/ロック/出撃中/探索中カードをグレーアウト＋右上ラベル（ロックは🔒）で非選択化。全選択も有効カードのみ（編集⑩⑪⑫⑬）。

---

## 編集① ①bossSortieName regex

**検索:**
```jsx
/^boss_([1-8])_(a|b|boss)/.exec(bossKey || '')
```

**置換:**
```jsx
/^boss_([1-8])_(boss|a|b)/.exec(bossKey || '')
```

---

## 編集② ②busyRole regex

**検索:**
```jsx
/^boss_([1-8])_(a|b|boss)/.exec(s.boss_key)
```

**置換:**
```jsx
/^boss_([1-8])_(boss|a|b)/.exec(s.boss_key)
```

---

## 編集③ ③parseBossKey regex

**検索:**
```jsx
/^boss_([1-8])_(a|b|boss)(?:_r([0-9]+))?$/
```

**置換:**
```jsx
/^boss_([1-8])_(boss|a|b)(?:_r([0-9]+))?$/
```

---

## 編集④ ④deck main CardPopup

**検索:**
```jsx
      {recallConfirm && (() => {
```

**置換:**
```jsx
      {detailCard && <CardPopup card={detailCard} onClose={() => setDetailCard(null)} />}
      {recallConfirm && (() => {
```

---

## 編集⑤ ⑤formatter SP/util対応

**検索:**
```jsx
    default: return sk.notes ? { pre: '', num: '', post: sk.notes } : null;
```

**置換:**
```jsx
    case 'enemy_mult': return { pre: '敵の実戦闘力を', num: Math.round((1 - val) * 100) + '%', post: '減少' };
    case 'loss_nullify': return { pre: '', num: '', post: '敗北してもデッキの武気を失わない' };
    case 'force_activate': return { pre: '', num: '', post: '戦闘時、確率スキルから1つを必ず発動' };
    default: { const t = sk.notes ? String(sk.notes).replace(/（[^（）]*(?:girl|dragon|houou|chara|旧|改定|仮|spec|TODO)[^（）]*）/g, '').trim() : ''; return t ? { pre: '', num: '', post: t } : null; }
```

---

## 編集⑥ ⑥発動率を強調

**検索:**
```jsx
      {rate != null && rate < 1 ? <span style={{ color: '#a98f66' }}>（発動{Math.round(rate * 100)}%）</span> : null}
```

**置換:**
```jsx
      {rate != null && rate < 1 ? <span style={{ color: '#d8b06a' }}>（発動<b style={{ color: GOLD_HI }}>{Math.round(rate * 100)}%</b>）</span> : null}
```

---

## 編集⑦ ⑦図鑑を閲覧専用化

**検索:**
```jsx
        {/* 操作（本番の全操作を維持＝各 setMode） */}
        <div style={zS.dSec}>操作（カード詳細が共通入口）</div>
        <div style={zS.zActions}>
          <button style={{ ...zS.zaBtn, ...(card.locked ? zS.zaOff : {}) }} disabled={!!card.locked} onClick={() => setMode('kyoka')}>★強化</button>
          <button style={{ ...zS.zaBtn, ...(st.isSp ? zS.zaOff : {}) }} disabled={st.isSp} onClick={() => setMode('skill')}>スキル強化/転移{st.isSp ? '（SP不可）' : ''}</button>
          <button style={{ ...zS.zaBtn, ...zS.zaOff, gridColumn: '1 / -1' }} disabled={!LOCK_RPC_AVAILABLE}
            onClick={() => flash('ロック切替には専用RPCが必要です（cardsの直接更新はRLS/不正対策Cで不可）')}>
            {card.locked ? 'ロック解除' : 'ロックする'}（専用RPC待ち）
          </button>
        </div>
```

**置換:**
```jsx
        {/* 図鑑詳細は閲覧専用（★強化/スキル/ロックは強化合成画面で実施）。 */}
```

---

## 編集⑧ ⑧交換所estOf列名修正

**検索:**
```jsx
  const estOf = (c) => { const r = rateOf(c); return r ? { color: r.crystal_color, count: Math.max(0, Math.round(r.base_value_blue * (1 + (r.star_coeff || 0) * (c.star || 0)) / (r.divisor || 1))) } : null; };
```

**置換:**
```jsx
  const estOf = (c) => { const r = rateOf(c); return r ? { color: r.crystal_color, count: Math.round((r.base_value || 0) * Math.pow(2, c.star || 0)) } : null; };
```

---

## 編集⑨ ⑨ExchangeView列名修正

**検索:**
```jsx
  const est = rate ? { color: rate.crystal_color, count: Math.round(rate.base_value_blue * (1 + (rate.star_coeff || 0) * (base.star || 0)) / (rate.divisor || 1)) } : null;
```

**置換:**
```jsx
  const est = rate ? { color: rate.crystal_color, count: Math.round((rate.base_value || 0) * Math.pow(2, base.star || 0)) } : null;
```

---

## 編集⑩ ⑩交換所decks読込

**検索:**
```jsx
  const [rates, setRates] = useState([]);
```

**置換:**
```jsx
  const [rates, setRates] = useState([]);
  const [decks, setDecks] = useState([]);
  useEffect(() => { (async () => { try { setDecks(await ChikarianAPI.getDecks() || []); } catch (e) {} })(); }, []);
```

---

## 編集⑪ ⑪交換所 編成中除外

**検索:**
```jsx
  // 交換可能カード（ロック中・探索/ボス出撃中は除外）
  const list = (cards || []).filter(c => !c.locked && c.tansaku_deck_no == null && c.boss_deck_no == null);
```

**置換:**
```jsx
  // 全カード表示。交換不可（ロック/編成中/出撃中/探索中）はグレーアウト＋ラベルで非選択化。
  const deckIds = new Set(); (decks || []).forEach(d => [d.slot1_card_id, d.slot2_card_id, d.slot3_card_id].forEach(id => { if (id) deckIds.add(id); }));
  const lockReason = (c) => c.locked ? 'lock' : (deckIds.has(c.id) ? '編成中' : (c.boss_deck_no != null ? '出撃中' : (c.tansaku_deck_no != null ? '探索中' : null)));
  const list = (cards || []);
```

---

## 編集⑫ ⑫交換所全選択を有効カードのみ

**検索:**
```jsx
  const selectAll = () => { const m = {}; list.forEach(c => { m[c.id] = true; }); setSel(m); };
```

**置換:**
```jsx
  const selectAll = () => { const m = {}; list.forEach(c => { if (!lockReason(c)) m[c.id] = true; }); setSel(m); };
```

---

## 編集⑬ ⑬交換所 render（グレーアウト＋ラベル）

**検索:**
```jsx
              const e = estOf(c); const on = !!sel[c.id]; const info = parseCardKey(c.card_key);
              return (
                <button key={c.id} onClick={() => toggle(c.id)} style={{ ...exS.card, ...(on ? exS.cardOn : {}) }}>
                  <div style={exS.cardArt}><DeckSlotArt cardKey={c.card_key} />{on && <div style={exS.check}>✓</div>}<div onClick={(e) => { e.stopPropagation(); setDetailCard(c); }} style={{ position: 'absolute', left: 3, bottom: 3, width: 20, height: 20, borderRadius: '50%', background: 'rgba(10,6,9,.82)', border: '1px solid rgba(232,194,90,.5)', color: '#fff3c8', fontSize: 12, lineHeight: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', zIndex: 3 }}>ⓘ</div></div>
                  <div style={exS.cardName}>{RAR_LABEL[info.rarity]} Lv{c.lv || 1}{(c.star || 0) > 0 ? ' ★' + (c.star || 0) : ''}</div>
                  <div style={exS.cardCx}>{e ? COLOR_JA[e.color] + '+' + e.count : '—'}</div>
                </button>
```

**置換:**
```jsx
              const e = estOf(c); const on = !!sel[c.id]; const info = parseCardKey(c.card_key); const reason = lockReason(c);
              return (
                <button key={c.id} onClick={() => { if (!reason) toggle(c.id); }} disabled={!!reason} style={{ ...exS.card, ...(on ? exS.cardOn : {}), ...(reason ? { opacity: .5, cursor: 'default' } : {}) }}>
                  <div style={exS.cardArt}><DeckSlotArt cardKey={c.card_key} />{reason ? <div style={{ position: 'absolute', top: 4, right: 4, fontSize: 9, fontWeight: 800, color: '#1a1014', background: reason === 'lock' ? 'rgba(210,130,130,.95)' : 'rgba(232,194,90,.95)', borderRadius: 5, padding: '1px 5px', zIndex: 3 }}>{reason === 'lock' ? '🔒' : reason}</div> : (on && <div style={exS.check}>✓</div>)}<div onClick={(e) => { e.stopPropagation(); setDetailCard(c); }} style={{ position: 'absolute', left: 3, bottom: 3, width: 20, height: 20, borderRadius: '50%', background: 'rgba(10,6,9,.82)', border: '1px solid rgba(232,194,90,.5)', color: '#fff3c8', fontSize: 12, lineHeight: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer', zIndex: 3 }}>ⓘ</div></div>
                  <div style={exS.cardName}>{RAR_LABEL[info.rarity]} Lv{c.lv || 1}{(c.star || 0) > 0 ? ' ★' + (c.star || 0) : ''}</div>
                  <div style={exS.cardCx}>{reason ? (reason === 'lock' ? 'ロック中' : reason) : (e ? COLOR_JA[e.color] + '+' + e.count : '—')}</div>
                </button>
```
