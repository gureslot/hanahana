-- ============================================================
-- Chikarian migration 0059: 鍛冶屋 精製コスト 15,000→5,000 ＋ cleared_stage 解放ゲート（D-2）
-- 土台: 0016 の place_kajiya_order（最新版）。claim_kajiya は無改変（0016 のまま・本ファイルでは再定義しない）。
-- 変更点（place_kajiya_order のみ）:
--   (1) 精製(refined)の解放コストを 15,000→5,000（canon-06 §5-2）。
--       魔装(enchanted)=30,000・聖装(holy)=45,000 は据え置き（現行 15000×現Lv と同値・canon が再指定していないため温存）。
--   (2) cleared_stage 解放ゲートを追加（canon-06 §5-2 の解放 1→3→5→8）：
--         精製=cleared_stage≥3 / 魔装≥5 / 聖装≥8。未達は STAGE_LOCKED。
--       ※ canon-06 §5-2 の「▼実装（0016）：解放ゲート 0/3/5/8」は 0016 本体に未実装だった（D-2）。本 0059 で実装＝canon に追従。
--   他（1件ずつ ORDER_IN_PROGRESS・段階 prereq・作業時間・返り値・claim_kajiya）は 0016 と同一。
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
  v_req_stage integer;     -- 解放に必要な cleared_stage（D-2・canon-06 §5-2）
  v_cleared integer;
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
  v_req_stage := case p_quality when 'refined' then 3 when 'enchanted' then 5 when 'holy' then 8 end;  -- 1→3→5→8（canon-06 §5-2）

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

  -- 残高＋解放段階をロックして取得
  select medal, coalesce(cleared_stage, 0) into v_medal_have, v_cleared
    from public.profiles where id = v_uid for update;

  -- cleared_stage 解放ゲート（D-2・canon-06 §5-2）：精製≥3 / 魔装≥5 / 聖装≥8
  if v_cleared < v_req_stage then raise exception 'STAGE_LOCKED'; end if;

  -- 費用: 精製=5,000（canon-06 §5-2）／魔装=30,000・聖装=45,000（据え置き＝現行 15000×Lv と同値）
  v_cost := (case p_quality when 'refined' then 5000 when 'enchanted' then 30000 when 'holy' then 45000 end)::bigint;
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
