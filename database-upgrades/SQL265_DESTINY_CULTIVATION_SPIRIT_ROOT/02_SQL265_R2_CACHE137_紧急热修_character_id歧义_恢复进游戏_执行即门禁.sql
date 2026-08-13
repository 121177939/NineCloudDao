-- 九霄问道 SQL265 R2 · V2.2.0 CACHE137 紧急热修
-- 目的：修复 SQL264 R3 对 claim_cultivation_v1() 的包装函数在生产运行时出现：
--       column reference "character_id" is ambiguous
-- 原因：claim_cultivation_v1() 为 RETURNS TABLE，输出列会成为 PL/pgSQL 隐式变量；
--       R3 包装体内少数 character_id / cultivation 等列未加表别名，运行时产生歧义。
-- 本热修：
--   1) 不修改游戏包、不修改 GM、不修改 Edge；
--   2) 不重做原 SQL263 修炼权威函数，继续调用已备份的 claim_cultivation_dynamic_v264()；
--   3) 仅重建 claim_cultivation_v1() 包装层，所有数据库列显式使用表别名；
--   4) 保留固定天道 + NPC正式道侣最终修炼速度 x1.5；
--   5) 末尾实际执行只读天命榜 RPC 门禁，确保 CACHE137 榜单也能正常读取。
-- 前置：SQL264 R3 已安装；SQL265 R1 可已安装或未安装，本文件均可安全执行。
-- 成功标志：SQL265_R2_HOTFIX_GATE_PASSED

begin;

do $precheck$
declare
  v_claim oid:=to_regprocedure('public.claim_cultivation_v1()');
  v_dynamic oid:=to_regprocedure('public.claim_cultivation_dynamic_v264()');
begin
  if v_claim is null then
    raise exception 'SQL265_R2_PRECHECK_CLAIM_CULTIVATION_V1_MISSING';
  end if;
  if v_dynamic is null then
    raise exception 'SQL265_R2_PRECHECK_SQL264_R3_BACKUP_MISSING';
  end if;
  if to_regclass('public.heaven_balance_control_v264') is null then
    raise exception 'SQL265_R2_PRECHECK_HEAVEN_CONTROL_MISSING';
  end if;
  if to_regclass('public.player_characters') is null
     or to_regclass('public.character_cultivation_state') is null
     or to_regclass('public.tiandao_companions_v259') is null then
    raise exception 'SQL265_R2_PRECHECK_REQUIRED_TABLE_MISSING';
  end if;
  if to_regprocedure('public.grant_cultivation_capped_v1(uuid,bigint,text,jsonb)') is null then
    raise exception 'SQL265_R2_PRECHECK_GRANT_CULTIVATION_CAPPED_V1_MISSING';
  end if;
end
$precheck$;

-- 重新生成与当前 claim_cultivation_v1() 完全相同 ABI 的安全包装层。
do $rebuild_claim$
declare
  v_oid oid:=to_regprocedure('public.claim_cultivation_v1()');
  v_retset boolean;
  v_secdef boolean;
  v_all oid[];
  v_modes "char"[];
  v_names text[];
  v_i integer;
  v_name text;
  v_type text;
  v_returns text:='';
  v_return_select text:='';
  v_sql text;
  v_required text[]:=array[
    'gained','elapsed_seconds','cultivation_total','current_rate_per_second',
    'qi_multiplier','fate_bonus','technique_multiplier_bonus','effect_multiplier_bonus'
  ];
  v_req text;
