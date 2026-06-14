/*
 * chikarian-api.js — Supabase データ層（SPA 共通）
 * ---------------------------------------------------------------------------
 * 前提: HTML で先に Supabase UMD を読み込む（anonキーは公開可・DBパスワード/service_roleは絶対秘匿）:
 *   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
 *   <script src="./chikarian-api.js"></script>
 *
 * 使い方:
 *   ChikarianAPI.init(SUPABASE_URL, SUPABASE_ANON_KEY);
 *   ChikarianAPI.auth.onChange(session => { ... 画面切替 ... });
 *   await ChikarianAPI.auth.signInWithGoogle();      // 認証=Google
 *   const me = await ChikarianAPI.getProfile();
 *   const r  = await ChikarianAPI.doKyoka(baseId, matId, 1);
 *
 * 方針: 資産が動く処理は全てサーバRPC（このラッパ経由）。表示は直SELECT（RLSで自分の行のみ）。
 *       RPCラッパはエラー時に例外を投げる（error.message にRPCのコード＝例 'INSUFFICIENT_MEDAL'）。
 */
(function (global) {
  'use strict';
  let sb = null;

  function init(url, anonKey) {
    if (!global.supabase || !global.supabase.createClient) {
      throw new Error('supabase-js (UMD) 未読み込み。<script src=".../@supabase/supabase-js@2"> を先に。');
    }
    sb = global.supabase.createClient(url, anonKey, {
      auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
    });
    return sb;
  }
  function client() {
    if (!sb) throw new Error('先に ChikarianAPI.init(url, anonKey) を呼んでください。');
    return sb;
  }

  // ---- RPC / SELECT 共通 ----
  async function rpc(name, args) {
    const { data, error } = await client().rpc(name, args || {});
    if (error) throw error;
    return data;
  }
  async function selectOwn(table, columns) {
    const { data, error } = await client().from(table).select(columns || '*');
    if (error) throw error;            // RLSで自分の行のみ
    return data;
  }

  // ---- 認証（Google OAuth）----
  const auth = {
    signInWithGoogle: () => client().auth.signInWithOAuth({
      provider: 'google',
      options: { redirectTo: global.location.origin + global.location.pathname }
    }),
    signOut:    () => client().auth.signOut(),
    getSession: async () => (await client().auth.getSession()).data.session,
    getUser:    async () => (await client().auth.getUser()).data.user,
    onChange:   (cb) => client().auth.onAuthStateChange((_evt, session) => cb(session))
  };

  // ---- 読み取り（RLSで自分の行のみ／マスタは全員可）----
  const getProfile       = async () => (await selectOwn('profiles'))[0] || null;
  const getCards         = ()        => selectOwn('cards');
  const getCardSkills    = async (cardId) => {
    const { data, error } = await client().from('card_skills').select('*').eq('card_id', cardId);
    if (error) throw error; return data;
  };
  const getDecks         = ()        => selectOwn('decks');
  const getRenkiden      = async ()  => (await selectOwn('renkiden'))[0] || null;
  const getKajiyaOrders  = ()        => selectOwn('kajiya_orders');
  const getTansaku       = ()        => selectOwn('tansaku_states');
  const getZukan         = ()        => selectOwn('zukan');
  const getMissions      = ()        => selectOwn('missions');
  const getMissionMaster = ()        => selectOwn('mission_master');           // 全員読取り可
  const getExchangeRates = ()        => selectOwn('crystal_exchange_master');  // 全員読取り可
  const getSkillMaster   = ()        => selectOwn('skill_master');             // 全員読取り可

  // ============================================================
  // 書き込み（資産が動く＝全てRPC）
  // ============================================================

  // ---- 既存(0001-0011) 引数名は repo の SQL と突合済み（2026-06-14）----
  //   claim_saishu(n integer)＝0003 / do_gacha()＝0004,0007 /
  //   update_deck(p_deck_no,p_slot1,p_slot2,p_slot3)＝0005 / do_boss_battle(p_deck_no,p_boss_key)＝0011。
  const claimSaishu  = (n)                  => rpc('claim_saishu',   { n: n });                                    // 0003: 引数名は n（dev/console.html と一致）
  const doGacha      = ()                   => rpc('do_gacha',       {});                                          // 0004/0007: 引数なし
  const updateDeck   = (deckNo, s1, s2, s3) => rpc('update_deck',    { p_deck_no: deckNo, p_slot1: s1, p_slot2: s2, p_slot3: s3 }); // 0005: 一致
  const doBossBattle = (deckNo, bossKey)    => rpc('do_boss_battle', { p_deck_no: deckNo, p_boss_key: bossKey });  // 0011: 一致

  // ---- 0012-0021（引数名は確定）----
  const doKyoka         = (baseId, matId, hoshou = 0)      => rpc('do_kyoka',          { p_base_id: baseId, p_mat_id: matId, p_hoshou_n: hoshou });
  const doSkillTeni     = (srcId, srcSlot, dstId, dstSlot) => rpc('do_skill_teni',     { p_src_id: srcId, p_src_slot: srcSlot, p_dst_id: dstId, p_dst_slot: dstSlot });
  const doSkillRensei   = (cardId, slot, color)            => rpc('do_skill_rensei',   { p_card_id: cardId, p_slot: slot, p_color: color });
  const investRenkiden  = (medal)                          => rpc('invest_renkiden',   { p_medal: medal });
  const collectRenkiden = ()                               => rpc('collect_renkiden',  {});
  const instantRenkiden = (n)                              => rpc('instant_renkiden',  { p_n: n });
  const upgradeRenkiden = ()                               => rpc('upgrade_renkiden',  {});
  const placeKajiyaOrder= (quality)                        => rpc('place_kajiya_order',{ p_quality: quality });   // 'refined'|'enchanted'|'holy'
  const claimKajiya     = (orderId)                        => rpc('claim_kajiya',      { p_order_id: orderId });
  const equipBuki       = (cardId, quality, amount)        => rpc('equip_buki',        { p_card_id: cardId, p_quality: quality, p_amount: amount }); // quality: crude|refined|enchanted|holy, amount=枠数
  const startTansaku    = (deckNo, area, depth)            => rpc('start_tansaku',     { p_deck_no: deckNo, p_area: area, p_depth: depth });          // depth: 'shallow'|'mid'|'deep'
  const collectTansaku  = (deckNo)                         => rpc('collect_tansaku',   { p_deck_no: deckNo });
  const useExpBook      = (cardId, size, count = 1)        => rpc('use_exp_book',      { p_card_id: cardId, p_size: size, p_count: count });          // size: 's'|'m'|'l'|'xl'
  const doCardExchange  = (cardId)                         => rpc('do_card_exchange',  { p_card_id: cardId });
  const claimMission    = (missionKey)                     => rpc('claim_mission',     { p_mission_key: missionKey });

  global.ChikarianAPI = {
    init, client, rpc, auth,
    // reads
    getProfile, getCards, getCardSkills, getDecks, getRenkiden, getKajiyaOrders,
    getTansaku, getZukan, getMissions, getMissionMaster, getExchangeRates, getSkillMaster,
    // writes (existing)
    claimSaishu, doGacha, updateDeck, doBossBattle,
    // writes (0012-0021)
    doKyoka, doSkillTeni, doSkillRensei,
    investRenkiden, collectRenkiden, instantRenkiden, upgradeRenkiden,
    placeKajiyaOrder, claimKajiya, equipBuki,
    startTansaku, collectTansaku, useExpBook, doCardExchange, claimMission
  };
})(window);
