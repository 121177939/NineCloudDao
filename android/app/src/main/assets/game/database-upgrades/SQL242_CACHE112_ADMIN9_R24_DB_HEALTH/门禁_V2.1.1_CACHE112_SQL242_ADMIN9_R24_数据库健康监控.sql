-- 《九霄问道》SQL242 制度门禁
-- 只验证数据库健康监控和ADMIN9 R24所需接口；不改变CACHE112游戏发布标识。

BEGIN;

DO $gate$
DECLARE
  v_policy text;
  v_n integer;
  v_rel text;
  v_cache integer;
BEGIN
  IF to_regclass('public.jiuxiao_db_health_snapshots_v242') IS NULL THEN
    RAISE EXCEPTION 'SQL242_GATE_SNAPSHOT_TABLE_MISSING';
  END IF;
  IF to_regprocedure('public.admin9_get_database_health_v242(boolean)') IS NULL
     OR to_regprocedure('public.admin9_list_database_health_v242(integer)') IS NULL THEN
    RAISE EXCEPTION 'SQL242_GATE_HEALTH_RPC_MISSING';
  END IF;

  SELECT coalesce(public.preview_jiuxiao_auto_cleanup_v210()->>'policy','') INTO v_policy;
  IF v_policy<>'DBCAP03_ROLLING_TTL' THEN
    RAISE EXCEPTION 'SQL242_GATE_DBCAP03_POLICY_INVALID:%',v_policy;
  END IF;

  SELECT count(*) INTO v_n FROM cron.job WHERE jobname='jiuxiao-auto-cleanup-v210' AND active AND schedule='25 */6 * * *';
  IF v_n<>1 THEN RAISE EXCEPTION 'SQL242_GATE_GLOBAL_CRON_INVALID:%',v_n; END IF;
  SELECT count(*) INTO v_n FROM cron.job WHERE jobname='jiuxiao_bsect06_daily_maintenance' AND active AND schedule='35 */6 * * *';
  IF v_n<>1 THEN RAISE EXCEPTION 'SQL242_GATE_BSECT06_CRON_INVALID:%',v_n; END IF;
  IF EXISTS(SELECT 1 FROM cron.job WHERE active AND command ILIKE '%paigow_tick_due_rooms_bpaigow01%') THEN
    RAISE EXCEPTION 'SQL242_GATE_FORBIDDEN_PAIGOW_TICK_ACTIVE';
  END IF;

  IF has_function_privilege('anon','public.admin9_get_database_health_v242(boolean)','EXECUTE')
     OR has_function_privilege('anon','public.admin9_list_database_health_v242(integer)','EXECUTE') THEN
    RAISE EXCEPTION 'SQL242_GATE_ANON_EXECUTE_NOT_REVOKED';
  END IF;
  IF NOT has_function_privilege('authenticated','public.admin9_get_database_health_v242(boolean)','EXECUTE')
     OR NOT has_function_privilege('authenticated','public.admin9_list_database_health_v242(integer)','EXECUTE') THEN
    RAISE EXCEPTION 'SQL242_GATE_AUTHENTICATED_EXECUTE_MISSING';
  END IF;

  SELECT release_name,cache_epoch INTO v_rel,v_cache
  FROM public.jiuxiao_app_release_control WHERE singleton_id=1;
  IF v_rel<>'V2.1.1 CACHE112' OR v_cache<>112 THEN
    RAISE EXCEPTION 'SQL242_GATE_RELEASE_BASELINE_CHANGED:%/%',v_rel,v_cache;
  END IF;

  -- SQL Editor 没有玩家JWT上下文，因此门禁不直接执行ADMIN9 RPC；
  -- 这里只验证函数存在、权限、基础策略和Cron制度。登录GM后的RPC会再次走 admin_whoami_v1。
END
$gate$;

COMMIT;

SELECT jsonb_build_object(
  'sql',242,
  'gate','SQL242_GATE_PASSED',
  'success',true,
  'release_name',(SELECT release_name FROM public.jiuxiao_app_release_control WHERE singleton_id=1),
  'cache_epoch',(SELECT cache_epoch FROM public.jiuxiao_app_release_control WHERE singleton_id=1),
  'admin9','R24',
  'database_health','GM_INTEGRATED',
  'next_sql',243
) AS sql242_gate_result;
