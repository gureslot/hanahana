-- =============================================================================
-- 0051 : 初回配布を canon-06 §0.5 の確定値へ（C-10）
--   付与：チカリウム1,000・メダル1,500・EXP本中(exp_book_m)×3・武気(renkiden.buki_stored)600・恩寵石0。
--   旧：0002=チカ300/メダル0/配布なし、0022トリガ=profiles(id)のみ（→他列は既定0）。
--   初期化は2経路：handle_new_user トリガ(0022/サインイン時)・initialize_profile RPC(0002/ログイン時)。
--   両経路とも profiles・renkiden を「on conflict do nothing」で作成＝行は最初の経路が一度だけ作る
--   ＝二重配布は起きない（一回限り）。crystal_*/hoshou_stone/exp_book_s,l は列 default(0)。
--   ※サーバのみ（クライアント変更不要＝プロフィール値を読むだけ）。
--   ※既存アカウントには再付与されない（行が既存＝on conflict）。新規サインインから有効。再実行可。
-- =============================================================================

-- 1) サインイン時トリガ（0022 を置換）：profiles＋renkiden を配布値で事前作成
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- 初回配布（canon-06 §0.5・一回限り）。saishu_date/boss_date/cleared_stage 等は列 default を使用。
  insert into public.profiles (id, chikarium, medal, exp_book_m)
    values (new.id, 1000, 1500, 3)
    on conflict (id) do nothing;
  -- 武気プール 600（renkiden を事前作成）
  insert into public.renkiden (user_id, lv, buki_stored, fuel_medal, last_calc_at)
    values (new.id, 1, 600, 0, now())
    on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 2) get-or-create RPC（0002 を置換）：トリガ未設置/未発火でも同じ配布を保証（on conflict で二重なし）
create or replace function public.initialize_profile()
returns public.profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  uid   uuid := auth.uid();
  today date := (now() at time zone 'Asia/Tokyo')::date;  -- JST当日
  prof  public.profiles;
begin
  if uid is null then
    raise exception 'not authenticated';
  end if;

  -- 初回配布（canon-06 §0.5・一回限り）：チカ1,000・メダル1,500・EXP本中×3。
  insert into public.profiles (id, chikarium, medal, exp_book_m, saishu_date, boss_date, cleared_stage)
  values (uid, 1000, 1500, 3, today, today, 0)
  on conflict (id) do nothing;

  -- 練気殿（ユーザ1行・Lv1・武気プール600）
  insert into public.renkiden (user_id, lv, buki_stored, fuel_medal, last_calc_at)
  values (uid, 1, 600, 0, now())
  on conflict (user_id) do nothing;

  -- 初期デッキ2本（balance §10）
  insert into public.decks (user_id, deck_no) values (uid, 1)
    on conflict (user_id, deck_no) do nothing;
  insert into public.decks (user_id, deck_no) values (uid, 2)
    on conflict (user_id, deck_no) do nothing;

  select * into prof from public.profiles where id = uid;
  return prof;
end;
$$;

revoke all on function public.initialize_profile() from public;
grant execute on function public.initialize_profile() to authenticated;

-- =============================================================================
-- 備考：
--  * 既存のテストアカウントで配布を確認したい場合のみ、自分の1行に対して手動UPDATE可（任意・dev）：
--      update public.profiles set chikarium=chikarium+1000, medal=medal+1500, exp_book_m=exp_book_m+3 where id = auth.uid();
--      update public.renkiden set buki_stored=buki_stored+600 where user_id = auth.uid();
--    ※これは「追加付与」なので二重配布注意。新規サインインでは 0051 が自動で一回だけ配る。
--  * canon-07 §3/§81 の「初回配布＝要追従」は本適用で解消（canon側の表記更新は別途）。
-- =============================================================================
