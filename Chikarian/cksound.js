/* チカリアン 共通サウンド（全画面共通）
   - 音声オン/オフは localStorage "ck_sound_on"（"1"=オン / "0"=オフ・未設定はオン）で全画面共通管理。
   - パスは各htmlから見て sounds/ファイル名.mp3。
   - ファイルが無い効果音を鳴らそうとしてもエラーにならない（後でファイルを置けば自動で鳴る）。
   - ブラウザの自動再生制限：SEはクリック（ユーザー操作）契機なので再生可。BGMは最初の操作後に開始。 */
(function () {
  var KEY = 'ck_sound_on';
  var bgm = null, bgmSrc = null;

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

  var CKSound = {
    isOn: function () { return localStorage.getItem(KEY) !== '0'; }, // 未設定はオン
    setOn: function (v) {
      localStorage.setItem(KEY, v ? '1' : '0');
      if (v) { this.resumeBGM(); } else { this.stopBGM(); }
    },
    toggle: function () { var n = !this.isOn(); this.setOn(n); return n; },

    // 効果音：毎回新しいAudioを生成（重なり再生OK）。未配置ファイルは握りつぶす。
    play: function (name) {
      if (!this.isOn()) return;
      if (!_AC) { // Web Audio 非対応環境は従来どおり new Audio フォールバック
        try { var a = new Audio('sounds/' + name + '.mp3'); var p = a.play(); if (p && p.catch) p.catch(function () {}); } catch (e) {}
        return;
      }
      if (_buf[name]) { _fire(_buf[name]); return; }   // 通常：デコード済み＝即時・遅延ゼロ
      _decode(name).then(_fire).catch(function () {});  // 未登録名：初回のみ取得→再生、以降はキャッシュされ即時化
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
