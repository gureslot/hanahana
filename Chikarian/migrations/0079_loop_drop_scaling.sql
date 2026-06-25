-- ============================================================
-- Chikarian migration 0079: 周回ドロップ増加（面8ボス戦力カーブ連動）
--   背景: 0078 は round>=2 のドロップを全周一定にしていた。周回が進むほど
--          敵戦力は boss_loop_curve で上がるのに報酬が据え置きだった。
--   変更:
--     [倍率] v_mult = p8(round) / p8(2)。round1..6 は boss_loop_curve の p8、
--            round7+ は p8(6)×1.15^(round-6)（do_boss_battle の連続カーブと同じ伸び）。
--            実値: 2周=1.00 / 3周=1.60 / 4周=2.00 / 5周=2.36 / 6周=2.71 / 以降×1.15。
--     [探索] collect_tansaku の round>=2 ドロップ（青/赤/虹/EXP本）に v_mult を適用。
--            恩寵石は需要が頭打ちのため周回倍率をかけず基底のまま。
--            メダル率・EXP率は式が既に周回スケールするため非適用（二重回避）。round=1 は不変。
--     [ボス] _chikarian_boss_loop_drops の青/赤/虹に v_mult を適用（四捨五入）。恩寵石は基底のまま。
--            ボスのEXP本は既存 do_boss_battle 側（per-stage 式）のままで本migration対象外。
--   依存: 0074(boss_loop_curve)・0078(collect_tansaku/トリガ)。0074 未適用だと作成時にエラー。
--   再実行可: create or replace ＋ drop trigger if exists → create。
--   適用順: 0078 の後。Supabase 手動適用後 schema_migrations に 0079 登録。
-- ============================================================

-- ------------------------------------------------------------
-- 1. collect_tansaku：round>=2 のドロップに周回倍率 v_mult を適用
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
  v_exp_mult numeric := 1.0;
  v_rate_book numeric := 0; v_rate_blue numeric := 0;
  v_rate_red numeric := 0;  v_rate_rainbow numeric := 0;
  v_rate_hoshou numeric := 0;
  v_n_book int := 0; v_n_blue int := 0; v_n_red int := 0; v_n_rainbow int := 0; v_n_hoshou int := 0;
  v_mult numeric := 1.0;                                        -- 周回ドロップ倍率（round=1 は1.0）
  v_p8_cur numeric; v_p8_base numeric;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select * into v_state from public.tansaku_states
    where user_id = v_uid and deck_no = p_deck_no for update;
  if not found then raise exception 'NOT_EXPLORING'; end if;

  v_elapsed_min := greatest(0, extract(epoch from (now() - v_state.last_collect_at)) / 60.0);

  if v_state.depth not in (1,2,3) then raise exception 'INVALID_DEPTH_STATE'; end if;
  if v_state.area < 1 or v_state.area > 8 then raise exception 'INVALID_AREA_STATE'; end if;
  select greatest(1, coalesce(boss_round, 1)) into v_round from public.profiles where id = v_uid;
  v_step := (v_state.area - 1) * 3 + v_state.depth;
  v_medal_rate := 0.33 + 2.97 * ( (2 - power(2.0, 2 - v_round)) + (v_step - 1) / (23.0 * power(2.0, v_round - 1)) );
  v_exp_rate   := 0.20 + 1.80 * ( (2 - power(2.0, 2 - v_round)) + (v_step - 1) / (23.0 * power(2.0, v_round - 1)) );

  v_medal_gain := floor(v_elapsed_min * v_medal_rate)::bigint;
  v_exp_gain   := floor(v_elapsed_min * v_exp_rate)::int;

  if v_round = 1 then
    -- ===== 1周目（0065/0078 と同一・不変）=====
    if v_state.area = 4 then
      v_exp_mult := 2.0;
      v_exp_gain := floor(v_elapsed_min * v_exp_rate * v_exp_mult)::int;
    elsif v_state.area = 7 then
      v_exp_gain := 0;
      if    v_state.depth = 1 then v_rate_book := 0.005;
      elsif v_state.depth = 2 then v_rate_blue := 0.005;  v_rate_red := 0.0008;
      elsif v_state.depth = 3 then v_rate_red := 0.0012;  v_rate_rainbow := 0.0001;
      end if;
    elsif v_state.area = 8 then
      v_exp_gain := 0; v_medal_gain := 0;
      if    v_state.depth = 1 then v_rate_book := 0.008;
      elsif v_state.depth = 2 then v_rate_blue := 0.008;  v_rate_red := 0.0015;
      elsif v_state.depth = 3 then v_rate_red := 0.002;   v_rate_rainbow := 0.0002;
      end if;
    end if;
  else
    -- ===== 2周目以降（0078 ドロップ表）＋周回倍率 v_mult =====
    -- 周回倍率：面8ボス power の2周目比（boss_loop_curve 連動・round7+ は ×1.15/周）
    select p8 into v_p8_cur from public.boss_loop_curve where round = least(v_round, 6);
    if v_p8_cur is null then v_p8_cur := 448320; end if;
    if v_round > 6 then v_p8_cur := v_p8_cur * power(1.15, (v_round - 6)::numeric); end if;
    select p8 into v_p8_base from public.boss_loop_curve where round = 2;
    v_mult := greatest(1.0, v_p8_cur / coalesce(v_p8_base, 448320));

    if v_state.area = 4 then
      v_exp_mult := 2.0;
      v_exp_gain := floor(v_elapsed_min * v_exp_rate * v_exp_mult)::int;
      v_medal_gain := 0;
    elsif v_state.area in (7, 8) then
      v_exp_gain := 0; v_medal_gain := 0;
    end if;
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

  -- ドロップ付与：率 × 経過 × 周回倍率 をポアソン抽選。round=1 は v_mult=1.0＝従来どおり。
  v_n_book    := public._chikarian_poisson(v_elapsed_min * v_rate_book    * v_mult);
  v_n_blue    := public._chikarian_poisson(v_elapsed_min * v_rate_blue    * v_mult);
  v_n_red     := public._chikarian_poisson(v_elapsed_min * v_rate_red     * v_mult);
  v_n_rainbow := public._chikarian_poisson(v_elapsed_min * v_rate_rainbow * v_mult);
  v_n_hoshou  := public._chikarian_poisson(v_elapsed_min * v_rate_hoshou);   -- 恩寵石は周回倍率をかけない（需要が頭打ちのため固定）
  if v_n_book + v_n_blue + v_n_red + v_n_rainbow + v_n_hoshou > 0 then
    update public.profiles set
      exp_book_m      = exp_book_m      + v_n_book,
      crystal_blue    = crystal_blue    + v_n_blue,
      crystal_red     = crystal_red     + v_n_red,
      crystal_rainbow = crystal_rainbow + v_n_rainbow,
      hoshou_stone    = hoshou_stone    + v_n_hoshou
    where id = v_uid;
  end if;

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
    'round', v_round, 'step', v_step, 'loop_mult', round(v_mult, 3),
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
-- 2. ボス撃破ドロップ：青/赤/虹/恩寵石に周回倍率 v_mult を適用
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
  v_mult numeric; v_p8_cur numeric; v_p8_base numeric;
