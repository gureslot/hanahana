# Chikarian 探索マップ 24段ラダー化（index.html）

対象: `Chikarian/index.html` のみ。SQL は別途 0057/0058 を Supabase で実行済み前提。

## 概要
探索を画像マップ＋3ノード（area=1固定・旧レート）から、**8面×3深度＝24段ラダー**へ。各段は `step=(面−1)×3+深度`、解放は `gate=cleared_stage×3+boss_round_role ≥ step−1`（面1浅は常時開放）、レートは現在の周回基準で表示（本体は 0057 のサーバ算出が正）。放置（HouchiScreen）は従来どおり面1浅。
編集5件。各検索が1回だけ出現することを確認してから置換。編集3は TansakuScreen 関数の全置換です。


### 編集1：ladderRate 追加＋ tansakuEstimate を周回対応へ
**検索:**
```jsx
function tansakuEstimate(row, now) {
  if (!row) return null;
  const di = depthInfo(row.depth); if (!di || !row.last_collect_at) return null;
  const min = Math.max(0, (now - new Date(row.last_collect_at).getTime()) / 60000);
  return { di, min, medal: Math.floor(min * di.medal), exp: +(min * di.exp).toFixed(1) };
}
```
**置換:**
```jsx
function ladderRate(step, round) {   // 0057 のレート式の表示用ミラー（本体は collect_tansaku が算出＝サーバが正）
  const r = Math.max(1, round || 1);
  const f = (R1, S) => R1 + S * ((2 - Math.pow(2, 2 - r)) + (step - 1) / (23 * Math.pow(2, r - 1)));
  return { medal: f(0.33, 2.97), exp: f(0.20, 1.80) };
}
function tansakuEstimate(row, now, round) {
  if (!row) return null;
  const di = depthInfo(row.depth); if (!di || !row.last_collect_at) return null;
  const step = (((row.area || 1) - 1) * 3) + di.n;
  const rate = ladderRate(step, round);
  const min = Math.max(0, (now - new Date(row.last_collect_at).getTime()) / 60000);
  return { di, min, step, medal: Math.floor(min * rate.medal), exp: +(min * rate.exp).toFixed(1) };
}
```

