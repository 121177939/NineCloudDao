-- B01-R1 部署前检查；只读。
select * from (
  values
    ('baseline_fates', (select count(*)=5 from public.fates where code in('late_bloomer','lucky_encounter','unyielding_heart','sword_heart','heaven_jealous')), '五种目标命格均存在'),
    ('claim_function', to_regprocedure('public.claim_cultivation_v1()') is not null, '修炼结算函数存在'),
    ('breakthrough_status_function', to_regprocedure('public.get_breakthrough_status_v1()') is not null, '突破状态函数存在'),
    ('breakthrough_attempt_function', to_regprocedure('public.attempt_breakthrough_v1()') is not null, '突破结算函数存在'),
    ('opportunity_function', to_regprocedure('public.settle_opportunity_v4(boolean)') is not null, '机缘V4结算函数存在'),
    ('casino_draw_function', to_regprocedure('public.casino_draw_pools_v1()') is not null, '赌坊奖池开奖函数存在'),
    ('breakthrough_state_table', to_regclass('public.character_breakthrough_states') is not null, '突破状态表存在'),
    ('casino_tables', to_regclass('public.casino_pools') is not null and to_regclass('public.casino_tickets') is not null and to_regclass('public.casino_draws') is not null, '赌坊奖池表存在')
) as x(check_name,ok,detail)
order by check_name;
