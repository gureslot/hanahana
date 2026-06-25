-- ============================================================
-- Chikarian migration 0078: 2周目（boss_round>=2）ドロップ配分
--   仕様: ユーザー確定の「2周目ドロップ配分」表をサーバ実装。
--   方針:
--     [探索] collect_tansaku を改修。round=1 は 0065 を完全温存、round>=2 のみ新表を適用。
--            面1-3,5-6=青/赤、面4=高EXP×2・メダル無し・EXP本(中)+恩寵石、
--            面7,8=メダル/EXP無し・ドロップ特化（青/赤/虹 or EXP本+恩寵石/虹+恩寵石）。
--            EXP本は既存踏襲で exp_book_m（中）に付与。ドロップは戻り値にも反映。
--     [ボス] battle_logs への AFTER INSERT トリガで、win かつ round>=2 のとき
--            青/赤/虹/恩寵石を表どおり付与（per-(stage,role)）。
--            ※ EXP本は既存 do_boss_battle が勝利毎に付与（周回問わず）しており、
--              トリガでは減算不可のため二重回避で「ボスのEXP本は表を適用しない」。
--              表どおりに厳密化する場合は do_boss_battle 本体の改修が別途必要。
--   依存: 0065(collect_tansaku・_chikarian_poisson)、battle_logs(0008系・user_id/boss_key/win)、
--         profiles(crystal_blue/red/rainbow・hoshou_stone・exp_book_m)、boss_round(0038/0074)。
--   再実行可: 関数は create or replace、トリガは drop if exists → create。
--   適用順: 0076/0077 の後（独立だが番号順で適用）。Supabase 手動適用後 schema_migrations に 0078 登録。
-- ============================================================

-- ------------------------------------------------------------
-- 1. collect_tansaku 改修（round=1 温存 / round>=2 に2周目ドロップ表）
-- ------------------------------------------------------------
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
  v_rate_hoshou numeric := 0;                                  -- 恩寵石率/分（2周目）
  v_n_book int := 0; v_n_blue int := 0; v_n_red int := 0; v_n_rainbow int := 0; v_n_hoshou int := 0;
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

  -- 報酬調整：round=1 は現状維持（0065 verbatim）、round>=2 は2周目ドロップ表（0078）。
  if v_round = 1 then
    -- ===== 1周目（既存・0065 と同一）=====
    if v_state.area = 4 then
      v_exp_mult := 2.0;                                          -- 面4=高EXP（×2.0）
      v_exp_gain := floor(v_elapsed_min * v_exp_rate * v_exp_mult)::int;
    elsif v_state.area = 7 then
      v_exp_gain := 0;                                            -- 面7=EXP無（メダルは維持）
      if    v_state.depth = 1 then v_rate_book := 0.005;
      elsif v_state.depth = 2 then v_rate_blue := 0.005;  v_rate_red := 0.0008;
      elsif v_state.depth = 3 then v_rate_red := 0.0012;  v_rate_rainbow := 0.0001;
      end if;
    elsif v_state.area = 8 then
      v_exp_gain := 0; v_medal_gain := 0;                         -- 面8=EXP無・メダル無
      if    v_state.depth = 1 then v_rate_book := 0.008;
      elsif v_state.depth = 2 then v_rate_blue := 0.008;  v_rate_red := 0.0015;
      elsif v_state.depth = 3 then v_rate_red := 0.002;   v_rate_rainbow := 0.0002;
      end if;
    end if;
  else
    -- ===== 2周目以降（0078 ドロップ表）=====
    -- 面4=高EXP×2・メダル無し／面7,8=メダル/EXP無し・ドロップ特化／面1-3,5-6=通常レート＋クリスタル
    if v_state.area = 4 then
      v_exp_mult := 2.0;
      v_exp_gain := floor(v_elapsed_min * v_exp_rate * v_exp_mult)::int;
      v_medal_gain := 0;                                          -- 面4=メダル無し（2周目仕様）
    elsif v_state.area in (7, 8) then
      v_exp_gain := 0; v_medal_gain := 0;                         -- 面7,8=メダル/EXP無し
    end if;
    -- per-(area,depth) ドロップ率（step 1..24・確定表どおり）
    case v_step
      when 1  then v_rate_blue:=0.01;   v_rate_red:=0.001;
      when 2  then v_rate_blue:=0.01;   v_rate_red:=0.001;
      when 3  then v_rate_blue:=0.015;  v_rate_red:=0.002;
      when 4  then v_rate_blue:=0.0155; v_rate_red:=0.002;
      when 5  then v_rate_blue:=0.0155; v_rate_red:=0.002;
      when 6  then v_rate_blue:=0.0165; v_rate_red:=0.003;
      when 7  then v_rate_blue:=0.0175; v_rate_red:=0.003;
      when 8  then v_rate_blue:=0.0175; v_rate_red:=0.003;
      when 9  then v_rate_blue:=0.018;  v_rate_red:=0.004;
      when 10 then v_rate_book:=0.01;   v_rate_hoshou:=0.0007;
      when 11 then v_rate_book:=0.013;  v_rate_hoshou:=0.0008;
      when 12 then v_rate_book:=0.016;  v_rate_hoshou:=0.0009;
      when 13 then v_rate_blue:=0.02;   v_rate_red:=0.004;
      when 14 then v_rate_blue:=0.02;   v_rate_red:=0.004;
      when 15 then v_rate_blue:=0.025;  v_rate_red:=0.005;
      when 16 then v_rate_blue:=0.03;   v_rate_red:=0.005;
      when 17 then v_rate_blue:=0.03;   v_rate_red:=0.005;
      when 18 then v_rate_blue:=0.035;  v_rate_red:=0.006;
      when 19 then v_rate_book:=0.01;   v_rate_hoshou:=0.0007;
      when 20 then v_rate_blue:=0.055;  v_rate_red:=0.007;  v_rate_rainbow:=0.0001;
      when 21 then v_rate_blue:=0.065;  v_rate_red:=0.009;  v_rate_rainbow:=0.0002;
      when 22 then v_rate_book:=0.01;   v_rate_hoshou:=0.0007;
      when 23 then v_rate_blue:=0.08;   v_rate_red:=0.01;   v_rate_rainbow:=0.0002;
      when 24 then v_rate_rainbow:=0.0005; v_rate_hoshou:=0.0007;
      else null;
    end case;
  end if;

  -- メダル付与（面8・2周目の面4/7は0）
  if v_medal_gain > 0 then
    update public.profiles set medal = medal + v_medal_gain where id = v_uid;
  end if;

  -- EXP付与（面7/8・面8は0＝スキップ）
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

  -- ドロップ付与（率>0 のものをポアソン抽選）：EXP本=中(exp_book_m)・恩寵石=hoshou_stone・クリスタル
  --   round=1 は面7/8のみ率>0（hoshou率=0）＝従来と同一。round>=2 は表どおり全面。
  v_n_book    := public._chikarian_poisson(v_elapsed_min * v_rate_book);
  v_n_blue    := public._chikarian_poisson(v_elapsed_min * v_rate_blue);
  v_n_red     := public._chikarian_poisson(v_elapsed_min * v_rate_red);
  v_n_rainbow := public._chikarian_poisson(v_elapsed_min * v_rate_rainbow);
  v_n_hoshou  := public._chikarian_poisson(v_elapsed_min * v_rate_hoshou);
  if v_n_book + v_n_blue + v_n_red + v_n_rainbow + v_n_hoshou > 0 then
    update public.profiles set
      exp_book_m      = exp_book_m      + v_n_book,
      crystal_blue    = crystal_blue    + v_n_blue,
      crystal_red     = crystal_red     + v_n_red,
      crystal_rainbow = crystal_rainbow + v_n_rainbow,
      hoshou_stone    = hoshou_stone    + v_n_hoshou
    where id = v_uid;
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
    'drop_book_m', v_n_book, 'drop_blue', v_n_blue, 'drop_red', v_n_red,
    'drop_rainbow', v_n_rainbow, 'drop_hoshou', v_n_hoshou,
    'medal_total', v_medal_total
  );
