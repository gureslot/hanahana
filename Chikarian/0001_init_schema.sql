-- =============================================================================
-- チカリアン Supabase マイグレーション 0001 : 初期スキーマ（テーブル11本 + RLS）
-- 出典: supabase-spec-2026-06-12.md §6①  /  用語: hikitsugi §2  /  数値・式の正: balance
-- 実行: Supabase SQL Editor に貼って一度実行（postgres ロールで実行される前提）。
-- 再実行可: create ... if not exists / drop policy if exists で冪等。
-- =============================================================================
--
-- 【セキュリティモデル（spec §0 確定方針）】
--   * 全テーブル RLS 有効。クライアント(authenticated)は「自分の行の SELECT のみ」。
--   * INSERT/UPDATE/DELETE のポリシーは一切作らない → 通常クライアントからの書込みは
--     RLS により全拒否。書込みは全て SECURITY DEFINER の RPC（③で実装）経由。
--   * RPC は postgres 所有 → テーブル所有者は own テーブルの RLS を bypass する。
--     そのため FORCE ROW LEVEL SECURITY は付けない（付けると DEFINER RPC も止まる）。
--   * service_role キーは RLS を bypass する。絶対秘匿（spec §6）。anon は公開可。
--   * ポリシーは "to authenticated"。匿名/メールどちらの認証でも uid を持つので
--     §5 の認証方式が未確定でもこのまま機能する（②で確定）。
--
-- 【時刻・0時リセット（spec §0 確定方針）】
--   * 時刻は全て timestamptz/date のサーバ絶対時刻で保存。残り時間は保存しない。
--   * 日次リセットの「保存日付 < 今日 ならリセット」判定は ③の RPC 内で JST 基準で行う。
--     本ファイルの date 列 default は初期化時の安全網として JST 当日を入れる:
--       (now() at time zone 'Asia/Tokyo')::date
--
-- 【DDL技術判断（私が決定・理由あり / 変更可）】
--   1) 全 user_id FK → profiles(id) ON DELETE CASCADE、profiles.id → auth.users(id)
--      ON DELETE CASCADE。auth ユーザ削除で全データが連鎖削除される。
--   2) quality 等の固定集合は enum 型でなく text + CHECK（Supabase で移行が容易）。
--   3) 通貨(chikarium/medal)は bigint、その他カウンタは integer。
--   4) id 系 PK は gen_random_uuid()（PG15 コア・拡張不要）。
--
-- 【※要確認フラグ（balance/§5 由来・このまま実行可・後で調整可）】
--   A) 開始値: 通貨・クリスタル・書・renkiden.lv・cards.lv/star の default は
--      0 / lv=1 / star=0。実際の初期付与は profiles 初期化 RPC(③)が balance に従って
--      設定する前提。cards.star の開始値（0 か レア基準か）は balance を確認したい。
--   B) tansaku_states.depth = smallint 1/2/3（1=浅・2=中・3=深）、area = smallint(エリア番号)。
--      この符号化は RPC のレート対応表に影響。確認したい。
--   C) kajiya_orders.quality = refined/enchanted/holy のみ（粗製=初期で発注対象外）。確認したい。
--   D) 防御目的の追加（外しても可）: 資源列の非負 CHECK / 鍛冶屋「1件ずつ」を担保する
--      部分 UNIQUE / decks スロットの ON DELETE SET NULL / card_skills・sp_states の CASCADE。
--   E) tansaku_states・renkiden の PK は (user_id, deck_no) / user_id（spec の "1行" 記述に基づく私の確定）。
--
-- =============================================================================


-- ============================== 1. profiles =================================
-- auth.users と 1:1。所持枠 = 300 + 100*cleared_stage（最大 1100）は算出値なので列は持たない。
create table if not exists public.profiles (
  id                uuid        primary key references auth.users(id) on delete cascade,
  chikarium         bigint      not null default 0 check (chikarium >= 0),
  medal             bigint      not null default 0 check (medal >= 0),
  crystal_blue      integer     not null default 0 check (crystal_blue >= 0),
  crystal_red       integer     not null default 0 check (crystal_red >= 0),
  crystal_rainbow   integer     not null default 0 check (crystal_rainbow >= 0),
  hoshou_stone      integer     not null default 0 check (hoshou_stone >= 0),   -- 確率保証石
  exp_book_s        integer     not null default 0 check (exp_book_s >= 0),     -- 経験の書 小
  exp_book_m        integer     not null default 0 check (exp_book_m >= 0),     -- 経験の書 中
  exp_book_l        integer     not null default 0 check (exp_book_l >= 0),     -- 経験の書 大
  saishu_today      integer     not null default 0 check (saishu_today >= 0),   -- 採取 日次（上限1000）
  saishu_date       date        not null default (now() at time zone 'Asia/Tokyo')::date,
  boss_count_today  integer     not null default 0 check (boss_count_today >= 0), -- ボス 1日3回
  boss_date         date        not null default (now() at time zone 'Asia/Tokyo')::date,
  cleared_stage     smallint    not null default 0 check (cleared_stage between 0 and 8),
  created_at        timestamptz not null default now()
);


