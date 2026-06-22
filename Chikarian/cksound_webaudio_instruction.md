# Claude Code 指示書：cksound.js の Web Audio 化（SE 再生遅延の解消）

対象：`Chikarian/cksound.js`。HEAD 基準。
背景：現状 `play(name)` が呼ばれるたびに `new Audio('sounds/'+name+'.mp3')` を生成して鳴らす HTMLAudio 方式のため、**再生のたびに mp3 のデコード/読込が走り、SE がワンテンポ遅れる**。これがブラウザゲームの SE 遅延の典型原因。対策として、起動後の初回ユーザー操作で全 SE を AudioBuffer へ一括デコードしておき、`play()` は `AudioBufferSourceNode` で即時発音する Web Audio 方式へ置換する。
注意：**公開 API（`isOn` / `setOn` / `toggle` / `play` / `initBGM` / `resumeBGM` / `stopBGM` の 7 メソッド）のシグネチャは一切変更しない**。index.html 側の呼び出し（`CKSound.play(...)` / `isOn()` / `setOn()`）は無改修で済む。**BGM・自動クリック SE（se_back / se_tap）・isBack 判定・localStorage キー `ck_sound_on`・BGM の `volume=0.45` / `loop=true` は逐語のまま据え置く**。変更するのは SE 再生経路のみ。
範囲：cksound.js の IIFE 内に SE 用の状態＋関数を追加し、`play()` の本体だけを差し替える 2 箇所。`window.CKSound = { ... }` の公開オブジェクトは不変。

---

## 変更0：IIFE 内モジュールスコープに「SE（Web Audio）ブロック」を追加

配置：IIFE の内側、かつ `function play(name) { ... }`（または公開オブジェクト）より**前**。BGM 用の変数群（`bgm` / `bgmSrc` など）の定義のすぐ後が分かりやすい。既存コードの削除は不要、**挿入のみ**。

【追加コード】
```js
  /* ===== SE: Web Audio 化（HTMLAudio の再生時デコード遅延を排除）===== */
  var _AC = window.AudioContext || window.webkitAudioContext;
  var _ctx = null;          // AudioContext（初回ユーザー操作で生成）
  var _buf = {};            // name -> AudioBuffer（デコード済みキャッシュ）
  var _load = {};           // name -> Promise（多重デコード防止）
  var _seUnlocked = false;
  var _PRELOAD = ['se_tap', 'se_back', 'se_card_flip', 'se_enhance_success', 'se_enhance_fail'];

  function _ensureCtx() {
    if (!_AC) return null;
    if (!_ctx) _ctx = new _AC();
    if (_ctx.state === 'suspended' && _ctx.resume) _ctx.resume();
    return _ctx;
  }
  function _decode(name) {
    if (_buf[name]) return Promise.resolve(_buf[name]);
    if (_load[name]) return _load[name];
    var c = _ensureCtx();
    if (!c) return Promise.reject(new Error('no AudioContext'));
    var pr = fetch('sounds/' + name + '.mp3')
      .then(function (r) { return r.arrayBuffer(); })
      .then(function (ab) { return c.decodeAudioData(ab); })
      .then(function (b) { _buf[name] = b; delete _load[name]; return b; })
      .catch(function (e) { delete _load[name]; throw e; });
    _load[name] = pr;
    return pr;
  }
  function _fire(buf) {
    var c = _ensureCtx(); if (!c || !buf) return;
    var s = c.createBufferSource();
    s.buffer = buf; s.connect(c.destination); s.start(0);
  }
  // 初回ユーザー操作：AudioContext 起動＋無音 warm up（iOS のロック解除）＋全 SE 先読みデコード
  function _seUnlock() {
    if (_seUnlocked) return; _seUnlocked = true;
    var c = _ensureCtx();
    if (c) {
      try { var s = c.createBufferSource(); s.buffer = c.createBuffer(1, 1, 22050); s.connect(c.destination); s.start(0); } catch (e) {}
      _PRELOAD.forEach(function (n) { _decode(n).catch(function () {}); });
    }
    window.removeEventListener('pointerdown', _seUnlock);
    window.removeEventListener('touchstart', _seUnlock);
    window.removeEventListener('keydown', _seUnlock);
  }
  window.addEventListener('pointerdown', _seUnlock);
  window.addEventListener('touchstart', _seUnlock);
  window.addEventListener('keydown', _seUnlock);
```

