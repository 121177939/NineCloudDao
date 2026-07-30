-- 九霄问道 V1.2 FIX3 CACHE40 升级后检查（只读）
select 'release_cache40' check_name,
       exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1 and cache_epoch>=40 and release_name='V1.2 FIX3 CACHE40') ok,
       '发布门禁已提升到CACHE40' detail
union all
select 'paigow_lobby_rpc',to_regprocedure('public.get_paigow_lobby_bpaigow01()') is not null,'牌九大厅接口存在'
union all
select 'paigow_advance_rpc',to_regprocedure('public.advance_paigow_round_bpaigow01(uuid)') is not null,'牌局推进接口存在'
union all
select 'paigow_create_room_rpc',to_regprocedure('public.create_paigow_room_bpaigow01(text,text,text,text,bigint)') is not null,'创建房间接口存在且底注使用bigint'
union all
select 'physical_tiles_32',(select count(*)=32 from public.paigow_tile_defs_bpaigow01),'传统32张实体骨牌保持完整'
union all
select 'secure_shuffle',position('casino_secure_random_int_v1' in pg_get_functiondef(to_regprocedure('public.paigow_shuffle_deck_bpaigow01()')))>0,'服务端安全洗牌保持不变'
union all
select 'private_secret_table',to_regclass('public.paigow_round_secrets_bpaigow01') is not null and not has_table_privilege('authenticated','public.paigow_round_secrets_bpaigow01','select'),'牌堆与私牌仍不可由客户端读取'
union all
select 'player_fee_250bps',exists(select 1 from public.paigow_settings_bpaigow01 where singleton_id=1 and player_fee_bps=250),'玩家局2.5%手续费保持不变'
union all
select 'mutation_system_retained',to_regprocedure('public.get_my_birth_result_v12()') is not null and exists(select 1 from public.battle_challenge_settings_bcombat01 where singleton_id=1 and mutation_final_damage_bonus=0.08),'V1.2变异灵根与战斗体系保持不变';
