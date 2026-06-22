# Chikarian UI修正バッチ（強化合成「真っ暗」＋ⓘ位置＋スキル効果文言）
`Chikarian/index.html` に対し、以下 **8件** を上から順に文字列アンカー一致で適用してください。各 old_string は全体で1回だけ出現します（事前 grep 済み）。私の手元で全8編集適用後に Babel 構文検証済みです。
> 補足：今回スキル文言は **DB（skill_master）を変更しません**。getSkillMaster が全列（effect_type/target_group/base_value/per_lv_value/activation_rate）を返すため、クライアントで自然文を生成します。

---

## 編集 1　① 強化合成「真っ暗」修正：CardPicker 右パネルに確定高さを与える（S.root が minHeight のため flex 列の rightScroll が高さ0に潰れていた）
**検索（old_string）:**
```jsx
maxHeight: '66vh', border: '1px solid rgba(232,194,90,.2)', borderRadius: 12, background: 'rgba(14,9,12,.55)', display: 'flex', flexDirection: 'column', overflow: 'hidden' }
```
**置換（new_string）:**
```jsx
height: '66vh', border: '1px solid rgba(232,194,90,.2)', borderRadius: 12, background: 'rgba(14,9,12,.55)', display: 'flex', flexDirection: 'column', overflow: 'hidden' }
```

## 編集 2　② デッキ編成 ⓘ ボタンを左上→**左下**へ（左上はレアリティ表示位置のため重なっていた）
**検索（old_string）:**
```jsx
left: 4, top: 4, width: 22, height: 22
```
**置換（new_string）:**
```jsx
left: 4, bottom: 4, width: 22, height: 22
```

## 編集 3　③ 交換所 ⓘ ボタンを左上→**左下**へ（同上。✓は右上なので左下が空き）
**検索（old_string）:**
```jsx
left: 3, top: 3, width: 20, height: 20
```
**置換（new_string）:**
```jsx
left: 3, bottom: 3, width: 20, height: 20
```

## 編集 4　④ スキル効果の自然文ジェネレータを新設（CardDetail 直前に挿入）。skill_master の構造データ（effect_type/target_group/base_value/per_lv）から「○属性の味方の総合戦闘力を24%上昇」を生成し、数値を強調表示。DB変更なし
**検索（old_string）:**
```jsx
function CardDetail({ card, cards, profile, skillMap, refreshAll, back, flash, onSelect }) {
```
**置換（new_string）:**
```jsx
const SK_GROUP_JA = { hana: '花', ha: '葉', shin: '芯', ken: '剣', tate: '盾', tsue: '杖' };
const SK_ATTR_SET = { hana: 1, ha: 1, shin: 1 };
function skillGroupLabel(g) { const ja = SK_GROUP_JA[g] || g || ''; return ja ? (SK_ATTR_SET[g] ? ja + '属性' : ja + '武器') : ''; }
// skill_master の構造データ（effect_type/target_group/base_value/per_lv_value）から自然文＋強調用の数値を生成。
function skillEffectParts(sk, lv) {
  if (!sk) return null;
  const L = Math.max(1, lv || 1);
  const base = Number(sk.base_value) || 0, perLv = Number(sk.per_lv_value) || 0;
  const val = base + perLv * (L - 1);
  const pct = Math.round(val * 1000) / 10;
  const g1 = skillGroupLabel(sk.target_group), g2 = skillGroupLabel(sk.target_group2);
  switch (sk.effect_type) {
    case 'sougou_pct': return { pre: g1 + 'の味方の総合戦闘力を', num: pct + '%', post: '上昇' };
    case 'hontai_pct': return { pre: g1 + 'の味方の本体戦闘力を', num: pct + '%', post: '上昇' };
    case 'soubi_pct': return { pre: g1 + 'の味方の装備項を', num: pct + '%', post: '上昇' };
    case 'kyousou_pct': return { pre: g1 + 'と' + g2 + 'の味方の総合戦闘力を', num: pct + '%', post: '上昇' };
    case 'meshibe_group_pct': return { pre: '芯属性または杖武器の味方の総合戦闘力を', num: pct + '%', post: '上昇' };
    case 'deck_sougou_pct': return { pre: 'デッキ全体の総合戦闘力を', num: pct + '%', post: '上昇' };
    case 'deck_sougou_mult': return { pre: 'デッキ全体の総合戦闘力を', num: '×' + val, post: '' };
    case 'self_burst': return { pre: '自身の本体戦闘力を', num: '×' + val, post: '' };
    case 'advantage_scaling': return { pre: '格上の敵ほど効果増・総合戦闘力を最大', num: pct + '%', post: '上昇' };
    case 'meta_amplify': return { pre: '同時発動した他スキルの効果量を', num: pct + '%', post: '増幅' };
    case 'per_skill_count': return { pre: '同時発動した他スキル1つにつき総合戦闘力を', num: pct + '%', post: '上昇' };
    default: return sk.notes ? { pre: '', num: '', post: sk.notes } : null;
  }
}
function SkillEffect({ sk, lv, style }) {
  const d = skillEffectParts(sk, lv);
  if (!d) return null;
  const rate = sk && Number(sk.activation_rate);
  return (
    <span style={style}>
      {d.pre}{d.num ? <b style={{ color: GOLD_HI, fontWeight: 800 }}>{d.num}</b> : null}{d.post}
      {rate != null && rate < 1 ? <span style={{ color: '#a98f66' }}>（発動{Math.round(rate * 100)}%）</span> : null}
    </span>
  );
}

function CardDetail({ card, cards, profile, skillMap, refreshAll, back, flash, onSelect }) {
```

