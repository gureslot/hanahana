-- ============================================================
-- Chikarian migration 0024: 探索RPCを depth=smallint(1/2/3) に整合（0018の修正）
-- 背景: tansaku_states.depth / area は smallint（depth は check (depth in (1,2,3))）。
--       0018 は p_depth を文字列のまま保存しようとして "column depth is of type smallint
--       but expression is of type text" で失敗していた。
-- 方針（フロント chikarian-api.js は変更不要にする）:
--   - start_tansaku: p_depth は文字列('shallow'|'mid'|'deep') でも整数(1|2|3) でも受け、
--     smallint(1/2/3) に正規化して保存。p_area も整数化して保存。
--   - collect_tansaku: 整数 depth(1/2/3) でレート判定（浅2/0.5・中5/1.2・深10/2.5・毎分）。
--   返り値キー・ロジックは 0018 と同じ（deck_no/depth/elapsed_min/medal_gain/exp_gain_per_card/medal_total）。
-- 0018 適用後に流す（_chikarian_lv_from_exp / _chikarian_rarity を使用）。
-- ============================================================

-- 文字列/整数のどちらでも smallint(1/2/3) に正規化
create or replace function public._chikarian_depth_to_int(p_depth text)
returns smallint
language sql immutable as $$
  select case lower(trim(p_depth))
           when 'shallow' then 1 when '1' then 1 when '浅' then 1 when '浅域' then 1
           when 'mid'     then 2 when '2' then 2 when '中' then 2 when '中域' then 2
           when 'deep'    then 3 when '3' then 3 when '深' then 3 when '深域' then 3
           else null
         end::smallint;
$$;

-- 探索を回収（depth=smallint で判定）
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

  case v_state.depth          -- smallint 1/2/3
    when 1 then v_medal_rate := 2;  v_exp_rate := 0.5;
    when 2 then v_medal_rate := 5;  v_exp_rate := 1.2;
    when 3 then v_medal_rate := 10; v_exp_rate := 2.5;
    else raise exception 'INVALID_DEPTH_STATE';
  end case;

  v_medal_gain := floor(v_elapsed_min * v_medal_rate)::bigint;
  v_exp_gain   := floor(v_elapsed_min * v_exp_rate)::int;

  if v_medal_gain > 0 then
    update public.profiles set medal = medal + v_medal_gain where id = v_uid;
  end if;

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

-- 探索を開始（p_depth は文字列/整数どちらでも可・smallint で保存）
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
  v_depth smallint;
  v_area smallint;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  v_depth := public._chikarian_depth_to_int(p_depth);
  if v_depth is null then raise exception 'INVALID_DEPTH'; end if;

  v_area := coalesce(p_area, 1)::smallint;
  if v_area < 1 then raise exception 'INVALID_AREA'; end if;   -- 面別解放は未確定＝下限のみ

  select cleared_stage into v_cleared from public.profiles where id = v_uid;
  v_max_decks := least(6, 2 + floor(coalesce(v_cleared, 0) / 2.0)::int);
  if p_deck_no < 1 or p_deck_no > v_max_decks then raise exception 'DECK_LOCKED'; end if;

  -- 既存探索があれば回収してから切替（蓄積を失わない）
  perform 1 from public.tansaku_states where user_id = v_uid and deck_no = p_deck_no;
  if found then
    perform public.collect_tansaku(p_deck_no);
  end if;

  insert into public.tansaku_states (user_id, deck_no, area, depth, last_collect_at, is_houchi)
    values (v_uid, p_deck_no, v_area, v_depth, now(), false)
    on conflict (user_id, deck_no)
    do update set area = excluded.area,
                  depth = excluded.depth,
                  last_collect_at = now(),
                  is_houchi = false;

  return jsonb_build_object(
    'deck_no', p_deck_no, 'area', v_area, 'depth', v_depth, 'started_at', now()
  );
end;
$$;
revoke all on function public.start_tansaku(integer, integer, text) from public, anon;
grant execute on function public.start_tansaku(integer, integer, text) to authenticated;
