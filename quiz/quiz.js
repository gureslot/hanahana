'use strict';

const REEL_NAMES = ['left', 'middle', 'right'];
const SYMBOL_NAMES = [
  'bell', 'replay', 'suika', 'cherry', 'hana',
  'pink7', 'white7', 'hibiscus', 'pinkBAR', 'whiteBAR',
];
const COLOR_KEY = { pink: 'pink7', white: 'white7' };
const REEL_LABEL = { left: '左', middle: '中', right: '右' };

// リザルト画像（画像を保存ボタン）の合成に使う素材。SYMBOL_NAMESとは別に
// 事前読み込みしておき、canvas生成をユーザー操作（クリック）と同じタスク内で
// 同期的に完結させる（iOS Safariでのnavigator.share/ダウンロードの成功率を上げる）。
const RESULT_IMAGE_NAMES = ['title1', 'title2', 'titleBG', 'scoredaiza'];

// bgm：難易度ごとのBGM。初心者・易はquizBGM2.mp3（138.7秒）、並・極は
// quizBGM.mp3（156.05秒、従来どおり）。どちらも制限時間の最大60秒より
// 十分長いためループは不要。
const DIFFICULTIES = {
  beginner: { label: '初心者', special: true, bgm: 'sounds/quizBGM2.mp3' },
  easy: { label: '易', shift: 2, reelCount: 1, fixLeft: true, bgm: 'sounds/quizBGM2.mp3' },
  normal: { label: '並', shift: 2, reelCount: 2, fixLeft: false, bgm: 'sounds/quizBGM.mp3' },
  hard: { label: '極', shift: 1, reelCount: 1, fixLeft: false, bgm: 'sounds/quizBGM.mp3' },
};

// 初心者モードの出目条件（仕様：左中段4or14・正解色のAがmax-min<=4）。
const BEGINNER_SPREAD_MAX = 4;

const DIFFICULTY_ICON = { beginner: 'syo', easy: 'yasa', normal: 'nami', hard: 'kiwami' };
const RING_TIME_VALUES = [30, 60];

/* ---------- タイトル画面：難易度・時間のリングUI ----------
 * 楕円軌道上にカードをposition:absoluteで並べる（3D transform/preserve-3dは
 * 使わない。カード自体は回転させず、常に正面を向いたまま）。
 * RING_RX/RING_RYが軌道の横/縦半径、RING_TILT_SKEWがxに比例してyをずらす
 * 傾き係数（左が下がり・右が上がる）、RING_SCALE_*が手前/奥のスケール範囲。
 * 実際に使った数値は報告に記載。 */
const RING_STEP_PX = 50; // スワイプでカード1枚ぶん送るのに必要なドラッグ距離(px)
const RING_RX = 70; // 楕円軌道の横半径(px)。100だとカードが◀▶ボタンに重なるため縮小
const RING_RY = 26; // 楕円軌道の縦半径(px)
const RING_TILT_SKEW = 0.35; // 左下がり・右上がりの傾き係数（xの大きさに比例してyをずらす）
const RING_SCALE_MAX = 1.15; // 手前（選択中）のスケール
const RING_SCALE_MIN = 0.62; // 奥（正面から最も遠い位置）のスケール
const RING_BRIGHTNESS_SELECTED = 1;
const RING_BRIGHTNESS_UNSELECTED = 0.55;
const RING_BRIGHTNESS_DISABLED = 0.25;

/* ---------- ランキング（Supabase REST API） ----------
 * supabase-jsは使わずfetchで直接叩く。anon keyはブラウザ埋め込み前提の
 * 公開キー（RLSでSELECT/INSERTのみ許可・UPDATE/DELETEは不可）。
 * Supabase Authは使わない（ログインなし）。 */
const SUPABASE_URL = 'https://pyzgeadtvpjjgoqvihuw.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB5emdlYWR0dnBqamdvcXZpaHV3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg1MjA3MDksImV4cCI6MjEwNDA5NjcwOX0.O8tBN6MtQy5_liMFJnGesJZLtzCB6CdkPBFMR1LmJOk';
const SCORES_URL = SUPABASE_URL + '/rest/v1/scores';
const RANKING_TOP_N = 20;

// ランキングは難易度×制限時間で7本（初心者は30秒のみ）。
const RANKING_BOARDS = [
  { diff: 'beginner', time: 30, label: '初心者' },
  { diff: 'easy', time: 30, label: '易 30秒' },
  { diff: 'easy', time: 60, label: '易 60秒' },
  { diff: 'normal', time: 30, label: '並 30秒' },
  { diff: 'normal', time: 60, label: '並 60秒' },
  { diff: 'hard', time: 30, label: '極 30秒' },
  { diff: 'hard', time: 60, label: '極 60秒' },
];

const ROW_DEFS = [
  { offset: 2, mode: 'peekBottom' },  // 枠上：N+2 の下側1/3
  { offset: 1, mode: 'full' },        // 上段：N+1
  { offset: 0, mode: 'full' },        // 中段：N
  { offset: -1, mode: 'full' },       // 下段：N-1
  { offset: -2, mode: 'peekTop' },    // 枠下：N-2 の上側1/3
];

let reelsData = null;
let sevens = null;
let symbolImages = {};
let resultImages = {}; // リザルト画像合成用（RESULT_IMAGE_NAMES参照）
let currentDifficulty = 'easy';
let currentQuestion = null;
let debugMode = false;
let forcedStops = null; // ?fix=左,中,右 で出目を固定（検証用）

/* ---------- ゲーム進行（仕様書 第6章：タイマー・スコアのみ） ---------- */

// gamePhase: 'idle'（未開始） | 'preview'（1問だけ表示＝タイマーなし） |
//            'playing'（タイマー中） | 'ending'（時間切れ後の3秒静止） | 'result'
let gamePhase = 'idle';
let currentTimeLimit = 30; // 30 / 60
let lastManualTimeLimit = 30; // プレイヤーが最後に自分で選んだ時間（初心者を抜けたときに復元する）
let timerStartMs = 0; // performance.now() 基準の開始時刻
let timerTotalMs = 0; // 制限時間の総ミリ秒
let timerPausedTotalMs = 0; // これまでに停止していた合計時間（回答待ちの1秒間ぶん）
let timerPauseStartedAt = null; // 現在停止中ならその開始時刻。停止中でなければnull
let timerRafId = null; // requestAnimationFrame のID
let endingTimeoutId = null; // 時間切れ後の3秒静止用
let endSePlayed = false; // end.wav（時間切れの瞬間の笛）を1ゲームにつき1回だけ鳴らすためのフラグ
let correctCount = 0;
let wrongCount = 0;
let records = []; // 1問ごとの出題・回答記録（振り返り画面で使用）
let beginnerCandidates = []; // 初心者モードの出目候補（起動時に一度だけ生成）
let easyCandidates = []; // 易モードの出目候補（起動時に一度だけ生成。左中段4/14固定）
let normalHardCandidates = []; // 並・極モードの出目候補（起動時に一度だけ生成。左中段自由）
let reviewIndex = 0; // 振り返り画面で現在表示中の問題番号（0始まり、records基準）
let diffRingState = null; // タイトル画面：難易度リングの状態
let timeRingState = null; // タイトル画面：時間リングの状態

/* ---------- ランキング：状態 ---------- */
let pendingRankEntry = null; // ランクイン確定後、送信待ちのデータ（difficulty/time_limit/score/correct/wrong）
let rankSubmitted = false; // 二重送信防止（このリザルト表示中に送信済みか）
let lastSubmittedEntry = null; // 直近に登録できた1件（ランキング画面で自分の行を目立たせるために使う）
let currentRankingBoard = null; // ランキング画面で表示中の板 { diff, time }
let rankingRequestSeq = 0; // 板を切り替えたときに古いリクエストの結果を無視するための連番

/* ---------- 音（仕様書 第6章：BGM・SE） ---------- */

let seikaiSeEl = null; // 正誤SE「正解」専用。srcは固定で差し替えない（差し替えは再ロードを招く）
let huseikaiSeEl = null; // 正誤SE「不正解」専用。srcは固定で差し替えない
let endSeEl = null; // end.wav専用。一度鳴らしたら途中で止めない
let seUnlocked = false; // 初回のユーザー操作でSE要素の再生権を取得済みか（二重に走らせない）
let tickSeEls = []; // tsu.wav用プール（リング連打で重ねて鳴らせるようラウンドロビン）
let tickSeIndex = 0;
const TICK_SE_POOL_SIZE = 4;

// ---- ?debug=1診断用（SEの遅れ調査。挙動には影響しない計測のみ） ----
let lastSeLatencyMs = null; // 直近のSE再生：play()呼び出しからplaying発火までの経過ms
let lastSeLatencyLabel = ''; // 上記がどの音か（seikai/huseikai/end/tick）
let seDebugPanelEl = null; // 診断パネルのDOM要素（?debug=1のときだけ生成）
let bgmEl = null;
let bgmVolume = 0.8;
let seVolume = 0.8;
// 初期状態は必ずミュートON（音声オフ）。localStorageには保存せず、リロードのたびに戻る。
let bgmMuted = true;
let seMuted = true;

function parseForcedStops() {
  const raw = new URLSearchParams(location.search).get('fix');
  if (!raw) return null;
  const parts = raw.split(',').map((s) => parseInt(s.trim(), 10));
  if (parts.length !== 3 || parts.some((n) => Number.isNaN(n))) return null;
  return { left: parts[0], middle: parts[1], right: parts[2] };
}

async function init() {
  try {
    debugMode = new URLSearchParams(location.search).get('debug') === '1';
    // SE要素がまだ生成されていない段階（画像プリロード前）から状態を追えるよう、
    // 他の初期化より先に診断パネルを立てる（タイトル画面でも見えるようにするため）。
    setupSeDebugPanel();
    forcedStops = parseForcedStops();
    const res = await fetch('reels.json');
    if (!res.ok) throw new Error('reels.json の取得に失敗しました（status ' + res.status + '）');
    const data = await res.json();
    reelsData = data.reels;
    sevens = data.sevens;
    bgmEl = document.getElementById('bgmAudio');
    await preloadImages();
    await preloadResultImages();
    beginnerCandidates = buildBeginnerCandidates();
    easyCandidates = buildStopCandidates(true).candidates;
    normalHardCandidates = buildStopCandidates(false).candidates;
    await preloadSounds();
    setupUI();
    setupTitleScreen();
    setPhase('idle');
    // ?fix= 指定時は従来どおり即表示する（?debug=1と組み合わせた検証用フロー）。
    // タイトル画面は挟まず、確認用UIまで含む本編画面をいきなり表示する。
    if (forcedStops) {
      showAppScreen();
      setPhase('preview');
      newQuestion();
    }
  } catch (err) {
    document.body.innerHTML =
      '<p style="color:#f66;padding:20px;">初期化に失敗しました: ' + err.message +
      '<br>file:// で直接開くと reels.json や画像の読み込みに失敗します。' +
      '簡易サーバー経由で開いてください。</p>';
    console.error(err);
  }
}

function preloadImages() {
  return Promise.all(SYMBOL_NAMES.map((name) => new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      symbolImages[name] = img;
      resolve();
    };
    img.onerror = () => reject(new Error('画像の読み込みに失敗: images/' + name + '.png'));
    img.src = 'images/' + name + '.png';
  })));
}

function preloadResultImages() {
  return Promise.all(RESULT_IMAGE_NAMES.map((name) => new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      resultImages[name] = img;
      resolve();
    };
    img.onerror = () => reject(new Error('画像の読み込みに失敗: images/' + name + '.png'));
    img.src = 'images/' + name + '.png';
  })));
}

