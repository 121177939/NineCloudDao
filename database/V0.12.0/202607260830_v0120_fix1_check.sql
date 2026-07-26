-- 《九霄问道》V0.12.0 FIX1 部署检查
-- 正常部署后应返回 27 项，且 result 全部为 PASS。
with checks(item,result,detail) as (
  values
  ('casino_settings',case when to_regclass('public.casino_settings') is not null then 'PASS' else 'FAIL' end,'赌场开关与时间配置'),
  ('casino_pools',case when to_regclass('public.casino_pools') is not null then 'PASS' else 'FAIL' end,'双造化彩池'),
  ('casino_duels',case when to_regclass('public.casino_duels') is not null then 'PASS' else 'FAIL' end,'异步玩家赌契'),
  ('casino_house_games',case when to_regclass('public.casino_house_games') is not null then 'PASS' else 'FAIL' end,'庄家局永久日志'),
  ('casino_daily_activity',case when to_regclass('public.casino_daily_activity') is not null then 'PASS' else 'FAIL' end,'每日场次与造化签上限'),
  ('casino_tickets',case when to_regclass('public.casino_tickets') is not null then 'PASS' else 'FAIL' end,'当前开奖轮次造化签'),
  ('casino_draws',case when to_regclass('public.casino_draws') is not null then 'PASS' else 'FAIL' end,'造化池开奖记录'),
  ('pool_rows',case when (select count(*) from public.casino_pools where stake_type in('spirit_stone','cultivation'))=2 then 'PASS' else 'FAIL' end,'灵石池与修为池各一行'),
  ('pool_next_draw',case when not exists(select 1 from public.casino_pools where next_draw_at is null) then 'PASS' else 'FAIL' end,'两池均有下次开奖时间'),
  ('get_market_v1',case when to_regprocedure('public.get_market_v1()') is not null then 'PASS' else 'FAIL' end,'市坊读取RPC'),
  ('play_house_game_v1',case when to_regprocedure('public.play_house_game_v1(text,text,bigint,text)') is not null then 'PASS' else 'FAIL' end,'庄家局RPC'),
  ('create_duel_v1',case when to_regprocedure('public.create_duel_v1(text,text,bigint,text)') is not null then 'PASS' else 'FAIL' end,'创建赌桌RPC'),
  ('join_duel_v1',case when to_regprocedure('public.join_duel_v1(uuid,text)') is not null then 'PASS' else 'FAIL' end,'应局RPC'),
  ('cancel_duel_v1',case when to_regprocedure('public.cancel_duel_v1(uuid)') is not null then 'PASS' else 'FAIL' end,'取消未应局赌桌RPC'),
  ('authenticated_endpoints',case when
      has_function_privilege('authenticated','public.get_market_v1()','EXECUTE') and
      has_function_privilege('authenticated','public.play_house_game_v1(text,text,bigint,text)','EXECUTE') and
      has_function_privilege('authenticated','public.create_duel_v1(text,text,bigint,text)','EXECUTE') and
      has_function_privilege('authenticated','public.join_duel_v1(uuid,text)','EXECUTE') and
      has_function_privilege('authenticated','public.cancel_duel_v1(uuid)','EXECUTE')
    then 'PASS' else 'FAIL' end,'authenticated仅可执行五个正式端点'),
  ('anon_denied',case when
      not has_function_privilege('anon','public.get_market_v1()','EXECUTE') and
      not has_function_privilege('anon','public.play_house_game_v1(text,text,bigint,text)','EXECUTE') and
      not has_function_privilege('anon','public.create_duel_v1(text,text,bigint,text)','EXECUTE') and
      not has_function_privilege('anon','public.join_duel_v1(uuid,text)','EXECUTE') and
      not has_function_privilege('anon','public.cancel_duel_v1(uuid)','EXECUTE')
    then 'PASS' else 'FAIL' end,'未登录用户不能调用赌场'),
  ('internal_helpers_private',case when
      not has_function_privilege('authenticated','public.casino_credit_v1(uuid,text,bigint)','EXECUTE') and
      not has_function_privilege('authenticated','public.casino_debit_v1(uuid,text,bigint,text,text)','EXECUTE') and
      not has_function_privilege('authenticated','public.casino_process_v1()','EXECUTE') and
      not has_function_privilege('authenticated','public.casino_draw_pools_v1()','EXECUTE') and
      not has_function_privilege('authenticated','public.casino_settle_duels_v1()','EXECUTE') and
      not has_function_privilege('authenticated','public.casino_realign_after_loss_v1(uuid)','EXECUTE') and
      not has_function_privilege('anon','public.casino_credit_v1(uuid,text,bigint)','EXECUTE')
    then 'PASS' else 'FAIL' end,'加资源、扣资源、开奖、结算和跌境函数均不可直接调用'),
  ('casino_tables_private',case when
      not has_table_privilege('authenticated','public.casino_pools','SELECT,INSERT,UPDATE,DELETE') and
      not has_table_privilege('authenticated','public.casino_duels','SELECT,INSERT,UPDATE,DELETE') and
      not has_table_privilege('anon','public.casino_pools','SELECT,INSERT,UPDATE,DELETE') and
      not has_table_privilege('anon','public.casino_duels','SELECT,INSERT,UPDATE,DELETE')
    then 'PASS' else 'FAIL' end,'客户端不能绕过RPC直接读写赌场表'),
  ('old_helpers_removed',case when
      to_regprocedure('public.casino_credit(uuid,text,bigint)') is null and
      to_regprocedure('public.casino_debit(uuid,text,bigint)') is null and
      to_regprocedure('public.casino_available(uuid,text)') is null and
      to_regprocedure('public.casino_result(text,text,text)') is null and
      to_regprocedure('public.settle_casino_duels_v1()') is null
    then 'PASS' else 'FAIL' end,'删除V0.12.0初稿危险辅助函数'),
  ('five_minute_reveal',case when (select reveal_delay_seconds from public.casino_settings where singleton_id=1)=300 then 'PASS' else 'FAIL' end,'第二名玩家应局后五分钟揭晓'),
  ('open_table_refund',case when (select open_expiry_seconds from public.casino_settings where singleton_id=1)=1800
      and pg_get_functiondef(to_regprocedure('public.casino_expire_open_duels_v1()')) like '%casino_credit_v1%'
    then 'PASS' else 'FAIL' end,'未应局赌桌30分钟自动原数返还'),
  ('five_percent_pool',case when pg_get_functiondef(to_regprocedure('public.casino_settle_duels_v1()')) like '%stake_amount*2*5%'
      and pg_get_functiondef(to_regprocedure('public.play_house_game_v1(text,text,bigint,text)')) like '%stake_amount*5%'
      and pg_get_functiondef(to_regprocedure('public.casino_settle_duels_v1()')) like '%casino_pools%'
      and pg_get_functiondef(to_regprocedure('public.play_house_game_v1(text,text,bigint,text)')) like '%casino_pools%'
    then 'PASS' else 'FAIL' end,'胜负局总赌注5%全部进入对应造化池'),
  ('draw_refund_no_fee',case when pg_get_functiondef(to_regprocedure('public.casino_settle_duels_v1()')) like '%fee_amount=0%'
      and pg_get_functiondef(to_regprocedure('public.casino_settle_duels_v1()')) like '%赌注原数奉还%'
    then 'PASS' else 'FAIL' end,'同招流局全额返还且不抽水'),
  ('cultivation_protection',case when pg_get_functiondef(to_regprocedure('public.casino_debit_v1(uuid,text,bigint,text,text)')) like '%0.20%'
      and pg_get_functiondef(to_regprocedure('public.casino_debit_v1(uuid,text,bigint,text,text)')) like '%50000%'
      and pg_get_functiondef(to_regprocedure('public.casino_realign_after_loss_v1(uuid)')) like '%major_order%'
      and pg_get_functiondef(to_regprocedure('public.casino_realign_after_loss_v1(uuid)')) like '%realm_base_cultivation_rate_v1%'
    then 'PASS' else 'FAIL' end,'元婴开放、最低5万、最高20%，输钱只回退同一大境界小境界'),
  ('daily_limits',case when pg_get_functiondef(to_regprocedure('public.casino_assert_activity_allowed_v1(uuid,text,text)')) like '%total_count>=30%'
      and pg_get_functiondef(to_regprocedure('public.casino_assert_activity_allowed_v1(uuid,text,text)')) like '%duel_count>=15%'
      and pg_get_functiondef(to_regprocedure('public.casino_assert_activity_allowed_v1(uuid,text,text)')) like '%cultivation_count>=10%'
      and pg_get_functiondef(to_regprocedure('public.casino_assert_activity_allowed_v1(uuid,text,text)')) like '%30 seconds%'
    then 'PASS' else 'FAIL' end,'总落注30次、雅间15次、修为10次及贪念冷却'),
  ('fortune_draws',case when (select draw_interval_seconds from public.casino_settings where singleton_id=1)=7200
      and to_regprocedure('public.casino_draw_pools_v1()') is not null
      and to_regprocedure('public.casino_add_ticket_v1(uuid,text)') is not null
    then 'PASS' else 'FAIL' end,'双造化池每两小时懒触发开奖并使用造化签'),
  ('rls_enabled',case when not exists(
      select 1 from pg_class c join pg_namespace n on n.oid=c.relnamespace
      where n.nspname='public' and c.relname in('casino_settings','casino_pools','casino_duels','casino_house_games','casino_daily_activity','casino_tickets','casino_draws') and not c.relrowsecurity
    ) then 'PASS' else 'FAIL' end,'赌场表全部启用RLS')
)
select * from checks order by item;
