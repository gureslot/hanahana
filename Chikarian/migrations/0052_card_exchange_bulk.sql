-- ============================================================
-- Chikarian migration 0052: 一括交換 do_card_exchange_bulk(uuid[])
-- 0019 (do_card_exchange) の仕組みをそのままバッチ化したもの。
--   仕様（0019準拠）:
--     カード → クリスタル（青/赤/虹）の一方向交換。全レア対応（SP含む）。
--     個数 = round( base_value_blue × (1 + 0.20×★) ÷ divisor )  ※レートは crystal_exchange_master（0019）。
--     N→青 / R→赤 / SR・SSR・SP→虹。装備の質・EXP(Lv)は価値に含めない。
--   一括用の追加挙動:
--     ・配列の各カードを検証し、所持外/ロック中/探索・ボス出撃中(tansaku_deck_no|boss_deck_no)は安全に SKIP。
--     ・有効カードのみ削除（デッキ枠null化・sp_states/card_skills削除・図鑑zukanは残す＝収集ミッション用）。
--     ・付与クリスタルは色ごとに合算し profiles を1回更新（原子性: 単一トランザクション）。
--   返り: exchanged/skipped 件数・色別獲得数・更新後の各クリスタル総数。
-- 規約は 0019/0012 準拠。crystal_exchange_master と _chikarian_rarity は 0019 で作成済み（前提）。
-- ============================================================

create or replace function public.do_card_exchange_bulk(p_card_ids uuid[])
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_id  uuid;
  v_card record;
  v_rare text;
  v_m   record;
  v_cnt int;
  v_blue int := 0; v_red int := 0; v_rb int := 0;
  v_n int := 0; v_skipped int := 0;
  v_new_blue int; v_new_red int; v_new_rainbow int;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_card_ids is null or array_length(p_card_ids, 1) is null then
    raise exception 'NO_CARDS';
  end if;

  foreach v_id in array p_card_ids loop
    -- 行ロックして検証。無効カードは SKIP（バッチ全体は止めない）
    select * into v_card from public.cards
      where id = v_id and user_id = v_uid
      for update;
    if not found then v_skipped := v_skipped + 1; continue; end if;
    if v_card.locked then v_skipped := v_skipped + 1; continue; end if;
    if v_card.tansaku_deck_no is not null or v_card.boss_deck_no is not null then
      v_skipped := v_skipped + 1; continue;   -- 探索/ボス出撃中は交換不可（安全）
    end if;

    v_rare := public._chikarian_rarity(v_card.card_key);
    select * into v_m from public.crystal_exchange_master where rarity = v_rare;
    if not found then v_skipped := v_skipped + 1; continue; end if;

    v_cnt := greatest(0, round(v_m.base_value_blue * (1 + v_m.star_coeff * v_card.star) / v_m.divisor))::int;
    if v_m.crystal_color = 'blue' then
      v_blue := v_blue + v_cnt;
    elsif v_m.crystal_color = 'red' then
      v_red := v_red + v_cnt;
    else
      v_rb := v_rb + v_cnt;
    end if;

    -- 安全消滅（デッキ枠null化・関連行削除・図鑑は残す）
    update public.decks set slot1_card_id = null where user_id = v_uid and slot1_card_id = v_id;
    update public.decks set slot2_card_id = null where user_id = v_uid and slot2_card_id = v_id;
    update public.decks set slot3_card_id = null where user_id = v_uid and slot3_card_id = v_id;
    delete from public.sp_states  where card_id = v_id;
    delete from public.card_skills where card_id = v_id;
    delete from public.cards where id = v_id and user_id = v_uid;

    v_n := v_n + 1;
  end loop;

  update public.profiles
     set crystal_blue    = crystal_blue    + v_blue,
         crystal_red     = crystal_red     + v_red,
         crystal_rainbow = crystal_rainbow + v_rb
   where id = v_uid
   returning crystal_blue, crystal_red, crystal_rainbow
        into v_new_blue, v_new_red, v_new_rainbow;

  return jsonb_build_object(
    'exchanged',       v_n,
    'skipped',         v_skipped,
    'blue_gained',     v_blue,
    'red_gained',      v_red,
    'rainbow_gained',  v_rb,
    'crystal_blue',    v_new_blue,
    'crystal_red',     v_new_red,
    'crystal_rainbow', v_new_rainbow
  );
end;
$$;

revoke all on function public.do_card_exchange_bulk(uuid[]) from public, anon;
grant execute on function public.do_card_exchange_bulk(uuid[]) to authenticated;
