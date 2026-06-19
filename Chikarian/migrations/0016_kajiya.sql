-- ============================================================
-- Chikarian migration 0016: 鍛冶屋 (kajiya) — place_kajiya_order / claim_kajiya
-- canon: balance-chikarian-2026-06-12 §11/§2-1, supabase-spec §1(table7)/§2
-- 規約は 0012 に準拠。kajiya_orders テーブルは 0001 で作成済みの前提。
--
-- 仕様:
--   装備の質: crude(粗製/初期) → refined(精製) → enchanted(魔装) → holy(聖装)。
--   Lv 対応: crude=1 / refined=2 / enchanted=3 / holy=4。crude は初期解放（依頼不可）。
--   段階解放: 直前の質を claim 済みであること（飛ばし不可）。
--   依頼制: メダル支払い → 作業時間経過 → claim で解放。1件ずつ（未claim行があれば新規拒否）。
--   費用: 15,000 × 現Lv（精製=15,000 / 魔装=30,000 / 聖装=45,000。§13と整合）。
--   作業時間: 精製24h / 魔装36h / 聖装48h。即時完成の課金ショートカットは無し。
--   現Lv = claim 済みの最高質から導出（無ければ crude=1）。
-- ============================================================

create or replace function public.place_kajiya_order(p_quality text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_target_lv integer;
  v_hours integer;
  v_current_lv integer;
  v_cost bigint;
  v_medal_have bigint;
  v_done_at timestamptz;
  v_order_id uuid;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_quality not in ('refined','enchanted','holy') then raise exception 'INVALID_QUALITY'; end if;

  v_target_lv := case p_quality when 'refined' then 2 when 'enchanted' then 3 when 'holy' then 4 end;
  v_hours     := case p_quality when 'refined' then 24 when 'enchanted' then 36 when 'holy' then 48 end;

  -- 1件ずつ: 未claim の依頼があれば拒否
  perform 1 from public.kajiya_orders where user_id = v_uid and claimed = false;
  if found then raise exception 'ORDER_IN_PROGRESS'; end if;

  -- 現Lv（claim済みの最高質）
  select coalesce(max(case quality
                        when 'holy' then 4 when 'enchanted' then 3
                        when 'refined' then 2 else 1 end), 1)
    into v_current_lv
    from public.kajiya_orders where user_id = v_uid and claimed = true;

  if v_current_lv >= v_target_lv then raise exception 'ALREADY_UNLOCKED'; end if;
  if v_current_lv <> v_target_lv - 1 then raise exception 'PREREQUISITE_MISSING'; end if;

  v_cost := 15000::bigint * v_current_lv;

  select medal into v_medal_have from public.profiles where id = v_uid for update;
  if v_medal_have < v_cost then raise exception 'INSUFFICIENT_MEDAL'; end if;

  update public.profiles set medal = medal - v_cost where id = v_uid;

  v_done_at := now() + make_interval(hours => v_hours);
  insert into public.kajiya_orders (user_id, quality, done_at, claimed)
    values (v_uid, p_quality, v_done_at, false)
    returning id into v_order_id;

  return jsonb_build_object(
    'order_id', v_order_id, 'quality', p_quality,
    'done_at', v_done_at, 'work_hours', v_hours,
    'cost', v_cost, 'medal_remaining', v_medal_have - v_cost
  );
end;
$$;
revoke all on function public.place_kajiya_order(text) from public, anon;
grant execute on function public.place_kajiya_order(text) to authenticated;

create or replace function public.claim_kajiya(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_order record;
  v_new_lv integer;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select * into v_order from public.kajiya_orders
    where id = p_order_id and user_id = v_uid for update;
  if not found then raise exception 'ORDER_NOT_FOUND'; end if;
  if v_order.claimed then raise exception 'ALREADY_CLAIMED'; end if;
  if now() < v_order.done_at then raise exception 'NOT_READY'; end if;

  update public.kajiya_orders set claimed = true where id = p_order_id;

  v_new_lv := case v_order.quality
                when 'holy' then 4 when 'enchanted' then 3
                when 'refined' then 2 else 1 end;

  return jsonb_build_object(
    'order_id', p_order_id, 'quality', v_order.quality,
    'unlocked', true, 'kajiya_lv', v_new_lv
  );
end;
$$;
revoke all on function public.claim_kajiya(uuid) from public, anon;
grant execute on function public.claim_kajiya(uuid) to authenticated;
