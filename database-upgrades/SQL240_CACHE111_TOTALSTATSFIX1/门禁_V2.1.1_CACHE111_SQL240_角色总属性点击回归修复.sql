-- 九霄问道 · V2.1.1 CACHE111 · SQL240 制度门禁
-- CACHE111网页/APP部署成功 + SQL240升级SQL成功后执行。
-- 门禁重新验证SQL239孔位核心规则后，将release_control提升到CACHE111。

begin;
lock table public.jiuxiao_app_release_control in row exclusive mode;

do $gate$
declare
  v_attr oid; v_bulk oid; v_legacy oid; v_comment text; v_def text; v_numeric oid;
begin
  if to_regclass('public.equipment_socket_settings_v210') is null
     or to_regclass('public.equipment_socket_affixes_v210') is null then
    raise exception 'SQL240_GATE_EQUIPMENT_SOCKET_TABLES_MISSING';
  end if;
  if not exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='equipment_socket_settings_v210'
      and column_name='level_reroll_enabled' and data_type='boolean'
  ) then raise exception 'SQL240_GATE_LEVEL_REROLL_SWITCH_MISSING'; end if;

  v_attr:=to_regprocedure('public.reroll_equipment_socket_attributes_v210(uuid,smallint[],uuid)');
  v_bulk:=to_regprocedure('public.reroll_equipment_socket_levels_v210(uuid,smallint[],uuid)');
  v_legacy:=to_regprocedure('public.reroll_equipment_socket_level_v210(uuid,smallint,uuid)');
  if v_attr is null then raise exception 'SQL240_GATE_ATTR_REROLL_RPC_MISSING'; end if;
  if v_bulk is null then raise exception 'SQL240_GATE_BULK_LEVEL_REROLL_RPC_MISSING'; end if;
  if v_legacy is null then raise exception 'SQL240_GATE_LEGACY_LEVEL_RPC_MISSING'; end if;

  if not has_function_privilege('authenticated',v_attr,'EXECUTE') or has_function_privilege('anon',v_attr,'EXECUTE') then
    raise exception 'SQL240_GATE_ATTR_REROLL_PRIVILEGE_INVALID';
  end if;
  if not has_function_privilege('authenticated',v_bulk,'EXECUTE') or has_function_privilege('anon',v_bulk,'EXECUTE') then
    raise exception 'SQL240_GATE_BULK_LEVEL_REROLL_PRIVILEGE_INVALID';
  end if;

  select obj_description(v_attr,'pg_proc'),pg_get_functiondef(v_attr) into v_comment,v_def;
  if coalesce(v_comment,'') not like '%SQL239 V2.1.1 CACHE110 FORGE_UI2%'
     or position('EQUIPMENT_V210_LOCK_LIMIT_EXCEEDED' in v_def)=0
     or position('v_lock_count*v_settings.lock_item_cost_per_socket' in replace(v_def,' ',''))=0 then
    raise exception 'SQL240_GATE_SQL239_ATTR_RULES_INVALID';
  end if;

  select obj_description(v_bulk,'pg_proc'),pg_get_functiondef(v_bulk) into v_comment,v_def;
  if coalesce(v_comment,'') not like '%SQL239 V2.1.1 CACHE110 FORGE_UI2%'
     or position('level_reroll_enabled' in v_def)=0
     or position('EQUIPMENT_V210_LOCK_LIMIT_EXCEEDED' in v_def)=0
     or position('EQUIPMENT_V210_NO_UNLOCKED_FILLED_SOCKET' in v_def)=0
     or position('reroll_levels_bulk_cache110' in v_def)=0 then
    raise exception 'SQL240_GATE_SQL239_BULK_BAILIAN_RULES_INVALID';
  end if;

  select obj_description(v_legacy,'pg_proc') into v_comment;
  if coalesce(v_comment,'') not like '%SQL239 V2.1.1 CACHE110 LEGACY_COMPAT%'
     or position('reroll_equipment_socket_levels_v210' in pg_get_functiondef(v_legacy))=0 then
    raise exception 'SQL240_GATE_SQL239_LEGACY_COMPAT_INVALID';
  end if;

  v_numeric:=to_regprocedure('public.bwboss01_grant_token(uuid,numeric)');
  if v_numeric is null then raise exception 'SQL240_GATE_WBOSS_NUMERIC_COMPAT_MISSING'; end if;
  if has_function_privilege('anon',v_numeric,'EXECUTE') or has_function_privilege('authenticated',v_numeric,'EXECUTE') then
    raise exception 'SQL240_GATE_WBOSS_NUMERIC_INTERNAL_RPC_EXPOSED';
  end if;
end
$gate$;

update public.jiuxiao_app_release_control
set release_name='V2.1.1 CACHE111',
    cache_epoch=111,
    notice_text='V2.1.1 CACHE111：修复元神中央点击“角色总属性”无反应的客户端样式回归；恢复总属性弹窗。继续沿用CACHE110锁3孔、兵魄/护道、百炼整装重炼及ADMIN9 R22规则。',
    updated_at=clock_timestamp()
where singleton_id=1;

commit;
notify pgrst,'reload schema';

select jsonb_build_object(
  'success',true,
  'gate','SQL240_GATE_PASSED',
  'sql',240,
  'release_name',(select release_name from public.jiuxiao_app_release_control where singleton_id=1),
  'cache_epoch',(select cache_epoch from public.jiuxiao_app_release_control where singleton_id=1),
  'total_stats_entry','CLIENT_STYLE_RESTORED_BY_CACHE111',
  'forge_rules','SQL239_REVALIDATED',
  'next_sql',241
) as sql240_gate_result;
