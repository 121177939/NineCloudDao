-- 九霄问道 SQL264 R2 · V2.2.0 CACHE136 / ADMIN9 R40
-- 1) GM 可将天道动态均衡切换为：自动 / 固定大道均衡 / 固定天道福泽 / 固定天道阻滞。
-- 2) 玩家与天道人物 NPC 形成正式 active 道侣期间，自动获得修炼倍率 +50%（基础 1/秒 -> 1.5/秒）；关系 ended/删除后自动失效。
-- 3) 不改变 AI 权限边界；AI 仍不能直接修改修为、经济、关系或世界状态。
-- 基线要求：SQL263 ONLINE / ADMIN9 R39 / CACHE135。
-- R2修复：移除错误的“必须直接调用 get_heaven_balance_v1”门禁，改为包装真实 claim_cultivation_v1 权威结算。
-- 成功后：SQL264_GATE_PASSED / NEXT SQL265。

begin;

-- ---------- precheck ----------
do $precheck$
declare
  v_heaven oid:=to_regprocedure('public.get_heaven_balance_v1()');
  v_claim oid:=to_regprocedure('public.claim_cultivation_v1()');
  v_claim_retset boolean;
  v_claim_secdef boolean;
  v_claim_all oid[];
  v_claim_modes "char"[];
  v_claim_names text[];
  v_required text[]:=array[
    'gained','elapsed_seconds','cultivation_total','current_rate_per_second',
    'qi_multiplier','fate_bonus','technique_multiplier_bonus','effect_multiplier_bonus'
  ];
  v_req text;
begin
  if to_regclass('public.tiandao_companions_v259') is null then raise exception 'SQL264_PRECHECK_TIANDAO_COMPANIONS_MISSING'; end if;
  if to_regclass('public.character_cultivation_effects') is null then raise exception 'SQL264_PRECHECK_CULTIVATION_EFFECTS_MISSING'; end if;
  if to_regclass('public.character_cultivation_state') is null then raise exception 'SQL264_PRECHECK_CULTIVATION_STATE_MISSING'; end if;
  if to_regclass('public.player_characters') is null then raise exception 'SQL264_PRECHECK_PLAYER_CHARACTERS_MISSING'; end if;
  if v_heaven is null then raise exception 'SQL264_PRECHECK_HEAVEN_BALANCE_RPC_MISSING'; end if;
  if v_claim is null then raise exception 'SQL264_PRECHECK_CLAIM_CULTIVATION_RPC_MISSING'; end if;
  if to_regprocedure('public.admin_whoami_v1()') is null then raise exception 'SQL264_PRECHECK_ADMIN_WHOAMI_MISSING'; end if;
  if to_regprocedure('public.grant_cultivation_capped_v1(uuid,bigint,text,jsonb)') is null then raise exception 'SQL264_PRECHECK_CAPPED_GRANT_RPC_MISSING'; end if;

  if exists (
    select 1 from unnest(array[
      'character_id','display_name','source_type','source_key','flat_rate_per_second','multiplier_bonus',
      'starts_at','expires_at','is_active','metadata','created_at'
    ]) as r(col)
    where not exists (
      select 1 from information_schema.columns c
      where c.table_schema='public' and c.table_name='character_cultivation_effects' and c.column_name=r.col
    )
  ) then raise exception 'SQL264_PRECHECK_CULTIVATION_EFFECTS_COLUMNS_MISSING'; end if;

  if exists (
    select 1 from unnest(array['character_id','npc_id','status']) as r(col)
    where not exists (
      select 1 from information_schema.columns c
      where c.table_schema='public' and c.table_name='tiandao_companions_v259' and c.column_name=r.col
    )
  ) then raise exception 'SQL264_PRECHECK_TIANDAO_COMPANION_COLUMNS_MISSING'; end if;

  if exists (
    select 1 from unnest(array['character_id','fractional_remainder','updated_at']) as r(col)
    where not exists (
      select 1 from information_schema.columns c
      where c.table_schema='public' and c.table_name='character_cultivation_state' and c.column_name=r.col
    )
  ) then raise exception 'SQL264_PRECHECK_CULTIVATION_STATE_COLUMNS_MISSING'; end if;

  if exists (
    select 1 from unnest(array['id','user_id','realm_stage_id','cultivation','status','created_at','updated_at']) as r(col)
    where not exists (
      select 1 from information_schema.columns c
      where c.table_schema='public' and c.table_name='player_characters' and c.column_name=r.col
    )
  ) then raise exception 'SQL264_PRECHECK_PLAYER_CHARACTER_COLUMNS_MISSING'; end if;

  select p.proretset,p.prosecdef,p.proallargtypes,p.proargmodes,p.proargnames
    into v_claim_retset,v_claim_secdef,v_claim_all,v_claim_modes,v_claim_names
  from pg_proc p where p.oid=v_claim;

  if not v_claim_retset or v_claim_all is null or v_claim_modes is null or v_claim_names is null then
    raise exception 'SQL264_PRECHECK_CLAIM_ABI_UNSUPPORTED_EXPECTED_RETURNS_TABLE';
  end if;
  foreach v_req in array v_required loop
    if not (v_req=any(v_claim_names)) then
      raise exception 'SQL264_PRECHECK_CLAIM_ABI_MISSING_COLUMN:%',v_req;
    end if;
  end loop;
