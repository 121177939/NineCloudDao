-- 九霄问道 V1.6 CACHE44 正式发布门禁
begin;

do $$
declare v_lobby_def text;v_room_def text;v_tick_def text;
begin
  if to_regprocedure('public.paigow_emit_state_event_payload_v16_bpaigow01(uuid,text,jsonb,boolean)') is null then raise exception 'V1_6_REQUIRED:event_payload'; end if;
  if to_regprocedure('public.paigow_tick_due_rooms_bpaigow01()') is null then raise exception 'V1_6_REQUIRED:global_tick'; end if;
  if to_regprocedure('public.paigow_start_round_internal_v16_bpaigow01(uuid)') is null then raise exception 'V1_6_REQUIRED:internal_start'; end if;
  if to_regclass('public.paigow_room_event_versions_bpaigow01') is null then raise exception 'V1_6_REQUIRED:event_versions'; end if;
  if to_regclass('realtime.messages') is null then raise exception 'V1_6_REQUIRED:realtime_messages'; end if;
  if to_regclass('cron.job') is null then raise exception 'V1_6_REQUIRED:pg_cron'; end if;
  if not exists(select 1 from cron.job where jobname='jiuxiao-paigow-v16-tick' and active) then raise exception 'V1_6_REQUIRED:cron_job'; end if;

  v_lobby_def:=pg_get_functiondef(to_regprocedure('public.get_paigow_lobby_bpaigow01()'));
  v_room_def:=pg_get_functiondef(to_regprocedure('public.get_paigow_room_state_bpaigow01(uuid)'));
  v_tick_def:=pg_get_functiondef(to_regprocedure('public.paigow_tick_due_rooms_bpaigow01()'));
  if position('paigow_prepare_waiting_room_bpaigow01' in v_lobby_def)>0 or position('paigow_cleanup_rooms_bpaigow01' in v_lobby_def)>0 then raise exception 'V1_6_REQUIRED:pure_lobby_snapshot'; end if;
  if position('paigow_prepare_waiting_room_bpaigow01' in v_room_def)>0 or position('paigow_advance_room_internal' in v_room_def)>0 then raise exception 'V1_6_REQUIRED:pure_room_snapshot'; end if;
  if position('pg_try_advisory_xact_lock' in v_tick_def)=0 then raise exception 'V1_6_REQUIRED:tick_lock'; end if;
  if not exists(select 1 from pg_policies where schemaname='realtime' and tablename='messages' and policyname='paigow_v16_authenticated_receive') then raise exception 'V1_6_REQUIRED:realtime_rls'; end if;
end
$$;

update public.jiuxiao_app_release_control
set release_name='V1.6 CACHE44',
    cache_epoch=greatest(cache_epoch,44),
    notice_text='V1.6：牌九取消每玩家高频轮询，改为私有Realtime事件、增量更新与单一数据库Cron；大厅和房间快照纯读取；关闭牌九即销毁iframe和后台任务；所有资金与私牌仍由事务RPC权威处理。',
    updated_at=now()
where singleton_id=1;

insert into public.jiuxiao_app_release_control(singleton_id,release_name,cache_epoch,notice_text,updated_at)
select 1,'V1.6 CACHE44',44,'V1.6牌九事件驱动、数据库统一推进与主游戏资源隔离发布。',now()
where not exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1);

notify pgrst,'reload schema';
commit;
