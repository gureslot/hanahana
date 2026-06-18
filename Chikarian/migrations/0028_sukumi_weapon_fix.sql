-- ============================================================
-- 0028 : 三すくみ武器の方向を 剣>盾 → 盾>剣 に修正
--   canon-05 §2 / canon-00 逆引き（武器 盾>剣>杖）/ canon-07 §3「要追従」
--
--   sukumi_factor を再定義。武器の輪を 剣→盾→杖→剣 から 盾→剣→杖→盾 へ。
--     武器: 盾>剣 ・ 剣>杖 ・ 杖>盾  ＝ (tate,ken) (ken,tsue) (tsue,tate)
--   属性は据え置き（花>芯>葉 ＝ (hana,shin) (shin,ha) (ha,hana)）。
--   係数: 有利 1.2 / 不利 0.8 / 中立 1.0（同種・null は中立）。
--
--   do_boss_battle は実行時に public.sukumi_factor を呼ぶだけなので、本再定義のみで反映。
--   0026（★式・do_boss_battle 再定義）は sukumi_factor を再定義しないため衝突しない。
--   クライアント側に三すくみの表示・計算は無し（戦闘時のみ・canon-03 §1）＝追従不要。
--   前提: 0011（sukumi_factor 初版）適用済み。本ファイルで上書き。
-- ============================================================

-- ===== 三すくみ係数ヘルパ（c=カード側 / e=敵側の単一属性 or 武器）====================
-- 有利1.2 / 不利0.8 / 中立1.0。輪: 花→芯→葉→花(hana→shin→ha) / 盾→剣→杖→盾(tate→ken→tsue)。
create or replace function public.sukumi_factor(c text, e text)
returns numeric
language sql
immutable
as $$
  select case
    when c is null or e is null then 1.0
    when c = e then 1.0
    when (c, e) in (('hana','shin'),('shin','ha'),('ha','hana'),
                    ('tate','ken'),('ken','tsue'),('tsue','tate')) then 1.2   -- c が e に有利
    else 0.8                                                                  -- e が c に有利
  end::numeric;
$$;
