-- 九霄问道 · V2.1.1 CACHE107 · SQL235 制度门禁
-- 在V2.1.1 CACHE107网页部署成功且配套SQL235升级SQL成功后执行。
-- 全部门禁通过后才把release_control正式提升到CACHE107。

begin;
lock table public.jiuxiao_app_release_control in row exclusive mode;
lock table public.world_boss_settings_bwboss01 in share mode;

do $gate$
declare
  v_comment text;
  v_oid oid;
  v_start time;
  v_duration integer;
begin
  v_oid:=to_regprocedure('public.set_world_boss_member_ready_bwboss01(boolean,text,uuid)');
  if v_oid is null then raise exception 'SQL235_GATE_READY_RPC_MISSING'; end if;

  select obj_description(v_oid,'pg_proc') into v_comment;
  if coalesce(v_comment,'') not like '%SQL235 V2.1.1 CACHE107 READYFIX1%' then
    raise exception 'SQL235_GATE_INSTALL_MARKER_MISSING';
  end if;

  if not has_function_privilege('authenticated',v_oid,'EXECUTE') or has_function_privilege('anon',v_oid,'EXECUTE') then
    raise exception 'SQL235_GATE_READY_RPC_PRIVILEGE_INVALID';
  end if;

  select daily_start_local,duration_minutes into v_start,v_duration
  from public.world_boss_settings_bwboss01 where singleton_id=1;
  if not found then raise exception 'SQL235_GATE_WORLD_BOSS_SETTINGS_MISSING'; end if;
  if not coalesce((select enabled from public.world_boss_settings_bwboss01 where singleton_id=1),false) then
    raise exception 'SQL235_GATE_WORLD_BOSS_DISABLED';
  end if;
  if coalesce(v_start,time '23:59')<>time '00:00' or coalesce(v_duration,0)<>1440 then
    raise exception 'SQL235_GATE_WORLD_BOSS_NOT_ALL_DAY start=% duration=%',v_start,v_duration;
  end if;

  if to_regprocedure('public.get_world_boss_state_bwboss01()') is null
     or to_regprocedure('public.start_world_boss_run_bwboss01(uuid)') is null then
    raise exception 'SQL235_GATE_WORLD_BOSS_RPC_MISSING';
  end if;
end
$gate$;

update public.jiuxiao_app_release_control
set release_name='V2.1.1 CACHE107',
    cache_epoch=107,
    notice_text='V2.1.1 CACHE107：修复世界BOSS“锁定快照并准备”及“复制口令”点击无反应；继续沿用SQL233世界BOSS/装备系统与SQL234全天开放、GM读取修复。',
    updated_at=clock_timestamp()
where singleton_id=1;

commit;
notify pgrst,'reload schema';

select jsonb_build_object(
  'success',true,
  'gate','SQL235_GATE_PASSED',
  'sql',235,
  'release_name',(select release_name from public.jiuxiao_app_release_control where singleton_id=1),
  'cache_epoch',(select cache_epoch from public.jiuxiao_app_release_control where singleton_id=1),
  'world_boss','ALL_DAY',
  'ready_rpc','READY',
  'next_sql',236
) as sql235_gate_result;