/* ---------- 音の読み込み・再生 ----------
 * SEは<audio>要素で鳴らす（Web Audio API・AudioContextは使わない）。
 * AudioContextの出力はiOSの画面収録に正しく乗らず、録画した音声がノイズになる
 * ことが確認できたため撤去した（同一原因の別プロジェクトでHTMLAudio化して解消済み）。
 * wavのままにしてあるのはmp3の先頭無音パディングによる再生遅延を避けるためで、
 * <audio>に移してもこの理由は変わらない。
 * 全SEはnew Audio()＋load()で起動時に事前ロードする。
 *
 * SEは3チャンネル構成：
 * ・正誤SE（seikai/huseikai）はそれぞれ専用の1要素に固定し、srcは差し替えない
 *   （1要素でsrcを差し替える実装だと、鳴らすたびに再ロードが発生し発音が遅れる）。
 *   新しい方を鳴らす前に両方をpause+currentTime=0で巻き戻してから鳴らす（正解SEが
 *   2.78秒あり、これをしないと連続回答で重なり続ける＝1チャンネル仕様は維持する）。
 * ・end.wav（時間切れの瞬間の笛）は独立した1要素。一度鳴り始めたら途中で
 *   止めない（時間切れ後の3秒静止のあいだも鳴り終わるまで続く）。
 * ・tsu.wav（リングが回って正面に来た瞬間のSE）も独立チャンネルだが、連続で
 *   回すと短い間隔で重なって鳴りうるため、専用のプールをラウンドロビンで回す。
 * 音量・ミュートは各要素の.volume/.mutedにそれぞれ反映する
 * （applySeVolume/applySeMute）。 */

function createSeAudio(src) {
  const el = new Audio(src);
  el.preload = 'auto';
  el.load();
  return el;
}

function preloadSounds() {
  seikaiSeEl = createSeAudio('sounds/seikai.wav');
  huseikaiSeEl = createSeAudio('sounds/huseikai.wav');
  endSeEl = createSeAudio('sounds/end.wav');
  tickSeEls = [];
  for (let i = 0; i < TICK_SE_POOL_SIZE; i++) {
    tickSeEls.push(createSeAudio('sounds/tsu.wav'));
  }
  applySeVolume();
  applySeMute();
}

// 音量・ミュート反映の対象になる全SE要素
function allSeEls() {
  return [seikaiSeEl, huseikaiSeEl, endSeEl, ...tickSeEls].filter(Boolean);
}

// モバイルの自動再生制限は<audio>にもかかる。programmaticなplay()（end.wavの
// タイマー発火など、クリックの外から呼ばれるもの）が後で失敗しないよう、最初の
// ユーザー操作で全SE要素の再生権を先に取得しておく。play()の間は一時的にmutedに
// して実際に音を出さず、完了後はミュート状態（seMuted。volumeは使わない）に戻す。
// 二重に走らないよう、初回成功後はseUnlockedを立てて以後は即座に解決済みの
// Promiseを返す（呼び出し側で.then()を使っても安全）。
function unlockSeElements() {
  if (seUnlocked) return Promise.resolve();
  seUnlocked = true;
  return Promise.all(allSeEls().map((el) => {
    el.muted = true;
    const restore = () => {
      try {
        el.pause();
        el.currentTime = 0;
      } catch (err) { /* 無視 */ }
      el.muted = seMuted;
    };
    return el.play().then(restore, restore);
  }));
}

// 最初のユーザー操作（STARTやミュートボタンに限らず、タイトル画面のリングを
// 先に触った場合も含む）でSE要素の再生権を取得する。発火後は自身を解除する。
function unlockSeElementsOnFirstGesture() {
  unlockSeElements();
  window.removeEventListener('pointerdown', unlockSeElementsOnFirstGesture);
  window.removeEventListener('touchstart', unlockSeElementsOnFirstGesture);
  window.removeEventListener('keydown', unlockSeElementsOnFirstGesture);
}
window.addEventListener('pointerdown', unlockSeElementsOnFirstGesture);
window.addEventListener('touchstart', unlockSeElementsOnFirstGesture);
window.addEventListener('keydown', unlockSeElementsOnFirstGesture);

// ?debug=1診断用：play()呼び出しからplaying発火（実際に鳴り始めた瞬間）までの
// 経過msを記録するだけで、再生そのものの挙動は変えない。
function trackSePlayLatency(el, label) {
  if (!debugMode) return;
  const t0 = performance.now();
  const onPlaying = () => {
    lastSeLatencyMs = performance.now() - t0;
    lastSeLatencyLabel = label;
    el.removeEventListener('playing', onPlaying);
  };
  el.addEventListener('playing', onPlaying);
}

// 正誤SE（seikai/huseikai）：それぞれ専用1要素（srcは固定・差し替えない）。
// 1チャンネル仕様を維持するため、新しい方を鳴らす前に両方を巻き戻す。
function playJudgeSe(name) {
  if (!seikaiSeEl || !huseikaiSeEl) return;
  seikaiSeEl.pause();
  seikaiSeEl.currentTime = 0;
  huseikaiSeEl.pause();
  huseikaiSeEl.currentTime = 0;
  const el = name === 'seikai' ? seikaiSeEl : huseikaiSeEl;
  trackSePlayLatency(el, name);
  el.play().catch((err) => console.error('SEの再生に失敗しました（無音のまま続行します）', err));
}

// end.wav専用チャンネル：正誤SEとは独立に鳴らし、途中で止めない（最後まで鳴らしきる）。
function playEndSe() {
  if (!endSeEl) return;
  endSeEl.currentTime = 0;
  trackSePlayLatency(endSeEl, 'end');
  endSeEl.play().catch((err) => console.error('SEの再生に失敗しました（無音のまま続行します）', err));
}

// tsu.wav専用チャンネル：リング（難易度・時間）が回って正面に来た瞬間に鳴らす。
// 連続で回すと短い間隔で重なって鳴りうるため、プールをラウンドロビンで回す。
function playRingTickSe() {
  if (tickSeEls.length === 0) return;
  const el = tickSeEls[tickSeIndex];
  tickSeIndex = (tickSeIndex + 1) % tickSeEls.length;
  el.currentTime = 0;
  trackSePlayLatency(el, 'tick');
  el.play().catch(() => { /* 無視：次回以降の操作で再試行される */ });
}

function applyBgmVolume() {
  if (bgmEl) bgmEl.volume = bgmVolume;
}

// BGMのミュート反映はここに集約する（.volumeではなく.mutedを使う＝音量設定を
// 壊さず、src差し替え時の読み込み状態に左右されず確実に無音にできる）。
// 状態が変わりうる全箇所（初期化・タイトル/確認用UIのトグル・play()直前）から呼ぶこと。
function applyBgmMute() {
  if (bgmEl) bgmEl.muted = bgmMuted;
}

function applySeVolume() {
  allSeEls().forEach((el) => { el.volume = seVolume; });
}

// SEのミュート反映はここに集約する（applyBgmMute()と同じ形＝.mutedを使う）。
// 状態が変わりうる全箇所（初期化・タイトル/確認用UIのトグル）から呼ぶこと。
function applySeMute() {
  allSeEls().forEach((el) => { el.muted = seMuted; });
}

// スタートボタンのタップ（ユーザー操作）をきっかけにSE要素の再生権を取得し、BGMを再生する。
// BGMは難易度（DIFFICULTIES[].bgm）で切り替える：ここでスタート時に反映する。
function unlockAndPlayBgm() {
  unlockSeElements();
  if (!bgmEl) return;
  const bgmSrc = DIFFICULTIES[currentDifficulty].bgm;
  if (bgmSrc && !bgmEl.src.endsWith(bgmSrc)) {
    bgmEl.src = bgmSrc;
  }
  bgmEl.currentTime = 0;
  applyBgmVolume();
  applyBgmMute();
  bgmEl.play().catch((err) => console.error('BGMの再生に失敗しました（無音のまま続行します）', err));
}

function stopBgm() {
  if (!bgmEl) return;
  bgmEl.pause();
  bgmEl.currentTime = 0;
}

/* ---------- 数値ユーティリティ ---------- */

function mod21(n) {
  return ((n % 21) + 21) % 21;
}

// 任意の整数を 1〜21 のコマ番号に正規化する
function wrapNum(n) {
  return mod21(n - 1) + 1;
}

function symbolAt(reel, num) {
  return reelsData[reel][wrapNum(num) - 1];
}

function randNum() {
  return Math.floor(Math.random() * 21) + 1;
}

function colorLabel(color) {
  return color === 'pink' ? 'ピンク7' : '白7';
}

/* ---------- 出題生成・判定ロジック（仕様書 第5章） ---------- */

// 出目は難易度ごとに起動時生成済みの候補リストから選ぶ（同時押しになる／コマ数が
// 足りない出目を除外済み。buildStopCandidates参照）。
function generateStops(diffKey) {
  if (forcedStops) return forcedStops;
  const pool = diffKey === 'beginner' ? beginnerCandidates
    : diffKey === 'easy' ? easyCandidates
    : normalHardCandidates; // 並・極は同じ候補プール（制限がshift/reelCountに依存しないため）
  const idx = Math.floor(Math.random() * pool.length);
  return pool[idx];
}

function computeTiming(S) {
  const d = {};
  for (const r of REEL_NAMES) {
    d[r] = Math.min(mod21(10 - S[r]), mod21(21 - S[r]));
  }
  const D = Math.max(d.left, d.middle, d.right) + 3; // K = 3
  const X = {};
  for (const r of REEL_NAMES) {
    X[r] = wrapNum(S[r] + D);
  }
  return { d, D, X };
}

function computeColorRequired(X, P) {
  const Dline = {};
  for (const r of REEL_NAMES) {
    Dline[r] = mod21(P[r] - X[r]);
  }
  const required = Math.max(Dline.left, Dline.middle, Dline.right);
  return { Dline, required };
}

function judgeQuestion(S) {
  const timing = computeTiming(S);
  const pinkCalc = computeColorRequired(timing.X, sevens.pink7);
  const whiteCalc = computeColorRequired(timing.X, sevens.white7);
  let correctColors;
  if (pinkCalc.required < whiteCalc.required) correctColors = ['pink'];
  else if (whiteCalc.required < pinkCalc.required) correctColors = ['white'];
  else correctColors = ['pink', 'white'];
  return { S, timing, pinkCalc, whiteCalc, correctColors };
}

/* ---------- 出目の制限（同時押し・コマ数不足の除外） ----------
 * ハナハナは3つのストップボタンを同時に押せない。正解色のA（=Dline。受付ライン
 * から対象色7までのコマ数、ずらしなし）に対してのみ、以下を判定する：
 * 1) A=0のリールが2つ以上ある出目は除外（min(A)=0のときA=0のリールが1つだけ
 *    であること＝同時押しになる出目を弾く）
 * 2) max(A)<=1の出目は除外（3リール止めるには最低3コマ必要なため、第三停止が
 *    2コマ目までに来てしまう出目を弾く）
 * 同着（両色とも正解）の場合は両方の色を判定し、どちらか一方でも条件を
 * 満たさなければ除外する。不正解になる側の色は判定しない。 */
function passesStopTimingConstraint(Dline) {
  const zeroCount = REEL_NAMES.filter((r) => Dline[r] === 0).length;
  const maxD = Math.max(Dline.left, Dline.middle, Dline.right);
  return zeroCount <= 1 && maxD >= 2;
}

function passesStopConstraint(judge) {
  for (const color of judge.correctColors) {
    const Dline = color === 'pink' ? judge.pinkCalc.Dline : judge.whiteCalc.Dline;
    if (!passesStopTimingConstraint(Dline)) return false;
  }
  return true;
}

/* ---------- 初心者モード：出目候補の生成（起動時に一度だけ） ----------
 * 条件：左中段が4または14 / 正解色のA（受付ラインから7までのコマ数、
 * ずらしなし）についてmax(A)-min(A)<=BEGINNER_SPREAD_MAX / 出目の制限
 * （passesStopConstraint）を満たすこと。
 * 同着（正解色が定まらない）出目は候補から除外する。
 * 判定ロジック（judgeQuestion）は他難易度と共通・無変更。 */
function buildBeginnerCandidates() {
  const candidates = [];
  let pinkCount = 0;
  let whiteCount = 0;
  let tieCount = 0;
  let stopConstraintExcluded = 0;

  for (const left of [4, 14]) {
    for (let middle = 1; middle <= 21; middle++) {
      for (let right = 1; right <= 21; right++) {
        const S = { left, middle, right };
        const judge = judgeQuestion(S);
        if (judge.correctColors.length !== 1) {
          tieCount++;
          continue;
        }
        const color = judge.correctColors[0];
        const Dline = color === 'pink' ? judge.pinkCalc.Dline : judge.whiteCalc.Dline;
        const vals = [Dline.left, Dline.middle, Dline.right];
        const spread = Math.max(...vals) - Math.min(...vals);
        if (spread <= BEGINNER_SPREAD_MAX) {
          if (!passesStopConstraint(judge)) {
            stopConstraintExcluded++;
            continue;
          }
          candidates.push(S);
          if (color === 'pink') pinkCount++; else whiteCount++;
        }
      }
    }
  }

  console.log(
    '[初心者モード] 候補' + candidates.length + '件' +
    '（ピンク' + pinkCount + '・白' + whiteCount + '）、同着除外' + tieCount + '件' +
    '、出目の制限で除外' + stopConstraintExcluded + '件'
  );
  return candidates;
}

