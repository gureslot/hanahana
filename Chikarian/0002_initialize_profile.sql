-- =============================================================================
-- 0002 : profiles 初期化RPC（get-or-create）＋ renkiden ＋ 初期デッキ2本
-- 出典: supabase-spec §6③ の最初  /  balance §10(初期デッキ2)・§11(練気殿Lv1)
-- 実行: SQL Editor に貼って Run（再実行可。create or replace なので上書き）。
-- 性質: 冪等（get-or-create）。ログイン後に毎回呼んでOK＝初回は作成・以降は取得のみ。
-- 呼び方(クライアント): supabase.rpc('initialize_profile')
-- =============================================================================

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

  -- ▼▼ 新規プレイヤーへの初期付与 【※balance未定義＝仮・要確認】 ▼▼
  --   ここの定数だけ変えれば開始所持を調整できる。
  START_CHIKARIUM constant bigint := 300;  -- A案(推奨): 初回ガチャ1回ぶん。B案=0 / C案=900
  START_MEDAL     constant bigint := 0;
  --   crystal_blue/red/rainbow・hoshou_stone・exp_book_s/m/l は profiles の列default(=0)のまま。
  --   初期配布カードは無し（チカリウムでガチャを引く設計＝A案。直接カードは配らない）。
  -- ▲▲
begin
  if uid is null then
    raise exception 'not authenticated';  -- JWT必須。SQL Editor(postgres)からは呼べない（クライアント経由で検証）
  end if;

  -- profiles（既存なら作らない＝冪等。残りの列は default が入る）
  insert into public.profiles (id, chikarium, medal, saishu_date, boss_date, cleared_stage)
  values (uid, START_CHIKARIUM, START_MEDAL, today, today, 0)
  on conflict (id) do nothing;

  -- 練気殿（ユーザ1行・Lv1）
  insert into public.renkiden (user_id, lv, buki_stored, fuel_medal, last_calc_at)
  values (uid, 1, 0, 0, now())
  on conflict (user_id) do nothing;

  -- 初期デッキ2本（空＝スロットnull）。balance §10「初期デッキ数2」
  insert into public.decks (user_id, deck_no) values (uid, 1)
    on conflict (user_id, deck_no) do nothing;
  insert into public.decks (user_id, deck_no) values (uid, 2)
    on conflict (user_id, deck_no) do nothing;

  select * into prof from public.profiles where id = uid;
  return prof;
end;
$$;

-- 実行権限: ログイン済みユーザのみ（anon/public からは呼べない）
revoke all on function public.initialize_profile() from public;
grant execute on function public.initialize_profile() to authenticated;

-- =============================================================================
-- 備考:
--  * 採取上限/ボス3回などの「日次リセット判定」は各処理RPC側で today(JST) と比較する。
--    本関数は saishu_date/boss_date に当日を入れて初期化するだけ。
--  * kajiya_orders は作らない（鍛冶屋Lv=claimed済み最大質から導出＝行が無ければ粗製=初期）。
--  * tansaku_states/sp_states/missions/zukan/cards も初期行なし（各処理RPCで発生時に作る）。
-- =============================================================================
