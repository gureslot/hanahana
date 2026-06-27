-- ============================================================
-- Chikarian migration 0094: 練気殿の強化を「依頼制（時間ゲート）」へ
-- 土台: upgrade_renkiden=0060（逓増コスト）／ collect_renkiden・_chikarian_renkiden_settle=0015。
--
-- 背景: 練気殿の強化が即時レベルアップで「早く進み過ぎる」（報告）。鍛冶屋の質解放（place_kajiya_order /
--       kajiya_orders.done_at＝0016/0059）と同型に、依頼→作業時間→受取（完成）に作り替える。
--       即生産（メダル3倍で武気を即入手）は別RPC＝据え置き＝「急ぎたい人」の救済はそのまま。
--
-- 設計:
--   ・強化は1件ずつ（依頼中の再依頼は UPGRADE_IN_PROGRESS）。鍛冶屋と同型。
--   ・コストは 0060 と同一（→Lv2:3,000 / →Lv3:5,000 / →Lv4:8,000 / →Lv5:12,000 / Lv5超:8,000×Lv）。費用は変えない＝時間ゲートだけ追加。
--   ・作業時間（現Lv→次Lv）: →Lv2:4h / →Lv3:8h / →Lv4:16h / →Lv5:24h / Lv5超:24h。
--   ・依頼中は lv 未変更＝settle は旧レート(0.1×lv)・旧上限(1000+1500×(lv-1))で正しく積む（_chikarian_renkiden_settle は select * でテーブルの lv を読む＝列追加で不変）。
--   ・受取(claim)で「先に旧レートで精算 → lv を確定 → 依頼をクリア」。以後の練成は新レート/新上限。
--   ・既存プレイヤーは現Lvのまま（依頼列は null 既定＝依頼なし）。本変更は今後の強化にのみ適用。
--
-- canon: canon-06 §5-1（練気殿の強化＝即時 → 依頼制に追補）。※canon-06 §5-1 は本ファイルの方式・
--        時間表へ追従させる（canon 反映は保留中の 0089–0092 と同じ納品でまとめて更新）。
--
-- クライアント: 別途 index.html（RenkidenTab）で依頼状態（残り時間）と受取ボタンを表示し
--              claim_renkiden_upgrade を配線（本SQL適用・確認後の別納品）。新エラーコード=
--              UPGRADE_IN_PROGRESS / NO_UPGRADE_PENDING / UPGRADE_NOT_READY を ERR_JA に追加する。
-- ============================================================

-- 1) renkiden に依頼列を追加（冪等・null=依頼なし）
alter table public.renkiden add column if not exists upgrade_to_lv  integer;
alter table public.renkiden add column if not exists upgrade_done_at timestamptz;

-- 2) upgrade_renkiden：即時昇格 → 依頼（メダル消費＋完成時刻を立てる）。土台=0060。
create or replace function public.upgrade_renkiden()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_lv integer; v_cost bigint; v_medal_have bigint;
  v_pending_lv integer;
  v_hours integer; v_done_at timestamptz;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  -- 行確保＆ここまでの練成を確定（旧Lvのレートで精算してから依頼を受ける）
  perform public._chikarian_renkiden_settle(v_uid);

  select lv, upgrade_to_lv into v_lv, v_pending_lv
    from public.renkiden where user_id = v_uid for update;

  -- 1件ずつ（鍛冶屋と同型）。既に依頼中なら不可。
  if v_pending_lv is not null then raise exception 'UPGRADE_IN_PROGRESS'; end if;

  -- 強化費（0060 と同一・逓増）: 現Lv→次Lv。Lv5超は従来式 8,000×Lv を温存。
  v_cost := (case v_lv
               when 1 then 3000      -- →Lv2
               when 2 then 5000      -- →Lv3
               when 3 then 8000      -- →Lv4
               when 4 then 12000     -- →Lv5
               else 8000 * v_lv      -- Lv5超（設計範囲外）＝従来式温存
             end)::bigint;

  -- 作業時間（依頼制・canon-06 §5-1 追補）: 現Lv→次Lv。Lv5超は24h。
  v_hours := (case v_lv
               when 1 then 4         -- →Lv2
               when 2 then 8         -- →Lv3
               when 3 then 16        -- →Lv4
               when 4 then 24        -- →Lv5
               else 24
             end);

  select medal into v_medal_have from public.profiles where id = v_uid for update;
  if v_medal_have < v_cost then raise exception 'INSUFFICIENT_MEDAL'; end if;

  update public.profiles set medal = medal - v_cost where id = v_uid;

  v_done_at := now() + make_interval(hours => v_hours);
  update public.renkiden
     set upgrade_to_lv = v_lv + 1, upgrade_done_at = v_done_at
   where user_id = v_uid;

  return jsonb_build_object(
    'pending', true,
    'upgrade_to_lv', v_lv + 1,
    'done_at', v_done_at,
    'work_hours', v_hours,
    'cost', v_cost,
    'medal_remaining', v_medal_have - v_cost
  );
