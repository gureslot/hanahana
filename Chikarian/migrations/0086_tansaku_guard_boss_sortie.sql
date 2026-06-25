-- ============================================================
-- Chikarian migration 0086: 探索の占有ロックに「ボス出撃中」を追加（start_tansaku 再定義・土台=0082）
--   ※ 0085 は 0085_terms_consent.sql で使用済みのため 0086 を採番（0085 の後に適用する）。
--
-- 不具合（ユーザー報告 2026-06-25）：
--   ボス戦に出撃中のデッキ（cards.boss_deck_no が付いた状態）を、そのまま探索にも派遣できてしまう。
--   結果、同じデッキが boss_sorties と tansaku_states の両方に居座り、二重ロック状態になる。
--
-- 原因（根本）：
--   start_tansaku の占有ロックが tansaku_deck_no だけを見ていた。
--   0042 で共通ガード _chikarian_assert_not_in_tansaku を「探索 or ボス出撃中なら拒否」に拡張したが、
--   start_tansaku だけは共通ガードを呼ばず自前の EXISTS（tansaku_deck_no のみ）で判定していたため、
--   ボス出撃(boss_deck_no)が判定から漏れていた。
--   ※ 放置 run_auto_houchi(0071) は boss_deck_no も見て除外済み＝今回の漏れは手動 start_tansaku のみ。
--
-- 修正：
--   start_tansaku の占有ロックを、他の資産RPC（update_deck / start_boss_battle 等）と同じ
--   共通ガード _chikarian_assert_not_in_tansaku に統一する。関数本体は 0082 と一字一句同じで、
--   変更は占有ロックの1ブロックのみ（解放ゲート/特設ゲート/回収/ロック付与/返り値は不変）。
--
-- 既存データの掃除（冪等）：
--   旧バグで二重ロックになったカードがあれば、誤って付いた「探索側」だけを巻き戻す（ボス出撃は温存）。
--   = 該当デッキの tansaku_states 行を削除＋ tansaku_deck_no を null（boss_deck_no は残す）。
--   ※ その探索の途中蓄積は破棄（本来出られないはずの探索のため）。二重ロックが無ければ何もしない。
--
-- 前提：0042（cards.boss_deck_no／共通ガード）・0082（現行 start_tansaku）・0085（採番済み）適用済み。
--
-- 適用（手動・Supabase SQL Editor）：
--   1) このファイルを貼って Run（create or replace → 掃除DO → self-register まで1回で完結／再実行安全）。
--   2) 末尾の「確認クエリ」で検証（A:関数存在 / B:二重ロック0件 / C:機能テスト / D:台帳）。
--   3) このファイルを Chikarian/migrations/ に追加してコミット＆プッシュ。
--
-- 注意（repo 差分）：2026-06-25 時点で GitHub origin/main のマイグレーションは 0075 までしか入っていない
--   （0076〜0085 は手元の正本にはあるが未プッシュの様子）。本 0086 は手元の最新 start_tansaku＝0082 を
--   土台にした。もし手元の正本に 0082 より新しい start_tansaku 定義があれば、その本体に同じ
--   占有ロック変更（下記4行＝slot取得＋perform 共通ガード3回）を当て直すこと。
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

  -- 占有ロック（canon-06 §3-4 / 0042）：このデッキの編成カードが「探索中 or ボス出撃中」なら出発を拒否。
  --   ★0086 修正：旧版は tansaku_deck_no だけを見ており、ボス出撃中(boss_deck_no)のデッキを探索に
  --     二重派遣できてしまっていた。他の資産RPC（update_deck / start_boss_battle 等）と同じく
  --     共通ガード _chikarian_assert_not_in_tansaku に統一（tansaku_deck_no か boss_deck_no が
  --     非NULL なら CARD_IN_TANSAKU）。
  select slot1_card_id, slot2_card_id, slot3_card_id into v_s1, v_s2, v_s3
    from public.decks where user_id = v_uid and deck_no = p_deck_no;
  perform public._chikarian_assert_not_in_tansaku(v_s1);
  perform public._chikarian_assert_not_in_tansaku(v_s2);
  perform public._chikarian_assert_not_in_tansaku(v_s3);

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

-- ============================================================
-- (掃除・冪等) 旧バグの二重ロックを解消：ボス出撃中なのに探索lockも付いたデッキの「探索側」だけを取り消す。
--   対象＝同一カードに boss_deck_no と tansaku_deck_no が両方付いている（旧 start_tansaku の二重派遣の痕跡）。
--   ボス出撃（boss_sorties / boss_deck_no）はユーザーの意図した行動なので温存し、誤った探索のみ巻き戻す。
--   二重ロックが無ければ 0 行＝何もしない。
-- ============================================================
-- 1) 誤って作られた探索状態を削除（該当デッキ）
delete from public.tansaku_states ts
 using public.cards c
 where c.user_id        = ts.user_id
   and c.tansaku_deck_no = ts.deck_no
   and c.boss_deck_no   is not null
   and c.tansaku_deck_no is not null;

-- 2) 探索lockだけ解除（ボスlockは残す）
update public.cards
   set tansaku_deck_no = null
 where boss_deck_no    is not null
   and tansaku_deck_no is not null;

-- 台帳登録（既にあればスキップ）
insert into public.schema_migrations (version) values ('0086') on conflict (version) do nothing;

-- ============================================================
-- 確認クエリ（任意）
--   A. 関数が置き換わったか（1行）：
--        select proname from pg_proc where proname = 'start_tansaku';
--   B. 二重ロックが残っていないか（0行が正常）：
--        select id, boss_deck_no, tansaku_deck_no from public.cards
--         where boss_deck_no is not null and tansaku_deck_no is not null;
--   C. 機能テスト（自分のアカウントで）：
--        1) あるデッキでボスに出撃（start_boss_battle）→ そのデッキを探索に派遣（start_tansaku）すると
--           CARD_IN_TANSAKU で拒否されること。
--        2) ボス出撃していない通常デッキは従来どおり探索に出られること。
--   D. 台帳：select version from public.schema_migrations where version = '0086';
-- ============================================================
