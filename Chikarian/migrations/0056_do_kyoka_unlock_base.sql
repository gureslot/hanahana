-- Chikarian migration 0056: ★強化はロック中の本体でも可（do_kyoka から BASE_LOCKED を除去）
-- 出典/前提: 0034 の do_kyoka を土台に再定義（最新版）。★強化は本体を消費せず、消えるのは素材のみ。
--           よって本体ロックは強化を妨げない（誤消費の保護対象は素材＝MATERIAL_LOCKED は維持）。
-- 変更点: 「if v_base.locked then raise exception 'BASE_LOCKED'; end if;」の1行のみ削除。他は 0034 と同一。

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

  -- ★強化は本体を消費しない（消えるのは素材のみ）ため、本体ロックは強化を妨げない（BASE_LOCKED 撤去）。
  -- 素材はロック中なら従来どおり保護。
  if v_mat.locked then raise exception 'MATERIAL_LOCKED'; end if;

  -- 占有ロック：探索中カードは★強化不可（canon-06 §3-4）
  perform public._chikarian_assert_not_in_tansaku(p_base_id);
  perform public._chikarian_assert_not_in_tansaku(p_mat_id);

  v_base_rare := public._chikarian_rarity(v_base.card_key);
  v_mat_rare  := public._chikarian_rarity(v_mat.card_key);
  v_is_sp := (v_base_rare = 'sp');

  -- 素材適合（canon-02 §6）
  if v_is_sp then
    if v_mat.card_key <> v_base.card_key then raise exception 'SP_MATERIAL_MISMATCH'; end if;
  else
    if v_mat_rare = 'sp' then raise exception 'SP_NOT_MATERIAL'; end if;
    if v_mat_rare <> v_base_rare then raise exception 'RARITY_MISMATCH'; end if;
  end if;
  if v_mat.star <> v_base.star then raise exception 'STAR_MISMATCH'; end if;

  -- コスト: メダル 500×(★+1)（据え置き）
  v_cost := 500 * (v_base.star + 1);

  -- ---- 成功率（canon-04 §2・素材Lv依存）------------------------------------
  v_mat_cap := case v_mat_rare
                 when 'n'   then 30
                 when 'r'   then 40
                 when 'sr'  then 50
                 when 'ssr' then 60
                 when 'sp'  then 50
                 else 60
               end;
  v_mat_lv := public._chikarian_lv_from_exp(v_mat.exp, v_mat_cap);
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

  perform public._chikarian_mission_bump(v_uid, 'kyoka', 1);

  return jsonb_build_object(
    'success',          v_success,
    'success_rate',     v_rate,
    'new_star',         v_new_star,
    'mat_lv',           v_mat_lv,
    'mat_lv_cap',       v_mat_cap,
    'medal_spent',      v_cost,
    'hoshou_spent',     coalesce(p_hoshou_n, 0),
    'medal_remaining',  v_medal_have  - v_cost,
    'hoshou_remaining', v_hoshou_have - coalesce(p_hoshou_n, 0)
  );
end;
$$;

revoke all on function public.do_kyoka(uuid, uuid, integer) from public, anon;
grant execute on function public.do_kyoka(uuid, uuid, integer) to authenticated;
