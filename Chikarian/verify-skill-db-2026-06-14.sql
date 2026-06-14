-- =============================================================================
-- 存在確認SQL（0006〜0009 適用後の検証）— SQL Editor で各ブロックを実行
-- 出典: skill-db-spec-2026-06-14.md。期待値は各行コメント参照。
-- =============================================================================

-- 1) skill_master テーブルの存在 ---------------------------------------------
select to_regclass('public.skill_master') as skill_master_table;     -- 期待: public.skill_master

-- 2) skill_master の件数とレア内訳 -------------------------------------------
select count(*) as total from public.skill_master;                    -- 期待: 45
select rarity, count(*) from public.skill_master group by rarity order by rarity;
--   期待: n=14(sougou6+hontai6+util2) / r=12(sougou6+soubi6) / sr=10(連奏6+逆鱗+血焚+めしべsr2) / ssr=6(haen,yuusei,ougon,kyoumei,めしべssr2) / sp=3
select is_meshibe, count(*) from public.skill_master group by is_meshibe;  -- 期待: true=4 / false=41
select is_battle,  count(*) from public.skill_master group by is_battle;   -- 期待: false=2(n_util_*) / true=43
select count(*) as lv_fixed from public.skill_master where lv_upgradable = false;  -- 期待: 4 (sp3 + meshibe_ssr_tenkei)

-- 3) effect_type の網羅（§4の値が入っているか）--------------------------------
select effect_type, count(*) from public.skill_master group by effect_type order by 1;

-- 4) skill_master の RLS ポリシー（全員SELECT・書込みポリシー無し）-------------
select policyname, cmd from pg_policies
where schemaname = 'public' and tablename = 'skill_master';          -- 期待: skill_master_select_all / SELECT のみ

-- 5) profiles.exp_book_xl 列の追加確認 ---------------------------------------
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema='public' and table_name='profiles' and column_name='exp_book_xl';
--   期待: integer / NO / 0

-- 6) card_skills の FK（skill_key → skill_master）----------------------------
select conname, confrelid::regclass as references
from pg_constraint
where conrelid = 'public.card_skills'::regclass and contype = 'f';
--   期待: card_skills_skill_key_fk → public.skill_master

-- 7) 関数（RPC/ヘルパ）の存在と security definer -----------------------------
select p.proname, p.prosecdef as security_definer,
       pg_get_function_identity_arguments(p.oid) as args
from pg_proc p join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('do_gacha','pick_fixed_skill','do_boss_battle','use_exp_book')
order by p.proname;
--   期待:
--     do_boss_battle (integer, text)   security_definer=t
--     do_gacha       ()                security_definer=t
--     pick_fixed_skill (text)          security_definer=f（純粋抽選・definer不要）
--     use_exp_book   (uuid, text, integer) security_definer=t

-- 8) 実行権限（authenticated に grant・public は revoke）----------------------
select routine_name, grantee, privilege_type
from information_schema.routine_privileges
where specific_schema = 'public'
  and routine_name in ('do_gacha','do_boss_battle','use_exp_book')
order by routine_name, grantee;
--   期待: 各関数 grantee=authenticated / privilege=EXECUTE（public は出てこない）

-- 9) pick_fixed_skill の挙動スモーク（書込みなし・抽選確認）-------------------
--    レアごとに数回引いて、返るキーが skill_master に存在するか（FK観点）。
select k as card_key, public.pick_fixed_skill(k) as picked
from (values
  ('chara_hibiscus_hana_ken_n'),
  ('chara_hibiscus_ha_tate_r'),
  ('chara_hibiscus_shin_tsue_sr'),
  ('chara_hibiscus_hana_ken_ssr'),
  ('chara_meshibe_shin_tsue_sr'),
  ('chara_meshibe_shin_tsue_ssr'),
  ('chara_dragon_sp'), ('chara_girl_sp'), ('chara_houou_sp')
) v(k);
--   期待: picked が全て skill_master.skill_key に存在（SPは sp_ryuki/sp_aitou/sp_fushichou 固定）

-- 10) pick の妥当性（全 picked が master に居るか・孤児が無いこと）--------------
with picks as (
  select public.pick_fixed_skill(k) as sk
  from (values ('chara_hibiscus_hana_ken_n'),('chara_hibiscus_ha_tate_r'),
               ('chara_hibiscus_shin_tsue_sr'),('chara_hibiscus_hana_ken_ssr'),
               ('chara_meshibe_shin_tsue_sr'),('chara_meshibe_shin_tsue_ssr'),
               ('chara_dragon_sp'),('chara_girl_sp'),('chara_houou_sp')) v(k)
)
select count(*) filter (where m.skill_key is null) as orphan_picks   -- 期待: 0
from picks p left join public.skill_master m on m.skill_key = p.sk;

-- =============================================================================
-- 11) boss_master（0010）の存在・件数・属性/武器（boss-attr-sukumi spec）-----------
select to_regclass('public.boss_master') as boss_master_table;        -- 期待: public.boss_master
select count(*) from public.boss_master;                              -- 期待: 21
select boss_key, base_power, attrs, weapons from public.boss_master
 where boss_key in ('boss_1_a','boss_2_boss','boss_8_a','boss_8_b','boss_8_boss') order by boss_key;
--   期待: boss_1_a={}/{} ／ boss_2_boss={hana}/{ken,tate} ／ boss_8_a={hana,shin}/{ken,tsue}
--         boss_8_b={ha,shin}/{tate,tsue} ／ boss_8_boss={hana,ha}/{ken,tate}

-- 12) sukumi_factor（0011）の係数（有利1.2/不利0.8/中立1.0）------------------------
select public.sukumi_factor('hana','shin') as adv,   -- 花は芯に有利 → 1.2
       public.sukumi_factor('ha','hana')   as adv2,  -- 葉は花に有利 → 1.2
       public.sukumi_factor('shin','hana') as dis,   -- 芯は花に不利 → 0.8
       public.sukumi_factor('hana','hana') as same,  -- 同属性     → 1.0
       public.sukumi_factor(null,'hana')   as sp,    -- SP/属性なし → 1.0
       public.sukumi_factor('tsue','ken')  as wadv;  -- 杖は剣に有利 → 1.2

-- 13) 例の検算（spec §2 例：ボス花葉持ち×芯カード → 属性係数 1.2×0.8=0.96）---------
select public.sukumi_factor('shin','hana') * public.sukumi_factor('shin','ha') as expect_096;  -- 期待: 0.96

-- =============================================================================
-- 注: do_gacha / do_boss_battle / use_exp_book は auth.uid() 必須＝SQL Editor(postgres)
--     からは 'not authenticated' になる。実呼び出しはログイン済みクライアント
--     （dev/console.html 等）経由で行うこと（spec §0）。
-- =============================================================================
