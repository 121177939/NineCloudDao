-- 九霄问道 · V2.1.1 CACHE111 · SQL240
-- 角色总属性点击回归修复发布登记。
-- 本次实际缺陷为客户端CSS回归：CACHE110重写装备孔位样式时误删 total-stats 弹窗样式。
-- 本SQL不改变战斗、装备、孔位、世界BOSS、GM参数；只验证CACHE110/SQL239服务端规则已具备。
-- 执行顺序：部署CACHE111客户端后执行本SQL，再执行配套制度门禁SQL。

begin;
lock table public.jiuxiao_app_release_control in row exclusive mode;

do $precheck$
declare v_cache integer; v_release text; v_comment text;
begin
  if to_regclass('public.jiuxiao_app_release_control') is null then
    raise exception 'SQL240_PRECHECK_RELEASE_CONTROL_MISSING';
  end if;
  if to_regclass('public.equipment_socket_settings_v210') is null
     or to_regclass('public.equipment_socket_affixes_v210') is null then
    raise exception 'SQL240_PRECHECK_SQL239_EQUIPMENT_BASE_MISSING';
  end if;
  if not exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='equipment_socket_settings_v210'
      and column_name='level_reroll_enabled' and data_type='boolean'
  ) then raise exception 'SQL240_PRECHECK_SQL239_LEVEL_REROLL_SWITCH_MISSING'; end if;

  if to_regprocedure('public.reroll_equipment_socket_attributes_v210(uuid,smallint[],uuid)') is null
     or to_regprocedure('public.reroll_equipment_socket_levels_v210(uuid,smallint[],uuid)') is null
     or to_regprocedure('public.reroll_equipment_socket_level_v210(uuid,smallint,uuid)') is null then
    raise exception 'SQL240_PRECHECK_SQL239_FORGE_RPC_MISSING';
  end if;

  select obj_description(to_regprocedure('public.reroll_equipment_socket_levels_v210(uuid,smallint[],uuid)'),'pg_proc') into v_comment;
  if coalesce(v_comment,'') not like '%SQL239 V2.1.1 CACHE110 FORGE_UI2%' then
    raise exception 'SQL240_PRECHECK_SQL239_BULK_BAILIAN_MARKER_MISSING';
  end if;

  select release_name,cache_epoch into v_release,v_cache
  from public.jiuxiao_app_release_control where singleton_id=1 for update;
  if not found then raise exception 'SQL240_PRECHECK_RELEASE_ROW_MISSING'; end if;
  if coalesce(v_cache,-1)>111 then
    raise exception 'SQL240_PRECHECK_NEWER_RELEASE_BLOCK:%/%',v_release,v_cache;
  end if;
end
$precheck$;

commit;
notify pgrst,'reload schema';

select jsonb_build_object(
  'success',true,
  'sql',240,
  'feature','TOTAL_STATS_MODAL_CLIENT_REGRESSION_FIX',
  'database_logic_changed',false,
  'sql239_forge_rules_ready',true,
  'release_control_unchanged',(select release_name from public.jiuxiao_app_release_control where singleton_id=1),
  'cache_epoch_unchanged',(select cache_epoch from public.jiuxiao_app_release_control where singleton_id=1),
  'next','RUN_V2.1.1_CACHE111_SQL240_GATE',
  'next_sql',241
) as sql240_install_result;
