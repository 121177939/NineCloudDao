
-- 九霄问道 · V2.1.1 CACHE112 · SQL241
-- DBCAP03 + PERF2 正式数据库稳定迁移：滚动24小时技术历史治理。
-- 由B候选方案按当前CACHE111/ADMIN9 R22真实基线选择性集成；不改写历史SQL210。
--
-- 重要：
-- - 这是“新迁移追加修改”，不是改写已经执行过的SQL210。
-- - 不删除玩家当前角色/资产/宗门/弟子等正式业务状态。
-- - 最近24小时保留。
-- - processing/running/settling、未领取、未展示、有效/永久效果全部保护。
-- - 重大/置顶世界事件、宗门重大经历不按本规则删除。
-- - 不增加秒级/分钟级Cron。
--
-- 本SQL自身包含结构前置检查；任一关键对象/字段不匹配会在事务内直接中止，不做半套修改。
BEGIN;
SET LOCAL lock_timeout='8s';
SET LOCAL statement_timeout='8min';

DO $precheck$
DECLARE
  r record;
  v_missing text[] := ARRAY[]::text[];
  v_n integer;
  v_cache integer;
  v_release text;
BEGIN
  -- 只认真实结构，不拿可能滞后的release_control显示值当数据库业务基线。
  FOR r IN SELECT * FROM (VALUES
    ('jiuxiao_auto_cleanup_config_v210'),('jiuxiao_cleanup_runs_v210'),('jiuxiao_cleanup_monthly_summary_v210'),
    ('secret_realm_requests_bsecretrealm01'),('secret_realm_events_bsecretrealm01'),('secret_realm_runs_bsecretrealm01'),
    ('opportunity_v3_results'),('opportunity_v3_effect_ledger'),('opportunity_v4_settlement_batches'),
    ('character_cultivation_effects'),('jiuxiao_world_events'),
    ('sect_settlement_requests_bsect01'),('sect_action_requests_bsect02'),('sect_action_requests_bsect03'),
    ('sect_action_requests_bsect04'),('sect_action_requests_bsect06'),('sect_autonomy_settings_bsect06'),
    ('sect_event_history_bsect06'),('sect_event_monthly_summaries_bsect06'),('sect_pending_events_bsect04'),
    ('sect_event_cooldowns_bsect06'),('sect_maintenance_state_bsect06'),('jiuxiao_app_release_control')
  ) AS x(name) LOOP
    IF to_regclass('public.'||r.name) IS NULL THEN v_missing:=array_append(v_missing,'public.'||r.name); END IF;
  END LOOP;
  IF to_regclass('cron.job') IS NULL OR to_regclass('cron.job_run_details') IS NULL THEN
    v_missing:=array_append(v_missing,'cron.job/cron.job_run_details');
  END IF;
  IF cardinality(v_missing)>0 THEN
    RAISE EXCEPTION 'SQL241_PRECHECK_MISSING_RELATIONS:%',array_to_string(v_missing,',');
  END IF;

  FOR r IN SELECT * FROM (VALUES
    ('jiuxiao_auto_cleanup_config_v210','singleton_id'),('jiuxiao_auto_cleanup_config_v210','enabled'),
    ('jiuxiao_auto_cleanup_config_v210','completed_request_days'),('jiuxiao_auto_cleanup_config_v210','failed_request_days'),
    ('jiuxiao_auto_cleanup_config_v210','ordinary_event_days'),('jiuxiao_auto_cleanup_config_v210','shown_batch_days'),
    ('jiuxiao_auto_cleanup_config_v210','expired_effect_days'),('jiuxiao_auto_cleanup_config_v210','cron_history_days'),
    ('jiuxiao_auto_cleanup_config_v210','batch_size'),
    ('sect_autonomy_settings_bsect06','singleton_id'),('sect_autonomy_settings_bsect06','ordinary_retention_days'),
    ('sect_autonomy_settings_bsect06','request_retention_days'),('sect_autonomy_settings_bsect06','maintenance_batch_size'),
    ('secret_realm_requests_bsecretrealm01','created_at'),('secret_realm_requests_bsecretrealm01','status'),('secret_realm_requests_bsecretrealm01','action_code'),
    ('secret_realm_events_bsecretrealm01','created_at'),('secret_realm_events_bsecretrealm01','run_id'),('secret_realm_events_bsecretrealm01','event_type'),('secret_realm_events_bsecretrealm01','outcome'),
    ('secret_realm_runs_bsecretrealm01','id'),('secret_realm_runs_bsecretrealm01','status'),('secret_realm_runs_bsecretrealm01','claim_status'),
    ('opportunity_v3_results','id'),('opportunity_v3_results','created_at'),('opportunity_v3_results','settlement_batch_id'),('opportunity_v3_results','rarity'),('opportunity_v3_results','path_key'),
    ('opportunity_v3_effect_ledger','result_id'),('opportunity_v3_effect_ledger','expires_at'),
    ('opportunity_v4_settlement_batches','id'),('opportunity_v4_settlement_batches','created_at'),('opportunity_v4_settlement_batches','shown_at'),
    ('jiuxiao_world_events','created_at'),('jiuxiao_world_events','is_pinned'),('jiuxiao_world_events','event_level'),
    ('character_cultivation_effects','expires_at'),
    ('jiuxiao_cleanup_monthly_summary_v210','source_code'),('jiuxiao_cleanup_monthly_summary_v210','month_key'),('jiuxiao_cleanup_monthly_summary_v210','dimension_key'),
    ('jiuxiao_cleanup_monthly_summary_v210','archived_rows'),('jiuxiao_cleanup_monthly_summary_v210','first_event_at'),('jiuxiao_cleanup_monthly_summary_v210','last_event_at'),('jiuxiao_cleanup_monthly_summary_v210','metadata'),('jiuxiao_cleanup_monthly_summary_v210','updated_at'),
    ('jiuxiao_cleanup_runs_v210','id'),('jiuxiao_cleanup_runs_v210','status'),('jiuxiao_cleanup_runs_v210','trigger_source'),('jiuxiao_cleanup_runs_v210','dry_run'),('jiuxiao_cleanup_runs_v210','batch_limit'),
    ('jiuxiao_cleanup_runs_v210','database_size_before'),('jiuxiao_cleanup_runs_v210','database_size_after'),('jiuxiao_cleanup_runs_v210','preview_rows'),('jiuxiao_cleanup_runs_v210','deleted_rows'),('jiuxiao_cleanup_runs_v210','error_text'),('jiuxiao_cleanup_runs_v210','created_at'),('jiuxiao_cleanup_runs_v210','finished_at'),
    ('sect_event_history_bsect06','id'),('sect_event_history_bsect06','sect_id'),('sect_event_history_bsect06','category_code'),('sect_event_history_bsect06','occurred_at'),('sect_event_history_bsect06','importance_code'),
    ('sect_event_monthly_summaries_bsect06','sect_id'),('sect_event_monthly_summaries_bsect06','month_key'),('sect_event_monthly_summaries_bsect06','category_code'),('sect_event_monthly_summaries_bsect06','event_count'),('sect_event_monthly_summaries_bsect06','effect_summary'),('sect_event_monthly_summaries_bsect06','generated_at'),
    ('sect_pending_events_bsect04','status'),('sect_pending_events_bsect04','created_at'),('sect_pending_events_bsect04','resolved_at'),
    ('sect_action_requests_bsect06','created_at'),('sect_event_cooldowns_bsect06','last_triggered_at'),
    ('sect_maintenance_state_bsect06','last_daily_run_at'),('sect_maintenance_state_bsect06','last_weekly_run_at'),('sect_maintenance_state_bsect06','last_result'),('sect_maintenance_state_bsect06','updated_at')
  ) AS x(tbl,col) LOOP
    IF NOT EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name=r.tbl AND column_name=r.col) THEN
      RAISE EXCEPTION 'SQL241_PRECHECK_MISSING_COLUMN:%.%',r.tbl,r.col;
    END IF;
  END LOOP;

  IF to_regprocedure('public.preview_jiuxiao_auto_cleanup_v210()') IS NULL
     OR to_regprocedure('public.run_jiuxiao_auto_cleanup_v210(boolean,integer,text)') IS NULL
     OR to_regprocedure('public.bsect06_run_maintenance_internal(timestamp with time zone)') IS NULL THEN
    RAISE EXCEPTION 'SQL241_PRECHECK_BASE_MAINTENANCE_FUNCTIONS_MISSING';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='admin9_get_database_maintenance_v210')
     OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='admin9_update_database_maintenance_v210')
     OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='admin9_run_database_cleanup_v210')
     OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='admin9_list_database_cleanup_runs_v210') THEN
    RAISE EXCEPTION 'SQL241_PRECHECK_ADMIN9_DB_RPC_MISSING';
  END IF;
  IF to_regprocedure('cron.alter_job(bigint,text,text,text,text,boolean)') IS NULL THEN
    RAISE EXCEPTION 'SQL241_PRECHECK_CRON_ALTER_JOB_SIGNATURE_MISSING';
  END IF;

  SELECT count(*) INTO v_n FROM cron.job WHERE jobname='jiuxiao-auto-cleanup-v210';
  IF v_n<>1 THEN RAISE EXCEPTION 'SQL241_PRECHECK_GLOBAL_CLEANUP_JOB_COUNT:%',v_n; END IF;
  SELECT count(*) INTO v_n FROM cron.job WHERE jobname='jiuxiao_bsect06_daily_maintenance';
  IF v_n<>1 THEN RAISE EXCEPTION 'SQL241_PRECHECK_BSECT06_JOB_COUNT:%',v_n; END IF;
  IF EXISTS(SELECT 1 FROM cron.job WHERE active AND command ILIKE '%paigow_tick_due_rooms_bpaigow01%') THEN
    RAISE EXCEPTION 'SQL241_PRECHECK_FORBIDDEN_PAIGOW_TICK_CRON_ACTIVE';
  END IF;

  IF NOT EXISTS(SELECT 1 FROM public.jiuxiao_auto_cleanup_config_v210 WHERE singleton_id=1) THEN RAISE EXCEPTION 'SQL241_PRECHECK_CLEANUP_CONFIG_ROW_MISSING'; END IF;
  IF NOT EXISTS(SELECT 1 FROM public.sect_autonomy_settings_bsect06 WHERE singleton_id=1) THEN RAISE EXCEPTION 'SQL241_PRECHECK_BSECT06_CONFIG_ROW_MISSING'; END IF;
  SELECT release_name,cache_epoch INTO v_release,v_cache FROM public.jiuxiao_app_release_control WHERE singleton_id=1;
  IF NOT FOUND THEN RAISE EXCEPTION 'SQL241_PRECHECK_RELEASE_ROW_MISSING'; END IF;
  IF coalesce(v_cache,-1)>112 THEN RAISE EXCEPTION 'SQL241_PRECHECK_NEWER_RELEASE_BLOCK:%/%',v_release,v_cache; END IF;
