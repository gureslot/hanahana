-- ============================================================
-- Chikarian migration 0025: do_kyoka ★成功率を「素材Lv依存」へ更新
--   canon-04 §2 / canon-07 §3「要追従」（★成功率＝0012 旧式 → 素材Lv依存）
--
--   旧（廃止）: 成功率 = clamp(90 − 5★, 30, 100) + 10×恩寵石          ← Lv非依存
--   新（canon）: 成功率 = clamp( (20 − 10★)
--                              + 80×(素材Lv−1)/(素材Lv上限−1)
--                              + 10×恩寵石 , 0, 100 )
--       ★        = 強化対象（base）の現★
--       素材Lv    = 素材カード（mat）の現Lv（denormalized lv 列ではなく
--                   真値の累積 exp から _chikarian_lv_from_exp で導出）
--       素材Lv上限 = 素材レアの Lv 上限（N30 / R40 / SR50 / SSR60 / SP50）
--                   ＝ use_exp_book / collect_tansaku の cap と同一対応表
--
--   早見（恩寵石0・Lv1底A=20／素材MAX上限=100−10★・canon-04 §2 表と一致）:
--     ★0: 底20 / MAX100      ★1: 底10 / MAX90
--     ★2: 底 0 / MAX80       ★3: 底 0 / MAX70
--   素材MAXで100%へ要る恩寵石: ★0=0 / ★1=1 / ★2=2 / ★3=3
--
--   ※ 本体ロジック・素材適合・コスト(500×(★+1))・成否問わず素材消費・
--      ミッション bump(0021) は据え置き。変更は v_rate 算出のみ（＋mat_lv 導出と返却追加）。
--   ※ これは do_kyoka の最新版 0021（mission hook 付き）を base に成功率式だけ
--      canon-04 §2 へ差し替えたもの。0020/0021 適用後に流すこと
--      （_chikarian_mission_bump / _chikarian_rarity / _chikarian_lv_from_exp が前提）。
--   規約は 0012 に準拠（security definer・FOR UPDATE・RAISE EXCEPTION '<UPPER_CODE>'）。
--
--   クライアント追従: 不要（index.html / chikarian-api.js は do_kyoka を呼んで
--      返り値 success_rate を表示するのみ。旧式のローカル計算は存在しない）。
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
