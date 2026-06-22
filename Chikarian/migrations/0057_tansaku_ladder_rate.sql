-- Chikarian migration 0057: 探索レートを24段ラダー＋周回半減へ（collect_tansaku 再定義・土台=0033）
-- 出典: canon-06 §3-1（24段ラダー・周回半減）＋ 確認用仕様 tansaku-ladder-spec-2026-06-21（ユーザー確認2026-06-21）。
-- 変更点: depth-only の固定レート（浅2/中5/深10・0.5/1.2/2.5）を、(面=area, 周=boss_round, 深度=depth) から算出する
--         24段ラダー＋周回半減へ置換。他（加算・帰還・解錠・返却）は 0033 と同一。
--   段 step = (area-1)*3 + depth（深=1/中=2/深=3）, 1..24。1周目: R_med=0.33+2.97*(step-1)/23, R_exp=0.20+1.80*(step-1)/23。
--   周回半減: rate_r = R(1) + S*[ (2 - 2^(2-r)) + (step-1)/(23*2^(r-1)) ]（S=R(24)-R(1)）。
--             面1浅=面8深の前周最上段から継続・登り幅毎周半減・上限=2*R(24)-R(1) で頭打ち（発散しない）。
--   ※レートは collect 時の boss_round を採用（デッキは占有ロック中＝探索中はボス戦に出せないため周跨ぎの悪用は限定的）。

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
  v_round integer;
  v_step  integer;
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

  -- 段とレート（24段ラダー＋周回半減）
  if v_state.depth not in (1,2,3) then raise exception 'INVALID_DEPTH_STATE'; end if;
  if v_state.area < 1 or v_state.area > 8 then raise exception 'INVALID_AREA_STATE'; end if;
  select greatest(1, coalesce(boss_round, 1)) into v_round from public.profiles where id = v_uid;
  v_step := (v_state.area - 1) * 3 + v_state.depth;   -- 1..24
  v_medal_rate := 0.33 + 2.97 * ( (2 - power(2.0, 2 - v_round)) + (v_step - 1) / (23.0 * power(2.0, v_round - 1)) );
  v_exp_rate   := 0.20 + 1.80 * ( (2 - power(2.0, 2 - v_round)) + (v_step - 1) / (23.0 * power(2.0, v_round - 1)) );

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

  -- 帰還（canon-06 §3-4）：このデッキの編成カードのロック解除（null）＋探索終了
  update public.cards c
     set tansaku_deck_no = null
    from public.decks d
   where d.user_id = v_uid and d.deck_no = p_deck_no
     and c.user_id = v_uid
     and c.id in (d.slot1_card_id, d.slot2_card_id, d.slot3_card_id);
  delete from public.tansaku_states where user_id = v_uid and deck_no = p_deck_no;

  select medal into v_medal_total from public.profiles where id = v_uid;
  return jsonb_build_object(
    'deck_no', p_deck_no, 'area', v_state.area, 'depth', v_state.depth,
    'round', v_round, 'step', v_step,
    'elapsed_min', round(v_elapsed_min, 2),
    'medal_rate', round(v_medal_rate, 3), 'exp_rate', round(v_exp_rate, 3),
    'medal_gain', v_medal_gain, 'exp_gain_per_card', v_exp_gain,
    'medal_total', v_medal_total
  );
end;
$$;

revoke all on function public.collect_tansaku(integer) from public, anon;
grant execute on function public.collect_tansaku(integer) to authenticated;
