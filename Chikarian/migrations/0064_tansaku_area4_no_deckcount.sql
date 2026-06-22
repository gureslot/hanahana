-- ============================================================
-- Chikarian migration 0064: 面4ゲートを「枚数不問の本体合計」に修正（start_tansaku 再定義・土台=0062）
-- canon-06 §3-2。0062では面4にも EXPLORE_DECK_INCOMPLETE（3枚必須）が掛かり、
-- かつ本体合計を3枚クロス結合で算出していたため SP単騎(2枠空)が0扱いで弾かれていた。
-- 修正：3枚必須は面7/面8のみ（各カード条件＝全枠必要）。面4は本体合計のみ（枚数不問・空枠=0）。
--   面4：sum(本体) over 編成カード ≥ しきい値（4-1=3,000/4-2=6,000/4-3=9,000）。SP1枚でも合計が足りれば可。
-- ヘルパ（_chikarian_card_body / _chikarian_card_attr）は0062のまま不変。他ロジックも0062と同一。
-- ============================================================

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

  -- 特設ノードのゲート（canon-06 §3-2 再設計）
  if v_area in (4, 7, 8) then
    select slot1_card_id, slot2_card_id, slot3_card_id into v_s1, v_s2, v_s3
      from public.decks where user_id = v_uid and deck_no = p_deck_no;

    if v_area = 4 then
      -- 面4＝本体戦力の合計ゲート（枚数不問・空枠=0）。SP1枚でも合計が足りれば可。
      select coalesce(sum(public._chikarian_card_body(c.card_key, c.lv)), 0)
        into v_body_sum
        from public.cards c
       where c.user_id = v_uid and c.id in (v_s1, v_s2, v_s3);
      v_threshold := case v_depth when 1 then 3000 when 2 then 6000 when 3 then 9000 end;
      if coalesce(v_body_sum, 0) < v_threshold then raise exception 'EXPLORE_POWER_LOCKED'; end if;

    else
      -- 面7/面8＝各カードが条件 → 3枚すべて必須（欠け/2枚以下は弾く）
      if v_s1 is null or v_s2 is null or v_s3 is null then
        raise exception 'EXPLORE_DECK_INCOMPLETE';
      end if;

      if v_area = 7 then
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
