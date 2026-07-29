-- 九霄问道 V1.0 FIX4 部署后检查（只读）
select 'safe_house_rpc' check_name,
       to_regprocedure('public.play_house_game_v1_fix4(uuid,text,text,text,bigint,text)') is not null
       and has_function_privilege('authenticated','public.play_house_game_v1_fix4(uuid,text,text,text,bigint,text)','execute') ok,
       '安全大堂结算RPC存在且仅向登录玩家开放' detail
union all
select 'safe_fish_rpc',
       to_regprocedure('public.place_fish_shrimp_bet_v1_fix4(uuid,text,text,text,bigint)') is not null
       and has_function_privilege('authenticated','public.place_fish_shrimp_bet_v1_fix4(uuid,text,text,text,bigint)','execute'),
       '安全鱼虾灵局RPC存在'
union all
select 'old_house_rpc_closed',
       not has_function_privilege('authenticated','public.play_house_game_v0147(text,text,text,bigint,text)','execute')
       and not has_function_privilege('authenticated','public.play_house_game_v1(text,text,bigint,text)','execute'),
       '旧大堂结算入口已撤权'
union all
select 'old_fish_rpc_closed',
       not has_function_privilege('authenticated','public.place_fish_shrimp_bet_v0148(text,text,text,bigint)','execute'),
       '旧鱼虾下注入口已撤权'
union all
select 'request_idempotency_table',to_regclass('public.casino_bet_requests_v1') is not null,'幂等请求审计表存在'
union all
select 'ten_percent_rule',exists(select 1 from public.casino_settings where singleton_id=1 and house_stake_limit_bps=1000),'单局上限为当前可用资源10%'
union all
select 'player_house_no_cover',
       position('system_cover_amount' in pg_get_functiondef(to_regprocedure('public.casino_play_player_house_v1_fix4(uuid,text,text,bigint,text,uuid)')))>0
       and position('no_cover' in pg_get_functiondef(to_regprocedure('public.casino_play_player_house_v1_fix4(uuid,text,text,bigint,text,uuid)')))>0,
       '玩家庄新结算明确记录系统兜底为0'
union all
select 'player_house_pool_fee',
       position('casino_pools' in pg_get_functiondef(to_regprocedure('public.casino_play_player_house_v1_fix4(uuid,text,text,bigint,text,uuid)')))>0,
       '玩家庄5%坊税进入现有造化池'
union all
select 'release_cache34',exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1 and cache_epoch>=34 and release_name='V1.0 FIX4 CACHE34'),'发布门禁已提升至CACHE34';
