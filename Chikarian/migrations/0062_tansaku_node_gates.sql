-- ============================================================
-- Chikarian migration 0062: 探索 特設ノードのゲート（start_tansaku 再定義・土台=0058）
-- canon-06 §3-2（再設計 2026-06-22）。面別解放(0058)はそのまま、特設ゲートを追加：
--   面4＝本体戦力ゲート（武気フリー・★非依存）：4-1≥3,000／4-2≥6,000／4-3≥9,000 → EXPLORE_POWER_LOCKED
--   面7＝属性ゲート（3枚同属性）：7-1=芯/7-2=葉/7-3=花 → EXPLORE_ATTR_LOCKED
--   面8＝★ゲート（3枚★2以上）：8-1〜8-3 → EXPLORE_STAR_LOCKED
--   いずれも「編成3枚すべてが条件」＝2枚以下/欠けは EXPLORE_DECK_INCOMPLETE。
-- 本体・属性は start_boss_battle(0054) と同算法（card_key を _ 分割／SP base 3,200／本体=base×(1+(Lv-1)×2/(cap-1))）。
-- 他（depth/area 検証・0058面別解放・デッキ上限・既存回収・占有ロック・出発ロック・返り値）は 0058 と一字一句同一。
-- 報酬（面4高EXP・面7/8ドロップ・面7-8 EXP無）は 0063（collect_tansaku）で実装。
-- ============================================================

-- 再利用ヘルパ1：カード本体戦力（★非依存・武気フリー）。base×(1+(Lv-1)×2/(cap-1))。
create or replace function public._chikarian_card_body(p_card_key text, p_lv integer)
returns numeric language plpgsql immutable as $$
declare v_base numeric; v_cap int;
begin
  if p_card_key like 'chara\_%\_sp' escape '\' then
    v_base := 3200; v_cap := 50;                          -- SP本体3,200（2026-06-18改定・0039/0040）
  else
    case split_part(p_card_key, '_', 5)                   -- 例 chara_hibiscus_hana_ken_n → 'n'
      when 'n'   then v_base := 80;  v_cap := 30;
      when 'r'   then v_base := 200; v_cap := 40;
      when 'sr'  then v_base := 360; v_cap := 50;
      when 'ssr' then v_base := 560; v_cap := 60;
      else return 0;
    end case;
  end if;
  return v_base * (1 + (least(coalesce(p_lv,1), v_cap) - 1) * 2.0 / (v_cap - 1));
end; $$;
revoke all on function public._chikarian_card_body(text,integer) from public, anon, authenticated;

-- 再利用ヘルパ2：カード属性（hana/ha/shin）。meshibe→shin・SP→null（中立＝属性ゲート不可）。
create or replace function public._chikarian_card_attr(p_card_key text)
returns text language sql immutable as $$
  select case
    when p_card_key like 'chara\_%\_sp' escape '\' then null
    when split_part(p_card_key, '_', 2) = 'meshibe'  then 'shin'
    else split_part(p_card_key, '_', 3)
  end;
$$;
revoke all on function public._chikarian_card_attr(text) from public, anon, authenticated;