END
$precheck$;

-- 1) 将已有可调保留参数统一设为1天；保留现有容量阈值等其他配置。
UPDATE public.jiuxiao_auto_cleanup_config_v210
SET completed_request_days=1,
    failed_request_days=1,
    ordinary_event_days=1,
    shown_batch_days=1,
    expired_effect_days=1,
    cron_history_days=1,
    batch_size=20000
WHERE singleton_id=1;

UPDATE public.sect_autonomy_settings_bsect06
SET ordinary_retention_days=1,
    request_retention_days=1
WHERE singleton_id=1;

-- 2) 为新纳入的宗门请求缓存补全局created_at清理索引。
-- 当前这些表已在事故处理中大幅瘦身，发布窗内普通建索引成本较低。
CREATE INDEX IF NOT EXISTS idx_sect_settlement_requests_bsect01_cleanup_dbcap03
  ON public.sect_settlement_requests_bsect01(created_at);
CREATE INDEX IF NOT EXISTS idx_sect_action_requests_bsect02_cleanup_dbcap03
  ON public.sect_action_requests_bsect02(created_at);
CREATE INDEX IF NOT EXISTS idx_sect_action_requests_bsect03_cleanup_dbcap03
  ON public.sect_action_requests_bsect03(created_at);
CREATE INDEX IF NOT EXISTS idx_sect_action_requests_bsect04_cleanup_dbcap03
  ON public.sect_action_requests_bsect04(created_at);
