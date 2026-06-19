-- ============================================================
-- Chikarian migration 0021: ミッション hook（0012 do_kyoka / 0014 do_skill_rensei の再発行）
-- 目的: ★強化・錬成の「挑戦回数」を missions.progress に積むため、各関数の末尾に
--       _chikarian_mission_bump(...) を1行追加（成否によらず＝挑戦1回）。
-- 0020 適用後に流す（_chikarian_mission_bump が必要）。本体ロジックは 0012/0014 と同一。
-- ============================================================

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
  v_cost  integer;
  v_rate  numeric;
  v_medal_have  bigint;
  v_hoshou_have integer;
  v_success boolean;
  v_new_star integer;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_base_id = p_mat_id then raise exception 'SAME_CARD'; end if;
  if coalesce(p_hoshou_n, 0) < 0 then raise exception 'INVALID_HOSHOU'; end if;

  select * into v_base from public.cards where id = p_base_id and user_id = v_uid for update;
  if not found then raise exception 'BASE_NOT_FOUND'; end if;
  select * into v_mat from public.cards where id = p_mat_id and user_id = v_uid for update;
  if not found then raise exception 'MATERIAL_NOT_FOUND'; end if;

  if v_base.locked then raise exception 'BASE_LOCKED'; end if;
  if v_mat.locked  then raise exception 'MATERIAL_LOCKED'; end if;

  v_base_rare := public._chikarian_rarity(v_base.card_key);
  v_mat_rare  := public._chikarian_rarity(v_mat.card_key);
  v_is_sp := (v_base_rare = 'sp');

  if v_is_sp then
    if v_mat.card_key <> v_base.card_key then raise exception 'SP_MATERIAL_MISMATCH'; end if;
  else
    if v_mat_rare = 'sp' then raise exception 'SP_NOT_MATERIAL'; end if;
    if v_mat_rare <> v_base_rare then raise exception 'RARITY_MISMATCH'; end if;
  end if;
  if v_mat.star <> v_base.star then raise exception 'STAR_MISMATCH'; end if;

  v_cost := 500 * (v_base.star + 1);
  v_rate := least(100, greatest(30, 90 - 5 * v_base.star) + 10 * coalesce(p_hoshou_n, 0));

  select medal, hoshou_stone into v_medal_have, v_hoshou_have
    from public.profiles where id = v_uid for update;
  if v_medal_have  < v_cost                 then raise exception 'INSUFFICIENT_MEDAL';  end if;
  if v_hoshou_have < coalesce(p_hoshou_n,0) then raise exception 'INSUFFICIENT_HOSHOU'; end if;

  v_success  := (random() * 100 < v_rate);
  v_new_star := v_base.star + (case when v_success then 1 else 0 end);

  update public.profiles
     set medal = medal - v_cost,
         hoshou_stone = hoshou_stone - coalesce(p_hoshou_n, 0)
   where id = v_uid;

  delete from public.card_skills where card_id = p_mat_id;
  delete from public.cards where id = p_mat_id and user_id = v_uid;

  if v_success then
    update public.cards set star = v_new_star where id = p_base_id;
  end if;

  perform public._chikarian_mission_bump(v_uid, 'kyoka', 1);   -- ★強化ミッション（挑戦=1・成否不問）

  return jsonb_build_object(
    'success',          v_success,
    'success_rate',     v_rate,
    'new_star',         v_new_star,
    'medal_spent',      v_cost,
    'hoshou_spent',     coalesce(p_hoshou_n, 0),
    'medal_remaining',  v_medal_have  - v_cost,
    'hoshou_remaining', v_hoshou_have - coalesce(p_hoshou_n, 0)
  );
end;
$$;
revoke all on function public.do_kyoka(uuid, uuid, integer) from public, anon;
grant execute on function public.do_kyoka(uuid, uuid, integer) to authenticated;


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
