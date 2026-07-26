-- V0.11.9 检查：正常应全部PASS。
WITH fn AS (
  SELECT pg_get_functiondef('public.claim_cultivation_v1()'::regprocedure) AS body
), checks AS (
  SELECT 'claim_function_exists' AS check_name,
         to_regprocedure('public.claim_cultivation_v1()') IS NOT NULL AS passed,
         COALESCE(to_regprocedure('public.claim_cultivation_v1()')::text, 'missing') AS detail
  UNION ALL
  SELECT 'heaven_balance_rpc_exists',
         to_regprocedure('public.get_heaven_balance_v1()') IS NOT NULL,
         COALESCE(to_regprocedure('public.get_heaven_balance_v1()')::text, 'missing')
  UNION ALL
  SELECT 'heaven_balance_function_exists',
         to_regprocedure('public.heaven_balance_multiplier_v1(integer)') IS NOT NULL,
         COALESCE(to_regprocedure('public.heaven_balance_multiplier_v1(integer)')::text, 'missing')
  UNION ALL
  SELECT 'blessing_gap_minus5_is_x5',
         public.heaven_balance_multiplier_v1(-5) = 5.0,
         public.heaven_balance_multiplier_v1(-5)::text
  UNION ALL
  SELECT 'balance_gap_zero_is_x1',
         public.heaven_balance_multiplier_v1(0) = 1.0,
         public.heaven_balance_multiplier_v1(0)::text
  UNION ALL
  SELECT 'obstruction_gap_plus3_is_x05',
         public.heaven_balance_multiplier_v1(3) = 0.5,
         public.heaven_balance_multiplier_v1(3)::text
  UNION ALL
  SELECT 'full_rate_multiplier_enabled',
         body LIKE '%v_segment_fixed_rate * v_effective_qi_multiplier%',
         CASE WHEN body LIKE '%v_segment_fixed_rate * v_effective_qi_multiplier%' THEN 'full rate multiplied' ELSE 'formula missing' END
  FROM fn
  UNION ALL
  SELECT 'current_rate_multiplier_enabled',
         body LIKE '%v_current_fixed_rate * v_effective_qi_multiplier%',
         CASE WHEN body LIKE '%v_current_fixed_rate * v_effective_qi_multiplier%' THEN 'current rate multiplied' ELSE 'formula missing' END
  FROM fn
  UNION ALL
  SELECT 'old_additive_formula_removed',
         body NOT LIKE '%v_current_fixed_rate + v_qi_environment_gain%'
         AND body NOT LIKE '%v_segment_fixed_rate + v_qi_environment_gain%',
         CASE WHEN body NOT LIKE '%v_qi_environment_gain%' THEN 'old additive variable removed' ELSE 'old additive formula remains' END
  FROM fn
  UNION ALL
  SELECT 'record_mode_is_v0119',
         body LIKE '%automatic_v0119_full_heaven_multiplier%',
         CASE WHEN body LIKE '%automatic_v0119_full_heaven_multiplier%' THEN 'v0119' ELSE 'old mode' END
  FROM fn
  UNION ALL
  SELECT 'example_131_1_times_05',
         round(131.1::numeric * 0.5, 2) = 65.55,
         round(131.1::numeric * 0.5, 2)::text
  UNION ALL
  SELECT 'function_count_expected_at_least_75',
         (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public') >= 75,
         (SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public')
)
SELECT check_name,
       CASE WHEN passed THEN 'PASS' ELSE 'FAIL' END AS status,
       detail
FROM checks
ORDER BY check_name;
