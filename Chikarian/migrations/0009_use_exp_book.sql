-- =============================================================================
-- 0009 : use_exp_book(card_id, size, count) ＝ 経験の書 使用RPC（特大xl対応）
-- 出典: supabase-spec §2(use_exp_book)/ balance §4(書EXP・必要EXP・Lv上限)
-- 前提: 0008 で profiles.exp_book_xl 追加済み。
-- 実行: SQL Editor に貼って Run（create or replace・再実行可）。
-- 呼び方: supabase.rpc('use_exp_book', { p_card_id: '<uuid>', p_size: 'xl', p_count: 1 })
--
-- 【EXPモデル（balance §4）】
--   書EXP：小=10 / 中=50 / 大=200 / 特大=1000。
--   必要EXP（Lv n→n+1）= 20×n。cards.exp ＝「次のLvへ向けた現在の進捗EXP」。
--   レベルアップ：exp が 20×lv 以上ある間、exp-=20×lv・lv+1 を繰り返す。
--   Lv上限（レア別）：N30 / R40 / SR50 / SSR60 / SP50。
--   上限到達時はクランプ（exp=0・余剰EXPは破棄＝決め打ち。後で上限解放しても resume しない）。
-- =============================================================================

create or replace function public.use_exp_book(p_card_id uuid, p_size text, p_count integer)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid   uuid := auth.uid();
  prof  public.profiles;
  vc    public.cards;
  exp_per int;
  have    int;
  total   bigint;
  v_lv    int;
  lvcap   int;
  is_sp   boolean;
  parts   text[];
  rare    text;
begin
  if uid is null then raise exception 'not authenticated'; end if;
  if p_count is null or p_count < 1 then raise exception 'invalid count'; end if;
  if p_size not in ('s','m','l','xl') then raise exception 'invalid size % (s/m/l/xl)', p_size; end if;

  -- profile 行ロック（書在庫の二重消費防止）
  select * into prof from public.profiles where id = uid for update;
  if not found then raise exception 'profile not initialized'; end if;

  -- カード行ロック（所持確認）
  select * into vc from public.cards where id = p_card_id and user_id = uid for update;
  if not found then raise exception 'card % not owned', p_card_id; end if;

  exp_per := case p_size when 's' then 10 when 'm' then 50 when 'l' then 200 when 'xl' then 1000 end;
  have    := case p_size when 's' then prof.exp_book_s when 'm' then prof.exp_book_m
                         when 'l' then prof.exp_book_l when 'xl' then prof.exp_book_xl end;
  if have < p_count then raise exception 'not enough exp books (%: have % need %)', p_size, have, p_count; end if;

  -- Lv上限（レア別）
  is_sp := vc.card_key like 'chara\_%\_sp' escape '\';
  if is_sp then
    lvcap := 50;
  else
    parts := string_to_array(vc.card_key, '_');
    rare  := parts[array_length(parts,1)];
    lvcap := case rare when 'n' then 30 when 'r' then 40 when 'sr' then 50 when 'ssr' then 60
                       else null end;
    if lvcap is null then raise exception 'unknown rarity in %', vc.card_key; end if;
  end if;

  -- 書を消費
  update public.profiles set
    exp_book_s  = exp_book_s  - (case when p_size = 's'  then p_count else 0 end),
    exp_book_m  = exp_book_m  - (case when p_size = 'm'  then p_count else 0 end),
    exp_book_l  = exp_book_l  - (case when p_size = 'l'  then p_count else 0 end),
    exp_book_xl = exp_book_xl - (case when p_size = 'xl' then p_count else 0 end)
  where id = uid;

  -- EXP加算 → レベルアップ（必要EXP=20×lv）→ Lv上限クランプ
  total := vc.exp::bigint + exp_per::bigint * p_count;
  v_lv  := vc.lv;
  while v_lv < lvcap and total >= 20 * v_lv loop
    total := total - 20 * v_lv;
    v_lv  := v_lv + 1;
  end loop;
  if v_lv >= lvcap then
    v_lv  := lvcap;
    total := 0;          -- 上限クランプ・余剰EXPは破棄
  end if;

  update public.cards set lv = v_lv, exp = total::int where id = p_card_id;

  return jsonb_build_object(
    'card_id',  p_card_id,
    'lv',       v_lv,
    'exp',      total,
    'lv_cap',   lvcap,
    'consumed', jsonb_build_object('size', p_size, 'count', p_count, 'exp_each', exp_per)
  );
end;
$$;

revoke all on function public.use_exp_book(uuid, text, integer) from public;
grant execute on function public.use_exp_book(uuid, text, integer) to authenticated;
