'use strict';

const REEL_NAMES = ['left', 'middle', 'right'];
const SYMBOL_NAMES = [
  'bell', 'replay', 'suika', 'cherry', 'hana',
  'pink7', 'white7', 'hibiscus', 'pinkBAR', 'whiteBAR',
];
const COLOR_KEY = { pink: 'pink7', white: 'white7' };
const REEL_LABEL = { left: '左', middle: '中', right: '右' };

const DIFFICULTIES = {
  beginner: { label: '初心者', special: true },
  easy: { label: '易', shift: 2, reelCount: 1, fixLeft: true },
  normal: { label: '並', shift: 2, reelCount: 2, fixLeft: false },
  hard: { label: '極', shift: 1, reelCount: 1, fixLeft: false },
};

// 初心者モードの出目条件（仕様：左中段4or14・正解色のAがmax-min<=4）。
const BEGINNER_SPREAD_MAX = 4;

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
let currentDifficulty = 'normal';
let currentQuestion = null;
let debugMode = false;
let forcedStops = null; // ?fix=左,中,右 で出目を固定（検証用）

/* ---------- ゲーム進行（仕様書 第6章：タイマー・スコアのみ） ---------- */

// gamePhase: 'idle'（未開始） | 'preview'（1問だけ表示＝タイマーなし） |
//            'playing'（タイマー中） | 'ending'（時間切れ後の3秒静止） | 'result'
let gamePhase = 'idle';
let currentTimeLimit = 60; // 30 / 60
let timerStartMs = 0; // performance.now() 基準の開始時刻
let timerTotalMs = 0; // 制限時間の総ミリ秒
let timerPausedTotalMs = 0; // これまでに停止していた合計時間（回答待ちの1秒間ぶん）
let timerPauseStartedAt = null; // 現在停止中ならその開始時刻。停止中でなければnull
let timerRafId = null; // requestAnimationFrame のID
let endingTimeoutId = null; // 時間切れ後の3秒静止用
let endSePlayed = false; // end.wav（残り3秒の笛）を1ゲームにつき1回だけ鳴らすためのフラグ
let correctCount = 0;
let wrongCount = 0;
let records = []; // 1問ごとの出題・回答記録（振り返り用。今回は蓄積のみ）
let beginnerCandidates = []; // 初心者モードの出目候補（起動時に一度だけ生成）

/* ---------- 音（仕様書 第6章：BGM・SE） ---------- */

let audioCtx = null; // ユーザーのタップ（スタートボタン）でresume()する
let seGainNode = null; // SE用のゲインノード（音量・ミュートをまとめて反映）
let currentSeSource = null; // 再生中のSEソース（新しいSEを鳴らす前に止める＝1チャンネル）
let soundBuffers = { seikai: null, huseikai: null, end: null }; // decodeAudioData済みのAudioBuffer
let bgmEl = null;
let bgmVolume = 0.8;
let seVolume = 0.8;
let bgmMuted = false;
let seMuted = false;

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
    forcedStops = parseForcedStops();
    const res = await fetch('reels.json');
    if (!res.ok) throw new Error('reels.json の取得に失敗しました（status ' + res.status + '）');
    const data = await res.json();
    reelsData = data.reels;
    sevens = data.sevens;
    bgmEl = document.getElementById('bgmAudio');
    await preloadImages();
    beginnerCandidates = buildBeginnerCandidates();
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

/* ---------- 音の読み込み・再生 ----------
 * AudioContextは起動時に生成してdecodeAudioDataまで済ませる（生成・デコード自体は
 * ユーザー操作なしでも可能）。実際の再生をアンロックするresume()はスタートボタンの
 * タップで行う（モバイルの自動再生制限対策）。
 * wavの読み込み・デコードに失敗した場合はbufferがnullのままになり、playSe()が
 * 何もせず無視する＝無音になるだけでゲーム進行（判定・スコア）には影響しない。 */

