-- 九霄问道 · V2.1.1 CACHE108 · SQL236 制度门禁
-- SQL236升级成功 + CACHE108游戏部署成功后执行。

begin;
lock table public.jiuxiao_app_release_control in row exclusive mode;

do $gate$
declare v_oid oid; v_comment text; v_admin_comment text;
begin
  if not exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='equipment_socket_settings_v210' and column_name='level_reroll_enabled' and data_type='boolean'
  ) then raise exception 'SQL236_GATE_LEVEL_REROLL_ENABLED_COLUMN_MISSING'; end if;

  if (select level_reroll_enabled from public.equipment_socket_settings_v210 where singleton_id=1) is null then
    raise exception 'SQL236_GATE_LEVEL_REROLL_ENABLED_NULL';
  end if;

  v_oid:=to_regprocedure('public.reroll_equipment_socket_level_v210(uuid,smallint,uuid)');
  if v_oid is null then raise exception 'SQL236_GATE_LEVEL_REROLL_RPC_MISSING'; end if;
  select obj_description(v_oid,'pg_proc') into v_comment;
  if coalesce(v_comment,'') not like '%SQL236 V2.1.1 CACHE108 BAILIAN_SWITCH1%' then
    raise exception 'SQL236_GATE_LEVEL_REROLL_RPC_MARKER_MISSING';
  end if;
  if position('level_reroll_enabled' in pg_get_functiondef(v_oid))=0 or position('EQUIPMENT_V210_LEVEL_REROLL_DISABLED' in pg_get_functiondef(v_oid))=0 then
    raise exception 'SQL236_GATE_LEVEL_REROLL_SERVER_ENFORCEMENT_MISSING';
  end if;
  if not has_function_privilege('authenticated',v_oid,'EXECUTE') or has_function_privilege('anon',v_oid,'EXECUTE') then
    raise exception 'SQL236_GATE_LEVEL_REROLL_RPC_PRIVILEGE_INVALID';
  end if;

  v_oid:=to_regprocedure('public.admin_set_v210_core_settings(text,jsonb,text,uuid)');
  if v_oid is null then raise exception 'SQL236_GATE_ADMIN_SETTER_MISSING'; end if;
  select obj_description(v_oid,'pg_proc') into v_admin_comment;
  if coalesce(v_admin_comment,'') not like '%SQL236 V2.1.1 CACHE108 ADMIN9 R22%' then
    raise exception 'SQL236_GATE_ADMIN_SETTER_MARKER_MISSING';
  end if;
  if position('level_reroll_enabled' in pg_get_functiondef(v_oid))=0 then
    raise exception 'SQL236_GATE_ADMIN_SETTER_SWITCH_MISSING';
  end if;

  if to_regprocedure('public.admin_get_v210_equipment_boss_control()') is null then
    raise exception 'SQL236_GATE_ADMIN_READER_MISSING';
  end if;
end
$gate$;

update public.jiuxiao_app_release_control
set release_name='V2.1.1 CACHE108',
    cache_epoch=108,
    notice_text='V2.1.1 CACHE108：ADMIN9 R22新增百炼玄铁孔位等级刷新总开关；关闭后服务端强制禁止使用且不消耗材料，客户端同步禁用百炼按钮。',
    updated_at=clock_timestamp()
where singleton_id=1;

commit;
notify pgrst,'reload schema';

select jsonb_build_object(
  'success',true,
  'gate','SQL236_GATE_PASSED',
  'sql',236,
  'release_name',(select release_name from public.jiuxiao_app_release_control where singleton_id=1),
  'cache_epoch',(select cache_epoch from public.jiuxiao_app_release_control where singleton_id=1),
  'bailian_enabled',(select level_reroll_enabled from public.equipment_socket_settings_v210 where singleton_id=1),
  'next_sql',237
) as sql236_gate_result;
