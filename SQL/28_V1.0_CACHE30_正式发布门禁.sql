-- 九霄问道 V1.0 CACHE30 正式发布门禁
-- 在 B-COMBAT01 主迁移成功后执行，随后运行部署后检查。
begin;

do $$
begin
  if to_regclass('public.jiuxiao_app_release_control') is null then
    raise exception 'V1_REQUIRED:jiuxiao_app_release_control';
  end if;
  if to_regprocedure('public.get_my_battle_snapshot_v1()') is null
     or to_regprocedure('public.get_battle_power_ranking_bcombat01(integer,integer)') is null
     or to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)') is null then
    raise exception 'V1_REQUIRED:B_COMBAT01_NOT_READY';
  end if;
end $$;

update public.jiuxiao_app_release_control
set release_name = 'V1.0 CACHE30',
    cache_epoch = greatest(cache_epoch, 30),
    notice_text = 'V1.0：五行战斗、战力榜与越阶挑战正式开放；元神显示服务端权威四属性，洞府升级为洞天幽居并展示未研习功法与物品类型。',
    updated_at = now()
where singleton_id = 1;

insert into public.jiuxiao_app_release_control(singleton_id, release_name, cache_epoch, notice_text, updated_at)
select 1,
       'V1.0 CACHE30',
       30,
       'V1.0：五行战斗、战力榜与越阶挑战正式开放；元神显示服务端权威四属性，洞府升级为洞天幽居并展示未研习功法与物品类型。',
       now()
where not exists (select 1 from public.jiuxiao_app_release_control where singleton_id=1);

notify pgrst,'reload schema';
commit;
