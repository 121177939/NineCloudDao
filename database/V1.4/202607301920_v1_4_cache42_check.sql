-- 九霄问道 V1.4 CACHE42 升级后检查（只读）
select 'release_cache42' check_name,
       exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1 and cache_epoch>=42 and release_name='V1.4 CACHE42') ok,
       '发布门禁已提升到CACHE42' detail
union all
select 'ready_deadline_column',
       exists(select 1 from information_schema.columns where table_schema='public' and table_name='paigow_room_members_bpaigow01' and column_name='ready_deadline'),
       '玩家准备期限字段存在'
union all
select 'auto_start_column',
       exists(select 1 from information_schema.columns where table_schema='public' and table_name='paigow_rooms_bpaigow01' and column_name='auto_start_at'),
       '全员准备自动开局时间字段存在'
union all
select 'timing_settings',
       exists(select 1 from public.paigow_settings_bpaigow01 where singleton_id=1 and ready_seconds=10 and auto_start_seconds=2 and small_multiplier_seconds=5),
       '10秒准备、2秒自动开局、小牌九5秒选倍均已生效'
union all
select 'private_small_open_card',
       position('v_visible:=''{}''::text[]' in pg_get_functiondef(to_regprocedure('public.get_paigow_room_state_bpaigow01(uuid)')))>0
       and position('v_cards[1:1]' in pg_get_functiondef(to_regprocedure('public.get_paigow_room_state_bpaigow01(uuid)')))>0,
       '小牌九仅本人取得首张可见牌，对手取得空可见牌数组'
union all
select 'prepare_tick_rpc',
       to_regprocedure('public.paigow_prepare_waiting_room_bpaigow01(uuid)') is not null,
       '准备超时退出与自动开局服务端推进函数存在'
union all
select 'delete_room_rpc',
       to_regprocedure('public.delete_paigow_room_bpaigow01(uuid)') is not null
       and has_function_privilege('authenticated','public.delete_paigow_room_bpaigow01(uuid)','execute'),
       '房主大厅删除等待房间接口存在'
union all
select 'active_room_delete_guard',
       position('PAIGOW_CANNOT_DELETE_ACTIVE_ROOM' in pg_get_functiondef(to_regprocedure('public.delete_paigow_room_bpaigow01(uuid)')))>0,
       '进行中的房间禁止删除'
union all
select 'secure_shuffle_retained',
       position('casino_secure_random_int_v1' in pg_get_functiondef(to_regprocedure('public.paigow_shuffle_deck_bpaigow01()')))>0,
       '服务端安全洗牌保持不变'
union all
select 'physical_tiles_32',(select count(*)=32 from public.paigow_tile_defs_bpaigow01),'传统32张实体骨牌保持完整'
union all
select 'player_fee_250bps',exists(select 1 from public.paigow_settings_bpaigow01 where singleton_id=1 and player_fee_bps=250),'玩家局2.5%手续费保持不变';
