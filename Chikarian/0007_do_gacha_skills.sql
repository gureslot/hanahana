-- =============================================================================
-- 0007 : do_gacha 改修（固定スキル slot0 付与）＋ pick_fixed_skill ヘルパ
-- 出典: skill-db-spec-2026-06-14.md §5(抽選プール)・§6(付与手順)
-- 前提: 0006 で skill_master 投入済み（FK 先）。0004 do_gacha を create or replace で上書き。
-- 実行: SQL Editor に貼って Run（再実行可）。
--
-- 【0004 からの差分】
--   カード挿入直後（new_id 取得後）に、card_key から §5 のプールで slot0 固定スキルを
--   1つ抽選し card_skills(slot=0,skill_lv=1) に挿入する。slot1/2 は作らない（転移で埋める・§6-5）。
--   SP は固定キー直付け（抽選なし）。返り値の各カードに skill_key を追加。
-- =============================================================================


-- ============================ pick_fixed_skill ==============================
-- card_key → §5 のルールで固定スキル skill_key を1つ返す（N のみ重み付き＝非戦闘1/4）。
-- 純粋な抽選関数（テーブル書込みなし）。do_gacha と将来の遡及付与の両方から使う。
create or replace function public.pick_fixed_skill(p_card_key text)
returns text
language plpgsql
volatile
set search_path = public
as $$
declare
  parts text[] := string_to_array(p_card_key, '_');
  attr  text;
  weap  text;
  rare  text;
  pool  text[];
begin
  -- SP（chara_{dragon|girl|houou}_sp）＝固定キー（§5・抽選なし）
  if p_card_key like 'chara\_%\_sp' escape '\' then
    if    p_card_key = 'chara_dragon_sp' then return 'sp_ryuki';
    elsif p_card_key = 'chara_girl_sp'   then return 'sp_aitou';
    elsif p_card_key = 'chara_houou_sp'  then return 'sp_fushichou';
    else raise exception 'unknown SP card_key %', p_card_key;
    end if;
  end if;

  -- めしべ（chara_meshibe_shin_tsue_{sr|ssr}）＝候補2つから1つ（案X）
  if parts[2] = 'meshibe' then
    rare := parts[array_length(parts,1)];
    if    rare = 'sr'  then pool := array['meshibe_sr_hisou',  'meshibe_sr_banshou'];
    elsif rare = 'ssr' then pool := array['meshibe_ssr_shinsou','meshibe_ssr_tenkei'];
    else raise exception 'unknown meshibe rarity in %', p_card_key;
    end if;
    return pool[1 + floor(random() * array_length(pool,1))::int];
  end if;

  -- ハイビスカス（chara_hibiscus_{attr}_{weap}_{rare}）
  if parts[2] = 'hibiscus' then
    attr := parts[3];
    weap := parts[4];
    rare := parts[5];

    if rare = 'n' then
      -- 通常候補4種=各重み4、非戦闘2種=各重み1（§5）＝配列展開で重み表現（18要素）
      -- array_fill(anyelement,int[]) は要素が裸リテラルだと型 unknown で多態解決に失敗するため ::text 明示
      pool := array[]::text[];
      pool := pool
        || array_fill(('n_sougou_' || attr)::text, array[4])
        || array_fill(('n_sougou_' || weap)::text, array[4])
        || array_fill(('n_hontai_' || attr)::text, array[4])
        || array_fill(('n_hontai_' || weap)::text, array[4])
        || array_fill('n_util_houjou'::text, array[1])
        || array_fill('n_util_senri'::text,  array[1]);

    elsif rare = 'r' then
      pool := array['r_sougou_'||attr, 'r_sougou_'||weap, 'r_soubi_'||attr, 'r_soubi_'||weap];

    elsif rare = 'sr' then
      -- 「attrを含む連奏」＋「weapを含む連奏」＋ sr_gekirin + sr_keppun（一様6）
      if attr not in ('hana','ha','shin') then raise exception 'unknown attr % in %', attr, p_card_key; end if;
      if weap not in ('ken','tate','tsue') then raise exception 'unknown weap % in %', weap, p_card_key; end if;
      pool := (case attr
                 when 'hana' then array['sr_kyousou_hana_ha','sr_kyousou_hana_shin']
                 when 'ha'   then array['sr_kyousou_hana_ha','sr_kyousou_ha_shin']
                 when 'shin' then array['sr_kyousou_ha_shin','sr_kyousou_hana_shin']
               end)
            || (case weap
                 when 'ken'  then array['sr_kyousou_ken_tate','sr_kyousou_ken_tsue']
                 when 'tate' then array['sr_kyousou_ken_tate','sr_kyousou_tate_tsue']
                 when 'tsue' then array['sr_kyousou_tate_tsue','sr_kyousou_ken_tsue']
               end)
            || array['sr_gekirin','sr_keppun'];

    elsif rare = 'ssr' then
      pool := array['ssr_haen','ssr_yuusei','ssr_ougon','ssr_kyoumei'];

    else
      raise exception 'unknown hibiscus rarity in %', p_card_key;
    end if;

    return pool[1 + floor(random() * array_length(pool,1))::int];
  end if;

  raise exception 'unsupported card_key %', p_card_key;
end;
$$;


