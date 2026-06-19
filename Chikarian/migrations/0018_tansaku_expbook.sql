-- ============================================================
-- Chikarian migration 0018: 探索 (start/collect_tansaku) + use_exp_book + EXP→Lv ヘルパ
-- canon: balance-chikarian-2026-06-12 §4/§7, design-updates-2026-06-13 ②, supabase-spec §1/§2
-- 規約は 0012 に準拠。tansaku_states / decks / profiles(exp_book_*) は 0001 作成済みの前提。
--
-- EXP/Lv（balance §4）:
--   経験の書 EXP: 小10 / 中50 / 大200 / 特大1000
--   必要EXP(Lv n→n+1)=20n ／ 累積(Lv1→L)=10·L·(L−1)
--   cards.exp は「累積EXP」、lv は累積から導出（_chikarian_lv_from_exp）。
--   Lv上限: N30 / R40 / SR50 / SSR60 / SP50。
-- 探索（balance §7）:
--   レート/分: 浅 2/0.5 ・ 中 5/1.2 ・ 深 10/2.5（メダル/EXP）。蓄積上限なし＝経過分×レート。
--   EXP はデッキ3枚それぞれに付与。メダル/EXP とも floor。
--   デッキ番号検証: 1..(2 + floor(cleared_stage/2))・上限6（design-updates 06-13）。
--   面別解放は未確定 → area は下限のみ（1以上）で受理・上限ゲートなし。
-- ============================================================

-- 累積EXP→Lv（厳密・ループ。Lv上限でクランプ）
create or replace function public._chikarian_lv_from_exp(p_exp numeric, p_cap integer)
returns integer
language plpgsql
immutable
as $$
declare v_lv integer := 1;
begin
  while v_lv < p_cap and coalesce(p_exp,0) >= 10::numeric * (v_lv + 1) * v_lv loop
    v_lv := v_lv + 1;
  end loop;
  return v_lv;
end;
$$;

-- 特大(xl) 列が無い環境向けの保険（既にあれば no-op）
alter table public.profiles add column if not exists exp_book_xl integer not null default 0;

