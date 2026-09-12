'use strict';

/* 選択肢版（quiz/quiz.js）から派生。画像・音・reels.jsonは複製せず../quiz/を
 * 相対参照する（二重管理を避けるため）。出目の生成・正解判定ロジック・タイマー・
 * 音・リングUI・ランキングの通信方式は選択肢版と同一（hanahana_quiz_ox_spec.md
 * 第1章の対応表を参照）。回答方式（○×1枚）とずらしの作り方（mod21で一周させる方式）
 * だけが選択肢版と異なる。 */

const REEL_NAMES = ['left', 'middle', 'right'];
const SYMBOL_NAMES = [
  'bell', 'replay', 'suika', 'cherry', 'hana',
  'pink7', 'white7', 'hibiscus', 'pinkBAR', 'whiteBAR',
];
const COLOR_KEY = { pink: 'pink7', white: 'white7' };
const REEL_LABEL = { left: '左', middle: '中', right: '右' };
const ASSET_BASE = '../quiz/';

const RESULT_IMAGE_NAMES = ['title1', 'title2', 'titleBG', 'scoredaiza'];

// 難易度定義。label/special/bgmは選択肢版と同じ。fixLeftは出目候補の生成条件
// （易は左中段4/14固定・並極は自由。選択肢版と同一）。shiftReelCount/shiftAmount/
// slowProbは○×版固有のずらしルール（仕様書 第3章）。
const DIFFICULTIES = {
  beginner: { label: '初心者', special: true, bgm: ASSET_BASE + 'sounds/quizBGM2.mp3' },
  easy: {
    label: '易', bgm: ASSET_BASE + 'sounds/quizBGM2.mp3',
    fixLeft: true, shiftReelCount: 1, shiftAmount: 3, slowProb: 0.5,
  },
  normal: {
    label: '並', bgm: ASSET_BASE + 'sounds/quizBGM.mp3',
    fixLeft: false, shiftReelCount: 3, shiftAmount: 3, slowProb: 0.5,
  },
  hard: {
    label: '極', bgm: ASSET_BASE + 'sounds/quizBGM.mp3',
    fixLeft: false, shiftReelCount: 2, shiftAmount: 2, slowProb: 1 / 3,
  },
};

const BEGINNER_SPREAD_MAX = 4;

const DIFFICULTY_ICON = { beginner: 'syo', easy: 'yasa', normal: 'nami', hard: 'kiwami' };
const RING_TIME_VALUES = [30, 60];

const RING_STEP_PX = 50;
const RING_RX = 70;
const RING_RY = 26;
const RING_TILT_SKEW = 0.35;
const RING_SCALE_MAX = 1.15;
const RING_SCALE_MIN = 0.62;
const RING_BRIGHTNESS_SELECTED = 1;
const RING_BRIGHTNESS_UNSELECTED = 0.55;
const RING_BRIGHTNESS_DISABLED = 0.25;

/* ---------- ランキング（Supabase REST API） ----------
 * 選択肢版と同じSupabaseプロジェクト・同じanon key。テーブルだけscores_oxに
 * 分ける（仕様書 第8章：選択肢版のscoresには手を入れない）。 */
const SUPABASE_URL = 'https://pyzgeadtvpjjgoqvihuw.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB5emdlYWR0dnBqamdvcXZpaHV3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODg1MjA3MDksImV4cCI6MjEwNDA5NjcwOX0.O8tBN6MtQy5_liMFJnGesJZLtzCB6CdkPBFMR1LmJOk';
const SCORES_URL = SUPABASE_URL + '/rest/v1/scores_ox';
const RANKING_TOP_N = 20;

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
  { offset: 2, mode: 'peekBottom' },
  { offset: 1, mode: 'full' },
  { offset: 0, mode: 'full' },
  { offset: -1, mode: 'full' },
  { offset: -2, mode: 'peekTop' },
];

let reelsData = null;
let sevens = null;
let symbolImages = {};
let resultImages = {};
let currentDifficulty = 'easy';
let currentQuestion = null;
let debugMode = false;
let forcedStops = null; // ?fix=左,中,右
let forcedAns = null;   // ?ans=o / ?ans=x
let forcedKind = null;  // ?kind=slow / ?kind=shift

/* ---------- ゲーム進行 ---------- */

