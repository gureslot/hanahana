-- ============================================================
-- Chikarian migration 0063: 探索 特設ノードの報酬（collect_tansaku 再定義・土台=0057）
-- canon-06 §3-1（再設計 2026-06-22）。24段ラダー(0057)はそのまま、特設ノードの報酬を上書き：
--   面4＝高EXP（EXP×倍率。6-3超え。暫定 ×2.0・要シミュ②）。メダルはラダー通り。
--   面7＝EXP無・メダル維持＋ドロップ：7-1芯→EXP本中／7-2葉→青・赤／7-3花→赤・虹。
--   面8＝EXP無・メダル無（ドロップ専用）・面7より高率：8-1→EXP本中／8-2→青・赤／8-3→赤・虹。
-- ドロップ＝経過時間×率（暫定）＋端数を確率で繰上げ（random）。率は冒頭CASEで調整（要シミュ③）。
-- 他（段/レート算出・帰還・解錠・占有解放）は 0057 と同一。
-- ============================================================

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
  -- 特設ノード報酬（暫定・要シミュ）
  v_exp_mult numeric := 1.0;                                   -- 面4=高EXP倍率
  v_rate_book numeric := 0; v_rate_blue numeric := 0;
  v_rate_red numeric := 0;  v_rate_rainbow numeric := 0;       -- ドロップ率/分
  v_n_book int := 0; v_n_blue int := 0; v_n_red int := 0; v_n_rainbow int := 0;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select * into v_state from public.tansaku_states
    where user_id = v_uid and deck_no = p_deck_no for update;
  if not found then raise exception 'NOT_EXPLORING'; end if;

  v_elapsed_min := greatest(0, extract(epoch from (now() - v_state.last_collect_at)) / 60.0);

  -- 段とレート（24段ラダー＋周回半減・0057と同一）
  if v_state.depth not in (1,2,3) then raise exception 'INVALID_DEPTH_STATE'; end if;
  if v_state.area < 1 or v_state.area > 8 then raise exception 'INVALID_AREA_STATE'; end if;
  select greatest(1, coalesce(boss_round, 1)) into v_round from public.profiles where id = v_uid;
  v_step := (v_state.area - 1) * 3 + v_state.depth;   -- 1..24
  v_medal_rate := 0.33 + 2.97 * ( (2 - power(2.0, 2 - v_round)) + (v_step - 1) / (23.0 * power(2.0, v_round - 1)) );
  v_exp_rate   := 0.20 + 1.80 * ( (2 - power(2.0, 2 - v_round)) + (v_step - 1) / (23.0 * power(2.0, v_round - 1)) );

  v_medal_gain := floor(v_elapsed_min * v_medal_rate)::bigint;
  v_exp_gain   := floor(v_elapsed_min * v_exp_rate)::int;

  -- 特設ノードの報酬調整（canon-06 §3-1 再設計）
  if v_state.area = 4 then
    v_exp_mult := 2.0;                                          -- 面4=高EXP（暫定×2.0・6-3超え・要シミュ②）
    v_exp_gain := floor(v_elapsed_min * v_exp_rate * v_exp_mult)::int;
  elsif v_state.area = 7 then
    v_exp_gain := 0;                                            -- 面7=EXP無（メダルは維持）
    if    v_state.depth = 1 then v_rate_book := 0.015;                          -- 7-1芯→EXP本中
    elsif v_state.depth = 2 then v_rate_blue := 0.020; v_rate_red := 0.005;     -- 7-2葉→青・赤
    elsif v_state.depth = 3 then v_rate_red := 0.008; v_rate_rainbow := 0.002;  -- 7-3花→赤・虹
    end if;
  elsif v_state.area = 8 then
    v_exp_gain := 0; v_medal_gain := 0;                         -- 面8=EXP無・メダル無（ドロップ専用）
    if    v_state.depth = 1 then v_rate_book := 0.030;                          -- 8-1→EXP本中（高率）
    elsif v_state.depth = 2 then v_rate_blue := 0.040; v_rate_red := 0.010;     -- 8-2→青・赤（高率）
    elsif v_state.depth = 3 then v_rate_red := 0.016; v_rate_rainbow := 0.004;  -- 8-3→赤・虹（高率）
    end if;
  end if;

  -- メダル付与（面8は0）
  if v_medal_gain > 0 then
    update public.profiles set medal = medal + v_medal_gain where id = v_uid;
  end if;

  -- EXP付与（面7/8は0＝スキップ）
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

  -- ドロップ（面7/8・canon-06 §3-1 再設計・経過×率＋端数を確率繰上げ・暫定率＝要シミュ③）
  if v_state.area in (7, 8) then
    v_n_book    := floor(v_elapsed_min * v_rate_book    + random())::int;
    v_n_blue    := floor(v_elapsed_min * v_rate_blue    + random())::int;
    v_n_red     := floor(v_elapsed_min * v_rate_red     + random())::int;
    v_n_rainbow := floor(v_elapsed_min * v_rate_rainbow + random())::int;
    if v_n_book + v_n_blue + v_n_red + v_n_rainbow > 0 then
      update public.profiles set
        exp_book_m      = exp_book_m      + v_n_book,
        crystal_blue    = crystal_blue    + v_n_blue,
        crystal_red     = crystal_red     + v_n_red,
        crystal_rainbow = crystal_rainbow + v_n_rainbow
      where id = v_uid;
    end if;
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
    'drop_book_m', v_n_book, 'drop_blue', v_n_blue, 'drop_red', v_n_red, 'drop_rainbow', v_n_rainbow,
    'medal_total', v_medal_total
  );
end;
$$;

revoke all on function public.collect_tansaku(integer) from public, anon;
grant execute on function public.collect_tansaku(integer) to authenticated;
