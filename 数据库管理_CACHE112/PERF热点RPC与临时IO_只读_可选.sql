-- 九霄问道 · PERF2 · 热点RPC/临时I/O检查（只读，可选）
-- 只有数据库已启用 pg_stat_statements 时执行。若提示 relation pg_stat_statements does not exist，直接跳过本文件即可。
WITH q AS (
  SELECT queryid,calls,total_exec_time,mean_exec_time,rows,
         shared_blks_hit,shared_blks_read,temp_blks_read,temp_blks_written,
         left(regexp_replace(query,E'\\s+',' ','g'),1000) AS query_text
  FROM pg_stat_statements
),
x AS (
  SELECT q.*,(temp_blks_read+temp_blks_written)*current_setting('block_size')::bigint AS temp_bytes_est
  FROM q
),
hot AS (
  SELECT * FROM x
  WHERE query_text ILIKE ANY(ARRAY[
    '%enforce_single_game_session_v1%','%settle_character_time_v1%','%claim_cultivation_v1%',
    '%settle_opportunity_v4%','%claim_next_divine_notice_v1%','%get_world_events_v1%','%get_market_v1%',
    '%paigow_tick_due_rooms_bpaigow01%'
  ])
)
SELECT jsonb_pretty(jsonb_build_object(
  'checked_at',clock_timestamp(),
  'database_size',pg_size_pretty(pg_database_size(current_database())),
  'hot_rpc',coalesce((SELECT jsonb_agg(to_jsonb(s) ORDER BY calls DESC) FROM hot s),'[]'::jsonb),
  'top_temp_io',coalesce((
    SELECT jsonb_agg(to_jsonb(s) ORDER BY temp_bytes_est DESC)
    FROM (SELECT *,pg_size_pretty(temp_bytes_est) AS temp_size_est FROM x WHERE temp_bytes_est>0 ORDER BY temp_bytes_est DESC LIMIT 20)s
  ),'[]'::jsonb),
  'top_total_time',coalesce((
    SELECT jsonb_agg(to_jsonb(s) ORDER BY total_exec_time DESC)
    FROM (SELECT * FROM x ORDER BY total_exec_time DESC LIMIT 20)s
  ),'[]'::jsonb)
)) AS perf_health_json;
