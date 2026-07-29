-- 九霄问道 V1.0 FIX2 CACHE32 正式发布门禁
-- 本次为前端交互与榜单隐私显示调整，不新增表、字段、RPC、触发器或RLS。
begin;

do $$
begin
  if to_regprocedure('public.get_battle_power_ranking_bcombat01(integer,integer)') is null then
    raise exception 'V1_FIX2_REQUIRED:BATTLE_RANKING_RPC_MISSING';
  end if;
  if to_regprocedure('public.get_battle_challenge_preview_bcombat01(uuid)') is null then
    raise exception 'V1_FIX2_REQUIRED:BATTLE_PREVIEW_RPC_MISSING';
  end if;
  if to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)') is null then
    raise exception 'V1_FIX2_REQUIRED:BATTLE_CHALLENGE_RPC_MISSING';
  end if;
end $$;

update public.jiuxiao_app_release_control
set release_name='V1.0 FIX2 CACHE32',
    cache_epoch=greatest(cache_epoch,32),
    notice_text='V1.0 FIX2：挑战过程与结果改为独立战报弹窗；战力榜及挑战预览仅显示姓名、等级、战力和五行；三类排行榜取消独立榜首卡片。',
    updated_at=now()
where singleton_id=1;

insert into public.jiuxiao_app_release_control(singleton_id,release_name,cache_epoch,notice_text,updated_at)
select 1,'V1.0 FIX2 CACHE32',32,
       'V1.0 FIX2：挑战过程与结果改为独立战报弹窗；战力榜及挑战预览仅显示姓名、等级、战力和五行；三类排行榜取消独立榜首卡片。',now()
where not exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1);

notify pgrst,'reload schema';
commit;
