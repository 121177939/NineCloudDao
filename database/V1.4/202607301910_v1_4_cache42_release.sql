-- 九霄问道 V1.4 CACHE42
-- 86：正式发布门禁
begin;

do $$
begin
  if to_regprocedure('public.delete_paigow_room_bpaigow01(uuid)') is null then raise exception 'V1_4_REQUIRED:delete_room_rpc';end if;
  if to_regprocedure('public.paigow_prepare_waiting_room_bpaigow01(uuid)') is null then raise exception 'V1_4_REQUIRED:prepare_tick';end if;
  if not exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='paigow_room_members_bpaigow01' and column_name='ready_deadline'
  ) then raise exception 'V1_4_REQUIRED:ready_deadline';end if;
  if not exists(
    select 1 from public.paigow_settings_bpaigow01
    where singleton_id=1 and ready_seconds=10 and auto_start_seconds=2 and small_multiplier_seconds=5
  ) then raise exception 'V1_4_REQUIRED:timing_settings';end if;
end
$$;

update public.jiuxiao_app_release_control
set release_name='V1.4 CACHE42',
    cache_epoch=greatest(cache_epoch,42),
    notice_text='V1.4：小牌九明牌仅本人可见；入座10秒未准备自动离桌；全员准备2秒自动开局；房主可删除未开局房间；新增结算灵石流特效。',
    updated_at=now()
where singleton_id=1;

insert into public.jiuxiao_app_release_control(singleton_id,release_name,cache_epoch,notice_text,updated_at)
select 1,'V1.4 CACHE42',42,'V1.4牌九准备流程、私密明牌、房间管理与结算特效发布。',now()
where not exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1);

notify pgrst,'reload schema';
commit;
