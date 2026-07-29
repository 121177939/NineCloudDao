-- 九霄问道 V0.15.4 FIX4 CACHE24 最终检查（只读）
-- 修复：原检查脚本第23行多余右括号，以及文本检索误用双引号。

with defs as (
  select
    coalesce(pg_get_functiondef(to_regprocedure('public.claim_cultivation_v1()')), '') as claim_def,
    coalesce(pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')), '') as attempt_def,
    coalesce(pg_get_functiondef(to_regprocedure('public.purchase_treasure_item_v0154(text,integer,uuid)')), '') as purchase_def
), checks(item, passed, detail) as (
  select 'release_cache24',
         exists(
           select 1
           from public.jiuxiao_app_release_control
           where singleton_id = 1 and cache_epoch >= 24
         ),
         '发布控制已升至 CACHE24'

  union all
  select 'operation_idempotency_table',
         to_regclass('public.player_operation_requests_v0154') is not null,
         '幂等请求表存在'

  union all
  select 'treasure_status_rpc',
         to_regprocedure('public.get_treasure_shop_v0154()') is not null,
         '珍宝阁读取 RPC 存在'

  union all
  select 'treasure_purchase_rpc',
         to_regprocedure('public.purchase_treasure_item_v0154(text,integer,uuid)') is not null,
         '珍宝阁购买 RPC 存在'

  union all
  select 'wash_rpc',
         to_regprocedure('public.use_spirit_washing_pill_v0154(uuid)') is not null,
         '洗灵丹 RPC 存在'

  union all
  select 'breakthrough_status_v0154',
         to_regprocedure('public.get_breakthrough_status_v0154()') is not null,
         '渡境清元丹突破状态 RPC 存在'

  union all
  select 'breakthrough_attempt_v0154',
         to_regprocedure('public.attempt_breakthrough_v0154(integer,uuid)') is not null,
         '渡境清元丹突破事务 RPC 存在'

  union all
  select 'ordinary_upgrade_v0154',
         to_regprocedure('public.upgrade_technique_v0154(uuid,uuid)') is not null,
         '普通功法幂等升级 RPC 存在'

  union all
  select 'exclusive_upgrade_v0154',
         to_regprocedure('public.upgrade_exclusive_technique_v0154(uuid,uuid)') is not null,
         '专属功法幂等升级 RPC 存在'

  union all
  select 'item_use_v0154',
         to_regprocedure('public.use_inventory_item_quantity_v0154(uuid,integer,uuid)') is not null,
         '道具幂等使用 RPC 存在'

  union all
  select 'breakthrough_pill_item',
         exists(
           select 1
           from public.item_definitions
           where code = 'breakthrough_clear_origin_pill_v0154'
             and name = '渡境清元丹'
         ),
         '渡境清元丹定义存在'

  union all
  select 'washing_pill_item',
         exists(
           select 1
           from public.item_definitions
           where code = 'spirit_washing_pill_v0154'
             and name = '洗灵丹'
         ),
         '洗灵丹定义存在'

  union all
  select 'pill_category_valid',
         not exists(
           select 1
           from public.item_definitions
           where code in (
             'breakthrough_clear_origin_pill_v0154',
             'spirit_washing_pill_v0154'
           )
             and category::text = '丹药'
         ),
         '丹药类别符合既有 CHECK 约束，不再写入中文展示词'

  union all
  select 'treasure_instant_inventory_payload',
         (
           select
             strpos(purchase_def, $q$'inventory_id'$q$) > 0
             and strpos(purchase_def, $q$'inventory_quantity'$q$) > 0
             and strpos(purchase_def, $q$'item_effects'$q$) > 0
           from defs
         ),
         '购买RPC返回库存ID、实时堆叠数量与物品效果，前端可即时入包并使用'

  union all
  select 'treasure_purchase_no_unique_constraint_dependency',
         (
           select strpos(purchase_def, 'on conflict(character_id,item_definition_id)') = 0
           from defs
         ),
         '购买RPC不依赖线上不存在的复合唯一约束'

  union all
  select 'operation_table_rls',
         coalesce(
           (
             select c.relrowsecurity
             from pg_class c
             where c.oid = to_regclass('public.player_operation_requests_v0154')
           ),
           false
         ),
         '幂等请求表已启用 RLS'

  union all
  select 'technique_bucket_fixed',
         (
           select
             strpos(claim_def, $q$source_key like 'opptech:%'$q$) > 0
             and strpos(claim_def, $q$not (e.source_key like 'opptech:%'$q$) > 0
           from defs
         ),
         '功法效果独立归类，不再计入持续机缘'

  union all
  select 'dao_collapse_probability',
         (
           select strpos(attempt_def, 'v_roll<0.003') > 0
           from defs
         ),
         '道果崩解概率为 0.3%'

  union all
  select 'death_removed',
         (
           select
             strpos(attempt_def, $q$status='dead'$q$) = 0
             and strpos(attempt_def, $q$v_outcome:='death'$q$) = 0
           from defs
         ),
         '突破失败死亡分支已移除'

  union all
  select 'pill_to_100',
         (
           select
             strpos(
               attempt_def,
               $q$current_setting('ncd.v0154_breakthrough_pill_quantity'$q$
             ) > 0
             and strpos(attempt_def, 'least(1.0') > 0
           from defs
         ),
         '渡境清元丹可把最终概率推至 100%'
)
select *
from checks
order by item;

select release_name, cache_epoch, notice_text, updated_at
from public.jiuxiao_app_release_control
where singleton_id = 1;

select code, name, category, effects, description
from public.item_definitions
where code in (
  'breakthrough_clear_origin_pill_v0154',
  'spirit_washing_pill_v0154'
)
order by code;

select
  count(*) filter (where recovery_active) as active_recovery_cycles,
  count(*) filter (where dao_collapse_active) as active_dao_collapse_recoveries,
  count(*) filter (
    where recovery_active
      and (
        original_target_stage_id is null
        or recovery_anchor_stage_id is null
        or recovery_floor_stage_id is null
      )
  ) as incomplete_recovery_rows
from public.character_breakthrough_states;
