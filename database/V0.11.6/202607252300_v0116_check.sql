-- V0.11.6 升级后只读检查
with checks as (
  select 'probability_base_50_50' as check_name,
         public.opportunity_v3_auspicious_probability_v1(50,50,false)=50 as passed,
         public.opportunity_v3_auspicious_probability_v1(50,50,false)::text as detail
  union all
  select 'lucky_encounter_plus_5',
         public.opportunity_v3_auspicious_probability_v1(50,50,true)=55,
         public.opportunity_v3_auspicious_probability_v1(50,50,true)::text
  union all
  select 'probability_low_example',
         public.opportunity_v3_auspicious_probability_v1(40,40,false)=40,
         public.opportunity_v3_auspicious_probability_v1(40,40,false)::text
  union all
  select 'probability_cap_90',
         public.opportunity_v3_auspicious_probability_v1(100,100,true)=90,
         public.opportunity_v3_auspicious_probability_v1(100,100,true)::text
  union all
  select 'negative_text_duration',
         public.opportunity_v3_negative_duration_hours_v1('24 小时内修炼速度 - 5%')=24,
         public.opportunity_v3_negative_duration_hours_v1('24 小时内修炼速度 - 5%')::text
  union all
  select 'polarity_constraint_exists',
         exists(select 1 from pg_constraint where conname='opportunity_v3_results_v0116_polarity_check'),
         coalesce((select convalidated::text from pg_constraint where conname='opportunity_v3_results_v0116_polarity_check'),'missing')
  union all
  select 'new_results_are_mutually_exclusive',
         not exists(
           select 1 from public.opportunity_v3_results
            where result_data ? 'auspicious_probability'
              and not (
                (path_key='auspicious' and length(btrim(coalesce(reward_text,'')))>0 and length(btrim(coalesce(penalty_text,'')))=0)
                or
                (path_key='risk' and length(btrim(coalesce(reward_text,'')))=0 and length(btrim(coalesce(penalty_text,'')))>0)
              )
         ),
         (select count(*)::text from public.opportunity_v3_results where result_data ? 'auspicious_probability')
  union all
  select 'function_count_expected_at_least_73',
         (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public')>=73,
         (select count(*)::text from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public')
)
select check_name, case when passed then 'PASS' else 'FAIL' end as status, detail
from checks
order by check_name;

select code, name, fate_code, base_cultivation_multiplier, max_level
from public.exclusive_technique_definitions
order by code;
