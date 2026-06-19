-- ============================================================
-- Chikarian migration 0041: 固定スキル(slot0) バックフィル
--   canon-03 §1（1カード＝固定1(slot0)＋空き2）／§5（slot0 抽選プール）
--
--   背景：0004 do_gacha は slot0 を付与しなかった。0007 で新規ガチャには
--     pick_fixed_skill による slot0 付与を追加したが、0004時代に引いた既存カードは
--     slot0 が無いまま（0007 備考の遡及付与＝「任意」とされ未実行）。
--     → 本ファイルで、card_skills に slot0 が無い全カードに固定スキルを付与する。
--
--   安全性：
--     ・既に slot0 を持つカードは対象外（重複付与しない＝再実行可）。
--     ・付与スキルは pick_fixed_skill(card_key)＝そのカードの属性/武器/レアの
--       抽選プールから決定（SPは専用固定キー）。canon §5 と同じ規則。
--     ・slot1/2（空き枠）は触らない＝既存の転移結果はそのまま。
--   前提：0007（pick_fixed_skill）適用済み。
-- ============================================================

insert into public.card_skills (card_id, slot, skill_key, skill_lv)
select c.id, 0, public.pick_fixed_skill(c.card_key), 1
  from public.cards c
 where not exists (
   select 1 from public.card_skills s
    where s.card_id = c.id and s.slot = 0
 );

-- 確認用（任意）：実行後、0 になれば全カードに slot0 が揃った状態。
-- select count(*) from public.cards c
--  where not exists (select 1 from public.card_skills s where s.card_id = c.id and s.slot = 0);
