-- ============================================================
-- Chikarian migration 0034: 占有ロック拒否チェック（CARD_IN_TANSAKU）を資産RPCに追加（1/?）
--   canon-06 §3-4 占有ロック / canon-07 §4「未実装」（B-2方式の第二段）
--
--   0033 で出発時に cards.tansaku_deck_no がセットされる。本ファイルで、探索中カード
--   （tansaku_deck_no が not null）に対する 編成・★強化・スキル転移/錬成・充填・出撃 を
--   サーバRPCで拒否する。共通ヘルパ _chikarian_assert_not_in_tansaku(card_id) を1つ作り、
--   各RPCの「カード取得後・資産変更前」に perform で挟む（null は無視＝空スロット安全）。
--
--   本ファイル(0034)対象：do_kyoka(0025) / do_skill_rensei(0021) / equip_buki(0031)。
--   続き：update_deck(0005)・do_skill_teni(0013)＝0035／do_boss_battle(0032)・start_tansaku(0033)＝0036。
--   ※各RPCは「最新版」を base に再定義（0025/0021/0031 が repo に適用済みである前提＝適用順 0034 はそれらの後）。
--   前提: 0033 適用済み（cards.tansaku_deck_no 存在）。
-- ============================================================

-- 共通ヘルパ：対象カードが探索中(tansaku_deck_no not null)なら CARD_IN_TANSAKU で拒否。null は無視。
create or replace function public._chikarian_assert_not_in_tansaku(p_card_id uuid)
returns void
language plpgsql
as $$
begin
  if p_card_id is null then return; end if;
  if exists (select 1 from public.cards where id = p_card_id and tansaku_deck_no is not null) then
    raise exception 'CARD_IN_TANSAKU';
  end if;
end;
$$;