end
$precheck$;

-- ---------- global heaven control ----------
create table if not exists public.heaven_balance_control_v264(
  singleton_id smallint primary key default 1 check(singleton_id=1),
  mode text not null default 'auto' check(mode in('auto','dao_balance','heavenly_blessing','heaven_obstruction')),
  blessing_coefficient numeric(8,4) not null default 1.5000 check(blessing_coefficient between 1.0000 and 5.0000),
  obstruction_coefficient numeric(8,4) not null default 0.5000 check(obstruction_coefficient between 0.1000 and 1.0000),
  updated_at timestamptz not null default clock_timestamp(),
  updated_by uuid
);
insert into public.heaven_balance_control_v264(singleton_id) values(1) on conflict(singleton_id) do nothing;
revoke all on table public.heaven_balance_control_v264 from anon,authenticated;

create table if not exists public.heaven_balance_control_audit_v264(
  id bigint generated always as identity primary key,
  request_id uuid not null unique,
  admin_user_id uuid,
  old_value jsonb not null,
  new_value jsonb not null,
  reason text not null,
  created_at timestamptz not null default clock_timestamp()
);
revoke all on table public.heaven_balance_control_audit_v264 from anon,authenticated;

-- ---------- preserve the original dynamic heaven function once ----------
do $backup_heaven$
declare
  v_oid oid:=to_regprocedure('public.get_heaven_balance_v1()');
  v_def text;
  v_backup text;
begin
  if to_regprocedure('public.get_heaven_balance_dynamic_v264()') is null then
    select pg_get_functiondef(v_oid) into v_def;
    if v_def is null or position('FUNCTION public.get_heaven_balance_v1()' in v_def)=0 then
      raise exception 'SQL264_HEAVEN_BACKUP_DEFINITION_UNEXPECTED';
    end if;
    v_backup:=replace(v_def,'FUNCTION public.get_heaven_balance_v1()','FUNCTION public.get_heaven_balance_dynamic_v264()');
    execute v_backup;
    execute 'revoke all on function public.get_heaven_balance_dynamic_v264() from public,anon';
    execute 'grant execute on function public.get_heaven_balance_dynamic_v264() to authenticated';
  end if;
end
$backup_heaven$;