CREATE INDEX IF NOT EXISTS idx_sect_action_requests_bsect06_cleanup_dbcap03
  ON public.sect_action_requests_bsect06(created_at);

-- DBCAP03会清理所有“安全的”V3历史，不再只限黄/玄/地，因此补全局时间索引。
CREATE INDEX IF NOT EXISTS idx_opportunity_v3_results_cleanup_dbcap03
  ON public.opportunity_v3_results(created_at);

CREATE INDEX IF NOT EXISTS idx_sect_event_history_bsect06_cleanup_dbcap03
  ON public.sect_event_history_bsect06(occurred_at,id)
  WHERE importance_code='ordinary';

-- 3) 预览函数：去掉row_number全表窗口排序；严格按TTL和业务保护条件判断。
CREATE OR REPLACE FUNCTION public.preview_jiuxiao_auto_cleanup_v210()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','cron','pg_temp'
AS $function$
DECLARE
  v_cfg public.jiuxiao_auto_cleanup_config_v210%rowtype;
  v_now timestamptz := clock_timestamp();
  v_result jsonb;
BEGIN
  SELECT * INTO STRICT v_cfg
  FROM public.jiuxiao_auto_cleanup_config_v210
  WHERE singleton_id=1;

  SELECT jsonb_build_object(
    'enabled',v_cfg.enabled,
    'policy','DBCAP03_ROLLING_TTL',
    'database_size_bytes',pg_database_size(current_database()),
    'database_size',pg_size_pretty(pg_database_size(current_database())),

    'sect_request_bsect01',(SELECT count(*) FROM public.sect_settlement_requests_bsect01
      WHERE created_at<v_now-make_interval(days=>v_cfg.completed_request_days)),
    'sect_request_bsect02',(SELECT count(*) FROM public.sect_action_requests_bsect02
      WHERE created_at<v_now-make_interval(days=>v_cfg.completed_request_days)),
    'sect_request_bsect03',(SELECT count(*) FROM public.sect_action_requests_bsect03
      WHERE created_at<v_now-make_interval(days=>v_cfg.completed_request_days)),
    'sect_request_bsect04',(SELECT count(*) FROM public.sect_action_requests_bsect04
      WHERE created_at<v_now-make_interval(days=>v_cfg.completed_request_days)),
    'sect_request_bsect06',(SELECT count(*) FROM public.sect_action_requests_bsect06
      WHERE created_at<v_now-make_interval(days=>v_cfg.completed_request_days)),

    'secret_realm_requests_done',(SELECT count(*) FROM public.secret_realm_requests_bsecretrealm01
      WHERE status='done' AND created_at<v_now-make_interval(days=>v_cfg.completed_request_days)),
    'secret_realm_requests_failed',(SELECT count(*) FROM public.secret_realm_requests_bsecretrealm01
      WHERE status='failed' AND created_at<v_now-make_interval(days=>v_cfg.failed_request_days)),

    'secret_realm_events_claimed',(SELECT count(*)
      FROM public.secret_realm_events_bsecretrealm01 e
      JOIN public.secret_realm_runs_bsecretrealm01 r ON r.id=e.run_id
      WHERE e.created_at<v_now-make_interval(days=>v_cfg.ordinary_event_days)
        AND r.status NOT IN('running','settling')
        AND r.claim_status='claimed'),

    'opportunity_v3_safe_history',(SELECT count(*)
      FROM public.opportunity_v3_results r
      WHERE r.created_at<v_now-make_interval(days=>v_cfg.ordinary_event_days)
        AND NOT EXISTS(
          SELECT 1 FROM public.opportunity_v3_effect_ledger l
          WHERE l.result_id=r.id
            AND (l.expires_at IS NULL OR l.expires_at>v_now)
        )
        AND NOT EXISTS(
          SELECT 1 FROM public.opportunity_v4_settlement_batches b
          WHERE b.id=r.settlement_batch_id AND b.shown_at IS NULL
        )),

    'opportunity_v4_shown_batches',(SELECT count(*)
      FROM public.opportunity_v4_settlement_batches b
      WHERE b.created_at<v_now-make_interval(days=>v_cfg.shown_batch_days)
        AND b.shown_at IS NOT NULL
        AND NOT EXISTS(
          SELECT 1 FROM public.opportunity_v3_results r
          WHERE r.settlement_batch_id=b.id
        )),

    'world_events_ordinary',(SELECT count(*)
      FROM public.jiuxiao_world_events e
      WHERE e.created_at<v_now-make_interval(days=>v_cfg.ordinary_event_days)
        AND e.is_pinned IS FALSE
        AND e.event_level<=2),

    'expired_cultivation_effects',(SELECT count(*)
      FROM public.character_cultivation_effects e
      WHERE e.expires_at IS NOT NULL
        AND e.expires_at<v_now-make_interval(days=>v_cfg.expired_effect_days)),

    'cron_history',(SELECT count(*)
      FROM cron.job_run_details d
      WHERE d.status<>'running'
        AND d.start_time<v_now-make_interval(days=>v_cfg.cron_history_days)),

    'protected',jsonb_build_object(
      'secret_processing',(SELECT count(*) FROM public.secret_realm_requests_bsecretrealm01 WHERE status='processing'),
      'secret_active_or_unclaimed_old',(SELECT count(*)
        FROM public.secret_realm_events_bsecretrealm01 e
        JOIN public.secret_realm_runs_bsecretrealm01 r ON r.id=e.run_id
        WHERE e.created_at<v_now-make_interval(days=>v_cfg.ordinary_event_days)
          AND (r.status IN('running','settling') OR r.claim_status<>'claimed')),
      'opportunity_unshown_batches',(SELECT count(*) FROM public.opportunity_v4_settlement_batches WHERE shown_at IS NULL),
      'permanent_cultivation_effects',(SELECT count(*) FROM public.character_cultivation_effects WHERE expires_at IS NULL),
      'world_major_or_pinned',(SELECT count(*) FROM public.jiuxiao_world_events WHERE event_level>=3 OR is_pinned)
    )
  ) INTO v_result;

  RETURN v_result;
