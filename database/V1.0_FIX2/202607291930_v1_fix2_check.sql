-- 九霄问道 V1.0 FIX2 部署后检查（只读）
select 'battle_ranking_available' as check_name,
       to_regprocedure('public.get_battle_power_ranking_bcombat01(integer,integer)') is not null
       and has_function_privilege('authenticated','public.get_battle_power_ranking_bcombat01(integer,integer)','execute') as ok,
       '战力榜RPC存在且authenticated可调用' as detail
union all
select 'battle_preview_available',
       to_regprocedure('public.get_battle_challenge_preview_bcombat01(uuid)') is not null
       and has_function_privilege('authenticated','public.get_battle_challenge_preview_bcombat01(uuid)','execute'),
       '挑战预览RPC存在且authenticated可调用'
union all
select 'battle_challenge_available',
       to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)') is not null
       and has_function_privilege('authenticated','public.challenge_battle_power_bcombat01(uuid,uuid)','execute'),
       '挑战结算RPC存在且authenticated可调用'
union all
select 'release_cache32',
       exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1 and cache_epoch>=32 and release_name='V1.0 FIX2 CACHE32'),
       '发布门禁已提升至V1.0 FIX2 CACHE32';
