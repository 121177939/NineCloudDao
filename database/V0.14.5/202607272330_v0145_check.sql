-- 合并模块迁移后检查
select case when count(*)=120 then 'PASS' else 'FAIL' end result,'story_pool_count' check_name,count(*) actual from public.opportunity_v4_story_pool where is_active;
select case when count(*)=120 then 'PASS' else 'FAIL' end result,'result_pool_count' check_name,count(*) actual from public.opportunity_v4_result_pool where is_active;
select case when count(*)=24 then 'PASS' else 'FAIL' end result,'ordinary_technique_pool_count' check_name,count(*) actual from public.opportunity_v4_technique_pool where is_active;
select case when count(*)=12 then 'PASS' else 'FAIL' end result,'new_support_technique_count' check_name,count(*) actual from public.techniques where code like 'opp_support_%' and category='support' and is_active;
select case when count(*)=4 then 'PASS' else 'FAIL' end result,'technique_drop_rate_count' check_name,count(*) actual from public.opportunity_v4_technique_drop_rates;
select case when online_interval_seconds=300 and offline_interval_seconds=300 and offline_catchup_limit=864 then 'PASS' else 'FAIL' end result,'five_minute_settings' check_name from public.opportunity_v3_settings where world_code='jiuxiao_world_1';
select case when player_house_win_commission_bps=500 then 'PASS' else 'FAIL' end result,'player_house_commission_5_percent' check_name from public.casino_settings where singleton_id=1;
select case when to_regprocedure('public.settle_opportunity_v4(boolean)') is not null then 'PASS' else 'FAIL' end result,'settle_function' check_name;
select case when to_regprocedure('public.opportunity_v4_award_ordinary_technique(uuid,uuid,integer,text,timestamptz)') is not null then 'PASS' else 'FAIL' end result,'technique_award_function' check_name;
