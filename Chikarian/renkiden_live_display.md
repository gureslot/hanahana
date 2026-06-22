# Chikarian バッチ：練気殿を整数表示＋武気/投資中メダルをライブ表示＋無意味な「更新」ボタン撤去
対象: `Chikarian/index.html`（このファイルのみ）。SQL不要。`function RenkidenTab` 内の編集です。

## 何を直すか
- 「投資中のメダル」等の小数点表示を整数（floor）に。
- 武気・投資中メダルを毎秒ライブ補間で増減表示（自動生産が見える）。サーバが正で、操作・再取得（画面を開く/操作後）に再同期。投資/即生産の残枠ガードもライブ値に統一。
- 「更新」ボタンを撤去（collectRenkidenは画面を開いた時と各操作後に必ず呼ばれ最新化されるため、手動更新は無意味）。これに伴い未使用となる collect 関数も削除。
- 練成量・残量の最終判定は従来どおりサーバ。クライアントは表示と無駄打ち防止のみ。

各編集は **検索文字列が1回だけ出現** することを確認してから置換。

---

### 編集 練A now/rkAtRef/liveSnap
**検索:**
```jsx
  const [busy, setBusy] = useState(false);
  const medal = profile ? (profile.medal || 0) : 0;
```
**置換:**
```jsx
  const [busy, setBusy] = useState(false);
  const [now, setNow] = useState(Date.now());
  const rkAtRef = useRef(Date.now());
  const medal = profile ? (profile.medal || 0) : 0;
  // 自動生産のライブ補間（表示/ガード用・サーバが正、操作と再取得で再同期）。武気1＝メダル5。
  const liveSnap = (t) => {
    if (!rk) return { b: 0, f: 0 };
    const el = Math.max(0, (t - rkAtRef.current) / 1000);
    let b = rk.buki, f = rk.fuel;
    if (rk.fuel > 0 && rk.buki < rk.cap) { const p = Math.min(rk.rate * el, rk.cap - rk.buki, rk.fuel / 5); b += p; f -= p * 5; }
    return { b, f };
  };
```

### 編集 練B 再同期+毎秒ティック
**検索:**
```jsx
  useEffect(() => { load(); }, []);
```
**置換:**
```jsx
  useEffect(() => { load(); }, []);
  useEffect(() => { rkAtRef.current = Date.now(); }, [rk]);
  useEffect(() => { const t = setInterval(() => setNow(Date.now()), 1000); return () => clearInterval(t); }, []);
```

### 編集 練C invest上限ライブ
**検索:**
```jsx
    const maxI = Math.max(0, Math.ceil(Math.max(0, rk.cap - rk.buki) * 5) - rk.fuel);  // 満タンまでに必要なメダル（投資中分を差引）
```
**置換:**
```jsx
    const { b: lb, f: lf } = liveSnap(Date.now());
    const maxI = Math.max(0, Math.ceil(Math.max(0, rk.cap - lb) * 5) - lf);  // 満タンまでに必要なメダル（投資中分を差引・ライブ）
```

### 編集 練D instant上限ライブ
**検索:**
```jsx
    const maxN = Math.floor(Math.max(0, rk.cap - rk.buki));  // 残り枠（個）
```
**置換:**
```jsx
    const { b: lb } = liveSnap(Date.now());
    const maxN = Math.floor(Math.max(0, rk.cap - lb));  // 残り枠（個・ライブ）
```

### 編集 練E collect関数撤去
**検索:**
```jsx
  const collect = () => run(() => ChikarianAPI.collectRenkiden(), '最新の状態に更新しました');
  const upgrade = () => run(() => ChikarianAPI.upgradeRenkiden(), '練気殿をLvアップ');
```
**置換:**
```jsx
  const upgrade = () => run(() => ChikarianAPI.upgradeRenkiden(), '練気殿をLvアップ');
```

### 編集 練F 描画算出ライブ
**検索:**
```jsx
  if (!rk) return <Booting />;
  const upFee = 8000 * rk.lv;   // balance §11
  const pct = rk.cap > 0 ? Math.min(100, rk.buki / rk.cap * 100) : 0;
  const running = rk.fuel > 0 && rk.buki < rk.cap;
  const instNum = parseInt(instantN, 10);
  const invNum = parseInt(investAmt, 10);
  const roomBuki = Math.max(0, rk.cap - rk.buki);                   // 残り枠（武気）
  const maxInvest = Math.max(0, Math.ceil(roomBuki * 5) - rk.fuel); // 満タンまで投資できるメダル
  const maxInstant = Math.floor(roomBuki);                         // 即生産の上限（個）
```
**置換:**
```jsx
  if (!rk) return <Booting />;
  const upFee = 8000 * rk.lv;   // balance §11
  const { b: liveBuki, f: liveFuel } = liveSnap(now);
  const pct = rk.cap > 0 ? Math.min(100, liveBuki / rk.cap * 100) : 0;
  const running = liveFuel > 0 && liveBuki < rk.cap;
  const instNum = parseInt(instantN, 10);
  const invNum = parseInt(investAmt, 10);
  const roomBuki = Math.max(0, rk.cap - liveBuki);                  // 残り枠（武気）
  const maxInvest = Math.max(0, Math.ceil(roomBuki * 5) - liveFuel); // 満タンまで投資できるメダル
  const maxInstant = Math.floor(roomBuki);                         // 即生産の上限（個）
```

### 編集 練G 武気表示ライブ整数
**検索:**
```jsx
        <div className="tat-st"><span className="k">武気</span><b>{Math.floor(rk.buki).toLocaleString()} / {rk.cap.toLocaleString()}</b></div>
```
**置換:**
```jsx
        <div className="tat-st"><span className="k">武気</span><b>{Math.floor(liveBuki).toLocaleString()} / {rk.cap.toLocaleString()}</b></div>
```

### 編集 練H 投資中メダル整数
**検索:**
```jsx
        <div className="tat-st"><span className="k">投資中のメダル</span><b>{rk.fuel.toLocaleString()}{rk.fuel > 0 ? '（尽きるまで毎秒練成）' : ''}</b></div>
```
**置換:**
```jsx
        <div className="tat-st"><span className="k">投資中のメダル</span><b>{Math.floor(liveFuel).toLocaleString()}{liveFuel > 0 ? '（尽きるまで毎秒練成）' : ''}</b></div>
```

### 編集 練I 更新ボタン撤去
**検索:**
```jsx
          <button className="tat-fb gold" disabled={busy || maxInstant <= 0} onClick={instant}>即生産（×15）</button>
          <button className="tat-fb" disabled={busy} onClick={collect}>更新</button>
```
**置換:**
```jsx
          <button className="tat-fb gold" disabled={busy || maxInstant <= 0} onClick={instant}>即生産（×15）</button>
```
