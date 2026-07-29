-- 九霄问道 V0.15.5 CACHE26 升级前检查（只读）
-- 本版本为前端洞府与元神界面升级；不创建战斗属性数据，不修改既有结算规则。

with checks(item, ok, detail) as (
  select '发布控制表', to_regclass('public.jiuxiao_app_release_control') is not null, 'jiuxiao_app_release_control 必须存在'
  union all
  select '当前缓存基线', coalesce((select cache_epoch >= 25 from public.jiuxiao_app_release_control where singleton_id=1), false), '应已部署 V0.15.4 FIX5 CACHE25'
  union all
  select '角色库存表', to_regclass('public.character_inventory') is not null, 'B-CAVE01 继续读取真实角色库存'
  union all
  select '物品定义表', to_regclass('public.item_definitions') is not null, '洞府储物格需要物品定义'
)
select * from checks order by item;
