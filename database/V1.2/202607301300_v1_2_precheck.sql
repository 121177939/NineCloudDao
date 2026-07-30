-- 九霄问道 V1.2 CACHE37：升级前检查（只读）
select 'release_cache36_or_newer' check_name,
  exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1 and cache_epoch>=36) ok,
  '数据库至少为V1.1 FIX1 CACHE36' detail
union all select 'spirit_root_tables',to_regclass('public.spirit_roots') is not null and to_regclass('public.character_spirit_roots') is not null,'灵根定义及角色灵根表存在'
union all select 'fate_tables',to_regclass('public.fates') is not null and to_regclass('public.character_fates') is not null,'命格定义及角色命格表存在'
union all select 'combat_tables',to_regclass('public.character_combat_profiles_bcombat01') is not null and to_regclass('public.battle_challenge_settings_bcombat01') is not null,'五行战斗资料及设置表存在'
union all select 'combat_functions',to_regprocedure('public.bcombat01_character_snapshot(uuid)') is not null and to_regprocedure('public.bcombat01_resolve_hit(jsonb,jsonb,integer,integer,integer)') is not null,'战斗快照和伤害函数存在'
union all select 'root_reroll_rpc',to_regprocedure('public.use_spirit_washing_pill_v0154(uuid)') is not null,'洗灵丹RPC存在'
union all select 'sword_heart_exists',exists(select 1 from public.fates where code='sword_heart'),'天生剑心命格存在'
union all select 'mutant_root_exists',exists(select 1 from public.spirit_roots where concat_ws(' ',name,code,rarity) ~* '(变异|异灵根|variant|mutant)'),'变异灵根定义存在'
union all select 'secure_rng_compat',to_regprocedure('public.casino_secure_random_int_v1(integer)') is not null and position('gen_random_bytes' in lower(pg_get_functiondef(to_regprocedure('public.casino_secure_random_int_v1(integer)'))))=0,'64号兼容随机修复已执行';
