-- 九霄问道 V1.6 CACHE44 升级后检查（只读）
select 'release_cache44' check_name,
       exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1 and cache_epoch>=44 and release_name='V1.6 CACHE44') ok,
       '发布门禁已提升到CACHE44' detail
union all
select 'event_version_table',to_regclass('public.paigow_room_event_versions_bpaigow01') is not null,'每房间状态版本表存在'
union all
select 'database_private_broadcast',
       to_regprocedure('public.paigow_emit_state_event_payload_v16_bpaigow01(uuid,text,jsonb,boolean)') is not null
       and position('realtime.send' in pg_get_functiondef(to_regprocedure('public.paigow_emit_state_event_payload_v16_bpaigow01(uuid,text,jsonb,boolean)')))>0
       and position('snapshot_required' in pg_get_functiondef(to_regprocedure('public.paigow_emit_state_event_payload_v16_bpaigow01(uuid,text,jsonb,boolean)')))>0,
       '数据库提交后发送私有Broadcast及安全增量'
union all
select 'broadcast_payload_has_no_cards',
       position('shuffled_deck' in pg_get_functiondef(to_regprocedure('public.paigow_emit_state_event_payload_v16_bpaigow01(uuid,text,jsonb,boolean)')))=0
       and position('laohe_cards' in pg_get_functiondef(to_regprocedure('public.paigow_emit_state_event_payload_v16_bpaigow01(uuid,text,jsonb,boolean)')))=0,
       '公共事件函数不读取或发送牌堆与私牌'
union all
select 'pure_lobby_snapshot',
       position('paigow_prepare_waiting_room_bpaigow01' in pg_get_functiondef(to_regprocedure('public.get_paigow_lobby_bpaigow01()')))=0
       and position('paigow_cleanup_rooms_bpaigow01' in pg_get_functiondef(to_regprocedure('public.get_paigow_lobby_bpaigow01()')))=0,
       '大厅快照严格只读'
union all
select 'pure_room_snapshot',
       position('paigow_prepare_waiting_room_bpaigow01' in pg_get_functiondef(to_regprocedure('public.get_paigow_room_state_bpaigow01(uuid)')))=0
       and position('paigow_advance_room_internal' in pg_get_functiondef(to_regprocedure('public.get_paigow_room_state_bpaigow01(uuid)')))=0,
       '房间快照严格只读且保留用户私牌隔离'
union all
select 'single_global_tick',
       to_regprocedure('public.paigow_tick_due_rooms_bpaigow01()') is not null
       and exists(select 1 from cron.job where jobname='jiuxiao-paigow-v16-tick' and active and schedule='1 second'),
       '单一秒级Cron统一推进所有到期房间'
union all
select 'tick_concurrency_guard',
       position('pg_try_advisory_xact_lock' in pg_get_functiondef(to_regprocedure('public.paigow_tick_due_rooms_bpaigow01()')))>0,
       '调度器使用事务级咨询锁避免重复推进'
union all
select 'realtime_receive_policy',
       exists(select 1 from pg_policies where schemaname='realtime' and tablename='messages' and policyname='paigow_v16_authenticated_receive'),
       '牌九私有Broadcast接收RLS存在'
union all
select 'no_client_broadcast_write_policy',
       not exists(select 1 from pg_policies where schemaname='realtime' and tablename='messages' and policyname='paigow_v16_authenticated_send'),
       '客户端不能直接广播权威游戏动作'
union all
select 'v15_money_rules_retained',
       position('v_profit_pay_total:=least(v_profit_pool,v_winner_claim)' in pg_get_functiondef(to_regprocedure('public.paigow_settle_round_internal_bpaigow01(uuid)')))>0
       and position('paigow_big_tie_fee_refund_v15' in pg_get_functiondef(to_regprocedure('public.paigow_settle_round_internal_bpaigow01(uuid)')))>0,
       '玩家庄比例赔付与大牌九平局退费保持不变'
union all
select 'private_small_card_retained',
       position('v_visible:=''{}''::text[]' in pg_get_functiondef(to_regprocedure('public.get_paigow_room_state_bpaigow01(uuid)')))>0,
       '小牌九首张明牌仍仅牌主可见'
union all
select 'cultivation_paigow_disabled',
       exists(select 1 from public.paigow_settings_bpaigow01 where singleton_id=1 and cultivation_stakes_enabled=false),
       '修为牌九仍暂时关闭';