/* ---------- 易・並・極：出目候補の生成（起動時に一度だけ） ----------
 * fixLeft=true（易）は左中段4/14固定、fixLeft=false（並・極）は左中段自由。
 * 並・極は出目の制限がずらしのshift/reelCountに依存しないため、同じ候補
 * プールを共有する。同着（両色正解）も候補に含める（passesStopConstraint内で
 * 両方の色を判定済み）。 */
function buildStopCandidates(fixLeft) {
  const candidates = [];
  let pinkCount = 0;
  let whiteCount = 0;
  let tieCount = 0;
  const leftValues = fixLeft ? [4, 14] : Array.from({ length: 21 }, (_, i) => i + 1);

  for (const left of leftValues) {
    for (let middle = 1; middle <= 21; middle++) {
      for (let right = 1; right <= 21; right++) {
        const S = { left, middle, right };
        const judge = judgeQuestion(S);
        if (!passesStopConstraint(judge)) continue;
        candidates.push(S);
        if (judge.correctColors.length === 2) tieCount++;
        else if (judge.correctColors[0] === 'pink') pinkCount++;
        else whiteCount++;
      }
    }
  }

  const total = leftValues.length * 21 * 21;
  console.log(
    '[' + (fixLeft ? '易' : '並・極') + 'モード] 候補' + candidates.length + '件（全' + total + '通り中）' +
    '（ピンク' + pinkCount + '・白' + whiteCount + '・同着' + tieCount + '）'
  );
  return { candidates, pinkCount, whiteCount, tieCount };
}

/* ---------- 選択肢生成（仕様書 第4章） ---------- */

function shuffleArray(arr) {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
}

// 難易度に応じて「どのリールを・何コマ・どちら向きに」ずらすかをランダムに決める（反転前の生の値）
function makeRawOffsets(diffKey) {
  const diff = DIFFICULTIES[diffKey];
  const indices = [0, 1, 2];
  shuffleArray(indices);
  const chosen = indices.slice(0, diff.reelCount);
  const offsets = { left: 0, middle: 0, right: 0 };
  for (const idx of chosen) {
    const reel = REEL_NAMES[idx];
    const sign = Math.random() < 0.5 ? 1 : -1;
    offsets[reel] = sign * diff.shift;
  }
  return offsets;
}

function rangeSize(A) {
  const vals = [A.left, A.middle, A.right];
  return Math.max(...vals) - Math.min(...vals) + 1;
}

// リールごとに順（左→中→右）に o_i を適用し、適用時点で表示範囲が21コマを
// 超えるなら、そのリールだけ21コマに収まる位置まで切り上げ（または切り下げ）て
// 縮める（符号反転はしない。2リールまとめての調整もしない）。
// 下端をA=0で固定する必要がなくなったため、min(A)が0でない選択肢も出てよい。
function applyShiftsWithFlip(baseA, rawOffsets) {
  const A = { ...baseA };
  const finalOffsets = { left: 0, middle: 0, right: 0 };
  for (const reel of REEL_NAMES) {
    const amt = rawOffsets[reel] || 0;
    if (amt === 0) continue;
    A[reel] += amt;
    if (rangeSize(A) > 21) {
      const others = REEL_NAMES.filter((r) => r !== reel).map((r) => A[r]);
      const otherMax = Math.max(...others);
      const otherMin = Math.min(...others);
      if (A[reel] < otherMin) {
        A[reel] = otherMax - 20; // 下端を切り上げて21コマに収める
      } else if (A[reel] > otherMax) {
        A[reel] = otherMin + 20; // 上端を切り下げて21コマに収める
      }
    }
    finalOffsets[reel] = A[reel] - baseA[reel];
  }
  return { A, offsets: finalOffsets };
}

// 仕様書 第4章：A_i = (P_i − X_i) mod 21 + o_i
// refX：描画時に「リールiの (refX_i + 行) 番」で実際の図柄を引くための基準番号。
// ずらしなし（o_i=0）ならrefX=X。ずらしありの場合、7がA_i行に来る位置を保ったまま
// 基準をo_iぶんずらす（refX = X − o_i）。
function computeChoiceLayout(X, color, rawOffsets) {
  const P = sevens[COLOR_KEY[color]];
  const baseA = {};
  for (const r of REEL_NAMES) baseA[r] = mod21(P[r] - X[r]);
  const { A, offsets } = applyShiftsWithFlip(baseA, rawOffsets);
  const minA = Math.min(A.left, A.middle, A.right);
  const maxA = Math.max(A.left, A.middle, A.right);
  const refX = {};
  for (const r of REEL_NAMES) refX[r] = X[r] - offsets[r];
  return { baseA, A, offsets, minA, maxA, rows: maxA - minA + 1, refX };
}

function buildChoices(judgeResult, diffKey) {
  const X = judgeResult.timing.X;

  if (diffKey === 'easy' || diffKey === 'normal') {
    return buildEasyNormalChoices(judgeResult, diffKey, X);
  }

  // 極（hard）は従来どおり4択（正しい形2つ＋ずらし2つ）。
  const choices = [
    { color: 'pink', isCorrectForm: true },
    { color: 'white', isCorrectForm: true },
    { color: 'pink', isCorrectForm: false, rawOffsets: makeRawOffsets(diffKey) },
    { color: 'white', isCorrectForm: false, rawOffsets: makeRawOffsets(diffKey) },
  ];

  for (const c of choices) {
    const raw = c.isCorrectForm
      ? { left: 0, middle: 0, right: 0 }
      : c.rawOffsets;
    c.layout = computeChoiceLayout(X, c.color, raw);
    c.isCorrect = c.isCorrectForm && judgeResult.correctColors.includes(c.color);
  }

  shuffleArray(choices);
  return choices;
}

/* ---------- 選択肢生成：易・並（2択）のずらし候補の列挙 ----------
 * 難易度ごとの「どのリールを・何コマ・どちら向きに」ずらすかの全組み合わせを
 * 列挙する（ランダムに1つ選ぶmakeRawOffsetsとは別物。候補を高さ条件Rで
 * 絞り込んでから抽選するために全パターンが要る）。
 * 易＝1リール±shift（3リール×2方向＝6通り）、並＝2リール±shift
 * （3通りのリール組×2^2方向＝12通り）。 */
function combinations(arr, k) {
  if (k === 0) return [[]];
  if (arr.length < k) return [];
  const [first, ...rest] = arr;
  const withFirst = combinations(rest, k - 1).map((c) => [first, ...c]);
  const withoutFirst = combinations(rest, k);
  return withFirst.concat(withoutFirst);
}

function cartesianSigns(n) {
  if (n === 0) return [[]];
  const rest = cartesianSigns(n - 1);
  const result = [];
  for (const r of rest) {
    result.push([1, ...r]);
    result.push([-1, ...r]);
  }
  return result;
}

function enumerateOffsetCandidates(diffKey) {
  const diff = DIFFICULTIES[diffKey];
  const idxCombos = combinations([0, 1, 2], diff.reelCount);
  const results = [];
  for (const combo of idxCombos) {
    for (const signs of cartesianSigns(combo.length)) {
      const offsets = { left: 0, middle: 0, right: 0 };
      combo.forEach((idx, j) => {
        offsets[REEL_NAMES[idx]] = signs[j] * diff.shift;
      });
      results.push(offsets);
    }
  }
  return results;
}

// Aを最下段=0に正規化した相対パターン（絵の形そのものの比較に使う）
function normalizedPattern(A, min) {
  return { left: A.left - min, middle: A.middle - min, right: A.right - min };
}

function patternsEqual(a, b) {
  return a.left === b.left && a.middle === b.middle && a.right === b.right;
}

// ベース（常に正解色のA。baseA）に難易度なりのずらし全パターンを適用し、
// 21コマを超えるもの（クランプしない。候補から外す）と、正規化した絵が
// 正解と一致してしまうもの（実質「ずれていない」ため）を除いた候補一覧を返す。
function buildShiftCandidates(baseA, diffKey) {
  const baseMin = Math.min(baseA.left, baseA.middle, baseA.right);
  const basePattern = normalizedPattern(baseA, baseMin);
  const candidates = [];
  for (const offsets of enumerateOffsetCandidates(diffKey)) {
    const A = {
      left: baseA.left + offsets.left,
      middle: baseA.middle + offsets.middle,
      right: baseA.right + offsets.right,
    };
    const rows = rangeSize(A);
    if (rows > 21) continue;
    const minA = Math.min(A.left, A.middle, A.right);
    const maxA = Math.max(A.left, A.middle, A.right);
    if (patternsEqual(normalizedPattern(A, minA), basePattern)) continue;
    candidates.push({ A, offsets, minA, maxA, rows });
  }
  return candidates;
}

// ?debug=1でのみ参照する、直近に生成した易・並の2択目（不正解）の内訳。
// 正解の高さ・ダミーの高さ・R（高い/低い）・C（同色/異色）・型(a/b)を保持する。
let lastEasyNormalDebug = null;

/* ---------- 選択肢生成：易・並（2択） ----------
 * 1つ目は必ず正解（速い方の色・正しい形）。
 * 2つ目（ダミー）は以下の手順で作る（同着は除く）：
 *   1. 目標の高さ関係R（ダミーが正解より高い/低い）を50:50で抽選
 *   2. ダミーの描画色C（正解と同色25%／異色75%）をRとは独立に抽選
 *   3. ずらし候補集合を作る：ベースは必ず正解色のA。21コマ超は除外
 *      （クランプしない）。正規化した絵が正解と一致するものも除外。
 *      候補は高さがRを満たすものだけに絞る
 *   4. C=異色かつ「遅い色・正しい形」の高さがRを満たすならそれを採用。
 *      それ以外は3の候補から一様抽選し、色はCに従って描く
 *   5. 3の候補が空ならRを反転してやり直す
 * 高さで正解が読めてしまう問題（縦の短い方が高確率で正解）への対策。
 * 同着（ピンク・白の所要が同値）の場合はサービス問題として扱い、必ず
 * 両方を正しい形にする（どちらを押しても正解。ここは変更なし）。 */