let gamePhase = 'idle';
let currentTimeLimit = 30;
let lastManualTimeLimit = 30;
let timerStartMs = 0;
let timerTotalMs = 0;
let timerPausedTotalMs = 0;
let timerPauseStartedAt = null;
let timerRafId = null;
let endingTimeoutId = null;
let endSePlayed = false;
let correctCount = 0;
let wrongCount = 0;
let records = [];
let beginnerCandidates = [];
let easyCandidates = [];
let normalHardCandidates = [];
let reviewIndex = 0;
let diffRingState = null;
let timeRingState = null;

let pendingRankEntry = null;
let rankSubmitted = false;
let lastSubmittedEntry = null;
let currentRankingBoard = null;
let rankingRequestSeq = 0;

/* ---------- 音 ---------- */

let seikaiSeEl = null;
let huseikaiSeEl = null;
let endSeEl = null;
let seUnlocked = false;
let tickSeEls = [];
let tickSeIndex = 0;
const TICK_SE_POOL_SIZE = 4;

let lastSeLatencyMs = null;
let lastSeLatencyLabel = '';
let seDebugPanelEl = null;
let bgmEl = null;
let bgmVolume = 0.8;
let seVolume = 0.8;
let bgmMuted = true;
let seMuted = true;

function parseForcedStops() {
  const raw = new URLSearchParams(location.search).get('fix');
  if (!raw) return null;
  const parts = raw.split(',').map((s) => parseInt(s.trim(), 10));
  if (parts.length !== 3 || parts.some((n) => Number.isNaN(n))) return null;
  return { left: parts[0], middle: parts[1], right: parts[2] };
}

function parseForcedAns() {
  const raw = new URLSearchParams(location.search).get('ans');
  return raw === 'o' || raw === 'x' ? raw : null;
}

function parseForcedKind() {
  const raw = new URLSearchParams(location.search).get('kind');
  return raw === 'slow' || raw === 'shift' ? raw : null;
}

async function init() {
  try {
    debugMode = new URLSearchParams(location.search).get('debug') === '1';
    setupSeDebugPanel();
    forcedStops = parseForcedStops();
    forcedAns = parseForcedAns();
    forcedKind = parseForcedKind();
    const res = await fetch(ASSET_BASE + 'reels.json');
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
    img.onerror = () => reject(new Error('画像の読み込みに失敗: ' + ASSET_BASE + 'images/' + name + '.png'));
    img.src = ASSET_BASE + 'images/' + name + '.png';
  })));
}

function preloadResultImages() {
  return Promise.all(RESULT_IMAGE_NAMES.map((name) => new Promise((resolve, reject) => {
    const img = new Image();
    img.onload = () => {
      resultImages[name] = img;
      resolve();
    };
    img.onerror = () => reject(new Error('画像の読み込みに失敗: ' + ASSET_BASE + 'images/' + name + '.png'));
    img.src = ASSET_BASE + 'images/' + name + '.png';
  })));
}

/* ---------- 音の読み込み・再生（選択肢版と同一実装） ---------- */

function createSeAudio(src) {
  const el = new Audio(src);
  el.preload = 'auto';
  el.load();
  return el;
}

function preloadSounds() {
  seikaiSeEl = createSeAudio(ASSET_BASE + 'sounds/seikai.wav');
  huseikaiSeEl = createSeAudio(ASSET_BASE + 'sounds/huseikai.wav');
  endSeEl = createSeAudio(ASSET_BASE + 'sounds/end.wav');
  tickSeEls = [];
  for (let i = 0; i < TICK_SE_POOL_SIZE; i++) {
    tickSeEls.push(createSeAudio(ASSET_BASE + 'sounds/tsu.wav'));
  }
  applySeVolume();
  applySeMute();
}

function allSeEls() {
  return [seikaiSeEl, huseikaiSeEl, endSeEl, ...tickSeEls].filter(Boolean);
}

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

function unlockSeElementsOnFirstGesture() {
  unlockSeElements();
  window.removeEventListener('pointerdown', unlockSeElementsOnFirstGesture);
  window.removeEventListener('touchstart', unlockSeElementsOnFirstGesture);
  window.removeEventListener('keydown', unlockSeElementsOnFirstGesture);
}
window.addEventListener('pointerdown', unlockSeElementsOnFirstGesture);
window.addEventListener('touchstart', unlockSeElementsOnFirstGesture);
window.addEventListener('keydown', unlockSeElementsOnFirstGesture);

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

