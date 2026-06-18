-- ============================================================
-- 0029 : 所持枠（カード保有上限）を 300/+100/1100 → 200/+100/1000 へ
--   canon-02 §7 / canon-07 §3「要追従」（所持枠 least(200+100×cleared_stage,1000)）
--
--   旧（廃止）: cap = least(300 + 100×cleared_stage, 1100)
--   新（canon）: cap = least(200 + 100×cleared_stage, 1000)
--     ＝初期200・面クリアごと+100・上限1000（8面クリアで 200+800=1000）。
--
--   所持枠は算出値（profiles に列なし・0001 のコメントどおり）＝チェック箇所は do_gacha のみ。
--   本ファイルは do_gacha を再定義（cap 行のみ変更）。pick_fixed_skill（0007）は据え置き＝
--   再定義しない（do_gacha は実行時に public.pick_fixed_skill を呼ぶだけ・DBに存在）。
--   GACHA_COST=300（ガチャ費用）は cap とは無関係＝変更しない。
--   クライアント追従なし（index.html に cap 値のハードコードなし。満杯時はサーバの
--   'not enough card space' を文言化するのみ）。
--
--   前提: 0004→0007（do_gacha）適用済み。本ファイルで do_gacha を上書き。
-- ============================================================

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

  -- 所持枠検証：現カード数 + 6 ≤ 200+100×cleared_stage（最大1000）。満たないなら弾く（消費なし）
  select count(*) into cur_count from public.cards where user_id = uid;
  cap := least(200 + 100 * prof.cleared_stage, 1000);
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