END
$function$;

-- 4) 正式清理函数。
CREATE OR REPLACE FUNCTION public.run_jiuxiao_auto_cleanup_v210(
  p_dry_run boolean DEFAULT false,
  p_batch_limit integer DEFAULT NULL::integer,
  p_trigger_source text DEFAULT 'manual'::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','cron','pg_temp'
AS $function$
DECLARE
  v_cfg public.jiuxiao_auto_cleanup_config_v210%rowtype;
  v_now timestamptz := clock_timestamp();
  v_limit integer;
  v_run_id bigint;
  v_before bigint := pg_database_size(current_database());
  v_after bigint;
  v_preview jsonb;
  v_deleted jsonb := '{}'::jsonb;
  v_tids tid[];
  v_count integer := 0;
  v_total integer := 0;
BEGIN
  PERFORM set_config('lock_timeout','5s',true);
  PERFORM set_config('statement_timeout','8min',true);

  IF NOT pg_try_advisory_xact_lock(hashtext('JIUXIAO_AUTO_CLEANUP_V210')::bigint) THEN
    RETURN jsonb_build_object('status','skipped','reason','another_cleanup_is_running','ran_at',v_now);
  END IF;

  SELECT * INTO STRICT v_cfg
  FROM public.jiuxiao_auto_cleanup_config_v210
  WHERE singleton_id=1
  FOR UPDATE;

  v_limit:=least(20000,greatest(100,coalesce(p_batch_limit,v_cfg.batch_size)));
  v_preview:=public.preview_jiuxiao_auto_cleanup_v210();

  INSERT INTO public.jiuxiao_cleanup_runs_v210(
    status,trigger_source,dry_run,batch_limit,database_size_before,preview_rows
  ) VALUES(
    CASE WHEN p_dry_run THEN 'preview' ELSE 'running' END,
    left(coalesce(nullif(btrim(p_trigger_source),''),'manual'),80),
    p_dry_run,v_limit,v_before,v_preview
  ) RETURNING id INTO v_run_id;

  BEGIN
    IF NOT v_cfg.enabled THEN
      UPDATE public.jiuxiao_cleanup_runs_v210 SET status='skipped',finished_at=clock_timestamp(),
        database_size_after=pg_database_size(current_database()),deleted_rows=jsonb_build_object('reason','disabled')
      WHERE id=v_run_id;
      RETURN jsonb_build_object('status','skipped','reason','disabled','run_id',v_run_id,'preview',v_preview);
    END IF;

    IF p_dry_run THEN
      UPDATE public.jiuxiao_cleanup_runs_v210 SET finished_at=clock_timestamp(),
        database_size_after=pg_database_size(current_database()) WHERE id=v_run_id;
      RETURN jsonb_build_object('status','preview','run_id',v_run_id,'preview',v_preview);
    END IF;

    -- A1-A5 宗门纯幂等缓存。无业务状态，仅删除TTL以前记录。
    SELECT array_agg(ctid) INTO v_tids FROM(
      SELECT ctid FROM public.sect_settlement_requests_bsect01
      WHERE created_at<v_now-make_interval(days=>v_cfg.completed_request_days)
      ORDER BY created_at LIMIT v_limit FOR UPDATE SKIP LOCKED
    )s;
    IF coalesce(cardinality(v_tids),0)>0 THEN
      DELETE FROM public.sect_settlement_requests_bsect01 WHERE ctid=ANY(v_tids);
      GET DIAGNOSTICS v_count=ROW_COUNT;
    ELSE v_count:=0; END IF;
    v_deleted:=v_deleted||jsonb_build_object('sect_settlement_requests_bsect01',v_count);v_total:=v_total+v_count;

    SELECT array_agg(ctid) INTO v_tids FROM(
      SELECT ctid FROM public.sect_action_requests_bsect02
      WHERE created_at<v_now-make_interval(days=>v_cfg.completed_request_days)
      ORDER BY created_at LIMIT v_limit FOR UPDATE SKIP LOCKED
    )s;
    IF coalesce(cardinality(v_tids),0)>0 THEN
      DELETE FROM public.sect_action_requests_bsect02 WHERE ctid=ANY(v_tids);
      GET DIAGNOSTICS v_count=ROW_COUNT;
    ELSE v_count:=0; END IF;
    v_deleted:=v_deleted||jsonb_build_object('sect_action_requests_bsect02',v_count);v_total:=v_total+v_count;

    SELECT array_agg(ctid) INTO v_tids FROM(
      SELECT ctid FROM public.sect_action_requests_bsect03
      WHERE created_at<v_now-make_interval(days=>v_cfg.completed_request_days)
      ORDER BY created_at LIMIT v_limit FOR UPDATE SKIP LOCKED
    )s;
    IF coalesce(cardinality(v_tids),0)>0 THEN
      DELETE FROM public.sect_action_requests_bsect03 WHERE ctid=ANY(v_tids);
      GET DIAGNOSTICS v_count=ROW_COUNT;
    ELSE v_count:=0; END IF;
    v_deleted:=v_deleted||jsonb_build_object('sect_action_requests_bsect03',v_count);v_total:=v_total+v_count;

    SELECT array_agg(ctid) INTO v_tids FROM(
      SELECT ctid FROM public.sect_action_requests_bsect04
      WHERE created_at<v_now-make_interval(days=>v_cfg.completed_request_days)
      ORDER BY created_at LIMIT v_limit FOR UPDATE SKIP LOCKED
    )s;
    IF coalesce(cardinality(v_tids),0)>0 THEN
      DELETE FROM public.sect_action_requests_bsect04 WHERE ctid=ANY(v_tids);
      GET DIAGNOSTICS v_count=ROW_COUNT;
    ELSE v_count:=0; END IF;
    v_deleted:=v_deleted||jsonb_build_object('sect_action_requests_bsect04',v_count);v_total:=v_total+v_count;

    SELECT array_agg(ctid) INTO v_tids FROM(
      SELECT ctid FROM public.sect_action_requests_bsect06
      WHERE created_at<v_now-make_interval(days=>v_cfg.completed_request_days)
      ORDER BY created_at LIMIT v_limit FOR UPDATE SKIP LOCKED
    )s;
    IF coalesce(cardinality(v_tids),0)>0 THEN
      DELETE FROM public.sect_action_requests_bsect06 WHERE ctid=ANY(v_tids);
      GET DIAGNOSTICS v_count=ROW_COUNT;
    ELSE v_count:=0; END IF;
    v_deleted:=v_deleted||jsonb_build_object('sect_action_requests_bsect06',v_count);v_total:=v_total+v_count;

    -- B 秘境请求：只done/failed；processing保护。
    SELECT array_agg(ctid) INTO v_tids FROM(
      SELECT ctid FROM public.secret_realm_requests_bsecretrealm01
      WHERE (status='done' AND created_at<v_now-make_interval(days=>v_cfg.completed_request_days))
         OR (status='failed' AND created_at<v_now-make_interval(days=>v_cfg.failed_request_days))
      ORDER BY created_at LIMIT v_limit FOR UPDATE SKIP LOCKED
    )s;
    IF coalesce(cardinality(v_tids),0)>0 THEN
      INSERT INTO public.jiuxiao_cleanup_monthly_summary_v210(
        source_code,month_key,dimension_key,archived_rows,first_event_at,last_event_at,metadata,updated_at
      )
      SELECT 'secret_realm_requests',date_trunc('month',created_at)::date,status||':'||action_code,
        count(*),min(created_at),max(created_at),jsonb_build_object('policy','DBCAP03_TTL'),v_now
      FROM public.secret_realm_requests_bsecretrealm01 WHERE ctid=ANY(v_tids)
      GROUP BY date_trunc('month',created_at)::date,status,action_code
      ON CONFLICT(source_code,month_key,dimension_key) DO UPDATE SET
        archived_rows=public.jiuxiao_cleanup_monthly_summary_v210.archived_rows+excluded.archived_rows,
        first_event_at=least(public.jiuxiao_cleanup_monthly_summary_v210.first_event_at,excluded.first_event_at),
        last_event_at=greatest(public.jiuxiao_cleanup_monthly_summary_v210.last_event_at,excluded.last_event_at),
        metadata=excluded.metadata,updated_at=excluded.updated_at;
      DELETE FROM public.secret_realm_requests_bsecretrealm01 WHERE ctid=ANY(v_tids);
      GET DIAGNOSTICS v_count=ROW_COUNT;
    ELSE v_count:=0; END IF;
    v_deleted:=v_deleted||jsonb_build_object('secret_realm_requests',v_count);v_total:=v_total+v_count;

    -- C 秘境详细事件：父run必须结束并已claimed；run摘要不删。
    SELECT array_agg(e.ctid) INTO v_tids FROM(
      SELECT e.ctid
      FROM public.secret_realm_events_bsecretrealm01 e
      JOIN public.secret_realm_runs_bsecretrealm01 r ON r.id=e.run_id
      WHERE e.created_at<v_now-make_interval(days=>v_cfg.ordinary_event_days)
        AND r.status NOT IN('running','settling')
        AND r.claim_status='claimed'
      ORDER BY e.created_at,e.ctid
      LIMIT v_limit
      FOR UPDATE OF e SKIP LOCKED
    ) e;
    IF coalesce(cardinality(v_tids),0)>0 THEN
      INSERT INTO public.jiuxiao_cleanup_monthly_summary_v210(
        source_code,month_key,dimension_key,archived_rows,first_event_at,last_event_at,metadata,updated_at
      )
      SELECT 'secret_realm_events',date_trunc('month',created_at)::date,event_type||':'||outcome,
        count(*),min(created_at),max(created_at),jsonb_build_object('policy','claimed_only_24h'),v_now
      FROM public.secret_realm_events_bsecretrealm01 WHERE ctid=ANY(v_tids)
      GROUP BY date_trunc('month',created_at)::date,event_type,outcome
      ON CONFLICT(source_code,month_key,dimension_key) DO UPDATE SET
        archived_rows=public.jiuxiao_cleanup_monthly_summary_v210.archived_rows+excluded.archived_rows,
        first_event_at=least(public.jiuxiao_cleanup_monthly_summary_v210.first_event_at,excluded.first_event_at),
        last_event_at=greatest(public.jiuxiao_cleanup_monthly_summary_v210.last_event_at,excluded.last_event_at),
        metadata=excluded.metadata,updated_at=excluded.updated_at;
      DELETE FROM public.secret_realm_events_bsecretrealm01 WHERE ctid=ANY(v_tids);
      GET DIAGNOSTICS v_count=ROW_COUNT;
    ELSE v_count:=0; END IF;
    v_deleted:=v_deleted||jsonb_build_object('secret_realm_events',v_count);v_total:=v_total+v_count;

    -- D 机缘V3：所有品级历史均可裁剪，但有效/永久effect与未展示批次保护。
    -- 不再使用row_number全表窗口排序。
    SELECT array_agg(r.ctid) INTO v_tids FROM(
      SELECT r.ctid
      FROM public.opportunity_v3_results r
      WHERE r.created_at<v_now-make_interval(days=>v_cfg.ordinary_event_days)
        AND NOT EXISTS(
          SELECT 1 FROM public.opportunity_v3_effect_ledger l
          WHERE l.result_id=r.id AND (l.expires_at IS NULL OR l.expires_at>v_now)
        )
        AND NOT EXISTS(
          SELECT 1 FROM public.opportunity_v4_settlement_batches b
          WHERE b.id=r.settlement_batch_id AND b.shown_at IS NULL
        )
      ORDER BY r.created_at,r.ctid
      LIMIT v_limit
      FOR UPDATE OF r SKIP LOCKED
    ) r;
    IF coalesce(cardinality(v_tids),0)>0 THEN
      INSERT INTO public.jiuxiao_cleanup_monthly_summary_v210(
        source_code,month_key,dimension_key,archived_rows,first_event_at,last_event_at,metadata,updated_at
      )
      SELECT 'opportunity_v3_results',date_trunc('month',created_at)::date,rarity||':'||path_key,
        count(*),min(created_at),max(created_at),jsonb_build_object('policy','safe_24h_all_rarities'),v_now
      FROM public.opportunity_v3_results WHERE ctid=ANY(v_tids)
      GROUP BY date_trunc('month',created_at)::date,rarity,path_key
      ON CONFLICT(source_code,month_key,dimension_key) DO UPDATE SET
        archived_rows=public.jiuxiao_cleanup_monthly_summary_v210.archived_rows+excluded.archived_rows,
        first_event_at=least(public.jiuxiao_cleanup_monthly_summary_v210.first_event_at,excluded.first_event_at),
        last_event_at=greatest(public.jiuxiao_cleanup_monthly_summary_v210.last_event_at,excluded.last_event_at),
        metadata=excluded.metadata,updated_at=excluded.updated_at;
      DELETE FROM public.opportunity_v3_results WHERE ctid=ANY(v_tids);
      GET DIAGNOSTICS v_count=ROW_COUNT;
    ELSE v_count:=0; END IF;
    v_deleted:=v_deleted||jsonb_build_object('opportunity_v3_results',v_count);v_total:=v_total+v_count;

    -- E V4：已展示且超过TTL；如仍被任何保留V3结果引用，则保护。
    SELECT array_agg(b.ctid) INTO v_tids FROM(
      SELECT b.ctid
      FROM public.opportunity_v4_settlement_batches b
      WHERE b.created_at<v_now-make_interval(days=>v_cfg.shown_batch_days)
        AND b.shown_at IS NOT NULL
        AND NOT EXISTS(SELECT 1 FROM public.opportunity_v3_results r WHERE r.settlement_batch_id=b.id)
      ORDER BY b.created_at,b.ctid
      LIMIT v_limit
      FOR UPDATE OF b SKIP LOCKED
    ) b;
    IF coalesce(cardinality(v_tids),0)>0 THEN
      DELETE FROM public.opportunity_v4_settlement_batches WHERE ctid=ANY(v_tids);
      GET DIAGNOSTICS v_count=ROW_COUNT;
    ELSE v_count:=0; END IF;
    v_deleted:=v_deleted||jsonb_build_object('opportunity_v4_settlement_batches',v_count);v_total:=v_total+v_count;

    -- F 世界普通feed：最近TTL、重大(level>=3)、置顶全部保护；不再做全表row_number。
    SELECT array_agg(e.ctid) INTO v_tids FROM(
      SELECT e.ctid FROM public.jiuxiao_world_events e
      WHERE e.created_at<v_now-make_interval(days=>v_cfg.ordinary_event_days)
        AND e.is_pinned IS FALSE AND e.event_level<=2
      ORDER BY e.created_at,e.ctid
      LIMIT v_limit
      FOR UPDATE OF e SKIP LOCKED
    ) e;
    IF coalesce(cardinality(v_tids),0)>0 THEN
      DELETE FROM public.jiuxiao_world_events WHERE ctid=ANY(v_tids);
      GET DIAGNOSTICS v_count=ROW_COUNT;
    ELSE v_count:=0; END IF;
    v_deleted:=v_deleted||jsonb_build_object('jiuxiao_world_events',v_count);v_total:=v_total+v_count;

    -- G 仅已过期并超过TTL的临时修炼效果；expires_at NULL永久保护。
    SELECT array_agg(ctid) INTO v_tids FROM(
      SELECT ctid FROM public.character_cultivation_effects
      WHERE expires_at IS NOT NULL
        AND expires_at<v_now-make_interval(days=>v_cfg.expired_effect_days)
      ORDER BY expires_at LIMIT v_limit FOR UPDATE SKIP LOCKED
    )s;
    IF coalesce(cardinality(v_tids),0)>0 THEN
      DELETE FROM public.character_cultivation_effects WHERE ctid=ANY(v_tids);
      GET DIAGNOSTICS v_count=ROW_COUNT;
    ELSE v_count:=0; END IF;
    v_deleted:=v_deleted||jsonb_build_object('character_cultivation_effects',v_count);v_total:=v_total+v_count;

    -- H Cron技术历史；running保护。
    SELECT array_agg(ctid) INTO v_tids FROM(
      SELECT ctid FROM cron.job_run_details
      WHERE status<>'running' AND start_time<v_now-make_interval(days=>v_cfg.cron_history_days)
      ORDER BY start_time LIMIT v_limit
    )s;
    IF coalesce(cardinality(v_tids),0)>0 THEN
      DELETE FROM cron.job_run_details WHERE ctid=ANY(v_tids);
      GET DIAGNOSTICS v_count=ROW_COUNT;
    ELSE v_count:=0; END IF;
    v_deleted:=v_deleted||jsonb_build_object('cron_job_run_details',v_count);v_total:=v_total+v_count;

    -- 清理系统自身审计仍保留180天；体积很小。
    DELETE FROM public.jiuxiao_cleanup_runs_v210
    WHERE id<>v_run_id AND created_at<v_now-interval '180 days';

    v_after:=pg_database_size(current_database());
    UPDATE public.jiuxiao_cleanup_runs_v210
    SET status='succeeded',finished_at=clock_timestamp(),database_size_after=v_after,deleted_rows=v_deleted
    WHERE id=v_run_id;

    RETURN jsonb_build_object(
      'status','succeeded','policy','DBCAP03_ROLLING_24H',
      'run_id',v_run_id,'deleted_total',v_total,'deleted_rows',v_deleted,
      'database_size_before_bytes',v_before,'database_size_after_bytes',v_after,
      'database_size_after',pg_size_pretty(v_after)
    );
  EXCEPTION WHEN OTHERS THEN
    UPDATE public.jiuxiao_cleanup_runs_v210
    SET status='failed',finished_at=clock_timestamp(),
      database_size_after=pg_database_size(current_database()),
      deleted_rows=v_deleted,error_text=left(sqlstate||':'||sqlerrm,2000)
    WHERE id=v_run_id;
    RETURN jsonb_build_object(
      'status','failed','run_id',v_run_id,'sqlstate',sqlstate,'error',sqlerrm,
      'deleted_rows_rolled_back',v_deleted
    );
  END;
END
$function$;

-- 5) BSECT06自身维护：普通历史先月汇总再删；请求TTL=1天；
-- resolved/expired案牍也按ordinary_retention_days清，未决案牍保护。
CREATE OR REPLACE FUNCTION public.bsect06_run_maintenance_internal(
  p_now timestamptz DEFAULT clock_timestamp()
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'pg_catalog','public','pg_temp'
AS $function$
DECLARE
  v_cfg public.sect_autonomy_settings_bsect06%rowtype;
  v_ids bigint[];
  v_archived integer:=0;
  v_trimmed integer:=0;
  v_pending integer:=0;
  v_requests integer:=0;
  v_cooldowns integer:=0;
  v_result jsonb;
BEGIN
  SELECT * INTO v_cfg FROM public.sect_autonomy_settings_bsect06 WHERE singleton_id=1;
  PERFORM pg_advisory_xact_lock(hashtext('BSECT06_MAINTENANCE'));

  SELECT array_agg(id) INTO v_ids FROM(
    SELECT id FROM public.sect_event_history_bsect06
    WHERE importance_code='ordinary'
      AND occurred_at<p_now-make_interval(days=>greatest(1,v_cfg.ordinary_retention_days))
    ORDER BY id LIMIT v_cfg.maintenance_batch_size
    FOR UPDATE SKIP LOCKED
  )s;

  IF cardinality(v_ids)>0 THEN
    INSERT INTO public.sect_event_monthly_summaries_bsect06(
      sect_id,month_key,category_code,event_count,effect_summary,generated_at
    )
    SELECT sect_id,date_trunc('month',occurred_at)::date,category_code,count(*),
      jsonb_build_object('archived_events',count(*)),p_now
    FROM public.sect_event_history_bsect06 WHERE id=ANY(v_ids)
    GROUP BY sect_id,date_trunc('month',occurred_at)::date,category_code
    ON CONFLICT(sect_id,month_key,category_code) DO UPDATE SET
      event_count=public.sect_event_monthly_summaries_bsect06.event_count+excluded.event_count,
      effect_summary=jsonb_build_object('archived_events',
        public.sect_event_monthly_summaries_bsect06.event_count+excluded.event_count),
      generated_at=excluded.generated_at;

    DELETE FROM public.sect_event_history_bsect06 WHERE id=ANY(v_ids);
    GET DIAGNOSTICS v_archived=ROW_COUNT;
  END IF;

  -- 原硬上限仍保留，但只作用于ordinary；先汇总再删。
  SELECT array_agg(id) INTO v_ids FROM(
    SELECT id FROM(
      SELECT id,row_number() OVER(PARTITION BY sect_id ORDER BY occurred_at DESC,id DESC) rn
      FROM public.sect_event_history_bsect06 WHERE importance_code='ordinary'
    ) ranked
    WHERE rn>v_cfg.ordinary_hard_cap_per_sect
    ORDER BY id LIMIT v_cfg.maintenance_batch_size
  ) doomed;

  IF cardinality(v_ids)>0 THEN
    INSERT INTO public.sect_event_monthly_summaries_bsect06(
      sect_id,month_key,category_code,event_count,effect_summary,generated_at
    )
    SELECT sect_id,date_trunc('month',occurred_at)::date,category_code,count(*),
      jsonb_build_object('archived_events',count(*),'reason','hard_cap'),p_now
    FROM public.sect_event_history_bsect06 WHERE id=ANY(v_ids)
    GROUP BY sect_id,date_trunc('month',occurred_at)::date,category_code
    ON CONFLICT(sect_id,month_key,category_code) DO UPDATE SET
      event_count=public.sect_event_monthly_summaries_bsect06.event_count+excluded.event_count,
      effect_summary=jsonb_build_object('archived_events',
        public.sect_event_monthly_summaries_bsect06.event_count+excluded.event_count,'last_reason','hard_cap'),
      generated_at=excluded.generated_at;
    DELETE FROM public.sect_event_history_bsect06 WHERE id=ANY(v_ids);
    GET DIAGNOSTICS v_trimmed=ROW_COUNT;
  END IF;

  -- resolved/expired案牍属于已完成历史；未决案牍绝对保护。按batch删除避免长事务。
  WITH doomed AS (
    SELECT ctid FROM public.sect_pending_events_bsect04
    WHERE status IN('resolved','expired')
      AND coalesce(resolved_at,created_at)<p_now-make_interval(days=>greatest(1,v_cfg.ordinary_retention_days))
    ORDER BY coalesce(resolved_at,created_at),ctid
    LIMIT v_cfg.maintenance_batch_size
    FOR UPDATE SKIP LOCKED
  )
  DELETE FROM public.sect_pending_events_bsect04 t USING doomed d WHERE t.ctid=d.ctid;
  GET DIAGNOSTICS v_pending=ROW_COUNT;

  WITH doomed AS (
    SELECT ctid FROM public.sect_action_requests_bsect06
    WHERE created_at<p_now-make_interval(days=>greatest(1,v_cfg.request_retention_days))
    ORDER BY created_at,ctid
    LIMIT v_cfg.maintenance_batch_size
    FOR UPDATE SKIP LOCKED
  )
  DELETE FROM public.sect_action_requests_bsect06 t USING doomed d WHERE t.ctid=d.ctid;
  GET DIAGNOSTICS v_requests=ROW_COUNT;

  -- 冷却是当前玩法状态，不按24小时历史规则处理；只清365天前陈旧记录，仍分批。
  WITH doomed AS (
    SELECT ctid FROM public.sect_event_cooldowns_bsect06
    WHERE last_triggered_at<p_now-interval '365 days'
    ORDER BY last_triggered_at,ctid
    LIMIT v_cfg.maintenance_batch_size
    FOR UPDATE SKIP LOCKED
  )
  DELETE FROM public.sect_event_cooldowns_bsect06 t USING doomed d WHERE t.ctid=d.ctid;
  GET DIAGNOSTICS v_cooldowns=ROW_COUNT;

  v_result:=jsonb_build_object(
    'archived_ordinary',v_archived,'hard_cap_summarized',v_trimmed,
    'pending_deleted',v_pending,'requests_deleted',v_requests,'cooldowns_deleted',v_cooldowns,
    'policy','DBCAP03_24H_HISTORY',
    'database_size_bytes',pg_database_size(current_database()),
    'database_size',pg_size_pretty(pg_database_size(current_database())),
    'ran_at',p_now
  );

  UPDATE public.sect_maintenance_state_bsect06
  SET last_daily_run_at=p_now,
      last_weekly_run_at=CASE WHEN extract(isodow from p_now)=1 THEN p_now ELSE last_weekly_run_at END,
      last_result=v_result,updated_at=p_now
  WHERE singleton_id=1;

  RETURN v_result;
END
$function$;


COMMENT ON FUNCTION public.preview_jiuxiao_auto_cleanup_v210() IS
  'SQL241 V2.1.1 CACHE112 DBCAP03 rolling-24h safe preview; protected current/business state';
COMMENT ON FUNCTION public.run_jiuxiao_auto_cleanup_v210(boolean,integer,text) IS
  'SQL241 V2.1.1 CACHE112 DBCAP03 indexed batched cleanup, max 20000/category, SKIP LOCKED';
COMMENT ON FUNCTION public.bsect06_run_maintenance_internal(timestamp with time zone) IS
  'SQL241 V2.1.1 CACHE112 DBCAP03 BSECT06 ordinary summary-before-delete and 24h request retention';

-- 6) 只调整现有Cron，不新增重复job。24h TTL在6小时扫描下最坏约30小时。
DO $cron$
DECLARE
  v_cleanup bigint;
  v_bsect bigint;
