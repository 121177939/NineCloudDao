-- V0.11.7 FIX1 恢复天道动态均衡系数。
begin;
create or replace function public.heaven_balance_multiplier_v1(p_realm_gap integer)
returns numeric
language sql
immutable
strict
set search_path = public, pg_temp
as $$
  select case
    when p_realm_gap <= -5 then 5.0::numeric
    when p_realm_gap = -4 then 4.0::numeric
    when p_realm_gap = -3 then 3.0::numeric
    when p_realm_gap = -2 then 2.0::numeric
    when p_realm_gap = -1 then 1.2::numeric
    when p_realm_gap = 0 then 1.0::numeric
    when p_realm_gap = 1 then 0.8::numeric
    when p_realm_gap = 2 then 0.6::numeric
    else 0.5::numeric
  end;
$$;
commit;
notify pgrst, 'reload schema';
select gap, public.heaven_balance_multiplier_v1(gap) as coefficient
from generate_series(-5, 3) as gap
order by gap;