function buildEasyNormalChoices(judgeResult, diffKey, X) {
  const isTie = judgeResult.correctColors.length === 2;

  if (isTie) {
    const choices = [
      { color: 'pink', isCorrectForm: true },
      { color: 'white', isCorrectForm: true },
    ];
    for (const c of choices) {
      c.layout = computeChoiceLayout(X, c.color, { left: 0, middle: 0, right: 0 });
      c.isCorrect = true;
    }
    lastEasyNormalDebug = null;
    shuffleArray(choices);
    return choices;
  }

  const correctColor = judgeResult.correctColors[0];
  const wrongColor = correctColor === 'pink' ? 'white' : 'pink';
  const correctLayout = computeChoiceLayout(X, correctColor, { left: 0, middle: 0, right: 0 });
  const wrongLayoutPlain = computeChoiceLayout(X, wrongColor, { left: 0, middle: 0, right: 0 });
  const hCorrect = correctLayout.rows;
  const hDummyPlain = wrongLayoutPlain.rows; // 型a（遅い色・正しい形）の高さ
  const baseA = correctLayout.A; // ずらし候補のベースは常に正解色のA

  const R = Math.random() < 0.5 ? 'higher' : 'lower';
  const C = Math.random() < 0.25 ? 'same' : 'diff';
  const typeASatisfiesR = R === 'higher' ? hDummyPlain > hCorrect : hDummyPlain < hCorrect;

  let secondChoice;
  const debugInfo = { hCorrect, hDummyPlain, R, C };

  if (C === 'diff' && typeASatisfiesR) {
    secondChoice = { color: wrongColor, isCorrectForm: true, layout: wrongLayoutPlain };
    debugInfo.type = 'a';
    debugInfo.hDummy = hDummyPlain;
  } else {
    let effectiveR = R;
    let candidates = buildShiftCandidates(baseA, diffKey).filter((cand) =>
      effectiveR === 'higher' ? cand.rows > hCorrect : cand.rows < hCorrect
    );
    if (candidates.length === 0) {
      // 手順5：候補が空ならRを反転してやり直す（発生率 約0.9%）
      effectiveR = effectiveR === 'higher' ? 'lower' : 'higher';
      candidates = buildShiftCandidates(baseA, diffKey).filter((cand) =>
        effectiveR === 'higher' ? cand.rows > hCorrect : cand.rows < hCorrect
      );
    }
    // 理論上ここは常に非空（仕様書の保証）。念のための最終フォールバックのみ用意する。
    if (candidates.length === 0) candidates = buildShiftCandidates(baseA, diffKey);

    const chosen = candidates[Math.floor(Math.random() * candidates.length)];
    const drawColor = C === 'same' ? correctColor : wrongColor;
    secondChoice = {
      color: drawColor,
      isCorrectForm: false,
      layout: { A: chosen.A, minA: chosen.minA, maxA: chosen.maxA, rows: chosen.rows, offsets: chosen.offsets },
    };
    debugInfo.type = 'b';
    debugInfo.hDummy = chosen.rows;
    debugInfo.effectiveR = effectiveR;
    debugInfo.flippedR = effectiveR !== R;
  }

  const choices = [
    { color: correctColor, isCorrectForm: true, layout: correctLayout, isCorrect: true },
    { ...secondChoice, isCorrect: false },
  ];

  lastEasyNormalDebug = debugInfo;
  shuffleArray(choices);
  return choices;
}

/* ---------- 選択肢生成：初心者モード（2択・色の見分けのみを問う）----------
 * 選択肢は「正解」（正解色・正解の形）と「不正解」の2つのみ。
 * 不正解側は「7の形（3つの7の相対位置＝A）は正解と同じ」にしつつ、
 * 周囲の図柄は正解色のものを流用せず、もう一方の色の7の実際の位置を
 * 基準にしたrefXで描く（＝もう一方の色の7が正解と同じ形に並んだ状態を
 * そのリール配列で描く）。他難易度の「ずらし」ロジックは使わない。 */
function buildBeginnerChoices(judgeResult) {
  const correctColor = judgeResult.correctColors[0];
  const wrongColor = correctColor === 'pink' ? 'white' : 'pink';
  const X = judgeResult.timing.X;
  const correctLayout = computeChoiceLayout(X, correctColor, { left: 0, middle: 0, right: 0 });

  const wrongP = sevens[COLOR_KEY[wrongColor]];
  const wrongRefX = {};
  for (const r of REEL_NAMES) wrongRefX[r] = wrongP[r] - correctLayout.A[r];
  const wrongLayout = { ...correctLayout, A: { ...correctLayout.A }, refX: wrongRefX };

  const choices = [
    { color: correctColor, isCorrectForm: true, layout: correctLayout, isCorrect: true },
    { color: wrongColor, isCorrectForm: true, layout: wrongLayout, isCorrect: false },
  ];

  shuffleArray(choices);
  return choices;
}

/* ---------- 描画：出題（3x3 + 枠上枠下 + 右リール番号） ---------- */

function renderStage(container, S) {
  container.innerHTML = '';
  const grid = document.createElement('div');
  grid.className = 'stage-grid';

  for (const rd of ROW_DEFS) {
    for (const reel of REEL_NAMES) {
      const num = S[reel] + rd.offset;
      const symbolName = symbolAt(reel, num);
      const cell = document.createElement('div');
      cell.className = 'stage-cell stage-cell--' + rd.mode;
      const img = document.createElement('img');
      img.src = symbolImages[symbolName].src;
      img.alt = symbolName;
      cell.appendChild(img);
      grid.appendChild(cell);
    }

    const numCell = document.createElement('div');
    numCell.className = 'stage-number-cell';
    if (rd.mode === 'full') {
      const badge = document.createElement('span');
      badge.className = 'number-badge';
      badge.textContent = String(wrapNum(S.right + rd.offset));
      numCell.appendChild(badge);
    }
    grid.appendChild(numCell);
  }

  container.appendChild(grid);
}

/* ---------- 描画：選択肢（仕様書 第4章）----------
 * 基準は受付開始ライン（X）。A_i = (P_i − X_i) mod 21 + o_i を
 * buildChoices() で choice.layout として計算済み。
 * 表示範囲は全難易度共通でminA〜maxA（下端をA=0で固定する必要はない。
 * applyShiftsWithFlipにより常に21コマ以内に収まる）。
 *
 * 全難易度共通：7以外の図柄は描かず、各リールの対象色の7（A_i行）だけを
 * 描く。それ以外の行は空セル。格子線は表示範囲の全行に引く。
 */

function renderChoiceStrip(container, choice) {
  const layout = choice.layout;
  const sevenSymbol = choice.color === 'pink' ? 'pink7' : 'white7';
  const top = layout.maxA;
  const bottom = layout.minA;
  const rows = top - bottom + 1;

  const grid = document.createElement('div');
  grid.className = 'choice-strip';
  grid.style.gridTemplateRows = 'repeat(' + rows + ', auto)';

  for (let j = 0; j < rows; j++) {
    const a = top - j;
    for (const reel of REEL_NAMES) {
      const slot = document.createElement('div');
      slot.className = 'choice-slot';
      if (layout.A[reel] === a) {
        const img = document.createElement('img');
        img.className = 'choice-symbol';
        img.src = symbolImages[sevenSymbol].src;
        img.alt = sevenSymbol;
        slot.appendChild(img);
      }
      grid.appendChild(slot);
    }
  }

  container.innerHTML = '';
  container.appendChild(grid);
}

// A（各リールの受付ラインからの行数）からminA/maxAを求め、renderChoiceStrip()に
// そのまま渡せる最小限のlayoutを組み立てる（振り返り画面：記録済みのAだけから
// 「答えた時と同じ表示」を再現するために使う）。
function layoutFromA(A) {
  return {
    A,
    minA: Math.min(A.left, A.middle, A.right),
    maxA: Math.max(A.left, A.middle, A.right),
  };
}

/* ---------- 描画：振り返り画面の「正解」側（21コマ全表示） ----------
 * 下端を受付ライン（A=0）に固定し、21コマ分（0〜20）すべてを表示する。
 * 7以外も含めてリール配列どおりの図柄を描く（判定ロジックは使わない、表示のみ）。
 * 正解の形（isCorrectForm）は常にo_i=0なので、refX=Xのまま。 */
function renderFullReelStrip(container, X) {
  const rows = 21;
  const grid = document.createElement('div');
  grid.className = 'choice-strip';
  grid.style.gridTemplateRows = 'repeat(' + rows + ', auto)';

  for (let j = 0; j < rows; j++) {
    const a = 20 - j; // 上端20〜下端0（受付ライン）
    for (const reel of REEL_NAMES) {
      const slot = document.createElement('div');
      slot.className = 'choice-slot';
      const symbolName = symbolAt(reel, X[reel] + a);
      const img = document.createElement('img');
      img.className = 'choice-symbol';
      img.src = symbolImages[symbolName].src;
      img.alt = symbolName;
      slot.appendChild(img);
      grid.appendChild(slot);
    }
  }

  container.innerHTML = '';
  container.appendChild(grid);
}

/* ---------- 出題の組み立て・UI ---------- */

let advanceTimer = null;

function newQuestion() {
  if (advanceTimer) {
    clearTimeout(advanceTimer);
    advanceTimer = null;
  }

  const diffKey = currentDifficulty;
  lastEasyNormalDebug = null; // 易・並以外、またtieでは使わない（stale表示防止）
  const S = generateStops(diffKey);
  const judge = judgeQuestion(S);
  const choices = diffKey === 'beginner' ? buildBeginnerChoices(judge) : buildChoices(judge, diffKey);
  currentQuestion = {
    diffKey, S, choices,
    timing: judge.timing,
    pinkCalc: judge.pinkCalc,
    whiteCalc: judge.whiteCalc,
    correctColors: judge.correctColors,
  };

  renderStage(document.getElementById('stage'), S);
  renderChoices(document.getElementById('choices'), choices, diffKey);
  clearResult();

  if (debugMode) renderDebugPanel(currentQuestion);
}

function renderChoices(container, choices, diffKey) {
  container.innerHTML = '';
  container.classList.remove('answered');
  container.classList.toggle('choices-2', choices.length === 2);
  choices.forEach((choice) => {
    const cell = document.createElement('div');
    cell.className = 'choice-cell';
    renderChoiceStrip(cell, choice);
    cell.addEventListener('click', () => onChoiceClick(choice));
    choice._cell = cell;
    container.appendChild(cell);
  });
}

function onChoiceClick(choice) {
  const container = document.getElementById('choices');
  if (container.classList.contains('answered')) return;
  container.classList.add('answered');

  currentQuestion.choices.forEach((ch) => {
    if (ch.isCorrect) ch._cell.classList.add('correct');
  });
  if (!choice.isCorrect) choice._cell.classList.add('wrong');

  showResult(choice.isCorrect);
  playJudgeSe(choice.isCorrect ? 'seikai' : 'huseikai');

  if (gamePhase === 'playing') {
    if (choice.isCorrect) correctCount++; else wrongCount++;
    updateCountsDisplay();
    pauseTimer(); // 次の問題に進むまでの1秒間はタイマーも止める
    records.push({
      S: { ...currentQuestion.S },
      choices: currentQuestion.choices.map((c) => ({
        color: c.color,
        isCorrectForm: c.isCorrectForm,
        A: { ...c.layout.A },
        isCorrect: c.isCorrect,
      })),
      pickedIndex: currentQuestion.choices.indexOf(choice),
      wasCorrect: choice.isCorrect,
    });
  }

  advanceTimer = setTimeout(() => {
    advanceTimer = null;
    resumeTimer();
    // 時間切れ・中断でフェーズが変わっていたら次の問題は出さない
    if (gamePhase === 'playing' || gamePhase === 'preview') {
      newQuestion();
    }
  }, 1000);
}

function showResult(isCorrect) {
  const el = document.getElementById('resultMessage');
  el.textContent = isCorrect ? '正解！' : '不正解';
  el.className = 'result-message ' + (isCorrect ? 'correct' : 'wrong');
}

function clearResult() {
  const el = document.getElementById('resultMessage');
  el.textContent = '';
  el.className = 'result-message';
}

/* ---------- 画面フェーズ・タイマー制御 ---------- */

function setPhase(newPhase) {
  gamePhase = newPhase;
  const isResult = newPhase === 'result';
  const isReview = newPhase === 'review';
  const isRanking = newPhase === 'ranking';
  const isOverlayScreen = isResult || isReview || isRanking;

  // .stage-wrap / .choices-wrap は display:flex 等をCSSで明示しているため、
  // hidden属性ではなくインラインstyleで確実に切り替える。
  document.querySelector('.stage-wrap').style.display = isOverlayScreen ? 'none' : '';
  document.querySelector('.choices-wrap').style.display = isOverlayScreen ? 'none' : '';
  document.getElementById('resultMessage').hidden = isOverlayScreen;
  document.getElementById('resultScreen').hidden = !isResult;
  document.getElementById('reviewScreen').hidden = !isReview;
  document.getElementById('rankingScreen').hidden = !isRanking;
  const showGameChrome = newPhase === 'playing' || newPhase === 'ending';
  document.getElementById('timerDisplay').hidden = !showGameChrome;
  document.getElementById('gameControls').hidden = !showGameChrome;
}

// 27:55（秒:1/100秒）形式で表示する。90秒が廃止され最大60秒のため分の桁は不要。
// 1/100秒まで滑らかに更新するため setInterval ではなく requestAnimationFrame を使う。
function updateTimerDisplay(remainingMs) {
  const totalCenti = Math.floor(remainingMs / 10);
  const cc = totalCenti % 100;
  const ss = Math.floor(totalCenti / 100); // 最大60（ゲーム開始直後の一瞬のみ）
  document.getElementById('timerSec').textContent = String(ss).padStart(2, '0');
  document.getElementById('timerCenti').textContent = String(cc).padStart(2, '0');
}