-- 経験の書を使用（p_count 冊・既定1）
create or replace function public.use_exp_book(
  p_card_id uuid,
  p_size    text,
  p_count   integer default 1
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
  v_per integer; v_have integer;
  v_add integer; v_new_exp integer; v_new_lv integer;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_size not in ('s','m','l','xl') then raise exception 'INVALID_SIZE'; end if;
  if p_count is null or p_count <= 0 then raise exception 'INVALID_COUNT'; end if;

  select * into v_card from public.cards where id = p_card_id and user_id = v_uid for update;
  if not found then raise exception 'CARD_NOT_FOUND'; end if;

  v_per := case p_size when 's' then 10 when 'm' then 50 when 'l' then 200 when 'xl' then 1000 end;

  -- 所持確認＆消費
  if p_size = 's' then
    select exp_book_s into v_have from public.profiles where id = v_uid for update;
    if v_have < p_count then raise exception 'INSUFFICIENT_BOOK'; end if;
    update public.profiles set exp_book_s = exp_book_s - p_count where id = v_uid;
  elsif p_size = 'm' then
    select exp_book_m into v_have from public.profiles where id = v_uid for update;
    if v_have < p_count then raise exception 'INSUFFICIENT_BOOK'; end if;
    update public.profiles set exp_book_m = exp_book_m - p_count where id = v_uid;
  elsif p_size = 'l' then
    select exp_book_l into v_have from public.profiles where id = v_uid for update;
    if v_have < p_count then raise exception 'INSUFFICIENT_BOOK'; end if;
    update public.profiles set exp_book_l = exp_book_l - p_count where id = v_uid;
  else
    select exp_book_xl into v_have from public.profiles where id = v_uid for update;
    if v_have < p_count then raise exception 'INSUFFICIENT_BOOK'; end if;
    update public.profiles set exp_book_xl = exp_book_xl - p_count where id = v_uid;
  end if;

  v_rare := public._chikarian_rarity(v_card.card_key);
  v_cap  := case v_rare when 'n' then 30 when 'r' then 40 when 'sr' then 50 when 'ssr' then 60 when 'sp' then 50 else 60 end;
  v_add  := v_per * p_count;
  v_new_exp := coalesce(v_card.exp, 0) + v_add;
  v_new_lv  := public._chikarian_lv_from_exp(v_new_exp, v_cap);

  update public.cards set exp = v_new_exp, lv = v_new_lv where id = p_card_id;

  return jsonb_build_object(
    'card_id', p_card_id, 'size', p_size, 'count', p_count,
    'exp_added', v_add, 'new_exp', v_new_exp,
    'old_lv', v_card.lv, 'new_lv', v_new_lv,
    'book_remaining', v_have - p_count
  );
end;
$$;
revoke all on function public.use_exp_book(uuid, text, integer) from public, anon;
grant execute on function public.use_exp_book(uuid, text, integer) to authenticated;

-- 探索を回収（経過分×レート。メダルは本人へ、EXP はデッキ3枚へ）
create or replace function public.collect_tansaku(p_deck_no integer)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_state record;
  v_deck record;
  v_elapsed_min numeric;
  v_medal_rate numeric; v_exp_rate numeric;
  v_medal_gain bigint; v_exp_gain integer;
  v_cid uuid;
  v_key text; v_exp integer; v_rare text; v_cap integer; v_newlv integer;
  v_medal_total bigint;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select * into v_state from public.tansaku_states
    where user_id = v_uid and deck_no = p_deck_no for update;
  if not found then raise exception 'NOT_EXPLORING'; end if;

  v_elapsed_min := greatest(0, extract(epoch from (now() - v_state.last_collect_at)) / 60.0);

  case v_state.depth
    when 'shallow' then v_medal_rate := 2;  v_exp_rate := 0.5;
    when 'mid'     then v_medal_rate := 5;  v_exp_rate := 1.2;
    when 'deep'    then v_medal_rate := 10; v_exp_rate := 2.5;
    else raise exception 'INVALID_DEPTH_STATE';
  end case;

  v_medal_gain := floor(v_elapsed_min * v_medal_rate)::bigint;
  v_exp_gain   := floor(v_elapsed_min * v_exp_rate)::int;

  if v_medal_gain > 0 then
    update public.profiles set medal = medal + v_medal_gain where id = v_uid;
  end if;

  -- デッキ3枚に EXP 付与
  select slot1_card_id, slot2_card_id, slot3_card_id into v_deck
    from public.decks where user_id = v_uid and deck_no = p_deck_no;
  if found and v_exp_gain > 0 then
    foreach v_cid in array array[v_deck.slot1_card_id, v_deck.slot2_card_id, v_deck.slot3_card_id]
    loop
      if v_cid is not null then
        select card_key, exp into v_key, v_exp
          from public.cards where id = v_cid and user_id = v_uid for update;
        if found then
          v_rare  := public._chikarian_rarity(v_key);
          v_cap   := case v_rare when 'n' then 30 when 'r' then 40 when 'sr' then 50 when 'ssr' then 60 when 'sp' then 50 else 60 end;
          v_exp   := coalesce(v_exp, 0) + v_exp_gain;
          v_newlv := public._chikarian_lv_from_exp(v_exp, v_cap);
          update public.cards set exp = v_exp, lv = v_newlv where id = v_cid;
        end if;
      end if;
    end loop;
  end if;

  update public.tansaku_states set last_collect_at = now()
    where user_id = v_uid and deck_no = p_deck_no;

  select medal into v_medal_total from public.profiles where id = v_uid;
  return jsonb_build_object(
    'deck_no', p_deck_no, 'depth', v_state.depth,
    'elapsed_min', round(v_elapsed_min, 2),
    'medal_gain', v_medal_gain, 'exp_gain_per_card', v_exp_gain,
    'medal_total', v_medal_total
  );
end;
$$;
revoke all on function public.collect_tansaku(integer) from public, anon;
grant execute on function public.collect_tansaku(integer) to authenticated;

-- 探索を開始（既存探索は自動回収→新ノードへ）
create or replace function public.start_tansaku(
  p_deck_no integer,
  p_area    integer,
  p_depth   text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_cleared integer;
  v_max_decks integer;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_depth not in ('shallow','mid','deep') then raise exception 'INVALID_DEPTH'; end if;
  if p_area is null or p_area < 1 then raise exception 'INVALID_AREA'; end if;  -- 面別解放は未確定

  select cleared_stage into v_cleared from public.profiles where id = v_uid;
  v_max_decks := least(6, 2 + floor(coalesce(v_cleared, 0) / 2.0)::int);
  if p_deck_no < 1 or p_deck_no > v_max_decks then raise exception 'DECK_LOCKED'; end if;

  -- 既存探索があれば回収してから切替（蓄積を失わない）
  perform 1 from public.tansaku_states where user_id = v_uid and deck_no = p_deck_no;
  if found then
    perform public.collect_tansaku(p_deck_no);
  end if;

  insert into public.tansaku_states (user_id, deck_no, area, depth, last_collect_at, is_houchi)
    values (v_uid, p_deck_no, p_area, p_depth, now(), false)
    on conflict (user_id, deck_no)
    do update set area = excluded.area,
                  depth = excluded.depth,
                  last_collect_at = now(),
                  is_houchi = false;

  return jsonb_build_object(
    'deck_no', p_deck_no, 'area', p_area, 'depth', p_depth, 'started_at', now()
  );
end;
$$;
revoke all on function public.start_tansaku(integer, integer, text) from public, anon;
grant execute on function public.start_tansaku(integer, integer, text) to authenticated;