begin
  if NEW.win is not true then return NEW; end if;
  m := regexp_match(NEW.boss_key, '^boss_([1-8])_(a|b|boss)(?:_r([0-9]+))?$');
  if m is null then return NEW; end if;
  v_round := coalesce(m[3]::int, 1);
  if v_round < 2 then return NEW; end if;
  v_stage    := m[1]::int;
  v_role     := m[2];
  v_role_idx := case v_role when 'a' then 1 when 'b' then 2 else 3 end;

  -- 基底（0078 確定表）
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

  -- 周回倍率（面8ボス power の2周目比・round7+ は ×1.15/周）
  select p8 into v_p8_cur from public.boss_loop_curve where round = least(v_round, 6);
  if v_p8_cur is null then v_p8_cur := 448320; end if;
  if v_round > 6 then v_p8_cur := v_p8_cur * power(1.15, (v_round - 6)::numeric); end if;
  select p8 into v_p8_base from public.boss_loop_curve where round = 2;
  v_mult := greatest(1.0, v_p8_cur / coalesce(v_p8_base, 448320));

  v_blue    := round(coalesce(v_blue, 0)    * v_mult)::int;
  v_red     := round(coalesce(v_red, 0)     * v_mult)::int;
  v_rainbow := round(coalesce(v_rainbow, 0) * v_mult)::int;
  v_hoshou  := coalesce(v_hoshou, 0);                          -- 恩寵石は周回倍率をかけない（基底のまま）

  update public.profiles set
    crystal_blue    = crystal_blue    + v_blue,
    crystal_red     = crystal_red     + v_red,
    crystal_rainbow = crystal_rainbow + v_rainbow,
    hoshou_stone    = hoshou_stone    + v_hoshou
  where id = NEW.user_id;

  return NEW;
end;
$$;

drop trigger if exists trg_boss_loop_drops on public.battle_logs;
create trigger trg_boss_loop_drops
  after insert on public.battle_logs
  for each row execute function public._chikarian_boss_loop_drops();


insert into public.schema_migrations (version) values ('0079') on conflict (version) do nothing;
