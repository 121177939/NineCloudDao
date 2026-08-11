-- 九霄问道 SQL263 · V2.2.0 CACHE135
-- B模块：天道AI多模型调度器 GM 指标接入
-- 不修改人物/探索/经济/关系规则；只新增 ADMIN9 只读指标 RPC。
-- 基线要求：SQL262 ONLINE / 300探索故事已存在。
-- 成功后：SQL263 ONLINE / NEXT SQL264

begin;

do $precheck$
begin
  if to_regclass('public.tiandao_ai_decisions_v259') is null then raise exception 'SQL263_PRECHECK_AI_DECISIONS_MISSING'; end if;
  if to_regclass('public.exploration_story_defs_v262') is null then raise exception 'SQL263_PRECHECK_SQL262_EXPLORATION_MISSING'; end if;
  if (select count(*) from public.exploration_story_defs_v262 where enabled) <> 300 then raise exception 'SQL263_PRECHECK_SQL262_STORY_COUNT'; end if;
  if to_regprocedure('public.admin_whoami_v1()') is null then raise exception 'SQL263_PRECHECK_ADMIN_WHOAMI_MISSING'; end if;
  if to_regprocedure('public.server_personality_v1(jsonb)') is null then raise exception 'SQL263_PRECHECK_LOCAL_FALLBACK_MISSING'; end if;
end
$precheck$;

create or replace function public.admin9_get_tiandao_ai_router_v263()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_last jsonb;
  v_zhipu bigint;
  v_cloudflare bigint;
  v_local bigint;
  v_total bigint;
  v_cloud_fallback bigint;
begin
  perform public.admin_whoami_v1();

  select jsonb_build_object(
    'engine',d.engine,
    'provider',case when d.engine='zhipu_glm' then 'zhipu' when d.engine='cloudflare_workers_ai' then 'cloudflare' when d.engine='server_personality_v1' then 'local' else d.engine end,
    'model',d.model,
    'latency_ms',d.latency_ms,
    'failure_reason',nullif(d.failure_reason,''),
    'decision',d.decision,
    'created_at',d.created_at
  ) into v_last
  from public.tiandao_ai_decisions_v259 d
  order by d.created_at desc limit 1;

  select count(*) into v_zhipu from public.tiandao_ai_decisions_v259 d where d.created_at>clock_timestamp()-interval '24 hours' and d.engine='zhipu_glm';
  select count(*) into v_cloudflare from public.tiandao_ai_decisions_v259 d where d.created_at>clock_timestamp()-interval '24 hours' and d.engine='cloudflare_workers_ai';
  select count(*) into v_local from public.tiandao_ai_decisions_v259 d where d.created_at>clock_timestamp()-interval '24 hours' and d.engine='server_personality_v1';
  select count(*) into v_total from public.tiandao_ai_decisions_v259 d where d.created_at>clock_timestamp()-interval '24 hours';
  select count(*) into v_cloud_fallback from public.tiandao_ai_decisions_v259 d where d.created_at>clock_timestamp()-interval '24 hours' and d.engine='cloudflare_workers_ai' and coalesce(d.failure_reason,'') like '%zhipu:%';

  return jsonb_build_object(
    'status','ok',
    'sql','SQL263',
    'module','B-TIANDAO-AI-ROUTER-V1.1-A-MERGE',
    'primary','zhipu',
    'primary_model_default','glm-4.7-flash',
    'cloud_fallback','cloudflare',
    'cloudflare_model_default','@cf/qwen/qwen3-30b-a3b-fp8',
    'local_fallback','server_personality_v1',
    'last',coalesce(v_last,'{}'::jsonb),
    'counts_24h',jsonb_build_object(
      'zhipu',v_zhipu,
      'cloudflare',v_cloudflare,
      'local_fallback',v_local,
      'total',v_total,
      'cloudflare_after_zhipu_failure',v_cloud_fallback
    )
  );
end $$;

revoke all on function public.admin9_get_tiandao_ai_router_v263() from public,anon,authenticated;
grant execute on function public.admin9_get_tiandao_ai_router_v263() to authenticated;

do $gate$
declare
  v_exposed int;
  v_def text;
begin
  if to_regprocedure('public.admin9_get_tiandao_ai_router_v263()') is null then raise exception 'SQL263_GATE_RPC_MISSING'; end if;
  if not has_function_privilege('authenticated','public.admin9_get_tiandao_ai_router_v263()','EXECUTE') then raise exception 'SQL263_GATE_AUTH_EXECUTE_MISSING'; end if;
  select count(*) into v_exposed from information_schema.routine_privileges where specific_schema='public' and routine_name='admin9_get_tiandao_ai_router_v263' and grantee in('anon','PUBLIC') and privilege_type='EXECUTE';
  if v_exposed<>0 then raise exception 'SQL263_GATE_RPC_EXPOSED:%',v_exposed; end if;
  select pg_get_functiondef(to_regprocedure('public.admin9_get_tiandao_ai_router_v263()')) into v_def;
  if position('zhipu_glm' in v_def)=0 or position('cloudflare_workers_ai' in v_def)=0 or position('server_personality_v1' in v_def)=0 then raise exception 'SQL263_GATE_ROUTER_ENGINE_METRICS_MISSING'; end if;
  if (select count(*) from public.exploration_story_defs_v262 where enabled)<>300 then raise exception 'SQL263_GATE_SQL262_STORIES_CHANGED'; end if;
end
$gate$;

commit;

select jsonb_build_object(
  'sql',263,
  'gate','SQL263_GATE_PASSED',
  'release','V2.2.0 CACHE135',
  'module','B天道AI多模型调度器：GLM-4.7-Flash → Cloudflare → server_personality_v1',
  'database_rule_changes',false,
  'gm','ADMIN9 R39',
  'edge','tiandao-ai CACHE135 R5 必须部署',
  'next_sql',264
) as sql263_install_result;
