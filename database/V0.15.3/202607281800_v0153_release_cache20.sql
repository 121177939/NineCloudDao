-- 九霄问道 V0.15.3 CACHE20
-- 仅修复前端发布门禁与GitHub Pages构建；不重复修改功法、命格或突破数据。

begin;

update public.jiuxiao_app_release_control
set release_name = 'V0.15.3 CACHE20',
    cache_epoch = greatest(cache_epoch, 20),
    notice_text = 'V0.15.3：修复GitHub Pages构建门禁，保留V0.15.2命格、功法与突破保护规则。',
    updated_at = now()
where singleton_id = 1;

insert into public.jiuxiao_app_release_control(singleton_id, release_name, cache_epoch, notice_text, updated_at)
select 1, 'V0.15.3 CACHE20', 20,
       'V0.15.3：修复GitHub Pages构建门禁，保留V0.15.2命格、功法与突破保护规则。', now()
where not exists (
  select 1 from public.jiuxiao_app_release_control where singleton_id = 1
);

commit;

select release_name, cache_epoch, notice_text, updated_at
from public.jiuxiao_app_release_control
where singleton_id = 1;
