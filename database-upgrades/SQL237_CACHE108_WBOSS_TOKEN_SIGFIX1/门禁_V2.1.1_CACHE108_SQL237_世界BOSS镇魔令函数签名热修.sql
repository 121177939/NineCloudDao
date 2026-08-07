-- 九霄问道 · V2.1.1 CACHE108 · SQL237 制度门禁
-- SQL237升级成功后执行；不修改客户端CACHE，只确认世界BOSS镇魔令发奖签名修复已就绪。

begin;
lock table public.jiuxiao_app_release_control in row exclusive mode;

do $gate$
declare
  v_bigint oid;
  v_numeric oid;
  v_numeric_def text;
  v_numeric_comment text;
begin
  v_bigint:=to_regprocedure('public.bwboss01_grant_token(uuid,bigint)');
  if v_bigint is null then raise exception 'SQL237_GATE_GRANT_TOKEN_BIGINT_MISSING'; end if;

  v_numeric:=to_regprocedure('public.bwboss01_grant_token(uuid,numeric)');
  if v_numeric is null then raise exception 'SQL237_GATE_GRANT_TOKEN_NUMERIC_MISSING'; end if;

  select pg_get_functiondef(v_numeric),obj_description(v_numeric,'pg_proc')
  into v_numeric_def,v_numeric_comment;

  if coalesce(v_numeric_comment,'') not like '%SQL237 V2.1.1 CACHE108 BWBOSS_TOKEN_SIGFIX1%' then
    raise exception 'SQL237_GATE_MARKER_MISSING';
  end if;
  if position('floor(p_amount)' in v_numeric_def)=0 then
    raise exception 'SQL237_GATE_NUMERIC_FLOOR_CONVERSION_MISSING';
  end if;
  if position('bwboss01_grant_token(p_character_id,v_amount)' in replace(v_numeric_def,' ',''))=0 then
    -- pg_get_functiondef 排版可能不同；下面再用宽松检查兜底。
    if position('bwboss01_grant_token' in v_numeric_def)=0 or position('v_amount' in v_numeric_def)=0 then
      raise exception 'SQL237_GATE_DELEGATION_TO_BIGINT_MISSING';
    end if;
  end if;

  if has_function_privilege('anon',v_numeric,'EXECUTE') or has_function_privilege('authenticated',v_numeric,'EXECUTE') then
    raise exception 'SQL237_GATE_NUMERIC_OVERLOAD_CLIENT_EXECUTE_MUST_BE_REVOKED';
  end if;

  if to_regprocedure('public.bwboss01_simulate_run(uuid)') is null then
    raise exception 'SQL237_GATE_SIMULATE_RUN_MISSING';
  end if;
  if to_regclass('public.world_boss_reward_ledger_bwboss01') is null then
    raise exception 'SQL237_GATE_REWARD_LEDGER_MISSING';
  end if;
end
$gate$;

-- 数据库热修，不提升CACHE；只更新发布提示文本与更新时间。
update public.jiuxiao_app_release_control
set notice_text='V2.1.1 CACHE108：SQL237修复世界BOSS开战结算镇魔令发奖 numeric/bigint 函数签名不匹配；游戏与GM无需重新部署。',
    updated_at=clock_timestamp()
where singleton_id=1;

commit;
notify pgrst,'reload schema';

select jsonb_build_object(
  'success',true,
  'gate','SQL237_GATE_PASSED',
  'sql',237,
  'release_name',(select release_name from public.jiuxiao_app_release_control where singleton_id=1),
  'cache_epoch',(select cache_epoch from public.jiuxiao_app_release_control where singleton_id=1),
  'grant_bigint_ready',to_regprocedure('public.bwboss01_grant_token(uuid,bigint)') is not null,
  'grant_numeric_ready',to_regprocedure('public.bwboss01_grant_token(uuid,numeric)') is not null,
  'next_sql',238
) as sql237_gate_result;
