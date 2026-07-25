-- V0.11.2只读检查
select 'catalog_total' item,count(*) value,(count(*)=300) pass from public.opportunity_v3_catalog union all
select 'yellow',count(*),(count(*)=150) from public.opportunity_v3_catalog where grade='黄品' union all
select 'mystic',count(*),(count(*)=72) from public.opportunity_v3_catalog where grade='玄品' union all
select 'earth',count(*),(count(*)=45) from public.opportunity_v3_catalog where grade='地品' union all
select 'heaven',count(*),(count(*)=24) from public.opportunity_v3_catalog where grade='天品' union all
select 'immortal',count(*),(count(*)=9) from public.opportunity_v3_catalog where grade='仙品' union all
select 'exclusive',count(*),(count(*)=5) from public.exclusive_technique_definitions union all
select 'xuan23_fixed',count(*),(count(*)=1) from public.opportunity_v3_catalog where code='mystic_023' and positive_text like '%清泉纳灵诀%' union all
select 'old_v2_absent',count(*),(count(*)=0) from pg_proc where proname like '%auto_opportunity_v2%';
select world_code,enabled,online_interval_seconds,offline_interval_seconds,offline_catchup_limit,weights from public.opportunity_v3_settings;
select code,name,fate_name,base_cultivation_multiplier,max_level,upgrade_cost_base from public.exclusive_technique_definitions order by code;
