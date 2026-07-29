-- 九霄问道 V0.15.5 CACHE26 正式升级
-- 仅更新客户端发布门禁，以强制旧 PWA 载入洞府真实界面与元神动画页。
-- 不新增表、字段、RPC、RLS；战斗属性数值仍显示“接入中”。

begin;

do $$
begin
  if to_regclass('public.jiuxiao_app_release_control') is null then
    raise exception 'V0155_REQUIRED:jiuxiao_app_release_control';
  end if;
end $$;

update public.jiuxiao_app_release_control
set release_name = 'V0.15.5 CACHE26',
    cache_epoch = greatest(cache_epoch, 26),
    notice_text = 'V0.15.5：接入B-CAVE01洞府真实界面与库存入格，新增元神导航及功法运转动画；战斗属性数值暂显示接入中。',
    updated_at = now()
where singleton_id = 1;

insert into public.jiuxiao_app_release_control(singleton_id, release_name, cache_epoch, notice_text, updated_at)
select 1, 'V0.15.5 CACHE26', 26,
       'V0.15.5：接入B-CAVE01洞府真实界面与库存入格，新增元神导航及功法运转动画；战斗属性数值暂显示接入中。', now()
where not exists (
  select 1 from public.jiuxiao_app_release_control where singleton_id = 1
);

commit;
