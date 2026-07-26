-- V0.11.7 天道动态均衡检查：status应全部为PASS。
with checks as (
  select 'blessing_gap_minus_5'::text as check_name,
         public.heaven_balance_multiplier_v1(-5) = 5.0 as passed,
         public.heaven_balance_multiplier_v1(-5)::text as detail
  union all
  select 'blessing_gap_minus_4', public.heaven_balance_multiplier_v1(-4) = 4.0, public.heaven_balance_multiplier_v1(-4)::text
  union all
  select 'blessing_gap_minus_3', public.heaven_balance_multiplier_v1(-3) = 3.0, public.heaven_balance_multiplier_v1(-3)::text
  union all
  select 'blessing_gap_minus_2', public.heaven_balance_multiplier_v1(-2) = 2.0, public.heaven_balance_multiplier_v1(-2)::text
  union all
  select 'blessing_gap_minus_1', public.heaven_balance_multiplier_v1(-1) = 1.2, public.heaven_balance_multiplier_v1(-1)::text
  union all
  select 'balance_gap_zero', public.heaven_balance_multiplier_v1(0) = 1.0, public.heaven_balance_multiplier_v1(0)::text
  union all
  select 'obstruction_gap_plus_1', public.heaven_balance_multiplier_v1(1) = 0.8, public.heaven_balance_multiplier_v1(1)::text
  union all
  select 'obstruction_gap_plus_2', public.heaven_balance_multiplier_v1(2) = 0.6, public.heaven_balance_multiplier_v1(2)::text
  union all
  select 'obstruction_gap_plus_3', public.heaven_balance_multiplier_v1(3) = 0.5, public.heaven_balance_multiplier_v1(3)::text
  union all
  select 'balance_rpc_exists',
         to_regprocedure('public.get_heaven_balance_v1()') is not null,
         coalesce(to_regprocedure('public.get_heaven_balance_v1()')::text, 'missing')
  union all
  select 'claim_uses_additive_qi',
         position('v_segment_fixed_rate + v_qi_environment_gain' in pg_get_functiondef('public.claim_cultivation_v1()'::regprocedure)) > 0,
         case when position('v_segment_fixed_rate + v_qi_environment_gain' in pg_get_functiondef('public.claim_cultivation_v1()'::regprocedure)) > 0 then 'additive' else 'missing' end
  union all
  select 'claim_records_mainstream_order',
         position('mainstream_realm_order' in pg_get_functiondef('public.claim_cultivation_v1()'::regprocedure)) > 0,
         case when position('mainstream_realm_order' in pg_get_functiondef('public.claim_cultivation_v1()'::regprocedure)) > 0 then 'present' else 'missing' end
  union all
  select 'public_table_count_75',
         (select count(*) from information_schema.tables where table_schema='public' and table_type='BASE TABLE') = 75,
         (select count(*)::text from information_schema.tables where table_schema='public' and table_type='BASE TABLE')
  union all
  select 'function_count_expected_at_least_75',
         (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public') >= 75,
         (select count(*)::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public')
)
select check_name,
       case when passed then 'PASS' else 'FAIL' end as status,
       detail
from checks
order by check_name;
