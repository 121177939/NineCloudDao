-- V0.11.5 FINAL 只读检查 SQL

-- A. 总体基线与核心对象。
select
  (select count(*) from information_schema.tables where table_schema='public' and table_type='BASE TABLE') as public_table_count,
  (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public') as public_function_count,
  (select enabled from public.opportunity_v3_settings where world_code='jiuxiao_world_1') as opportunity_enabled,
  (select count(*) from public.opportunity_v3_catalog where is_active) as active_opportunity_count,
  (select count(*) from public.exclusive_technique_definitions) as exclusive_definition_count;

-- B. 300条五品机缘分布，应为 黄150、玄72、地45、天24、仙9。
select grade, count(*) as item_count
from public.opportunity_v3_catalog
where is_active
group by grade
order by case grade when '黄品' then 1 when '玄品' then 2 when '地品' then 3 when '天品' then 4 when '仙品' then 5 end;

-- C. 权重、在线/离线间隔与补领上限。
select online_interval_seconds, offline_interval_seconds, offline_catchup_limit, first_interval_seconds, weights
from public.opportunity_v3_settings
where world_code='jiuxiao_world_1';

-- D. 正式功法定义与玄品23修复。
select code, name, grade, fixed_effects
from public.techniques
where code like 'opp\_%' escape '\'
order by code;

select code, grade, grade_sequence, title, positive_text
from public.opportunity_v3_catalog
where code='mystic_023';

-- E. 五本专属功法。
select code, name, fate_code, fate_name, cave_resource_code, base_cultivation_multiplier, max_level, upgrade_cost_base
from public.exclusive_technique_definitions
order by code;

-- F. V0.11.5 应存在的函数。
select proname, pg_get_function_identity_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public'
  and proname in (
    'v0115_linear_effect_v1',
    'exclusive_technique_effect_bonus_v1',
    'refresh_opportunity_technique_effects_v1',
    'trg_refresh_opportunity_technique_effects_v1',
    'refresh_exclusive_technique_effects_v1',
    'award_opportunity_technique_v3',
    'award_cave_resource_v3',
    'apply_opportunity_v3_effects_v1',
    'get_exclusive_technique_system_v1',
    'set_exclusive_technique_slot_v1',
    'upgrade_exclusive_technique_v1',
    'get_auto_opportunity_v3'
  )
order by proname;

-- G. 普通机缘功法同步触发器。
select tgname, tgenabled
from pg_trigger
where tgrelid='public.character_techniques'::regclass
  and not tgisinternal
  and tgname='trg_refresh_opportunity_technique_effects_v1';

-- H. 主函数源码契约检查。
select
  position('cfg.enabled' in pg_get_functiondef('public.get_auto_opportunity_v3()'::regprocedure))>0 as emergency_switch_effective,
  position('offline_interval_seconds' in pg_get_functiondef('public.get_auto_opportunity_v3()'::regprocedure))>0 as offline_20min_logic_present,
  position('apply_opportunity_v3_effects_v1' in pg_get_functiondef('public.get_auto_opportunity_v3()'::regprocedure))>0 as effect_application_present,
  position('refresh_exclusive_technique_effects_v1' in pg_get_functiondef('public.get_auto_opportunity_v3()'::regprocedure))>0 as exclusive_effect_present,
  position('realm_stage' in pg_get_functiondef('public.get_auto_opportunity_v3()'::regprocedure))=0 as no_realm_gate;

-- I. 不再残留当前系统无法承载的三类奖励文案。
select
  count(*) filter(where positive_text like '%直接突破%') as direct_breakthrough_remaining,
  count(*) filter(where positive_text like '%所有已习得功法效果翻倍%') as all_techniques_double_remaining,
  count(*) filter(where positive_text like '%满境界修为%') as full_realm_cultivation_remaining
from public.opportunity_v3_catalog;

-- J. 实际角色数据异常检查。
select character_id, count(*) as equipped_exclusive_count
from public.character_exclusive_techniques
where equipped
group by character_id
having count(*)>1;

select count(*) as active_opportunity_technique_effects
from public.character_cultivation_effects
where is_active and source_key like 'opptech:%';

select count(*) as active_exclusive_effects
from public.character_cultivation_effects
where is_active and source_key like 'exclusive:%';

-- K. 综合结果。所有 status 应为 PASS。
with checks as (
  select 'catalog_total_300' as item,
         case when (select count(*) from public.opportunity_v3_catalog where is_active)=300 then 'PASS' else 'FAIL' end as status
  union all select 'yellow_150',case when (select count(*) from public.opportunity_v3_catalog where grade='黄品' and is_active)=150 then 'PASS' else 'FAIL' end
  union all select 'mystic_72',case when (select count(*) from public.opportunity_v3_catalog where grade='玄品' and is_active)=72 then 'PASS' else 'FAIL' end
  union all select 'earth_45',case when (select count(*) from public.opportunity_v3_catalog where grade='地品' and is_active)=45 then 'PASS' else 'FAIL' end
  union all select 'heaven_24',case when (select count(*) from public.opportunity_v3_catalog where grade='天品' and is_active)=24 then 'PASS' else 'FAIL' end
  union all select 'immortal_9',case when (select count(*) from public.opportunity_v3_catalog where grade='仙品' and is_active)=9 then 'PASS' else 'FAIL' end
  union all select 'exclusive_5',case when (select count(*) from public.exclusive_technique_definitions)=5 then 'PASS' else 'FAIL' end
  union all select 'mystic_23_fixed',case when exists(select 1 from public.opportunity_v3_catalog where code='mystic_023' and positive_text like '%清泉纳灵诀%' and positive_text not like '%浅溪养气诀%') then 'PASS' else 'FAIL' end
  union all select 'intervals',case when exists(select 1 from public.opportunity_v3_settings where world_code='jiuxiao_world_1' and online_interval_seconds=300 and offline_interval_seconds=1200 and offline_catchup_limit=1) then 'PASS' else 'FAIL' end
  union all select 'unsupported_rewards_rewritten',case when not exists(select 1 from public.opportunity_v3_catalog where positive_text like '%直接突破%' or positive_text like '%所有已习得功法效果翻倍%' or positive_text like '%满境界修为%') then 'PASS' else 'FAIL' end
  union all select 'exclusive_single_slot',case when not exists(select character_id from public.character_exclusive_techniques where equipped group by character_id having count(*)>1) then 'PASS' else 'FAIL' end
)
select * from checks order by item;
