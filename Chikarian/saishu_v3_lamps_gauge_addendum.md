# Chikarian｜採取 v3 追補：判定ゲージ＋5判定項目チップ＋診断文の移植

対象: `Chikarian/index.html`（このファイルのみ）。**SQL不要**。
v3本体（点滅ベース・粒子）は実装済み。本追補は**現行 index.html に無い「判定ゲージ(#lockBar)・5判定項目チップ・診断文」をモック `saishu-test.html` から移植して追加**する（v3 §D「復活」の実体。v3 §A①の「現状踏襲」は誤り＝踏襲元が無いため移植が正）。

> 背景：これらはモック専用UI。現行 index.html の採取画面には「光を探しています…／採取中」ラベルと**チカリウムの残量ゲージ（残1,000）**はあるが、**ロック合格率ゲージ(#lockBar)・5チップ・診断文は無い**。ユーザー初回指示「モックにあった判定ゲージと判定項目を省かない」を満たすため追加する。

## 追加するもの（3つ）
1. **判定ゲージ（#lockBar）**＝ロック合格率を表示（チカリウム残量ゲージとは別物）。
2. **5判定項目チップ**＝形／花の赤／色の違い／葉の緑／点滅（各条件の現在OK/NG）。
3. **診断文**＝直近で最も不合格な条件を「○○が うまく認識できていません」。

## 触らない
- `TUNE` 閾値・ロック判定（`LOCK_WIN`/`LOCK_RATE`）・採取の点滅ベース・粒子・サーバ0003。**表示の追加のみ**。
- ラベルは物理表現のみ（Hz/bpm/点滅検出 等の技術表示や「ランプ／チカり」語は出さない＝saishu-detection-history §6）。チップ文言・診断文言はモックのまま（物理表現で適合済み）。

---

## 既存の analyze から取り出す値（既に計算済み）
現行の採取ループは各フレームで `shapeOK / petalRed / colorGap / leafGreen / hzOK`（=`frameOK` の各項）と、ロック窓の合格率 `rate`、`locked` を計算している。**これらを React 状態に載せて描画するだけ**（新たな判定計算は不要）。

20fps（50ms）なので毎フレーム setState で問題ない（重ければ ~10fps に間引き可）。React 状態を追加：
- `lamps`（5条件の真偽：`{shape,red,gap,leaf,hz}`）
- `lockPct`（数値）
- `lockLabel`（'光を探しています…' / 'パターン認識中…' / '採取中'）
- `diagMsg`（診断文・空文字可）

`analyze` 内、`locked` 確定の直後に算出して setState：
```js
// rate, locked, および shapeOK/petalRed/colorGap/leafGreen/hzOK は算出済み
setLamps({ shape:shapeOK, red:petalRed, gap:colorGap, leaf:leafGreen, hz:hzOK });
setLockPct(Math.min(100, (rate / TUNE.LOCK_RATE) * 100));   // モック updateLockUI と同式
setLockLabel(locked ? '採取中' : (rate > 0.15 ? 'パターン認識中…' : '光を探しています…'));

// 診断（直近STAT_WIN=40フレームで最劣条件・モック updateStatus と同ロジック）
const st = stateRef.current;
if (!st.statBufs) st.statBufs = { shape:[], red:[], gap:[], leaf:[], hz:[] };
const COND = [['shape',shapeOK,'形（光の出方）'],['red',petalRed,'赤い光'],['gap',colorGap,'色の違い'],['leaf',leafGreen,'緑の部分'],['hz',hzOK,'点滅の速さ']];
for (const [k,ok] of COND){ const b=st.statBufs[k]; b.push(ok?1:0); if(b.length>40) b.shift(); }
let worst=null, worstRate=1;
for (const [k,,label] of COND){ const b=st.statBufs[k]; if(b.length<40) continue; const r=b.reduce((a,x)=>a+x,0)/b.length; if(r<worstRate){ worstRate=r; worst=label; } }
setDiagMsg(locked ? '' : ((worst && worstRate<0.5) ? worst+'が うまく認識できていません' : ''));
```

## JSX（既存ラベル付近に追加）
現行の「光を探しています…／採取中」ラベル表示を `lockLabel` 状態に置換し、その直下に判定ゲージ・チップ・診断文を入れる（モックの並び：ラベル → 判定ゲージ → チップ → 診断文）。チカリウム残量ゲージは現状のまま残す（別物）。

```jsx
{/* 判定ラベル（既存の locked 三項を lockLabel に） */}
<div style={{ fontSize: 13, letterSpacing: 1, color: locked ? '#3fe08a' : GOLD }}>{lockLabel}</div>

{/* 判定ゲージ（合格率・#lockBar 相当） */}
<div style={{ width: 240, height: 12, background: 'rgba(0,0,0,.6)', border: `1.5px solid ${locked ? '#3fe08a' : 'rgba(232,194,90,.5)'}`, borderRadius: 8, overflow: 'hidden', boxShadow: locked ? '0 0 12px rgba(63,224,138,.5)' : 'none' }}>
  <div style={{ height: '100%', width: `${lockPct}%`, background: locked ? 'linear-gradient(90deg,#1fc46a,#9dffce)' : 'linear-gradient(90deg,#ff9500,#ffe28a)', transition: 'width .15s' }} />
</div>

{/* 5判定項目チップ */}
<div style={{ display: 'flex', gap: 4, justifyContent: 'center', flexWrap: 'wrap', marginTop: 4 }}>
  {[['shape','形'],['red','花の赤'],['gap','色の違い'],['leaf','葉の緑'],['hz','点滅']].map(([k,t]) => (
    <span key={k} style={{ fontSize: 10, padding: '3px 7px', borderRadius: 5,
      background: lamps[k] ? 'rgba(30,110,50,.5)' : 'rgba(120,30,30,.5)',
      color: lamps[k] ? '#9f9' : '#e88',
      border: `1px solid ${lamps[k] ? 'rgba(60,180,90,.5)' : 'rgba(180,60,60,.4)'}` }}>{t}</span>
  ))}
</div>

{/* 診断文 */}
<div style={{ fontSize: 11, color: '#e8b04a', marginTop: 5, minHeight: 14, textAlign: 'center' }}>{diagMsg}</div>
```

初期 state：`lamps={shape:false,red:false,gap:false,leaf:false,hz:false}`、`lockPct=0`、`lockLabel='光を探しています…'`、`diagMsg=''`。

## 受け入れ確認
- 光を合わせると5チップが順に緑に点灯し、判定ゲージ（オレンジ）が合格率で伸び、ロックで緑＋満タン＝「採取中」。
- 合わせきれない時、最も弱い条件名で「○○が うまく認識できていません」。
- チカリウム残量ゲージ（残1,000）は従来どおり別表示で残っている。
- 採取の点滅ベース・粒子・TUNE・サーバは不変（表示追加のみ・SQL変更なし）。
