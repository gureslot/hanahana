-- ============================================================
-- Chikarian migration 0031: equip_buki ギア値更新（canon-04 §3 / canon-07 §3「要追従」）
--   枠コスト  1/2/4/8  → 1/3/9/27（武気↔枠数の変換。v_new_cost と v_old_cost の2箇所）
--   枠攻撃力 7/15/33/73 → 10/15/22/34（ここは表示 soubi_kou 用。実戦の装備項は do_boss_battle の qatk）
--   ★ギアは2RPCに跨る：実戦 qatk は別マイグレーション 0032（do_boss_battle）で更新＝0031と同時適用。
--   ※既存カードの loaded_buki(枠数)は不変。枠コスト変更後の初回再充填で「旧条件返却→新条件引直し」が走る
--     （旧質で充填済みは返却が新コスト基準＝微差。dev前提で許容・canon「定数は後差し替え安」）。元は 0017。本ファイルで上書き。
-- ---- 以下は 0017 由来のモデル説明 ----
-- equip_buki (装備充填)
-- canon: balance-chikarian-2026-06-12 §2-1/§2-3/§2-4, supabase-spec §2
-- 規約は 0012 に準拠。0015(練気殿)・0016(鍛冶屋) 適用後に流す。
--
-- モデル（戦国IXA式）:
--   loaded_buki = 込めた武気 = 「枠数」（do_boss_battle が 装備項 = loaded_buki×枠攻撃力 で使用）。
--   充填量(枠上限) = 基礎 + (MAX-基礎)×(Lv-1)/(Lv上限-1)  ［レア別］
--     N 80/240/30 ・ R 120/400/40 ・ SR 160/560/50 ・ SSR 200/800/60。SP は装備なし。
--   質の枠コスト/枠攻撃力: crude 1/10 ・ refined 3/15 ・ enchanted 9/22 ・ holy 27/34。
--   込めた武気(枠) = min( 要求 , 充填量 , floor(プール ÷ 枠コスト) )。
--   raw 武気の出し入れ: 込めた枠 × 枠コスト を renkiden.buki_stored から増減。
--   質変更/再充填は非破壊: 現在込めている武気を一旦プールへ返却→新条件で引き直す。
--   解放済みの質のみ装備可（鍛冶屋Lv = claim済みの最高質）。
--   p_amount = 込めた武気（枠数）の希望値。p_amount=0 で実質アンロード。
-- ============================================================

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
