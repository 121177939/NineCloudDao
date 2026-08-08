-- 九霄问道 · V2.1.1 CACHE108 · SQL237
-- 世界BOSS镇魔令发奖函数签名兼容热修。
-- 原因：bwboss01_simulate_run 中失败奖励表达式 floor(...) 使 CASE 推导为 numeric，
--       而 SQL233 仅定义 bwboss01_grant_token(uuid,bigint)，PostgreSQL 函数解析不会隐式匹配 numeric -> bigint。
-- 修复：新增内部 numeric 重载，向下取整后转调原 bigint 权威函数。
-- 本SQL不改客户端、不改GM、不改CACHE；SQL236是否已执行均不影响本修复。

begin;

lock table public.jiuxiao_app_release_control in row exclusive mode;

do $precheck$
declare v_cache integer; v_release text;
begin
  if to_regclass('public.jiuxiao_app_release_control') is null then
    raise exception 'SQL237_PRECHECK_RELEASE_CONTROL_MISSING';
  end if;
  if to_regclass('public.world_boss_reward_ledger_bwboss01') is null then
    raise exception 'SQL237_PRECHECK_WBOSS_REWARD_LEDGER_MISSING_SQL233_REQUIRED';
  end if;
  if to_regprocedure('public.bwboss01_grant_token(uuid,bigint)') is null then
    raise exception 'SQL237_PRECHECK_GRANT_TOKEN_BIGINT_MISSING_SQL233_REQUIRED';
  end if;
  if to_regprocedure('public.bwboss01_simulate_run(uuid)') is null then
    raise exception 'SQL237_PRECHECK_SIMULATE_RUN_MISSING_SQL233_REQUIRED';
  end if;
  select release_name,cache_epoch into v_release,v_cache
  from public.jiuxiao_app_release_control where singleton_id=1 for update;
  if not found then raise exception 'SQL237_PRECHECK_RELEASE_ROW_MISSING'; end if;
  if coalesce(v_cache,-1)>108 then
    raise exception 'SQL237_PRECHECK_NEWER_RELEASE_BLOCK:%/%',v_release,v_cache;
  end if;
end
$precheck$;

create or replace function public.bwboss01_grant_token(p_character_id uuid,p_amount numeric)
returns bigint
language plpgsql
security definer
set search_path=''
as $$
declare v_amount bigint;
begin
  if p_amount is null or p_amount<=0 then return 0; end if;
  -- 世界BOSS镇魔令只允许整数；兼容 numeric 调用时统一向下取整。
  v_amount:=floor(p_amount)::bigint;
  if v_amount<=0 then return 0; end if;
  return public.bwboss01_grant_token(p_character_id,v_amount);
end $$;

comment on function public.bwboss01_grant_token(uuid,numeric) is
'SQL237 V2.1.1 CACHE108 BWBOSS_TOKEN_SIGFIX1: numeric compatibility overload; floor to bigint then delegate to authoritative uuid,bigint grant function.';

-- 与原 bigint 发奖函数保持相同的内部权限边界：客户端不可直接调用。
revoke all on function public.bwboss01_grant_token(uuid,numeric) from public,anon,authenticated;

commit;
notify pgrst,'reload schema';

select jsonb_build_object(
  'success',true,
  'sql',237,
  'feature','BWBOSS_TOKEN_SIGNATURE_COMPAT',
  'bigint_signature',to_regprocedure('public.bwboss01_grant_token(uuid,bigint)') is not null,
  'numeric_signature',to_regprocedure('public.bwboss01_grant_token(uuid,numeric)') is not null,
  'release_control_unchanged',(select release_name from public.jiuxiao_app_release_control where singleton_id=1),
  'cache_epoch_unchanged',(select cache_epoch from public.jiuxiao_app_release_control where singleton_id=1),
  'next','RUN_V2.1.1_CACHE108_SQL237_GATE',
  'next_sql',238
) as sql237_install_result;
