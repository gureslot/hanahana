-- ============================================================
-- Chikarian migration 0022: 新規ユーザーの profiles 初期化トリガ
-- 目的: Google サインインで auth.users に行ができた時、public.profiles を自動作成。
--       （SPAの本番ログインで必須。dev で手動作成していた人は、本番前にこれを入れる）
-- ※ 既に同等のトリガがあるなら適用不要。idempotent（drop & create）なので二重適用は安全。
--
-- 前提: 0001 の profiles 各列に DEFAULT が入っていること（chikarium/medal/crystal_* 等=0、
--       saishu_date/boss_date 等）。もし NOT NULL なのに DEFAULT が無い列があれば、
--       下の insert にその列と初期値を明示してください（例: saishu_today=0 等）。
-- ============================================================

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.profiles (id) values (new.id)
    on conflict (id) do nothing;
  -- 練気殿の行は各RPC（settle）が遅延作成するので必須ではない。
  -- 事前に作りたい場合は次を有効化:
  -- insert into public.renkiden (user_id, lv, buki_stored, fuel_medal, last_calc_at)
  --   values (new.id, 1, 0, 0, now()) on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
