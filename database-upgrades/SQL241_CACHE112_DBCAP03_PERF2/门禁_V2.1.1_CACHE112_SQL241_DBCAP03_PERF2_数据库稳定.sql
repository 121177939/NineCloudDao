-- 九霄问道 · V2.1.1 CACHE112 · SQL241 制度门禁
-- 在SQL241升级成功、CACHE112网页/Android部署、ADMIN9 R23验证后执行。
-- 只认真实结构/函数/配置/Cron；不要求旧release_control必须显示CACHE111，避免再次被滞后显示误伤。

BEGIN;
LOCK TABLE public.jiuxiao_app_release_control IN ROW EXCLUSIVE MODE;

DO $gate$
DECLARE
  v_preview oid;
  v_run oid;
  v_bsect oid;
  v_def text;
  v_comment text;
  v_p jsonb;
  v_n integer;
  v_cache integer;
  v_release text;
BEGIN
  IF to_regclass('public.jiuxiao_auto_cleanup_config_v210') IS NULL
     OR to_regclass('public.jiuxiao_cleanup_runs_v210') IS NULL
     OR to_regclass('public.jiuxiao_cleanup_monthly_summary_v210') IS NULL
     OR to_regclass('public.sect_autonomy_settings_bsect06') IS NULL THEN
    RAISE EXCEPTION 'SQL241_GATE_CORE_TABLES_MISSING';
  END IF;

  IF NOT EXISTS(
    SELECT 1 FROM public.jiuxiao_auto_cleanup_config_v210
    WHERE singleton_id=1
      AND completed_request_days=1 AND failed_request_days=1 AND ordinary_event_days=1
      AND shown_batch_days=1 AND expired_effect_days=1 AND cron_history_days=1
      AND batch_size=20000
  ) THEN RAISE EXCEPTION 'SQL241_GATE_24H_CONFIG_INVALID'; END IF;

  IF NOT EXISTS(
    SELECT 1 FROM public.sect_autonomy_settings_bsect06
    WHERE singleton_id=1 AND ordinary_retention_days=1 AND request_retention_days=1
  ) THEN RAISE EXCEPTION 'SQL241_GATE_BSECT06_24H_CONFIG_INVALID'; END IF;

  IF to_regclass('public.idx_sect_settlement_requests_bsect01_cleanup_dbcap03') IS NULL
     OR to_regclass('public.idx_sect_action_requests_bsect02_cleanup_dbcap03') IS NULL
     OR to_regclass('public.idx_sect_action_requests_bsect03_cleanup_dbcap03') IS NULL
     OR to_regclass('public.idx_sect_action_requests_bsect04_cleanup_dbcap03') IS NULL
     OR to_regclass('public.idx_sect_action_requests_bsect06_cleanup_dbcap03') IS NULL
     OR to_regclass('public.idx_opportunity_v3_results_cleanup_dbcap03') IS NULL
     OR to_regclass('public.idx_sect_event_history_bsect06_cleanup_dbcap03') IS NULL THEN
    RAISE EXCEPTION 'SQL241_GATE_DBCAP03_INDEX_MISSING';
  END IF;

  v_preview:=to_regprocedure('public.preview_jiuxiao_auto_cleanup_v210()');
  v_run:=to_regprocedure('public.run_jiuxiao_auto_cleanup_v210(boolean,integer,text)');
  v_bsect:=to_regprocedure('public.bsect06_run_maintenance_internal(timestamp with time zone)');
  IF v_preview IS NULL OR v_run IS NULL OR v_bsect IS NULL THEN RAISE EXCEPTION 'SQL241_GATE_FUNCTION_MISSING'; END IF;

  SELECT obj_description(v_preview,'pg_proc'),pg_get_functiondef(v_preview) INTO v_comment,v_def;
  IF coalesce(v_comment,'') NOT LIKE '%SQL241 V2.1.1 CACHE112 DBCAP03%'
     OR position('DBCAP03_ROLLING_TTL' in v_def)=0
     OR position('secret_active_or_unclaimed_old' in v_def)=0
     OR position('opportunity_unshown_batches' in v_def)=0
     OR position('permanent_cultivation_effects' in v_def)=0
     OR position('world_major_or_pinned' in v_def)=0 THEN
    RAISE EXCEPTION 'SQL241_GATE_PREVIEW_RULES_INVALID';
  END IF;

  SELECT obj_description(v_run,'pg_proc'),pg_get_functiondef(v_run) INTO v_comment,v_def;
  IF coalesce(v_comment,'') NOT LIKE '%SQL241 V2.1.1 CACHE112 DBCAP03%'
     OR position('SKIP LOCKED' in upper(v_def))=0
     OR position('least(20000' in replace(lower(v_def),' ',''))=0
     OR position('row_number' in lower(v_def))>0
     OR position('claim_status' in lower(v_def))=0
     OR position('shown_at is null' in lower(v_def))=0
     OR position('expires_at is null' in lower(v_def))=0
     OR position('event_level' in lower(v_def))=0 THEN
    RAISE EXCEPTION 'SQL241_GATE_CLEANUP_RULES_INVALID';
  END IF;

  SELECT obj_description(v_bsect,'pg_proc'),pg_get_functiondef(v_bsect) INTO v_comment,v_def;
  IF coalesce(v_comment,'') NOT LIKE '%SQL241 V2.1.1 CACHE112 DBCAP03%'
     OR position('sect_event_monthly_summaries_bsect06' in lower(v_def))=0
     OR position('importance_code' in lower(v_def))=0
     OR position('resolved' in lower(v_def))=0
     OR position('SKIP LOCKED' in upper(v_def))=0 THEN
    RAISE EXCEPTION 'SQL241_GATE_BSECT06_RULES_INVALID';
  END IF;

  -- SQL210内部函数继续保持仅服务端调用；ADMIN9通过旧安全包装RPC进入。
  IF has_function_privilege('anon',v_run,'EXECUTE') OR has_function_privilege('authenticated',v_run,'EXECUTE') THEN
    RAISE EXCEPTION 'SQL241_GATE_INTERNAL_CLEANUP_RPC_EXPOSED';
  END IF;

  IF NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='admin9_get_database_maintenance_v210')
     OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='admin9_update_database_maintenance_v210')
     OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='admin9_run_database_cleanup_v210')
     OR NOT EXISTS(SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public' AND p.proname='admin9_list_database_cleanup_runs_v210') THEN
    RAISE EXCEPTION 'SQL241_GATE_ADMIN9_OLD_DB_RPC_MISSING';
  END IF;

  SELECT count(*) INTO v_n FROM cron.job WHERE jobname='jiuxiao-auto-cleanup-v210';
  IF v_n<>1 THEN RAISE EXCEPTION 'SQL241_GATE_GLOBAL_CLEANUP_JOB_COUNT:%',v_n; END IF;
  IF NOT EXISTS(SELECT 1 FROM cron.job WHERE jobname='jiuxiao-auto-cleanup-v210' AND active AND schedule='25 */6 * * *') THEN
    RAISE EXCEPTION 'SQL241_GATE_GLOBAL_CLEANUP_SCHEDULE_INVALID';
  END IF;

  SELECT count(*) INTO v_n FROM cron.job WHERE jobname='jiuxiao_bsect06_daily_maintenance';
  IF v_n<>1 THEN RAISE EXCEPTION 'SQL241_GATE_BSECT06_JOB_COUNT:%',v_n; END IF;
  IF NOT EXISTS(SELECT 1 FROM cron.job WHERE jobname='jiuxiao_bsect06_daily_maintenance' AND active AND schedule='35 */6 * * *') THEN
    RAISE EXCEPTION 'SQL241_GATE_BSECT06_SCHEDULE_INVALID';
  END IF;

  IF EXISTS(SELECT 1 FROM cron.job WHERE active AND command ILIKE '%paigow_tick_due_rooms_bpaigow01%') THEN
    RAISE EXCEPTION 'SQL241_GATE_FORBIDDEN_PAIGOW_TICK_CRON_ACTIVE';
  END IF;

  v_p:=public.preview_jiuxiao_auto_cleanup_v210();
  IF coalesce(v_p->>'policy','')<>'DBCAP03_ROLLING_TTL'
     OR jsonb_typeof(v_p->'protected')<>'object'
     OR NOT (v_p ? 'sect_request_bsect01')
     OR NOT (v_p ? 'sect_request_bsect06')
     OR NOT (v_p ? 'secret_realm_events_claimed')
     OR NOT (v_p ? 'opportunity_v3_safe_history') THEN
    RAISE EXCEPTION 'SQL241_GATE_RUNTIME_PREVIEW_INVALID:%',v_p;
  END IF;

  SELECT release_name,cache_epoch INTO v_release,v_cache
  FROM public.jiuxiao_app_release_control WHERE singleton_id=1 FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'SQL241_GATE_RELEASE_ROW_MISSING'; END IF;
  IF coalesce(v_cache,-1)>112 THEN RAISE EXCEPTION 'SQL241_GATE_NEWER_RELEASE_BLOCK:%/%',v_release,v_cache; END IF;
END
$gate$;

UPDATE public.jiuxiao_app_release_control
SET release_name='V2.1.1 CACHE112',
    cache_epoch=112,
    notice_text='V2.1.1 CACHE112：DBCAP03滚动24小时技术历史治理 + PERF2空转RPC节流 + ADMIN9 R23简明管理版。当前角色/资产/宗门/弟子、运行中、未领取、未展示、有效/永久效果、重大/置顶事件继续绝对保护。',
    updated_at=clock_timestamp()
WHERE singleton_id=1;

COMMIT;
NOTIFY pgrst,'reload schema';

SELECT jsonb_build_object(
  'success',true,
  'gate','SQL241_GATE_PASSED',
  'sql',241,
  'release_name',(SELECT release_name FROM public.jiuxiao_app_release_control WHERE singleton_id=1),
  'cache_epoch',(SELECT cache_epoch FROM public.jiuxiao_app_release_control WHERE singleton_id=1),
  'policy',(public.preview_jiuxiao_auto_cleanup_v210()->>'policy'),
  'global_cleanup_schedule',(SELECT schedule FROM cron.job WHERE jobname='jiuxiao-auto-cleanup-v210'),
  'bsect06_schedule',(SELECT schedule FROM cron.job WHERE jobname='jiuxiao_bsect06_daily_maintenance'),
  'admin9','R23_REUSES_EXISTING_SAFE_RPCS',
  'next_sql',242
) AS sql241_gate_result;
