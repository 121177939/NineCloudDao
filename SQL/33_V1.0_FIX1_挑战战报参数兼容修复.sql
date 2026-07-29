-- 九霄问道 V1.0 FIX1：挑战战报发布参数兼容修复
-- 生产故障：挑战结算传入 integer 等级，既有发布器要求 smallint，导致整场挑战事务回滚。
-- 本文件增加私有 integer 兼容重载；不会修改历史界闻数据，也不会开放给 anon/authenticated 直接调用。
begin;

do $$
begin
  if to_regprocedure('public.world_event_publish_v0140(uuid,integer,text,smallint,uuid,text,text,text,text,text,jsonb,boolean,timestamptz)') is null then
    raise exception 'V1_FIX1_REQUIRED:WORLD_EVENT_PUBLISHER_MISSING';
  end if;
  if to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)') is null then
    raise exception 'V1_FIX1_REQUIRED:BATTLE_CHALLENGE_RPC_MISSING';
  end if;
end $$;

create or replace function public.world_event_publish_v0140(
  p_world_id uuid,
  p_world_year integer,
  p_event_type text,
  p_event_level integer,
  p_actor_character_id uuid,
  p_actor_name_snapshot text,
  p_title text,
  p_content text,
  p_source_table text,
  p_source_key text,
  p_metadata jsonb default '{}'::jsonb,
  p_is_pinned boolean default false,
  p_expires_at timestamptz default null
)
returns uuid
language sql
security definer
set search_path = public, pg_temp
as $$
  select public.world_event_publish_v0140(
    p_world_id,
    p_world_year,
    p_event_type,
    greatest(-32768,least(32767,coalesce(p_event_level,1)))::smallint,
    p_actor_character_id,
    p_actor_name_snapshot,
    p_title,
    p_content,
    p_source_table,
    p_source_key,
    coalesce(p_metadata,'{}'::jsonb),
    coalesce(p_is_pinned,false),
    p_expires_at
  );
$$;

revoke all on function public.world_event_publish_v0140(uuid,integer,text,integer,uuid,text,text,text,text,text,jsonb,boolean,timestamptz) from public,anon,authenticated;

notify pgrst,'reload schema';
commit;