-- ---------- replace original function body while preserving its OID/signature ----------
-- This dynamic builder preserves the production RETURNS TABLE ABI exactly, so existing server callers continue to hit the same function OID.
do $wrap_heaven$
declare
  v_oid oid:=to_regprocedure('public.get_heaven_balance_v1()');
  v_retset boolean;
  v_secdef boolean;
  v_vol "char";
  v_all oid[];
  v_modes "char"[];
  v_names text[];
  v_i integer;
  v_returns text:='';
  v_select text:='';
  v_name text;
  v_type text;
  v_fixed_expr text:='case ctl.mode when ''heavenly_blessing'' then ctl.blessing_coefficient when ''heaven_obstruction'' then ctl.obstruction_coefficient else 1::numeric end';
  v_security text;
  v_volatility text;
  v_sql text;
  v_required text[]:=array['status_code','status_name','reason_label','coefficient','world_qi_base','qi_gain_per_second'];
  v_req text;
begin
  select p.proretset,p.prosecdef,p.provolatile,p.proallargtypes,p.proargmodes,p.proargnames
    into v_retset,v_secdef,v_vol,v_all,v_modes,v_names
  from pg_proc p where p.oid=v_oid;

  if not v_retset or v_all is null or v_modes is null or v_names is null then
    raise exception 'SQL264_HEAVEN_RPC_ABI_UNSUPPORTED_EXPECTED_RETURNS_TABLE';
  end if;
  foreach v_req in array v_required loop
    if not (v_req=any(v_names)) then raise exception 'SQL264_HEAVEN_RPC_ABI_MISSING_COLUMN:%',v_req; end if;
  end loop;

  for v_i in select generate_subscripts(v_all,1) loop
    if v_modes[v_i] not in('o','b','t') then continue; end if;
    v_name:=v_names[v_i];
    v_type:=format_type(v_all[v_i],null);
    if v_returns<>'' then v_returns:=v_returns||','; v_select:=v_select||','; end if;
    v_returns:=v_returns||format('%I %s',v_name,v_type);

    if v_name='status_code' then
      v_select:=v_select||format('(case when ctl.mode=''auto'' then d.%I else ctl.mode end)::%s as %I',v_name,v_type,v_name);
    elsif v_name='status_name' then
      v_select:=v_select||format('(case when ctl.mode=''auto'' then d.%I when ctl.mode=''dao_balance'' then ''大道均衡'' when ctl.mode=''heavenly_blessing'' then ''天道福泽'' else ''天道阻滞'' end)::%s as %I',v_name,v_type,v_name);
    elsif v_name='reason_label' then
      v_select:=v_select||format('(case when ctl.mode=''auto'' then d.%I when ctl.mode=''dao_balance'' then ''GM固定：大道均衡，不再按全服境界差动态变化'' when ctl.mode=''heavenly_blessing'' then ''GM固定：天道福泽，使用后台固定福泽倍率'' else ''GM固定：天道阻滞，使用后台固定阻滞倍率'' end)::%s as %I',v_name,v_type,v_name);
    elsif v_name in('coefficient','qi_multiplier') then
      v_select:=v_select||format('(case when ctl.mode=''auto'' then d.%I else %s end)::%s as %I',v_name,v_fixed_expr,v_type,v_name);
    elsif v_name='qi_gain_per_second' then
      v_select:=v_select||format('(case when ctl.mode=''auto'' then d.%I else coalesce(d.world_qi_base,1)::numeric*(%s) end)::%s as %I',v_name,v_fixed_expr,v_type,v_name);
    else
      v_select:=v_select||format('d.%I',v_name);
    end if;
  end loop;

  v_security:='SECURITY DEFINER';
  v_volatility:=case v_vol when 'i' then 'IMMUTABLE' when 's' then 'STABLE' else 'VOLATILE' end;
  v_sql:=format($fmt$
    create or replace function public.get_heaven_balance_v1()
    returns table(%s)
    language sql
    %s
    %s
    set search_path=''
    as $body$
      with ctl as (
        select mode,blessing_coefficient,obstruction_coefficient
        from public.heaven_balance_control_v264 where singleton_id=1
      ), dyn as (
        select * from public.get_heaven_balance_dynamic_v264()
      )
      select %s from dyn d cross join ctl
    $body$
  $fmt$,v_returns,v_volatility,v_security,v_select);
  execute v_sql;
