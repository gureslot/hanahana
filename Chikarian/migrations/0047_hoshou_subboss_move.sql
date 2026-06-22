-- =============================================================================
-- 0047 : 恩寵石供給を「面ボス初回 +1」→「副ボスB（中ボスB）初回 +1」へ移管【推奨案=総合8維持】
--   背景：恩寵石は整数（1個）。副ボスにドロップを足すと1周あたり最低 +8 増えるため、
--         1周目総合を 8（canon-04 §2＝D38に要る5+余裕3）に保つには供給源を「移す」のが整合的。
--   変更：do_boss_battle の報酬部のみ。面ボス初回 → 恩寵石を付けない（cleared_stage 前進は維持）。
--         代わりに 副ボスB（v_role='b'）の 1周目初回撃破で hoshou_stone += 1。
--         初回判定＝battle_logs に同一 boss_key の勝利が無いこと（本戦闘の log は後段で追記＝未記録）。
--   ※start_boss_battle は不変（0046 のまま）。SP離脱スキップ等 0046 の全ロジックを継承。
--   ※Option B（総合16・より寛容）に切替えたい場合は本文コメント参照（面ボス側の +1 を戻すだけ）。
--   実行：SQL Editor に貼って Run（create or replace・再実行可）。前提：0046 適用済み。
-- =============================================================================

-- 4) 既存 do_boss_battle(integer, text) を破棄し、p_from_sortie 付き3引数版に置換
drop function if exists public.do_boss_battle(integer, text);

