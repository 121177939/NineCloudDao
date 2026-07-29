-- 九霄问道 V1.0 FIX1 部署后检查（只读）
select 'challenge_compat_overload' as check_name,
       to_regprocedure('public.world_event_publish_v0140(uuid,integer,text,integer,uuid,text,text,text,text,text,jsonb,boolean,timestamptz)') is not null as ok,
       'integer事件等级兼容重载存在' as detail
union all
select 'compat_not_public',
       not has_function_privilege('anon','public.world_event_publish_v0140(uuid,integer,text,integer,uuid,text,text,text,text,text,jsonb,boolean,timestamptz)','execute')
       and not has_function_privilege('authenticated','public.world_event_publish_v0140(uuid,integer,text,integer,uuid,text,text,text,text,text,jsonb,boolean,timestamptz)','execute'),
       '兼容重载没有向客户端直接开放'
union all
select 'challenge_rpc_available',
       to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)') is not null
       and has_function_privilege('authenticated','public.challenge_battle_power_bcombat01(uuid,uuid)','execute'),
       '挑战结算RPC存在且authenticated可调用'
union all
select 'release_cache31',
       exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1 and cache_epoch>=31 and release_name='V1.0 FIX1 CACHE31'),
       '发布门禁已提升至V1.0 FIX1 CACHE31';