function playEndSe() {
  if (!endSeEl) return;
  endSeEl.currentTime = 0;
  trackSePlayLatency(endSeEl, 'end');
  endSeEl.play().catch((err) => console.error('SEの再生に失敗しました（無音のまま続行します）', err));
}

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

function applyBgmMute() {
  if (bgmEl) bgmEl.muted = bgmMuted;
}

function applySeVolume() {
  allSeEls().forEach((el) => { el.volume = seVolume; });
}

function applySeMute() {
  allSeEls().forEach((el) => { el.muted = seMuted; });
}

let currentBgmSrc = null; // 直近にbgmEl.srcへ設定した相対パス（endsWith比較は
  // "../"を含む相対パスだと解決後の絶対URLと一致しないため使えない。値そのもので比較する）

function unlockAndPlayBgm() {
  unlockSeElements();
  if (!bgmEl) return;
  const bgmSrc = DIFFICULTIES[currentDifficulty].bgm;
  if (bgmSrc && bgmSrc !== currentBgmSrc) {
    bgmEl.src = bgmSrc;
    currentBgmSrc = bgmSrc;
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

function wrapNum(n) {
  return mod21(n - 1) + 1;
}

function symbolAt(reel, num) {
  return reelsData[reel][wrapNum(num) - 1];
}

function colorLabel(color) {
  return color === 'pink' ? 'ピンク7' : '白7';
}

function oppositeColor(color) {
  return color === 'pink' ? 'white' : 'pink';
}

/* ---------- 出題生成・判定ロジック（選択肢版と同一。仕様書 第4章） ---------- */

function generateStops(diffKey) {
  if (forcedStops) return forcedStops;
  const pool = diffKey === 'beginner' ? beginnerCandidates
    : diffKey === 'easy' ? easyCandidates
    : normalHardCandidates;
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

/* ---------- ○×の抽選・ずらしの作り方（仕様書 第3章。選択肢版とは別物） ----------
 * ○:×=50:50。○は速い色の正しい形（同着なら2色からランダム）。
 * ×は「遅い色の正しい形」か「ずらし」のどちらか（難易度ごとの比率）。
 * 同着のときは遅い色が存在しないため×は必ずずらしにする。
 * ずらしは21で一周する（A_i = (本来のA_i + o_i) mod 21）。ずらしは回答画像の
 * 中だけの操作で、出目も受付ラインも動かさない。リールが21コマで一周している
 * のと同じく行番号も21で一周させるため、はみ出しの処理・符号選択は不要
 * （クランプ＝端で止めると、端にいる7が動かず正解の形と同一の画像が×として
 * 出てしまう事故が起きる。mod21方式では原理的に起こらない）。 */

function computeBaseA(X, color) {
  const P = sevens[COLOR_KEY[color]];
  const A = {};
  for (const r of REEL_NAMES) A[r] = mod21(P[r] - X[r]);
  return A;
}

function shuffleArray(arr) {
  for (let i = arr.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [arr[i], arr[j]] = [arr[j], arr[i]];
  }
}

// 難易度ごとに対象リールを選ぶ。易＝中・右のどちらか1つ、並＝3リール全部、
// 極＝3リールのうちランダムな2つ。対象外のリールは0のまま。
function chooseShiftReels(diffKey) {
  if (diffKey === 'easy') {
    return [Math.random() < 0.5 ? 'middle' : 'right'];
  }
  if (diffKey === 'normal') {
    return ['left', 'middle', 'right'];
  }
  const indices = [0, 1, 2];
  shuffleArray(indices);
  return indices.slice(0, 2).map((i) => REEL_NAMES[i]);
}

// 対象リール・符号（+/-）をリールごとに独立して抽選する（50:50）。
// ずらしは21で一周する（mod21）ため、はみ出しの処理・符号選択は不要。
function buildShiftOffsets(diffKey) {
  const diff = DIFFICULTIES[diffKey];
  const reels = chooseShiftReels(diffKey);
  const offsets = { left: 0, middle: 0, right: 0 };
  for (const r of reels) {
    const sign = Math.random() < 0.5 ? 1 : -1;
    offsets[r] = sign * diff.shiftAmount;
  }
  return offsets;
}

// 1問ぶんの回答画像を決める。戻り値：
// ans（正解の○/×）、kind（correct/slow/shift）、color（描画する色）、
// offsets（ずらし量。correct/slowは全て0）、A（実際に描く各列の行数）。
function decideAnswer(diffKey, judge, X) {
  const isTie = judge.correctColors.length === 2;
  const ans = forcedAns || (Math.random() < 0.5 ? 'o' : 'x');

  if (ans === 'o') {
    const color = isTie
      ? (Math.random() < 0.5 ? 'pink' : 'white')
      : judge.correctColors[0];
    return { ans, kind: 'correct', color, offsets: { left: 0, middle: 0, right: 0 }, A: computeBaseA(X, color) };
  }

  // ans === 'x'
  let kind;
  if (diffKey === 'beginner') {
    kind = 'slow'; // 初心者はずらしを使わない（DIFFICULTIES.beginnerにshiftAmount等が
    // 無いためforcedKindより優先する。?kind=shiftを渡してもここで無視する）
  } else if (forcedKind) {
    kind = forcedKind;
  } else if (isTie) {
    kind = 'shift'; // 同着では「遅い色」が存在しない
  } else {
    kind = Math.random() < DIFFICULTIES[diffKey].slowProb ? 'slow' : 'shift';
  }

  if (kind === 'slow') {
    const color = isTie
      ? (Math.random() < 0.5 ? 'pink' : 'white') // 同着でのslow強制指定（?kind用）はどちらかをランダムに
      : oppositeColor(judge.correctColors[0]);
    return { ans, kind, color, offsets: { left: 0, middle: 0, right: 0 }, A: computeBaseA(X, color) };
  }

  // shift：色はピンク・白からランダム（正解/不正解とは無関係）。
  // A_i = (本来のA_i + o_i) mod 21（21で一周。出目も受付ラインも動かさない、
  // 描く行だけを動かす）。
  const color = Math.random() < 0.5 ? 'pink' : 'white';
  const baseA = computeBaseA(X, color);
  const offsets = buildShiftOffsets(diffKey);
  const A = {};
  for (const r of REEL_NAMES) A[r] = mod21(baseA[r] + offsets[r]);
  return { ans, kind, color, offsets, A };
}

/* ---------- 描画：出題（3x3 + 枠上枠下 + 右リール番号）。選択肢版と同一 ---------- */

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

/* ---------- 描画：回答画像（仕様書 第3章）----------
 * 下端（0行目）＝受付ライン固定。高さは常に21行（max(A)に関係なく縮めない）。
 * 各列にその色の7がちょうど1つだけ入り、7以外の図柄は描かない。 */

function renderOxStrip(container, A, color) {
  const sevenSymbol = COLOR_KEY[color];
  const rows = 21;

  const grid = document.createElement('div');
  grid.className = 'ox-grid';

  for (let j = 0; j < rows; j++) {
    const a = (rows - 1) - j; // 上端20〜下端0（受付ライン）
    for (const reel of REEL_NAMES) {
      const slot = document.createElement('div');
      slot.className = 'ox-slot';
      if (A[reel] === a) {
        const img = document.createElement('img');
        img.className = 'ox-symbol';
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

/* ---------- 描画：振り返り画面「出題された画像」（○×版）----------
 * renderOxStripと見た目は同じ21行だが、choice-strip/choice-slotのクラスを使い、
 * .choice-cell（枠）の中に収めて選択肢版の振り返り画面と同じ見た目に揃える。 */

function renderReviewPresented(container, A, color) {
  const sevenSymbol = COLOR_KEY[color];
  const rows = 21;

  const grid = document.createElement('div');
  grid.className = 'choice-strip';
  grid.style.gridTemplateRows = 'repeat(' + rows + ', auto)';

  for (let j = 0; j < rows; j++) {
    const a = (rows - 1) - j;
    for (const reel of REEL_NAMES) {
      const slot = document.createElement('div');
      slot.className = 'choice-slot';
      if (A[reel] === a) {
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

/* ---------- 描画：振り返り画面「正解の形」（21コマ全表示） ----------
 * 下端を受付ライン（A=0）に固定し、21コマ分（0〜20）すべてを表示する。
 * 7以外も含めてリール配列どおりの図柄を描く（判定ロジックは使わない、表示のみ）。
 * 選択肢版のrenderFullReelStripと同一実装：Xそのものが実際のリール配列を
 * 指すため、色を問わず「本物の並び」がそのまま出る。 */

function renderFullReelStrip(container, X) {
  const rows = 21;
  const grid = document.createElement('div');
  grid.className = 'choice-strip';
  grid.style.gridTemplateRows = 'repeat(' + rows + ', auto)';

  for (let j = 0; j < rows; j++) {
    const a = 20 - j;
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
let oxAnswered = false;

function newQuestion() {
  if (advanceTimer) {
    clearTimeout(advanceTimer);
    advanceTimer = null;
  }

  const diffKey = currentDifficulty;
  const S = generateStops(diffKey);
  const judge = judgeQuestion(S);
  const decision = decideAnswer(diffKey, judge, judge.timing.X);
  currentQuestion = {
    diffKey, S,
    timing: judge.timing,
    pinkCalc: judge.pinkCalc,
    whiteCalc: judge.whiteCalc,
    correctColors: judge.correctColors,
    decision,
  };

  renderStage(document.getElementById('stage'), S);
  renderOxStrip(document.getElementById('oxGrid'), decision.A, decision.color);
  resetOxButtons();
  clearResult();

  if (debugMode) renderDebugPanel(currentQuestion);
}

function resetOxButtons() {
  oxAnswered = false;
  const btnO = document.getElementById('oxBtnO');
  const btnX = document.getElementById('oxBtnX');
  [btnO, btnX].forEach((btn) => {
    btn.disabled = false;
    btn.classList.remove('correct', 'wrong');
  });
  document.getElementById('oxGrid').classList.remove('correct', 'wrong');
}

function onOxAnswer(pickedAns) {
  if (oxAnswered) return;
  oxAnswered = true;

  const btnO = document.getElementById('oxBtnO');
  const btnX = document.getElementById('oxBtnX');
  btnO.disabled = true;
  btnX.disabled = true;

  const decision = currentQuestion.decision;
  const isCorrect = pickedAns === decision.ans;
  const correctBtn = decision.ans === 'o' ? btnO : btnX;
  const pickedBtn = pickedAns === 'o' ? btnO : btnX;
  correctBtn.classList.add('correct');
  if (!isCorrect) pickedBtn.classList.add('wrong');

  // 回答画像の枠も選択肢版と同じ色で正誤を示す（緑＝正解／赤＝不正解）
  document.getElementById('oxGrid').classList.add(isCorrect ? 'correct' : 'wrong');

  showResult(isCorrect);
  playJudgeSe(isCorrect ? 'seikai' : 'huseikai');

  if (gamePhase === 'playing') {
    if (isCorrect) correctCount++; else wrongCount++;
    updateCountsDisplay();
    pauseTimer();
    records.push({
      S: { ...currentQuestion.S },
      presented: { color: decision.color, kind: decision.kind, A: { ...decision.A } },
      ans: decision.ans,
      isTie: currentQuestion.correctColors.length === 2,
      pickedAns,
      wasCorrect: isCorrect,
    });
  }

  advanceTimer = setTimeout(() => {
    advanceTimer = null;
    resumeTimer();
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

  document.querySelector('.stage-wrap').style.display = isOverlayScreen ? 'none' : '';
  document.querySelector('.ox-answer-wrap').style.display = isOverlayScreen ? 'none' : '';
  document.getElementById('resultMessage').hidden = isOverlayScreen;
  document.getElementById('resultScreen').hidden = !isResult;
  document.getElementById('reviewScreen').hidden = !isReview;
  document.getElementById('rankingScreen').hidden = !isRanking;
  const showGameChrome = newPhase === 'playing' || newPhase === 'ending';
  document.getElementById('timerDisplay').hidden = !showGameChrome;
  document.getElementById('gameControls').hidden = !showGameChrome;
}

function updateTimerDisplay(remainingMs) {
  const totalCenti = Math.floor(remainingMs / 10);
  const cc = totalCenti % 100;
  const ss = Math.floor(totalCenti / 100);
  document.getElementById('timerSec').textContent = String(ss).padStart(2, '0');
  document.getElementById('timerCenti').textContent = String(cc).padStart(2, '0');
}

function updateCountsDisplay() {
  document.getElementById('correctCountValue').textContent = String(correctCount);
  document.getElementById('wrongCountValue').textContent = String(wrongCount);
}

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
  unlockAndPlayBgm();
  setPhase('playing');
  timerTotalMs = currentTimeLimit * 1000;
  timerStartMs = performance.now();
  timerPausedTotalMs = 0;
  timerPauseStartedAt = null;
  updateTimerDisplay(timerTotalMs);
  timerRafId = requestAnimationFrame(timerTick);
  newQuestion();
}

function endGame() {
  setPhase('ending');
  if (advanceTimer) {
    clearTimeout(advanceTimer);
    advanceTimer = null;
  }
  document.getElementById('oxBtnO').disabled = true;
  document.getElementById('oxBtnX').disabled = true;
  endingTimeoutId = setTimeout(() => {
    endingTimeoutId = null;
    renderGameResult();
  }, 3000);
}

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
  document.getElementById('reviewBtn').disabled = records.length === 0;

  resetRankEntryUI();
  if (score > 0) {
    checkRankInAndOfferEntry(currentDifficulty, currentTimeLimit, score, correctCount, wrongCount);
  }
}

function backToSetup() {
  stopTimers();
  stopBgm();
  setPhase('idle');
  document.getElementById('stage').innerHTML = '';
  document.getElementById('oxGrid').innerHTML = '';
  document.getElementById('reviewStage').innerHTML = '';
  document.getElementById('reviewPickedCell').innerHTML = '';
  document.getElementById('reviewCorrectCell').innerHTML = '';
  clearResult();
  currentQuestion = null;
}

/* ---------- 振り返り画面 ---------- */

function openReview() {
  if (records.length === 0) return;
  reviewIndex = 0;
  setPhase('review');
  renderReviewQuestion();
}

function renderReviewQuestion() {
  const rec = records[reviewIndex];
  document.getElementById('reviewIndexLabel').textContent = String(reviewIndex + 1);
  document.getElementById('reviewTotalLabel').textContent = String(records.length);

  renderStage(document.getElementById('reviewStage'), rec.S);

  const pickedCellEl = document.getElementById('reviewPickedCell');
  pickedCellEl.classList.remove('correct', 'wrong');
  pickedCellEl.classList.add(rec.wasCorrect ? 'correct' : 'wrong');
  renderReviewPresented(pickedCellEl, rec.presented.A, rec.presented.color);
  document.getElementById('reviewPickedLabel').textContent =
    '出題／あなたの回答：' + (rec.pickedAns === 'o' ? '○' : '×');

  const correctCellEl = document.getElementById('reviewCorrectCell');
  correctCellEl.classList.remove('correct', 'wrong');
  correctCellEl.classList.add('correct');
  const X = computeTiming(rec.S).X; // 表示専用の再計算（判定ロジックには使わない）
  renderFullReelStrip(correctCellEl, X);
  let correctLabel = '正解：' + (rec.ans === 'o' ? '○' : '×');
  if (rec.isTie) correctLabel += '（同着：どちらの色でも正解）';
  document.getElementById('reviewCorrectLabel').textContent = correctLabel;

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

/* ---------- ランキング：Supabase REST通信（選択肢版と同一実装、テーブルのみscores_ox） ---------- */

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

async function checkRankInAndOfferEntry(difficulty, timeLimit, score, correct, wrong) {
  try {
    const eligible = await checkRankIn(difficulty, timeLimit, score);
    if (gamePhase !== 'result') return;
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
    lastSubmittedEntry = entry;
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
    if (seq !== rankingRequestSeq) return;
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

const SHARE_URL = 'https://gureslot.github.io/hanahana/quiz-ox/';

function buildShareText() {
  const diffLabel = DIFFICULTIES[currentDifficulty].label;
  const lines = [
    'ハナハナ最速目押しクイズ ○×版',
    diffLabel + '／' + currentTimeLimit + '秒',
    'スコア：正解' + correctCount + '　誤答' + wrongCount,
    '',
    '#ハナハナ最速目押しクイズ',
    SHARE_URL,
  ];
  return lines.join('\n');
}

function shareToX() {
  const text = buildShareText();
  const intentUrl = 'https://twitter.com/intent/tweet?text=' + encodeURIComponent(text);
  window.open(intentUrl, '_blank', 'noopener,noreferrer');
}

function drawImageCover(ctx, img, x, y, w, h) {
  const scale = Math.max(w / img.width, h / img.height);
  const sw = w / scale;
  const sh = h / scale;
  const sx = (img.width - sw) / 2;
  const sy = (img.height - sh) / 2;
  ctx.drawImage(img, sx, sy, sw, sh, x, y, w, h);
}

function drawImageContainCentered(ctx, img, centerX, topY, targetW) {
  const targetH = targetW * (img.height / img.width);
  ctx.drawImage(img, centerX - targetW / 2, topY, targetW, targetH);
  return targetH;
}

const RESULT_CANVAS_W = 800;
const RESULT_CANVAS_H = 1050;

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
  ctx.transform(1, 0, Math.tan(-36 * Math.PI / 180), 1, 0, 0);
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

async function saveResultImage() {
  const canvas = buildResultCanvas();
  const blob = await new Promise((resolve) => canvas.toBlob(resolve, 'image/png'));
  if (!blob) {
    console.error('リザルト画像の生成に失敗しました');
    return;
  }
  const fileName = 'hanahana-quiz-ox-result.png';
  const file = new File([blob], fileName, { type: 'image/png' });

  if (canShareFile(file)) {
    try {
      await navigator.share({ files: [file], title: 'ハナハナ最速目押しクイズ ○×版' });
      return;
    } catch (err) {
      if (err && err.name === 'AbortError') return;
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

function showPreviewQuestion() {
  stopTimers();
  setPhase('preview');
  newQuestion();
}

/* ---------- タイトル画面：難易度・時間のリングUI（選択肢版と同一実装） ---------- */

const RING_ANIM_EASE = 0.25;
const RING_ANIM_EPS = 0.001;

function ringCanonicalIndex(index, count) {
  return ((index % count) + count) % count;
}

function ringTheta(index, displaySelected, count) {
  return (index - displaySelected) * (360 / count) - 90;
}

function ringStepIndex(state, dir) {
  const n = state.items.length;
  let next = state.selected;
  for (let tries = 0; tries < n; tries++) {
    next += dir;
    if (!state.items[ringCanonicalIndex(next, n)].disabled) break;
  }
  return next;
}

function ringNearestAccumulatorFor(state, canonicalTarget) {
  const n = state.items.length;
  const currentCanonical = ringCanonicalIndex(state.selected, n);
  let delta = ((canonicalTarget - currentCanonical) % n + n) % n;
  if (delta > n / 2) delta -= n;
  return state.selected + delta;
}

function applyRingCardStyles(state) {
  const n = state.items.length;
  const selectedCanonical = ringCanonicalIndex(state.selected, n);
  state.cardEls.forEach((card, i) => {
    const rad = ringTheta(i, state.displaySelected, n) * Math.PI / 180;
    const rawX = RING_RX * Math.cos(rad);
    const rawY = RING_RY * Math.sin(rad);
    const skewedY = rawY - rawX * RING_TILT_SKEW;
    const depth = (Math.sin(rad) + 1) / 2;
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

function renderRing(state) {
  if (state.rafId) return;
  const diff = state.selected - state.displaySelected;
  if (Math.abs(diff) < RING_ANIM_EPS) {
    applyRingCardStyles(state);
    return;
  }
  state.rafId = requestAnimationFrame(() => stepRingAnimation(state));
}

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
      const dir = sign > 0 ? -1 : 1;
      const next = ringStepIndex(state, dir);
      if (ringCanonicalIndex(next, n) === ringCanonicalIndex(state.selected, n)) {
        state.dragAccum = 0;
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
    displaySelected: initialIndex,
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

function setupTitleRings() {
  const diffKeys = Object.keys(DIFFICULTIES);
  const diffItems = diffKeys.map((key) => ({
    key,
    imgSrc: ASSET_BASE + 'images/' + DIFFICULTY_ICON[key] + '.png',
    alt: DIFFICULTIES[key].label,
    disabled: false,
  }));
  const timeItems = RING_TIME_VALUES.map((t) => ({
    key: String(t),
    imgSrc: ASSET_BASE + 'images/' + t + '.png',
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
      lastManualTimeLimit = currentTimeLimit;
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
  document.getElementById('retryBtn').addEventListener('click', startGame);
  document.getElementById('backToTitleBtn').addEventListener('click', backToTitle);

  document.getElementById('reviewBtn').addEventListener('click', openReview);
  document.getElementById('shareBtn').addEventListener('click', shareToX);
  document.getElementById('saveImageBtn').addEventListener('click', saveResultImage);

  document.getElementById('reviewPrevBtn').addEventListener('click', reviewGoPrev);
  document.getElementById('reviewNextBtn').addEventListener('click', reviewGoNext);
  document.getElementById('reviewBackBtn').addEventListener('click', backToResultFromReview);

  document.getElementById('rankSubmitBtn').addEventListener('click', submitRankEntry);
  document.getElementById('rankNameInput').addEventListener('keydown', (e) => {
    if (e.key === 'Enter') submitRankEntry();
  });
  document.getElementById('viewRankingBtn').addEventListener('click', openRankingScreen);

  setupRankingBoardButtons();
  document.getElementById('rankingBackBtn').addEventListener('click', backToResultFromRanking);

  document.getElementById('abortBtn').addEventListener('click', abortGame);

  document.getElementById('oxBtnO').addEventListener('click', () => onOxAnswer('o'));
  document.getElementById('oxBtnX').addEventListener('click', () => onOxAnswer('x'));

  document.getElementById('devControls').hidden = !debugMode;

  setupSoundUI();
}

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

function updateTitleMuteUI() {
  const icon = document.getElementById('titleMuteIcon');
  const label = document.getElementById('titleMuteLabel');
  const btn = document.getElementById('titleMuteBtn');
  if (!icon || !label) return;
  icon.src = ASSET_BASE + 'images/' + (bgmMuted ? 'mute_on.png' : 'mute_off.png');
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
    if (wasMuted) unlockSeElements().then(() => playRingTickSe());
  });
}

/* ---------- SE診断パネル（?debug=1。選択肢版と同一） ---------- */

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

  const { S, timing, pinkCalc, whiteCalc, correctColors, decision, diffKey } = q;
  const fmt = (o) => '左' + o.left + ' 中' + o.middle + ' 右' + o.right;

  const lines = [];
  lines.push('=== デバッグ情報（難易度: ' + DIFFICULTIES[diffKey].label + '） ===');
  lines.push('S: ' + fmt(S));
  lines.push('d: ' + fmt(timing.d));
  lines.push('D: ' + timing.D);
  lines.push('X: ' + fmt(timing.X));
  lines.push('ピンクの所要: ' + fmt(pinkCalc.Dline) + '  max=' + pinkCalc.required);
  lines.push('白の所要: ' + fmt(whiteCalc.Dline) + '  max=' + whiteCalc.required);
  lines.push('正解色: ' + correctColors.map(colorLabel).join('・') + (correctColors.length === 2 ? '（同着）' : ''));

  lines.push('');
  lines.push('=== 出した画像 ===');
  lines.push('正解（○×）: ' + (decision.ans === 'o' ? '○' : '×'));
  lines.push('種別: ' + ({ correct: '正しい形（速い色）', slow: '遅い色の正しい形', shift: 'ずらし' })[decision.kind]);
  lines.push('色: ' + colorLabel(decision.color));
  if (decision.kind === 'shift') {
    const shiftInfo = REEL_NAMES
      .filter((r) => decision.offsets[r] !== 0)
      .map((r) => REEL_LABEL[r] + (decision.offsets[r] > 0 ? '+' : '') + decision.offsets[r])
      .join('・');
    lines.push('ずらし量: ' + (shiftInfo || 'なし'));
  }
  lines.push('A: ' + fmt(decision.A));

  panel.textContent = lines.join('\n');
}

/* ---------- ダブルタップズームの抑止（JS版。選択肢版と同一） ---------- */

(function setupDoubleTapZoomGuard() {
  const DOUBLE_TAP_MS = 300;
  const DOUBLE_TAP_DIST_PX = 30;
  let lastTapTime = 0;
  let lastTapX = 0;
  let lastTapY = 0;

  document.addEventListener('touchend', (e) => {
    if (e.touches.length > 0) return;
    if (!e.changedTouches || e.changedTouches.length !== 1) return;

    const touch = e.changedTouches[0];
    const now = Date.now();
    const dx = touch.clientX - lastTapX;
    const dy = touch.clientY - lastTapY;
    const dist = Math.sqrt(dx * dx + dy * dy);

    if (lastTapTime && now - lastTapTime < DOUBLE_TAP_MS && dist < DOUBLE_TAP_DIST_PX) {
      e.preventDefault();
      lastTapTime = 0;
      return;
    }

    lastTapTime = now;
    lastTapX = touch.clientX;
    lastTapY = touch.clientY;
  }, { passive: false });
})();

document.addEventListener('DOMContentLoaded', init);
