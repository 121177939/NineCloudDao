-- 九霄问道 V0.14.2
-- 九霄界闻严格按新消息置顶：任何新消息都必须顶掉旧消息，不再因置顶标记、事件类型或等级滞留在旧位置。
-- 前提：V0.14.0 FIX2/FIX3、V0.14.1主迁移及FIX2、FIX3、FIX4、FIX5、FIX6、FIX7、FIX7A已部署。
-- 本脚本只修改九霄界闻排序、拉取字段、索引与发布缓存版本，不修改突破、赌坊、造化池或角色数值。

begin;

-- 1. 前置检查。
do $$
begin
  if to_regclass('public.jiuxiao_world_events') is null then
    raise exception 'V0142_REQUIRES_JIUXIAO_WORLD_EVENTS';
  end if;
  if to_regclass('public.jiuxiao_world_event_settings') is null then
    raise exception 'V0142_REQUIRES_JIUXIAO_WORLD_EVENT_SETTINGS';
  end if;
  if to_regprocedure('public.get_world_events_v1(integer)') is null then
    raise exception 'V0142_REQUIRES_GET_WORLD_EVENTS_V1';
  end if;
end;
$$;

-- 2. 增加严格单调递增的消息序号。
-- created_at可能在高并发时相同；feed_sequence保证后插入的消息一定排在前面。
create sequence if not exists public.jiuxiao_world_events_feed_sequence_seq as bigint;

alter table public.jiuxiao_world_events
  add column if not exists feed_sequence bigint;

alter sequence public.jiuxiao_world_events_feed_sequence_seq
  owned by public.jiuxiao_world_events.feed_sequence;

alter table public.jiuxiao_world_events
  alter column feed_sequence
  set default nextval('public.jiuxiao_world_events_feed_sequence_seq'::regclass);

-- 仅为旧数据补序号：按旧消息时间从早到晚分配，越新的旧消息序号越大。
with existing_max as (
  select coalesce(max(feed_sequence), 0)::bigint as max_sequence
  from public.jiuxiao_world_events
), missing_rows as (
  select e.id,
         row_number() over(order by e.created_at asc, e.id asc)::bigint as row_no
  from public.jiuxiao_world_events e
  where e.feed_sequence is null
)
update public.jiuxiao_world_events e
set feed_sequence = existing_max.max_sequence + missing_rows.row_no
from existing_max, missing_rows
where e.id = missing_rows.id;

do $$
declare
  v_max bigint;
begin
  select max(feed_sequence) into v_max from public.jiuxiao_world_events;
  if v_max is null then
    perform setval('public.jiuxiao_world_events_feed_sequence_seq'::regclass, 1, false);
  else
    perform setval('public.jiuxiao_world_events_feed_sequence_seq'::regclass, v_max, true);
  end if;
end;
$$;

alter table public.jiuxiao_world_events
  alter column feed_sequence set not null;

comment on column public.jiuxiao_world_events.feed_sequence is
  'V0.14.2：九霄界闻严格消息序号。新插入消息序号更大，查询只按此字段倒序。';

-- 3. 替换旧的“置顶优先”索引，改成严格新消息索引。
drop index if exists public.jiuxiao_world_events_public_feed_idx;

create index jiuxiao_world_events_public_feed_idx
  on public.jiuxiao_world_events(is_public, feed_sequence desc);

create unique index if not exists jiuxiao_world_events_feed_sequence_uidx
  on public.jiuxiao_world_events(feed_sequence);

create index if not exists jiuxiao_world_events_world_feed_sequence_idx
  on public.jiuxiao_world_events(world_id, feed_sequence desc)
  where is_public;