function updateCountsDisplay() {
  document.getElementById('correctCountValue').textContent = String(correctCount);
  document.getElementById('wrongCountValue').textContent = String(wrongCount);
}

// 一時停止中は「経過時間」が増えないよう、現在停止中の経過ぶんを差し引いて計算する。
// これにより remainingMs は停止直前の値のまま完全に固定される（1/100秒の桁も動かない）。
function timerElapsedMs(now) {
  let elapsed = (now - timerStartMs) - timerPausedTotalMs;
  if (timerPauseStartedAt !== null) {
    elapsed -= (now - timerPauseStartedAt);
  }
  return elapsed;
}

function timerRemainingMs(now) {
  return timerTotalMs - timerElapsedMs(now);
}

function pauseTimer() {
  if (timerPauseStartedAt === null) {
    timerPauseStartedAt = performance.now();
  }
}

function resumeTimer() {
  if (timerPauseStartedAt !== null) {
    timerPausedTotalMs += performance.now() - timerPauseStartedAt;
    timerPauseStartedAt = null;
  }
}

function timerTick(now) {
  const remainingMs = timerRemainingMs(now);

  // end.wav：残り0.00秒（時間切れの瞬間）に1回だけ再生を開始する
  if (!endSePlayed && remainingMs <= 0) {
    endSePlayed = true;
    playEndSe();
  }

  if (remainingMs <= 0) {
    updateTimerDisplay(0);
    timerRafId = null;
    endGame();
    return;
  }
  updateTimerDisplay(remainingMs);
  timerRafId = requestAnimationFrame(timerTick);
}

function stopTimers() {
  if (timerRafId) {
    cancelAnimationFrame(timerRafId);
    timerRafId = null;
  }
  if (advanceTimer) {
    clearTimeout(advanceTimer);
    advanceTimer = null;
  }
  if (endingTimeoutId) {
    clearTimeout(endingTimeoutId);
    endingTimeoutId = null;
  }
  timerPauseStartedAt = null;
}

function startGame() {
  stopTimers();
  correctCount = 0;
  wrongCount = 0;
  records = [];
  endSePlayed = false;
  updateCountsDisplay();
  unlockAndPlayBgm(); // ユーザーのタップ（このクリック）でBGM・SEの再生権を取得する
  setPhase('playing');
  timerTotalMs = currentTimeLimit * 1000;
  timerStartMs = performance.now();
  timerPausedTotalMs = 0;
  timerPauseStartedAt = null;
  updateTimerDisplay(timerTotalMs);
  timerRafId = requestAnimationFrame(timerTick);
  newQuestion();
}

// 時間切れ：3秒静止してからリザルトへ（仕様書 第6章）。
// end.wavは止めない＝鳴り終わるまで再生を続ける。BGMはリザルト表示時に止める。
function endGame() {
  setPhase('ending');
  if (advanceTimer) {
    clearTimeout(advanceTimer);
    advanceTimer = null;
  }
  document.getElementById('choices').classList.add('answered');
  endingTimeoutId = setTimeout(() => {
    endingTimeoutId = null;
    renderGameResult();
  }, 3000);
}

// 中断：即リザルトへ（本番ではタイトルへ戻る想定）
function abortGame() {
  stopTimers();
  renderGameResult();
}

function renderGameResult() {
  stopBgm();
  setPhase('result');
  const score = correctCount - wrongCount;
  document.getElementById('resultScore').textContent = String(score);
  document.getElementById('resultCorrect').textContent = String(correctCount);
  document.getElementById('resultWrong').textContent = String(wrongCount);
  document.getElementById('resultDiffLabel').textContent = DIFFICULTIES[currentDifficulty].label;
  document.getElementById('resultTimeLabel').textContent = String(currentTimeLimit);
  // 1問も回答せず終わった場合（即中断など）は振り返る記録が無いのでボタンを無効化する
  document.getElementById('reviewBtn').disabled = records.length === 0;

  resetRankEntryUI();
  // score<=0はランキング対象外（判定自体を行わない＝名前入力欄も出さない）
  if (score > 0) {
    checkRankInAndOfferEntry(currentDifficulty, currentTimeLimit, score, correctCount, wrongCount);
  }
}

function backToSetup() {
  stopTimers();
  stopBgm();
  setPhase('idle');
  document.getElementById('stage').innerHTML = '';
  document.getElementById('choices').innerHTML = '';
  document.getElementById('reviewStage').innerHTML = '';
  document.getElementById('reviewPickedCell').innerHTML = '';
  document.getElementById('reviewCorrectCell').innerHTML = '';
  clearResult();
  currentQuestion = null;
}

/* ---------- 振り返り画面（リザルトの「答え合わせ」から遷移） ----------
 * records（第6章：1問ごとの出題・回答記録）を1問ずつ表示する。判定ロジックは
 * 使わず、記録済みの値とcomputeTiming(S)（表示用の再計算。判定結果には影響しない）
 * だけで「出題」「あなたの回答」「正解」を再現する。 */

function openReview() {
  if (records.length === 0) return; // 記録が無ければ何もしない（reviewBtnはdisabled済み）
  reviewIndex = 0;
  setPhase('review');
  renderReviewQuestion();
}

function renderReviewQuestion() {
  const rec = records[reviewIndex];
  document.getElementById('reviewIndexLabel').textContent = String(reviewIndex + 1);
  document.getElementById('reviewTotalLabel').textContent = String(records.length);

  renderStage(document.getElementById('reviewStage'), rec.S);

  const pickedChoice = rec.choices[rec.pickedIndex];
  // 正解表示は、答えが正解だった場合は「実際に選んだ色」をそのまま使う
  // （tie＝両色正解のとき、選んだのと違う色を「正解」として出すと紛らわしいため）。
  // 誤答だった場合のみ、記録の中から「正しい形かつ正解」の選択肢を探す。
  const correctChoice = pickedChoice.isCorrect
    ? pickedChoice
    : (rec.choices.find((c) => c.isCorrectForm && c.isCorrect) || pickedChoice);

  const pickedCellEl = document.getElementById('reviewPickedCell');
  pickedCellEl.classList.remove('correct', 'wrong');
  pickedCellEl.classList.add(rec.wasCorrect ? 'correct' : 'wrong');
  renderChoiceStrip(pickedCellEl, { color: pickedChoice.color, layout: layoutFromA(pickedChoice.A) });
  document.getElementById('reviewPickedLabel').textContent = 'あなたの回答（' + colorLabel(pickedChoice.color) + '）';

  const correctCellEl = document.getElementById('reviewCorrectCell');
  correctCellEl.classList.remove('correct', 'wrong');
  correctCellEl.classList.add('correct');
  const X = computeTiming(rec.S).X; // 表示専用の再計算（判定ロジックには使わない）
  renderFullReelStrip(correctCellEl, X);
  document.getElementById('reviewCorrectLabel').textContent = '正解（' + colorLabel(correctChoice.color) + '）';

  const judgeEl = document.getElementById('reviewJudge');
  judgeEl.textContent = rec.wasCorrect ? '正解' : '不正解';
  judgeEl.className = 'review-judge ' + (rec.wasCorrect ? 'correct' : 'wrong');

  document.getElementById('reviewPrevBtn').disabled = reviewIndex === 0;
  document.getElementById('reviewNextBtn').disabled = reviewIndex === records.length - 1;
}

function reviewGoPrev() {
  if (reviewIndex <= 0) return;
  reviewIndex--;
  renderReviewQuestion();
}

function reviewGoNext() {
  if (reviewIndex >= records.length - 1) return;
  reviewIndex++;
  renderReviewQuestion();
}

function backToResultFromReview() {
  setPhase('result');
}

/* ---------- ランキング：Supabase REST通信 ----------
 * supabase-jsは使わずfetchで直接叩く（CDN読み込みを増やさないため）。
 * anon keyはブラウザ埋め込み前提の公開キー。Supabase Authは使わない。 */

function supabaseHeaders(isWrite) {
  const headers = {
    apikey: SUPABASE_ANON_KEY,
    Authorization: 'Bearer ' + SUPABASE_ANON_KEY,
  };
  if (isWrite) {
    headers['Content-Type'] = 'application/json';
    headers['Prefer'] = 'return=minimal';
  }
  return headers;
}

// difficulty/time_limitの板の上位RANKING_TOP_N件を取得する
// （score降順、同スコアはcreated_at昇順＝先に記録した方が上位）。
async function fetchTopScores(difficulty, timeLimit, selectFields) {
  const params = new URLSearchParams({
    select: selectFields,
    difficulty: 'eq.' + difficulty,
    time_limit: 'eq.' + timeLimit,
    order: 'score.desc,created_at.asc',
    limit: String(RANKING_TOP_N),
  });
  const res = await fetch(SCORES_URL + '?' + params.toString(), {
    headers: supabaseHeaders(false),
  });
  if (!res.ok) throw new Error('ランキングの取得に失敗しました（status ' + res.status + '）');
  return res.json();
}

// 送信前に「その難易度・時間の上位RANKING_TOP_N位以内に入るか」を判定する。
// 現在の登録が20件未満なら常にランクイン。20件埋まっていれば、20位の点数を
// 上回っている必要がある（同点の場合は既存の記録の方がcreated_at昇順で先に
// 並ぶため、同点では入れ替われない＝ランクインとしない）。
async function checkRankIn(difficulty, timeLimit, score) {
  const rows = await fetchTopScores(difficulty, timeLimit, 'score');
  if (rows.length < RANKING_TOP_N) return true;
  const lowestScore = rows[rows.length - 1].score;
  return score > lowestScore;
}

async function submitScore(entry) {
  const res = await fetch(SCORES_URL, {
    method: 'POST',
    headers: supabaseHeaders(true),
    body: JSON.stringify(entry),
  });
  if (!res.ok) throw new Error('登録に失敗しました（status ' + res.status + '）');
}

/* ---------- ランキング：リザルト画面（ランクイン判定・名前登録） ---------- */

function resetRankEntryUI() {
  pendingRankEntry = null;
  rankSubmitted = false;

  const note = document.getElementById('rankCheckNote');
  note.hidden = true;
  note.textContent = '';

  document.getElementById('rankEntry').hidden = true;

  const nameInput = document.getElementById('rankNameInput');
  nameInput.value = '';
  nameInput.disabled = false;

  const submitBtn = document.getElementById('rankSubmitBtn');
  submitBtn.disabled = false;
  submitBtn.textContent = '登録';

  const statusEl = document.getElementById('rankEntryStatus');
  statusEl.textContent = '';
  statusEl.className = 'rank-entry-status';
}

// リザルト表示のたびに呼ぶ：送信前にSELECTでランクイン（上位RANKING_TOP_N位以内）を
// 判定し、入っていれば名前入力欄を出す。通信に失敗した場合は正しく判定できないため
// 入力欄は出さず、小さくメッセージだけ出す（ゲーム本体・リザルトの他の操作には
// 影響しない＝Supabaseに繋がらなくてもゲームは通常どおり遊べる）。
async function checkRankInAndOfferEntry(difficulty, timeLimit, score, correct, wrong) {
  try {
    const eligible = await checkRankIn(difficulty, timeLimit, score);
    if (gamePhase !== 'result') return; // 判定中に画面が切り替わっていたら反映しない
    if (eligible) {
      pendingRankEntry = { difficulty, time_limit: timeLimit, score, correct, wrong };
      document.getElementById('rankEntry').hidden = false;
    }
  } catch (err) {
    console.error('ランクイン判定に失敗しました（ランキング機能のみに影響）', err);
    if (gamePhase !== 'result') return;
    const note = document.getElementById('rankCheckNote');
    note.textContent = 'ランキングの確認に失敗しました（通信環境をご確認ください）';
    note.hidden = false;
  }
}

// 前後の空白を除いた長さが1〜12文字であることを確認する。範囲外はnull（送信しない）。
function normalizeRankName(raw) {
  const trimmed = raw.trim();
  if (trimmed.length === 0 || trimmed.length > 12) return null;
  return trimmed;
}