end;
$$;
revoke all on function public.upgrade_renkiden() from public, anon;
grant execute on function public.upgrade_renkiden() to authenticated;

-- 3) claim_renkiden_upgrade：完成時刻を過ぎた依頼を受け取り、Lvを確定（新設）。
create or replace function public.claim_renkiden_upgrade()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_pending_lv integer; v_done_at timestamptz;
  v_new_lv integer; v_buki numeric; v_fuel numeric; v_cap numeric;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  -- 旧Lvのレート/上限で「今まで」を精算してから昇格（依頼中は lv 未変更＝settle は旧値で正しい）。
  perform public._chikarian_renkiden_settle(v_uid);

  select upgrade_to_lv, upgrade_done_at into v_pending_lv, v_done_at
    from public.renkiden where user_id = v_uid for update;

  if v_pending_lv is null then raise exception 'NO_UPGRADE_PENDING'; end if;
  if now() < v_done_at then raise exception 'UPGRADE_NOT_READY'; end if;

  -- 完成：Lvを上げ、依頼をクリア。以後の練成は新レート/新上限。
  update public.renkiden
     set lv = v_pending_lv, upgrade_to_lv = null, upgrade_done_at = null
   where user_id = v_uid;

  select lv, buki_stored, fuel_medal into v_new_lv, v_buki, v_fuel
    from public.renkiden where user_id = v_uid;
  v_cap := 1000 + 1500 * (v_new_lv - 1);

  return jsonb_build_object(
    'new_lv', v_new_lv, 'cap', v_cap, 'rate_per_sec', 0.1 * v_new_lv,
    'buki_stored', v_buki, 'fuel_medal', v_fuel
  );
end;
$$;
revoke all on function public.claim_renkiden_upgrade() from public, anon;
grant execute on function public.claim_renkiden_upgrade() to authenticated;

-- 4) collect_renkiden：返り値に依頼状態（upgrade_to_lv / upgrade_done_at）を追加。土台=0015。
create or replace function public.collect_renkiden()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_lv integer; v_buki numeric; v_fuel numeric; v_cap numeric;
  v_up_lv integer; v_up_at timestamptz;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  perform public._chikarian_renkiden_settle(v_uid);
  select lv, buki_stored, fuel_medal, upgrade_to_lv, upgrade_done_at
    into v_lv, v_buki, v_fuel, v_up_lv, v_up_at
    from public.renkiden where user_id = v_uid;
  v_cap := 1000 + 1500 * (v_lv - 1);
  return jsonb_build_object(
    'lv', v_lv, 'buki_stored', v_buki, 'fuel_medal', v_fuel,
    'cap', v_cap, 'rate_per_sec', 0.1 * v_lv,
    'upgrade_to_lv', v_up_lv, 'upgrade_done_at', v_up_at
  );
end;
$$;
revoke all on function public.collect_renkiden() from public, anon;
grant execute on function public.collect_renkiden() to authenticated;

-- ============================================================
-- 確認用（任意・適用後）:
--   -- 列が追加されたか
--   select column_name, data_type from information_schema.columns
--   where table_schema='public' and table_name='renkiden'
--     and column_name in ('upgrade_to_lv','upgrade_done_at');
--   -- 依頼→受取の手動テスト（24h待たずに確認したい場合）:
--   --   1. アプリで「強化」を実行（upgrade_to_lv / upgrade_done_at がセットされる）
--   --   2. 下記で完成時刻を過去にして即受取可能にする（自分の行のみ）:
--   --      update public.renkiden set upgrade_done_at = now() - interval '1 minute' where user_id = auth.uid();
--   --   3. アプリで「受け取る」→ lv が上がり依頼列が null に戻る
-- ============================================================
