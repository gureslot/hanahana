# Chikarian｜採取 速度の作り直し v3（判定=モック率ベース／採取9秒・点滅ベース＋粒子移植）

対象: `Chikarian/index.html`（このファイルのみ）。**SQL実行は不要**。
サーバ 0003 `claim_saishu` は `claimSaishu(n)=n×10` を `DAILY_MAX=1000` でクランプするだけ＝採取速度はクライアントが持つ（canon-06 §1）。

> ※**v1/v2 を破棄してこれ(v3)だけを使う**。v2からの変更点は2つだけ：
> 1. 判定フェーズを **モックの率ベースロック（20フレーム窓）そのまま**に戻す（v2の「2秒アキュムレータ」は撤去）。
> 2. 採取 **8秒 → 9秒**、1ピーク加算 **20.83 → `DAILY_MAX/54 ≈ 18.52`**。
> 粒子移植（§C）はv2と同じ＝必須。

---

## ⚠ 最初に必ず

- **作業前に実ファイルの `Saishu`（採取・カメラ）コンポーネントを読む。** スナップショットは実デプロイ版より古い可能性が高い。粒子コードの有無も実ファイルで確認（無ければ §C で移植）。
- **判定閾値 `TUNE` は変更しない**（`LOCK_WIN=20`/`LOCK_RATE=0.60` 含め据え置き。検出精度の再調整は `hibiscus-2box2.html` の測定→逆算＝別件）。
- **基準は `saishu-test.html`**（率ベースロック＋判定ゲージ＋5判定項目ランプ＋粒子演出）。

## ゴール（ユーザー指定）

- 合計 **約10秒**（判定 最速約1秒＝モックの率ベース ＋ 採取 **9秒**）。
- **6点滅/秒として計算**。採取9秒で日次上限 **1000** を満たす（1かざしで完了）。
- **判定ゲージ・判定項目（5ランプ）・粒子演出は残す/復活させる**（省かない）。

## 確定値（変えない）

- サーバ `DAILY_MAX=1000` ／ claim単位 `PER_BLINK=10`（0003）。退出時 `claimSaishu(Math.round(acc/10))`（1000なら100点滅）。

---

## A. 判定 → 採取（速度・タイミング）

**v2のような phase 列挙や detectAcc は不要。モックの `locked` をそのまま使う。**

### ① 判定（モックの率ベース・そのまま）
- モックの判定をそのまま使う：直近 `LOCK_WIN=20` フレームの合格率（5条件AND `frameOK` の率）が `LOCK_RATE=0.60` 以上で `locked=true`（`locked = okBuf.length>=20 && rate>=0.60`）。
- 判定ゲージ（`#lockBar`）はモックの `updateLockUI` のまま＝**`pct = rate/LOCK_RATE*100`**（時間ではなく合格率）。
- `MS=50`（20fps）×20フレーム＝1.00秒ぶんの窓 → **最速約1秒でロック**。
- 5ランプ＋最劣条件の診断文（`updateStatus`）は現状踏襲。閾値は据え置き。
- **`locked` でない間は採取しない**（onPeak・粒子なし）。

### ② 採取（点滅ベース・`locked` 中・9秒で1000）
- `locked` 中のみ `detectPeakAndSpawn`（明るさ上昇→下降・最短80ms間隔）でピーク検出 → `onPeak`。
- **`onPeak` の加算 = `DAILY_MAX/54 ≈ 18.518`**（`remaining=max(0,DAILY_MAX−本日採取)` で頭打ち）。
  - 6点滅/秒 × 18.518 = 111.1/秒 → 9秒で1000。1000到達に必要なピーク = 54回。
  - 実機ハイビスカス≈6.9Hz → 採取 約7.8秒（6Hz丁度で9秒・5Hz等の遅い光だと9秒超だが本物の支配周波数は6.9Hz）。
- **`onPeak` ごとに `spawnChikarium()`（§C の粒子）を呼ぶ**。
- `acc`（=`sessionGain`/`dailyGot` 相当）に積み、`remaining` 到達で完了（`finish` 演出）。`locked` が外れた（光を外した）間はピークを数えない＝一時停止。

### ③ 退出・サーバ確定（変更なし）
- 退出時 `claimSaishu(Math.round(acc/10))`。サーバが1000でクランプ。

