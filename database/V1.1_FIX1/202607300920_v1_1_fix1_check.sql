-- 九霄问道 V1.1 FIX1 CACHE36 升级后检查（只读）
select 'release_cache36' check_name,
  exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1 and cache_epoch>=36 and release_name='V1.1 FIX1 CACHE36') ok,
  '发布门禁已提升至CACHE36' detail
union all select 'period_settings',exists(select 1 from public.casino_settings where singleton_id=1 and casino_period_seconds=7200 and casino_close_before_seconds=60 and casino_profit_pool_bps=5000),'两小时一期、提前一分钟封盘、正利润50%入池'
union all select 'bankroll_targets',exists(select 1 from public.casino_bankroll_v1 where stake_type='spirit_stone' and target_amount=100000000) and exists(select 1 from public.casino_bankroll_v1 where stake_type='cultivation' and target_amount=1000000000),'灵石1亿、修为10亿固定期初资金'
union all select 'stake_limit_30',exists(select 1 from public.casino_settings where singleton_id=1 and house_stake_limit_bps=3000),'单局累计下注上限30%'
union all select 'player_house_2_5',exists(select 1 from public.casino_settings where singleton_id=1 and player_house_win_commission_bps=250),'玩家庄100:97.5，2.5%进入赌场资金'
union all select 'dice_triple_choice',public.casino_validate_choice_v1('spirit_dice','triple'),'灵骰可独立押任意豹子'
union all select 'dice_true_three',position('casino_secure_random_int_v1(6)' in pg_get_functiondef(to_regprocedure('public.casino_draw_house_result_fix1(text,text)')))>0,'灵骰由三颗独立安全随机骰组成'
union all select 'pool_70_percent',position('0.70' in pg_get_functiondef(to_regprocedure('public.casino_pool_draw_fix1(text,timestamp with time zone,boolean)')))>0,'中奖者领取70%，30%滚存'
union all select 'profit_only_draw',position('v_profit>0' in replace(pg_get_functiondef(to_regprocedure('public.casino_settle_bankroll_periods_v1()')),' ',''))>0,'赌场正利润才入池并开奖'
union all select 'no_system_cover',position('system_cover_amount=0' in replace(pg_get_functiondef(to_regprocedure('public.casino_fish_settle_round_v0148(uuid)')),' ',''))>0,'玩家庄鱼虾局无系统兜底'
union all select 'old_rpc_revoked',not has_function_privilege('authenticated','public.play_house_game_v1(text,text,bigint,text)','EXECUTE'),'旧大堂RPC仍保持撤权';

select stake_type,target_amount,balance,period_started_at,betting_closes_at,period_ends_at,
       last_period_profit,last_pool_allocation,last_reset_adjustment
from public.casino_bankroll_v1 order by stake_type;
