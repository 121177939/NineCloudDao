-- 九霄问道 V1.0 FIX1 升级前检查（只读）
-- 适用于已经部署 V1.0 CACHE30 的正式库。
select 'release_cache30_or_higher' as check_name,
       coalesce((select cache_epoch>=30 from public.jiuxiao_app_release_control where singleton_id=1),false) as ok,
       '正式库应已部署V1.0 CACHE30' as detail
union all
select 'battle_challenge_rpc',
       to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)') is not null,
       '挑战结算RPC存在'
union all
select 'world_feed_smallint_publisher',
       to_regprocedure('public.world_event_publish_v0140(uuid,integer,text,smallint,uuid,text,text,text,text,text,jsonb,boolean,timestamptz)') is not null,
       '既有九霄界闻发布函数存在'
union all
select 'release_control',
       to_regclass('public.jiuxiao_app_release_control') is not null,
       '发布控制表存在';
