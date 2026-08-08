-- 《九霄问道》SQL242
-- V2.1.1 CACHE112 / ADMIN9 R24
-- 数据库健康监控 + 低频健康快照
-- 目标：把原先需要手动跑只读SQL查看的容量趋势、rollback、deadlock、temp I/O、Cron、Top表、热点SQL集中到GM。
-- 安全：不直接DELETE业务表；不修改SQL241的DBCAP03治理策略；不修改游戏CACHE版本。

BEGIN;

DO $precheck$
DECLARE v_n integer;
BEGIN
  IF to_regprocedure('public.admin_whoami_v1()') IS NULL THEN
    RAISE EXCEPTION 'SQL242_PRECHECK_ADMIN_WHOAMI_MISSING';
  END IF;
  IF to_regprocedure('public.admin9_get_database_maintenance_v210()') IS NULL THEN
    RAISE EXCEPTION 'SQL242_PRECHECK_ADMIN9_DATABASE_RPC_MISSING';
  END IF;
  IF to_regprocedure('public.preview_jiuxiao_auto_cleanup_v210()') IS NULL THEN
    RAISE EXCEPTION 'SQL242_PRECHECK_DBCAP03_PREVIEW_MISSING';
  END IF;
  IF to_regclass('public.jiuxiao_auto_cleanup_config_v210') IS NULL
     OR to_regclass('public.jiuxiao_cleanup_runs_v210') IS NULL
     OR to_regclass('public.jiuxiao_app_release_control') IS NULL
     OR to_regclass('cron.job') IS NULL THEN
    RAISE EXCEPTION 'SQL242_PRECHECK_REQUIRED_RELATION_MISSING';
  END IF;

  IF coalesce(public.preview_jiuxiao_auto_cleanup_v210()->>'policy','') <> 'DBCAP03_ROLLING_TTL' THEN
    RAISE EXCEPTION 'SQL242_PRECHECK_DBCAP03_POLICY_NOT_ACTIVE';
  END IF;

  SELECT count(*) INTO v_n FROM cron.job WHERE jobname='jiuxiao-auto-cleanup-v210';
  IF v_n<>1 THEN RAISE EXCEPTION 'SQL242_PRECHECK_GLOBAL_CLEANUP_JOB_COUNT:%',v_n; END IF;
  SELECT count(*) INTO v_n FROM cron.job WHERE jobname='jiuxiao_bsect06_daily_maintenance';
  IF v_n<>1 THEN RAISE EXCEPTION 'SQL242_PRECHECK_BSECT06_JOB_COUNT:%',v_n; END IF;

  IF EXISTS(SELECT 1 FROM cron.job WHERE active AND command ILIKE '%paigow_tick_due_rooms_bpaigow01%') THEN
    RAISE EXCEPTION 'SQL242_PRECHECK_FORBIDDEN_PAIGOW_TICK_ACTIVE';
  END IF;
END
$precheck$;

