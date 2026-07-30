-- 九霄问道 V1.1 部署后检查（只读）
select 'challenge_rules' check_name,
  exists(select 1 from public.battle_challenge_settings_bcombat01 where singleton_id=1 and active_challenge_daily_limit=20 and challenge_cooldown_minutes=20 and protection_minutes=0 and higher_power_win_rate=0.005 and lower_power_win_rate=0.01) ok,
  '每日20次、全局冷却20分钟、0.5%/1%规则已生效' detail
union all select 'ranking_bidirectional',position('''can_challenge'',id<>v_self_id' in pg_get_functiondef(to_regprocedure('public.get_battle_power_ranking_bcombat01(integer,integer)')))>0,'除自己外均可挑战'
union all select 'no_higher_only_guard',position('TARGET_POWER_NOT_HIGHER' in pg_get_functiondef(to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)')))=0,'已移除只能挑战高战力限制'
union all select 'stage_progress_only',position('v_loser_stage_progress' in pg_get_functiondef(to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)')))>0,'只按败者当前小境界进度计算'
union all select 'no_stage_drop',position('greatest(v_loser_stage_floor' in pg_get_functiondef(to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)')))>0,'败者不会跌破当前小境界起点'
union all select 'equal_transfer',position('v_escrow:=v_transfer-v_granted' in pg_get_functiondef(to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)')))>0,'当前修为与战利暂存合计严格等于败者扣除量'
union all select 'world_event_correct_table',position('public.jiuxiao_world_events' in pg_get_functiondef(to_regprocedure('public.bcombat01_refresh_world_event_v11()')))>0,'挑战趣味文案写入前端实际读取的界闻表'
union all select 'world_event_trigger',exists(select 1 from pg_trigger where tgrelid=to_regclass('public.battle_challenges_bcombat01') and tgname='trg_bcombat01_refresh_world_event_v11' and not tgisinternal),'V1.1界闻触发器已启用'
union all select 'release_cache35',exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1 and cache_epoch>=35 and release_name='V1.1 CACHE35'),'发布门禁已提升至CACHE35';
