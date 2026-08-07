-- 九霄问道 · V2.1.1 CACHE110 · SQL239 制度门禁
-- CACHE110网页/APP部署成功 + SQL239升级SQL成功后执行。
-- 门禁通过后将release_control正式提升到CACHE110。

begin;
lock table public.jiuxiao_app_release_control in row exclusive mode;

do $gate$
declare v_attr oid;v_bulk oid;v_legacy oid;v_admin oid;v_numeric oid;v_comment text;v_def text;
begin
  if to_regclass('public.equipment_socket_settings_v210') is null
     or to_regclass('public.equipment_socket_affixes_v210') is null then
    raise exception 'SQL239_GATE_EQUIPMENT_SOCKET_TABLES_MISSING';
  end if;
  if not exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='equipment_socket_settings_v210'
      and column_name='level_reroll_enabled' and data_type='boolean'
  ) then raise exception 'SQL239_GATE_LEVEL_REROLL_ENABLED_MISSING'; end if;

  v_attr:=to_regprocedure('public.reroll_equipment_socket_attributes_v210(uuid,smallint[],uuid)');
  v_bulk:=to_regprocedure('public.reroll_equipment_socket_levels_v210(uuid,smallint[],uuid)');
  v_legacy:=to_regprocedure('public.reroll_equipment_socket_level_v210(uuid,smallint,uuid)');
  v_admin:=to_regprocedure('public.admin_set_v210_core_settings(text,jsonb,text,uuid)');
  if v_attr is null then raise exception 'SQL239_GATE_ATTR_REROLL_RPC_MISSING'; end if;
  if v_bulk is null then raise exception 'SQL239_GATE_BULK_LEVEL_REROLL_RPC_MISSING'; end if;
  if v_legacy is null then raise exception 'SQL239_GATE_LEGACY_LEVEL_RPC_MISSING'; end if;
  if v_admin is null then raise exception 'SQL239_GATE_ADMIN_SETTER_MISSING'; end if;

  if not has_function_privilege('authenticated',v_attr,'EXECUTE') or has_function_privilege('anon',v_attr,'EXECUTE') then
    raise exception 'SQL239_GATE_ATTR_REROLL_PRIVILEGE_INVALID';
  end if;
  if not has_function_privilege('authenticated',v_bulk,'EXECUTE') or has_function_privilege('anon',v_bulk,'EXECUTE') then
    raise exception 'SQL239_GATE_BULK_LEVEL_REROLL_PRIVILEGE_INVALID';
  end if;
  if not has_function_privilege('authenticated',v_legacy,'EXECUTE') or has_function_privilege('anon',v_legacy,'EXECUTE') then
    raise exception 'SQL239_GATE_LEGACY_LEVEL_RPC_PRIVILEGE_INVALID';
  end if;

  select obj_description(v_attr,'pg_proc') into v_comment;
  if coalesce(v_comment,'') not like '%SQL239 V2.1.1 CACHE110 FORGE_UI2%' then raise exception 'SQL239_GATE_ATTR_MARKER_MISSING'; end if;
  select pg_get_functiondef(v_attr) into v_def;
  if position('v_lock_count>3' in replace(v_def,' ',''))=0
     or position('EQUIPMENT_V210_LOCK_LIMIT_EXCEEDED' in v_def)=0
     or position('v_lock_count*v_settings.lock_item_cost_per_socket' in replace(v_def,' ',''))=0 then
    raise exception 'SQL239_GATE_ATTR_LOCK3_ENFORCEMENT_MISSING';
  end if;

  select obj_description(v_bulk,'pg_proc') into v_comment;
  if coalesce(v_comment,'') not like '%SQL239 V2.1.1 CACHE110 FORGE_UI2%' then raise exception 'SQL239_GATE_BULK_MARKER_MISSING'; end if;
  select pg_get_functiondef(v_bulk) into v_def;
  if position('level_reroll_enabled' in v_def)=0
     or position('EQUIPMENT_V210_LEVEL_REROLL_DISABLED' in v_def)=0
     or position('EQUIPMENT_V210_LOCK_LIMIT_EXCEEDED' in v_def)=0
     or position('EQUIPMENT_V210_NO_UNLOCKED_FILLED_SOCKET' in v_def)=0
     or position('reroll_levels_bulk_cache110' in v_def)=0 then
    raise exception 'SQL239_GATE_BULK_RULE_ENFORCEMENT_MISSING';
  end if;

  select obj_description(v_legacy,'pg_proc') into v_comment;
  if coalesce(v_comment,'') not like '%SQL239 V2.1.1 CACHE110 LEGACY_COMPAT%' then raise exception 'SQL239_GATE_LEGACY_MARKER_MISSING'; end if;
  if position('reroll_equipment_socket_levels_v210' in pg_get_functiondef(v_legacy))=0 then
    raise exception 'SQL239_GATE_LEGACY_SINGLE_SOCKET_BYPASS_STILL_PRESENT';
  end if;

  if position('level_reroll_enabled' in pg_get_functiondef(v_admin))=0 then
    raise exception 'SQL239_GATE_ADMIN_BAILIAN_SWITCH_WRITE_MISSING';
  end if;

  v_numeric:=to_regprocedure('public.bwboss01_grant_token(uuid,numeric)');
  if v_numeric is null then raise exception 'SQL239_GATE_WBOSS_NUMERIC_GRANT_MISSING'; end if;
  select obj_description(v_numeric,'pg_proc') into v_comment;
  if coalesce(v_comment,'') not like '%SQL239 V2.1.1 CACHE110 COMPAT%' then raise exception 'SQL239_GATE_WBOSS_NUMERIC_MARKER_MISSING'; end if;
  if has_function_privilege('anon',v_numeric,'EXECUTE') or has_function_privilege('authenticated',v_numeric,'EXECUTE') then
    raise exception 'SQL239_GATE_WBOSS_NUMERIC_INTERNAL_RPC_EXPOSED';
  end if;
end
$gate$;

update public.jiuxiao_app_release_control
set release_name='V2.1.1 CACHE110',
    cache_epoch=110,
    notice_text='V2.1.1 CACHE110：装备孔位页紧凑化；孔位标题点按查看规则；最多锁3孔并同时保护属性与等级；兵魄/护道刷新未锁孔属性类型，百炼一次重炼全部未锁已有孔等级；洗炼操作原地即时更新，不再整页刷新。',
    updated_at=clock_timestamp()
where singleton_id=1;

commit;
notify pgrst,'reload schema';

select jsonb_build_object(
  'success',true,
  'gate','SQL239_GATE_PASSED',
  'sql',239,
  'release_name',(select release_name from public.jiuxiao_app_release_control where singleton_id=1),
  'cache_epoch',(select cache_epoch from public.jiuxiao_app_release_control where singleton_id=1),
  'socket_lock_max',3,
  'bailian_rule','ALL_UNLOCKED_FILLED_LEVELS_REROLL',
  'next_sql',240
) as sql239_gate_result;