async function loadSoundBuffer(url) {
  try {
    const res = await fetch(url);
    if (!res.ok) throw new Error('status ' + res.status);
    const arrayBuffer = await res.arrayBuffer();
    return await audioCtx.decodeAudioData(arrayBuffer);
  } catch (err) {
    console.error('効果音の読み込みに失敗しました（無音のまま続行します）: ' + url, err);
    return null;
  }
}

async function preloadSounds() {
  try {
    audioCtx = new (window.AudioContext || window.webkitAudioContext)();
  } catch (err) {
    console.error('AudioContextの生成に失敗しました。効果音・BGMなしで続行します。', err);
    audioCtx = null;
    return;
  }

  seGainNode = audioCtx.createGain();
  seGainNode.connect(audioCtx.destination);
  applySeVolume();

  const [seikai, huseikai, end] = await Promise.all([
    loadSoundBuffer('sounds/seikai.wav'),
    loadSoundBuffer('sounds/huseikai.wav'),
    loadSoundBuffer('sounds/end.wav'),
  ]);
  soundBuffers.seikai = seikai;
  soundBuffers.huseikai = huseikai;
  soundBuffers.end = end;
}

// SEは1チャンネル：新しいSEを鳴らす前に再生中のSEを止める（正解SE等の重なりを防ぐ）
function playSe(name) {
  if (!audioCtx || !seGainNode) return;
  const buffer = soundBuffers[name];
  if (!buffer) return; // 読み込み失敗時は無音のまま
  if (currentSeSource) {
    try { currentSeSource.stop(); } catch (err) { /* 既に停止済みなら無視 */ }
    currentSeSource = null;
  }
  const source = audioCtx.createBufferSource();
  source.buffer = buffer;
  source.connect(seGainNode);
  source.start();
  currentSeSource = source;
}

function applyBgmVolume() {
  if (bgmEl) bgmEl.volume = bgmMuted ? 0 : bgmVolume;
}

function applySeVolume() {
  if (seGainNode) seGainNode.gain.value = seMuted ? 0 : seVolume;
}