-- ================================ 2. cards ==================================
-- 41種(cards.md準拠)。card_key の master テーブルは持たず RPC で検証。
-- quality は SP=NULL（CHECK は NULL を許容）。loaded_buki は §9 損失で減る。
create table if not exists public.cards (
  id           uuid        primary key default gen_random_uuid(),
  user_id      uuid        not null references public.profiles(id) on delete cascade,
  card_key     text        not null,
  lv           integer     not null default 1   check (lv >= 1),
  exp          integer     not null default 0   check (exp >= 0),
  star         smallint    not null default 0   check (star >= 0),
  quality      text        check (quality in ('crude','refined','enchanted','holy')), -- SP は NULL
  loaded_buki  integer     not null default 0   check (loaded_buki >= 0),  -- 込めた武気
  locked       boolean     not null default false,
  obtained_at  timestamptz not null default now()
);
create index if not exists cards_user_id_idx on public.cards (user_id);


-- ============================= 3. card_skills ===============================
-- slot 0=固定 / 1・2=空き。固定スキル抽選結果もここ。
-- 転移 = 行移動 + 素材カード削除（RPC側）。カード削除でスキルも CASCADE。
create table if not exists public.card_skills (
  card_id    uuid     not null references public.cards(id) on delete cascade,
  slot       smallint not null check (slot in (0,1,2)),
  skill_key  text     not null,                       -- SP専用3種を含む
  skill_lv   integer  not null default 1 check (skill_lv >= 1),
  primary key (card_id, slot)
);


-- =============================== 4. decks ===================================
-- デッキ3枚（絶対固定）。本数上限は §5 未確定のため deck_no に上限 CHECK は置かない。
-- スロットは空き可(NULL)。参照カード削除時はスロットを NULL に（RPC でも整理）。
create table if not exists public.decks (
  user_id        uuid     not null references public.profiles(id) on delete cascade,
  deck_no        smallint not null,
  slot1_card_id  uuid     references public.cards(id) on delete set null,
  slot2_card_id  uuid     references public.cards(id) on delete set null,
  slot3_card_id  uuid     references public.cards(id) on delete set null,
  primary key (user_id, deck_no)
);


-- ========================== 5. tansaku_states ===============================
-- デッキ単位の探索状態。蓄積上限なし＝経過分×レートで回収。
-- depth: 1=浅 / 2=中 / 3=深（レート/EXP は balance）。is_houchi=放置(1面浅域自動)。
create table if not exists public.tansaku_states (
  user_id          uuid        not null references public.profiles(id) on delete cascade,
  deck_no          smallint    not null,
  area             smallint    not null,                       -- 探索エリア番号
  depth            smallint    not null check (depth in (1,2,3)),
  last_collect_at  timestamptz not null default now(),
  is_houchi        boolean     not null default false,
  primary key (user_id, deck_no)
);


-- =============================== 6. renkiden ================================
-- 錬気殿: ユーザ1行。レート 0.1*Lv/秒・保管上限 1000+1500*(Lv-1)（balance）。
-- fuel_medal=投資中残メダル（単価5）。値の更新は時刻計算 RPC。
create table if not exists public.renkiden (
  user_id      uuid        primary key references public.profiles(id) on delete cascade,
  lv           integer     not null default 1 check (lv >= 1),
  buki_stored  integer     not null default 0 check (buki_stored >= 0),  -- 武気プール
  fuel_medal   integer     not null default 0 check (fuel_medal >= 0),
  last_calc_at timestamptz not null default now()
);


-- ============================ 7. kajiya_orders ==============================
-- 鍛冶屋発注。done_at=完成時刻(精製24h/魔装36h/聖装48h は発注RPCで now()+interval)。
-- 鍛冶屋Lv は claimed 済み最大質から導出（粗製=初期）。「1件ずつ」を部分UNIQUEで担保。
create table if not exists public.kajiya_orders (
  id        uuid        primary key default gen_random_uuid(),
  user_id   uuid        not null references public.profiles(id) on delete cascade,
  quality   text        not null check (quality in ('refined','enchanted','holy')),
  done_at   timestamptz not null,
  claimed   boolean     not null default false
);
-- 未claimed行は user あたり最大1件（= 新規依頼拒否を DB でも担保）
create unique index if not exists kajiya_orders_one_active_per_user
  on public.kajiya_orders (user_id) where (claimed = false);


-- ============================== 8. sp_states ================================
-- SP発動日離脱・翌0時復帰。編成/探索/出撃の検証に使用。判定は ③の RPC で JST。
create table if not exists public.sp_states (
  card_id           uuid primary key references public.cards(id) on delete cascade,
  unavailable_until date not null
);


