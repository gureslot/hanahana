# Chikarian 修正バッチ：採取 連続式 + 画面エラー表示（安全網）
対象: `Chikarian/index.html`（このファイルのみ）。SQL実行は不要。
各編集は **検索文字列が1回だけ出現** することを確認してから置換してください。

---

## 【A】採取（Saishu）を連続式に修正（4編集）
点滅1回ごと+10 → **検出中(locked)は経過時間で充填**（約10秒で1日上限1000）。サーバ(`claim_saishu`)は変更しない。

### 編集 ①FILL_SEC定数
**検索:**
```jsx
const DAILY_MAX = 1000;
```
**置換:**
```jsx
const DAILY_MAX = 1000;
const SAISHU_FILL_SEC = 10;   // 検出中(locked)に連続充填して上限到達までの目安秒数（balance §8・連続式）
```

### 編集 ②onPeak撤去
**検索:**
```jsx
    function onPeak() {
      blinksRef.current += 1;
      setSessionGain(g => g + 10);
    }
```
**置換:**
```jsx
    // 連続式に変更：点滅ごと加算(onPeak)は廃止。検出中の経過時間で充填する（下の analyze 内）。
```

### 編集 ③連続充填ロジック
**検索:**
```jsx
      // ピーク検出（明るさの立ち上がり→下降で1点滅）
      if (isLocked) {
        const cur = P.br;
        if (cur > st.prevBr) st.rising = true;
        else if (st.rising && cur < st.prevBr) { st.rising = false; const now = Date.now(); if (now - st.lastSpawn > 80) { onPeak(); st.lastSpawn = now; } }
        st.prevBr = cur;
      } else { st.rising = false; st.prevBr = P.br; }
```
**置換:**
```jsx
      // 連続式：検出中(locked)は経過時間で充填（約 SAISHU_FILL_SEC 秒で1日上限）。点滅ごと加算はしない。
      const nowT = Date.now();
      if (isLocked) {
        const dt = st.fillTick ? Math.min(nowT - st.fillTick, 250) / 1000 : 0;   // 秒（タブ復帰等の巨大dtは0.25sに制限）
        st.fillTick = nowT;
        st.acc = Math.min((st.acc || 0) + (DAILY_MAX / SAISHU_FILL_SEC) * dt, remaining);   // チカリウム換算で蓄積（残り枠で頭打ち）
        blinksRef.current = st.acc / 10;                                          // claim 用（点滅単位＝チカリウム/10）
        setSessionGain(Math.floor(st.acc));
      } else {
        st.fillTick = nowT;   // 非検出中は時計だけ進め、蓄積しない（一時停止）
      }
```

### 編集 ④claimで丸め
**検索:**
```jsx
    const blinks = blinksRef.current;
```
**置換:**
```jsx
    const blinks = Math.round(blinksRef.current);
```

---

## 【B】画面描画エラーを「真っ暗」ではなく画面表示する安全網（2編集）
どの画面でも描画中に例外が出たら、黒画面ではなく**エラー文＋「ホームに戻る」**を表示する（強化合成の原因特定にも使う）。

### 編集 ⑤ErrorBoundary定義
**検索:**
```jsx
function App() {
```
**置換:**
```jsx
class ErrBoundary extends React.Component {
  constructor(p) { super(p); this.state = { err: null }; }
  static getDerivedStateFromError(e) { return { err: e }; }
  componentDidCatch(e, info) { try { console.error('CK画面描画エラー:', e, info); } catch (_) {} }
  render() {
    if (this.state.err) {
      const m = String((this.state.err && this.state.err.message) || this.state.err);
      return (
        <div style={{ position: 'relative', zIndex: 2, minHeight: '100dvh', padding: '60px 22px', color: '#efe2c8', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', textAlign: 'center', gap: 12 }}>
          <div style={{ fontSize: 15, fontWeight: 800, color: '#ff9a8a' }}>この画面の描画でエラーが発生しました</div>
          <div style={{ fontSize: 11, color: '#cdb488', whiteSpace: 'pre-wrap', wordBreak: 'break-word', maxWidth: 360, lineHeight: 1.6, background: 'rgba(60,20,24,.4)', border: '1px solid rgba(255,120,120,.35)', borderRadius: 10, padding: '10px 12px' }}>{m}</div>
          <button onClick={() => { this.setState({ err: null }); if (this.props.onReset) this.props.onReset(); }} style={{ marginTop: 8, fontFamily: 'inherit', fontSize: 13, fontWeight: 800, color: '#1a0f06', background: 'linear-gradient(180deg,#ffd98a,#e8a23b)', border: 'none', borderRadius: 12, padding: '11px 24px', cursor: 'pointer' }}>‹ ホームに戻る</button>
        </div>
      );
    }
    return this.props.children;
  }
}

function App() {
```

### 編集 ⑥bodyを包む
**検索:**
```jsx
      <audio ref={audioRef} src="sounds/bgm_home.mp3" loop preload="auto" muted={!bgmOn} />
      {body}
```
**置換:**
```jsx
      <audio ref={audioRef} src="sounds/bgm_home.mp3" loop preload="auto" muted={!bgmOn} />
      <ErrBoundary key={screen} onReset={() => setScreen('home')}>{body}</ErrBoundary>
```
