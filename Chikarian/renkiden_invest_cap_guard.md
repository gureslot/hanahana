# Chikarian バッチ：練気殿の投資上限超過ガード（過剰投資の無駄を防止）
対象: `Chikarian/index.html`（このファイルのみ）。SQL不要。`function RenkidenTab`（建物・練気殿タブ）内の編集です。

## 何を直すか
- 投資が上限ガードなしで、残り枠を超えて投資した分が「投資中のメダル」として滞留＝実質無駄になっていた（武気1＝メダル5・残り枠＝cap−buki、投資中メダル fuel も差引）。
- 投資を「満タンまで投資できる額」でクランプ（超過分は投資しない）。満タン時は投資不可。「全額」ボタンを「上限まで」に変更し、無駄が出ない額をセット。
- 即生産も残り枠（個）でクランプ＋残り枠を表示。満タン時は不可。
- 練成量・残量の最終判定は従来どおりサーバ。クライアントは無駄打ち防止の表示・入力ガードのみ。

各編集は **検索文字列が1回だけ出現** することを確認してから置換。

---

### 編集 練1 invest上限クランプ
**検索:**
```jsx
  const invest = () => { const m = parseInt(investAmt, 10); if (!(m > 0)) { flash('投資額を入力してください'); return; } run(() => ChikarianAPI.investRenkiden(m), 'メダルを投資しました'); setInvestAmt(''); };
```
**置換:**
```jsx
  const invest = () => {
    const m0 = parseInt(investAmt, 10);
    if (!(m0 > 0)) { flash('投資額を入力してください'); return; }
    const maxI = Math.max(0, Math.ceil(Math.max(0, rk.cap - rk.buki) * 5) - rk.fuel);  // 満タンまでに必要なメダル（投資中分を差引）
    if (maxI <= 0) { flash('武気は満タンです（投資中のメダルで充足）。回収してから投資してください'); return; }
    const m = Math.min(m0, maxI);
    run(() => ChikarianAPI.investRenkiden(m), m < m0 ? `満タンまでの ${m.toLocaleString()} メダルのみ投資しました` : 'メダルを投資しました');
    setInvestAmt('');
  };
```

### 編集 練2 instant残枠クランプ
**検索:**
```jsx
  const instant = () => { const n = parseInt(instantN, 10); if (!(n > 0)) { flash('生産量を入力してください'); return; } run(() => ChikarianAPI.instantRenkiden(n), '即時生産しました'); setInstantN(''); };
```
**置換:**
```jsx
  const instant = () => {
    const n0 = parseInt(instantN, 10);
    if (!(n0 > 0)) { flash('生産量を入力してください'); return; }
    const maxN = Math.floor(Math.max(0, rk.cap - rk.buki));  // 残り枠（個）
    if (maxN <= 0) { flash('武気は満タンです'); return; }
    const n = Math.min(n0, maxN);
    run(() => ChikarianAPI.instantRenkiden(n), n < n0 ? `上限までの ${n} 個のみ即生産しました` : '即時生産しました');
    setInstantN('');
  };
```

### 編集 練3 残枠算出
**検索:**
```jsx
  const instNum = parseInt(instantN, 10);
```
**置換:**
```jsx
  const instNum = parseInt(instantN, 10);
  const invNum = parseInt(investAmt, 10);
  const roomBuki = Math.max(0, rk.cap - rk.buki);                   // 残り枠（武気）
  const maxInvest = Math.max(0, Math.ceil(roomBuki * 5) - rk.fuel); // 満タンまで投資できるメダル
  const maxInstant = Math.floor(roomBuki);                         // 即生産の上限（個）
```

### 編集 練4 全額→上限まで
**検索:**
```jsx
          <button className="tat-allbtn" onClick={() => setInvestAmt(String(medal))}>全額</button>
```
**置換:**
```jsx
          <button className="tat-allbtn" onClick={() => setInvestAmt(String(Math.min(medal, maxInvest)))}>上限まで</button>
```

### 編集 練5 投資上限ヒント+不可
**検索:**
```jsx
        <div className="tat-fbtns">
          <button className="tat-fb primary" disabled={busy} onClick={invest}>投資して練る</button>
        </div>
```
**置換:**
```jsx
        {maxInvest > 0
          ? <div className="tat-est"><div className="row2"><span>満タンまで投資できる</span><span className="b">{maxInvest.toLocaleString()} メダル</span></div>{invNum > maxInvest && <div className="note">※超過分（{(invNum - maxInvest).toLocaleString()} メダル）は練成されないため投資されません</div>}</div>
          : <div className="tat-est"><div className="note">※武気は満タン（投資中のメダルで充足）。回収すると再び投資できます。</div></div>}
        <div className="tat-fbtns">
          <button className="tat-fb primary" disabled={busy || maxInvest <= 0} onClick={invest}>投資して練る</button>
        </div>
```

### 編集 練6 即生産残枠表示
**検索:**
```jsx
        {instNum > 0 && <div className="tat-est"><div className="row2"><span>必要メダル 目安</span><span className="b">{(instNum * 15).toLocaleString()}</span></div><div className="note">※上限超過はサーバが拒否。</div></div>}
```
**置換:**
```jsx
        {instNum > 0 && <div className="tat-est"><div className="row2"><span>必要メダル 目安</span><span className="b">{(instNum * 15).toLocaleString()}</span></div><div className="row2"><span>残り枠</span><span className="b">{maxInstant.toLocaleString()} 個</span></div>{instNum > maxInstant && <div className="note">※残り枠（{maxInstant.toLocaleString()} 個）までに調整して生産します。</div>}</div>}
```

### 編集 練7 即生産満タン不可
**検索:**
```jsx
          <button className="tat-fb gold" disabled={busy} onClick={instant}>即生産（×15）</button>
```
**置換:**
```jsx
          <button className="tat-fb gold" disabled={busy || maxInstant <= 0} onClick={instant}>即生産（×15）</button>
```
