-- 《九霄问道》Web Alpha V0.14.0 FIX2
-- FIX2：配套修复 world_event_publish_v0140 直接调用的参数类型解析问题。
-- FIX2使用独立表名，不修改数据库中已有的 public.world_events。
-- 市坊门户与九霄界闻：只读前置检查。
-- 执行顺序：本文件 -> 主迁移 -> check -> data_audit。

do $$
declare
  v_missing text[] := array[]::text[];
begin
  if to_regclass('public.player_characters') is null then v_missing := array_append(v_missing, 'player_characters'); end if;
  if to_regclass('public.game_worlds') is null then v_missing := array_append(v_missing, 'game_worlds'); end if;
  if to_regclass('public.cultivation_records') is null then v_missing := array_append(v_missing, 'cultivation_records'); end if;
  if to_regclass('public.opportunity_v3_results') is null then v_missing := array_append(v_missing, 'opportunity_v3_results'); end if;
  if to_regclass('public.casino_house_games') is null then v_missing := array_append(v_missing, 'casino_house_games'); end if;
  if to_regclass('public.casino_duels') is null then v_missing := array_append(v_missing, 'casino_duels'); end if;
  if to_regclass('public.casino_draws') is null then v_missing := array_append(v_missing, 'casino_draws'); end if;
  if to_regprocedure('public.attempt_breakthrough_v1()') is null then v_missing := array_append(v_missing, 'attempt_breakthrough_v1()'); end if;
  if to_regprocedure('public.get_market_v1()') is null then v_missing := array_append(v_missing, 'get_market_v1()'); end if;
  if array_length(v_missing, 1) is not null then
    raise exception 'V0140_PRECHECK_MISSING:%', array_to_string(v_missing, ',');
  end if;
end
$$;

select
  'V0.14.0 precheck passed' as status,
  current_database() as database_name,
  now() as checked_at;


select
  case when to_regclass('public.world_events') is null
       then '未发现旧 world_events 表'
       else '发现旧 world_events 表；FIX2 将保留它并使用 jiuxiao_world_events'
  end as compatibility_note,
  to_regclass('public.world_events') as existing_world_events,
  to_regclass('public.world_event_settings') as existing_world_event_settings;
