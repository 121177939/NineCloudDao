-- 九霄问道 Web Alpha V0.14.1 FIX4 CACHE1
-- 客户端强制缓存更新控制。此SQL不能直接删除浏览器缓存；它为已部署CACHE1更新守卫提供服务器版本指令。
-- 正常执行一次即可。以后发布新前端时，将cache_epoch加1。

begin;

create table if not exists public.jiuxiao_app_release_control (
  singleton_id smallint not null,
  release_name text not null default 'V0.14.1 FIX4 CACHE1',
  cache_epoch bigint not null default 1,
  notice_text text not null default '发现游戏资源更新，正在刷新。',
  updated_at timestamptz not null default now()
);

alter table public.jiuxiao_app_release_control
  add column if not exists singleton_id smallint,
  add column if not exists release_name text,
  add column if not exists cache_epoch bigint,
  add column if not exists notice_text text,
  add column if not exists updated_at timestamptz;

update public.jiuxiao_app_release_control
set singleton_id = 1
where singleton_id is null;

update public.jiuxiao_app_release_control
set
  release_name = coalesce(release_name, 'V0.14.1 FIX4 CACHE1'),
  cache_epoch = greatest(coalesce(cache_epoch, 1), 1),
  notice_text = coalesce(notice_text, '发现游戏资源更新，正在刷新。'),
  updated_at = coalesce(updated_at, now());

-- 只保留单例控制行；若此前误建多行，保留最近更新的一行。
with ranked as (
  select ctid, row_number() over(order by updated_at desc nulls last, ctid desc) as rn
  from public.jiuxiao_app_release_control
)
delete from public.jiuxiao_app_release_control t
using ranked r
where t.ctid = r.ctid and r.rn > 1;

update public.jiuxiao_app_release_control
set singleton_id = 1
where singleton_id <> 1;

insert into public.jiuxiao_app_release_control(
  singleton_id, release_name, cache_epoch, notice_text, updated_at
)
select 1, 'V0.14.1 FIX4 CACHE1', 1, '发现游戏资源更新，正在刷新。', now()
where not exists(select 1 from public.jiuxiao_app_release_control);

alter table public.jiuxiao_app_release_control
  alter column singleton_id set not null,
  alter column release_name set not null,
  alter column cache_epoch set not null,
  alter column notice_text set not null,
  alter column updated_at set not null;

alter table public.jiuxiao_app_release_control
  alter column release_name set default 'V0.14.1 FIX4 CACHE1',
  alter column cache_epoch set default 1,
  alter column notice_text set default '发现游戏资源更新，正在刷新。',
  alter column updated_at set default now();

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.jiuxiao_app_release_control'::regclass
      and contype = 'p'
  ) then
    alter table public.jiuxiao_app_release_control
      add constraint jiuxiao_app_release_control_pkey primary key(singleton_id);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.jiuxiao_app_release_control'::regclass
      and conname = 'jiuxiao_app_release_control_singleton_check'
  ) then
    alter table public.jiuxiao_app_release_control
      add constraint jiuxiao_app_release_control_singleton_check check(singleton_id = 1);
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.jiuxiao_app_release_control'::regclass
      and conname = 'jiuxiao_app_release_control_epoch_check'
  ) then
    alter table public.jiuxiao_app_release_control
      add constraint jiuxiao_app_release_control_epoch_check check(cache_epoch > 0);
  end if;
end
$$;

insert into public.jiuxiao_app_release_control(
  singleton_id, release_name, cache_epoch, notice_text, updated_at
)
values (
  1,
  'V0.14.1 FIX4 CACHE1',
  1,
  '发现游戏资源更新，正在刷新。',
  now()
)
on conflict(singleton_id) do update
set
  release_name = excluded.release_name,
  cache_epoch = greatest(public.jiuxiao_app_release_control.cache_epoch, excluded.cache_epoch),
  notice_text = excluded.notice_text,
  updated_at = now();

alter table public.jiuxiao_app_release_control enable row level security;

revoke all on table public.jiuxiao_app_release_control from public, anon, authenticated;

create or replace function public.get_jiuxiao_app_release_control_v1()
returns jsonb
language sql
stable
security definer
set search_path = pg_catalog, public, pg_temp
as $$
  select jsonb_build_object(
    'release_name', release_name,
    'cache_epoch', cache_epoch,
    'notice_text', notice_text,
    'updated_at', updated_at
  )
  from public.jiuxiao_app_release_control
  where singleton_id = 1;
$$;

revoke all on function public.get_jiuxiao_app_release_control_v1() from public;
grant execute on function public.get_jiuxiao_app_release_control_v1() to anon, authenticated;

comment on table public.jiuxiao_app_release_control is
  '九霄问道客户端发布与缓存代号单例表。SQL只发布更新指令，缓存清理由前端更新守卫执行。';
comment on function public.get_jiuxiao_app_release_control_v1() is
  '匿名只读返回客户端release_name与cache_epoch。';

notify pgrst, 'reload schema';

commit;

-- 自检：全部ok应为true。
select 'release_control_table'::text as check_name,
       to_regclass('public.jiuxiao_app_release_control') is not null as ok,
       '缓存版本控制表存在'::text as detail
union all
select 'release_control_singleton',
       (select count(*) = 1 and min(singleton_id) = 1 from public.jiuxiao_app_release_control),
       '单例控制行存在'
union all
select 'release_control_epoch',
       (select cache_epoch >= 1 from public.jiuxiao_app_release_control where singleton_id = 1),
       'cache_epoch有效'
union all
select 'release_control_rpc',
       to_regprocedure('public.get_jiuxiao_app_release_control_v1()') is not null,
       '匿名只读RPC存在'
union all
select 'release_control_anon_execute',
       has_function_privilege('anon', 'public.get_jiuxiao_app_release_control_v1()', 'execute'),
       'anon可读取版本指令'
union all
select 'release_control_authenticated_execute',
       has_function_privilege('authenticated', 'public.get_jiuxiao_app_release_control_v1()', 'execute'),
       'authenticated可读取版本指令'
union all
select 'release_control_rls',
       (select relrowsecurity from pg_class where oid = 'public.jiuxiao_app_release_control'::regclass),
       '控制表启用RLS';

-- 以后发布新的前端资源后，用下面语句触发已安装CACHE1守卫的客户端强制刷新：
-- update public.jiuxiao_app_release_control
-- set cache_epoch = cache_epoch + 1,
--     release_name = '新的发布名称',
--     notice_text = '游戏资源已更新，正在重新加载。',
--     updated_at = now()
-- where singleton_id = 1;