-- 4. 公开RPC严格按feed_sequence倒序。
-- is_pinned字段仅保留为历史/样式元数据，不再拥有排序优先权。
create or replace function public.get_world_events_v1(p_limit integer default 30)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_character_id uuid;
  v_world_id uuid;
  v_limit integer;
  v_enabled boolean := true;
  v_max integer := 50;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED'; end if;

  select pc.id, pc.world_id
    into v_character_id, v_world_id
  from public.player_characters pc
  where pc.user_id = v_user_id
    and pc.status in ('active', 'secluded', 'missing')
  order by pc.created_at desc
  limit 1;

  if v_character_id is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;

  select s.enabled, s.max_feed_rows
    into v_enabled, v_max
  from public.jiuxiao_world_event_settings s
  where s.singleton_id = 1;

  v_limit := greatest(1, least(coalesce(v_max, 50), coalesce(p_limit, 30)));

  return jsonb_build_object(
    'status', case when coalesce(v_enabled, true) then 'active' else 'disabled' end,
    'title', '九霄界闻',
    'subtitle', '天道传音',
    'sort_mode', 'strict_newest_first',
    'entries', coalesce((
      select jsonb_agg(x.obj order by x.feed_sequence desc)
      from (
        select e.feed_sequence,
          jsonb_build_object(
            'id', e.id,
            'feed_sequence', e.feed_sequence,
            'event_type', e.event_type,
            'event_level', e.event_level,
            'actor_name', e.actor_name_snapshot,
            'title', e.title,
            'content', e.content,
            'world_year', e.world_year,
            'is_pinned', e.is_pinned,
            'created_at', e.created_at,
            'seconds_ago', greatest(0, floor(extract(epoch from (now() - e.created_at)))::bigint)
          ) obj
        from public.jiuxiao_world_events e
        where e.is_public
          and (e.world_id is null or e.world_id = v_world_id)
          and (e.expires_at is null or e.expires_at > now())
        order by e.feed_sequence desc
        limit v_limit
      ) x
    ), '[]'::jsonb),
    'fetched_at', now()
  );
end;
$$;

revoke all on function public.get_world_events_v1(integer) from public, anon;
grant execute on function public.get_world_events_v1(integer) to authenticated;

comment on function public.get_world_events_v1(integer) is
  'V0.14.2：九霄界闻严格按feed_sequence倒序；任何新消息均顶掉旧消息，置顶标记不参与排序。';

-- 5. 提升CACHE6，通知已安装更新守卫的客户端刷新资源。
do $$
begin
  if to_regclass('public.jiuxiao_app_release_control') is not null then
    update public.jiuxiao_app_release_control
    set cache_epoch = greatest(coalesce(cache_epoch, 0) + 1, 6),
        release_name = 'V0.14.2 CACHE6',
        updated_at = now()
    where singleton_id = 1;
  end if;
end;
$$;

commit;

-- 6. 部署后自检：所有ok应为true。
with function_text as (
  select pg_get_functiondef('public.get_world_events_v1(integer)'::regprocedure) as definition
), checks(name, ok, detail) as (
  values
    ('world_events_table_exists',
      to_regclass('public.jiuxiao_world_events') is not null,
      '九霄界闻表存在'),
    ('feed_sequence_column_exists',
      exists(
        select 1 from information_schema.columns
        where table_schema='public' and table_name='jiuxiao_world_events' and column_name='feed_sequence'
      ),
      '严格消息序号字段存在'),
    ('feed_sequence_not_null',
      coalesce((
        select c.is_nullable='NO'
        from information_schema.columns c
        where c.table_schema='public' and c.table_name='jiuxiao_world_events' and c.column_name='feed_sequence'
      ), false),
      '消息序号不可为空'),
    ('feed_sequence_all_filled',
      not exists(select 1 from public.jiuxiao_world_events where feed_sequence is null),
      '历史消息序号已补齐'),
    ('feed_sequence_unique',
      not exists(
        select feed_sequence
        from public.jiuxiao_world_events
        group by feed_sequence
        having count(*) > 1
      ),
      '当前消息序号没有重复'),
    ('strict_feed_index_exists',
      exists(
        select 1 from pg_indexes
        where schemaname='public'
          and indexname='jiuxiao_world_events_public_feed_idx'
          and indexdef ilike '%feed_sequence%desc%'
      ),
      '严格新消息索引存在'),
    ('rpc_exists',
      to_regprocedure('public.get_world_events_v1(integer)') is not null,
      '界闻RPC存在'),
    ('rpc_uses_feed_sequence',
      coalesce((select definition ilike '%order by e.feed_sequence desc%' from function_text), false),
      'RPC使用严格消息序号倒序'),
    ('rpc_does_not_prioritize_pinned',
      coalesce((select definition not ilike '%order by e.is_pinned%' from function_text), false),
      '置顶标记不再参与排序'),
    ('rpc_returns_sort_mode',
      coalesce((select definition ilike '%strict_newest_first%' from function_text), false),
      'RPC标明严格新消息模式'),
    ('latest_sequence_is_maximum',
      coalesce((
        select feed_sequence = (select max(feed_sequence) from public.jiuxiao_world_events)
        from public.jiuxiao_world_events
        order by feed_sequence desc
        limit 1
      ), true),
      '首条消息序号为当前最大值'),
    ('release_control_cache6',
      case
        when to_regclass('public.jiuxiao_app_release_control') is null then true
        else coalesce((
          select release_name='V0.14.2 CACHE6' and cache_epoch>=6
          from public.jiuxiao_app_release_control
          where singleton_id=1
        ), false)
      end,
      '发布控制已提升到CACHE6')
)
select * from checks order by name;
