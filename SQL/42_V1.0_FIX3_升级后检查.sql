-- 九霄问道 V1.0 FIX3 部署后检查（只读）
select 'battle_story_function' as check_name,
       to_regprocedure('public.bcombat01_world_event_story_fix3(jsonb,jsonb,uuid,integer,bigint,jsonb)') is not null as ok,
       '挑战界闻文案函数存在' as detail
union all
select 'battle_story_function_private',
       not has_function_privilege('authenticated','public.bcombat01_world_event_story_fix3(jsonb,jsonb,uuid,integer,bigint,jsonb)','execute'),
       '普通玩家不能直接调用界闻文案函数'
union all
select 'battle_story_trigger',
       exists(select 1 from pg_trigger where tgname='trg_bcombat01_refresh_world_event_fix3' and not tgisinternal),
       '挑战界闻重写触发器存在'
union all
select 'battle_challenge_available',
       to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)') is not null
       and has_function_privilege('authenticated','public.challenge_battle_power_bcombat01(uuid,uuid)','execute'),
       '挑战结算RPC仍可调用'
union all
select 'release_cache33',
       exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1 and cache_epoch>=33 and release_name='V1.0 FIX3 CACHE33'),
       '发布门禁已提升至V1.0 FIX3 CACHE33';
