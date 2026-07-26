-- V0.13.0只读预检查
with checks as (
select 1 n,'player_characters_exists' item,(to_regclass('public.player_characters') is not null) pass union all
select 2,'realm_stages_exists',(to_regclass('public.realm_stages') is not null) union all
select 3,'breakthrough_state_exists',(to_regclass('public.character_breakthrough_states') is not null) union all
select 4,'claim_cultivation_exists',(to_regprocedure('public.claim_cultivation_v1()') is not null) union all
select 5,'attempt_breakthrough_exists',(to_regprocedure('public.attempt_breakthrough_v1()') is not null) union all
select 6,'v0120_casino_exists',(to_regclass('public.casino_settings') is not null) union all
select 7,'casino_debit_exists',(to_regprocedure('public.casino_debit_v1(uuid,text,bigint,text,text)') is not null)
)
select n,item,case when pass then 'PASS' else 'FAIL' end result from checks order by n;
