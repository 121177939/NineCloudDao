-- 九霄问道 V1.0 FIX3 CACHE33 正式发布门禁
begin;

do $$
begin
  if to_regprocedure('public.bcombat01_world_event_story_fix3(jsonb,jsonb,uuid,integer,bigint,jsonb)') is null then
    raise exception 'V1_FIX3_REQUIRED:BATTLE_STORY_FUNCTION_MISSING';
  end if;
  if not exists(select 1 from pg_trigger where tgname='trg_bcombat01_refresh_world_event_fix3' and not tgisinternal) then
    raise exception 'V1_FIX3_REQUIRED:BATTLE_STORY_TRIGGER_MISSING';
  end if;
end $$;

update public.jiuxiao_app_release_control
set release_name='V1.0 FIX3 CACHE33',
    cache_epoch=greatest(cache_epoch,33),
    notice_text='V1.0 FIX3：挑战战报采用紧凑左右对阵栏、扩大逐回合显示区并缩小底部控制区；九霄界闻新增挑战关系、兵刃、胜负与修为损失的修仙化趣味文案。',
    updated_at=now()
where singleton_id=1;

insert into public.jiuxiao_app_release_control(singleton_id,release_name,cache_epoch,notice_text,updated_at)
select 1,'V1.0 FIX3 CACHE33',33,
       'V1.0 FIX3：挑战战报采用紧凑左右对阵栏、扩大逐回合显示区并缩小底部控制区；九霄界闻新增挑战关系、兵刃、胜负与修为损失的修仙化趣味文案。',now()
where not exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1);

notify pgrst,'reload schema';
commit;