-- ================================ do_gacha ==================================
create or replace function public.do_gacha()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  GACHA_COST constant bigint := 300;   -- balance §1
  DRAW_COUNT constant int := 6;        -- balance §1
  attrs text[] := array['hana','ha','shin'];   -- 花/葉/芯
  weaps text[] := array['ken','tate','tsue'];   -- 剣/盾/杖
  sps   text[] := array['dragon','girl','houou'];
  prof public.profiles;
  cur_count int;
  cap int;
  i int;
  r double precision;
  rare text;
  ckey text;
  q text;
  idx int;
  new_id uuid;
  v_skill text;        -- ← 追加: 抽選した固定スキル
  results jsonb := '[]'::jsonb;
  new_chikarium bigint;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  -- 行ロック（同時実行での二重消費/枠超過を防ぐ）
  select * into prof from public.profiles where id = uid for update;
  if not found then raise exception 'profile not initialized'; end if;

  -- 通貨検証
  if prof.chikarium < GACHA_COST then
    raise exception 'not enough chikarium';
  end if;

  -- 所持枠検証：現カード数 + 6 ≤ 300+100×cleared_stage（最大1100）。満たないなら弾く（消費なし）
  select count(*) into cur_count from public.cards where user_id = uid;
  cap := least(300 + 100 * prof.cleared_stage, 1100);
  if cur_count + DRAW_COUNT > cap then
    raise exception 'not enough card space';
  end if;

  -- 300消費
  update public.profiles set chikarium = chikarium - GACHA_COST where id = uid;

  -- 6回独立抽選
  for i in 1..DRAW_COUNT loop
    r := random();  -- 0..1
    if r < 0.5545 then
      -- N（帯内9種＝ハイビスカス 属性×武器 を一様）
      rare := 'n';
      ckey := 'chara_hibiscus_' || attrs[(1+floor(random()*3))::int] || '_' || weaps[(1+floor(random()*3))::int] || '_n';
      q := 'crude';
    elsif r < 0.8710 then
      -- R（+0.3165）
      rare := 'r';
      ckey := 'chara_hibiscus_' || attrs[(1+floor(random()*3))::int] || '_' || weaps[(1+floor(random()*3))::int] || '_r';
      q := 'crude';
    elsif r < 0.9610 then
      -- SR（+0.09・帯内10種＝ハイビスカス9＋めしべ芯杖1を一様）
      rare := 'sr';
      idx := floor(random()*10)::int;  -- 0..9
      if idx < 9 then
        ckey := 'chara_hibiscus_' || attrs[(1+(idx/3))::int] || '_' || weaps[(1+(idx%3))::int] || '_sr';
      else
        ckey := 'chara_meshibe_shin_tsue_sr';
      end if;
      q := 'crude';
    elsif r < 0.9780 then
      -- SP（+0.017・帯内3種を一様。quality=null）
      rare := 'sp';
      ckey := 'chara_' || sps[(1+floor(random()*3))::int] || '_sp';
      q := null;
    else
      -- SSR（+0.022・帯内10種＝ハイビスカス9＋めしべ芯杖1を一様）
      rare := 'ssr';
      idx := floor(random()*10)::int;
      if idx < 9 then
        ckey := 'chara_hibiscus_' || attrs[(1+(idx/3))::int] || '_' || weaps[(1+(idx%3))::int] || '_ssr';
      else
        ckey := 'chara_meshibe_shin_tsue_ssr';
      end if;
      q := 'crude';
    end if;

    -- cards 挿入（通常 quality=crude / SP quality=null・Lv1・★0）
    insert into public.cards (user_id, card_key, lv, exp, star, quality, loaded_buki, locked)
    values (uid, ckey, 1, 0, 0, q, 0, false)
    returning id into new_id;

    -- 図鑑（未登録なら記録・カード消滅後も残る）
    insert into public.zukan (user_id, card_key) values (uid, ckey)
    on conflict (user_id, card_key) do nothing;

    -- ★追加: 固定スキル slot0 を §5 プールから抽選して付与（slot1/2 は作らない）
    v_skill := public.pick_fixed_skill(ckey);
    insert into public.card_skills (card_id, slot, skill_key, skill_lv)
    values (new_id, 0, v_skill, 1);

    results := results || jsonb_build_object('id', new_id, 'card_key', ckey, 'rarity', rare, 'skill_key', v_skill);
  end loop;

  select chikarium into new_chikarium from public.profiles where id = uid;

  return jsonb_build_object(
    'cards', results,           -- 引いた6枚 [{id, card_key, rarity, skill_key}, ...]
    'chikarium', new_chikarium  -- 消費後の総チカリウム
  );
end;
$$;

revoke all on function public.do_gacha() from public;
grant execute on function public.do_gacha() to authenticated;

-- pick_fixed_skill はクライアント直叩き不要だが、definer関数内から呼ぶため public のままでOK。
-- （明示的に絞る場合: revoke all on function public.pick_fixed_skill(text) from public;）

-- =============================================================================
-- 備考:
--  * 既存カード（0004時代に引いた固定スキル無しのカード）への遡及付与が要るなら、
--    別途 backfill 関数で「card_skills に slot0 が無い cards に pick_fixed_skill を流す」を実行可（§6・任意）。
--  * 重み付き（N）は配列展開（array_fill）で一様抽選＝通常4:非戦闘1 を表現。
-- =============================================================================