CREATE TABLE IF NOT EXISTS public.jiuxiao_db_health_snapshots_v242 (
  id bigserial PRIMARY KEY,
  checked_at timestamptz NOT NULL DEFAULT clock_timestamp(),
  checked_by uuid NULL,
  health_code text NOT NULL CHECK (health_code IN ('safe','warning','critical')),
  database_size_bytes bigint NOT NULL,
  xact_commit bigint NOT NULL DEFAULT 0,
  xact_rollback bigint NOT NULL DEFAULT 0,
  deadlocks bigint NOT NULL DEFAULT 0,
  temp_files bigint NOT NULL DEFAULT 0,
  temp_bytes bigint NOT NULL DEFAULT 0,
  stats_reset timestamptz NULL,
  release_name text NULL,
  cache_epoch integer NULL,
  policy text NULL,
  issues jsonb NOT NULL DEFAULT '[]'::jsonb,
  top_tables jsonb NOT NULL DEFAULT '[]'::jsonb,
  cron_status jsonb NOT NULL DEFAULT '{}'::jsonb,
  cleanup_status jsonb NOT NULL DEFAULT '{}'::jsonb,
  perf_hotspots jsonb NOT NULL DEFAULT '[]'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_jiuxiao_db_health_snapshots_v242_checked_at
  ON public.jiuxiao_db_health_snapshots_v242(checked_at DESC);

REVOKE ALL ON TABLE public.jiuxiao_db_health_snapshots_v242 FROM PUBLIC, anon, authenticated;
REVOKE ALL ON SEQUENCE public.jiuxiao_db_health_snapshots_v242_id_seq FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.admin9_get_database_health_v242(
  p_save_snapshot boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','cron','auth','pg_temp'
AS $function$
DECLARE
  v_now timestamptz := clock_timestamp();
  v_checked_by uuid := auth.uid();
  v_db_size bigint := pg_database_size(current_database());
  v_commit bigint := 0;
  v_rollback bigint := 0;
  v_deadlocks bigint := 0;
  v_temp_files bigint := 0;
  v_temp_bytes bigint := 0;
  v_stats_reset timestamptz;
  v_prev public.jiuxiao_db_health_snapshots_v242%rowtype;
  v_release_name text;
  v_cache_epoch integer;
  v_policy text;
  v_warning_mb integer := 350;
  v_critical_mb integer := 400;
  v_block_mb integer := 470;
  v_global_count integer := 0;
  v_global_active integer := 0;
  v_global_schedule text;
  v_bsect_count integer := 0;
  v_bsect_active integer := 0;
  v_bsect_schedule text;
  v_forbidden_tick boolean := false;
  v_latest_cleanup jsonb := '{}'::jsonb;
  v_issues jsonb := '[]'::jsonb;
  v_health text := 'safe';
  v_top_tables jsonb := '[]'::jsonb;
  v_cron jsonb := '{}'::jsonb;
  v_hotspots jsonb := '[]'::jsonb;
  v_pgss_schema text;
  v_comparisons jsonb := '{}'::jsonb;
  v_snapshot_id bigint;
  v_mb numeric;
  r record;
BEGIN
  -- 复用旧GM最高管理员接口作为权限门槛；失败会直接抛出。
  PERFORM public.admin_whoami_v1();

  SELECT s.xact_commit,s.xact_rollback,s.deadlocks,s.temp_files,s.temp_bytes,s.stats_reset
    INTO v_commit,v_rollback,v_deadlocks,v_temp_files,v_temp_bytes,v_stats_reset
  FROM pg_stat_database s
  WHERE s.datname=current_database();

  SELECT release_name,cache_epoch
    INTO v_release_name,v_cache_epoch
  FROM public.jiuxiao_app_release_control
  WHERE singleton_id=1;

  SELECT coalesce(p.preview->>'policy','')
    INTO v_policy
  FROM (SELECT public.preview_jiuxiao_auto_cleanup_v210() AS preview) p;

  SELECT coalesce(database_warning_mb,350),coalesce(database_critical_mb,400)
    INTO v_warning_mb,v_critical_mb
  FROM public.sect_autonomy_settings_bsect06
  WHERE singleton_id=1;

  SELECT coalesce(warning_mb,v_warning_mb),coalesce(critical_mb,v_critical_mb),coalesce(block_mb,470)
    INTO v_warning_mb,v_critical_mb,v_block_mb
  FROM public.jiuxiao_auto_cleanup_config_v210
  WHERE singleton_id=1;

  SELECT count(*),count(*) FILTER (WHERE active),min(schedule)
    INTO v_global_count,v_global_active,v_global_schedule
  FROM cron.job WHERE jobname='jiuxiao-auto-cleanup-v210';

  SELECT count(*),count(*) FILTER (WHERE active),min(schedule)
    INTO v_bsect_count,v_bsect_active,v_bsect_schedule
  FROM cron.job WHERE jobname='jiuxiao_bsect06_daily_maintenance';

  SELECT EXISTS(
    SELECT 1 FROM cron.job
    WHERE active AND command ILIKE '%paigow_tick_due_rooms_bpaigow01%'
  ) INTO v_forbidden_tick;

  v_cron := jsonb_build_object(
    'global_cleanup',jsonb_build_object('count',v_global_count,'active_count',v_global_active,'schedule',v_global_schedule,'expected','25 */6 * * *','ok',v_global_count=1 AND v_global_active=1 AND v_global_schedule='25 */6 * * *'),
    'bsect06',jsonb_build_object('count',v_bsect_count,'active_count',v_bsect_active,'schedule',v_bsect_schedule,'expected','35 */6 * * *','ok',v_bsect_count=1 AND v_bsect_active=1 AND v_bsect_schedule='35 */6 * * *'),
    'forbidden_paigow_tick_active',v_forbidden_tick
  );

  SELECT coalesce(to_jsonb(x),'{}'::jsonb) INTO v_latest_cleanup
  FROM (
    SELECT id,status,trigger_source,dry_run,batch_limit,database_size_before,database_size_after,
           deleted_rows,error_text,created_at,finished_at
    FROM public.jiuxiao_cleanup_runs_v210
    ORDER BY id DESC LIMIT 1
  ) x;
  v_latest_cleanup := coalesce(v_latest_cleanup,'{}'::jsonb);

  -- 上一份快照用于“自上次检查以来”的增量。
  SELECT * INTO v_prev
  FROM public.jiuxiao_db_health_snapshots_v242
  ORDER BY checked_at DESC,id DESC LIMIT 1;

  -- Top10大表，并与上一份快照中同名表比较。
  SELECT coalesce(jsonb_agg(jsonb_build_object(
      'schema_name',q.schema_name,
      'table_name',q.table_name,
      'size_bytes',q.size_bytes,
      'size',pg_size_pretty(q.size_bytes),
      'estimated_rows',q.estimated_rows,
      'delta_bytes',q.size_bytes-coalesce(q.prev_size_bytes,q.size_bytes),
      'delta',pg_size_pretty(abs(q.size_bytes-coalesce(q.prev_size_bytes,q.size_bytes))),
      'delta_direction',CASE WHEN q.prev_size_bytes IS NULL THEN 'new' WHEN q.size_bytes>q.prev_size_bytes THEN 'up' WHEN q.size_bytes<q.prev_size_bytes THEN 'down' ELSE 'flat' END
    ) ORDER BY q.size_bytes DESC),'[]'::jsonb)
  INTO v_top_tables
  FROM (
    SELECT n.nspname AS schema_name,c.relname AS table_name,
           pg_total_relation_size(c.oid) AS size_bytes,
           greatest(0,c.reltuples::bigint) AS estimated_rows,
           (
             SELECT (e->>'size_bytes')::bigint
             FROM jsonb_array_elements(coalesce(v_prev.top_tables,'[]'::jsonb)) e
             WHERE e->>'schema_name'=n.nspname AND e->>'table_name'=c.relname
             LIMIT 1
           ) AS prev_size_bytes
    FROM pg_class c
    JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='public' AND c.relkind IN('r','p')
    ORDER BY pg_total_relation_size(c.oid) DESC
    LIMIT 10
  ) q;

  -- pg_stat_statements 是可选监控；不可用时不阻断GM。
  SELECT n.nspname INTO v_pgss_schema
  FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE c.relname='pg_stat_statements' AND c.relkind IN('v','m')
  ORDER BY CASE WHEN n.nspname='extensions' THEN 0 WHEN n.nspname='public' THEN 1 ELSE 2 END
  LIMIT 1;

  IF v_pgss_schema IS NOT NULL THEN
    BEGIN
      EXECUTE format($sql$
        SELECT coalesce(jsonb_agg(to_jsonb(z) ORDER BY z.total_exec_time DESC),'[]'::jsonb)
        FROM (
          SELECT queryid::text AS queryid,calls,round(total_exec_time::numeric,2) AS total_exec_time_ms,
                 round(mean_exec_time::numeric,2) AS mean_exec_time_ms,rows,
                 left(regexp_replace(query,E'[\\n\\r\\t ]+',' ','g'),320) AS query
          FROM %I.pg_stat_statements
          WHERE dbid=(SELECT oid FROM pg_database WHERE datname=current_database())
            AND query NOT ILIKE '%%pg_stat_statements%%'
          ORDER BY total_exec_time DESC
          LIMIT 10
        ) z
      $sql$,v_pgss_schema) INTO v_hotspots;
    EXCEPTION WHEN OTHERS THEN
      v_hotspots:=jsonb_build_array(jsonb_build_object('available',false,'error',SQLERRM));
    END;
  ELSE
    v_hotspots:=jsonb_build_array(jsonb_build_object('available',false,'reason','pg_stat_statements_not_available'));
  END IF;

  -- 明确的制度异常才影响颜色；rollback/temp只展示增量，不凭空设阈值。
  v_mb:=v_db_size/1024.0/1024.0;
  IF v_policy<>'DBCAP03_ROLLING_TTL' THEN
    v_health:='critical';
    v_issues:=v_issues||jsonb_build_array(jsonb_build_object('level','critical','code','DBCAP03_POLICY_INVALID','text','24小时滚动治理策略未生效'));
  END IF;
  IF v_global_count<>1 OR v_global_active<>1 OR v_global_schedule<>'25 */6 * * *' THEN
    v_health:='critical';
    v_issues:=v_issues||jsonb_build_array(jsonb_build_object('level','critical','code','GLOBAL_CRON_INVALID','text','全局治理Cron数量、启用状态或计划不正确'));
  END IF;
  IF v_bsect_count<>1 OR v_bsect_active<>1 OR v_bsect_schedule<>'35 */6 * * *' THEN
    v_health:='critical';
    v_issues:=v_issues||jsonb_build_array(jsonb_build_object('level','critical','code','BSECT06_CRON_INVALID','text','宗门维护Cron数量、启用状态或计划不正确'));
  END IF;
  IF v_forbidden_tick THEN
    v_health:='critical';
    v_issues:=v_issues||jsonb_build_array(jsonb_build_object('level','critical','code','FORBIDDEN_PAIGOW_TICK','text','禁止的牌九数据库Tick正在运行'));
  END IF;
  IF v_mb>=v_critical_mb THEN
    v_health:='critical';
    v_issues:=v_issues||jsonb_build_array(jsonb_build_object('level','critical','code','DATABASE_CAPACITY_CRITICAL','text',format('数据库容量 %sMB 已达到警告线 %sMB',round(v_mb,2),v_critical_mb)));
  ELSIF v_mb>=v_warning_mb AND v_health='safe' THEN
    v_health:='warning';
    v_issues:=v_issues||jsonb_build_array(jsonb_build_object('level','warning','code','DATABASE_CAPACITY_WARNING','text',format('数据库容量 %sMB 已达到提醒线 %sMB',round(v_mb,2),v_warning_mb)));
  END IF;
  IF coalesce(v_latest_cleanup->>'status','')='failed' AND v_health='safe' THEN
    v_health:='warning';
    v_issues:=v_issues||jsonb_build_array(jsonb_build_object('level','warning','code','LATEST_CLEANUP_FAILED','text','最近一次数据库治理失败，请先查看失败原因'));
  END IF;
  IF v_prev.id IS NOT NULL AND v_deadlocks>v_prev.deadlocks AND v_health='safe' THEN
    v_health:='warning';
    v_issues:=v_issues||jsonb_build_array(jsonb_build_object('level','warning','code','NEW_DEADLOCK','text',format('自上次检查新增 %s 次 deadlock',v_deadlocks-v_prev.deadlocks)));
  END IF;

  -- 1h/6h/24h/48h找“目标时刻之前最近的一份快照”，没有就返回null。
  FOR r IN SELECT * FROM (VALUES ('1h',interval '1 hour'),('6h',interval '6 hours'),('24h',interval '24 hours'),('48h',interval '48 hours')) AS x(label,age) LOOP
    v_comparisons:=v_comparisons||jsonb_build_object(r.label,(
      SELECT jsonb_build_object(
        'snapshot_id',s.id,'checked_at',s.checked_at,
        'database_size_delta_bytes',v_db_size-s.database_size_bytes,
        'xact_commit_delta',v_commit-s.xact_commit,
        'xact_rollback_delta',v_rollback-s.xact_rollback,
        'deadlocks_delta',v_deadlocks-s.deadlocks,
        'temp_files_delta',v_temp_files-s.temp_files,
        'temp_bytes_delta',v_temp_bytes-s.temp_bytes
      )
      FROM public.jiuxiao_db_health_snapshots_v242 s
      WHERE s.checked_at<=v_now-r.age
      ORDER BY s.checked_at DESC,id DESC LIMIT 1
    ));
  END LOOP;

  IF p_save_snapshot THEN
    -- 快照很小，只保留90天；这是管理统计，不是玩家业务数据。
    DELETE FROM public.jiuxiao_db_health_snapshots_v242 WHERE checked_at<v_now-interval '90 days';
    INSERT INTO public.jiuxiao_db_health_snapshots_v242(
      checked_at,checked_by,health_code,database_size_bytes,xact_commit,xact_rollback,deadlocks,temp_files,temp_bytes,stats_reset,
      release_name,cache_epoch,policy,issues,top_tables,cron_status,cleanup_status,perf_hotspots
    ) VALUES(
      v_now,v_checked_by,v_health,v_db_size,v_commit,v_rollback,v_deadlocks,v_temp_files,v_temp_bytes,v_stats_reset,
      v_release_name,v_cache_epoch,v_policy,v_issues,v_top_tables,v_cron,v_latest_cleanup,v_hotspots
    ) RETURNING id INTO v_snapshot_id;
  END IF;

  RETURN jsonb_build_object(
    'checked_at',v_now,
    'saved_snapshot_id',v_snapshot_id,
    'health',v_health,
    'issues',v_issues,
    'release',jsonb_build_object('release_name',v_release_name,'cache_epoch',v_cache_epoch,'admin9','R24'),
    'policy',v_policy,
    'database',jsonb_build_object(
      'size_bytes',v_db_size,'size',pg_size_pretty(v_db_size),'size_mb',round(v_mb,2),
      'warning_mb',v_warning_mb,'critical_mb',v_critical_mb,'block_mb',v_block_mb
    ),
    'stats',jsonb_build_object(
      'xact_commit',v_commit,'xact_rollback',v_rollback,'deadlocks',v_deadlocks,
      'temp_files',v_temp_files,'temp_bytes',v_temp_bytes,'stats_reset',v_stats_reset,
      'since_previous',CASE WHEN v_prev.id IS NULL THEN NULL ELSE jsonb_build_object(
        'snapshot_id',v_prev.id,'checked_at',v_prev.checked_at,
        'database_size_delta_bytes',v_db_size-v_prev.database_size_bytes,
        'xact_commit_delta',v_commit-v_prev.xact_commit,
        'xact_rollback_delta',v_rollback-v_prev.xact_rollback,
        'deadlocks_delta',v_deadlocks-v_prev.deadlocks,
        'temp_files_delta',v_temp_files-v_prev.temp_files,
        'temp_bytes_delta',v_temp_bytes-v_prev.temp_bytes
      ) END
    ),
    'comparisons',v_comparisons,
    'top_tables',v_top_tables,
    'cron',v_cron,
    'latest_cleanup',v_latest_cleanup,
    'perf_hotspots',v_hotspots
  );
END
$function$;

CREATE OR REPLACE FUNCTION public.admin9_list_database_health_v242(
  p_limit integer DEFAULT 30
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','auth','pg_temp'
AS $function$
DECLARE v_limit integer := least(100,greatest(1,coalesce(p_limit,30))); v_items jsonb;
BEGIN
  PERFORM public.admin_whoami_v1();
  SELECT coalesce(jsonb_agg(to_jsonb(x) ORDER BY x.checked_at DESC,x.id DESC),'[]'::jsonb)
  INTO v_items
  FROM (
    SELECT id,checked_at,health_code,database_size_bytes,pg_size_pretty(database_size_bytes) AS database_size,
           xact_commit,xact_rollback,deadlocks,temp_files,temp_bytes,stats_reset,release_name,cache_epoch,policy,
           issues,top_tables,cron_status,cleanup_status
    FROM public.jiuxiao_db_health_snapshots_v242
    ORDER BY checked_at DESC,id DESC LIMIT v_limit
  ) x;
  RETURN jsonb_build_object('items',v_items,'limit',v_limit);
END
$function$;

REVOKE ALL ON FUNCTION public.admin9_get_database_health_v242(boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin9_list_database_health_v242(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin9_get_database_health_v242(boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin9_list_database_health_v242(integer) TO authenticated;

COMMIT;

SELECT jsonb_build_object(
  'sql',242,
  'status','INSTALLED',
  'release_unchanged',(SELECT release_name FROM public.jiuxiao_app_release_control WHERE singleton_id=1),
  'admin9','R24',
  'health_rpc','admin9_get_database_health_v242',
  'history_rpc','admin9_list_database_health_v242',
  'next','DEPLOY_ADMIN9_R24_THEN_RUN_SQL242_GATE',
  'next_sql',243
) AS sql242_install_result;
