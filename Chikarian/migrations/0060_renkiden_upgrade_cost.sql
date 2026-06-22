-- ============================================================
-- Chikarian migration 0060: 練気殿 強化費を逓増へ（upgrade_renkiden 再定義・土台=0015）
-- 変更点（upgrade_renkiden のみ）:
--   強化費 8,000×現Lv → Lv2:3,000／Lv3:5,000／Lv4:8,000／Lv5:12,000（計28,000・canon-06 §5-1・canon-04 §7）。
--   v_lv=現Lv（昇格前）。v_lv 1→Lv2:3,000 / 2→Lv3:5,000 / 3→Lv4:8,000 / 4→Lv5:12,000。
--   ※ Lv5超（v_lv≥5・canon未指定の設計範囲外）は従来式 8,000×Lv を温存（挙動を変えない）。
--   他（_chikarian_renkiden_settle／レート0.1×Lv／保管上限1000+1500×(Lv-1)／昇格処理／返り値）は 0015 と同一。
--   本ファイルは upgrade_renkiden のみ再定義（collect/invest/instant/settle は無改変）。
-- ============================================================

create or replace function public.upgrade_renkiden()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_lv integer; v_cost bigint; v_medal_have bigint;
  v_new_lv integer; v_buki numeric; v_cap numeric;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  perform public._chikarian_renkiden_settle(v_uid);

  select lv into v_lv from public.renkiden where user_id = v_uid for update;

  -- 強化費（canon-06 §5-1・逓増）: 現Lv→次Lv。Lv5超は canon未指定のため従来式 8,000×Lv を温存。
  v_cost := (case v_lv
               when 1 then 3000      -- →Lv2
               when 2 then 5000      -- →Lv3
               when 3 then 8000      -- →Lv4
               when 4 then 12000     -- →Lv5
               else 8000 * v_lv      -- Lv5超（設計範囲外）＝従来式温存
             end)::bigint;

  select medal into v_medal_have from public.profiles where id = v_uid for update;
  if v_medal_have < v_cost then raise exception 'INSUFFICIENT_MEDAL'; end if;

  update public.profiles set medal = medal - v_cost where id = v_uid;
  update public.renkiden set lv = lv + 1 where user_id = v_uid;

  select lv, buki_stored into v_new_lv, v_buki from public.renkiden where user_id = v_uid;
  v_cap := 1000 + 1500 * (v_new_lv - 1);
  return jsonb_build_object(
    'new_lv', v_new_lv, 'cost', v_cost, 'cap', v_cap, 'rate_per_sec', 0.1 * v_new_lv,
    'buki_stored', v_buki, 'medal_remaining', v_medal_have - v_cost
  );
end;
$$;
revoke all on function public.upgrade_renkiden() from public, anon;
grant execute on function public.upgrade_renkiden() to authenticated;
