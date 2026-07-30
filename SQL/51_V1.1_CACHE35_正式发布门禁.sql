-- 九霄问道 V1.1 CACHE35 正式发布门禁
begin;
do $$
begin
  if to_regprocedure('public.bcombat01_world_event_story_v11(jsonb,jsonb,uuid,integer,bigint,jsonb)') is null then raise exception 'V1_1_REQUIRED:story';end if;
  if to_regprocedure('public.bcombat01_refresh_world_event_v11()') is null then raise exception 'V1_1_REQUIRED:event_refresh';end if;
  if not exists(select 1 from public.battle_challenge_settings_bcombat01 where singleton_id=1 and active_challenge_daily_limit=20 and challenge_cooldown_minutes=20 and higher_power_win_rate=0.005 and lower_power_win_rate=0.01) then raise exception 'V1_1_REQUIRED:rules';end if;
end$$;
update public.jiuxiao_app_release_control
set release_name='V1.1 CACHE35',cache_epoch=greatest(cache_epoch,35),
    notice_text='V1.1：战力榜高低战力可互相挑战；每日20次、每次冷却20分钟；低战力胜高战力转移败者阶段进度1%，其余0.5%，不掉段且修为严格等量转移；挑战界闻已改写到正确九霄界闻表。',updated_at=now()
where singleton_id=1;
insert into public.jiuxiao_app_release_control(singleton_id,release_name,cache_epoch,notice_text,updated_at)
select 1,'V1.1 CACHE35',35,'V1.1：战力挑战与九霄界闻修复。',now()
where not exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1);
notify pgrst,'reload schema';
commit;
