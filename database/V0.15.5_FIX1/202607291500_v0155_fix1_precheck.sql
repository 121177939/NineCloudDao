-- 九霄问道 V0.15.5 FIX1 CACHE27 升级前检查（只读）
-- 可从 V0.15.4 FIX5 CACHE25 直接升级；此前未部署 CACHE26 也无需补跑。
-- 本版本只修正洞府视觉并封存 V0.15.5 前端功能，不新增战斗属性数据或数据库结构。

with checks(item, ok, detail) as (
  select '发布控制表',
         to_regclass('public.jiuxiao_app_release_control') is not null,
         'jiuxiao_app_release_control 必须存在'
  union all
  select '当前缓存基线',
         coalesce((select cache_epoch >= 25 from public.jiuxiao_app_release_control where singleton_id = 1), false),
         '应至少已部署 V0.15.4 FIX5 CACHE25'
  union all
  select '角色库存表',
         to_regclass('public.character_inventory') is not null,
         '洞府储物格继续读取真实角色库存'
  union all
  select '物品定义表',
         to_regclass('public.item_definitions') is not null,
         '洞府物品详情继续读取正式物品定义'
)
select * from checks order by item;
