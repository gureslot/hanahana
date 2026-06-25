-- ============================================================
-- Chikarian migration 0082: 探索の面別解放ゲートを「その周の進行」基準に修正（start_tansaku 再定義・土台=0064）
--
-- 背景・確定（ユーザー指示 2026-06-25）：
--   探索の解放は1周目とまったく同じ＝「その周のボスを倒した分だけ先のノードが開く」。
--   2周目に入った瞬間は何も開かず（面1浅だけ）、2周目のボスを倒すごとに探索も順次解放される。
--   ※「2周目以降は全段開放」は誤り（旧0082案＝全面開放は破棄）。canon-06 §3-2 の該当記述も後で訂正する。
--
-- 原因：
--   0064 までのゲートは gate = cleared_stage*3 + boss_round_role。
--   cleared_stage は「1周目の累積撃破（クリアで止まり減らない恒常カウンタ）」なので、
--   2周目以降は cleared_stage=8 → gate=24 → 全段開放になっていた（＝バグ）。
--
-- 修正：
--   ゲートの基準を cleared_stage から boss_round_stage（その周のクリア面数＝周頭で0にリセット）へ変更。
--     gate = boss_round_stage*3 + boss_round_role
--   ・1周目：boss_round_stage は cleared_stage と常に等しい（面ボス撃破で同時に前進）ので、数式は完全に同一＝挙動不変。
--   ・2周目以降：周頭で boss_round_stage=0 → gate=0 → step1(面1浅)だけ。
--       2周目の中A撃破→role=1→gate=1→step2 / 中B撃破→role=2→gate=2→step3 / 面ボス撃破→stage+1,role=0→gate=3→step4 …
--       ＝1周目と同じ順次解放。
--
-- 不変（0064と一字一句同じ）：
--   ・デッキ上限 v_max_decks は cleared_stage 基準のまま（恒常解放＝周回で減らない）。
--   ・面4/7/8 の特設ゲート（本体合計／属性／★）・占有ロック・回収・返り値・revoke/grant。
--   ・変更点は (a) 宣言に v_round_stage 追加 (b) SELECT に boss_round_stage 追加 (c) gate 計算行の3箇所のみ。
--
-- 手動適用（Supabase SQL Editor）：0064 の後（実体は最新の start_tansaku を上書き）に1回実行 → schema_migrations に 0082 登録。
--   ※旧「全面開放版0082」は適用していない前提。万一作っていてもこの create or replace が正しい版で上書きします。
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
  v_round_stage integer;                      -- ★追加：その周のクリア面数（boss_round_stage）
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

  -- ★変更：cleared_stage（恒常）に加えて boss_round_stage（その周の進行）も取得。
  select cleared_stage, boss_round_stage, boss_round_role
    into v_cleared, v_round_stage, v_role
    from public.profiles where id = v_uid;

  -- 面別解放ゲート（canon-06 §3-2・ボス進行相乗り）。
  -- ★変更：その周の進行で判定（boss_round_stage*3 + boss_round_role）。1周目は cleared_stage と一致＝従来どおり。
  v_step := (v_area - 1) * 3 + v_depth;                                       -- 1..24
  v_gate := coalesce(v_round_stage, 0) * 3 + coalesce(v_role, 0);             -- その周の累積撃破ノード数
  if v_gate < v_step - 1 then raise exception 'EXPLORE_LOCKED'; end if;       -- step1(面1浅)は常時開放（gate>=0）

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

  -- デッキ上限は恒常解放のまま cleared_stage 基準（周回で減らない）。
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

-- 台帳登録（既にあればスキップ）
insert into public.schema_migrations (version) values ('0082') on conflict (version) do nothing;