-- ============================= 9. battle_logs ===============================
-- 追記のみ（INSERT 専用ポリシー無し＝RPC のみ挿入。UPDATE/DELETE はポリシー無しで不可）。
create table if not exists public.battle_logs (
  id            uuid        primary key default gen_random_uuid(),
  user_id       uuid        not null references public.profiles(id) on delete cascade,
  boss_key      text        not null,
  win           boolean     not null,
  deck          jsonb,                       -- 使用デッキのスナップショット
  fired_skills  jsonb,                       -- 発動スキル
  rewards       jsonb,                       -- 報酬
  loss_rate     numeric,                     -- clamp(0.5R, 0.10, 1.00)
  fought_at     timestamptz not null default now()
);
create index if not exists battle_logs_user_fought_idx on public.battle_logs (user_id, fought_at desc);


-- =============================== 10. missions ===============================
-- period_start: デイリー=日付 / 週=週初 / 達成=固定。PK=3列。
create table if not exists public.missions (
  user_id      uuid     not null references public.profiles(id) on delete cascade,
  mission_key  text     not null,
  period_start date     not null,
  progress     integer  not null default 0 check (progress >= 0),
  claimed      boolean  not null default false,
  primary key (user_id, mission_key, period_start)
);


-- ================================ 11. zukan =================================
-- 図鑑収集ミッション(10/20/30/41種)の判定用。カード消滅後も残る。
create table if not exists public.zukan (
  user_id   uuid        not null references public.profiles(id) on delete cascade,
  card_key  text        not null,
  first_at  timestamptz not null default now(),
  primary key (user_id, card_key)
);


-- =============================================================================
-- RLS: 全テーブル有効化 + 「自分の行の SELECT のみ」。DML ポリシーは作らない。
-- =============================================================================

-- profiles -------------------------------------------------------------------
alter table public.profiles enable row level security;
drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select to authenticated using (id = auth.uid());

-- cards ----------------------------------------------------------------------
alter table public.cards enable row level security;
drop policy if exists cards_select_own on public.cards;
create policy cards_select_own on public.cards
  for select to authenticated using (user_id = auth.uid());

-- card_skills（user_id を持たない → 親 cards 経由で所有確認）-------------------
alter table public.card_skills enable row level security;
drop policy if exists card_skills_select_own on public.card_skills;
create policy card_skills_select_own on public.card_skills
  for select to authenticated using (
    exists (
      select 1 from public.cards c
      where c.id = card_skills.card_id and c.user_id = auth.uid()
    )
  );

-- decks ----------------------------------------------------------------------
alter table public.decks enable row level security;
drop policy if exists decks_select_own on public.decks;
create policy decks_select_own on public.decks
  for select to authenticated using (user_id = auth.uid());

-- tansaku_states -------------------------------------------------------------
alter table public.tansaku_states enable row level security;
drop policy if exists tansaku_states_select_own on public.tansaku_states;
create policy tansaku_states_select_own on public.tansaku_states
  for select to authenticated using (user_id = auth.uid());

-- renkiden -------------------------------------------------------------------
alter table public.renkiden enable row level security;
drop policy if exists renkiden_select_own on public.renkiden;
create policy renkiden_select_own on public.renkiden
  for select to authenticated using (user_id = auth.uid());

-- kajiya_orders --------------------------------------------------------------
alter table public.kajiya_orders enable row level security;
drop policy if exists kajiya_orders_select_own on public.kajiya_orders;
create policy kajiya_orders_select_own on public.kajiya_orders
  for select to authenticated using (user_id = auth.uid());

-- sp_states（user_id を持たない → 親 cards 経由で所有確認）---------------------
alter table public.sp_states enable row level security;
drop policy if exists sp_states_select_own on public.sp_states;
create policy sp_states_select_own on public.sp_states
  for select to authenticated using (
    exists (
      select 1 from public.cards c
      where c.id = sp_states.card_id and c.user_id = auth.uid()
    )
  );

-- battle_logs（SELECT のみ。INSERT は RPC、UPDATE/DELETE 不可）-----------------
alter table public.battle_logs enable row level security;
drop policy if exists battle_logs_select_own on public.battle_logs;
create policy battle_logs_select_own on public.battle_logs
  for select to authenticated using (user_id = auth.uid());

-- missions -------------------------------------------------------------------
alter table public.missions enable row level security;
drop policy if exists missions_select_own on public.missions;
create policy missions_select_own on public.missions
  for select to authenticated using (user_id = auth.uid());

-- zukan ----------------------------------------------------------------------
alter table public.zukan enable row level security;
drop policy if exists zukan_select_own on public.zukan;
create policy zukan_select_own on public.zukan
  for select to authenticated using (user_id = auth.uid());

-- =============================================================================
-- ここまで 0001。RPC（③）・認証設定（②）は本ファイルに含めない。
-- =============================================================================