async function submitRankEntry() {
  if (rankSubmitted || !pendingRankEntry) return;

  const nameInput = document.getElementById('rankNameInput');
  const statusEl = document.getElementById('rankEntryStatus');
  const name = normalizeRankName(nameInput.value);
  if (!name) {
    statusEl.textContent = '名前を入力してください（1〜12文字）';
    statusEl.className = 'rank-entry-status error';
    return;
  }

  const submitBtn = document.getElementById('rankSubmitBtn');
  submitBtn.disabled = true;
  nameInput.disabled = true;
  statusEl.textContent = '送信中…';
  statusEl.className = 'rank-entry-status';

  const entry = { ...pendingRankEntry, name };
  try {
    await submitScore(entry);
    rankSubmitted = true;
    lastSubmittedEntry = entry; // ランキング画面で自分の行を目立たせるために保持
    statusEl.textContent = '登録しました';
    statusEl.className = 'rank-entry-status success';
    submitBtn.textContent = '登録済み';
  } catch (err) {
    console.error('スコアの登録に失敗しました（ランキング機能のみに影響）', err);
    statusEl.textContent = '登録に失敗しました。通信環境をご確認のうえもう一度お試しください';
    statusEl.className = 'rank-entry-status error';
    submitBtn.disabled = false;
    nameInput.disabled = false;
  }
}

/* ---------- ランキング：ランキング画面 ---------- */

function findRankingBoard(diff, time) {
  return RANKING_BOARDS.find((b) => b.diff === diff && b.time === time) || RANKING_BOARDS[0];
}

function setupRankingBoardButtons() {
  const container = document.getElementById('rankingBoardButtons');
  RANKING_BOARDS.forEach((board) => {
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'ranking-board-btn';
    btn.textContent = board.label;
    btn.dataset.diff = board.diff;
    btn.dataset.time = String(board.time);
    btn.addEventListener('click', () => loadRankingBoard(board.diff, board.time));
    container.appendChild(btn);
  });
}

function updateRankingBoardButtonsActive() {
  document.querySelectorAll('.ranking-board-btn').forEach((btn) => {
    const isActive = !!currentRankingBoard &&
      btn.dataset.diff === currentRankingBoard.diff &&
      Number(btn.dataset.time) === currentRankingBoard.time;
    btn.classList.toggle('active', isActive);
  });
}

// リザルトの「ランキングを見る」から開く：初期表示は直前にプレイした難易度・時間の板。
function openRankingScreen() {
  setPhase('ranking');
  const board = findRankingBoard(currentDifficulty, currentTimeLimit);
  loadRankingBoard(board.diff, board.time);
}

function backToResultFromRanking() {
  setPhase('result');
}

async function loadRankingBoard(diff, time) {
  currentRankingBoard = { diff, time };
  updateRankingBoardButtonsActive();

  const bodyEl = document.getElementById('rankingBody');
  bodyEl.innerHTML = '';
  const loading = document.createElement('p');
  loading.className = 'ranking-status';
  loading.textContent = '読み込み中…';
  bodyEl.appendChild(loading);

  const seq = ++rankingRequestSeq;
  try {
    const rows = await fetchTopScores(diff, time, 'name,score,correct,wrong,created_at');
    if (seq !== rankingRequestSeq) return; // 途中で別の板に切り替えられていたら破棄
    renderRankingRows(bodyEl, rows, diff, time);
  } catch (err) {
    if (seq !== rankingRequestSeq) return;
    console.error('ランキングの取得に失敗しました', err);
    bodyEl.innerHTML = '';
    const errorEl = document.createElement('p');
    errorEl.className = 'ranking-status ranking-error';
    errorEl.textContent = 'ランキングの取得に失敗しました。通信環境をご確認のうえもう一度お試しください。';
    bodyEl.appendChild(errorEl);
  }
}

// 送信データを保持していないので、直近に自分が登録した1件（lastSubmittedEntry）と
// name/score/correct/wrongが一致する行を「自分の行」とみなして目立たせる
// （POSTはPrefer: return=minimalのため挿入行のidが返らず、他に照合手段がない）。
function renderRankingRows(container, rows, diff, time) {
  container.innerHTML = '';
  if (rows.length === 0) {
    const empty = document.createElement('p');
    empty.className = 'ranking-status';
    empty.textContent = 'まだ記録がありません';
    container.appendChild(empty);
    return;
  }

  const table = document.createElement('table');
  table.className = 'ranking-table';

  const thead = document.createElement('thead');
  const headRow = document.createElement('tr');
  ['順位', '名前', 'スコア', '正解', '誤答'].forEach((text) => {
    const th = document.createElement('th');
    th.textContent = text;
    headRow.appendChild(th);
  });
  thead.appendChild(headRow);
  table.appendChild(thead);

  const tbody = document.createElement('tbody');
  const isSelfBoard = !!lastSubmittedEntry &&
    lastSubmittedEntry.difficulty === diff &&
    lastSubmittedEntry.time_limit === time;

  rows.forEach((row, i) => {
    const tr = document.createElement('tr');
    const isSelf = isSelfBoard &&
      row.name === lastSubmittedEntry.name &&
      row.score === lastSubmittedEntry.score &&
      row.correct === lastSubmittedEntry.correct &&
      row.wrong === lastSubmittedEntry.wrong;
    if (isSelf) tr.classList.add('ranking-row-self');

    [String(i + 1), row.name, String(row.score), String(row.correct), String(row.wrong)].forEach((text) => {
      const td = document.createElement('td');
      td.textContent = text;
      tr.appendChild(td);
    });
    tbody.appendChild(tr);
  });
  table.appendChild(tbody);
  container.appendChild(table);
}

/* ---------- リザルト：Xシェア・画像保存 ---------- */

const SHARE_URL = 'https://gureslot.github.io/hanahana/quiz/';

function buildShareText() {
  const diffLabel = DIFFICULTIES[currentDifficulty].label;
  const lines = [
    'ハナハナ最速目押しクイズ',
    diffLabel + '／' + currentTimeLimit + '秒',
    'スコア：正解' + correctCount + '　誤答' + wrongCount,
    '',
    '#ハナハナ最速目押しクイズ',
    SHARE_URL,
  ];
  return lines.join('\n');
}

// X Web Intent。/intent/post はモバイルで無限ループになる事例があるため
// 必ず /intent/tweet を使う。
function shareToX() {
  const text = buildShareText();
  const intentUrl = 'https://twitter.com/intent/tweet?text=' + encodeURIComponent(text);
  window.open(intentUrl, '_blank', 'noopener,noreferrer');
}

// background-size:cover と同じロジックで画像を敷く（はみ出す分は中央基準でクロップ）。
function drawImageCover(ctx, img, x, y, w, h) {
  const scale = Math.max(w / img.width, h / img.height);
  const sw = w / scale;
  const sh = h / scale;
  const sx = (img.width - sw) / 2;
  const sy = (img.height - sh) / 2;
  ctx.drawImage(img, sx, sy, sw, sh, x, y, w, h);
}

// 幅を指定してアスペクト比を保ったまま中央揃えで描画し、実際に使った高さを返す。
function drawImageContainCentered(ctx, img, centerX, topY, targetW) {
  const targetH = targetW * (img.height / img.width);
  ctx.drawImage(img, centerX - targetW / 2, topY, targetW, targetH);
  return targetH;
}

const RESULT_CANVAS_W = 800;
const RESULT_CANVAS_H = 1050;

// リザルト画面（quiz.css .result-screen）と同じ構成要素を1枚のcanvasに合成する：
// 背景(titleBG.png)・ロゴ(title1/title2)・スコア台座(scoredaiza.png)＋スコア数字
// （台座の傾きに合わせたskewX(-36deg)もCSSと同じ角度で再現）・正解誤答・難易度秒数。
function buildResultCanvas() {
  const canvas = document.createElement('canvas');
  canvas.width = RESULT_CANVAS_W;
  canvas.height = RESULT_CANVAS_H;
  const ctx = canvas.getContext('2d');
  const centerX = canvas.width / 2;

  ctx.fillStyle = '#12131a';
  ctx.fillRect(0, 0, canvas.width, canvas.height);
  drawImageCover(ctx, resultImages.titleBG, 0, 0, canvas.width, canvas.height);

  let y = 60;
  y += drawImageContainCentered(ctx, resultImages.title1, centerX, y, canvas.width * 0.75);
  y += 16;
  y += drawImageContainCentered(ctx, resultImages.title2, centerX, y, canvas.width * 0.95);
  y += 40;

  const daizaW = canvas.width * 0.88;
  const daizaH = daizaW * (resultImages.scoredaiza.height / resultImages.scoredaiza.width);
  const daizaX = centerX - daizaW / 2;
  const daizaY = y;
  ctx.drawImage(resultImages.scoredaiza, daizaX, daizaY, daizaW, daizaH);

  const score = correctCount - wrongCount;
  ctx.save();
  ctx.translate(centerX, daizaY + daizaH / 2);
  ctx.transform(1, 0, Math.tan(-36 * Math.PI / 180), 1, 0, 0); // CSS skewX(-36deg)と同じ角度
  ctx.fillStyle = '#fff44d';
  ctx.font = 'bold ' + Math.round(daizaW * 0.13) + 'px system-ui, "Hiragino Kaku Gothic ProN", sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.shadowColor = 'rgba(0, 0, 0, 0.6)';
  ctx.shadowBlur = 8;
  ctx.shadowOffsetY = 4;
  ctx.fillText(String(score), 0, 0);
  ctx.restore();

  y = daizaY + daizaH + 40;
  ctx.shadowColor = 'rgba(0, 0, 0, 0.7)';
  ctx.shadowBlur = 6;
  ctx.shadowOffsetY = 2;
  ctx.fillStyle = '#fff';
  ctx.font = Math.round(canvas.width * 0.038) + 'px system-ui, "Hiragino Kaku Gothic ProN", sans-serif';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'alphabetic';
  ctx.fillText('正解 ' + correctCount + '　誤答 ' + wrongCount, centerX, y);

  y += 42;
  ctx.fillStyle = '#ddd';
  ctx.font = Math.round(canvas.width * 0.032) + 'px system-ui, "Hiragino Kaku Gothic ProN", sans-serif';
  ctx.fillText(DIFFICULTIES[currentDifficulty].label + '／' + currentTimeLimit + '秒', centerX, y);

  ctx.shadowColor = 'transparent';
  ctx.shadowBlur = 0;

  return canvas;
}

function canShareFile(file) {
  try {
    return !!(navigator.share && navigator.canShare && navigator.canShare({ files: [file] }));
  } catch (err) {
    return false;
  }
}

