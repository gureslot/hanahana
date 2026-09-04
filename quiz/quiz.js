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
let resultImages = {}; // リザルト画像合成用（RESULT_IMAGE_NAMES参照）
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
let endSePlayed = false; // end.wav（時間切れの瞬間の笛）を1ゲームにつき1回だけ鳴らすためのフラグ
let correctCount = 0;
let wrongCount = 0;
let records = []; // 1問ごとの出題・回答記録（振り返り画面で使用）
let beginnerCandidates = []; // 初心者モードの出目候補（起動時に一度だけ生成）
let easyCandidates = []; // 易モードの出目候補（起動時に一度だけ生成。左中段4/14固定）
let normalHardCandidates = []; // 並・極モードの出目候補（起動時に一度だけ生成。左中段自由）
let reviewIndex = 0; // 振り返り画面で現在表示中の問題番号（0始まり、records基準）

/* ---------- 音（仕様書 第6章：BGM・SE） ---------- */

let audioCtx = null; // ユーザーのタップ（スタートボタン）でresume()する
let seGainNode = null; // SE用のゲインノード（音量・ミュートをまとめて反映。正誤SE・end.wav共通）
let currentJudgeSeSource = null; // 再生中の正誤SEソース（新しい方を鳴らす前に止める＝1チャンネル）
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
 * AudioContextは起動時に生成してdecodeAudioDataまで済ませる（生成・デコード自体は
 * ユーザー操作なしでも可能）。実際の再生をアンロックするresume()はスタートボタンの
 * タップで行う（モバイルの自動再生制限対策）。
 * wavの読み込み・デコードに失敗した場合はbufferがnullのままになり、再生関数が
 * 何もせず無視する＝無音になるだけでゲーム進行（判定・スコア）には影響しない。
 *
 * SEは2チャンネル構成：
 * ・正誤SE（seikai/huseikai）は従来どおり1チャンネル（新しい方を鳴らす前に前を止める）。
 * ・end.wav（時間切れの瞬間の笛）は正誤SEとは独立したチャンネルで鳴らし、一度鳴り
 *   始めたら途中で止めない（時間切れ後の3秒静止のあいだも鳴り終わるまで続く）。
 *   正誤SEを鳴らしても end.wav の再生には影響しない（かき消されない）。
 * どちらも同じ seGainNode を通すため、音量・ミュートは共通で反映される。 */

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

// 正誤SE（seikai/huseikai）：1チャンネル。新しい方を鳴らす前に再生中のものを止める。
function playJudgeSe(name) {
  if (!audioCtx || !seGainNode) return;
  const buffer = soundBuffers[name];
  if (!buffer) return; // 読み込み失敗時は無音のまま
  if (currentJudgeSeSource) {
    try { currentJudgeSeSource.stop(); } catch (err) { /* 既に停止済みなら無視 */ }
    currentJudgeSeSource = null;
  }
  const source = audioCtx.createBufferSource();
  source.buffer = buffer;
  source.connect(seGainNode);
  source.start();
  currentJudgeSeSource = source;
}

// end.wav専用チャンネル：正誤SEとは独立に鳴らし、途中で止めない（最後まで鳴らしきる）。
function playEndSe() {
  if (!audioCtx || !seGainNode) return;
  const buffer = soundBuffers.end;
  if (!buffer) return; // 読み込み失敗時は無音のまま
  const source = audioCtx.createBufferSource();
  source.buffer = buffer;
  source.connect(seGainNode);
  source.start();
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

  // .stage-wrap / .choices-wrap は display:flex 等をCSSで明示しているため、
  // hidden属性ではなくインラインstyleで確実に切り替える。
  document.querySelector('.stage-wrap').style.display = (isResult || isReview) ? 'none' : '';
  document.querySelector('.choices-wrap').style.display = (isResult || isReview) ? 'none' : '';
  document.getElementById('resultMessage').hidden = isResult || isReview;
  document.getElementById('resultScreen').hidden = !isResult;
  document.getElementById('reviewScreen').hidden = !isReview;
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
  // 1問も回答せず終わった場合（即中断など）は振り返る記録が無いのでボタンを無効化する
  document.getElementById('reviewBtn').disabled = records.length === 0;
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

  // リザルト：答え合わせ（振り返り画面へ）／Xシェア／画像を保存
  document.getElementById('reviewBtn').addEventListener('click', openReview);
  document.getElementById('shareBtn').addEventListener('click', shareToX);
  document.getElementById('saveImageBtn').addEventListener('click', saveResultImage);

  // 振り返り画面：前後送り・リザルトへ戻る
  document.getElementById('reviewPrevBtn').addEventListener('click', reviewGoPrev);
  document.getElementById('reviewNextBtn').addEventListener('click', reviewGoNext);
  document.getElementById('reviewBackBtn').addEventListener('click', backToResultFromReview);

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
