-- Chikarian migration 0058: 探索の面別解放ゲート（start_tansaku 再定義・土台=0036）
-- 出典: canon-06 §3-2（面別解放＝ボス進行相乗り・最下段常時開放）＋ 確認用仕様 tansaku-ladder-spec-2026-06-21（ユーザー確認2026-06-21）。
-- 変更点: 現状の「p_area≥1 下限のみ」に、ボス進行相乗りの上限ゲートを追加。
--   段 step = (area-1)*3 + depth（浅=1/中=2/深=3）, 1..24。
--   解放ゲート gate = cleared_stage*3 + boss_round_role（0=未/1=中A済/2=中B済・0054）＝1周目の累積撃破ノード数。
--   step は gate >= step-1 で解放（step1=面1浅は常時開放＝放置の受け皿）。2周目以降は cleared_stage=8→gate>=24＝全段開放。
--   検証: ボス1-2(中B)撃破→role=2→gate=2→step3(面1深)解放 / ボス1-3(面ボス)撃破→cleared_stage=1,role=0→gate=3→step4(面2浅)解放。
-- 注: 戦力ゲート（本体戦闘力合計≥しきい値・武気フリー）は値が Phase 4 シミュ確定待ちのため本migrationでは未実装（構造は確認済み・後続migrationで追加）。
--     他（デッキ上限・既存回収・占有ロック・出発ロック）は 0036 と同一。

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
