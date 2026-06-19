-- =============================================================================
-- 0004 : do_gacha() ＝ ガチャ（300チカリウム→6枚）RPC
-- 出典: balance §1（300/6枚・N55.45/R31.65/SR9/SP1.7/SSR2.2）/ cards.md §4（帯母数）/ spec §2
-- 実行: SQL Editor に貼って Run（create or replace・再実行可）。
-- 呼び方(クライアント): supabase.rpc('do_gacha')
--
-- 【この版の範囲】
--   実装する：300消費・6回独立抽選・帯内一様・cards挿入・zukan挿入・所持枠検証。
--   実装しない：card_skills（固定スキルslot0）の付与。
--     理由①skill_key（DB用の英字キー）体系が未定義（skills文書は日本語名/番号管理）。
--     理由②固定スキル抽選プールの候補表が未生成（cards.md §5＝実装時生成・SR特殊/非戦闘の重み未確定）。
--     → skill_key体系＋候補表が確定したら、別マイグレーションで card_skills 付与を追加する
--       （新規ガチャへの付与＋既存カードへの遡及付与）。
-- =============================================================================

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

    -- ※ card_skills（固定スキルslot0）の付与はこの版では行わない（冒頭コメント参照）

    results := results || jsonb_build_object('id', new_id, 'card_key', ckey, 'rarity', rare);
  end loop;

  select chikarium into new_chikarium from public.profiles where id = uid;

  return jsonb_build_object(
    'cards', results,           -- 引いた6枚 [{id, card_key, rarity}, ...]
    'chikarium', new_chikarium  -- 消費後の総チカリウム
  );
end;
$$;

revoke all on function public.do_gacha() from public;
grant execute on function public.do_gacha() to authenticated;
