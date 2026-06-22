-- ============================================================
-- Chikarian migration 0070: do_skill_teni に「同一スキル重複の禁止」と
--   「めしべ専用スキル→通常カードの越境禁止」を追加（canon-03 §1・§9）
-- 土台: 0055（埋まった移植枠への上書き対応）。変更点のみ:
--   ・受け側が既に同じスキルを“別枠”に持つ場合は拒否＝DUPLICATE_SKILL
--       （上書き先の枠そのものは除外＝同枠の同スキル上書き＝Lv入替は許可）。
--   ・めしべ専用スキル（skill_key が 'meshibe_' 始まり）は、受け側が“めしべ”でなければ拒否
--       ＝MESHIBE_ONLY_SKILL（通常→めしべは可・めしべ→めしべは可）。
--   ・両チェックは「素材スキル確定後・メダル消費前」に実施（消費なしで弾く）。
-- 他（メダル3,000・素材消滅・SP不可・ロック素材拒否・探索中ロック・固定slot0不可侵・replaced）は 0055 と同一。
-- ============================================================

create or replace function public.do_skill_teni(
  p_src_id   uuid,
  p_src_slot integer,
  p_dst_id   uuid,
  p_dst_slot integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_cost integer := 3000;        -- balance §3（仮）
  v_src record;
  v_dst record;
  v_skill record;
  v_medal_have bigint;
  v_replaced boolean := false;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_src_id = p_dst_id then raise exception 'SAME_CARD'; end if;
  if p_dst_slot not in (1, 2) then raise exception 'DST_SLOT_INVALID'; end if;  -- 0=固定は不可侵

  select * into v_src from public.cards where id = p_src_id and user_id = v_uid for update;
  if not found then raise exception 'SRC_NOT_FOUND'; end if;
  select * into v_dst from public.cards where id = p_dst_id and user_id = v_uid for update;
  if not found then raise exception 'DST_NOT_FOUND'; end if;

  if public._chikarian_rarity(v_src.card_key) = 'sp' then raise exception 'SP_NOT_TRANSFERABLE'; end if;
  if public._chikarian_rarity(v_dst.card_key) = 'sp' then raise exception 'SP_NO_SLOT'; end if;
  if v_src.locked then raise exception 'SRC_LOCKED'; end if;

  -- 占有ロック：探索中カードは転移の素材(src)/対象(dst)にできない（canon-06 §3-4）
  perform public._chikarian_assert_not_in_tansaku(p_src_id);
  perform public._chikarian_assert_not_in_tansaku(p_dst_id);

  -- 取り出すスキル（固定slot0でも可）
  select skill_key, skill_lv into v_skill
    from public.card_skills where card_id = p_src_id and slot = p_src_slot;
  if not found then raise exception 'SRC_SKILL_NOT_FOUND'; end if;

  -- 【0070】めしべ専用スキルは「めしべ→めしべ」のみ（canon-03 §9）。
  --   めしべ専用＝skill_key が 'meshibe_' 始まり。受け側が“めしべ”でなければ不可。
  if left(v_skill.skill_key, 8) = 'meshibe_' and v_dst.card_key not like '%meshibe%' then
    raise exception 'MESHIBE_ONLY_SKILL';
  end if;

  -- 【0070】同一スキルの重複禁止（canon-03 §1）。
  --   受け側が同じスキルを“別枠”に既に持つなら不可（上書き先の枠は除外＝同枠上書き=Lv入替は可）。
  perform 1 from public.card_skills
    where card_id = p_dst_id and slot <> p_dst_slot and skill_key = v_skill.skill_key;
  if found then raise exception 'DUPLICATE_SKILL'; end if;

  -- メダル検証・消費
  select medal into v_medal_have from public.profiles where id = v_uid for update;
  if v_medal_have < v_cost then raise exception 'INSUFFICIENT_MEDAL'; end if;
  update public.profiles set medal = medal - v_cost where id = v_uid;

  -- 受け枠に既存があれば上書き（入替）。元のスキルは失われる。
  perform 1 from public.card_skills where card_id = p_dst_id and slot = p_dst_slot;
  if found then v_replaced := true; end if;
  delete from public.card_skills where card_id = p_dst_id and slot = p_dst_slot;

  -- スキルを受け側へ挿入（Lv持ち込み）→ 素材カード（全スキル）消滅
  insert into public.card_skills (card_id, slot, skill_key, skill_lv)
    values (p_dst_id, p_dst_slot, v_skill.skill_key, v_skill.skill_lv);
  delete from public.card_skills where card_id = p_src_id;
  delete from public.cards where id = p_src_id and user_id = v_uid;

  return jsonb_build_object(
    'moved_skill',     v_skill.skill_key,
    'moved_lv',        v_skill.skill_lv,
    'dst_id',          p_dst_id,
    'dst_slot',        p_dst_slot,
    'replaced',        v_replaced,
    'medal_spent',     v_cost,
    'medal_remaining', v_medal_have - v_cost
  );
end;
$$;

revoke all on function public.do_skill_teni(uuid, integer, uuid, integer) from public, anon;
grant execute on function public.do_skill_teni(uuid, integer, uuid, integer) to authenticated;

-- 適用後: insert into public.schema_migrations (version) values ('0070') on conflict do nothing;