---

## 変更1：`play()` の本体を差し替え

既存の `play(name)` の**中身だけ**を以下に置換（関数名・引数・公開方法は不変）。`new Audio(...)` で都度生成していた処理を、デコード済みバッファの即時発音へ置き換える。Web Audio 非対応環境は従来どおり `new Audio` にフォールバック。

【新 play()（本体）】
```js
    if (!isOn()) return;
    if (!_AC) { // Web Audio 非対応環境は従来どおり new Audio フォールバック
      try { var a = new Audio('sounds/' + name + '.mp3'); var p = a.play(); if (p && p.catch) p.catch(function () {}); } catch (e) {}
      return;
    }
    if (_buf[name]) { _fire(_buf[name]); return; }   // 通常：デコード済み＝即時・遅延ゼロ
    _decode(name).then(_fire).catch(function () {});  // 未登録名：初回のみ取得→再生、以降はキャッシュされ即時化
```

※ `play` が公開オブジェクト内に `play: function (name) { ... }` の形で定義されている場合も、置換対象はその関数本体（`{ ... }` の中身）。

---

## 不変（変更禁止）

以下は**一切変更しない**。逐語のまま残すこと。

- `isOn()`：`localStorage.getItem('ck_sound_on') !== '0'`（未設定はオン扱い）。
- `setOn(v)` / `toggle()`：localStorage 永続化と `resumeBGM()` / `stopBGM()` 呼び出しを含め現状維持。
- `initBGM(src)` / `resumeBGM()` / `stopBGM()`：BGM は **HTMLAudio のまま**（`loop=true` / `volume=0.45`、初回操作で開始）。BGM は Web Audio 化しない。
- 自動クリック SE ハンドラ（`document` の click で `se_back` / `se_tap` を鳴らす部分）と `isBack(...)` 判定ロジック：**逐語のまま**。
- `window.CKSound = { ... }` の公開メンバー構成。

---

## 確認事項

- アップロードされた cksound.js 文書は要約（逐語ソースではない）。**適用前に変更0/変更1以外の差分が出ていないこと（特に自動クリックハンドラ・isBack・BGM 3 メソッドが原文と一致すること）を `git diff` で確認**すること。
- SE 音量：原実装の `new Audio` は既定音量（1.0）。本置換も GainNode を挟まず `destination` 直結＝既定音量で**音量はそのまま**。
- 先読み対象は sounds/ 内の SE 5 種（`se_tap` / `se_back` / `se_card_flip` / `se_enhance_success` / `se_enhance_fail`）。**`_PRELOAD` 配列はファイル追加時の唯一の更新点**。一覧に無い name で `play()` しても、初回に取得・デコードしてキャッシュするため次回以降は即時化される。
- パス解決は従来どおり相対（`sounds/<name>.mp3`）。GitHub Pages・`http://127.0.0.1:5500` のいずれも同一オリジン＝ `fetch`＋`decodeAudioData` に CORS 問題は出ない。
- 初回のユーザー操作（タップ/キー/タッチ）まで AudioContext は起動しない（ブラウザの自動再生制限）。これは BGM と同じ制約で、初回操作前は SE も鳴らない（仕様どおり）。
- 動作確認手順：適用後 commit & push → Ctrl+Shift+R。①画面を1回タップ（warm up＋先読み発火）→②ボタン連打で `se_tap` が**遅延なく即時**鳴ること、③強化を実行し成功/失敗 SE が即時鳴ること、④設定で SE オフ→無音、オン→復帰、を確認。スマホ（特に iOS Safari）でも初回タップ後に遅延が消えていることを確認。