// スタートボタンのタップ（ユーザー操作）をきっかけにAudioContextを起こし、BGMを再生する
function unlockAndPlayBgm() {
  if (audioCtx && audioCtx.state === 'suspended') {
    audioCtx.resume().catch((err) => console.error('AudioContextの再開に失敗しました', err));
  }
  if (!bgmEl) return;
  bgmEl.currentTime = 0;
  applyBgmVolume();
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

/* ---------- 出題生成・判定ロジック（仕様書 第5章） ---------- */

function generateStops(diffKey) {
  if (forcedStops) return forcedStops;
  if (diffKey === 'beginner') {
    const idx = Math.floor(Math.random() * beginnerCandidates.length);
    return beginnerCandidates[idx];
  }
  const diff = DIFFICULTIES[diffKey];
  const left = diff.fixLeft ? (Math.random() < 0.5 ? 4 : 14) : randNum();
  const middle = randNum();
  const right = randNum();
  return { left, middle, right };
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

/* ---------- 初心者モード：出目候補の生成（起動時に一度だけ） ----------
 * 条件：左中段が4または14 / 正解色のA（受付ラインから7までのコマ数、
 * ずらしなし）についてmax(A)-min(A)<=BEGINNER_SPREAD_MAX。
 * 同着（正解色が定まらない）出目は候補から除外する。
 * 判定ロジック（judgeQuestion）は他難易度と共通・無変更。 */
function buildBeginnerCandidates() {
  const candidates = [];
  let pinkCount = 0;
  let whiteCount = 0;
  let tieCount = 0;

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
          candidates.push(S);
          if (color === 'pink') pinkCount++; else whiteCount++;
        }
      }
    }
  }

  console.log(
    '[初心者モード] 候補' + candidates.length + '件' +
    '（ピンク' + pinkCount + '・白' + whiteCount + '）、同着除外' + tieCount + '件'
  );
  return candidates;
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
// 超えるならそのリールだけ符号を反転する（2リールまとめての反転はしない）。
function applyShiftsWithFlip(baseA, rawOffsets) {
  const A = { ...baseA };
  const finalOffsets = { left: 0, middle: 0, right: 0 };
  for (const reel of REEL_NAMES) {
    let amt = rawOffsets[reel] || 0;
    if (amt === 0) continue;
    A[reel] += amt;
    if (rangeSize(A) > 21) {
      A[reel] -= amt;
      amt = -amt;
      A[reel] += amt;
    }
    finalOffsets[reel] = amt;
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
 *
 * 極（hard）は従来どおり：下端＝各リールの最小A（受付ライン以降で最初の7）、
 * 7以外の図柄は描かず格子線だけを引く。
 *
 * 初・易・並：下端を受付開始ライン（A=0）で固定し、上端は従来どおりmax(A)。
 * 表示範囲0〜max(A)の各行・各リールについて、リールiの (refX_i + 行) 番の
 * 図柄（7以外も含む実際のリール配列）を描く。ずらし選択肢はrefXがo_iぶん
 * ずれているため、ずらした位置の図柄がそのまま出る。
 */

function renderChoiceStrip(container, choice, diffKey) {
  const layout = choice.layout;
  const sevenSymbol = choice.color === 'pink' ? 'pink7' : 'white7';
  const showFull = diffKey !== 'hard';
  const top = layout.maxA;
  const bottom = showFull ? 0 : layout.minA;
  const rows = top - bottom + 1;

  const grid = document.createElement('div');
  grid.className = 'choice-strip';
  grid.style.gridTemplateRows = 'repeat(' + rows + ', auto)';

  for (let j = 0; j < rows; j++) {
    const a = top - j;
    for (const reel of REEL_NAMES) {
      const slot = document.createElement('div');
      slot.className = 'choice-slot';
      if (showFull) {
        const symbolName = symbolAt(reel, layout.refX[reel] + a);
        const img = document.createElement('img');
        img.className = 'choice-symbol';
        img.src = symbolImages[symbolName].src;
        img.alt = symbolName;
        slot.appendChild(img);
      } else if (layout.A[reel] === a) {
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

/* ---------- 出題の組み立て・UI ---------- */

let advanceTimer = null;

function newQuestion() {
  if (advanceTimer) {
    clearTimeout(advanceTimer);
    advanceTimer = null;
  }

  const diffKey = currentDifficulty;
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
    renderChoiceStrip(cell, choice, diffKey);
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
  playSe(choice.isCorrect ? 'seikai' : 'huseikai');

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

  // .stage-wrap / .choices-wrap は display:flex 等をCSSで明示しているため、
  // hidden属性ではなくインラインstyleで確実に切り替える。
  document.querySelector('.stage-wrap').style.display = isResult ? 'none' : '';
  document.querySelector('.choices-wrap').style.display = isResult ? 'none' : '';
  document.getElementById('resultMessage').hidden = isResult;
  document.getElementById('resultScreen').hidden = !isResult;
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

  // end.wav：残り3.00秒の時点で1回だけ再生を開始する
  if (!endSePlayed && remainingMs <= 3000) {
    endSePlayed = true;
    playSe('end');
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
  unlockAndPlayBgm(); // ユーザーのタップ（このクリック）でAudioContextを起こす
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
}

function backToSetup() {
  stopTimers();
  stopBgm();
  setPhase('idle');
  document.getElementById('stage').innerHTML = '';
  document.getElementById('choices').innerHTML = '';
  clearResult();
  currentQuestion = null;
}

// 確認用「1問だけ表示」：タイマーなしで出題と判定だけ見る（従来の動作）
function showPreviewQuestion() {
  stopTimers();
  setPhase('preview');
  newQuestion();
}

// 初心者モードは30秒のみ：60秒ボタンを無効化し、60秒が選ばれていたら30秒に戻す
function applyTitleTimeConstraint() {
  const time60Btn = document.querySelector('.title-time-btn[data-time="60"]');
  const time30Btn = document.querySelector('.title-time-btn[data-time="30"]');
  const isBeginner = currentDifficulty === 'beginner';
  if (time60Btn) time60Btn.disabled = isBeginner;
  if (isBeginner && currentTimeLimit === 60) {
    currentTimeLimit = 30;
    document.querySelectorAll('.title-time-btn').forEach((b) => b.classList.remove('active'));
    if (time30Btn) time30Btn.classList.add('active');
  }
}

// タイトル画面：難易度・時間の選択（平面の横並び）
function setupTitleSelectors() {
  const diffButtons = document.querySelectorAll('.title-diff-btn');
  diffButtons.forEach((btn) => {
    btn.addEventListener('click', () => {
      diffButtons.forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      currentDifficulty = btn.dataset.diff;
      applyTitleTimeConstraint();
    });
  });
  const activeDiffBtn = document.querySelector('.title-diff-btn[data-diff="' + currentDifficulty + '"]');
  if (activeDiffBtn) activeDiffBtn.classList.add('active');

  const timeButtons = document.querySelectorAll('.title-time-btn');
  timeButtons.forEach((btn) => {
    btn.addEventListener('click', () => {
      if (btn.disabled) return;
      timeButtons.forEach((b) => b.classList.remove('active'));
      btn.classList.add('active');
      currentTimeLimit = parseInt(btn.dataset.time, 10);
    });
  });
  const activeTimeBtn = document.querySelector('.title-time-btn[data-time="' + currentTimeLimit + '"]');
  if (activeTimeBtn) activeTimeBtn.classList.add('active');

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
  setupTitleSelectors();
}

function setupUI() {
  document.getElementById('startBtn').addEventListener('click', startGame);
  document.getElementById('previewBtn').addEventListener('click', showPreviewQuestion);
  // もう一度：同じ難易度・時間で即再スタート
  document.getElementById('retryBtn').addEventListener('click', startGame);
  document.getElementById('backToTitleBtn').addEventListener('click', backToTitle);

  // 中断ボタン：押したら即リザルトへ（ゲーム画面にのみ表示。仕様上の動作は現状のまま）
  document.getElementById('abortBtn').addEventListener('click', abortGame);

  // 確認用UI全体は ?debug=1 のときだけ表示する
  document.getElementById('devControls').hidden = !debugMode;

  setupSoundUI();
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
    bgmMuteBtn.classList.toggle('active', bgmMuted);
    bgmMuteBtn.textContent = bgmMuted ? 'ミュート中' : 'ミュート';
    applyBgmVolume();
  });
  seMuteBtn.addEventListener('click', () => {
    seMuted = !seMuted;
    seMuteBtn.classList.toggle('active', seMuted);
    seMuteBtn.textContent = seMuted ? 'ミュート中' : 'ミュート';
    applySeVolume();
  });

  applyBgmVolume();
  applySeVolume();
}

/* ---------- デバッグパネル（?debug=1） ---------- */

function renderDebugPanel(q) {
  const panel = document.getElementById('debugPanel');
  panel.hidden = false;

  const { S, timing, pinkCalc, whiteCalc, correctColors, choices, diffKey } = q;
  const fmt = (o) => '左' + o.left + ' 中' + o.middle + ' 右' + o.right;
  const colorLabel = (c) => (c === 'pink' ? 'ピンク7' : '白7');

  const lines = [];
  lines.push('=== デバッグ情報（難易度: ' + DIFFICULTIES[diffKey].label + '） ===');
  lines.push('S: ' + fmt(S));
  lines.push('d: ' + fmt(timing.d));
  lines.push('D: ' + timing.D);
  lines.push('X: ' + fmt(timing.X));
  lines.push('ピンクの所要: ' + fmt(pinkCalc.Dline) + '  max=' + pinkCalc.required);
  lines.push('白の所要: ' + fmt(whiteCalc.Dline) + '  max=' + whiteCalc.required);
  lines.push('正解色: ' + correctColors.map(colorLabel).join('・'));
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

document.addEventListener('DOMContentLoaded', init);
