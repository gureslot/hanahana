-- =============================================================================
-- 0008 : do_boss_battle(deck_no, boss_key) ＝ ボス戦RPC ＋ profiles.exp_book_xl 列追加
-- 出典: skill-db-spec-2026-06-14.md §4(effect_type)・§7(手順)/ balance §2(戦力式)・§6(戦力/報酬)・§9(損失)
-- 前提: 0006(skill_master)・0007(do_gacha改修) 実行済み。
-- 実行: SQL Editor に貼って Run（create or replace・再実行可。列追加は if not exists で冪等）。
-- 呼び方: supabase.rpc('do_boss_battle', { p_deck_no: 1, p_boss_key: 'boss_1_a' })
--
-- 【boss_key 命名規則（images/ の boss_{面}_{a|b|boss}.png ＋ boss-mockup より確定）】
--   boss_{面1-8}_{a|b|boss}  例: boss_1_a / boss_3_boss / boss_8_b
--   2周目以降は末尾に _r{N}    例: boss_8_boss_r2（敵戦力 ×N・balance §6-1）
--   role: a=中ボスA / b=中ボスB / boss=面ボス。
--
-- 【勝敗＝決定的（ユーザー確定）】デッキ実戦闘力 ≥ 敵戦力 で勝ち（確率化しない）。
--
-- 【本版の確定的な決め打ち（要確認なら指摘でUPDATE可）】
--   1) 三すくみ（§7-5h）：敵の属性/武器データが現状どの canon にも無い（boss-mockup は attr='なし'）。
--      → 本版は三すくみ＝中立(×1.0)で計算（1面は元々属性中立・武器三すくみは敵データ待ち）。
--      amplify_advantage(絶対優勢)は「有利時のみ」発動効果のため、中立では実質不発（構造は残置）。
--      敵 attr/weap が定義されたら h. のブロックに乗算を入れるだけで有効化できる。
--   2) self_burst(覇焔解放)：§7 はステップ e で本体×20→総合再計算だが、本版は本体確定段階(a)で
--      ×20 を本体に乗せてから総合を組む（バースト分にも総合×系が乗る・より自然）。順序は仮。
--   3) meta_amplify(共鳴)：同カードの他発動スキルの「%系」効果量を×(1+0.30)（self_burst/敵デバフ等は対象外）。
--   4) per_skill_count(万象共鳴)：発動他スキル数＝デッキの発動戦闘スキル総数−1（自身除く）。
--   5) 格上度(advantage_scaling)：R=敵/自素総合 として +base×clamp(R-1,0,1)（上限base）。
--   6) N周目の敵戦力のみ×N。報酬(§6-2/§6-3)は周回スケールしない（balance に倍率記載なしのため据置）。
-- =============================================================================


-- ===== profiles.exp_book_xl（特大の経験の書）列を追加（balance §4：特大=1000EXP）=====
alter table public.profiles add column if not exists exp_book_xl integer not null default 0;
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_exp_book_xl_check') then
    alter table public.profiles add constraint profiles_exp_book_xl_check check (exp_book_xl >= 0);
  end if;
end $$;


