-- 九霄问道 V0.15.5 FIX1 CACHE27 升级后检查（只读）
with checks(item, ok, detail) as (
  select '发布缓存 CACHE27',
         coalesce((
           select cache_epoch >= 27 and release_name = 'V0.15.5 FIX1 CACHE27'
           from public.jiuxiao_app_release_control
           where singleton_id = 1
         ), false),
         '发布控制应为 V0.15.5 FIX1 CACHE27'
  union all
  select '角色库存数据链',
         to_regclass('public.character_inventory') is not null,
         '洞府继续使用真实库存'
  union all
  select '物品定义数据链',
         to_regclass('public.item_definitions') is not null,
         '物品详情继续使用正式定义'
)
select * from checks order by item;

select release_name, cache_epoch, notice_text, updated_at
from public.jiuxiao_app_release_control
where singleton_id = 1;
