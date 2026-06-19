-- ============================================================
-- Chikarian migration 0014: do_skill_rensei (スキル錬成 / skill level-up via crystals)
-- canon: skill-kyoka-tenni-spec §1, chikarian-crystal-exchange §4 (06-14), skill-db-spec
-- 規約は 0012 に準拠。
--
-- 仕様:
--   1挑戦 = 1色を C 個消費・混色不可。成功率は色固定（青10 / 赤33 / 虹100 %）。
--   失敗 = C個消失・Lv据置。伸びるのは効果量のみ（skill_master 側が Lv でスケール）。
--   C = ceil( 基礎個数(現Lv) × レア倍率 )。
--     基礎個数カーブ = skill-kyoka §1。
--     レア倍率（06-14・crystal-exchange §4 が §1 を上書き）= N2 / R4.4 / SR8.8。
--   ★SSR倍率は未確定 → 暫定 ×17.6（素材コスト比 1:2:4:8 ×2.2 の継続）。要確定。
--   lv_upgradable=false（SP専用・天啓 等）は対象外。
--   ロック中カードでも錬成可（消費は本体でなくクリスタル）。
--
-- 前提: profiles 列 crystal_blue / crystal_red / crystal_rainbow、skill_master（適用済）。
-- ============================================================

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

  -- カード所有確認（ロック）
  perform 1 from public.cards where id = p_card_id and user_id = v_uid for update;
  if not found then raise exception 'CARD_NOT_OWNED'; end if;

  -- 対象スキル＋マスタ情報
  select cs.skill_key, cs.skill_lv, sm.rarity, sm.lv_upgradable
    into v_skill_key, v_lv, v_rare, v_upg
    from public.card_skills cs
    join public.skill_master sm on sm.skill_key = cs.skill_key
   where cs.card_id = p_card_id and cs.slot = p_slot;
  if not found then raise exception 'SKILL_NOT_FOUND'; end if;
  if not v_upg then raise exception 'NOT_UPGRADABLE'; end if;

  -- 基礎個数カーブ（現Lv→次・skill-kyoka §1）
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
    else round(40 * power(1.4, floor((v_lv - 40) / 10.0) + 1))::int  -- 40+ は1帯(幅10)ごと×1.4（仮）
  end;

  -- レア倍率（06-14）
  v_mult := case v_rare
    when 'n'   then 2.0
    when 'r'   then 4.4
    when 'sr'  then 8.8
    when 'ssr' then 17.6     -- 仮・要確定
    else null
  end;
  if v_mult is null then raise exception 'RARITY_NOT_SUPPORTED'; end if;  -- sp等

  v_cost := ceil(v_base_c * v_mult)::int;
  v_rate := case p_color when 'blue' then 10 when 'red' then 33 else 100 end;

  -- クリスタル残ロック・検証・消費（成否によらず消費）
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
  else  -- rainbow
    v_have := v_rainbow;
    if v_have < v_cost then raise exception 'INSUFFICIENT_CRYSTAL'; end if;
    update public.profiles set crystal_rainbow = crystal_rainbow - v_cost where id = v_uid;
  end if;

  -- 抽選
  v_success := (random() * 100 < v_rate);
  v_new_lv  := v_lv + (case when v_success then 1 else 0 end);
  if v_success then
    update public.card_skills set skill_lv = v_new_lv
     where card_id = p_card_id and slot = p_slot;
  end if;

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
