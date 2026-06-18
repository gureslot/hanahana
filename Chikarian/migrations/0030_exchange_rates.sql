-- ============================================================
-- 0030 : 交換所 do_card_exchange を新モデルへ（虹はSPのみ・個数=★0基準値×2^★）
--   canon-03 §10（2026-06-16決定）/ canon-07 §3「要追従」（交換所レート）
--
--   旧（廃止・0019）:
--     マスタ列 base_value_blue / star_coeff(0.20) / divisor、個数 = round(base_value_blue×(1+0.20★)/divisor)。
--     色: N青 / R赤 / SR・SSR・SP 虹。
--     → +0.20/★ は★1で投資割れ（誤り）。虹を SR/SSR にも配っていた（虹が律速にならない）。
--
--   新（canon §10）:
--     個数 ＝ ★0基準値 × 2^★（＝投入カード枚数。★強化は同★素材＝倍々消費なので投資保存）。
--     色割当: N・R→青 / SR・SSR→赤 / SP→虹（虹はSPからのみ＝律速資源を絞る）。
--     ★0基準値（色）: N 1（青） / R 2（青） / SR 2（赤） / SSR 6（赤） / SP 2（虹）。
--
--   マスタ表 crystal_exchange_master を新スキーマで作り直す（5行の設定マスタ・user データなし・FK参照なし）。
--   ★0基準値は仮（調整対象）。★倍率は 2^★ 固定（投資保存）。装備の質・EXP(Lv) は価値に含めない。
--   削除時の安全処理（デッキ枠null化・sp_states/card_skills 削除・図鑑zukanは残す）は 0019 と同一。
--   クライアント追従なし（交換所UIは未実装。将来 getExchangeRates は新列 base_value を返す＝個数は base_value×2^★ で算出）。
--   前提: 0019 適用済み。本ファイルで上書き。
-- ============================================================

-- マスタ表を新スキーマで作り直し（旧 base_value_blue/star_coeff/divisor を廃し base_value に一本化）
drop table if exists public.crystal_exchange_master;
create table public.crystal_exchange_master (
  rarity        text primary key check (rarity in ('n','r','sr','ssr','sp')),
  crystal_color text not null check (crystal_color in ('blue','red','rainbow')),
  base_value    integer not null    -- ★0基準値（個数 = base_value × 2^★）
);
alter table public.crystal_exchange_master enable row level security;
drop policy if exists crystal_exchange_master_select_all on public.crystal_exchange_master;
create policy crystal_exchange_master_select_all on public.crystal_exchange_master
  for select to authenticated using (true);   -- マスタは全員読取り可・書込みポリシー無し＝不可

insert into public.crystal_exchange_master (rarity, crystal_color, base_value) values
  ('n',   'blue',    1),
  ('r',   'blue',    2),
  ('sr',  'red',     2),
  ('ssr', 'red',     6),
  ('sp',  'rainbow', 2);

create or replace function public.do_card_exchange(p_card_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_card record;
  v_rare text;
  v_m record;
  v_count integer;
  v_new_blue integer; v_new_red integer; v_new_rainbow integer;
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;

  select * into v_card from public.cards where id = p_card_id and user_id = v_uid for update;
  if not found then raise exception 'CARD_NOT_FOUND'; end if;
  if v_card.locked then raise exception 'CARD_LOCKED'; end if;

  v_rare := public._chikarian_rarity(v_card.card_key);

  select * into v_m from public.crystal_exchange_master where rarity = v_rare;
  if not found then raise exception 'RARITY_NOT_EXCHANGEABLE'; end if;

  -- 個数 ＝ ★0基準値 × 2^★（投入カード枚数ぶんを返す＝投資保存）。Lv・装備の質は含めない。
  v_count := (v_m.base_value * power(2::numeric, coalesce(v_card.star, 0)))::int;

  -- カードを安全に消滅させる（デッキ枠null化・関連行削除・図鑑zukanは残す＝収集ミッション用）
  update public.decks set slot1_card_id = null where user_id = v_uid and slot1_card_id = p_card_id;
  update public.decks set slot2_card_id = null where user_id = v_uid and slot2_card_id = p_card_id;
  update public.decks set slot3_card_id = null where user_id = v_uid and slot3_card_id = p_card_id;
  delete from public.sp_states  where card_id = p_card_id;
  delete from public.card_skills where card_id = p_card_id;
  delete from public.cards where id = p_card_id and user_id = v_uid;

  -- クリスタル付与（色はレアで決定＝N/R青・SR/SSR赤・SP虹）
  if v_m.crystal_color = 'blue' then
    update public.profiles set crystal_blue = crystal_blue + v_count where id = v_uid
      returning crystal_blue, crystal_red, crystal_rainbow into v_new_blue, v_new_red, v_new_rainbow;
  elsif v_m.crystal_color = 'red' then
    update public.profiles set crystal_red = crystal_red + v_count where id = v_uid
      returning crystal_blue, crystal_red, crystal_rainbow into v_new_blue, v_new_red, v_new_rainbow;
  else
    update public.profiles set crystal_rainbow = crystal_rainbow + v_count where id = v_uid
      returning crystal_blue, crystal_red, crystal_rainbow into v_new_blue, v_new_red, v_new_rainbow;
  end if;

  return jsonb_build_object(
    'card_key',        v_card.card_key,
    'rarity',          v_rare,
    'star',            v_card.star,
    'crystal_color',   v_m.crystal_color,
    'crystal_count',   v_count,
    'crystal_blue',    v_new_blue,
    'crystal_red',     v_new_red,
    'crystal_rainbow', v_new_rainbow
  );
end;
$$;
revoke all on function public.do_card_exchange(uuid) from public, anon;
grant execute on function public.do_card_exchange(uuid) to authenticated;
