-- =============================================================================
-- 0045 : ボス出撃に「復路（帰り道）」を追加
--   従来 collect_boss_result は到着時に戦闘解決→即デッキ解放だった（＝到着で即帰還）。
--   本修正で「到着＝戦闘＆報告書記録」のあと、往路と同じ時間の復路を挟んでから解放する。
--
--   ライフサイクル：
--     出撃 → 往路(travel_sec) → 到着[戦闘＋報告書記録] → 復路(travel_sec) → 帰宅[デッキ解放]
--     ・到着時の collect：do_boss_battle(...,true) で戦闘解決＋報酬＋報告書 → is_returning=true,
--       return_until = started_at + 2×travel_sec（= 復路ぶん）。デッキはまだ解放しない。
--       ※離席で往復とも経過済みなら、同じ呼び出しで戦闘＋即解放（home:true）。
--     ・帰宅時(return_done)の collect：ロック解除・行削除のみ（戦闘は到着時に済）。
--     ・キャンセル帰還(従来)：戦闘なし・行削除のみ（{canceled:true}）。return_done と同じ扱い。
--
--   ※ get_boss_sorties / cancel_boss_sortie / start_boss_battle は変更不要（phase 機械はそのまま）。
--   実行: SQL Editor に貼って Run（create or replace・再実行可）。前提: 0042 適用済み。
-- =============================================================================
create or replace function public.collect_boss_result(p_deck_no integer)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  uid uuid := auth.uid();
  v_s public.boss_sorties;
  v_res jsonb;
  v_arrive timestamptz;
  v_return_until timestamptz;
begin
  if uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select * into v_s from public.boss_sorties
    where user_id = uid and deck_no = p_deck_no for update;
  if not found then raise exception 'NOT_ON_SORTIE'; end if;

  -- 帰還中（到着後の復路 or キャンセル折り返し）
  if v_s.is_returning then
    if now() >= v_s.return_until then
      -- 帰宅 → 解放（戦闘は到着時に済 or キャンセルで無し）
      update public.cards c set boss_deck_no = null
        from public.decks d
       where d.user_id = uid and d.deck_no = p_deck_no
         and c.user_id = uid and c.id in (d.slot1_card_id, d.slot2_card_id, d.slot3_card_id);
      delete from public.boss_sorties where user_id = uid and deck_no = p_deck_no;
      return jsonb_build_object('deck_no', p_deck_no, 'home', true);
    else
      raise exception 'STILL_RETURNING';
    end if;
  end if;

  -- 通常：まだ到着していない（往路の途中）
  v_arrive := v_s.started_at + (v_s.travel_sec || ' seconds')::interval;
  if now() < v_arrive then
    raise exception 'STILL_OUT';
  end if;

  -- 到着 → 戦闘解決（出撃モード：回数/フロンティア/占有はスキップ）＋報告書
  v_res := public.do_boss_battle(p_deck_no, v_s.boss_key, true);

  -- 復路を開始（往路と同じ時間：return_until = started_at + 2×travel_sec）
  v_return_until := v_s.started_at + ((v_s.travel_sec * 2) || ' seconds')::interval;

  if now() >= v_return_until then
    -- 離席で復路も経過済み → そのまま帰宅・解放
    update public.cards c set boss_deck_no = null
      from public.decks d
     where d.user_id = uid and d.deck_no = p_deck_no
       and c.user_id = uid and c.id in (d.slot1_card_id, d.slot2_card_id, d.slot3_card_id);
    delete from public.boss_sorties where user_id = uid and deck_no = p_deck_no;
    return v_res || jsonb_build_object('canceled', false, 'arrived', true, 'returning', false, 'home', true);
  else
    -- 復路に入る（デッキは解放しない）
    update public.boss_sorties
       set is_returning = true, return_until = v_return_until
     where user_id = uid and deck_no = p_deck_no;
    return v_res || jsonb_build_object('canceled', false, 'arrived', true, 'returning', true, 'return_until', v_return_until);
  end if;
end;
$$;
revoke all on function public.collect_boss_result(integer) from public, anon;
grant execute on function public.collect_boss_result(integer) to authenticated;