end
$wrap_heaven$;

comment on function public.get_heaven_balance_v1() is 'SQL264 V2.2.0 CACHE136: dynamic heaven balance with ADMIN9 fixed-mode override; original preserved as get_heaven_balance_dynamic_v264().';

-- ---------- authoritative cultivation wrapper ----------
-- Production SQL263 claim_cultivation_v1 does not have to call get_heaven_balance_v1 by name.
-- SQL264 therefore wraps the real settlement RPC itself:
--   * auto mode keeps the original SQL263 result exactly;
--   * fixed heaven mode mathematically re-bases the just-settled interval to the selected qi multiplier;
--   * active NPC companion multiplies the final cultivation speed by exactly 1.5.
-- The original production function is preserved privately as claim_cultivation_dynamic_v264().
do $backup_claim$
declare
  v_oid oid:=to_regprocedure('public.claim_cultivation_v1()');
  v_def text;
  v_backup text;
begin
  if to_regprocedure('public.claim_cultivation_dynamic_v264()') is null then
    select pg_get_functiondef(v_oid) into v_def;
    if v_def is null or position('FUNCTION public.claim_cultivation_v1()' in v_def)=0 then
      raise exception 'SQL264_CLAIM_BACKUP_DEFINITION_UNEXPECTED';
    end if;
    v_backup:=replace(v_def,'FUNCTION public.claim_cultivation_v1()','FUNCTION public.claim_cultivation_dynamic_v264()');
    execute v_backup;
  end if;
end
$backup_claim$;

