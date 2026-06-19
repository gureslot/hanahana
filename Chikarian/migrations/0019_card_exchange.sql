-- ============================================================
-- Chikarian migration 0019: 交換所 (do_card_exchange) + crystal_exchange_master
-- canon: chikarian-crystal-exchange-2026-06-14 §2/§3, design-updates-2026-06-13 ④
-- 規約は 0012 に準拠。supabase-spec §2 未記載の新RPC。
--
-- 仕様:
--   カード → クリスタル の一方向交換。ロック中カードは不可。全レア対応（SP含む）。
--   価値 = ガチャ価値(青換算) × (1 + 0.20×★)。装備の質・EXP(Lv)は価値に含めない。
--   種類変換: 青1 : 赤3.3 : 虹10。低レア=青 / R=赤 / 高レア(SR/SSR/SP)=虹。
--   個数 = round( base_value_blue × (1+0.20×★) ÷ divisor )。
--   ※ハンドテーブル(§3)との丸め差は最大±1（仮許容）。レートは下記マスタで後調整可。
--   削除前にデッキ枠null化・sp_states/card_skills削除（図鑑zukanは残す＝収集ミッション用）。
-- ============================================================

create table if not exists public.crystal_exchange_master (
  rarity          text primary key check (rarity in ('n','r','sr','ssr','sp')),
  crystal_color   text not null check (crystal_color in ('blue','red','rainbow')),
  base_value_blue numeric not null,                -- ガチャ価値（青換算・排出率の逆数）
  star_coeff      numeric not null default 0.20,   -- +20%/★（線形）
  divisor         numeric not null                 -- 青1 / 赤3.3 / 虹10
);
alter table public.crystal_exchange_master enable row level security;
drop policy if exists crystal_exchange_master_select_all on public.crystal_exchange_master;
create policy crystal_exchange_master_select_all on public.crystal_exchange_master
  for select to authenticated using (true);   -- マスタは全員読取り可・書込みポリシー無し＝不可

insert into public.crystal_exchange_master (rarity, crystal_color, base_value_blue, divisor) values
  ('n',   'blue',     16,  1),
  ('r',   'red',      28,  3.3),
  ('sr',  'rainbow',  111, 10),
  ('ssr', 'rainbow',  455, 10),
  ('sp',  'rainbow',  176, 10)
on conflict (rarity) do nothing;

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

  v_count := greatest(0, round(v_m.base_value_blue * (1 + v_m.star_coeff * v_card.star) / v_m.divisor))::int;

  -- カードを安全に消滅させる（デッキ枠null化・関連行削除・図鑑は残す）
  update public.decks set slot1_card_id = null where user_id = v_uid and slot1_card_id = p_card_id;
  update public.decks set slot2_card_id = null where user_id = v_uid and slot2_card_id = p_card_id;
  update public.decks set slot3_card_id = null where user_id = v_uid and slot3_card_id = p_card_id;
  delete from public.sp_states  where card_id = p_card_id;
  delete from public.card_skills where card_id = p_card_id;
  delete from public.cards where id = p_card_id and user_id = v_uid;

  -- クリスタル付与
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