-- ===== do_kyoka（0025）＋ CARD_IN_TANSAKU =====
create or replace function public.do_kyoka(
  p_base_id  uuid,
  p_mat_id   uuid,
  p_hoshou_n integer default 0
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_base record;
  v_mat  record;
  v_base_rare text;
  v_mat_rare  text;
  v_is_sp boolean;
  v_mat_cap integer;        -- 素材レアの Lv 上限（N30/R40/SR50/SSR60/SP50）
  v_mat_lv  integer;        -- 素材カードの現Lv（累積 exp から導出）
  v_cost  integer;
  v_rate  numeric;          -- 0..100
  v_medal_have  bigint;
  v_hoshou_have integer;
  v_success boolean;
  v_new_star integer;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_base_id = p_mat_id then raise exception 'SAME_CARD'; end if;
  if coalesce(p_hoshou_n, 0) < 0 then raise exception 'INVALID_HOSHOU'; end if;

  -- 本体・素材をロック（自分の所有のみ）
  select * into v_base from public.cards where id = p_base_id and user_id = v_uid for update;
  if not found then raise exception 'BASE_NOT_FOUND'; end if;
  select * into v_mat from public.cards where id = p_mat_id and user_id = v_uid for update;
  if not found then raise exception 'MATERIAL_NOT_FOUND'; end if;

  if v_base.locked then raise exception 'BASE_LOCKED'; end if;
  if v_mat.locked  then raise exception 'MATERIAL_LOCKED'; end if;

  -- 占有ロック：探索中カードは★強化不可（canon-06 §3-4）
  perform public._chikarian_assert_not_in_tansaku(p_base_id);
  perform public._chikarian_assert_not_in_tansaku(p_mat_id);

  v_base_rare := public._chikarian_rarity(v_base.card_key);
  v_mat_rare  := public._chikarian_rarity(v_mat.card_key);
  v_is_sp := (v_base_rare = 'sp');

  -- 素材適合（canon-02 §6）
  if v_is_sp then
    -- SP: 同名(card_key一致)・同★のSPのみ素材可
    if v_mat.card_key <> v_base.card_key then raise exception 'SP_MATERIAL_MISMATCH'; end if;
  else
    if v_mat_rare = 'sp' then raise exception 'SP_NOT_MATERIAL'; end if;      -- SPは通常素材に使えない
    if v_mat_rare <> v_base_rare then raise exception 'RARITY_MISMATCH'; end if;
  end if;
  if v_mat.star <> v_base.star then raise exception 'STAR_MISMATCH'; end if;

  -- コスト: メダル 500×(★+1)（据え置き）
  v_cost := 500 * (v_base.star + 1);

  -- ---- 成功率（canon-04 §2・素材Lv依存）------------------------------------
  -- 素材レアの Lv 上限（_chikarian_lv_from_exp と同一の対応表）。
  -- RARITY_MISMATCH/SP_MATERIAL_MISMATCH 後なので素材レア＝適合レア。
  v_mat_cap := case v_mat_rare
                 when 'n'   then 30
                 when 'r'   then 40
                 when 'sr'  then 50
                 when 'ssr' then 60
                 when 'sp'  then 50
                 else 60
               end;
  -- 素材Lv は累積 exp から導出（lv 列は参照しない＝真値の exp が正）。
  v_mat_lv := public._chikarian_lv_from_exp(v_mat.exp, v_mat_cap);
  -- clamp( (20 − 10★) + 80×(素材Lv−1)/(素材Lv上限−1) + 10×恩寵石 , 0, 100 )
  -- 80.0 で numeric 除算を強制（整数除算による切り捨てを防止）。cap−1≥29 で 0除算なし。
  v_rate := least(100::numeric,
              greatest(0::numeric,
                (20 - 10 * v_base.star)
                + 80.0 * (v_mat_lv - 1) / (v_mat_cap - 1)
                + 10 * coalesce(p_hoshou_n, 0)
              ));
  -- -------------------------------------------------------------------------

  -- 残高ロック・検証
  select medal, hoshou_stone into v_medal_have, v_hoshou_have
    from public.profiles where id = v_uid for update;
  if v_medal_have  < v_cost                 then raise exception 'INSUFFICIENT_MEDAL';  end if;
  if v_hoshou_have < coalesce(p_hoshou_n,0) then raise exception 'INSUFFICIENT_HOSHOU'; end if;

  -- 抽選（サーバ内乱数）
  v_success  := (random() * 100 < v_rate);
  v_new_star := v_base.star + (case when v_success then 1 else 0 end);

  -- 消費（成否によらずメダル・恩寵石・素材は消費）
  update public.profiles
     set medal = medal - v_cost,
         hoshou_stone = hoshou_stone - coalesce(p_hoshou_n, 0)
   where id = v_uid;

  -- 素材カード消滅（スキル行も明示削除）
  delete from public.card_skills where card_id = p_mat_id;
  delete from public.cards where id = p_mat_id and user_id = v_uid;

  -- 成功なら★+1（失敗は本体不変＝★下がらない）
  if v_success then
    update public.cards set star = v_new_star where id = p_base_id;
  end if;

  perform public._chikarian_mission_bump(v_uid, 'kyoka', 1);   -- ★強化ミッション（挑戦=1・成否不問）

  return jsonb_build_object(
    'success',          v_success,
    'success_rate',     v_rate,
    'new_star',         v_new_star,
    'mat_lv',           v_mat_lv,       -- 追加: 成功率の根拠（素材の現Lv）
    'mat_lv_cap',       v_mat_cap,      -- 追加: 素材レアのLv上限
    'medal_spent',      v_cost,
    'hoshou_spent',     coalesce(p_hoshou_n, 0),
    'medal_remaining',  v_medal_have  - v_cost,
    'hoshou_remaining', v_hoshou_have - coalesce(p_hoshou_n, 0)
  );
end;
$$;

revoke all on function public.do_kyoka(uuid, uuid, integer) from public, anon;
grant execute on function public.do_kyoka(uuid, uuid, integer) to authenticated;

-- ===== do_skill_rensei（0021）＋ CARD_IN_TANSAKU =====
create or replace function public.do_skill_rensei(
  p_card_id uuid,
  p_slot    integer,
  p_color   text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_skill_key text;
  v_lv   integer;
  v_rare text;
  v_upg  boolean;
  v_base_c integer;
  v_mult numeric;
  v_cost integer;
  v_rate numeric;
  v_blue integer; v_red integer; v_rainbow integer;
  v_have integer;
  v_success boolean;
  v_new_lv integer;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_color not in ('blue','red','rainbow') then raise exception 'INVALID_COLOR'; end if;

  perform 1 from public.cards where id = p_card_id and user_id = v_uid for update;
  if not found then raise exception 'CARD_NOT_OWNED'; end if;

  -- 占有ロック：探索中カードはスキル錬成不可（canon-06 §3-4）
  perform public._chikarian_assert_not_in_tansaku(p_card_id);

  select cs.skill_key, cs.skill_lv, sm.rarity, sm.lv_upgradable
    into v_skill_key, v_lv, v_rare, v_upg
    from public.card_skills cs
    join public.skill_master sm on sm.skill_key = cs.skill_key
   where cs.card_id = p_card_id and cs.slot = p_slot;
  if not found then raise exception 'SKILL_NOT_FOUND'; end if;
  if not v_upg then raise exception 'NOT_UPGRADABLE'; end if;

  v_base_c := case
    when v_lv <= 2  then 1
    when v_lv <= 4  then 2
    when v_lv <= 6  then 3
    when v_lv <= 8  then 4
    when v_lv <= 10 then 5
    when v_lv <= 13 then 7
    when v_lv <= 16 then 10
    when v_lv <= 19 then 14
    when v_lv <= 24 then 20
    when v_lv <= 29 then 28
    when v_lv <= 39 then 40
    else round(40 * power(1.4, floor((v_lv - 40) / 10.0) + 1))::int
  end;

  v_mult := case v_rare
    when 'n'   then 2.0
    when 'r'   then 4.4
    when 'sr'  then 8.8
    when 'ssr' then 17.6
    else null
  end;
  if v_mult is null then raise exception 'RARITY_NOT_SUPPORTED'; end if;

  v_cost := ceil(v_base_c * v_mult)::int;
  v_rate := case p_color when 'blue' then 10 when 'red' then 33 else 100 end;

  select crystal_blue, crystal_red, crystal_rainbow
    into v_blue, v_red, v_rainbow
    from public.profiles where id = v_uid for update;

  if p_color = 'blue' then
    v_have := v_blue;
    if v_have < v_cost then raise exception 'INSUFFICIENT_CRYSTAL'; end if;
    update public.profiles set crystal_blue = crystal_blue - v_cost where id = v_uid;
  elsif p_color = 'red' then
    v_have := v_red;
    if v_have < v_cost then raise exception 'INSUFFICIENT_CRYSTAL'; end if;
    update public.profiles set crystal_red = crystal_red - v_cost where id = v_uid;
  else
    v_have := v_rainbow;
    if v_have < v_cost then raise exception 'INSUFFICIENT_CRYSTAL'; end if;
    update public.profiles set crystal_rainbow = crystal_rainbow - v_cost where id = v_uid;
  end if;

  v_success := (random() * 100 < v_rate);
  v_new_lv  := v_lv + (case when v_success then 1 else 0 end);
  if v_success then
    update public.card_skills set skill_lv = v_new_lv
     where card_id = p_card_id and slot = p_slot;
  end if;

  perform public._chikarian_mission_bump(v_uid, 'rensei', 1);  -- 錬成ミッション（挑戦=1・成否不問）

  return jsonb_build_object(
    'success',           v_success,
    'success_rate',      v_rate,
    'color',             p_color,
    'cost',              v_cost,
    'skill_key',         v_skill_key,
    'old_lv',            v_lv,
    'new_lv',            v_new_lv,
    'crystal_remaining', v_have - v_cost
  );
end;
$$;
revoke all on function public.do_skill_rensei(uuid, integer, text) from public, anon;
grant execute on function public.do_skill_rensei(uuid, integer, text) to authenticated;

-- ===== equip_buki（0031）＋ CARD_IN_TANSAKU =====
create or replace function public.equip_buki(
  p_card_id uuid,
  p_quality text,
  p_amount  integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_card record;
  v_rare text;
  v_cap_base numeric; v_cap_max numeric; v_lv_cap integer;
  v_capacity integer;
  v_quality_lv integer;
  v_kajiya_lv integer;
  v_new_cost integer; v_new_atk integer;
  v_old_cost integer;
  v_pool numeric;
  v_refund numeric;
  v_affordable integer;
  v_filled integer;
  v_draw numeric;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_quality not in ('crude','refined','enchanted','holy') then raise exception 'INVALID_QUALITY'; end if;
  if p_amount is null or p_amount < 0 then raise exception 'INVALID_AMOUNT'; end if;

  select * into v_card from public.cards where id = p_card_id and user_id = v_uid for update;
  if not found then raise exception 'CARD_NOT_FOUND'; end if;

  -- 占有ロック：探索中カードは充填（装備）不可（canon-06 §3-4）
  perform public._chikarian_assert_not_in_tansaku(p_card_id);

  v_rare := public._chikarian_rarity(v_card.card_key);
  if v_rare = 'sp' then raise exception 'SP_NO_EQUIP'; end if;

  -- 質の解放確認
  v_quality_lv := case p_quality when 'crude' then 1 when 'refined' then 2 when 'enchanted' then 3 when 'holy' then 4 end;
  select coalesce(max(case quality when 'holy' then 4 when 'enchanted' then 3 when 'refined' then 2 else 1 end), 1)
    into v_kajiya_lv
    from public.kajiya_orders where user_id = v_uid and claimed = true;
  if v_kajiya_lv < v_quality_lv then raise exception 'QUALITY_LOCKED'; end if;

  -- 充填量（枠上限・レア別）
  case v_rare
    when 'n'   then v_cap_base := 80;  v_cap_max := 240; v_lv_cap := 30;
    when 'r'   then v_cap_base := 120; v_cap_max := 400; v_lv_cap := 40;
    when 'sr'  then v_cap_base := 160; v_cap_max := 560; v_lv_cap := 50;
    when 'ssr' then v_cap_base := 200; v_cap_max := 800; v_lv_cap := 60;
    else raise exception 'RARITY_NOT_SUPPORTED';
  end case;
  v_capacity := floor(
    v_cap_base + (v_cap_max - v_cap_base)
                 * (least(v_card.lv, v_lv_cap) - 1)::numeric / (v_lv_cap - 1)
  )::int;

  v_new_cost := case p_quality when 'crude' then 1 when 'refined' then 3 when 'enchanted' then 9 when 'holy' then 27 end;
  v_new_atk  := case p_quality when 'crude' then 10 when 'refined' then 15 when 'enchanted' then 22 when 'holy' then 34 end;

  -- 練気殿プールを精算
  perform public._chikarian_renkiden_settle(v_uid);
  select buki_stored into v_pool from public.renkiden where user_id = v_uid for update;

  -- 現在込めている武気を返却（非破壊）
  v_old_cost := case v_card.quality
                  when 'crude' then 1 when 'refined' then 3
                  when 'enchanted' then 9 when 'holy' then 27 else 0 end;
  v_refund := coalesce(v_card.loaded_buki, 0) * v_old_cost;
  v_pool := v_pool + v_refund;     -- 返却後の実効プール

  -- 込めた武気（枠）
  v_affordable := floor(v_pool / v_new_cost)::int;
  v_filled := greatest(0, least(p_amount, v_capacity, v_affordable));
  v_draw := v_filled::numeric * v_new_cost;

  -- プール確定（DB値 + 返却 - 引出）
  update public.renkiden
     set buki_stored = buki_stored + v_refund - v_draw
   where user_id = v_uid;

  -- カード更新
  update public.cards
     set quality = p_quality, loaded_buki = v_filled
   where id = p_card_id;

  return jsonb_build_object(
    'card_id',        p_card_id,
    'quality',        p_quality,
    'loaded_buki',    v_filled,                 -- 込めた武気（枠）
    'capacity',       v_capacity,
    'soubi_kou',      v_filled * v_new_atk,     -- 装備項（発動前・表示用）
    'buki_drawn',     v_draw,
    'buki_refunded',  v_refund,
    'pool_remaining', v_pool - v_draw
  );
end;
$$;
revoke all on function public.equip_buki(uuid, text, integer) from public, anon;
grant execute on function public.equip_buki(uuid, text, integer) to authenticated;
