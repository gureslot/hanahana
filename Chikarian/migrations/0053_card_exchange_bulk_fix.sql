-- ============================================================
-- Chikarian migration 0053: do_card_exchange_bulk の個数式バグ修正
--   0052 は旧スキーマ（base_value_blue / star_coeff / divisor）参照のまま作られていたが、
--   0030 で crystal_exchange_master は base_value 一本化済み（個数 = base_value × 2^★）。
--   そのため一括交換 RPC が実行時に
--     ERROR: record "v_m" has no field "base_value_blue"
--   で失敗していた（交換所の「一括交換」が全く通らない・スクショ2,3）。
--   本マイグレーションは 0052 の関数本体のうち個数計算の1行のみを 0030 単発交換と同式に直す
--   （他の挙動＝検証/SKIP/安全消滅/色別合算/profiles更新は 0052 のまま不変）。
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

    -- 個数 = base_value × 2^★（0030 単発 do_card_exchange と同式）
    v_cnt := (v_m.base_value * power(2::numeric, coalesce(v_card.star, 0)))::int;
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
