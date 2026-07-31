-- 九霄问道 V1.6 FIX1 CACHE45 升级后检查（只读）
select 'release_cache45' check_name,
       exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1 and cache_epoch>=45 and release_name='V1.6 FIX1 CACHE45') ok,
       '发布门禁已提升到CACHE45' detail
union all
select 'laohe_small_blind_before_settlement',
       position($needle$if v_phase='settled' then v_visible:=v_cards;else v_visible:='{}'::text[];end if$needle$ in pg_get_functiondef(to_regprocedure('public.get_paigow_room_state_bpaigow01(uuid)')))>0,
       '老何庄小牌九结算前不向玩家返回任何牌面'
union all
select 'laohe_big_blind_before_multiplier',
       position($needle$v_phase in('arrange','head_reveal','tail_reveal','settled')$needle$ in pg_get_functiondef(to_regprocedure('public.get_paigow_room_state_bpaigow01(uuid)')))>0,
       '老何庄大牌九选倍前不返回预发明牌，组牌阶段才返回本人四张牌'
union all
select 'laohe_dealer_cards_still_hidden',
       position($needle$v_laohe_visible:='{}'::text[]$needle$ in pg_get_functiondef(to_regprocedure('public.get_paigow_room_state_bpaigow01(uuid)')))>0
       and position($needle$elsif v_phase='head_reveal'$needle$ in pg_get_functiondef(to_regprocedure('public.get_paigow_room_state_bpaigow01(uuid)')))>0,
       '老何牌面在公开阶段前继续保持遮罩'
union all
select 'room_snapshot_still_pure_read',
       position('paigow_prepare_waiting_room_bpaigow01' in pg_get_functiondef(to_regprocedure('public.get_paigow_room_state_bpaigow01(uuid)')))=0
       and position('paigow_advance_room_internal' in pg_get_functiondef(to_regprocedure('public.get_paigow_room_state_bpaigow01(uuid)')))=0,
       '盲牌修复未恢复高频推进或写入副作用'
union all
select 'v16_realtime_retained',
       to_regprocedure('public.paigow_tick_due_rooms_bpaigow01()') is not null
       and to_regclass('public.paigow_room_event_versions_bpaigow01') is not null,
       'V1.6事件驱动与单一调度器保持不变';
