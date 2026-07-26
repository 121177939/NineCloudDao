-- V0.11.7 FIX1 紧急停用：暂时令所有修士处于大道均衡×1，不删除任何数据。
begin;
create or replace function public.heaven_balance_multiplier_v1(p_realm_gap integer)
returns numeric
language sql
immutable
strict
set search_path = public, pg_temp
as $$ select 1.0::numeric; $$;
commit;
notify pgrst, 'reload schema';
select public.heaven_balance_multiplier_v1(-5) as disabled_coefficient;
