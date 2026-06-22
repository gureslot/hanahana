-- ============================================================
-- Chikarian migration 0069: use_exp_book ＝ 既定は「最大を超えない範囲だけ消費（無駄ゼロ）」、
--                            p_allow_overshoot=true のときだけ最後の1冊の超過を許して最大到達。
--   基底＝0068（さらに精緻化）。0068 は「最大到達に要る最小冊数」を消費＝最後の1冊で最大990EXP無駄。
--   本修正：
--     - 既定(p_allow_overshoot=false)：最大累積を超えずに入る冊数 v_full のみ消費（EXPの無駄ゼロ）。
--       要求が v_full を超える＆端数(remainder)が残るなら、超過分は消費せず would_overshoot=true を返す
--       （＝最大到達には1冊の超過が必要。クライアントが「超過分は返却されません」確認を出す）。
--     - p_allow_overshoot=true：最後の1冊の超過を許可し最大到達まで消費（v_needed＝ceil）。EXPは最大でクランプ。
--   EXPモデル（0018）：cards.exp は累積。Lv=cap の累積EXP ＝ 10×cap×(cap−1)。本EXP 小10/中50/大200/特大1000。
--   ※3引数版を drop し 4引数版に統一（p_allow_overshoot は default false＝3引数呼びも従来名で解決）。
--   前提：0018 適用済み。0068 を適用済みでも未適用でも、本ファイルが use_exp_book を完全再定義＝最終状態は同一。
-- ============================================================

drop function if exists public.use_exp_book(uuid, text, integer);

create or replace function public.use_exp_book(
  p_card_id uuid,
  p_size    text,
  p_count   integer default 1,
  p_allow_overshoot boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_card record;
  v_rare text; v_cap integer;
  v_per integer;
  v_bs integer; v_bm integer; v_bl integer; v_bxl integer; v_have integer;
  v_cur integer; v_max_exp integer; v_gap integer;
  v_full integer; v_remainder integer; v_needed integer;
  v_cap_books integer; v_used integer;
  v_would_overshoot boolean; v_waste integer;
  v_new_exp integer; v_new_lv integer;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_size not in ('s','m','l','xl') then raise exception 'INVALID_SIZE'; end if;
  if p_count is null or p_count <= 0 then raise exception 'INVALID_COUNT'; end if;

  select * into v_card from public.cards where id = p_card_id and user_id = v_uid for update;
  if not found then raise exception 'CARD_NOT_FOUND'; end if;

  v_per  := case p_size when 's' then 10 when 'm' then 50 when 'l' then 200 when 'xl' then 1000 end;
  v_rare := public._chikarian_rarity(v_card.card_key);
  v_cap  := case v_rare when 'n' then 30 when 'r' then 40 when 'sr' then 50 when 'ssr' then 60 when 'sp' then 50 else 60 end;

  v_cur     := coalesce(v_card.exp, 0);
  v_max_exp := 10 * v_cap * (v_cap - 1);                 -- Lv=cap（最大）の累積EXP
  if v_cur >= v_max_exp then raise exception 'ALREADY_MAX_LEVEL'; end if;

  v_gap       := v_max_exp - v_cur;
  v_full      := floor(v_gap::numeric / v_per)::int;     -- 最大を超えずに入る冊数（無駄ゼロ）
  v_remainder := v_gap - v_full * v_per;                 -- >0 なら最後の1冊は超過
  v_needed    := v_full + (case when v_remainder > 0 then 1 else 0 end);  -- 最大到達に要る最小冊数
  v_waste     := case when v_remainder > 0 then v_per - v_remainder else 0 end;  -- 超過1冊で捨てるEXP

  -- 所持取得（行ロック）
  select exp_book_s, exp_book_m, exp_book_l, exp_book_xl
    into v_bs, v_bm, v_bl, v_bxl
    from public.profiles where id = v_uid for update;
  v_have := case p_size when 's' then v_bs when 'm' then v_bm when 'l' then v_bl else v_bxl end;

  -- 消費上限：既定=v_full（無駄ゼロ）／許可時=v_needed（最大到達）。要求・所持でさらに頭打ち。
  v_cap_books := case when p_allow_overshoot then v_needed else v_full end;
  v_used := least(p_count, v_cap_books, coalesce(v_have, 0));

  -- 超過確認フラグ：許可なし＆端数あり＆要求が無駄ゼロ枠を超える（＝最大到達には超過1冊が必要）
  v_would_overshoot := (not p_allow_overshoot) and (v_remainder > 0) and (p_count > v_full);

  -- 消費（v_used 冊のみ。v_used=0 のときは消費なし＝would_overshoot をクライアントが確認）
  if v_used > 0 then
    update public.profiles set
      exp_book_s  = exp_book_s  - (case when p_size = 's'  then v_used else 0 end),
      exp_book_m  = exp_book_m  - (case when p_size = 'm'  then v_used else 0 end),
      exp_book_l  = exp_book_l  - (case when p_size = 'l'  then v_used else 0 end),
      exp_book_xl = exp_book_xl - (case when p_size = 'xl' then v_used else 0 end)
    where id = v_uid;
  end if;

  v_new_exp := least(v_cur + v_used * v_per, v_max_exp);  -- 最大でクランプ
  v_new_lv  := public._chikarian_lv_from_exp(v_new_exp, v_cap);
  update public.cards set exp = v_new_exp, lv = v_new_lv where id = p_card_id;

  return jsonb_build_object(
    'card_id',         p_card_id,
    'size',            p_size,
    'count_requested', p_count,
    'count_used',      v_used,
    'count_refunded',  p_count - v_used,        -- 未消費（無駄ゼロ枠を超えた要求分）
    'allow_overshoot', p_allow_overshoot,
    'would_overshoot', v_would_overshoot,       -- true=最大到達に超過1冊が必要（確認を出す）
    'overshoot_waste', v_waste,                 -- 超過1冊で捨てるEXP
    'gap_remaining',   v_max_exp - v_new_exp,   -- 消費後・最大までの残りEXP
    'exp_added',       v_used * v_per,
    'new_exp',         v_new_exp,
    'old_lv',          v_card.lv,
    'new_lv',          v_new_lv,
    'maxed',           (v_new_lv >= v_cap),
    'book_remaining',  coalesce(v_have, 0) - v_used
  );
end;
$$;
revoke all on function public.use_exp_book(uuid, text, integer, boolean) from public, anon;
grant execute on function public.use_exp_book(uuid, text, integer, boolean) to authenticated;