do $wrap_claim$
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
  from pg_proc p where p.oid=v_oid;

  if not v_retset or not v_secdef or v_all is null or v_modes is null or v_names is null then
    raise exception 'SQL264_CLAIM_RPC_ABI_UNSUPPORTED';
  end if;
  foreach v_req in array v_required loop
    if not (v_req=any(v_names)) then raise exception 'SQL264_CLAIM_RPC_ABI_MISSING_COLUMN:%',v_req; end if;
  end loop;

  for v_i in select generate_subscripts(v_all,1) loop
    if v_modes[v_i] not in('o','b','t') then continue; end if;
    v_name:=v_names[v_i];
    v_type:=format_type(v_all[v_i],null);
    if v_returns<>'' then v_returns:=v_returns||','; v_return_select:=v_return_select||','; end if;
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
  select to_jsonb(x) into v_result from public.claim_cultivation_dynamic_v264() x;
  if v_result is null then return; end if;

  select mode,blessing_coefficient,obstruction_coefficient
    into v_mode,v_bless,v_obstruct
  from public.heaven_balance_control_v264 where singleton_id=1;

  select pc.id
    into v_character_id
  from public.player_characters pc
  where pc.user_id=auth.uid() and pc.status in('active','secluded','missing')
  order by pc.created_at desc limit 1;

  if v_character_id is null then
    return query select %s;
    return;
  end if;

  select exists(
    select 1 from public.tiandao_companions_v259 tc
    where tc.character_id=v_character_id and tc.status='active'
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

  select coalesce(fractional_remainder,0)
    into v_current_remainder
  from public.character_cultivation_state
  where character_id=v_character_id
  for update;

  if v_current_remainder is null then v_current_remainder:=0; end if;

  -- If SQL263 reports rate=0 because the character has just reached a cultivation cap,
  -- keep the authoritative capped result. At a cap, additional multipliers cannot grant more cultivation.
  if v_dynamic_rate<=0 then
    v_target_rate:=0;
    v_target_gained:=v_dynamic_gained;
    v_target_remainder:=v_current_remainder;
  else
    v_target_rate:=greatest(0,(v_dynamic_rate/v_dynamic_qi)*v_target_qi*v_companion_multiplier);

    -- Reconstruct the fractional remainder immediately before the original SQL263 claim,
    -- then settle the exact same elapsed interval again with SQL264's target multiplier.
    v_old_remainder:=v_current_remainder-(v_elapsed*v_dynamic_rate)+v_dynamic_gained;
    if abs(v_old_remainder)<0.0000001 then v_old_remainder:=0; end if;
    v_old_remainder:=greatest(0,least(0.999999999999,v_old_remainder));
    v_raw_target:=v_old_remainder+(v_elapsed*v_target_rate);
    v_target_gained:=greatest(0,floor(v_raw_target)::bigint);
    v_target_remainder:=greatest(0,least(0.999999999999,v_raw_target-v_target_gained));

    -- Never implement the stage cap ourselves: cultivation_required is a stage floor, not the next-stage cap.
    -- For positive correction, reuse the existing production capped grant authority.
    -- For negative correction, only remove part of the cultivation just granted by SQL263, never below the pre-claim total.
    v_delta:=v_target_gained-v_dynamic_gained;
    if v_delta>0 then
      select to_jsonb(g) into v_grant
      from public.grant_cultivation_capped_v1(
        v_character_id,v_delta,'sql264_heaven_companion',
        jsonb_build_object('sql','SQL264 R2','heaven_mode',coalesce(v_mode,'auto'),'companion_multiplier',v_companion_multiplier)
      ) g;
      v_extra_granted:=greatest(0,coalesce((v_grant->>'granted_amount')::bigint,0));
      v_capped_by_authority:=v_extra_granted<v_delta;
      v_target_gained:=v_dynamic_gained+v_extra_granted;
      if v_capped_by_authority then
        v_target_remainder:=0;
        v_target_rate:=0;
      end if;
    elsif v_delta<0 then
      update public.player_characters
      set cultivation=v_old_total+v_target_gained,updated_at=clock_timestamp()
      where id=v_character_id;
    end if;
  end if;

  select cultivation into v_new_total from public.player_characters where id=v_character_id;

  update public.character_cultivation_state
  set fractional_remainder=v_target_remainder,updated_at=clock_timestamp()
  where character_id=v_character_id;

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
$wrap_claim$;

comment on function public.claim_cultivation_v1() is 'SQL264 R2 CACHE136: wraps SQL263 authoritative cultivation settlement; fixed heaven mode is applied to real gains and active NPC companion multiplies final rate exactly x1.5.';


-- ---------- NPC companion cultivation effect ----------
create or replace function public.sync_tiandao_companion_cultivation_v264(p_character_id uuid,p_active boolean,p_npc_id uuid default null)
returns void
language plpgsql
security definer
set search_path=''
as $$
declare v_ctid tid;
begin
  if p_character_id is null then return; end if;

  -- Disable every historical row first; only one canonical row may be active.
  update public.character_cultivation_effects
  set is_active=false,
      expires_at=coalesce(expires_at,clock_timestamp()),
      metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('v264_active',false,'v264_last_synced_at',clock_timestamp())
  where character_id=p_character_id and source_key='tiandao_companion_v264';

  if not coalesce(p_active,false) then return; end if;

  select ctid into v_ctid
  from public.character_cultivation_effects
  where character_id=p_character_id and source_key='tiandao_companion_v264'
  order by created_at asc,ctid asc limit 1;

  if v_ctid is null then
    insert into public.character_cultivation_effects(
      character_id,display_name,source_type,source_key,flat_rate_per_second,multiplier_bonus,
      starts_at,expires_at,is_active,metadata
    ) values(
      p_character_id,'NPC道侣同修','tiandao_companion','tiandao_companion_v264',0,0,
      clock_timestamp(),null,true,
      jsonb_build_object('v264_kind','npc_companion_cultivation','cultivation_multiplier',1.5,'authoritative_mode','claim_wrapper_exact','npc_id',p_npc_id,'v264_active',true)
    );
  else
    update public.character_cultivation_effects
    set display_name='NPC道侣同修',source_type='tiandao_companion',flat_rate_per_second=0,multiplier_bonus=0,
        starts_at=clock_timestamp(),expires_at=null,is_active=true,
        metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object('v264_kind','npc_companion_cultivation','cultivation_multiplier',1.5,'authoritative_mode','claim_wrapper_exact','npc_id',p_npc_id,'v264_active',true,'v264_last_synced_at',clock_timestamp())
    where ctid=v_ctid;
  end if;
end $$;

create or replace function public.tiandao_companion_cultivation_trigger_v264()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if tg_op='DELETE' then
    perform public.sync_tiandao_companion_cultivation_v264(old.character_id,false,old.npc_id);
    return old;
  end if;

  if tg_op='UPDATE' and old.character_id is distinct from new.character_id then
    perform public.sync_tiandao_companion_cultivation_v264(old.character_id,false,old.npc_id);
  end if;
  perform public.sync_tiandao_companion_cultivation_v264(new.character_id,new.status='active',new.npc_id);
  return new;
end $$;

drop trigger if exists trg_tiandao_companion_cultivation_v264_insert_delete on public.tiandao_companions_v259;
drop trigger if exists trg_tiandao_companion_cultivation_v264_update on public.tiandao_companions_v259;
create trigger trg_tiandao_companion_cultivation_v264_insert_delete
after insert or delete on public.tiandao_companions_v259
for each row execute function public.tiandao_companion_cultivation_trigger_v264();
create trigger trg_tiandao_companion_cultivation_v264_update
after update of status,npc_id,character_id on public.tiandao_companions_v259
for each row execute function public.tiandao_companion_cultivation_trigger_v264();

-- Existing active companions receive the bonus immediately after SQL264.
do $backfill$
declare r record;
begin
  for r in select character_id,npc_id from public.tiandao_companions_v259 where status='active' loop
    perform public.sync_tiandao_companion_cultivation_v264(r.character_id,true,r.npc_id);
  end loop;
end
$backfill$;

-- ---------- ADMIN9 R40 ----------
create or replace function public.admin9_get_heaven_balance_control_v264()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare c public.heaven_balance_control_v264%rowtype;v_active bigint;v_effects bigint;
begin
  perform public.admin_whoami_v1();
  select * into c from public.heaven_balance_control_v264 where singleton_id=1;
  select count(distinct character_id) into v_active from public.tiandao_companions_v259 where status='active';
  select count(*) into v_effects from public.character_cultivation_effects where source_key='tiandao_companion_v264' and is_active and (expires_at is null or expires_at>clock_timestamp());
  return jsonb_build_object(
    'status','ok','sql','SQL264','mode',c.mode,'blessing_coefficient',c.blessing_coefficient,
    'obstruction_coefficient',c.obstruction_coefficient,'updated_at',c.updated_at,'updated_by',c.updated_by,
    'active_npc_companions',v_active,'active_companion_cultivation_effects',v_effects,'companion_multiplier',1.5
  );
end $$;

create or replace function public.admin9_update_heaven_balance_control_v264(
  p_mode text,p_blessing_coefficient numeric,p_obstruction_coefficient numeric,p_reason text,p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare c public.heaven_balance_control_v264%rowtype;v_old jsonb;v_new jsonb;v_admin uuid:=auth.uid();
begin
  perform public.admin_whoami_v1();
  if p_request_id is null then raise exception 'ADMIN9_REQUEST_ID_REQUIRED'; end if;
  if coalesce(length(trim(p_reason)),0)<2 then raise exception 'ADMIN9_REASON_REQUIRED'; end if;
  if p_mode not in('auto','dao_balance','heavenly_blessing','heaven_obstruction') then raise exception 'ADMIN9_HEAVEN_MODE_INVALID'; end if;
  if p_blessing_coefficient is null or p_blessing_coefficient<1 or p_blessing_coefficient>5 then raise exception 'ADMIN9_HEAVEN_BLESSING_COEFFICIENT_INVALID'; end if;
  if p_obstruction_coefficient is null or p_obstruction_coefficient<0.1 or p_obstruction_coefficient>1 then raise exception 'ADMIN9_HEAVEN_OBSTRUCTION_COEFFICIENT_INVALID'; end if;

  if exists(select 1 from public.heaven_balance_control_audit_v264 where request_id=p_request_id) then
    return public.admin9_get_heaven_balance_control_v264();
  end if;

  select * into c from public.heaven_balance_control_v264 where singleton_id=1 for update;
  v_old:=to_jsonb(c);
  update public.heaven_balance_control_v264 set
    mode=p_mode,
    blessing_coefficient=p_blessing_coefficient,
    obstruction_coefficient=p_obstruction_coefficient,
    updated_at=clock_timestamp(),updated_by=v_admin
  where singleton_id=1 returning * into c;
  v_new:=to_jsonb(c);
  insert into public.heaven_balance_control_audit_v264(request_id,admin_user_id,old_value,new_value,reason)
  values(p_request_id,v_admin,v_old,v_new,trim(p_reason));
  return public.admin9_get_heaven_balance_control_v264();
end $$;

create or replace function public.admin9_check_heaven_companion_v264()
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare v_active bigint;v_effects bigint;v_heaven_def text;v_claim_def text;
begin
  perform public.admin_whoami_v1();
  select count(distinct character_id) into v_active from public.tiandao_companions_v259 where status='active';
  select count(*) into v_effects from public.character_cultivation_effects
    where source_key='tiandao_companion_v264' and is_active and (expires_at is null or expires_at>clock_timestamp());
  select pg_get_functiondef(to_regprocedure('public.get_heaven_balance_v1()')) into v_heaven_def;
  select pg_get_functiondef(to_regprocedure('public.claim_cultivation_v1()')) into v_claim_def;
  return jsonb_build_object(
    'status',case when v_active=v_effects
      and position('heaven_balance_control_v264' in v_heaven_def)>0
      and position('claim_cultivation_dynamic_v264' in v_claim_def)>0
      and position('v_companion_multiplier' in v_claim_def)>0
      then 'PASS' else 'FAIL' end,
    'sql','SQL264 R2',
    'active_npc_companions',v_active,'active_companion_effects',v_effects,
    'heaven_display_wrapper_installed',position('heaven_balance_control_v264' in v_heaven_def)>0,
    'cultivation_authority_wrapper_installed',position('claim_cultivation_dynamic_v264' in v_claim_def)>0,
    'companion_multiplier',1.5
  );
end $$;

revoke all on function public.admin9_get_heaven_balance_control_v264() from public,anon,authenticated;
revoke all on function public.admin9_update_heaven_balance_control_v264(text,numeric,numeric,text,uuid) from public,anon,authenticated;
revoke all on function public.admin9_check_heaven_companion_v264() from public,anon,authenticated;
grant execute on function public.admin9_get_heaven_balance_control_v264() to authenticated;
grant execute on function public.admin9_update_heaven_balance_control_v264(text,numeric,numeric,text,uuid) to authenticated;
grant execute on function public.admin9_check_heaven_companion_v264() to authenticated;

-- Internal trigger/sync helpers are never player RPCs.
revoke all on function public.sync_tiandao_companion_cultivation_v264(uuid,boolean,uuid) from public,anon,authenticated;
revoke all on function public.tiandao_companion_cultivation_trigger_v264() from public,anon,authenticated;
revoke all on function public.get_heaven_balance_dynamic_v264() from public,anon,authenticated;
revoke all on function public.claim_cultivation_dynamic_v264() from public,anon,authenticated;

-- ---------- execution gate ----------
do $gate$
declare
  v_heaven_def text;
  v_claim_def text;
  v_exposed int;
  v_active bigint;
  v_effects bigint;
  v_bad_effects bigint;
begin
  if to_regprocedure('public.admin9_get_heaven_balance_control_v264()') is null then raise exception 'SQL264_GATE_ADMIN_GET_MISSING'; end if;
  if to_regprocedure('public.admin9_update_heaven_balance_control_v264(text,numeric,numeric,text,uuid)') is null then raise exception 'SQL264_GATE_ADMIN_UPDATE_MISSING'; end if;
  if to_regprocedure('public.admin9_check_heaven_companion_v264()') is null then raise exception 'SQL264_GATE_ADMIN_CHECK_MISSING'; end if;
  if to_regprocedure('public.get_heaven_balance_dynamic_v264()') is null then raise exception 'SQL264_GATE_DYNAMIC_HEAVEN_BACKUP_MISSING'; end if;
  if to_regprocedure('public.claim_cultivation_dynamic_v264()') is null then raise exception 'SQL264_GATE_DYNAMIC_CLAIM_BACKUP_MISSING'; end if;
  if to_regprocedure('public.sync_tiandao_companion_cultivation_v264(uuid,boolean,uuid)') is null then raise exception 'SQL264_GATE_COMPANION_SYNC_MISSING'; end if;

  select pg_get_functiondef(to_regprocedure('public.get_heaven_balance_v1()')) into v_heaven_def;
  if position('heaven_balance_control_v264' in v_heaven_def)=0 or position('get_heaven_balance_dynamic_v264' in v_heaven_def)=0 then
    raise exception 'SQL264_GATE_HEAVEN_WRAPPER_INVALID';
  end if;

  select pg_get_functiondef(to_regprocedure('public.claim_cultivation_v1()')) into v_claim_def;
  if position('claim_cultivation_dynamic_v264' in v_claim_def)=0
     or position('heaven_balance_control_v264' in v_claim_def)=0
     or position('v_companion_multiplier' in v_claim_def)=0 then
    raise exception 'SQL264_GATE_CLAIM_WRAPPER_INVALID';
  end if;

  select count(*) into v_exposed from information_schema.routine_privileges
  where specific_schema='public'
    and routine_name in(
      'admin9_get_heaven_balance_control_v264','admin9_update_heaven_balance_control_v264',
      'admin9_check_heaven_companion_v264','claim_cultivation_dynamic_v264','get_heaven_balance_dynamic_v264'
    )
    and grantee in('anon','PUBLIC') and privilege_type='EXECUTE';
  if v_exposed<>0 then raise exception 'SQL264_GATE_PRIVATE_RPC_EXPOSED:%',v_exposed; end if;

  select count(distinct character_id) into v_active from public.tiandao_companions_v259 where status='active';
  select count(*) into v_effects from public.character_cultivation_effects
    where source_key='tiandao_companion_v264' and is_active and (expires_at is null or expires_at>clock_timestamp());
  if v_active<>v_effects then raise exception 'SQL264_GATE_COMPANION_EFFECT_COUNT_MISMATCH active=% effects=%',v_active,v_effects; end if;

  select count(*) into v_bad_effects from public.character_cultivation_effects
    where source_key='tiandao_companion_v264' and is_active and coalesce(multiplier_bonus,0)<>0;
  if v_bad_effects<>0 then raise exception 'SQL264_GATE_COMPANION_MARKER_MUST_NOT_BE_ADDITIVE:%',v_bad_effects; end if;
end
$gate$;

commit;

select jsonb_build_object(
  'sql','264 R2','gate','SQL264_GATE_PASSED','release','V2.2.0 CACHE136',
  'heaven_control','auto / fixed dao_balance / fixed heavenly_blessing / fixed heaven_obstruction',
  'npc_companion_cultivation_multiplier',1.5,'cultivation_authority','claim_cultivation_v1 wrapper',
  'gm','ADMIN9 R40','edge','tiandao-ai CACHE135 R6 unchanged','next_sql',265
) as sql264_install_result;
