-- 九霄问道 · V2.1.1 CACHE107 · SQL235
-- 世界BOSS“锁定快照并准备 / 复制口令”客户端点击链热修登记。
-- 本SQL不重建SQL233/234对象，不改变世界BOSS战斗/奖励规则；仅验证生产契约并登记SQL235热修。
-- 执行顺序：先部署V2.1.1 CACHE107游戏文件，再执行本SQL，成功后执行配套“门禁SQL”。

begin;
lock table public.jiuxiao_app_release_control in row exclusive mode;
lock table public.world_boss_settings_bwboss01 in share mode;

do $precheck$
declare
  v_release text;
  v_cache integer;
  v_start time;
  v_duration integer;
  v_oid oid;
  v_sec boolean;
  v_path boolean;
begin
  if to_regclass('public.jiuxiao_app_release_control') is null then
    raise exception 'SQL235_PRECHECK_RELEASE_CONTROL_MISSING';
  end if;
  if to_regclass('public.world_boss_settings_bwboss01') is null then
    raise exception 'SQL235_PRECHECK_WORLD_BOSS_SETTINGS_MISSING';
  end if;
  if to_regprocedure('public.set_world_boss_member_ready_bwboss01(boolean,text,uuid)') is null then
    raise exception 'SQL235_PRECHECK_READY_RPC_MISSING';
  end if;
  if to_regprocedure('public.get_world_boss_state_bwboss01()') is null then
    raise exception 'SQL235_PRECHECK_STATE_RPC_MISSING';
  end if;

  select release_name,cache_epoch into v_release,v_cache
  from public.jiuxiao_app_release_control where singleton_id=1 for update;
  if not found then raise exception 'SQL235_PRECHECK_RELEASE_ROW_MISSING'; end if;
  if coalesce(v_cache,-1)>107 then
    raise exception 'SQL235_PRECHECK_NEWER_RELEASE_BLOCK:%/%',v_release,v_cache;
  end if;
  if coalesce(v_cache,-1)=107 and coalesce(v_release,'') not in ('V2.1.1 CACHE107','') then
    raise exception 'SQL235_PRECHECK_CACHE107_COLLISION:%/%',v_release,v_cache;
  end if;

  select daily_start_local,duration_minutes into v_start,v_duration
  from public.world_boss_settings_bwboss01 where singleton_id=1;
  if not found then raise exception 'SQL235_PRECHECK_WORLD_BOSS_SETTINGS_ROW_MISSING'; end if;
  if coalesce(v_start,time '23:59')<>time '00:00' or coalesce(v_duration,0)<>1440 then
    raise exception 'SQL235_PRECHECK_SQL234_ALL_DAY_REQUIRED start=% duration=%',v_start,v_duration;
  end if;
  if not coalesce((select enabled from public.world_boss_settings_bwboss01 where singleton_id=1),false) then
    raise exception 'SQL235_PRECHECK_WORLD_BOSS_MUST_BE_ENABLED';
  end if;

  v_oid:=to_regprocedure('public.set_world_boss_member_ready_bwboss01(boolean,text,uuid)');
  select p.prosecdef,exists(select 1 from unnest(coalesce(p.proconfig,array[]::text[])) c where c like 'search_path=%')
    into v_sec,v_path from pg_proc p where p.oid=v_oid;
  if not coalesce(v_sec,false) or not coalesce(v_path,false) then
    raise exception 'SQL235_PRECHECK_READY_RPC_SECURITY_INVALID';
  end if;
  if not has_function_privilege('authenticated',v_oid,'EXECUTE') or has_function_privilege('anon',v_oid,'EXECUTE') then
    raise exception 'SQL235_PRECHECK_READY_RPC_PRIVILEGE_INVALID';
  end if;
end
$precheck$;

-- 记录SQL235已经完成数据库侧契约确认；不修改RPC逻辑。
comment on function public.set_world_boss_member_ready_bwboss01(boolean,text,uuid)
is 'SQL235 V2.1.1 CACHE107 READYFIX1: client click handler must use Event.currentTarget; DB ready RPC contract verified.';

commit;
notify pgrst,'reload schema';

select jsonb_build_object(
  'success',true,
  'sql',235,
  'hotfix','WORLD_BOSS_READY_CLICK_READYFIX1',
  'database_logic_changed',false,
  'world_boss','ALL_DAY',
  'release_control_unchanged',(select release_name from public.jiuxiao_app_release_control where singleton_id=1),
  'cache_epoch_unchanged',(select cache_epoch from public.jiuxiao_app_release_control where singleton_id=1),
  'next','RUN_V2.1.1_CACHE107_SQL235_GATE',
  'next_sql',236
) as sql235_install_result;
