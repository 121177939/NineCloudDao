-- V0.14.0 九霄界闻数据审计（只读）。
-- FIX2：配套修复 world_event_publish_v0140 直接调用的参数类型解析问题。
select 'total_events' as metric, count(*)::bigint as value from public.jiuxiao_world_events
union all
select 'public_events', count(*) from public.jiuxiao_world_events where is_public
union all
select 'duplicate_sources', count(*) from (
  select source_table, source_key, event_type
  from public.jiuxiao_world_events
  group by source_table, source_key, event_type
  having count(*) > 1
) d
union all
select 'invalid_empty_content', count(*) from public.jiuxiao_world_events where btrim(title)='' or btrim(content)=''
union all
select 'expired_visible', count(*) from public.jiuxiao_world_events where expires_at <= now() and is_public;

select event_type, count(*) as event_count, max(created_at) as latest_at
from public.jiuxiao_world_events
group by event_type
order by latest_at desc;
