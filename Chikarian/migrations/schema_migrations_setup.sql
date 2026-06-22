-- ============================================================
-- Chikarian: schema_migrations 台帳 セットアップ＋バックフィル（0001〜0058・統合版）
--   この1本だけで完結（テーブル作成 → RLS有効 → 既存分登録 → 確認）。順序依存なし。
--   読み取り以外は INSERT のみ・on conflict do nothing＝何度 Run しても安全。
--
--   方針：
--     ・0001〜0047 は アプリ稼働＝適用済みが自明 → 無条件登録（0023を除く）。
--     ・0023 / 0048〜0056 は repo に .sql があるが「適用済みか」を実DBで検査して当てる（憶測しない）。
--       判定は「修正で“消えた”識別子の不在」または「追加された列の存在」を用いる（誤検出回避）。
--     ・0057/0058 はユーザーが SQL エディタで Run 済みと確認（2026-06-21）→無条件登録。
--       ※ repo の .sql は未コミット＝フェーズ1-1 で pg_get_functiondef をダンプして正本化する。
--
--   ※ 実行時に Supabase が「RLS未有効」を警告した場合：下の alter で本スクリプト自身が
--      RLS を有効化するため、どちらのボタンでも結果は RLS=ON。迷ったら「Run and enable RLS」。
--      ポリシーは追加しない＝anon/authenticated は全拒否（台帳はクライアント非公開）。
--      SQLエディタは owner 実行で RLS をバイパスするため、登録・確認クエリは通常どおり通る。
-- ============================================================

-- 0. テーブル（冪等）＋ RLS 有効（ポリシーなし＝クライアント全拒否）
create table if not exists public.schema_migrations (
  version    text primary key,
  applied_at timestamptz not null default now()
);
alter table public.schema_migrations enable row level security;

-- (A) 0001〜0047 のうち、アプリ稼働＝適用済みが自明な分を無条件登録（0023を除く）
insert into public.schema_migrations (version) values
  ('0001'),('0002'),('0003'),('0004'),('0005'),('0006'),('0007'),('0008'),('0009'),('0010'),
  ('0011'),('0012'),('0013'),('0014'),('0015'),('0016'),('0017'),('0018'),('0019'),('0020'),
  ('0021'),('0022'),('0024'),('0025'),('0026'),('0027'),('0028'),('0029'),('0030'),('0031'),
  ('0032'),('0033'),('0034'),('0035'),('0036'),('0037'),('0038'),('0039'),('0040'),('0041'),
  ('0042'),('0043'),('0044'),('0045'),('0046'),('0047')
on conflict (version) do nothing;

-- (B) 不確実な分（0023ロック / 0048〜0052）は実DBを検査し、検出できた分だけ登録
with checks as (
  select
    exists(select 1 from pg_proc where pronamespace='public'::regnamespace
           and proname='set_card_lock')                                            as m0023,
    exists(select 1 from public.boss_master where stage=8 and base_power=129300)    as m0048,
    exists(select 1 from pg_proc where pronamespace='public'::regnamespace
           and proname='do_boss_battle'    and pg_get_functiondef(oid) ilike '%draw%')        as m0049,
    exists(select 1 from pg_proc where pronamespace='public'::regnamespace
           and proname='update_deck'       and pg_get_functiondef(oid) ilike '%buki_stored%') as m0050,
    exists(select 1 from pg_proc where pronamespace='public'::regnamespace
           and proname='initialize_profile'
           and pg_get_functiondef(oid) like '%1000%' and pg_get_functiondef(oid) like '%1500%') as m0051,
    exists(select 1 from pg_proc where pronamespace='public'::regnamespace
           and proname='do_card_exchange_bulk')                                     as m0052
)
insert into public.schema_migrations (version)
select t.ver
from checks c
cross join lateral (values
  ('0023', c.m0023),('0048', c.m0048),('0049', c.m0049),
  ('0050', c.m0050),('0051', c.m0051),('0052', c.m0052)
) as t(ver, ok)
where t.ok
on conflict (version) do nothing;

-- (D) 0053〜0056 も実DB検査で登録（修正で消えた識別子の不在 / 追加列の存在）
with checks as (
  select
    -- 0053: do_card_exchange_bulk の個数式バグ修正。旧(0052)は base_value_blue 参照→修正で消滅。
    exists(select 1 from pg_proc where pronamespace='public'::regnamespace
           and proname='do_card_exchange_bulk'
           and pg_get_functiondef(oid) not ilike '%base_value_blue%')               as m0053,
    -- 0054: ボス面内ノード順次解放。profiles.boss_round_role 列の追加が一意なシグネチャ。
    exists(select 1 from information_schema.columns
           where table_schema='public' and table_name='profiles'
           and column_name='boss_round_role')                                       as m0054,
    -- 0055: do_skill_teni 上書き対応。旧(0035)の DST_SLOT_OCCUPIED を撤廃→定義から消滅。
    exists(select 1 from pg_proc where pronamespace='public'::regnamespace
           and proname='do_skill_teni'
           and pg_get_functiondef(oid) not ilike '%DST_SLOT_OCCUPIED%')             as m0055,
    -- 0056: do_kyoka からロック本体拒否(BASE_LOCKED)を除去→定義から消滅（MATERIAL_LOCKED は維持）。
    exists(select 1 from pg_proc where pronamespace='public'::regnamespace
           and proname='do_kyoka'
           and pg_get_functiondef(oid) not ilike '%BASE_LOCKED%')                   as m0056
)
insert into public.schema_migrations (version)
select t.ver
from checks c
cross join lateral (values
  ('0053', c.m0053),('0054', c.m0054),('0055', c.m0055),('0056', c.m0056)
) as t(ver, ok)
where t.ok
on conflict (version) do nothing;

-- (E) 0057/0058：ユーザー適用確認済み（2026-06-21）→無条件登録。
--     本文は repo 未コミット＝フェーズ1-1 で
--       select pg_get_functiondef('public.collect_tansaku'::regproc);
--       select pg_get_functiondef('public.start_tansaku'::regproc);
--     をダンプして 0057/0058.sql として正本化（repo == Supabase を保証）。
insert into public.schema_migrations (version) values
  ('0057'), ('0058')
on conflict (version) do nothing;

-- (F) 結果確認（この表を貼っていただければ私が照合します）
select version, applied_at from public.schema_migrations order by version;