create or replace function public.do_boss_battle(p_deck_no integer, p_boss_key text, p_from_sortie boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  uid       uuid := auth.uid();
  today     date := (now() at time zone 'Asia/Tokyo')::date;
  tomorrow  date := ((now() at time zone 'Asia/Tokyo')::date) + 1;
  prof      public.profiles;
  v_boss_count int;
  -- boss_key 解析
  m         text[];
  v_stage   int;
  v_role    text;
  v_round   int;
  v_role_idx int;
  v_boss    public.boss_master;
  v_enemy   numeric;
  -- デッキ
  v_deck    public.decks;
  slot_ids  uuid[];
  i         int;
  cid       uuid;
  vc        public.cards;
  parts     text[];
  v_is_sp   boolean;
  v_attr    text;
  v_weap    text;
  rare      text;
  base      numeric;
  lvcap     int;
  qatk      numeric;
  -- 三すくみ
  v_sukumi  numeric;
  ea        text;
  ew        text;
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
  if not p_from_sortie and v_boss_count >= 3 then raise exception 'boss daily limit reached (3/day)'; end if;

  -- boss_key 解析: boss_{1-8}_{a|b|boss}[_r{N}]
  m := regexp_match(p_boss_key, '^boss_([1-8])_(a|b|boss)(?:_r([0-9]+))?$');
  if m is null then raise exception 'invalid boss_key %', p_boss_key; end if;
  v_stage    := m[1]::int;
  v_role     := m[2];
  v_round    := coalesce(m[3]::int, 1);
  if v_round < 1 then v_round := 1; end if;
  v_role_idx := case v_role when 'a' then 1 when 'b' then 2 else 3 end;

  -- 7. 敵戦力＝boss_master.base_power（§6-1）× N周目。属性/武器も取得（_r{N}は剥がして基底キーで引く）。
  select * into v_boss from public.boss_master where boss_key = 'boss_' || v_stage || '_' || v_role;
  if not found then raise exception 'boss % not found in boss_master', 'boss_' || v_stage || '_' || v_role; end if;
  v_enemy := v_boss.base_power * v_round;

  -- (1) 周回フロンティア検証（canon-07 §4）：到達点以下のみ戦える。それ以外は BOSS_LOCKED。
  --     許可: v_round < boss_round（過去周＝再戦可）
  --         / v_round = boss_round かつ v_stage ≤ boss_round_stage+1（現周の先頭未クリア面まで）
  if not p_from_sortie then   -- 出撃版は start_boss_battle でフロンティア検証済み
    if v_round > prof.boss_round
       or (v_round = prof.boss_round and v_stage > prof.boss_round_stage + 1) then
      raise exception 'BOSS_LOCKED';
    end if;
  end if;

  -- 2. デッキ取得
  select * into v_deck from public.decks where user_id = uid and deck_no = p_deck_no;
  if not found then raise exception 'deck % not found', p_deck_no; end if;
  slot_ids := array[v_deck.slot1_card_id, v_deck.slot2_card_id, v_deck.slot3_card_id];

  -- 占有ロック：探索中カードでは出撃不可（canon-06 §3-4）
  if not p_from_sortie then   -- 出撃版(collect)は当該デッキが占有中＝正常なのでスキップ
    perform public._chikarian_assert_not_in_tansaku(slot_ids[1]);
    perform public._chikarian_assert_not_in_tansaku(slot_ids[2]);
    perform public._chikarian_assert_not_in_tansaku(slot_ids[3]);
  end if;

  -- temp 作業表（トランザクション終了で破棄）
  create temp table _bc (
    idx int, card_id uuid, is_sp boolean, attr text, weap text,
    body numeric, equip numeric, sougou numeric, add_pct numeric default 0,
    sukumi numeric default 1.0, star int default 0
  ) on commit drop;
  create temp table _cand (
    owner_idx int, skill_key text, effect_type text, target_scope text,
    target_group text, target_group2 text, val numeric, rate numeric, is_battle boolean
  ) on commit drop;
  create temp table _fs (
    owner_idx int, skill_key text, effect_type text, target_scope text,
    target_group text, target_group2 text, val numeric
  ) on commit drop;

  -- 3. 各カードの素値（balance §2）＋ 三すくみ係数 ＋ スキル候補を展開
  for i in 1..3 loop
    cid := slot_ids[i];
    if cid is null then continue; end if;

    select * into vc from public.cards where id = cid and user_id = uid;
    if not found then raise exception 'card % not owned', cid; end if;

    -- SP離脱中はこの出撃から除外（外して出撃。start_boss_battle がロックもしない＝連れて行かない）
    if exists (select 1 from public.sp_states s where s.card_id = cid and s.unavailable_until >= today) then
      continue;
    end if;

    v_is_sp := vc.card_key like 'chara\_%\_sp' escape '\';

    if v_is_sp then
      -- SP: 本体のみ・装備項0・三すくみ常に中立(1.0)
      base := case vc.card_key when 'chara_dragon_sp' then 3200
                               when 'chara_girl_sp'   then 3200
                               when 'chara_houou_sp'  then 3200 end;  -- SP本体3種同値（2026-06-18改定・旧2260/2160/2060）
      if base is null then raise exception 'unknown SP card_key %', vc.card_key; end if;
      lvcap := 50;
      base  := base * (1 + (vc.lv - 1) * (2.0 / (lvcap - 1)));   -- 本体（Lv式のみ・★は総合形成時に乗せる=0026）
      insert into _bc(idx, card_id, is_sp, attr, weap, body, equip, sougou, sukumi, star)
      values (i, cid, true, null, null, base, 0, 0, 1.0, coalesce(vc.star,0));
    else
      parts := string_to_array(vc.card_key, '_');
      if parts[2] = 'meshibe' then v_attr := 'shin'; v_weap := 'tsue'; rare := parts[5];
      else v_attr := parts[3]; v_weap := parts[4]; rare := parts[5]; end if;

      case rare
        when 'n'   then base := 80;  lvcap := 30;
        when 'r'   then base := 200; lvcap := 40;
        when 'sr'  then base := 360; lvcap := 50;
        when 'ssr' then base := 560; lvcap := 60;
        else raise exception 'unknown rarity in %', vc.card_key;
      end case;
      base := base * (1 + (vc.lv - 1) * (2.0 / (lvcap - 1)));   -- 本体（Lv式のみ・★は総合形成時に乗せる=0026）
      qatk := case vc.quality when 'crude' then 10 when 'refined' then 15
                              when 'enchanted' then 22 when 'holy' then 34 else 0 end;

      -- 三すくみ係数＝属性係数×武器係数（敵の各属性/武器を全乗算・§2-B方式）
      v_sukumi := 1.0;
      foreach ea in array v_boss.attrs   loop v_sukumi := v_sukumi * public.sukumi_factor(v_attr, ea); end loop;
      foreach ew in array v_boss.weapons loop v_sukumi := v_sukumi * public.sukumi_factor(v_weap, ew); end loop;

      insert into _bc(idx, card_id, is_sp, attr, weap, body, equip, sougou, sukumi, star)
      values (i, cid, false, v_attr, v_weap, base, vc.loaded_buki * qatk, 0, v_sukumi, coalesce(vc.star,0));
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

  -- 4. スキル発動判定（force_activate=天啓 があれば確率スキル1つを確定発動に）
  select count(*) into v_force from _cand where effect_type = 'force_activate';
  forced_ctid := null;
  if v_force > 0 then
    select c.ctid into forced_ctid
    from _cand c
    where c.is_battle and c.effect_type <> 'force_activate' and c.rate < 1
    order by random() limit 1;
  end if;

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
    update _bc set body = body * (1 + rec.val) where attr = rec.target_group or weap = rec.target_group;
  end loop;
  for rec in select * from _fs where effect_type = 'self_burst' loop
    update _bc set body = body * rec.val where idx = rec.owner_idx;
  end loop;

  -- 5-b. soubi_pct(対象グループ装備) ＋ risk_soubi(自身装備・損失2倍) → 装備項
  for rec in select * from _fs where effect_type = 'soubi_pct' loop
    update _bc set equip = equip * (1 + rec.val) where attr = rec.target_group or weap = rec.target_group;
  end loop;
  for rec in select * from _fs where effect_type = 'risk_soubi' loop
    update _bc set equip = equip * (1 + rec.val) where idx = rec.owner_idx;
  end loop;

  -- 5-c. カード総合 = (装備項 + 本体) × (1 + 0.10×★)（canon-04 §1・canon-03 §4 step4・本体非依存）。
  --      ★は本体だけでなく装備項込みの総合に乗る。hontai_pct/soubi_pct 適用後の equip/body に掛ける。
  --      where idx is not null は sql_safe_updates 対策＝実質全行。
  update _bc set sougou = (equip + body) * (1 + 0.10 * star) where idx is not null;
  select coalesce(sum(sougou), 0) into v_own_base from _bc;
  if v_own_base <= 0 then v_R := 999; else v_R := v_enemy / v_own_base; end if;

  -- 5-d. 総合×系（同種加算）→ add_pct
  for rec in select * from _fs where effect_type = 'sougou_pct' loop
    update _bc set add_pct = add_pct + rec.val where attr = rec.target_group or weap = rec.target_group;
  end loop;
  for rec in select * from _fs where effect_type = 'kyousou_pct' loop
    update _bc set add_pct = add_pct + rec.val
    where attr in (rec.target_group, rec.target_group2) or weap in (rec.target_group, rec.target_group2);
  end loop;
  for rec in select * from _fs where effect_type = 'meshibe_group_pct' loop
    update _bc set add_pct = add_pct + rec.val where attr = 'shin' or weap = 'tsue';
  end loop;
  for rec in select * from _fs where effect_type = 'advantage_scaling' loop
    if v_R > 1 then
      update _bc set add_pct = add_pct + least(rec.val * least(v_R - 1, 1), rec.val) where idx = rec.owner_idx;
    end if;
  end loop;
  select count(*) into v_fired_count from _fs;
  for rec in select * from _fs where effect_type = 'per_skill_count' loop
    update _bc set add_pct = add_pct + rec.val * greatest(v_fired_count - 1, 0) where idx = rec.owner_idx;
  end loop;
  update _bc set sougou = sougou * (1 + add_pct) where idx is not null;

  -- 5-g. deck_sougou_pct(黄金律) → 全カード総合
  for rec in select * from _fs where effect_type = 'deck_sougou_pct' loop
    update _bc set sougou = sougou * (1 + rec.val) where idx is not null;
  end loop;

  -- 5-h. 三すくみ（カードごと・属性係数×武器係数。1面/SPは中立1.0）。
  --      amplify_advantage(絶対優勢): 自身が有利(係数>1.0)のとき係数に +base（仮+0.30）。
  for rec in select * from _fs where effect_type = 'amplify_advantage' loop
    update _bc set sukumi = sukumi + rec.val where idx = rec.owner_idx and sukumi > 1.0;
  end loop;
  update _bc set sougou = sougou * sukumi where idx is not null;

  -- 5-i. deck_sougou_mult(竜気覚醒) → デッキ総合×base（×4.0・skill_master駆動＝0027）
  for rec in select * from _fs where effect_type = 'deck_sougou_mult' loop
    update _bc set sougou = sougou * rec.val where idx is not null;
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

  -- 10. loaded_buki を損失率ぶん減算（SPは無傷）
  update public.cards c
  set loaded_buki = floor(c.loaded_buki * (1 - loss_rate))
  from _bc b
  where b.card_id = c.id and b.is_sp = false;

  -- 11. SP発動 → 当日離脱（翌0時復帰）。竜気/哀慟=発動時、不死鳥=敗北で損失0適用時。
  for rec in select owner_idx, skill_key from _fs where skill_key in ('sp_ryuki','sp_aitou','sp_fushichou') loop
    if rec.skill_key = 'sp_fushichou' and win then continue; end if;
    insert into public.sp_states(card_id, unavailable_until)
    select b.card_id, tomorrow from _bc b where b.idx = rec.owner_idx
    on conflict (card_id) do update set unavailable_until = excluded.unavailable_until;
  end loop;

  -- 1(末). ボス回数 +1
  if not p_from_sortie then   -- 出撃版は start_boss_battle で消費済み
    update public.profiles set boss_count_today = v_boss_count + 1, boss_date = today where id = uid;
  end if;

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

    -- cleared_stage：面ボス勝利 かつ stage=cleared_stage+1（1周目のみ・最大8）で +1（恩寵石は中ボスBへ移管=0047）
    if v_role = 'boss' and v_round = 1 and v_stage = prof.cleared_stage + 1 then
      update public.profiles set cleared_stage = least(v_stage, 8) where id = uid;
    end if;

    -- 恩寵石供給（canon-06 §6・0047調整）：副ボスB 初回撃破（1周目）で hoshou_stone += 1。
    --   旧「面ボス初回 +1」を中ボスBへ移して 1周目総合8 を維持（★希少性 据え置き）。
    --   初回判定＝battle_logs に同一 boss_key の勝利ログが無いこと。本戦闘の log 追記は後段(§13)なので未記録＝正しく初回を判定する。
    --   ▼Option B（総合16・より寛容＝margin 3→11）にしたい場合のみ：上の面ボスブロックを 0046 と同じ2列更新
    --     （set cleared_stage = least(v_stage,8), hoshou_stone = hoshou_stone + 1 where id=uid）に戻す。中ボスB分はそのままで合算16になる。
    if v_role = 'b' and v_round = 1
       and not exists (select 1 from public.battle_logs where user_id = uid and boss_key = p_boss_key and win) then
      update public.profiles set hoshou_stone = hoshou_stone + 1 where id = uid;
    end if;

    -- (2) 周回フロンティア前進：先頭面の面ボス勝利で boss_round_stage+1、8到達で boss_round++・stage=0
    if v_role = 'boss' and v_round = prof.boss_round and v_stage = prof.boss_round_stage + 1 then
      if prof.boss_round_stage + 1 >= 8 then
        update public.profiles set boss_round = boss_round + 1, boss_round_stage = 0 where id = uid;
      else
        update public.profiles set boss_round_stage = boss_round_stage + 1 where id = uid;
      end if;
    end if;
  end if;

  -- 13. battle_logs 追記
  select coalesce(jsonb_agg(jsonb_build_object(
           'card_id', card_id, 'is_sp', is_sp, 'sukumi', sukumi, 'sougou', round(sougou))), '[]'::jsonb)
  into v_deck_snapshot from _bc;

  v_rewards := jsonb_build_object(
    'medal',     case when win then v_medal else 0 end,
    'exp_rank',  case when win then v_exp_rank else null end,
    'exp_count', case when win then v_exp_cnt else 0 end
  );

  insert into public.battle_logs(user_id, boss_key, win, deck, fired_skills, rewards, loss_rate, fought_at)
  values (uid, p_boss_key, win, v_deck_snapshot, v_fired, v_rewards, loss_rate, now());

  -- 14. 返り値
  select * into prof from public.profiles where id = uid;
  return jsonb_build_object(
    'win',              win,
    'own_power',        round(v_own),
    'enemy_power',      round(v_enemy),
    'stage',            v_stage,
    'role',             v_role,
    'round',            v_round,
    'boss_attrs',       to_jsonb(v_boss.attrs),
    'boss_weapons',     to_jsonb(v_boss.weapons),
    'fired_skills',     v_fired,
    'loss_rate',        loss_rate,
    'rewards',          v_rewards,
    'boss_count_today', prof.boss_count_today,
    'cleared_stage',    prof.cleared_stage,
    'boss_round',       prof.boss_round,
    'boss_round_stage', prof.boss_round_stage
  );
end;
$$;

revoke all on function public.do_boss_battle(integer, text, boolean) from public;
grant execute on function public.do_boss_battle(integer, text, boolean) to authenticated;
