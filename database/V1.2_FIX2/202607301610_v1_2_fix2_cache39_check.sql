-- 九霄问道 V1.2 FIX2 CACHE39 升级后检查（只读）
select 'release_cache39' check_name,
       exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1 and cache_epoch>=39 and release_name='V1.2 FIX2 CACHE39') ok,
       '发布门禁已提升到CACHE39' detail
union all
select 'create_room_hotfix77',
       position('1::smallint' in pg_get_functiondef('public.create_paigow_room_bpaigow01(text,text,text,text,bigint)'::regprocedure))>0,
       '创建房间自动入座显式使用smallint'
union all
select 'start_round_hotfix78_record',
       position('v_member record' in pg_get_functiondef('public.start_paigow_round_bpaigow01(uuid,uuid)'::regprocedure))>0,
       '开局函数不再使用冲突record变量m'
union all
select 'start_round_hotfix78_alias',
       position('from public.paigow_room_members_bpaigow01 as rm' in pg_get_functiondef('public.start_paigow_round_bpaigow01(uuid,uuid)'::regprocedure))>0,
       '开局成员查询使用独立表别名rm'
union all
select 'physical_tiles_32',(select count(*)=32 from public.paigow_tile_defs_bpaigow01),'传统32张实体骨牌完整'
union all
select 'secure_shuffle',position('casino_secure_random_int_v1' in pg_get_functiondef(to_regprocedure('public.paigow_shuffle_deck_bpaigow01()')))>0,'洗牌仍使用服务端安全随机'
union all
select 'private_secret_table',to_regclass('public.paigow_round_secrets_bpaigow01') is not null and not has_table_privilege('authenticated','public.paigow_round_secrets_bpaigow01','select'),'牌堆与私牌仍不可由客户端直读'
union all
select 'player_fee_250bps',exists(select 1 from public.paigow_settings_bpaigow01 where singleton_id=1 and player_fee_bps=250),'玩家局2.5%手续费保持不变'
union all
select 'mutation_system_retained',to_regprocedure('public.get_my_birth_result_v12()') is not null and exists(select 1 from public.battle_challenge_settings_bcombat01 where singleton_id=1 and mutation_final_damage_bonus=0.08),'V1.2变异灵根与战斗体系保持不变';
