/* チカリアン 共通サウンド（全画面共通）
   - 音声オン/オフは localStorage "ck_sound_on"（"1"=オン / "0"=オフ・未設定はオン）で全画面共通管理。
   - パスは各htmlから見て sounds/ファイル名.mp3。
   - ファイルが無い効果音を鳴らそうとしてもエラーにならない（後でファイルを置けば自動で鳴る）。
   - ブラウザの自動再生制限：SEはクリック（ユーザー操作）契機なので再生可。BGMは最初の操作後に開始。 */
(function () {
  var KEY = 'ck_sound_on';
  var bgm = null, bgmSrc = null;

  /* ===== iOS サイレントスイッチ対策 =====
     iPhone はサイレント(マナー)スイッチがオンだと音を消す。無音をループ再生する HTMLAudio 要素を
     1つ流すと「再生(playback)セッション」が保たれ、スイッチがオンでも BGM/SE が鳴る。
     SE がオンの間だけ保持し、オフにすれば解放する（他アプリの音楽を不要に止めない）。 */
  var _silent = null;
  function _silentSrc() {
    // 1秒の無音WAV(44.1kHz/mono/16bit)をその場生成（外部ファイル不要）。
    var sr = 44100, ch = 1, bps = 2, n = sr * ch * bps, view = new DataView(new ArrayBuffer(44 + n));
    function s(o, str) { for (var i = 0; i < str.length; i++) view.setUint8(o + i, str.charCodeAt(i)); }
    s(0, 'RIFF'); view.setUint32(4, 36 + n, true); s(8, 'WAVE');
    s(12, 'fmt '); view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, ch, true);
    view.setUint32(24, sr, true); view.setUint32(28, sr * ch * bps, true); view.setUint16(32, ch * bps, true); view.setUint16(34, 8 * bps, true);
    s(36, 'data'); view.setUint32(40, n, true);
    // 16bit符号付きの無音は全サンプル0。ArrayBuffer は 0 初期化のため追加書き込み不要。
    return URL.createObjectURL(new Blob([view.buffer], { type: 'audio/wav' }));
  }
  function _startKeepalive() {
    try {
      if (!_silent) { _silent = new Audio(_silentSrc()); _silent.loop = true; _silent.volume = 1; }
      var p = _silent.play(); if (p && p.catch) p.catch(function () {});
    } catch (e) {}
  }
  function _stopKeepalive() { if (_silent) { try { _silent.pause(); } catch (e) {} } }

  /* ===== SE: HTMLAudio プール（事前バッファでデコード遅延を排除／画面収録でも録音される）=====
     Web Audio(AudioContext) の出力は iOS の画面収録(ReplayKit)で録音が破綻しノイズ化するため、
     SE も BGM と同じ HTMLAudio 経路にする。各音を起動時に複数要素へ先読みロードし、
     ラウンドロビンで即時再生＆重なり再生する。 */
  var _seUnlocked = false;
  var _POOL = {};           // name -> [HTMLAudioElement, ...]
  var _rr = {};             // name -> 次に使う要素のインデックス
  var _POOL_N = 4;          // 1音あたりの同時再生数（重なり用）
  var _PRELOAD = ['se_tap', 'se_back', 'se_card_flip', 'se_enhance_success', 'se_enhance_fail'];

  // iOS は「ユーザー操作中に一度 play した要素」だけ後で任意契機に再生できる。
  // ミュートで一瞬 play→pause し、再生許可だけ取得する。
  function _unlock(a) {
    try {
      a.muted = true;
      var p = a.play();
      var fin = function () { try { a.pause(); a.currentTime = 0; a.muted = false; } catch (e) {} };
      if (p && p.then) p.then(fin, fin); else fin();
    } catch (e) {}
  }
  function _ensurePool(name) {
    if (_POOL[name]) return _POOL[name];
    var arr = [];
    for (var i = 0; i < _POOL_N; i++) {
      var a = new Audio('sounds/' + name + '.mp3');
      a.preload = 'auto';
      try { a.load(); } catch (e) {}
      if (_seUnlocked) _unlock(a);   // 操作後に新規生成したプールは即解錠
      arr.push(a);
    }
    _POOL[name] = arr; _rr[name] = 0;
    return arr;
  }
  function _seFire(name) {
    var arr = _ensurePool(name);
    var idx = _rr[name] % arr.length; _rr[name] = (idx + 1) % arr.length;
    var a = arr[idx];
    try { a.currentTime = 0; var p = a.play(); if (p && p.catch) p.catch(function () {}); } catch (e) {}
  }
  // 初回ユーザー操作：全プールを解錠（非操作契機のSE＝強化結果音などを後から鳴らせるように）＋keepalive開始。
  function _seUnlock() {
    if (_seUnlocked) return; _seUnlocked = true;
    _PRELOAD.forEach(function (n) { _ensurePool(n).forEach(_unlock); });
    if (localStorage.getItem(KEY) !== '0') _startKeepalive();   // SEオンならiOS用に再生セッション保持
    window.removeEventListener('pointerdown', _seUnlock);
    window.removeEventListener('touchstart', _seUnlock);
    window.removeEventListener('keydown', _seUnlock);
  }
  window.addEventListener('pointerdown', _seUnlock);
  window.addEventListener('touchstart', _seUnlock);
  window.addEventListener('keydown', _seUnlock);
  // 起動時に先読みロード（初回タップ前にバッファを用意＝最初のタップも即時化）。
  _PRELOAD.forEach(function (n) { _ensurePool(n); });

  var CKSound = {
    isOn: function () { return localStorage.getItem(KEY) !== '0'; }, // 未設定はオン
    setOn: function (v) {
      localStorage.setItem(KEY, v ? '1' : '0');
      if (v) { _startKeepalive(); this.resumeBGM(); } else { _stopKeepalive(); this.stopBGM(); }
    },
    toggle: function () { var n = !this.isOn(); this.setOn(n); return n; },

    // 効果音：事前ロード済みHTMLAudioをラウンドロビン再生（重なり再生OK）。未配置ファイルは握りつぶす。
    play: function (name) {
      if (!this.isOn()) return;
      _seFire(name);
    },

    // ホーム専用：最初のユーザー操作でBGMをループ開始
    initBGM: function (src) {
      bgmSrc = src;
      var self = this, started = false;
      function start() {
        if (started) return; started = true;
        self.resumeBGM();
        window.removeEventListener('pointerdown', start);
        window.removeEventListener('keydown', start);
      }
      window.addEventListener('pointerdown', start);
      window.addEventListener('keydown', start);
    },
    resumeBGM: function () {
      if (!bgmSrc || !this.isOn()) return;
      try {
        if (!bgm) { bgm = new Audio(bgmSrc); bgm.loop = true; bgm.volume = 0.45; }
        var p = bgm.play();
        if (p && p.catch) p.catch(function () {});
      } catch (e) {}
    },
    stopBGM: function () { if (bgm) { try { bgm.pause(); } catch (e) {} } }
  };
  window.CKSound = CKSound;

  // 戻る／閉じるボタンの判定
  function isBack(el) {
    var cls = (typeof el.className === 'string') ? el.className : '';
    var s = ((el.id || '') + ' ' + cls).toLowerCase();
    if (s.indexOf('back') >= 0 || s.indexOf('close') >= 0) return true;
    var t = (el.textContent || '').trim();
    if (t === '×' || t === '✕' || t === '‹' || t.indexOf('戻る') >= 0 || t.indexOf('閉じる') >= 0) return true;
    return false;
  }

  // 全画面共通：クリックで操作対象を探し、戻る/閉じる→se_back、その他のボタン→se_tap
  document.addEventListener('click', function (e) {
    var el = e.target, hit = null;
    for (var i = 0; el && el.nodeType === 1 && i < 12; i++, el = el.parentElement) {
      var clickable = (el.tagName === 'BUTTON' || el.tagName === 'A');
      if (!clickable) { try { clickable = (getComputedStyle(el).cursor === 'pointer'); } catch (_) {} }
      if (clickable) { hit = el; break; }
    }
    if (!hit) return;
    CKSound.play(isBack(hit) ? 'se_back' : 'se_tap');
  }, true);
})();
