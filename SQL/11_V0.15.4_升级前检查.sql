-- 九霄问道 V0.15.4 CACHE23 升级前检查（只读）
with checks(item,passed,detail) as (
  values
    ('player_characters',to_regclass('public.player_characters') is not null,'角色表存在'),
    ('item_definitions',to_regclass('public.item_definitions') is not null,'物品定义表存在'),
    ('character_inventory',to_regclass('public.character_inventory') is not null,'角色背包存在'),
    ('spirit_roots',to_regclass('public.spirit_roots') is not null,'灵根定义表存在'),
    ('character_spirit_roots',to_regclass('public.character_spirit_roots') is not null,'角色灵根表存在'),
    ('breakthrough_states',to_regclass('public.character_breakthrough_states') is not null,'突破状态表存在'),
    ('claim_rpc',to_regprocedure('public.claim_cultivation_v1()') is not null,'修炼结算RPC存在'),
    ('breakthrough_status_rpc',to_regprocedure('public.get_breakthrough_status_v1()') is not null,'突破状态RPC存在'),
    ('breakthrough_attempt_rpc',to_regprocedure('public.attempt_breakthrough_v1()') is not null,'突破结算RPC存在'),
    ('ordinary_upgrade_rpc',to_regprocedure('public.upgrade_technique_v2(uuid)') is not null,'普通功法升级RPC存在'),
    ('exclusive_upgrade_rpc',to_regprocedure('public.upgrade_exclusive_technique_v1(uuid)') is not null,'专属功法升级RPC存在'),
    ('item_use_rpc',to_regprocedure('public.use_inventory_item_quantity_v0147(uuid,integer)') is not null,'批量道具使用RPC存在'),
    ('stone_balance_rpc',to_regprocedure('public.spirit_stone_balance_v0141(uuid)') is not null,'统一灵石余额函数存在'),
    ('stone_debit_rpc',to_regprocedure('public.spirit_stone_debit_v0141(uuid,bigint,text)') is not null,'统一灵石扣款函数存在'),
    ('release_control',to_regclass('public.jiuxiao_app_release_control') is not null,'发布控制表存在'),
    ('historical_peak',exists(select 1 from information_schema.columns where table_schema='public' and table_name='character_breakthrough_states' and column_name='historical_peak_stage_id'),'CACHE22历史境界字段存在')
)
select * from checks order by item;

-- FIX1：显示线上物品类别约束与现有类别，便于核对。
select c.conname,pg_get_constraintdef(c.oid) as constraint_definition
from pg_constraint c
where c.conrelid='public.item_definitions'::regclass and c.contype='c'
order by c.conname;

select category,count(*) as item_count
from public.item_definitions
group by category
order by category;

select
  md5(pg_get_functiondef('public.claim_cultivation_v1()'::regprocedure)) as claim_before_md5,
  md5(pg_get_functiondef('public.get_breakthrough_status_v1()'::regprocedure)) as breakthrough_status_before_md5,
  md5(pg_get_functiondef('public.attempt_breakthrough_v1()'::regprocedure)) as breakthrough_attempt_before_md5;
