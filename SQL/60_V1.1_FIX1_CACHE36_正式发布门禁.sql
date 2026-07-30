-- 九霄问道 V1.1 FIX1 CACHE36 正式发布门禁
begin;
do $$
begin
  if to_regclass('public.casino_bankroll_v1') is null then raise exception 'V1_1_FIX1_REQUIRED:casino_bankroll_v1'; end if;
  if to_regclass('public.casino_bankroll_periods_v1') is null then raise exception 'V1_1_FIX1_REQUIRED:casino_bankroll_periods_v1'; end if;
  if to_regclass('public.casino_bankroll_ledger_v1') is null then raise exception 'V1_1_FIX1_REQUIRED:casino_bankroll_ledger_v1'; end if;
  if to_regprocedure('public.casino_settle_bankroll_periods_v1()') is null then raise exception 'V1_1_FIX1_REQUIRED:period_settlement'; end if;
  if to_regprocedure('public.casino_secure_random_int_v1(integer)') is null then raise exception 'V1_1_FIX1_REQUIRED:secure_rng'; end if;
  if to_regprocedure('public.play_house_game_v1_fix4(uuid,text,text,text,bigint,text)') is null then raise exception 'V1_1_FIX1_REQUIRED:house_rpc'; end if;
  if to_regprocedure('public.place_fish_shrimp_bet_v1_fix4(uuid,text,text,text,bigint)') is null then raise exception 'V1_1_FIX1_REQUIRED:fish_rpc'; end if;
  if not exists(
    select 1 from public.casino_settings where singleton_id=1
      and house_stake_limit_bps=3000
      and casino_period_seconds=7200
      and casino_close_before_seconds=60
      and casino_profit_pool_bps=5000
      and casino_spirit_stone_target=100000000
      and casino_cultivation_target=1000000000
      and player_house_win_commission_bps=250
  ) then raise exception 'V1_1_FIX1_REQUIRED:settings'; end if;
  if not exists(select 1 from public.casino_bankroll_v1 where stake_type='spirit_stone' and target_amount=100000000) then raise exception 'V1_1_FIX1_REQUIRED:stone_bankroll'; end if;
  if not exists(select 1 from public.casino_bankroll_v1 where stake_type='cultivation' and target_amount=1000000000) then raise exception 'V1_1_FIX1_REQUIRED:cultivation_bankroll'; end if;
  if not public.casino_validate_choice_v1('spirit_dice','triple') then raise exception 'V1_1_FIX1_REQUIRED:triple_choice'; end if;
end;
$$;

update public.jiuxiao_app_release_control
set release_name='V1.1 FIX1 CACHE36',cache_epoch=greatest(cache_epoch,36),
    notice_text='V1.1 FIX1：赌场采用公平三骰与公开赔率；系统庄每两小时独立重置1亿灵石/10亿修为，封盘前1分钟停止新注，正利润50%入造化池并按70%派奖、30%滚存；每局下注上限30%；玩家庄100:97.5且系统绝不兜底。',updated_at=now()
where singleton_id=1;
insert into public.jiuxiao_app_release_control(singleton_id,release_name,cache_epoch,notice_text,updated_at)
select 1,'V1.1 FIX1 CACHE36',36,'V1.1 FIX1：赌场周期资金、公平概率、30%单局上限与玩家庄2.5%平台费。',now()
where not exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1);
notify pgrst,'reload schema';
commit;
