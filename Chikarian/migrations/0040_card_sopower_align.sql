-- ============================================================
-- Chikarian migration 0040: _chikarian_card_sopower を戦闘(do_boss_battle)と同算法に統一
--   canon-04 §1（★式0.10・総合=(装備項+本体)×(1+0.10★)）／§3（qatk 10/15/22/34）
--   ＋ SP改定(2026-06-18) SP本体3,200。canon-07 §3「要追従」。
--
--   _chikarian_card_sopower は「カードの素の総合戦力（発動前・三すくみ/スキルなし）」＝
--   ミッションの deck_power 判定用（0020 で3枚合計を取る・唯一の呼び出し元）。
--   これが do_boss_battle と別算法（旧★式0.15・旧qatk7/15/33/73・旧SP本体2260…）のままで、
--   0026(★式0.10)/0031・0032(qatk)/0039(SP本体3200) の追従から漏れていた＝本ファイルで一致させる。
--
--   変更点（戦闘と一致）：
--     ・総合 = (装備項 + 本体) × (1 + 0.10×★)。★は総合に乗せる（本体非依存）。旧＝本体に×(1+0.15★)。
--     ・装備項 = loaded × 枠攻撃力。枠攻撃力 7/15/33/73 → 10/15/22/34。SPは装備項0。
--     ・SP本体 dragon2260/girl2160/houou2060 → 3種とも 3,200（2026-06-18改定）。
--     ・本体 = レア基礎 × (1+(Lv-1)×2/(上限-1))。レア基礎/上限(N80/30・R200/40・SR360/50・SSR560/60・SP—/50)は不変。
--
--   ⚠ 注意：本変更で deck_power の値が変わる。ミッションの deck_power しきい値（mission_master・0020）は
--      旧算法基準なので、再シミュでのしきい値見直しが要る（しきい値の正は別途・本ファイルは算法のみ）。
--   前提: 0020 適用済み。シグネチャ不変＝呼び出し元(0020)は無改修。内部ヘルパー＝grant無し。
-- ============================================================

-- カードの素の総合戦力（発動前・三すくみ/スキルなし）。deck_power 判定用。
-- 戦闘(do_boss_battle)と同算法：総合 = (装備項 + 本体) × (1+0.10×★)。装備項=loaded×枠攻撃力(10/15/22/34)。SPは装備項0。
create or replace function public._chikarian_card_sopower(
  p_card_key text, p_lv integer, p_star integer, p_quality text, p_loaded numeric
) returns numeric
language plpgsql immutable as $$
declare
  v_rare text; v_base numeric; v_cap integer; v_rL numeric; v_lv integer; v_atk integer;
  v_star_mult numeric; v_body numeric;
begin
  if p_card_key is null then return 0; end if;
  v_rare := public._chikarian_rarity(p_card_key);
  v_lv := coalesce(p_lv, 1);
  v_star_mult := 1 + 0.10 * coalesce(p_star, 0);          -- ★は総合に乗せる（0.10・本体非依存）
  if v_rare = 'sp' then
    v_base := 3200;                                        -- SP本体3種同値（2026-06-18改定・旧2260/2160/2060）
    v_cap := 50; v_rL := 2.0 / (v_cap - 1);
    v_body := v_base * (1 + (least(v_lv, v_cap) - 1) * v_rL);
    return v_body * v_star_mult;                           -- SPは装備項0＝総合=本体×(1+0.10★)
  end if;
  case v_rare
    when 'n'   then v_base := 80;  v_cap := 30;
    when 'r'   then v_base := 200; v_cap := 40;
    when 'sr'  then v_base := 360; v_cap := 50;
    when 'ssr' then v_base := 560; v_cap := 60;
    else return 0;
  end case;
  v_rL   := 2.0 / (v_cap - 1);
  v_atk  := case p_quality when 'crude' then 10 when 'refined' then 15
                           when 'enchanted' then 22 when 'holy' then 34 else 0 end;
  v_body := v_base * (1 + (least(v_lv, v_cap) - 1) * v_rL);
  return (coalesce(p_loaded,0) * v_atk + v_body) * v_star_mult;   -- 総合=(装備項+本体)×(1+0.10★)
end; $$;
