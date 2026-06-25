-- ============================================================
-- 0085_terms_consent.sql
--   利用規約・プライバシーポリシーへの同意の記録。
--   ・profiles に「同意した版（tos_version）」と「同意日時（tos_agreed_at）」を持たせる。
--   ・agree_terms(p_version) RPC で記録する（資産は一切動かさない）。
--   ・RLS は profiles の既存ポリシー（SELECT 自分の行）のまま。getProfile が直SELECTで読むので
--     追加カラムは自動でクライアントに届く。
--   方針：認証必須・SECURITY DEFINER・authenticated にのみ EXECUTE 付与（0071 と同じ規約）。
-- ============================================================

-- 1) profiles に同意カラムを追加（IF NOT EXISTS＝再実行安全）
alter table public.profiles
  add column if not exists tos_version   text,
  add column if not exists tos_agreed_at timestamptz;

-- 2) 同意記録 RPC
create or replace function public.agree_terms(p_version text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then raise exception 'NOT_AUTHENTICATED'; end if;
  if p_version is null or btrim(p_version) = '' then raise exception 'VERSION_REQUIRED'; end if;

  update public.profiles
     set tos_version   = p_version,
         tos_agreed_at = now()
   where id = v_uid;

  if not found then raise exception 'PROFILE_NOT_FOUND'; end if;

  return jsonb_build_object('version', p_version, 'agreed_at', now());
end;
$$;

revoke all on function public.agree_terms(text) from public, anon;
grant execute on function public.agree_terms(text) to authenticated;

-- 3) 台帳登録（再実行安全）
insert into public.schema_migrations (version) values ('0085') on conflict (version) do nothing;

-- 4) 確認用（任意）
-- select version from public.schema_migrations where version = '0085';
-- select column_name from information_schema.columns where table_name='profiles' and column_name in ('tos_version','tos_agreed_at');
