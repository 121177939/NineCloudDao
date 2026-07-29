-- 九霄问道 V0.15.5 FIX1 CACHE27 正式升级
-- 可直接从 CACHE25 升级，不要求先执行 CACHE26。
-- 仅更新客户端发布门禁，强制旧 PWA 载入洞府视觉修正版、洞府真实库存界面与元神动画页。
-- 不新增表、字段、RPC、触发器或 RLS；战斗属性数值仍统一显示“接入中”。

begin;

do $$
begin
  if to_regclass('public.jiuxiao_app_release_control') is null then
    raise exception 'V0155_FIX1_REQUIRED:jiuxiao_app_release_control';
  end if;
end $$;

update public.jiuxiao_app_release_control
set release_name = 'V0.15.5 FIX1 CACHE27',
    cache_epoch = greatest(cache_epoch, 27),
    notice_text = 'V0.15.5 FIX1：洞府主景改为幽静洞窟、灵脉暗流、石台坐镇与仙府隐修风格；保留洞府真实库存与元神动画，战斗属性暂显示接入中。',
    updated_at = now()
where singleton_id = 1;

insert into public.jiuxiao_app_release_control(singleton_id, release_name, cache_epoch, notice_text, updated_at)
select 1,
       'V0.15.5 FIX1 CACHE27',
       27,
       'V0.15.5 FIX1：洞府主景改为幽静洞窟、灵脉暗流、石台坐镇与仙府隐修风格；保留洞府真实库存与元神动画，战斗属性暂显示接入中。',
       now()
where not exists (
  select 1 from public.jiuxiao_app_release_control where singleton_id = 1
);

commit;