## 編集 5　⑤ 図鑑カード詳細：スキル効果を notes 直書き→ SkillEffect に置換
**検索（old_string）:**
```jsx
{m && m.notes && <div style={{ fontSize: 11, color: '#cdb488', marginTop: 2 }}>{m.notes}</div>}
```
**置換（new_string）:**
```jsx
{m && <div style={{ fontSize: 11, color: '#cdb488', marginTop: 2 }}><SkillEffect sk={m} lv={row.skill_lv} /></div>}
```

## 編集 6　⑥ カード選択パネル：同上
**検索（old_string）:**
```jsx
? <><div style={cpS.skName}>{m ? m.display_name : row.skill_key}</div>{m && m.notes && <div style={cpS.skEff}>{m.notes}</div>}</>
```
**置換（new_string）:**
```jsx
? <><div style={cpS.skName}>{m ? m.display_name : row.skill_key}</div>{m && <div style={cpS.skEff}><SkillEffect sk={m} lv={row.skill_lv} /></div>}</>
```

## 編集 7　⑦ CardPopup（デッキ/ボス/交換所の詳細）：同上
**検索（old_string）:**
```jsx
{r ? <><div style={popS.skName}>{m ? m.display_name : r.skill_key}</div>{m && m.notes && <div style={popS.skEff}>{m.notes}</div>}</> : <div style={popS.skEmpty}>（空き）</div>}
```
**置換（new_string）:**
```jsx
{r ? <><div style={popS.skName}>{m ? m.display_name : r.skill_key}</div>{m && <div style={popS.skEff}><SkillEffect sk={m} lv={r.skill_lv} /></div>}</> : <div style={popS.skEmpty}>（空き）</div>}
```

## 編集 8　⑧ スキル錬成画面：同上
**検索（old_string）:**
```jsx
{m && m.notes && <div className="sk-sm">{m.notes}</div>}
```
**置換（new_string）:**
```jsx
{m && <div className="sk-sm"><SkillEffect sk={m} lv={row.skill_lv} /></div>}
```

---

## 適用後
- 8件すべてを同一セッションで適用 → commit & push。
- ブラウザで **Ctrl+Shift+R**（強制再読込）。

## 確認ポイント
1. **強化合成**：カードをタップ→右パネルに詳細（カード絵・ステータス・スキル）が表示され、下部に ★強化／スキル強化・転移／ロック の固定フッターが見える（「真っ暗」が解消）。
2. **ⓘ ボタン**：デッキ編成・交換所のカードで、ⓘ が**左下**に移動しレアリティ（左上）と重ならない。
3. **スキル効果**：図鑑詳細・選択パネル・CardPopup・スキル錬成のすべてで、効果が「○属性の味方の総合戦闘力を **24%** 上昇」のような自然文になり、**数値が金色で強調**される（確率発動スキルは「（発動85%）」付き）。
