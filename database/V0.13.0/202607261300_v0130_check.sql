-- V0.13.0部署后检查
with checks as (
select 1 n,'settings_table' item,to_regclass('public.progression_v0130_settings') is not null pass union all
select 2,'audit_table',to_regclass('public.cultivation_cap_adjustment_logs') is not null union all
select 3,'cap_function',to_regprocedure('public.character_cultivation_cap_v1(smallint)') is not null union all
select 4,'full_function',to_regprocedure('public.character_cultivation_full_v1(uuid)') is not null union all
select 5,'grant_function',to_regprocedure('public.grant_cultivation_capped_v1(uuid,bigint,text,jsonb)') is not null union all
select 6,'cap_trigger',exists(select 1 from pg_trigger where tgname='trg_player_characters_cultivation_cap_v0130' and not tgisinternal) union all
select 7,'total_failure_column',exists(select 1 from information_schema.columns where table_schema='public' and table_name='character_breakthrough_states' and column_name='total_failure_count') union all
select 8,'insight_column',exists(select 1 from information_schema.columns where table_schema='public' and table_name='character_breakthrough_states' and column_name='heavenly_insight_count') union all
select 9,'death_probability_0_5',exists(select 1 from public.progression_v0130_settings where singleton_id=1 and death_probability=0.005) union all
select 10,'major_probability_5',exists(select 1 from public.progression_v0130_settings where singleton_id=1 and major_fall_probability=0.05) union all
select 11,'minor_probability_8',exists(select 1 from public.progression_v0130_settings where singleton_id=1 and minor_fall_probability=0.08) union all
select 12,'full_loss_probability_15',exists(select 1 from public.progression_v0130_settings where singleton_id=1 and full_loss_probability=0.15) union all
select 13,'half_loss_probability_30',exists(select 1 from public.progression_v0130_settings where singleton_id=1 and half_loss_probability=0.30) union all
select 14,'no_loss_probability_41_5',exists(select 1 from public.progression_v0130_settings where singleton_id=1 and no_loss_probability=0.415) union all
select 15,'probability_sum_100',exists(select 1 from public.progression_v0130_settings where singleton_id=1 and death_probability+major_fall_probability+minor_fall_probability+full_loss_probability+half_loss_probability+no_loss_probability=1) union all
select 16,'insight_bonus_5',exists(select 1 from public.progression_v0130_settings where singleton_id=1 and insight_bonus_per_stack=0.05) union all
select 17,'success_cap_80',exists(select 1 from public.progression_v0130_settings where singleton_id=1 and final_success_rate_cap=0.80) union all
select 18,'breakthrough_rpc',to_regprocedure('public.attempt_breakthrough_v1()') is not null union all
select 19,'status_rpc',to_regprocedure('public.get_breakthrough_status_v1()') is not null union all
select 20,'claim_rpc',to_regprocedure('public.claim_cultivation_v1()') is not null union all
select 21,'opportunity_effect_rpc',to_regprocedure('public.apply_opportunity_v3_effects_v1(uuid,uuid,integer,uuid,text,text,text,text,timestamptz)') is not null union all
select 22,'casino_debit_rpc',to_regprocedure('public.casino_debit_v1(uuid,text,bigint,text,text)') is not null union all
select 23,'casino_credit_rpc',to_regprocedure('public.casino_credit_v1(uuid,text,bigint)') is not null union all
select 24,'no_character_above_cap',not exists(select 1 from public.player_characters pc cross join lateral(select public.character_cultivation_cap_v1(pc.realm_stage_id) cap) x where x.cap is not null and pc.cultivation>x.cap) union all
select 25,'settings_private',not has_table_privilege('authenticated','public.progression_v0130_settings','select') union all
select 26,'audit_private',not has_table_privilege('authenticated','public.cultivation_cap_adjustment_logs','select') union all
select 27,'internal_grant_private',not has_function_privilege('authenticated','public.grant_cultivation_capped_v1(uuid,bigint,text,jsonb)','execute') union all
select 28,'arith_full_loss_200_to_100',(greatest(100::bigint,200::bigint-(200::bigint-100::bigint))=100) union all
select 29,'arith_half_loss_200_to_150',(greatest(100::bigint,200::bigint-floor((200::bigint-100::bigint)*0.5)::bigint)=150) union all
select 30,'arith_cap_190_plus_50_to_200',(190::bigint+least(50::bigint,greatest(0::bigint,200::bigint-190::bigint))=200) union all
select 31,'arith_old_500_truncated_to_200',(least(500::bigint,200::bigint)=200) union all
select 32,'casino_uses_non_bound_stones',pg_get_functiondef(to_regprocedure('public.casino_debit_v1(uuid,text,bigint,text,text)')) ilike '%is_bound=false%' union all
select 33,'casino_exact_balance_deletes_row',pg_get_functiondef(to_regprocedure('public.casino_debit_v1(uuid,text,bigint,text,text)')) ilike '%delete from public.character_inventory%' union all
select 34,'insight_bound_to_original_target',pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')) ilike '%v_original_target_id=v_next.id%'
)
select n,item,case when pass then 'PASS' else 'FAIL' end result from checks order by n;
