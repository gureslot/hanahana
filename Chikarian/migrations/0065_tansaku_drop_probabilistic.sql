-- ============================================================
-- Chikarian migration 0065: 探索ドロップを「確率ドロップ」に変更＋経済安全値へ調整（collect_tansaku 再定義・土台=0063）
-- canon-06 §3-1。0063 は drop = floor(経過×率＋random())＝整数部が確定累積で供給過多だった（③検証）。
-- 変更点（他は 0063 と一字一句同一）：
--   (1) ヘルパ _chikarian_poisson(λ) を追加。1回の collect の期待ドロップ λ=経過×率 を「ポアソン抽選」で確率実現
--       （= 確実ドロップではなく確率ドロップ。希少ほどλが小さく散発的＝当たり感）。λ>200 は確定近似（暴走防止・希少資源は常にλ小なので影響なし）。
--   (2) 面7/8 のドロップ率を経済安全値へ（③検証）：1周目38日の基準供給 青≈1,250/赤≈230/虹≈35 に対し、
--       終盤に1デッキ常駐しても 赤≈+25前後(≈基準の1割)・虹≈+2〜3(基準35のごく一部・SP律速を維持)・青はやや多め可、になる水準。
--   (3) 面4の高EXP×2.0・24段ラダー・メダル/EXP付与・帰還/解錠/占有解放・返り値は 0063 と同一（無改変）。
-- 期待値の目安（per 1デッキ・連続放置）：
--   8-3： 赤 0.002/分→9日で≈26 ・ 虹 0.0002/分→9日で≈2.6
--   7-3： 赤 0.0012/分→16日で≈28 ・ 虹 0.0001/分→16日で≈2.3
--   8-2： 青 0.008/分→9日で≈104 ・ 赤 0.0015/分→9日で≈19
--   7-2： 青 0.005/分→16日で≈115 ・ 赤 0.0008/分→16日で≈18
--   8-1/7-1： EXP本 0.008/0.005（Lvは非律速＝控えめトリクル）
-- ============================================================

-- ヘルパ：ポアソン乱数（期待値 λ）。Knuth 法。λ<=0→0、λ>200 は確定近似（ループ暴走防止）。
create or replace function public._chikarian_poisson(p_lambda numeric)
returns int
language plpgsql
volatile
as $$
declare
  v_l double precision;
  v_k int := 0;
  v_p double precision := 1.0;
begin
  if p_lambda is null or p_lambda <= 0 then return 0; end if;
  if p_lambda > 200 then return round(p_lambda)::int; end if;     -- 長期放置の大量域は確定近似（希少資源はλ<<200で常に確率）
  v_l := exp(-(p_lambda::double precision));
  loop
    v_k := v_k + 1;
    v_p := v_p * random();
    exit when v_p <= v_l;
  end loop;
  return v_k - 1;
end;
$$;
revoke all on function public._chikarian_poisson(numeric) from public, anon, authenticated;

-- collect_tansaku（0063 と同一・ドロップの率と実現方法のみ変更）
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
  v_exp_mult numeric := 1.0;                                   -- 面4=高EXP倍率
  v_rate_book numeric := 0; v_rate_blue numeric := 0;
  v_rate_red numeric := 0;  v_rate_rainbow numeric := 0;       -- ドロップ率/分（＝1分あたりの期待ドロップ）
  v_n_book int := 0; v_n_blue int := 0; v_n_red int := 0; v_n_rainbow int := 0;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select * into v_state from public.tansaku_states
    where user_id = v_uid and deck_no = p_deck_no for update;
  if not found then raise exception 'NOT_EXPLORING'; end if;

  v_elapsed_min := greatest(0, extract(epoch from (now() - v_state.last_collect_at)) / 60.0);

  -- 段とレート（24段ラダー＋周回半減・0057/0063と同一）
  if v_state.depth not in (1,2,3) then raise exception 'INVALID_DEPTH_STATE'; end if;
  if v_state.area < 1 or v_state.area > 8 then raise exception 'INVALID_AREA_STATE'; end if;
  select greatest(1, coalesce(boss_round, 1)) into v_round from public.profiles where id = v_uid;
  v_step := (v_state.area - 1) * 3 + v_state.depth;   -- 1..24
  v_medal_rate := 0.33 + 2.97 * ( (2 - power(2.0, 2 - v_round)) + (v_step - 1) / (23.0 * power(2.0, v_round - 1)) );
  v_exp_rate   := 0.20 + 1.80 * ( (2 - power(2.0, 2 - v_round)) + (v_step - 1) / (23.0 * power(2.0, v_round - 1)) );

  v_medal_gain := floor(v_elapsed_min * v_medal_rate)::bigint;
  v_exp_gain   := floor(v_elapsed_min * v_exp_rate)::int;

  -- 特設ノードの報酬調整（canon-06 §3-1）
  if v_state.area = 4 then
    v_exp_mult := 2.0;                                          -- 面4=高EXP（×2.0・0063/0065確定）
    v_exp_gain := floor(v_elapsed_min * v_exp_rate * v_exp_mult)::int;
  elsif v_state.area = 7 then
    v_exp_gain := 0;                                            -- 面7=EXP無（メダルは維持）
    if    v_state.depth = 1 then v_rate_book := 0.005;                            -- 7-1芯→EXP本中
    elsif v_state.depth = 2 then v_rate_blue := 0.005;  v_rate_red := 0.0008;     -- 7-2葉→青・赤
    elsif v_state.depth = 3 then v_rate_red := 0.0012;  v_rate_rainbow := 0.0001; -- 7-3花→赤・虹（虹は稀）
    end if;
  elsif v_state.area = 8 then
    v_exp_gain := 0; v_medal_gain := 0;                         -- 面8=EXP無・メダル無（ドロップ専用）
    if    v_state.depth = 1 then v_rate_book := 0.008;                            -- 8-1→EXP本中（面7より上）
    elsif v_state.depth = 2 then v_rate_blue := 0.008;  v_rate_red := 0.0015;     -- 8-2→青・赤
    elsif v_state.depth = 3 then v_rate_red := 0.002;   v_rate_rainbow := 0.0002; -- 8-3→赤・虹（虹は稀）
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

  -- ドロップ（面7/8）：確率ドロップ＝期待値 λ=経過×率 をポアソン抽選で実現（確実累積ではない）
  if v_state.area in (7, 8) then
    v_n_book    := public._chikarian_poisson(v_elapsed_min * v_rate_book);
    v_n_blue    := public._chikarian_poisson(v_elapsed_min * v_rate_blue);
    v_n_red     := public._chikarian_poisson(v_elapsed_min * v_rate_red);
    v_n_rainbow := public._chikarian_poisson(v_elapsed_min * v_rate_rainbow);
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

-- 台帳に登録（このマイグレーションを適用済みとして記録・on conflict で再実行安全）
insert into public.schema_migrations (version) values ('0065') on conflict (version) do nothing;
