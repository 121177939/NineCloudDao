-- 九霄问道 · V2.1.1 CACHE112 · 数据库健康检查（只读）
-- 用途：上线前 / 上线后1小时 / 6小时 / 24小时 / 48小时执行并保存结果。
-- 安全：本文件只有SELECT，不DELETE、不UPDATE、不VACUUM、不TRUNCATE。

WITH cfg AS (
  SELECT to_jsonb(c) AS v FROM public.jiuxiao_auto_cleanup_config_v210 c WHERE singleton_id=1
),
sect_cfg AS (
  SELECT to_jsonb(c) AS v FROM public.sect_autonomy_settings_bsect06 c WHERE singleton_id=1
),
preview AS (
  SELECT public.preview_jiuxiao_auto_cleanup_v210() AS v
),
release AS (
  SELECT to_jsonb(r) AS v FROM public.jiuxiao_app_release_control r WHERE singleton_id=1
),
dbstats AS (
  SELECT jsonb_build_object(
    'stats_reset',stats_reset,
    'xact_commit',xact_commit,
    'xact_rollback',xact_rollback,
    'temp_files',temp_files,
    'temp_bytes',temp_bytes,
    'temp_size',pg_size_pretty(temp_bytes),
    'deadlocks',deadlocks,
    'blk_read_time_ms',blk_read_time,
    'blk_write_time_ms',blk_write_time
  ) AS v
  FROM pg_stat_database WHERE datname=current_database()
),
jobs AS (
  SELECT coalesce(jsonb_agg(jsonb_build_object(
    'jobid',jobid,'jobname',jobname,'schedule',schedule,'active',active,'command',command
  ) ORDER BY jobid),'[]'::jsonb) AS v
  FROM cron.job
),
top_tables AS (
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.total_bytes DESC),'[]'::jsonb) AS v
  FROM (
    SELECT n.nspname AS schema_name,c.relname AS table_name,
           pg_total_relation_size(c.oid) AS total_bytes,
           pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size,
           greatest(c.reltuples,0)::bigint AS estimated_rows
    FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE c.relkind='r' AND n.nspname IN('public','cron')
    ORDER BY pg_total_relation_size(c.oid) DESC
    LIMIT 10
  ) x
),
recent_runs AS (
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.started_at DESC),'[]'::jsonb) AS v
  FROM (
    SELECT id,started_at,finished_at,status,trigger_source,dry_run,batch_limit,
           database_size_before,database_size_after,deleted_rows,error_text
    FROM public.jiuxiao_cleanup_runs_v210
    ORDER BY started_at DESC LIMIT 20
  ) x
),
cleanup24 AS (
  SELECT jsonb_build_object(
    'run_count',count(*),
    'failed_count',count(*) FILTER(WHERE status='failed'),
    'last_started_at',max(started_at),
    'deleted_rows',coalesce(sum((
      SELECT coalesce(sum(CASE WHEN jsonb_typeof(e.value)='number' THEN (e.value::text)::bigint ELSE 0 END),0)
      FROM jsonb_each(r.deleted_rows) e
    )),0),
    'first_size_after',(
      SELECT database_size_after FROM public.jiuxiao_cleanup_runs_v210
      WHERE started_at>=clock_timestamp()-interval '24 hours' AND database_size_after IS NOT NULL
      ORDER BY started_at ASC LIMIT 1
    ),
    'last_size_after',(
      SELECT database_size_after FROM public.jiuxiao_cleanup_runs_v210
      WHERE started_at>=clock_timestamp()-interval '24 hours' AND database_size_after IS NOT NULL
      ORDER BY started_at DESC LIMIT 1
    )
  ) AS v
  FROM public.jiuxiao_cleanup_runs_v210 r
  WHERE started_at>=clock_timestamp()-interval '24 hours'
),
key_table_stats AS (
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.total_bytes DESC),'[]'::jsonb) AS v
  FROM (
    SELECT s.relname AS table_name,s.n_live_tup,s.n_dead_tup,s.last_autovacuum,s.last_autoanalyze,
           pg_total_relation_size(format('public.%I',s.relname)::regclass) AS total_bytes,
           pg_size_pretty(pg_total_relation_size(format('public.%I',s.relname)::regclass)) AS total_size
    FROM pg_stat_user_tables s
    WHERE s.relname IN(
      'sect_settlement_requests_bsect01','sect_action_requests_bsect02','sect_action_requests_bsect03',
      'sect_action_requests_bsect04','sect_action_requests_bsect06','secret_realm_requests_bsecretrealm01',
      'secret_realm_events_bsecretrealm01','opportunity_v3_results','opportunity_v4_settlement_batches',
      'jiuxiao_world_events','character_cultivation_effects','sect_event_history_bsect06'
    )
  ) x
)
SELECT jsonb_pretty(jsonb_build_object(
  'checked_at',clock_timestamp(),
  'database',current_database(),
  'database_size_bytes',pg_database_size(current_database()),
  'database_size',pg_size_pretty(pg_database_size(current_database())),
  'release',(SELECT v FROM release),
  'cleanup_config',(SELECT v FROM cfg),
  'sect_cleanup_config',(SELECT v FROM sect_cfg),
  'safe_cleanup_preview',(SELECT v FROM preview),
  'last_24h_cleanup',(SELECT v FROM cleanup24),
  'database_stats',(SELECT v FROM dbstats),
  'cron_jobs',(SELECT v FROM jobs),
  'top_10_tables',(SELECT v FROM top_tables),
  'key_table_stats',(SELECT v FROM key_table_stats),
  'recent_cleanup_runs',(SELECT v FROM recent_runs),
  'checks',jsonb_build_object(
    'global_cleanup_job_exactly_one',(SELECT count(*)=1 FROM cron.job WHERE jobname='jiuxiao-auto-cleanup-v210'),
    'global_cleanup_schedule_ok',(SELECT count(*)=1 FROM cron.job WHERE jobname='jiuxiao-auto-cleanup-v210' AND active AND schedule='25 */6 * * *'),
    'bsect06_job_exactly_one',(SELECT count(*)=1 FROM cron.job WHERE jobname='jiuxiao_bsect06_daily_maintenance'),
    'bsect06_schedule_ok',(SELECT count(*)=1 FROM cron.job WHERE jobname='jiuxiao_bsect06_daily_maintenance' AND active AND schedule='35 */6 * * *'),
    'forbidden_paigow_tick_active',EXISTS(SELECT 1 FROM cron.job WHERE active AND command ILIKE '%paigow_tick_due_rooms_bpaigow01%'),
    'dbcap03_policy',(SELECT v->>'policy' FROM preview)
  )
)) AS database_health_json;