// 画像を保存：iOS Safariは<a download>が確実に効かないため、Web Share API
// （ファイル共有）が使える場合はまずそちらを使う（共有シートの「画像を保存」で
// 端末に保存できる）。使えない環境ではBlob URL＋<a download>にフォールバックする。
async function saveResultImage() {
  const canvas = buildResultCanvas();
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/png'));
  if (!blob) {
    console.error('リザルト画像の生成に失敗しました');
    return;
  }
  const fileName = 'hanahana-quiz-result.png';
  const file = new File([blob], fileName, { type: 'image/png' });

  if (canShareFile(file)) {
    try {
      await navigator.share({ files: [file], title: 'ハナハナ最速目押しクイズ' });
      return;
    } catch (err) {
      if (err && err.name === 'AbortError') return; // ユーザーがキャンセルした場合はそのまま終了
      console.error('画像の共有に失敗しました。ダウンロードにフォールバックします', err);
    }
  }

  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = fileName;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

// 確認用「1問だけ表示」：タイマーなしで出題と判定だけ見る（従来の動作）
function showPreviewQuestion() {
  stopTimers();
  setPhase('preview');
  newQuestion();
}

/* ---------- タイトル画面：難易度・時間のリングUI ----------
 * 各リングは { items, selected, displaySelected, rafId, cardEls, onChange,
 * dragStartX, dragAccum, dragged } を持つ状態オブジェクト。
 * items[i] = { key, imgSrc, alt, disabled }。
 * selected：確定している選択。0〜(枚数-1)に丸めない「累積する整数」で持つ
 * （左ドラッグ／▶で+1、右ドラッグ／◀で-1）。カードのインデックス解決や
 * 「今どれが選択中か」の判定は ringCanonicalIndex()（((selected%n)+n)%n）で
 * 行う。selectedを毎回0〜n-1に丸めてしまうと、たとえば2枚リングで
 * 0→1のときは常に+1、1→0のときは常に-1の回転にしかならず、ドラッグの
 * 向きが反映されない（左右どちらにドラッグしても同じ動きになる）。
 * displaySelected：表示用の実数。rAFでselected（累積値）へ滑らかに近づけ、
 * 毎フレームこの値からθ→x,y,scaleを計算し直す（＝位置のx,yを直線補間する
 * のではなく、角度を累積値のまま補間してから毎回x,y,scaleを算出する）。
 * カード自体は3D回転させない（画像=文字は常に正面向きのまま）。 */

const RING_ANIM_EASE = 0.25; // 毎フレーム、残り角度差のこの割合ぶん近づける
const RING_ANIM_EPS = 0.001; // これ未満になったら到達とみなしてrAFを止める

function ringCanonicalIndex(index, count) {
  return ((index % count) + count) % count;
}

function ringTheta(index, displaySelected, count) {
  // 度。0 = 正面（選択中）。baseAngle=-90°で正面をy軸上の「手前寄り」に置く。
  return (index - displaySelected) * (360 / count) - 90;
}

// 隣接カードへ進める（累積値のまま±1し、disabledな正準位置はスキップする）。
// 行き場が無ければ動かない（＝「回しても止まらない」の実装）。
function ringStepIndex(state, dir) {
  const n = state.items.length;
  let next = state.selected;
  for (let tries = 0; tries < n; tries++) {
    next += dir;
    if (!state.items[ringCanonicalIndex(next, n)].disabled) break;
  }
  return next;
}

// state.selectedの現在値から見て、canonicalTarget（0〜n-1）に最短距離で
// 到達する累積値を返す。ユーザー操作（advanceRing/ドラッグ）では使わない
// （そちらは向きをそのまま反映したいため）。初心者⇔他難易度の自動切替のような
// プログラム側の強制スナップだけに使う、最短経路での見た目にするための補助。
function ringNearestAccumulatorFor(state, canonicalTarget) {
  const n = state.items.length;
  const currentCanonical = ringCanonicalIndex(state.selected, n);
  let delta = ((canonicalTarget - currentCanonical) % n + n) % n;
  if (delta > n / 2) delta -= n;
  return state.selected + delta;
}

// 現在のdisplaySelected（実数）を使って全カードのtransform/filterを反映する。
function applyRingCardStyles(state) {
  const n = state.items.length;
  const selectedCanonical = ringCanonicalIndex(state.selected, n);
  state.cardEls.forEach((card, i) => {
    const rad = ringTheta(i, state.displaySelected, n) * Math.PI / 180;
    const rawX = RING_RX * Math.cos(rad);
    const rawY = RING_RY * Math.sin(rad);
    const skewedY = rawY - rawX * RING_TILT_SKEW; // 左下がり・右上がりの傾き
    const depth = (Math.sin(rad) + 1) / 2; // 0(手前)〜1(奥)
    const scale = RING_SCALE_MAX + depth * (RING_SCALE_MIN - RING_SCALE_MAX);

    card.style.transform =
      'translate(-50%, -50%) translate(' + rawX.toFixed(1) + 'px, ' + skewedY.toFixed(1) + 'px) scale(' + scale.toFixed(3) + ')';
    card.style.zIndex = String(Math.round(scale * 100));

    const item = state.items[i];
    const isSelected = i === selectedCanonical;
    let brightness = RING_BRIGHTNESS_UNSELECTED;
    if (item.disabled) brightness = RING_BRIGHTNESS_DISABLED;
    else if (isSelected) brightness = RING_BRIGHTNESS_SELECTED;

    card.style.filter = isSelected && !item.disabled
      ? 'brightness(' + brightness + ') drop-shadow(0 0 6px #fff44d) drop-shadow(0 0 10px #4a6cf7)'
      : 'brightness(' + brightness + ')';
  });
}

function stepRingAnimation(state) {
  // 累積値どうしの差をそのまま使う（最短経路への畳み込みはしない）。
  // これにより、ユーザーが回した向きどおりにカードが楕円上を移動する。
  const diff = state.selected - state.displaySelected;
  if (Math.abs(diff) < RING_ANIM_EPS) {
    state.displaySelected = state.selected;
    applyRingCardStyles(state);
    state.rafId = null;
    return;
  }
  state.displaySelected += diff * RING_ANIM_EASE;
  applyRingCardStyles(state);
  state.rafId = requestAnimationFrame(() => stepRingAnimation(state));
}

// selected（目標の累積値）へdisplaySelectedをrAFで近づけるアニメーションを
// （未開始なら）開始する。既にアニメーション中なら何もしない：ループ側が
// 毎フレーム最新のselectedを見るため、連続してselectedが変わっても自然に追従する。
function renderRing(state) {
  if (state.rafId) return;
  const diff = state.selected - state.displaySelected;
  if (Math.abs(diff) < RING_ANIM_EPS) {
    applyRingCardStyles(state);
    return;
  }
  state.rafId = requestAnimationFrame(() => stepRingAnimation(state));
}

// 矢印ボタン用：1枚ぶん進める。動けなければ何もしない（音も鳴らさない）。
function advanceRing(state, dir) {
  const n = state.items.length;
  const next = ringStepIndex(state, dir);
  if (ringCanonicalIndex(next, n) === ringCanonicalIndex(state.selected, n)) return;
  state.selected = next;
  renderRing(state);
  playRingTickSe();
  const canonicalIndex = ringCanonicalIndex(next, n);
  state.onChange(state.items[canonicalIndex].key, canonicalIndex);
}

// スワイプ：ドラッグ量をRING_STEP_PXぶん消費するたびに1枚ずつ進める
// （＝連続で回すとそのぶん複数回、正面に来るたびに鳴る）。
function setupRingDrag(trackEl, state) {
  let dragging = false;

  trackEl.addEventListener('pointerdown', (e) => {
    dragging = true;
    state.dragStartX = e.clientX;
    state.dragAccum = 0;
    state.dragged = false;
    trackEl.setPointerCapture(e.pointerId);
  });

  trackEl.addEventListener('pointermove', (e) => {
    if (!dragging) return;
    const n = state.items.length;
    const dx = e.clientX - state.dragStartX;
    state.dragStartX = e.clientX;
    state.dragAccum += dx;
    if (Math.abs(dx) > 3) state.dragged = true;

    while (Math.abs(state.dragAccum) >= RING_STEP_PX) {
      const sign = state.dragAccum > 0 ? 1 : -1;
      const dir = sign > 0 ? -1 : 1; // 右へドラッグ(正)なら前へ、左(負)なら次へ
      const next = ringStepIndex(state, dir);
      if (ringCanonicalIndex(next, n) === ringCanonicalIndex(state.selected, n)) {
        state.dragAccum = 0; // これ以上動けない（disabledでブロック）
        break;
      }
      state.selected = next;
      renderRing(state);
      playRingTickSe();
      const canonicalIndex = ringCanonicalIndex(next, n);
      state.onChange(state.items[canonicalIndex].key, canonicalIndex);
      state.dragAccum -= sign * RING_STEP_PX;
    }
  });

  const endDrag = () => {
    dragging = false;
    state.dragAccum = 0;
  };
  trackEl.addEventListener('pointerup', endDrag);
  trackEl.addEventListener('pointercancel', endDrag);
}

function createRing(trackEl, items, initialIndex, onChange) {
  const state = {
    items,
    selected: initialIndex,
    displaySelected: initialIndex, // 初期表示はアニメーションなしでそのまま反映
    rafId: null,
    cardEls: [],
    onChange,
    dragStartX: null,
    dragAccum: 0,
    dragged: false,
  };

  items.forEach((item) => {
    const card = document.createElement('div');
    card.className = 'ring-card';
    const img = document.createElement('img');
    img.src = item.imgSrc;
    img.alt = item.alt;
    card.appendChild(img);
    trackEl.appendChild(card);
    state.cardEls.push(card);
  });

  setupRingDrag(trackEl, state);
  applyRingCardStyles(state);
  return state;
}

// 初心者モードは30秒のみ：時間リングの60秒を選択不可にし、60秒が選ばれていたら
// 表示だけ30秒に移す（見た目はapplyRingCardStylesのRING_BRIGHTNESS_DISABLEDで
// さらに暗くなる）。lastManualTimeLimit（プレイヤーが最後に自分で選んだ値）は
// ここでは書き換えない：初心者を抜けたときにこの値へ戻すため。
// 初心者以外に切り替わった際、現在値がlastManualTimeLimitとズレていれば
// （＝初心者中に30へ強制されていたなら）記憶していた値に戻す。
// どちらもユーザーがドラッグしたわけではない自動スナップなので、
// ringNearestAccumulatorFor()で最短経路の見た目にする。
function applyTitleTimeConstraint() {
  if (!timeRingState) return;
  const isBeginner = currentDifficulty === 'beginner';
  const sixtyIndex = RING_TIME_VALUES.indexOf(60);
  const thirtyIndex = RING_TIME_VALUES.indexOf(30);
  timeRingState.items[sixtyIndex].disabled = isBeginner;

  if (isBeginner) {
    if (currentTimeLimit === 60) {
      currentTimeLimit = 30;
      timeRingState.selected = ringNearestAccumulatorFor(timeRingState, thirtyIndex);
    }
  } else if (currentTimeLimit !== lastManualTimeLimit) {
    currentTimeLimit = lastManualTimeLimit;
    const targetIndex = RING_TIME_VALUES.indexOf(lastManualTimeLimit);
    timeRingState.selected = ringNearestAccumulatorFor(timeRingState, targetIndex);
  }

  renderRing(timeRingState);
}

// タイトル画面：難易度・時間のリングを生成し、矢印ボタンを配線する。
function setupTitleRings() {
  const diffKeys = Object.keys(DIFFICULTIES);
  const diffItems = diffKeys.map((key) => ({
    key,
    imgSrc: 'images/' + DIFFICULTY_ICON[key] + '.png',
    alt: DIFFICULTIES[key].label,
    disabled: false,
  }));
  const timeItems = RING_TIME_VALUES.map((t) => ({
    key: String(t),
    imgSrc: 'images/' + t + '.png',
    alt: t + '秒',
    disabled: false,
  }));

  diffRingState = createRing(
    document.getElementById('diffRingTrack'),
    diffItems,
    Math.max(0, diffKeys.indexOf(currentDifficulty)),
    (key) => {
      currentDifficulty = key;
      applyTitleTimeConstraint();
    }
  );

  timeRingState = createRing(
    document.getElementById('timeRingTrack'),
    timeItems,
    Math.max(0, RING_TIME_VALUES.indexOf(currentTimeLimit)),
    (key) => {
      currentTimeLimit = parseInt(key, 10);
      lastManualTimeLimit = currentTimeLimit; // プレイヤーが自分で選んだ値として記憶する
    }
  );

  document.getElementById('diffRingLeft').addEventListener('click', () => advanceRing(diffRingState, -1));
  document.getElementById('diffRingRight').addEventListener('click', () => advanceRing(diffRingState, 1));
  document.getElementById('timeRingLeft').addEventListener('click', () => advanceRing(timeRingState, -1));
  document.getElementById('timeRingRight').addEventListener('click', () => advanceRing(timeRingState, 1));

  applyTitleTimeConstraint();
}

function showAppScreen() {
  document.getElementById('titleScreen').hidden = true;
  document.getElementById('appScreen').hidden = false;
}

// タイトルへ戻る：ゲーム画面をidleに戻したうえでタイトル画面を再表示する
function backToTitle() {
  backToSetup();
  document.getElementById('appScreen').hidden = true;
  document.getElementById('titleScreen').hidden = false;
}

function setupTitleScreen() {
  document.getElementById('titleStartBtn').addEventListener('click', () => {
    showAppScreen();
    startGame();
  });
  setupTitleRings();
  setupTitleMuteButton();
}

function setupUI() {
  document.getElementById('startBtn').addEventListener('click', startGame);
  document.getElementById('previewBtn').addEventListener('click', showPreviewQuestion);
  // もう一度：同じ難易度・時間で即再スタート
  document.getElementById('retryBtn').addEventListener('click', startGame);
  document.getElementById('backToTitleBtn').addEventListener('click', backToTitle);

  // リザルト：答え合わせ（振り返り画面へ）／Xシェア／画像を保存
  document.getElementById('reviewBtn').addEventListener('click', openReview);
  document.getElementById('shareBtn').addEventListener('click', shareToX);
  document.getElementById('saveImageBtn').addEventListener('click', saveResultImage);

  // 振り返り画面：前後送り・リザルトへ戻る
  document.getElementById('reviewPrevBtn').addEventListener('click', reviewGoPrev);
  document.getElementById('reviewNextBtn').addEventListener('click', reviewGoNext);
  document.getElementById('reviewBackBtn').addEventListener('click', backToResultFromReview);

  // リザルト：ランキング登録・ランキングを見る
  document.getElementById('rankSubmitBtn').addEventListener('click', submitRankEntry);
  document.getElementById('rankNameInput').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') submitRankEntry();
  });
  document.getElementById('viewRankingBtn').addEventListener('click', openRankingScreen);

  // ランキング画面：板の切り替えボタン・リザルトへ戻る
  setupRankingBoardButtons();
  document.getElementById('rankingBackBtn').addEventListener('click', backToResultFromRanking);

  // 中断ボタン：押したら即リザルトへ（ゲーム画面にのみ表示。仕様上の動作は現状のまま）
  document.getElementById('abortBtn').addEventListener('click', abortGame);

  // 確認用UI全体は ?debug=1 のときだけ表示する
  document.getElementById('devControls').hidden = !debugMode;

  setupSoundUI();
}

