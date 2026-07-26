-- V0.11.10 FIX2 read-only check
with f as (
  select pg_get_functiondef('public.claim_cultivation_v1()'::regprocedure) as def
)
select
  'claim_cultivation_alias_qualified' as check_name,
  case
    when def like '%update public.character_cultivation_state as ccs%'
     and def like '%where ccs.character_id = v_character_id%'
     and def like '%ccs.total_cultivation_seconds + v_elapsed%'
    then 'PASS'
    else 'FAIL'
  end as result
from f
union all
select
  'claim_cultivation_function_exists',
  case when to_regprocedure('public.claim_cultivation_v1()') is not null then 'PASS' else 'FAIL' end;
