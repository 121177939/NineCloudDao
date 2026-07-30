-- 九霄问道 V1.1 FIX1 CACHE36：赌场升级前检查（只读）
-- 前置：V1.1 CACHE35 + V1.0 FIX4 赌场幂等结算。
-- 执行本文件前应先暂停前端发布；鱼虾灵局未结算注单必须先自然结算完毕。

do $$
begin
  if to_regclass('public.casino_settings') is null then raise exception 'V1_1_FIX1_REQUIRED:casino_settings'; end if;
  if to_regclass('public.casino_pools') is null then raise exception 'V1_1_FIX1_REQUIRED:casino_pools'; end if;
  if to_regclass('public.casino_tickets') is null then raise exception 'V1_1_FIX1_REQUIRED:casino_tickets'; end if;
  if to_regclass('public.casino_draws') is null then raise exception 'V1_1_FIX1_REQUIRED:casino_draws'; end if;
  if to_regclass('public.casino_house_games') is null then raise exception 'V1_1_FIX1_REQUIRED:casino_house_games'; end if;
  if to_regclass('public.casino_bet_requests_v1') is null then raise exception 'V1_1_FIX1_REQUIRED:casino_bet_requests_v1'; end if;
  if to_regclass('public.casino_fish_rounds_v0148') is null then raise exception 'V1_1_FIX1_REQUIRED:casino_fish_rounds_v0148'; end if;
  if to_regclass('public.casino_fish_bets_v0148') is null then raise exception 'V1_1_FIX1_REQUIRED:casino_fish_bets_v0148'; end if;
  if to_regclass('public.casino_player_house_state') is null then raise exception 'V1_1_FIX1_REQUIRED:casino_player_house_state'; end if;
  if to_regprocedure('public.play_house_game_v1_fix4(uuid,text,text,text,bigint,text)') is null then raise exception 'V1_1_FIX1_REQUIRED:house_fix4_rpc'; end if;
  if to_regprocedure('public.place_fish_shrimp_bet_v1_fix4(uuid,text,text,text,bigint)') is null then raise exception 'V1_1_FIX1_REQUIRED:fish_fix4_rpc'; end if;
  if to_regprocedure('public.casino_credit_result_v0141(uuid,text,bigint)') is null then raise exception 'V1_1_FIX1_REQUIRED:credit_result'; end if;
  if to_regprocedure('public.casino_debit_v1(uuid,text,bigint,text,text)') is null then raise exception 'V1_1_FIX1_REQUIRED:casino_debit'; end if;
  if to_regprocedure('public.casino_player_house_resolve_dealer_v1()') is null then raise exception 'V1_1_FIX1_REQUIRED:player_house_resolver'; end if;
  if coalesce((select cache_epoch>=35 from public.jiuxiao_app_release_control where singleton_id=1),false) is not true then
    raise exception 'V1_1_FIX1_REQUIRED:CACHE35';
  end if;
  if exists(select 1 from public.casino_bet_requests_v1 where status='pending') then
    raise exception 'V1_1_FIX1_PENDING_REQUESTS:请等待或人工核对pending请求后再升级';
  end if;
  if exists(select 1 from public.casino_fish_bets_v0148 where not is_settled) then
    raise exception 'V1_1_FIX1_PENDING_FISH_BETS:请等待当前40秒鱼虾局自然结算后重试';
  end if;
end;
$$;

select 'current_release' check_name,
       coalesce((select release_name from public.jiuxiao_app_release_control where singleton_id=1),'missing') detail
union all
select 'pool_spirit_stone_preserved',coalesce((select amount::text from public.casino_pools where stake_type='spirit_stone'),'missing')
union all
select 'pool_cultivation_preserved',coalesce((select amount::text from public.casino_pools where stake_type='cultivation'),'missing')
union all
select 'pending_requests',(select count(*)::text from public.casino_bet_requests_v1 where status='pending')
union all
select 'pending_fish_bets',(select count(*)::text from public.casino_fish_bets_v0148 where not is_settled);