-- start_tansaku（0058）＋ 特設ゲート
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
  v_role    integer;
  v_max_decks integer;
  v_depth smallint;
  v_area smallint;
  v_step integer;
  v_gate integer;
  v_s1 uuid; v_s2 uuid; v_s3 uuid;
  v_body_sum numeric;
  v_threshold numeric;
  v_req_attr text;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  v_depth := public._chikarian_depth_to_int(p_depth);
  if v_depth is null then raise exception 'INVALID_DEPTH'; end if;

  v_area := coalesce(p_area, 1)::smallint;
  if v_area < 1 or v_area > 8 then raise exception 'INVALID_AREA'; end if;

  select cleared_stage, boss_round_role into v_cleared, v_role from public.profiles where id = v_uid;

  -- 面別解放ゲート（canon-06 §3-2・ボス進行相乗り）
  v_step := (v_area - 1) * 3 + v_depth;                                  -- 1..24
  v_gate := coalesce(v_cleared, 0) * 3 + coalesce(v_role, 0);            -- 累積撃破ノード数
  if v_gate < v_step - 1 then raise exception 'EXPLORE_LOCKED'; end if;  -- step1(面1浅)は常時開放（gate>=0）

  -- 特設ノードのゲート（canon-06 §3-2 再設計・面4本体/面7属性/面8★・3枚全条件）
  if v_area in (4, 7, 8) then
    select slot1_card_id, slot2_card_id, slot3_card_id into v_s1, v_s2, v_s3
      from public.decks where user_id = v_uid and deck_no = p_deck_no;
    if v_s1 is null or v_s2 is null or v_s3 is null then
      raise exception 'EXPLORE_DECK_INCOMPLETE';                         -- 3枚揃っていない（2枚以下は弾く）
    end if;

    if v_area = 4 then
      -- 本体戦力合計 ≥ しきい値(depth)：4-1=3,000 / 4-2=6,000 / 4-3=9,000
      select coalesce(public._chikarian_card_body(c1.card_key, c1.lv),0)
           + coalesce(public._chikarian_card_body(c2.card_key, c2.lv),0)
           + coalesce(public._chikarian_card_body(c3.card_key, c3.lv),0)
        into v_body_sum
        from public.cards c1, public.cards c2, public.cards c3
       where c1.id = v_s1 and c2.id = v_s2 and c3.id = v_s3
         and c1.user_id = v_uid and c2.user_id = v_uid and c3.user_id = v_uid;
      v_threshold := case v_depth when 1 then 3000 when 2 then 6000 when 3 then 9000 end;
      if coalesce(v_body_sum, 0) < v_threshold then raise exception 'EXPLORE_POWER_LOCKED'; end if;

    elsif v_area = 7 then
      -- 3枚とも同属性：7-1=芯(shin) / 7-2=葉(ha) / 7-3=花(hana)
      v_req_attr := case v_depth when 1 then 'shin' when 2 then 'ha' when 3 then 'hana' end;
      if (select count(*) from public.cards c
            where c.id in (v_s1, v_s2, v_s3) and c.user_id = v_uid
              and public._chikarian_card_attr(c.card_key) = v_req_attr) < 3 then
        raise exception 'EXPLORE_ATTR_LOCKED';
      end if;

    elsif v_area = 8 then
      -- 3枚とも★2以上
      if (select count(*) from public.cards c
            where c.id in (v_s1, v_s2, v_s3) and c.user_id = v_uid
              and coalesce(c.star, 0) >= 2) < 3 then
        raise exception 'EXPLORE_STAR_LOCKED';
      end if;
    end if;
  end if;

  v_max_decks := least(6, 2 + floor(coalesce(v_cleared, 0) / 2.0)::int);
  if p_deck_no < 1 or p_deck_no > v_max_decks then raise exception 'DECK_LOCKED'; end if;

  -- 既存探索があれば回収してから切替（蓄積を失わない）
  perform 1 from public.tansaku_states where user_id = v_uid and deck_no = p_deck_no;
  if found then
    perform public.collect_tansaku(p_deck_no);
  end if;

  -- 占有ロック：このデッキの編成カードが既に他デッキで探索中なら出発を拒否（1カード＝1デッキ・canon-06 §3-4）
  if exists (
    select 1 from public.decks d
    join public.cards ca
      on ca.id in (d.slot1_card_id, d.slot2_card_id, d.slot3_card_id)
    where d.user_id = v_uid and d.deck_no = p_deck_no and ca.tansaku_deck_no is not null
  ) then
    raise exception 'CARD_IN_TANSAKU';
  end if;

  insert into public.tansaku_states (user_id, deck_no, area, depth, last_collect_at, is_houchi)
    values (v_uid, p_deck_no, v_area, v_depth, now(), false)
    on conflict (user_id, deck_no)
    do update set area = excluded.area,
                  depth = excluded.depth,
                  last_collect_at = now(),
                  is_houchi = false;

  -- 出発（canon-06 §3-4）：このデッキの編成カードをロック（tansaku_deck_no = deck_no）
  update public.cards c
     set tansaku_deck_no = p_deck_no::smallint
    from public.decks d
   where d.user_id = v_uid and d.deck_no = p_deck_no
     and c.user_id = v_uid
     and c.id in (d.slot1_card_id, d.slot2_card_id, d.slot3_card_id);

  return jsonb_build_object(
    'deck_no', p_deck_no, 'area', v_area, 'depth', v_depth, 'step', v_step, 'started_at', now()
  );
end;
$$;
revoke all on function public.start_tansaku(integer, integer, text) from public, anon;
grant execute on function public.start_tansaku(integer, integer, text) to authenticated;