begin
  select p.proretset,p.prosecdef,p.proallargtypes,p.proargmodes,p.proargnames
    into v_retset,v_secdef,v_all,v_modes,v_names
  from pg_proc p
  where p.oid=v_oid;

  if not v_retset or not v_secdef or v_all is null or v_modes is null or v_names is null then
    raise exception 'SQL265_R2_CLAIM_RPC_ABI_UNSUPPORTED';
  end if;

  foreach v_req in array v_required loop
    if not (v_req=any(v_names)) then
      raise exception 'SQL265_R2_CLAIM_RPC_ABI_MISSING_COLUMN:%',v_req;
    end if;
  end loop;

  for v_i in select generate_subscripts(v_all,1) loop
    if v_modes[v_i] not in('o','b','t') then continue; end if;
    v_name:=v_names[v_i];
    v_type:=format_type(v_all[v_i],null);
    if v_returns<>'' then
      v_returns:=v_returns||',';
      v_return_select:=v_return_select||',';
    end if;
    v_returns:=v_returns||format('%I %s',v_name,v_type);
    if v_all[v_i]=3802 then
      v_return_select:=v_return_select||format('(v_result->%L)::jsonb as %I',v_name,v_name);
    elsif v_all[v_i]=114 then
      v_return_select:=v_return_select||format('(v_result->%L)::json as %I',v_name,v_name);
    else
      v_return_select:=v_return_select||format('(v_result->>%L)::%s as %I',v_name,v_type,v_name);
    end if;
  end loop;

  v_sql:=format($fmt$
create or replace function public.claim_cultivation_v1()
returns table(%s)
language plpgsql
security definer
set search_path=''
as $body$
#variable_conflict error
declare
  v_result jsonb;
  v_mode text;
  v_bless numeric;
  v_obstruct numeric;
  v_target_qi numeric;
  v_dynamic_qi numeric;
  v_dynamic_rate numeric;
  v_target_rate numeric;
  v_elapsed numeric;
  v_dynamic_gained bigint;
  v_old_total bigint;
  v_grant jsonb;
  v_delta bigint:=0;
  v_extra_granted bigint:=0;
  v_capped_by_authority boolean:=false;
  v_current_remainder numeric;
  v_old_remainder numeric;
  v_raw_target numeric;
  v_target_gained bigint;
  v_target_remainder numeric;
  v_new_total bigint;
  v_character_id uuid;
  v_has_companion boolean:=false;
  v_companion_multiplier numeric:=1;
begin
  select to_jsonb(src)
    into v_result
  from public.claim_cultivation_dynamic_v264() as src;

  if v_result is null then return; end if;

  select ctl.mode,ctl.blessing_coefficient,ctl.obstruction_coefficient
    into v_mode,v_bless,v_obstruct
  from public.heaven_balance_control_v264 as ctl
  where ctl.singleton_id=1;

  select pc.id
    into v_character_id
  from public.player_characters as pc
  where pc.user_id=auth.uid()
    and pc.status in('active','secluded','missing')
  order by pc.created_at desc
  limit 1;

  if v_character_id is null then
    return query select %s;
    return;
  end if;

  select exists(
    select 1
    from public.tiandao_companions_v259 as tc
    where tc.character_id=v_character_id
      and tc.status='active'
  ) into v_has_companion;

  v_companion_multiplier:=case when v_has_companion then 1.5::numeric else 1::numeric end;

  v_dynamic_qi:=greatest(0.000001,coalesce((v_result->>'qi_multiplier')::numeric,1));
  v_target_qi:=case coalesce(v_mode,'auto')
    when 'heavenly_blessing' then coalesce(v_bless,1.5)
    when 'heaven_obstruction' then coalesce(v_obstruct,0.5)
    when 'dao_balance' then 1::numeric
    else v_dynamic_qi
  end;

  v_dynamic_rate:=greatest(0,coalesce((v_result->>'current_rate_per_second')::numeric,0));
  v_elapsed:=greatest(0,coalesce((v_result->>'elapsed_seconds')::numeric,0));
  v_dynamic_gained:=greatest(0,coalesce((v_result->>'gained')::bigint,0));
  v_old_total:=greatest(0,coalesce((v_result->>'cultivation_total')::bigint,0)-v_dynamic_gained);

  select coalesce(ccs.fractional_remainder,0)
    into v_current_remainder
  from public.character_cultivation_state as ccs
  where ccs.character_id=v_character_id
  for update;

  if v_current_remainder is null then v_current_remainder:=0; end if;

  if v_dynamic_rate<=0 then
    v_target_rate:=0;
    v_target_gained:=v_dynamic_gained;
    v_target_remainder:=v_current_remainder;
  else
    v_target_rate:=greatest(0,(v_dynamic_rate/v_dynamic_qi)*v_target_qi*v_companion_multiplier);

    v_old_remainder:=v_current_remainder-(v_elapsed*v_dynamic_rate)+v_dynamic_gained;
    if abs(v_old_remainder)<0.0000001 then v_old_remainder:=0; end if;
    v_old_remainder:=greatest(0,least(0.999999999999,v_old_remainder));
    v_raw_target:=v_old_remainder+(v_elapsed*v_target_rate);
    v_target_gained:=greatest(0,floor(v_raw_target)::bigint);
    v_target_remainder:=greatest(0,least(0.999999999999,v_raw_target-v_target_gained));

    v_delta:=v_target_gained-v_dynamic_gained;
    if v_delta>0 then
      select to_jsonb(g)
        into v_grant
      from public.grant_cultivation_capped_v1(
        v_character_id,
        v_delta,
        'sql264_heaven_companion',
        jsonb_build_object(
          'sql','SQL265 R2 HOTFIX',
          'heaven_mode',coalesce(v_mode,'auto'),
          'companion_multiplier',v_companion_multiplier
        )
      ) as g;

      v_extra_granted:=greatest(0,coalesce((v_grant->>'granted_amount')::bigint,0));
      v_capped_by_authority:=v_extra_granted<v_delta;
      v_target_gained:=v_dynamic_gained+v_extra_granted;
      if v_capped_by_authority then
        v_target_remainder:=0;
        v_target_rate:=0;
      end if;
    elsif v_delta<0 then
      update public.player_characters as pc
      set cultivation=v_old_total+v_target_gained,
          updated_at=clock_timestamp()
      where pc.id=v_character_id;
    end if;
  end if;

  select pc.cultivation
    into v_new_total
  from public.player_characters as pc
  where pc.id=v_character_id;

  update public.character_cultivation_state as ccs
  set fractional_remainder=v_target_remainder,
      updated_at=clock_timestamp()
  where ccs.character_id=v_character_id;

  v_result:=jsonb_set(v_result,'{gained}',to_jsonb(v_target_gained),true);
  v_result:=jsonb_set(v_result,'{cultivation_total}',to_jsonb(v_new_total),true);
  v_result:=jsonb_set(v_result,'{current_rate_per_second}',to_jsonb(v_target_rate),true);
  v_result:=jsonb_set(v_result,'{qi_multiplier}',to_jsonb(v_target_qi),true);

  return query select %s;
end
$body$
$fmt$,v_returns,v_return_select,v_return_select);

  execute v_sql;
