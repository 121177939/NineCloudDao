-- 九霄问道 V1.0 FIX2 升级前检查（只读）
-- 适用于已经部署 V1.0 FIX1 CACHE31 的正式库。
select 'release_cache31_or_higher' as check_name,
       coalesce((select cache_epoch>=31 from public.jiuxiao_app_release_control where singleton_id=1),false) as ok,
       '正式库应已部署V1.0 FIX1 CACHE31' as detail
union all
select 'battle_ranking_rpc',
       to_regprocedure('public.get_battle_power_ranking_bcombat01(integer,integer)') is not null,
       '战力榜RPC存在'
union all
select 'battle_challenge_preview_rpc',
       to_regprocedure('public.get_battle_challenge_preview_bcombat01(uuid)') is not null,
       '挑战预览RPC存在'
union all
select 'battle_challenge_rpc',
       to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)') is not null,
       '挑战结算RPC存在'
union all
select 'release_control',
       to_regclass('public.jiuxiao_app_release_control') is not null,
       '发布控制表存在';