// ミュート状態の表示をまとめて更新する（確認用UIのBGM/SEボタンとタイトル画面の
// ミュートボタン、両方の見た目をここに集約する＝状態管理を二重にしない）。
function updateMuteUI() {
  const bgmMuteBtn = document.getElementById('bgmMuteBtn');
  const seMuteBtn = document.getElementById('seMuteBtn');
  if (bgmMuteBtn) {
    bgmMuteBtn.classList.toggle('active', bgmMuted);
    bgmMuteBtn.textContent = bgmMuted ? 'ミュート中' : 'ミュート';
  }
  if (seMuteBtn) {
    seMuteBtn.classList.toggle('active', seMuted);
    seMuteBtn.textContent = seMuted ? 'ミュート中' : 'ミュート';
  }
  updateTitleMuteUI();
}

// タイトル画面のミュートボタンはBGM・SEをまとめて1つの状態として表示する
// （bgmMutedを代表値として使う。トグルは常に両方を同じ値にするため一致している）。
function updateTitleMuteUI() {
  const icon = document.getElementById('titleMuteIcon');
  const label = document.getElementById('titleMuteLabel');
  const btn = document.getElementById('titleMuteBtn');
  if (!icon || !label) return;
  icon.src = bgmMuted ? 'images/mute_on.png' : 'images/mute_off.png';
  label.textContent = bgmMuted ? '音声オフ' : '音声オン';
  if (btn) btn.setAttribute('aria-pressed', String(bgmMuted));
}

function setupSoundUI() {
  const bgmSlider = document.getElementById('bgmVolumeSlider');
  const seSlider = document.getElementById('seVolumeSlider');
  const bgmMuteBtn = document.getElementById('bgmMuteBtn');
  const seMuteBtn = document.getElementById('seMuteBtn');

  bgmVolume = Number(bgmSlider.value) / 100;
  seVolume = Number(seSlider.value) / 100;

  bgmSlider.addEventListener('input', () => {
    bgmVolume = Number(bgmSlider.value) / 100;
    applyBgmVolume();
  });
  seSlider.addEventListener('input', () => {
    seVolume = Number(seSlider.value) / 100;
    applySeVolume();
  });
  bgmMuteBtn.addEventListener('click', () => {
    bgmMuted = !bgmMuted;
    applyBgmMute();
    updateMuteUI();
  });
  seMuteBtn.addEventListener('click', () => {
    seMuted = !seMuted;
    applySeMute();
    updateMuteUI();
  });

  applyBgmVolume();
  applyBgmMute();
  applySeVolume();
  applySeMute();
  updateMuteUI();
}

// タイトル画面左上のミュートボタン：BGM・SEをまとめてトグルする。
// ミュート解除（ON→OFF）のタップはSE要素の再生権を取得するきっかけにもする
// （STARTタップより先にここで解除されることがあるため）。
// 押した感触は:activeの代わりにpointerdown/up（pointercancel）で.pressedを付け外しする。
function setupTitleMuteButton() {
  const btn = document.getElementById('titleMuteBtn');
  if (!btn) return;

  btn.addEventListener('pointerdown', () => btn.classList.add('pressed'));
  btn.addEventListener('pointerup', () => btn.classList.remove('pressed'));
  btn.addEventListener('pointercancel', () => btn.classList.remove('pressed'));

  btn.addEventListener('click', () => {
    const wasMuted = bgmMuted;
    bgmMuted = !wasMuted;
    seMuted = bgmMuted;
    applyBgmMute();
    applySeMute();
    updateMuteUI();
    // ONにしたとき（wasMuted=true）だけ、再生権を取ってからtsu.wavを1回鳴らして
    // 音声経路が生きていることを示す。OFFにするときは鳴らさない。
    if (wasMuted) unlockSeElements().then(() => playRingTickSe());
  });
}

/* ---------- SE診断パネル（?debug=1。SEの遅れ調査用。挙動には影響しない） ---------- */

// 既存の#debugPanel（1問ごとに更新）はタイトル画面では非表示（#appScreen配下でhidden）
// のため、タイトル画面でのミュート/リング操作も観測できるよう、bodyに直接
// 独立した常時表示パネルを立てる。
function setupSeDebugPanel() {
  if (!debugMode) return;
  seDebugPanelEl = document.createElement('div');
  seDebugPanelEl.id = 'seDebugPanel';
  seDebugPanelEl.style.cssText =
    'position:fixed;left:0;top:0;z-index:99999;max-width:100vw;' +
    'background:rgba(0,0,0,0.85);color:#7fff7f;font:11px/1.5 monospace;' +
    'white-space:pre;padding:6px 10px;pointer-events:none;';
  document.body.appendChild(seDebugPanelEl);
  updateSeDebugPanel();
  setInterval(updateSeDebugPanel, 200);
}

function readyStateLabel(rs) {
  const NAMES = ['0 HAVE_NOTHING', '1 HAVE_METADATA', '2 HAVE_CURRENT_DATA', '3 HAVE_FUTURE_DATA', '4 HAVE_ENOUGH_DATA'];
  return NAMES[rs] !== undefined ? NAMES[rs] : String(rs);
}

function seElInfo(label, el) {
  if (!el) return label + ': 未生成';
  return label + ': readyState=' + readyStateLabel(el.readyState) + ' muted=' + el.muted + ' paused=' + el.paused;
}

function updateSeDebugPanel() {
  if (!seDebugPanelEl) return;
  const lines = [];
  lines.push('=== SE debug (?debug=1) ===');
  lines.push('seUnlocked: ' + seUnlocked);
  lines.push(seElInfo('seikai', seikaiSeEl));
  lines.push(seElInfo('huseikai', huseikaiSeEl));
  lines.push(seElInfo('end', endSeEl));
  if (tickSeEls.length === 0) {
    lines.push('tick: 未生成');
  } else {
    tickSeEls.forEach((el, i) => lines.push(seElInfo('tick[' + i + ']', el)));
  }
  lines.push(
    '直近再生: ' + (lastSeLatencyLabel || '(なし)') +
    '  play()→playing: ' + (lastSeLatencyMs === null ? '(なし)' : Math.round(lastSeLatencyMs) + 'ms')
  );
  seDebugPanelEl.textContent = lines.join('\n');
}

/* ---------- デバッグパネル（?debug=1） ---------- */

function renderDebugPanel(q) {
  const panel = document.getElementById('debugPanel');
  panel.hidden = false;

  const { S, timing, pinkCalc, whiteCalc, correctColors, choices, diffKey } = q;
  const fmt = (o) => '左' + o.left + ' 中' + o.middle + ' 右' + o.right;

  const lines = [];
  lines.push('=== デバッグ情報（難易度: ' + DIFFICULTIES[diffKey].label + '） ===');
  lines.push('S: ' + fmt(S));
  lines.push('d: ' + fmt(timing.d));
  lines.push('D: ' + timing.D);
  lines.push('X: ' + fmt(timing.X));
  lines.push('ピンクの所要: ' + fmt(pinkCalc.Dline) + '  max=' + pinkCalc.required);
  lines.push('白の所要: ' + fmt(whiteCalc.Dline) + '  max=' + whiteCalc.required);
  lines.push('正解色: ' + correctColors.map(colorLabel).join('・'));

  if (lastEasyNormalDebug) {
    const dbg = lastEasyNormalDebug;
    lines.push('');
    lines.push('=== 易・並：2択目（ダミー）の内訳 ===');
    lines.push('正解の高さ h_correct=' + dbg.hCorrect + '　型aの高さ h_dummyPlain=' + dbg.hDummyPlain);
    lines.push('R(目標の高さ関係)=' + (dbg.R === 'higher' ? '高い' : '低い') +
      (dbg.flippedR ? '　→　候補0件のため反転→' + (dbg.effectiveR === 'higher' ? '高い' : '低い') : ''));
    lines.push('C(ダミーの色)=' + (dbg.C === 'same' ? '正解と同色' : '正解と異色'));
    lines.push('採用した型=' + (dbg.type === 'a' ? 'a（遅い色・正しい形）' : 'b（ずらし）') +
      '　ダミーの高さ=' + dbg.hDummy);
  }

  lines.push('');
  lines.push('選択肢:');
  choices.forEach((c, i) => {
    const layout = c.layout;
    const shiftInfo = c.isCorrectForm
      ? 'ずれなし'
      : REEL_NAMES
          .filter((r) => layout.offsets[r] !== 0)
          .map((r) => REEL_LABEL[r] + (layout.offsets[r] > 0 ? '+' : '') + layout.offsets[r])
          .join('・');
    const aInfo = '  A=' + fmt(layout.A) + '  範囲' + layout.minA + '〜' + layout.maxA + '（' + layout.rows + 'コマ）';
    lines.push(
      '  ' + (i + 1) + ': ' + colorLabel(c.color) +
      ' / ' + (c.isCorrectForm ? '正しい形' : 'ずらし（' + shiftInfo + '）') +
      ' / 判定=' + (c.isCorrect ? '正解' : '不正解') + aInfo
    );
  });

  panel.textContent = lines.join('\n');
}

/* ---------- ダブルタップズームの抑止（JS版） ----------
 * html, body に touch-action: manipulation を指定しても、実機では画面下部
 * （はみ出してスクロールした先の領域など）でダブルタップズームが効いてしまう
 * ケースがあるため、JS側でも touchend を見て止める。
 * 直前のtouchendから300ms未満・かつタップ位置が前回から近い場合のみ
 * preventDefault()する（＝ダブルタップとみなせる場合だけ）。
 * ピンチズームは残す：touchend時点で他の指がまだ残っている（e.touches.length>0）
 * 場合や、直前に複数指が絡んでいた場合は対象外にする。 */
(function setupDoubleTapZoomGuard() {
  const DOUBLE_TAP_MS = 300;
  const DOUBLE_TAP_DIST_PX = 30; // これ以上位置が離れていたら別タップとみなす（誤爆防止）
  let lastTapTime = 0;
  let lastTapX = 0;
  let lastTapY = 0;

  document.addEventListener('touchend', (e) => {
    // 他の指がまだ画面に残っている（ピンチ操作の途中など）は対象外にする
    if (e.touches.length > 0) return;
    if (!e.changedTouches || e.changedTouches.length !== 1) return;

    const touch = e.changedTouches[0];
    const now = Date.now();
    const dx = touch.clientX - lastTapX;
    const dy = touch.clientY - lastTapY;
    const dist = Math.sqrt(dx * dx + dy * dy);

    if (lastTapTime && now - lastTapTime < DOUBLE_TAP_MS && dist < DOUBLE_TAP_DIST_PX) {
      e.preventDefault();
      lastTapTime = 0; // 3回連続タップ等で誤ってまた二重判定しないようリセット
      return;
    }

    lastTapTime = now;
    lastTapX = touch.clientX;
    lastTapY = touch.clientY;
  }, { passive: false });
})();

document.addEventListener('DOMContentLoaded', init);