create or replace function public.do_boss_battle(p_deck_no integer, p_boss_key text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid       uuid := auth.uid();
  today     date := (now() at time zone 'Asia/Tokyo')::date;   -- JST当日
  tomorrow  date := ((now() at time zone 'Asia/Tokyo')::date) + 1;
  prof      public.profiles;
  v_boss_count int;
  -- boss_key 解析
  m         text[];
  v_stage   int;
  v_role    text;
  v_round   int;
  v_role_idx int;
  v_enemy_arr int[];
  v_enemy_base numeric;
  v_enemy   numeric;
  -- デッキ
  v_deck    public.decks;
  slot_ids  uuid[];
  i         int;
  cid       uuid;
  vc        public.cards;
  parts     text[];
  is_sp     boolean;
  attr      text;
  weap      text;
  rare      text;
  base      numeric;
  lvcap     int;
  qatk      numeric;
  -- スキル発動
  v_force   int;
  forced_ctid tid;
  rec       record;
  v_fired_count int;
  -- 戦闘集計
  v_own       numeric := 0;
  v_own_base  numeric := 0;
  v_R         numeric;
  win         boolean;
  loss_rate   numeric;
  has_risk    boolean := false;
  has_nullify boolean := false;
  -- 報酬
  v_medal_arr int[];
  v_medal     int := 0;
  v_exp_rank  text;
  v_exp_cnt   int := 0;
  -- ログ/返り値
  v_fired        jsonb := '[]'::jsonb;
  v_rewards      jsonb;
  v_deck_snapshot jsonb;
  v_card_count   int;
begin
  if uid is null then raise exception 'not authenticated'; end if;

  -- 1. profile 行ロック
  select * into prof from public.profiles where id = uid for update;
  if not found then raise exception 'profile not initialized'; end if;

  -- 1. ボス 1日3回（JST 0時リセット）
  if prof.boss_date < today then v_boss_count := 0; else v_boss_count := prof.boss_count_today; end if;
  if v_boss_count >= 3 then raise exception 'boss daily limit reached (3/day)'; end if;

  -- boss_key 解析: boss_{1-8}_{a|b|boss}[_r{N}]
  m := regexp_match(p_boss_key, '^boss_([1-8])_(a|b|boss)(?:_r([0-9]+))?$');
  if m is null then raise exception 'invalid boss_key %', p_boss_key; end if;
  v_stage    := m[1]::int;
  v_role     := m[2];
  v_round    := coalesce(m[3]::int, 1);
  if v_round < 1 then v_round := 1; end if;
  v_role_idx := case v_role when 'a' then 1 when 'b' then 2 else 3 end;

  -- 7. 敵戦力（balance §6-1）× N周目
  v_enemy_arr := case v_stage
    when 1 then array[3000,5000,8000]
    when 2 then array[10000,15000,25000]
    when 3 then array[25000,35000,50000]
    when 4 then array[45000,60000,80000]
    when 5 then array[65000,80000,90000]
    when 6 then array[75000,90000,100000]
    when 7 then array[90000,100000,110000]
    when 8 then array[100000,110000,120000]
  end;
  v_enemy_base := v_enemy_arr[v_role_idx];
  v_enemy := v_enemy_base * v_round;

  -- 2. デッキ取得
  select * into v_deck from public.decks where user_id = uid and deck_no = p_deck_no;
  if not found then raise exception 'deck % not found', p_deck_no; end if;
  slot_ids := array[v_deck.slot1_card_id, v_deck.slot2_card_id, v_deck.slot3_card_id];

  -- temp 作業表（トランザクション終了で破棄）
  create temp table _bc (
    idx int, card_id uuid, is_sp boolean, attr text, weap text,
    body numeric, equip numeric, sougou numeric, add_pct numeric default 0
  ) on commit drop;
  create temp table _cand (
    owner_idx int, skill_key text, effect_type text, target_scope text,
    target_group text, target_group2 text, val numeric, rate numeric, is_battle boolean
  ) on commit drop;
  create temp table _fs (
    owner_idx int, skill_key text, effect_type text, target_scope text,
    target_group text, target_group2 text, val numeric
  ) on commit drop;

  -- 3. 各カードの素値（balance §2）＋ スキル候補を展開
  for i in 1..3 loop
    cid := slot_ids[i];
    if cid is null then continue; end if;

    select * into vc from public.cards where id = cid and user_id = uid;
    if not found then raise exception 'card % not owned', cid; end if;

    -- SP離脱中の二重チェック（編成で弾く前提・§7-2）
    if exists (select 1 from public.sp_states s where s.card_id = cid and s.unavailable_until >= today) then
      raise exception 'card % is SP-unavailable today', cid;
    end if;

    is_sp := vc.card_key like 'chara\_%\_sp' escape '\';

    if is_sp then
      attr := null; weap := null;
      base  := case vc.card_key when 'chara_dragon_sp' then 2260
                                when 'chara_girl_sp'   then 2160
                                when 'chara_houou_sp'  then 2060 end;
      if base is null then raise exception 'unknown SP card_key %', vc.card_key; end if;
      lvcap := 50;
      base  := base * (1 + (vc.lv - 1) * (2.0 / (lvcap - 1))) * (1 + 0.15 * vc.star);  -- 本体戦闘力
      insert into _bc(idx, card_id, is_sp, attr, weap, body, equip, sougou)
      values (i, cid, true, null, null, base, 0, 0);   -- SP は装備項0
    else
      parts := string_to_array(vc.card_key, '_');
      if parts[2] = 'meshibe' then attr := 'shin'; weap := 'tsue'; rare := parts[5];
      else attr := parts[3]; weap := parts[4]; rare := parts[5]; end if;

      case rare
        when 'n'   then base := 80;  lvcap := 30;
        when 'r'   then base := 200; lvcap := 40;
        when 'sr'  then base := 360; lvcap := 50;
        when 'ssr' then base := 560; lvcap := 60;
        else raise exception 'unknown rarity in %', vc.card_key;
      end case;
      base := base * (1 + (vc.lv - 1) * (2.0 / (lvcap - 1))) * (1 + 0.15 * vc.star);   -- 本体
      qatk := case vc.quality when 'crude' then 7 when 'refined' then 15
                              when 'enchanted' then 33 when 'holy' then 73 else 0 end;  -- 枠攻撃力 §2-1
      insert into _bc(idx, card_id, is_sp, attr, weap, body, equip, sougou)
      values (i, cid, false, attr, weap, base, vc.loaded_buki * qatk, 0);  -- 装備項 = 込めた武気×枠攻撃力
    end if;

    -- スキル候補（Lv効果量を確定して格納）
    insert into _cand(owner_idx, skill_key, effect_type, target_scope, target_group, target_group2, val, rate, is_battle)
    select i, sm.skill_key, sm.effect_type, sm.target_scope, sm.target_group, sm.target_group2,
           sm.base_value + (case when sm.lv_upgradable then sm.per_lv_value * (cs.skill_lv - 1) else 0 end),
           sm.activation_rate, sm.is_battle
    from public.card_skills cs
    join public.skill_master sm on sm.skill_key = cs.skill_key
    where cs.card_id = cid;
  end loop;

  select count(*) into v_card_count from _bc;
  if v_card_count = 0 then raise exception 'deck % is empty', p_deck_no; end if;

  -- 4. スキル発動判定
  --   force_activate(天啓・rate1) があれば、先に確率スキル1つを確定発動に。
  select count(*) into v_force from _cand where effect_type = 'force_activate';
  forced_ctid := null;
  if v_force > 0 then
    select c.ctid into forced_ctid
    from _cand c
    where c.is_battle and c.effect_type <> 'force_activate' and c.rate < 1
    order by random() limit 1;
  end if;

  --   各候補を activation_rate で判定（force_activate 自体は効果適用しない＝_fs に入れない）。
  for rec in
    select c.ctid as rid, c.* from _cand c
    where c.is_battle and c.effect_type <> 'force_activate'
  loop
    if not (random() < rec.rate or coalesce(rec.rid = forced_ctid, false)) then
      continue;
    end if;
    insert into _fs(owner_idx, skill_key, effect_type, target_scope, target_group, target_group2, val)
    values (rec.owner_idx, rec.skill_key, rec.effect_type, rec.target_scope, rec.target_group, rec.target_group2, rec.val);
    if rec.effect_type = 'risk_soubi'   then has_risk    := true; end if;
    if rec.effect_type = 'loss_nullify' then has_nullify := true; end if;
    v_fired := v_fired || jsonb_build_object('owner_idx', rec.owner_idx, 'skill_key', rec.skill_key, 'effect', rec.effect_type);
  end loop;

  -- 5-f. meta_amplify(共鳴): 同カードの他発動「%系」効果量を ×(1+val)
  for rec in select owner_idx, val from _fs where effect_type = 'meta_amplify' loop
    update _fs set val = val * (1 + rec.val)
    where owner_idx = rec.owner_idx
      and effect_type in ('hontai_pct','soubi_pct','sougou_pct','kyousou_pct',
                          'meshibe_group_pct','per_skill_count','advantage_scaling','amplify_advantage');
  end loop;

  -- 5-a. hontai_pct(対象グループ本体) ＋ self_burst(自身本体×base) → 本体
  for rec in select * from _fs where effect_type = 'hontai_pct' loop
    update _bc set body = body * (1 + rec.val)
    where attr = rec.target_group or weap = rec.target_group;
  end loop;
  for rec in select * from _fs where effect_type = 'self_burst' loop
    update _bc set body = body * rec.val where idx = rec.owner_idx;  -- ×20（決め打ち2参照）
  end loop;

  -- 5-b. soubi_pct(対象グループ装備) ＋ risk_soubi(自身装備・損失2倍) → 装備項
  for rec in select * from _fs where effect_type = 'soubi_pct' loop
    update _bc set equip = equip * (1 + rec.val)
    where attr = rec.target_group or weap = rec.target_group;
  end loop;
  for rec in select * from _fs where effect_type = 'risk_soubi' loop
    update _bc set equip = equip * (1 + rec.val) where idx = rec.owner_idx;
  end loop;

  -- 5-c. 総合 = 装備項 + 本体
  update _bc set sougou = equip + body;
  select coalesce(sum(sougou), 0) into v_own_base from _bc;   -- 格上度Rの基準
  if v_own_base <= 0 then v_R := 999; else v_R := v_enemy / v_own_base; end if;

  -- 5-d. 総合×系（同種加算）: sougou/kyousou/meshibe_group/advantage_scaling/per_skill_count → add_pct
  for rec in select * from _fs where effect_type = 'sougou_pct' loop
    update _bc set add_pct = add_pct + rec.val
    where attr = rec.target_group or weap = rec.target_group;
  end loop;
  for rec in select * from _fs where effect_type = 'kyousou_pct' loop
    update _bc set add_pct = add_pct + rec.val
    where attr in (rec.target_group, rec.target_group2)
       or weap in (rec.target_group, rec.target_group2);
  end loop;
  for rec in select * from _fs where effect_type = 'meshibe_group_pct' loop
    update _bc set add_pct = add_pct + rec.val
    where attr = 'shin' or weap = 'tsue';   -- 芯属性 or 杖武器の和集合（§4）
  end loop;
  for rec in select * from _fs where effect_type = 'advantage_scaling' loop
    if v_R > 1 then
      update _bc set add_pct = add_pct + least(rec.val * least(v_R - 1, 1), rec.val)
      where idx = rec.owner_idx;
    end if;
  end loop;
  select count(*) into v_fired_count from _fs;   -- 発動戦闘スキル総数（force_activateは_fsに無い）
  for rec in select * from _fs where effect_type = 'per_skill_count' loop
    update _bc set add_pct = add_pct + rec.val * greatest(v_fired_count - 1, 0)
    where idx = rec.owner_idx;
  end loop;
  update _bc set sougou = sougou * (1 + add_pct);

  -- 5-g. deck_sougou_pct(黄金律) → 全カード総合
  for rec in select * from _fs where effect_type = 'deck_sougou_pct' loop
    update _bc set sougou = sougou * (1 + rec.val);
  end loop;

  -- 5-h. 三すくみ：本版は中立(×1.0)＝乗算なし（決め打ち1参照・敵attr/weap未定義）。

  -- 5-i. deck_sougou_mult(竜気覚醒) → デッキ総合×base(×1.90)
  for rec in select * from _fs where effect_type = 'deck_sougou_mult' loop
    update _bc set sougou = sougou * rec.val;
  end loop;

  -- 6. デッキ実戦闘力
  select coalesce(sum(sougou), 0) into v_own from _bc;

  -- 7. enemy_mult(哀慟/呪詛) → 敵実戦闘力
  for rec in select * from _fs where effect_type = 'enemy_mult' loop
    v_enemy := v_enemy * rec.val;
  end loop;

  -- 8. 勝敗（決定的）
  win := v_own >= v_enemy;

  -- 9. 武気損失率 = clamp(0.5×(敵÷自), 0.10, 1.00)。risk_soubi→×2。不死鳥(敗北)→0。
  if v_own <= 0 then v_R := 1.0; else v_R := v_enemy / v_own; end if;
  loss_rate := least(greatest(0.5 * v_R, 0.10), 1.00);
  if has_risk then loss_rate := least(loss_rate * 2, 1.00); end if;
  if has_nullify and not win then loss_rate := 0; end if;

  -- 10. 各カードの loaded_buki を損失率ぶん減算（SPは無傷）
  update public.cards c
  set loaded_buki = floor(c.loaded_buki * (1 - loss_rate))
  from _bc b
  where b.card_id = c.id and b.is_sp = false;

  -- 11. SP発動 → 当日離脱（翌0時復帰）。竜気/哀慟=発動時、不死鳥=敗北で損失0適用時。
  for rec in select owner_idx, skill_key from _fs where skill_key in ('sp_ryuki','sp_aitou','sp_fushichou') loop
    if rec.skill_key = 'sp_fushichou' and win then continue; end if;   -- 不死鳥は敗北時のみ離脱
    insert into public.sp_states(card_id, unavailable_until)
    select b.card_id, tomorrow from _bc b where b.idx = rec.owner_idx
    on conflict (card_id) do update set unavailable_until = excluded.unavailable_until;
  end loop;

  -- 1(末). ボス回数 +1
  update public.profiles set boss_count_today = v_boss_count + 1, boss_date = today where id = uid;

  -- 12. 報酬（勝利時のみ・balance §6-2/§6-3）
  if win then
    v_medal_arr := case v_stage
      when 1 then array[300,600,1500]      when 2 then array[1000,2000,5000]
      when 3 then array[2500,5000,12500]   when 4 then array[4500,9000,22500]
      when 5 then array[6500,13000,32500]  when 6 then array[7500,15000,37500]
      when 7 then array[9000,18000,45000]  when 8 then array[10000,20000,50000]
    end;
    v_medal := v_medal_arr[v_role_idx];
    update public.profiles set medal = medal + v_medal where id = uid;

    -- EXP書：枚数＝A:面+1 / B:2(面+1) / 面ボス:面+2。ランク 中ボス:〜3面m/〜6面l/7-8面xl、面ボス:〜3面l/以降xl
    v_exp_cnt := case v_role when 'a' then v_stage + 1 when 'b' then 2 * (v_stage + 1) else v_stage + 2 end;
    if v_role = 'boss' then
      v_exp_rank := case when v_stage <= 3 then 'l' else 'xl' end;
    else
      v_exp_rank := case when v_stage <= 3 then 'm' when v_stage <= 6 then 'l' else 'xl' end;
    end if;
    update public.profiles set
      exp_book_m  = exp_book_m  + (case when v_exp_rank = 'm'  then v_exp_cnt else 0 end),
      exp_book_l  = exp_book_l  + (case when v_exp_rank = 'l'  then v_exp_cnt else 0 end),
      exp_book_xl = exp_book_xl + (case when v_exp_rank = 'xl' then v_exp_cnt else 0 end)
    where id = uid;

    -- cleared_stage：面ボス勝利 かつ stage=cleared_stage+1（1周目のみ・最大8）で +1
    if v_role = 'boss' and v_round = 1 and v_stage = prof.cleared_stage + 1 then
      update public.profiles set cleared_stage = least(v_stage, 8) where id = uid;
    end if;
  end if;

  -- 13. battle_logs 追記
  select coalesce(jsonb_agg(jsonb_build_object(
           'card_id', card_id, 'is_sp', is_sp, 'sougou', round(sougou))), '[]'::jsonb)
  into v_deck_snapshot from _bc;

  v_rewards := jsonb_build_object(
    'medal',     case when win then v_medal else 0 end,
    'exp_rank',  case when win then v_exp_rank else null end,
    'exp_count', case when win then v_exp_cnt else 0 end
  );

  insert into public.battle_logs(user_id, boss_key, win, deck, fired_skills, rewards, loss_rate, fought_at)
  values (uid, p_boss_key, win, v_deck_snapshot, v_fired, v_rewards, loss_rate, now());

  -- 14. 返り値
  select * into prof from public.profiles where id = uid;   -- 更新後を反映
  return jsonb_build_object(
    'win',              win,
    'own_power',        round(v_own),
    'enemy_power',      round(v_enemy),
    'stage',            v_stage,
    'role',             v_role,
    'round',            v_round,
    'fired_skills',     v_fired,
    'loss_rate',        loss_rate,
    'rewards',          v_rewards,
    'boss_count_today', prof.boss_count_today,
    'cleared_stage',    prof.cleared_stage
  );
end;
$$;

revoke all on function public.do_boss_battle(integer, text) from public;
grant execute on function public.do_boss_battle(integer, text) to authenticated;

-- =============================================================================
-- 備考:
--  * 三すくみ(§7-5h)は敵 attr/weap データが未定義のため中立(×1.0)。実装フックは 5-h コメント位置。
--  * 報酬は1周目相当（N周目は敵戦力のみ×N・報酬は据置）。周回報酬倍率が決まれば §12 ブロックで乗算。
--  * fired_skills/deck は battle_logs にスナップショット保存（追記のみ・spec §0）。
-- =============================================================================
