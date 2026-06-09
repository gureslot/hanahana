/* チカリアン 共通サウンド（全画面共通）
   - 音声オン/オフは localStorage "ck_sound_on"（"1"=オン / "0"=オフ・未設定はオン）で全画面共通管理。
   - パスは各htmlから見て sounds/ファイル名.mp3。
   - ファイルが無い効果音を鳴らそうとしてもエラーにならない（後でファイルを置けば自動で鳴る）。
   - ブラウザの自動再生制限：SEはクリック（ユーザー操作）契機なので再生可。BGMは最初の操作後に開始。 */
(function () {
  var KEY = 'ck_sound_on';
  var bgm = null, bgmSrc = null;

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
      try {
        var a = new Audio('sounds/' + name + '.mp3');
        a.volume = 0.9;
        var p = a.play();
        if (p && p.catch) p.catch(function () {});
      } catch (e) {}
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
