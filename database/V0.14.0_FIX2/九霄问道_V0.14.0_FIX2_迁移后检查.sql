-- 《九霄问道》Web Alpha V0.14.0 FIX2 部署检查。
-- FIX2：配套修复 world_event_publish_v0140 直接调用的参数类型解析问题。
with checks(name, ok, detail) as (
  values
    ('jiuxiao_world_event_settings_table', to_regclass('public.jiuxiao_world_event_settings') is not null, '配置表存在'),
    ('jiuxiao_world_events_table', to_regclass('public.jiuxiao_world_events') is not null, '界闻表存在'),
    ('get_world_events_rpc', to_regprocedure('public.get_world_events_v1(integer)') is not null, '只读RPC存在'),
    ('publish_helper_private', not has_function_privilege('authenticated', 'public.world_event_publish_v0140(uuid,integer,text,smallint,uuid,text,text,text,text,text,jsonb,boolean,timestamptz)', 'execute'), '普通玩家不能直接发布'),
    ('feed_rpc_authenticated', has_function_privilege('authenticated', 'public.get_world_events_v1(integer)', 'execute'), '认证玩家可读取'),
    ('admin_rpc_not_authenticated', not has_function_privilege('authenticated', 'public.admin_publish_account_erasure_v1(text,text,text,text)', 'execute'), '普通玩家不能调用后台裁决'),
    ('breakthrough_trigger', exists(select 1 from pg_trigger where tgname='trg_world_event_breakthrough_v0140' and not tgisinternal), '突破触发器存在'),
    ('opportunity_trigger', exists(select 1 from pg_trigger where tgname='trg_world_event_opportunity_v0140' and not tgisinternal), '机缘触发器存在'),
    ('house_trigger', exists(select 1 from pg_trigger where tgname='trg_world_event_house_game_v0140' and not tgisinternal), '大堂赌局触发器存在'),
    ('duel_trigger', exists(select 1 from pg_trigger where tgname='trg_world_event_duel_v0140' and not tgisinternal), '雅间赌契触发器存在'),
    ('draw_trigger', exists(select 1 from pg_trigger where tgname='trg_world_event_casino_draw_v0140' and not tgisinternal), '造化池触发器存在'),
    ('rls_jiuxiao_world_events', coalesce((select relrowsecurity from pg_class where oid=to_regclass('public.jiuxiao_world_events')), false), 'jiuxiao_world_events启用RLS'),
    ('unique_source', exists(select 1 from pg_constraint where conname='jiuxiao_world_events_source_unique' and conrelid=to_regclass('public.jiuxiao_world_events')), '来源幂等约束存在'),
    ('opening_notice', exists(select 1 from public.jiuxiao_world_events where source_table='system' and source_key='v0140-world-feed-open'), '启用公告存在')
)
select name, ok, detail from checks order by name;

do $$
begin
  if exists (
    with checks(ok) as (
      values
        (to_regclass('public.jiuxiao_world_event_settings') is not null),
        (to_regclass('public.jiuxiao_world_events') is not null),
        (to_regprocedure('public.get_world_events_v1(integer)') is not null),
        (exists(select 1 from pg_trigger where tgname='trg_world_event_breakthrough_v0140' and not tgisinternal)),
        (exists(select 1 from pg_trigger where tgname='trg_world_event_opportunity_v0140' and not tgisinternal)),
        (exists(select 1 from pg_trigger where tgname='trg_world_event_house_game_v0140' and not tgisinternal)),
        (exists(select 1 from pg_trigger where tgname='trg_world_event_duel_v0140' and not tgisinternal)),
        (exists(select 1 from pg_trigger where tgname='trg_world_event_casino_draw_v0140' and not tgisinternal))
    ) select 1 from checks where not ok
  ) then
    raise exception 'V0140_CHECK_FAILED';
  end if;
end
$$;