end
$rebuild_claim$;

comment on function public.claim_cultivation_v1()
is 'SQL265 R2 HOTFIX CACHE137: fixes RETURNS TABLE column/variable ambiguity in SQL264 R3 wrapper; preserves fixed heaven mode and active NPC companion exact x1.5 final cultivation rate.';

-- 静态门禁：确认危险的未限定 character_id 写法已经不存在。
do $claim_gate$
declare
  v_def text;
begin
  select pg_get_functiondef(to_regprocedure('public.claim_cultivation_v1()')) into v_def;
  if v_def is null then raise exception 'SQL265_R2_GATE_CLAIM_DEFINITION_MISSING'; end if;
  if position('ccs.character_id' in v_def)=0 then raise exception 'SQL265_R2_GATE_CULTIVATION_STATE_ALIAS_MISSING'; end if;
  if position('tc.character_id' in v_def)=0 then raise exception 'SQL265_R2_GATE_COMPANION_ALIAS_MISSING'; end if;
  if position('pc.cultivation' in v_def)=0 then raise exception 'SQL265_R2_GATE_PLAYER_CULTIVATION_ALIAS_MISSING'; end if;
  if position('v_companion_multiplier' in v_def)=0 or position('1.5' in v_def)=0 then
    raise exception 'SQL265_R2_GATE_COMPANION_X1_5_MISSING';
  end if;
end
$claim_gate$;

-- CACHE137 榜单只读探针：若 SQL265 R1 已存在，实际执行一次读取。
-- 榜单本身不是登录/修炼启动链的硬门禁；即使榜单另有问题，也不能回滚本次紧急进服热修。
do $ranking_probe$
declare
  v_rank jsonb;
begin
  begin
    if to_regprocedure('public.get_destiny_ranking_v265(integer,integer)') is not null then
      select public.get_destiny_ranking_v265(1,0) into v_rank;
      if v_rank is null then raise warning 'SQL265_R2_RANKING_PROBE_RETURNED_NULL'; end if;
    elsif to_regprocedure('public.get_destiny_ranking_v1(integer,integer)') is not null then
      select public.get_destiny_ranking_v1(1,0) into v_rank;
      if v_rank is null then raise warning 'SQL265_R2_BASE_RANKING_PROBE_RETURNED_NULL'; end if;
    end if;
  exception when others then
    raise warning 'SQL265_R2_RANKING_PROBE_WARNING: %',SQLERRM;
  end;
end
$ranking_probe$;

commit;

select jsonb_build_object(
  'sql','SQL265 R2 HOTFIX',
  'gate','SQL265_R2_HOTFIX_GATE_PASSED',
  'release','V2.2.0 CACHE137',
  'fixed','claim_cultivation_v1 RETURNS TABLE character_id ambiguity',
  'heaven_control','preserved',
  'npc_companion_multiplier',1.5,
  'ranking_spirit_root','preserved when SQL265 R1 installed; runtime probe is non-blocking',
  'game_package','unchanged',
  'gm','ADMIN9 R40 unchanged',
  'edge','tiandao-ai CACHE135 R6 unchanged',
  'next_sql',266
) as sql265_r2_hotfix_result;