end;
$$;

revoke all on function public.collect_tansaku(integer) from public, anon;
grant execute on function public.collect_tansaku(integer) to authenticated;


-- ------------------------------------------------------------
-- 2. ボス撃破ドロップ（2周目）：battle_logs AFTER INSERT トリガ
--    win かつ round>=2 のとき、青/赤/虹/恩寵石を表どおり付与。EXP本は既存付与のため対象外。
-- ------------------------------------------------------------
create or replace function public._chikarian_boss_loop_drops()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  m text[];
  v_stage int; v_role text; v_round int; v_role_idx int;
  v_blue int; v_red int; v_rainbow int; v_hoshou int;
begin
  if NEW.win is not true then return NEW; end if;
  m := regexp_match(NEW.boss_key, '^boss_([1-8])_(a|b|boss)(?:_r([0-9]+))?$');
  if m is null then return NEW; end if;
  v_round := coalesce(m[3]::int, 1);
  if v_round < 2 then return NEW; end if;          -- 2周目以降のみ（round=1=1周目は付与しない）
  v_stage    := m[1]::int;
  v_role     := m[2];
  v_role_idx := case v_role when 'a' then 1 when 'b' then 2 else 3 end;

  -- 確定表どおり（青=stage×role、赤=stage段、虹=0、恩寵石=各1・面8面ボスのみ3）
  v_blue := case v_stage
    when 1 then 1
    when 2 then 1
    when 3 then 2
    when 4 then (case v_role_idx when 1 then 2 else 3 end)
    when 5 then (case v_role_idx when 3 then 4 else 3 end)
    when 6 then (case v_role_idx when 3 then 5 else 4 end)
    when 7 then (case v_role_idx when 3 then 7 else 6 end)
    when 8 then (case v_role_idx when 3 then 8 else 7 end)
  end;
  v_red     := case when v_stage <= 2 then 0 when v_stage <= 6 then 1 else 2 end;
  v_rainbow := 0;
  v_hoshou  := case when v_stage = 8 and v_role = 'boss' then 3 else 1 end;

  update public.profiles set
    crystal_blue    = crystal_blue    + coalesce(v_blue, 0),
    crystal_red     = crystal_red     + coalesce(v_red, 0),
    crystal_rainbow = crystal_rainbow + coalesce(v_rainbow, 0),
    hoshou_stone    = hoshou_stone    + coalesce(v_hoshou, 0)
  where id = NEW.user_id;

  return NEW;
end;
$$;

drop trigger if exists trg_boss_loop_drops on public.battle_logs;
create trigger trg_boss_loop_drops
  after insert on public.battle_logs
  for each row execute function public._chikarian_boss_loop_drops();


-- 台帳に登録（再実行安全）
insert into public.schema_migrations (version) values ('0078') on conflict (version) do nothing;