BEGIN
  SELECT jobid INTO STRICT v_cleanup FROM cron.job WHERE jobname='jiuxiao-auto-cleanup-v210';
  SELECT jobid INTO STRICT v_bsect FROM cron.job WHERE jobname='jiuxiao_bsect06_daily_maintenance';
  PERFORM cron.alter_job(v_cleanup,'25 */6 * * *',NULL,NULL,NULL,true);
  PERFORM cron.alter_job(v_bsect,'35 */6 * * *',NULL,NULL,NULL,true);
END
$cron$;

COMMIT;

NOTIFY pgrst,'reload schema';

SELECT jsonb_build_object(
  'success',true,
  'sql',241,
  'feature','DBCAP03_ROLLING_24H_DATABASE_GOVERNANCE',
  'policy',(public.preview_jiuxiao_auto_cleanup_v210()->>'policy'),
  'cleanup_days',(SELECT completed_request_days FROM public.jiuxiao_auto_cleanup_config_v210 WHERE singleton_id=1),
  'batch_size',(SELECT batch_size FROM public.jiuxiao_auto_cleanup_config_v210 WHERE singleton_id=1),
  'global_cleanup_schedule',(SELECT schedule FROM cron.job WHERE jobname='jiuxiao-auto-cleanup-v210'),
  'bsect06_schedule',(SELECT schedule FROM cron.job WHERE jobname='jiuxiao_bsect06_daily_maintenance'),
  'release_control_unchanged',(SELECT release_name FROM public.jiuxiao_app_release_control WHERE singleton_id=1),
  'next','DEPLOY_CACHE112_ADMIN9_R23_THEN_RUN_SQL241_GATE',
  'next_sql',242
) AS sql241_install_result;
