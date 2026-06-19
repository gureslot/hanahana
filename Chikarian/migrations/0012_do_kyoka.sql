-- ============================================================
-- Chikarian migration 0012: do_kyoka (★強化 / card star enhancement)
-- canon: balance-chikarian-2026-06-12 §5, supabase-spec §2
--
-- このファイルが 0012+ の規約を確立する:
--   * security definer + set search_path。EXECUTE は authenticated のみに付与
--   * 認証は auth.uid()。エラーは RAISE EXCEPTION '<UPPER_CODE>'
--   * 資産更新はサーバ内のみ。対象行は FOR UPDATE でロック。戻り値は jsonb
--
-- 前提（適用済み 0001-0011 と異なれば調整してください）:
--   * profiles 列: medal, hoshou_stone（supabase-spec §1）
--   * cards 列  : user_id, card_key, star, locked（supabase-spec §1）
--   * card_key の末尾トークン = レア（chara_..._{n|r|sr|ssr} / chara_{name}_sp）＝cards.md
--   * cards 削除時に card_skills が ON DELETE CASCADE でない前提 → 明示削除する
-- ============================================================

-- レア判定ヘルパ（card_key の末尾トークン）。交換所など以降でも再利用。
create or replace function public._chikarian_rarity(p_card_key text)
returns text
language sql
immutable
as $$
  select lower(split_part(p_card_key, '_', -1));
$$;

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
  select * into v_base from public.cards
    where id = p_base_id and user_id = v_uid for update;
  if not found then raise exception 'BASE_NOT_FOUND'; end if;

  select * into v_mat from public.cards
    where id = p_mat_id and user_id = v_uid for update;
  if not found then raise exception 'MATERIAL_NOT_FOUND'; end if;

  if v_base.locked then raise exception 'BASE_LOCKED'; end if;
  if v_mat.locked  then raise exception 'MATERIAL_LOCKED'; end if;

  v_base_rare := public._chikarian_rarity(v_base.card_key);
  v_mat_rare  := public._chikarian_rarity(v_mat.card_key);
  v_is_sp := (v_base_rare = 'sp');

  -- 素材適合（balance §5）
  if v_is_sp then
    -- SP: 同名(card_key一致)・同★のSPのみ素材可
    if v_mat.card_key <> v_base.card_key then raise exception 'SP_MATERIAL_MISMATCH'; end if;
  else
    if v_mat_rare = 'sp' then raise exception 'SP_NOT_MATERIAL'; end if;  -- SPは通常素材に使えない
    if v_mat_rare <> v_base_rare then raise exception 'RARITY_MISMATCH'; end if;
  end if;
  if v_mat.star <> v_base.star then raise exception 'STAR_MISMATCH'; end if;

  -- コスト・成功率: メダル 500×(★+1) ／ 成功 min(100, max(30,90-5★)+10×保証石)
  v_cost := 500 * (v_base.star + 1);
  v_rate := least(100, greatest(30, 90 - 5 * v_base.star) + 10 * coalesce(p_hoshou_n, 0));

  -- 残高ロック・検証
  select medal, hoshou_stone into v_medal_have, v_hoshou_have
    from public.profiles where id = v_uid for update;
  if v_medal_have  < v_cost              then raise exception 'INSUFFICIENT_MEDAL';  end if;
  if v_hoshou_have < coalesce(p_hoshou_n,0) then raise exception 'INSUFFICIENT_HOSHOU'; end if;

  -- 抽選（サーバ内乱数）
  v_success  := (random() * 100 < v_rate);
  v_new_star := v_base.star + (case when v_success then 1 else 0 end);

  -- 消費（成否によらずメダル・保証石・素材は消費）
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