### 数値の根拠（モックからの唯一の加算変更）
- モックの `onPeak` は1ピーク+10。6点滅/秒×9秒×10=540 で1000に届かない。9秒・6点滅/秒で1000にするには **1ピーク=1000/54≈18.52**。
- **サーバのclaim単位10・上限1000は据え置き**（退出時 acc/10=100点滅）＝SQL不要。canon §1「明滅1回=10」はサーバ単位の記述で不変。変えるのはクライアントのゲージ加算のみ。画面に per-blink 数値は出さない。

## B. 定数
- `SAISHU_HARVEST_SEC = 9`
- `SAISHU_BLINK_HZ = 6`
- `SAISHU_PER_PEAK = DAILY_MAX / (SAISHU_BLINK_HZ * SAISHU_HARVEST_SEC)`  // = 18.518…
- 判定は `TUNE.LOCK_WIN`/`TUNE.LOCK_RATE`（=20/0.60）を使う＝**判定用の新定数は追加しない**。
- **本番は上限ON**（mockの `NO_LIMIT` 相当は false／残量クランプ）。mockのテスト用「300上限トグル」は本番に出さない（saishu-detection-history §6）。

---

## C. 粒子演出の移植（現行に不在＝必須・モック L374-404 相当）

モック（vanilla JS）の以下を **React/Babel の `Saishu` に移植**する（現行は丸ごと欠落）。

1. **`#fx` オーバーレイ canvas**：video の上に `position:absolute; inset:0; width:100%; height:100%; pointer-events:none;`。**ref で参照**（例 `fxRef`）。カメラ枠 div（video＋hidden canvas がある所）に兄弟として追加。
2. **状態**：`particles=[]`・`lastSpawn`・`fxRaf`。`stateRef.current` か専用 ref に持つ（再レンダで消えないこと）。
3. **`spawnChikarium()`**：`fx.width/height` 基準でパーティクル1つ push（モックの初速・寿命・サイズ・回転のまま）。`particles.length>100` で間引き。
4. **`updateFx()`＋`drawP(p,al)`**：毎フレーム重力で落下・寿命でフェード。`drawP` は **`jewelImg` を `drawImage`**、未ロード時は金色 radial グラデ＋十字スパークルの**フォールバック**（モックのまま）。
5. **`fxLoop()`**：`requestAnimationFrame` で `updateFx`。**useEffect 内で起動し、クリーンアップで `cancelAnimationFrame`**。
6. **`fxResize()`**：`fx.width=fx.clientWidth; fx.height=fx.clientHeight`。マウント時1回＋`resize` リスナ（クリーンアップで解除）。**canvasの実ピクセルとCSSサイズを一致**（忘れると描画されない）。
7. **アイコン**：
   ```
   const jewelImg = new Image();
   jewelImg.onload = () => { jewelReady = true; };
   jewelImg.src = './images/ic_chikarium_Jewel.png';   // 大文字J。実在確認済み
   ```
   フォールバックのグラデ宝石は必ず残す。

React 移植の注意：
- モックは `document.getElementById('fx')` をモジュール読込時に取得しているが、Reactでは **マウント後（useEffect 内）に ref から取得**（描画ループ・リサイズもそこで起動）。
- 2dコンテキスト取得・rAF起動・リスナ登録は、カメラの `analyze` を起動している既存 useEffect に相乗りさせ、**同じクリーンアップで停止**。
- `spawnChikarium` は §A② の `onPeak` から呼ぶ。

---

## D. 残す / 触らない
- **残す/復活**：判定ゲージ（率ベース・モックのまま）・5判定項目ランプ・診断文・**粒子演出（§C 移植）**。
- **触らない**：`TUNE` 閾値（LOCK_WIN/LOCK_RATE 含む）／サーバ 0003。調整パネル（⚙）は本番非表示が正典方針（saishu-detection-history §6）だが今回スコープ外。

## E. 受け入れ確認
- 採取中、ピークごとに**チカリウムの宝石が弾ける**（`ic_chikarium_Jewel.png`／未読込時はグラデ宝石）。
- 判定はモックのまま率ベース（合格率ゲージ・最速約1秒でロック）。
- 満タン日：ロック後、採取（実機≈6.9Hzで約7.8秒・6Hzで9秒）で +1000、所持+1000、上限到達でホーム採取グレーアウト。
- 部分日（残200）：早期完了（+200）。
- カメラを外すと判定/採取/粒子が止まり、戻すと再開。
- **SQL変更が無い**こと。
