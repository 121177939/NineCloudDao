-- 九霄问道 · V2.1.1 CACHE109 · SQL238 制度门禁
-- CACHE109网页/APP资源部署成功 + SQL238升级SQL成功后执行。
-- 门禁通过后将release_control正式提升到CACHE109。

begin;
lock table public.jiuxiao_app_release_control in row exclusive mode;

do $gate$
declare v_forge oid; v_numeric oid; v_comment text;
begin
  v_forge:=to_regprocedure('public.get_equipment_forge_overview_v210()');
  if v_forge is null then raise exception 'SQL238_GATE_FORGE_OVERVIEW_RPC_MISSING'; end if;
  if not has_function_privilege('authenticated',v_forge,'EXECUTE')
     or has_function_privilege('anon',v_forge,'EXECUTE') then
    raise exception 'SQL238_GATE_FORGE_OVERVIEW_RPC_PRIVILEGE_INVALID';
  end if;

  if to_regclass('public.equipment_socket_affixes_v210') is null
     or to_regclass('public.equipment_socket_level_config_v210') is null then
    raise exception 'SQL238_GATE_EQUIPMENT_SOCKET_TABLES_MISSING';
  end if;

  v_numeric:=to_regprocedure('public.bwboss01_grant_token(uuid,numeric)');
  if v_numeric is null then raise exception 'SQL238_GATE_WBOSS_NUMERIC_GRANT_MISSING'; end if;
  select obj_description(v_numeric,'pg_proc') into v_comment;
  if coalesce(v_comment,'') not like '%SQL238 V2.1.1 CACHE109 EQUIPMENT_DETAIL1%' then
    raise exception 'SQL238_GATE_MARKER_MISSING';
  end if;
  if has_function_privilege('anon',v_numeric,'EXECUTE')
     or has_function_privilege('authenticated',v_numeric,'EXECUTE') then
    raise exception 'SQL238_GATE_INTERNAL_WBOSS_GRANT_EXPOSED';
  end if;
end
$gate$;

update public.jiuxiao_app_release_control
set release_name='V2.1.1 CACHE109',
    cache_epoch=109,
    notice_text='V2.1.1 CACHE109：装备详情基础说明区改为单列孔位属性；①至⑧显示属性/空，等级统一LV.x，LV.10整条红字。继续沿用ADMIN9 R22与现有世界BOSS/孔位数值规则。',
    updated_at=clock_timestamp()
where singleton_id=1;

commit;
notify pgrst,'reload schema';

select jsonb_build_object(
  'success',true,
  'gate','SQL238_GATE_PASSED',
  'sql',238,
  'release_name',(select release_name from public.jiuxiao_app_release_control where singleton_id=1),
  'cache_epoch',(select cache_epoch from public.jiuxiao_app_release_control where singleton_id=1),
  'equipment_detail','SOCKET_LIST_SINGLE_COLUMN_LV10_RED',
  'next_sql',239
) as sql238_gate_result;
