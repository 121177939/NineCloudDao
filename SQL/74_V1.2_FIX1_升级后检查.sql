-- 九霄问道 V1.2 FIX1 CACHE38 升级后检查（只读）
select 'release_cache38' check_name,exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1 and cache_epoch>=38 and release_name='V1.2 FIX1 CACHE38') ok,'发布门禁已提升到CACHE38' detail
union all select 'room_limit_four',to_regclass('public.paigow_rooms_bpaigow01') is not null and exists(select 1 from pg_indexes where indexname='paigow_room_slot_open_bpaigow01'),'天地玄黄最多四个开放房'
union all select 'physical_tiles_32',(select count(*)=32 from public.paigow_tile_defs_bpaigow01),'传统32张实体骨牌完整'
union all select 'secure_shuffle',position('casino_secure_random_int_v1' in pg_get_functiondef(to_regprocedure('public.paigow_shuffle_deck_bpaigow01()')))>0,'洗牌仅使用服务端安全随机'
union all select 'private_secret_table',to_regclass('public.paigow_round_secrets_bpaigow01') is not null and not has_table_privilege('authenticated','public.paigow_round_secrets_bpaigow01','select'),'牌堆和老何私牌不可由客户端直读'
union all select 'whole_table_settlement',to_regprocedure('public.paigow_settle_round_internal_bpaigow01(uuid)') is not null,'整桌单事务结算函数存在'
union all select 'idempotent_actions',to_regclass('public.paigow_action_requests_bpaigow01') is not null and to_regprocedure('public.paigow_action_claim_bpaigow01(uuid,uuid,text,jsonb)') is not null,'资金动作使用request_id幂等'
union all select 'small_big_timers',exists(select 1 from public.paigow_settings_bpaigow01 where singleton_id=1 and small_multiplier_seconds=6 and big_multiplier_seconds=10),'小牌九6秒选倍，大牌九10秒选倍'
union all select 'player_fee_250bps',exists(select 1 from public.paigow_settings_bpaigow01 where singleton_id=1 and player_fee_bps=250),'玩家局每笔确认赌注2.5%进入现有赌场资金'
union all select 'laohe_existing_bankroll',position('paigow_laohe_settlement_bpaigow01' in pg_get_functiondef(to_regprocedure('public.paigow_settle_round_internal_bpaigow01(uuid)')))>0,'老何100:100复用现有赌场资金'
union all select 'system_zero_cover_pvp',position('paigow_dealer_reserve_bpaigow01' in pg_get_functiondef(to_regprocedure('public.paigow_apply_multiplier_internal_bpaigow01(uuid,uuid,integer,boolean)')))>0,'随机庄由玩家预存最大责任，系统不兜底'
union all select 'idle_close_20m',position('20 minutes' in pg_get_functiondef(to_regprocedure('public.paigow_cleanup_rooms_bpaigow01()')))>0,'首局20分钟未开始自动关闭'
union all select 'casino_rng_still_compatible',position('gen_random_bytes' in lower(pg_get_functiondef(to_regprocedure('public.casino_secure_random_int_v1(integer)'))))=0,'原赌场安全随机兼容修复保持生效'
union all select 'mutation_system_retained',to_regprocedure('public.get_my_birth_result_v12()') is not null and exists(select 1 from public.battle_challenge_settings_bcombat01 where singleton_id=1 and mutation_final_damage_bonus=0.08),'V1.2变异灵根和剑心互斥体系保持不变';
