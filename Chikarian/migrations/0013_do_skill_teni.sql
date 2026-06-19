-- ============================================================
-- Chikarian migration 0013: do_skill_teni (スキル転移 / skill transfer)
-- canon: skill-kyoka-tenni-spec §2, balance §3, supabase-spec §2
-- 規約は 0012 に準拠（_chikarian_rarity を使うため 0012 適用後に流す）。
--
-- 仕様:
--   素材カードの固定(slot0)/追加(slot1,2)どれか1スキルを、対象カードの
--   空き枠(slot1 or 2)へ「移動」(複製なし・Lv持ち込み)。
--   素材カードは消滅（選ばなかったスキルも失われる）。メダル3,000。失敗なし。
--   受け側の固定スロット(slot0)は不可侵。SPは送り/受けとも対象外。
--   ガード: 素材がロック中なら拒否（誤消費防止・spec沈黙のため安全側）。
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

  -- 取り出すスキル（固定slot0でも可）
  select skill_key, skill_lv into v_skill
    from public.card_skills where card_id = p_src_id and slot = p_src_slot;
  if not found then raise exception 'SRC_SKILL_NOT_FOUND'; end if;

  -- 受け側の空き枠確認（既に埋まっていれば不可）
  perform 1 from public.card_skills where card_id = p_dst_id and slot = p_dst_slot;
  if found then raise exception 'DST_SLOT_OCCUPIED'; end if;

  -- メダル検証・消費
  select medal into v_medal_have from public.profiles where id = v_uid for update;
  if v_medal_have < v_cost then raise exception 'INSUFFICIENT_MEDAL'; end if;
  update public.profiles set medal = medal - v_cost where id = v_uid;

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
    'medal_spent',     v_cost,
    'medal_remaining', v_medal_have - v_cost
  );
end;
$$;

revoke all on function public.do_skill_teni(uuid, integer, uuid, integer) from public, anon;
grant execute on function public.do_skill_teni(uuid, integer, uuid, integer) to authenticated;
