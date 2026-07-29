-- 九霄问道 V1.0 FIX1 CACHE31 正式发布门禁
-- 在挑战兼容修复SQL与前端部署完成后执行。
begin;

do $$
begin
  if to_regprocedure('public.world_event_publish_v0140(uuid,integer,text,integer,uuid,text,text,text,text,text,jsonb,boolean,timestamptz)') is null then
    raise exception 'V1_FIX1_REQUIRED:CHALLENGE_COMPAT_NOT_READY';
  end if;
  if to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)') is null then
    raise exception 'V1_FIX1_REQUIRED:BATTLE_CHALLENGE_RPC_MISSING';
  end if;
end $$;

update public.jiuxiao_app_release_control
set release_name='V1.0 FIX1 CACHE31',
    cache_epoch=greatest(cache_epoch,31),
    notice_text='V1.0 FIX1：挑战战报发布兼容修复；角色栏显示灵根五行；元神主景压缩10%；洞府储物恢复6×6格。',
    updated_at=now()
where singleton_id=1;

insert into public.jiuxiao_app_release_control(singleton_id,release_name,cache_epoch,notice_text,updated_at)
select 1,'V1.0 FIX1 CACHE31',31,
       'V1.0 FIX1：挑战战报发布兼容修复；角色栏显示灵根五行；元神主景压缩10%；洞府储物恢复6×6格。',now()
where not exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1);

notify pgrst,'reload schema';
commit;