### 編集2：TAN_CSS にラダー用スタイルを追記（既存の閉じ ``;`` の直前へ）
**検索:**
```jsx
.tan-toast .ti b{color:#ffe39a; font-weight:800;}
`;
```
**置換:**
```jsx
.tan-toast .ti b{color:#ffe39a; font-weight:800;}
.tan-col2{position:relative; width:100%; max-width:480px; margin:0 auto; min-height:100dvh; background:#070409; color:#fff3c8; display:flex; flex-direction:column;}
.tan-hd{flex:none; display:flex; align-items:center; gap:10px; padding:14px 14px 10px;}
.tan-hd .t{flex:1; text-align:center; font-size:18px; font-weight:800; letter-spacing:2px; text-shadow:0 2px 6px #000;}
.tan-list{flex:1; overflow-y:auto; padding:2px 12px 84px;}
.tan-faceGroup{margin-bottom:12px;}
.tan-faceHd{font-size:12px; color:#cdb488; letter-spacing:2px; border-left:3px solid #e8c25a; padding-left:8px; margin:8px 0 6px;}
.tan-stepRow{display:flex; justify-content:space-between; align-items:center; gap:8px; padding:11px 12px; margin-bottom:6px; border-radius:12px; background:rgba(255,235,180,.05); border:1.5px solid rgba(232,194,90,.4); cursor:pointer;}
.tan-stepRow.locked{background:rgba(40,34,30,.5); border-color:rgba(120,110,95,.3); cursor:default;}
.tan-stepRow.busy{background:linear-gradient(180deg,rgba(120,200,255,.14),rgba(77,166,232,.07)); border-color:rgba(150,210,255,.55);}
.tan-stepName{font-size:14px; font-weight:800; color:#fff3c8;}
.tan-stepRow.locked .tan-stepName{color:#9a8c70;}
.tan-stepRate{font-size:11px; color:#e7d3a6; text-align:right; white-space:nowrap;}
.tan-stepLock{font-size:11px; color:#9a8c70; white-space:nowrap;}
`;
```

### 編集3：TansakuScreen 関数を全置換
`function TansakuScreen({ profile, refreshAll, back, flash }) {` から、直後の `/* 放置報酬画面 専用スタイル` コメント直前の閉じ `}` までを、下記で置換。
**検索（関数全体）:**
```jsx
function TansakuScreen({ profile, refreshAll, back, flash }) {
  const maxDecks = Math.min(2 + Math.floor(((profile && profile.cleared_stage) || 0) / 2), 6);
  const [states, setStates] = useState(null);
  const [decks, setDecks] = useState([]);
  const [deckNo, setDeckNo] = useState(1);
  const [openNode, setOpenNode] = useState(null);   // 開いているノード(depthキー) or null
  const [busy, setBusy] = useState(false);
  const [now, setNow] = useState(Date.now());
  const [toast, setToast] = useState(null);         // 回収結果トースト {medal, exp}

  async function load() { try { setStates(await ChikarianAPI.getTansaku() || []); } catch (e) { flash(errMsg(e)); setStates([]); } }
  useEffect(() => { load(); const t = setInterval(() => setNow(Date.now()), 1000); return () => clearInterval(t); }, []);

  async function run(fn, okMsg) {
    if (busy) return; setBusy(true);
    try { const r = await fn(); if (okMsg) flash(okMsg); await load(); await refreshAll(); return r; }
    catch (e) { flash(errMsg(e)); }
    finally { setBusy(false); }
  }
  // 出発：選択中デッキ＋このノードの深さで開始（深さ変更時の「既存分は自動回収」は startTansaku 仕様のまま）。area=1固定。
  useEffect(() => { (async () => { try { setDecks(await ChikarianAPI.getDecks() || []); } catch (e) {} })(); }, []);   // デッキ編成（空デッキ判定用）
  const doStart = () => { const depth = openNode; setOpenNode(null); run(() => ChikarianAPI.startTansaku(deckNo, 1, depth), '探索を開始しました'); };
  // 回収：選択中デッキの探索を回収。返り値の実数のみトースト表示（捏造しない）。
  const doCollect = async () => {
    const r = await run(() => ChikarianAPI.collectTansaku(deckNo));
    setOpenNode(null);
    if (r) { setToast({ medal: Number(r.medal_gain || 0), exp: r.exp_gain_per_card }); setTimeout(() => setToast(null), 1800); }
  };

  if (!states) return <Booting />;
  const cur = states.find(s => s.deck_no === deckNo) || null;            // 選択中デッキの探索状態（1デッキ＝1探索）
  const selDeckRow = (decks || []).find(d => d.deck_no === deckNo);
  const selDeckCards = selDeckRow ? [selDeckRow.slot1_card_id, selDeckRow.slot2_card_id, selDeckRow.slot3_card_id].filter(Boolean).length : 0;   // 選択中デッキの編成枚数（空デッキ判定）
  const curDi = cur ? depthInfo(cur.depth) : null;
  const curKey = curDi ? curDi.key : null;                              // 選択中デッキが探索中の深さ＝busyノード
  const est = tansakuEstimate(cur, now);
  const byDeck = {}; states.forEach(s => { byDeck[s.deck_no] = s; });
  const isBusyNode = openNode && curKey === openNode;                    // 開いたノードが選択中デッキの探索先か
  const od = openNode ? depthInfo(openNode) : null;

  return (
    <div style={tanRoot}>
      <style>{TAN_CSS}</style>
      <div className="tan-mapWrap">
        <div className="tan-mapDim" />
        {DEPTHS.map(d => {
          const pos = TAN_NODES[d.key]; if (!pos) return null;
          const owner = (states || []).find(s => { const di = depthInfo(s.depth); return di && di.key === d.key; });   // この深さを探索中のデッキ（全デッキ対象）
          const nodeBusy = !!owner;
          return (
            <div key={d.key} className={'tan-node' + (nodeBusy ? ' busy' : '')} style={{ left: pos.left, top: pos.top }} onClick={() => { if (owner) setDeckNo(owner.deck_no); setOpenNode(d.key); }}>
              <div className="tan-dot" /><div className="tan-lbl">{pos.name}</div>
            </div>
          );
        })}
      </div>

      <div className="tan-topbar">
        <div className="tan-area">{WORLD_NAMES[1]}</div>
        <div className="tan-res">メダル <b>{((profile && profile.medal) || 0).toLocaleString()}</b></div>
      </div>

      <div className={'tan-scrim' + (openNode ? ' show' : '')} onClick={() => setOpenNode(null)} />

      <div className={'tan-sheet' + (openNode ? ' show' : '')}>
        {openNode && isBusyNode && (
          /* 探索中ノード：経過/見込み＋回収 */
          <>
            <span className="tan-close" onClick={() => setOpenNode(null)}>×</span>
            <h3>{TAN_NODES[openNode].name}（探索中）</h3>
            <div className="tan-reward">
              <div className="tan-col"><div className="tan-amt">{est ? est.medal.toLocaleString() : '0'}</div><div className="tan-cap">メダル（目安）</div></div>
              <div className="tan-col"><div className="tan-amt">{est ? est.exp : '0'}</div><div className="tan-cap">各カードEXP（目安）</div></div>
            </div>
            <div className="tan-note">経過 約{est ? Math.floor(est.min) : 0}分 ／ デッキ{deckNo}。増減・時刻計算・Lv反映はサーバ判定（balance §7）。</div>
            <button className="tan-recall" onClick={doCollect} disabled={busy}>引っ込めて回収する</button>
          </>
        )}
        {openNode && !isBusyNode && od && (
          /* 未探索ノード：レート＋デッキ選択＋出発 */
          <>
            <span className="tan-close" onClick={() => setOpenNode(null)}>×</span>
            <h3>{TAN_NODES[openNode].name}</h3>
            {/* 要求戦力・ドロップchip は本番にデータが無いため省略（捏造しない） // TODO 深さ別の戦力ゲート/ドロップが確定したら追加 */}
            <div className="tan-stat"><span className="k">属性要求</span><span className="v attr-none">なし</span></div>
            <div className="tan-secTitle">時間で蓄積（balance §7・上限なし・張り付き不要）</div>
            <div className="tan-stat"><span className="k">メダル</span><span className="v">{od.medal} /分</span></div>
            <div className="tan-stat"><span className="k">各カードEXP</span><span className="v">{od.exp} /分</span></div>
            <div className="tan-deckTitle">派遣するデッキ</div>
            <div className="tan-decks">
              {Array.from({ length: maxDecks }, (_, i) => i + 1).map(n => {
                const st = byDeck[n]; const di = st && depthInfo(st.depth);
                const dr = (decks || []).find(x => x.deck_no === n); const cc = dr ? [dr.slot1_card_id, dr.slot2_card_id, dr.slot3_card_id].filter(Boolean).length : 0;
                return (
                  <div key={n} className={'tan-deck' + (n === deckNo ? ' sel' : '')} onClick={() => setDeckNo(n)}>
                    <div className="tan-dn">デッキ{n}</div>
                    <div className="tan-dp">{di ? di.label + '探索中' : (cc === 0 ? 'カードなし' : '待機')}</div>
                  </div>
                );
              })}
            </div>
            <button className="tan-go" onClick={doStart} disabled={busy || selDeckCards === 0}>{selDeckCards === 0 ? 'デッキにカードがありません' : (cur ? '出発（既存分は自動回収）' : '出発')}</button>
            <div className="tan-note">レートは balance §7 の確定値。増減・時刻計算・Lv反映はサーバ。area は当面1固定（面別解放は未確定）。</div>
          </>
        )}
      </div>

      {toast && (
        <div className="tan-toast">
          <div className="tt">回収しました</div>
          <div className="ti">メダル <b>+{toast.medal.toLocaleString()}</b></div>
          {toast.exp != null && <div className="ti">各カードEXP <b>+{toast.exp}</b></div>}
        </div>
      )}

      <button className="tan-back" onClick={back}>ホームへ戻る</button>
    </div>
  );
}
```
**置換（関数全体）:**
```jsx
function TansakuScreen({ profile, refreshAll, back, flash }) {
  const maxDecks = Math.min(2 + Math.floor(((profile && profile.cleared_stage) || 0) / 2), 6);
  const round = Math.max(1, (profile && profile.boss_round) || 1);
  const gate = (((profile && profile.cleared_stage) || 0) * 3) + ((profile && profile.boss_round_role) || 0);
  const [states, setStates] = useState(null);
  const [decks, setDecks] = useState([]);
  const [deckNo, setDeckNo] = useState(1);
  const [openStep, setOpenStep] = useState(null);
  const [busy, setBusy] = useState(false);
  const [now, setNow] = useState(Date.now());
  const [toast, setToast] = useState(null);

  async function load() { try { setStates(await ChikarianAPI.getTansaku() || []); } catch (e) { flash(errMsg(e)); setStates([]); } }
  useEffect(() => { load(); const t = setInterval(() => setNow(Date.now()), 1000); return () => clearInterval(t); }, []);
  useEffect(() => { (async () => { try { setDecks(await ChikarianAPI.getDecks() || []); } catch (e) {} })(); }, []);

  async function run(fn, okMsg) {
    if (busy) return; setBusy(true);
    try { const r = await fn(); if (okMsg) flash(okMsg); await load(); await refreshAll(); return r; }
    catch (e) { flash(errMsg(e)); }
    finally { setBusy(false); }
  }
  const DEPTH_KEY = { 1: 'shallow', 2: 'mid', 3: 'deep' };
  const doStart = () => { if (!openStep) return; const a = openStep.area, d = openStep.depth; setOpenStep(null); run(() => ChikarianAPI.startTansaku(deckNo, a, DEPTH_KEY[d]), '探索を開始しました'); };
  const doCollect = async (dno) => {
    const r = await run(() => ChikarianAPI.collectTansaku(dno));
    setOpenStep(null);
    if (r) { setToast({ medal: Number(r.medal_gain || 0), exp: r.exp_gain_per_card }); setTimeout(() => setToast(null), 1800); }
  };

  if (!states) return <Booting />;
  const stepOwner = {}; (states || []).forEach(s => { const di = depthInfo(s.depth); if (di) stepOwner[(((s.area || 1) - 1) * 3) + di.n] = s; });
  const byDeck = {}; states.forEach(s => { byDeck[s.deck_no] = s; });

  return (
    <div className="tan-col2">
      <style>{TAN_CSS}</style>
      <div className="tan-hd">
        <div className="t">探索</div>
        <div className="tan-res">メダル <b>{((profile && profile.medal) || 0).toLocaleString()}</b></div>
      </div>
      <div className="tan-list">
        {[1, 2, 3, 4, 5, 6, 7, 8].map(area => (
          <div key={area} className="tan-faceGroup">
            <div className="tan-faceHd">面{area} ・ {WORLD_NAMES[area]}</div>
            {[1, 2, 3].map(depth => {
              const step = (area - 1) * 3 + depth;
              const unlocked = gate >= step - 1;
              const owner = stepOwner[step];
              const di = depthInfo(depth);
              const rate = ladderRate(step, round);
              return (
                <div key={depth}
                  className={'tan-stepRow' + (unlocked ? '' : ' locked') + (owner ? ' busy' : '')}
                  onClick={unlocked ? () => { if (owner) setDeckNo(owner.deck_no); setOpenStep({ area, depth, step, name: '面' + area + ' ' + di.label }); } : undefined}>
                  <div className="tan-stepName">{di.label}{owner ? '（デッキ' + owner.deck_no + '探索中）' : ''}</div>
                  {unlocked
                    ? <div className="tan-stepRate">メダル {rate.medal.toFixed(2)} ・ EXP {rate.exp.toFixed(2)} /分</div>
                    : <div className="tan-stepLock">🔒 ボス進行で解放</div>}
                </div>
              );
            })}
          </div>
        ))}
      </div>

      <div className={'tan-scrim' + (openStep ? ' show' : '')} onClick={() => setOpenStep(null)} />
      <div className={'tan-sheet' + (openStep ? ' show' : '')}>
        {openStep && (() => {
          const owner = stepOwner[openStep.step];
          const rate = ladderRate(openStep.step, round);
          if (owner) {
            const oe = tansakuEstimate(owner, now, round);
            return (
              <>
                <span className="tan-close" onClick={() => setOpenStep(null)}>×</span>
                <h3>{openStep.name}（探索中・デッキ{owner.deck_no}）</h3>
                <div className="tan-reward">
                  <div className="tan-col"><div className="tan-amt">{oe ? oe.medal.toLocaleString() : '0'}</div><div className="tan-cap">メダル（目安）</div></div>
                  <div className="tan-col"><div className="tan-amt">{oe ? oe.exp : '0'}</div><div className="tan-cap">各カードEXP（目安）</div></div>
                </div>
                <div className="tan-note">経過 約{oe ? Math.floor(oe.min) : 0}分 ／ デッキ{owner.deck_no}。増減・時刻計算・Lv反映はサーバ判定。</div>
                <button className="tan-recall" onClick={() => doCollect(owner.deck_no)} disabled={busy}>引っ込めて回収する</button>
              </>
            );
          }
          const dr = (decks || []).find(x => x.deck_no === deckNo);
          const cc = dr ? [dr.slot1_card_id, dr.slot2_card_id, dr.slot3_card_id].filter(Boolean).length : 0;
          const busyDeck = byDeck[deckNo];
          return (
            <>
              <span className="tan-close" onClick={() => setOpenStep(null)}>×</span>
              <h3>{openStep.name}</h3>
              <div className="tan-stat"><span className="k">属性要求</span><span className="v attr-none">なし</span></div>
              <div className="tan-secTitle">時間で蓄積（上限なし・張り付き不要）</div>
              <div className="tan-stat"><span className="k">メダル</span><span className="v">{rate.medal.toFixed(2)} /分</span></div>
              <div className="tan-stat"><span className="k">各カードEXP</span><span className="v">{rate.exp.toFixed(2)} /分</span></div>
              <div className="tan-deckTitle">派遣するデッキ</div>
              <div className="tan-decks">
                {Array.from({ length: maxDecks }, (_, i) => i + 1).map(n => {
                  const st = byDeck[n]; const di = st && depthInfo(st.depth);
                  const drn = (decks || []).find(x => x.deck_no === n); const ccn = drn ? [drn.slot1_card_id, drn.slot2_card_id, drn.slot3_card_id].filter(Boolean).length : 0;
                  return (
                    <div key={n} className={'tan-deck' + (n === deckNo ? ' sel' : '')} onClick={() => setDeckNo(n)}>
                      <div className="tan-dn">デッキ{n}</div>
                      <div className="tan-dp">{di ? '面' + (st.area || 1) + di.label + '中' : (ccn === 0 ? 'カードなし' : '待機')}</div>
                    </div>
                  );
                })}
              </div>
              <button className="tan-go" onClick={doStart} disabled={busy || cc === 0}>{cc === 0 ? 'デッキにカードがありません' : (busyDeck ? '出発（既存分は自動回収）' : '出発')}</button>
              <div className="tan-note">レートは現在の周回（{round}周目）基準の目安。増減・時刻計算・Lv反映はサーバ。</div>
            </>
          );
        })()}
      </div>

      {toast && (
        <div className="tan-toast">
          <div className="tt">回収しました</div>
          <div className="ti">メダル <b>+{toast.medal.toLocaleString()}</b></div>
          {toast.exp != null && <div className="ti">各カードEXP <b>+{toast.exp}</b></div>}
        </div>
      )}

      <button className="tan-back" onClick={back}>ホームへ戻る</button>
    </div>
  );
}
```

### 編集4：HouchiScreen に round を追加
**検索:**
```jsx
function HouchiScreen({ profile, refreshAll, back, flash }) {
  const maxDecks = Math.min(2 + Math.floor(((profile && profile.cleared_stage) || 0) / 2), 6);
```
**置換:**
```jsx
function HouchiScreen({ profile, refreshAll, back, flash }) {
  const maxDecks = Math.min(2 + Math.floor(((profile && profile.cleared_stage) || 0) / 2), 6);
  const round = Math.max(1, (profile && profile.boss_round) || 1);
```

### 編集5：HouchiScreen の tansakuEstimate 呼び出しに round を渡す
**検索:**
```jsx
const row = byDeck[n]; const est = tansakuEstimate(row, now); const di = row && depthInfo(row.depth);
```
**置換:**
```jsx
const row = byDeck[n]; const est = tansakuEstimate(row, now, round); const di = row && depthInfo(row.depth);
```

## 備考
- 画像マップCSS（.tan-mapWrap 等）は未使用になりますが定義は残置で無害。
- 戦力ゲート（本体戦闘力合計≥しきい値）は値が Phase 4 確定待ちのため未表示。確定後に各段へ可否表示を追加予定。