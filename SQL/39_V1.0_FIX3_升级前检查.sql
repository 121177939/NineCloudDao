-- 九霄问道 V1.0 FIX3 升级前检查（只读）
-- 适用于已部署 V1.0 FIX2 CACHE32 的正式库。
select 'release_cache32_or_higher' as check_name,
       coalesce((select cache_epoch>=32 from public.jiuxiao_app_release_control where singleton_id=1),false) as ok,
       '正式库应已部署V1.0 FIX2 CACHE32' as detail
union all
select 'battle_challenge_table',
       to_regclass('public.battle_challenges_bcombat01') is not null,
       '挑战记录表存在'
union all
select 'world_events_table',
       to_regclass('public.world_events') is not null,
       '九霄界闻表存在'
union all
select 'battle_challenge_rpc',
       to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)') is not null,
       '挑战结算RPC存在'
union all
select 'release_control',
       to_regclass('public.jiuxiao_app_release_control') is not null,
       '发布控制表存在';
