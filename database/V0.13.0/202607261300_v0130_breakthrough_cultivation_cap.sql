-- 九霄问道 Web Alpha V0.13.0
-- 天劫突破机制重构 + 修为硬上限 + 历史超额修为截断
-- 权威开发基线：V0.12.0 FIX1 + Deploy Hotfix
-- 数据库前置：V0.11.10 FIX1/FIX2 与 V0.12.0 FIX1
-- 旧 V0.12.0 FIX3 已废弃，不是本迁移的前置条件。

begin;

-- 0. 前置检查
DO $$
BEGIN
  IF to_regclass('public.player_characters') IS NULL
     OR to_regclass('public.realm_stages') IS NULL
     OR to_regclass('public.character_breakthrough_states') IS NULL
     OR to_regprocedure('public.claim_cultivation_v1()') IS NULL
     OR to_regprocedure('public.attempt_breakthrough_v1()') IS NULL
     OR to_regprocedure('public.casino_debit_v1(uuid,text,bigint,text,text)') IS NULL THEN
    RAISE EXCEPTION 'V0130_BASELINE_REQUIRED';
  END IF;
END$$;

-- 1. 可安全停用的V0.13.0设置。紧急停用只关闭新突破，修为上限继续保护数据。
create table if not exists public.progression_v0130_settings (
  singleton_id smallint primary key default 1 check (singleton_id=1),
  breakthrough_enabled boolean not null default true,
  cultivation_cap_enabled boolean not null default true,
  death_probability numeric(8,6) not null default 0.005000,
  major_fall_probability numeric(8,6) not null default 0.050000,
  minor_fall_probability numeric(8,6) not null default 0.080000,
  full_loss_probability numeric(8,6) not null default 0.150000,
  half_loss_probability numeric(8,6) not null default 0.300000,
  no_loss_probability numeric(8,6) not null default 0.415000,
  insight_bonus_per_stack numeric(8,6) not null default 0.050000,
  final_success_rate_cap numeric(8,6) not null default 0.800000,
  updated_at timestamptz not null default now(),
  check (death_probability+major_fall_probability+minor_fall_probability+full_loss_probability+half_loss_probability+no_loss_probability=1.000000)
);
insert into public.progression_v0130_settings(singleton_id) values(1)
on conflict(singleton_id) do update set
  death_probability=0.005000,major_fall_probability=0.050000,minor_fall_probability=0.080000,
  full_loss_probability=0.150000,half_loss_probability=0.300000,no_loss_probability=0.415000,
  insight_bonus_per_stack=0.050000,final_success_rate_cap=0.800000,updated_at=now();
alter table public.progression_v0130_settings enable row level security;
revoke all on table public.progression_v0130_settings from public,anon,authenticated;

-- 2. 历史和运行期截断审计。该表不向客户端开放。
create table if not exists public.cultivation_cap_adjustment_logs (
  id bigserial primary key,
  character_id uuid not null references public.player_characters(id) on delete cascade,
  source_code text not null,
  cultivation_before bigint not null,
  cultivation_cap bigint not null,
  cultivation_after bigint not null,
  discarded_amount bigint not null check(discarded_amount>=0),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists idx_cultivation_cap_logs_character_time on public.cultivation_cap_adjustment_logs(character_id,created_at desc);
alter table public.cultivation_cap_adjustment_logs enable row level security;
revoke all on table public.cultivation_cap_adjustment_logs from public,anon,authenticated;

-- 3. 天劫感悟独立于总失败次数；旧补偿按5个百分点折算为感悟层数，避免直接清空历史补偿。
alter table public.character_breakthrough_states
  add column if not exists total_failure_count integer not null default 0 check(total_failure_count>=0),
  add column if not exists heavenly_insight_count integer not null default 0 check(heavenly_insight_count>=0);
update public.character_breakthrough_states
set total_failure_count=greatest(total_failure_count,failure_count),
    heavenly_insight_count=greatest(heavenly_insight_count,least(16,round(coalesce(compensation_bonus,0)/0.05)::integer)),
    compensation_bonus=least(0.80,greatest(0,round(coalesce(compensation_bonus,0)/0.05)::integer)*0.05),
    updated_at=now();

-- 4. 当前境界的修为上限就是下一境界门槛；最高境界返回NULL表示没有可用下一关。
create or replace function public.character_cultivation_cap_v1(p_stage_id smallint)
returns bigint
language sql
stable
strict
set search_path=public,pg_temp
as $$
  select rs.cultivation_required
  from public.realm_stages rs
  join public.realms r on r.id=rs.realm_id
  where (r.major_order,rs.minor_level,rs.id)>(
    select r0.major_order,rs0.minor_level,rs0.id
    from public.realm_stages rs0 join public.realms r0 on r0.id=rs0.realm_id
    where rs0.id=p_stage_id
  )
  order by r.major_order,rs.minor_level,rs.id
  limit 1;
$$;

create or replace function public.character_cultivation_full_v1(p_character_id uuid)
returns boolean
language sql
stable
strict
set search_path=public,pg_temp
as $$
  select case when cap.value is null then false else pc.cultivation>=cap.value end
  from public.player_characters pc
  cross join lateral (select public.character_cultivation_cap_v1(pc.realm_stage_id) value) cap
  where pc.id=p_character_id;
$$;

revoke all on function public.character_cultivation_cap_v1(smallint) from public,anon,authenticated;
revoke all on function public.character_cultivation_full_v1(uuid) from public,anon,authenticated;

-- 5. 统一受控修为授予函数：返回实际接收和直接舍弃的数量。
create or replace function public.grant_cultivation_capped_v1(
  p_character_id uuid,p_requested_amount bigint,p_source_code text,p_metadata jsonb default '{}'::jsonb
)
returns table(requested_amount bigint,granted_amount bigint,discarded_amount bigint,cultivation_total bigint,cultivation_cap bigint,cultivation_full boolean)
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_before bigint;
  v_stage_id smallint;
  v_cap bigint;
  v_granted bigint:=0;
  v_discarded bigint:=0;
begin
  if p_requested_amount is null or p_requested_amount<=0 then
    return query select greatest(coalesce(p_requested_amount,0),0),0::bigint,0::bigint,pc.cultivation,public.character_cultivation_cap_v1(pc.realm_stage_id),public.character_cultivation_full_v1(pc.id)
    from public.player_characters pc where pc.id=p_character_id;
    return;
  end if;
  select pc.cultivation,pc.realm_stage_id into v_before,v_stage_id
  from public.player_characters pc where pc.id=p_character_id for update;
  if v_stage_id is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;
  v_cap:=public.character_cultivation_cap_v1(v_stage_id);
  if v_cap is null then v_granted:=p_requested_amount;
  else v_granted:=least(p_requested_amount,greatest(0,v_cap-v_before)); end if;
  v_discarded:=greatest(0,p_requested_amount-v_granted);
  if v_granted>0 then
    update public.player_characters set cultivation=cultivation+v_granted,updated_at=now() where id=p_character_id;
  end if;
  if v_discarded>0 and v_cap is not null then
    insert into public.cultivation_cap_adjustment_logs(character_id,source_code,cultivation_before,cultivation_cap,cultivation_after,discarded_amount,metadata)
    values(p_character_id,coalesce(nullif(p_source_code,''),'unknown'),v_before,v_cap,v_before+v_granted,v_discarded,coalesce(p_metadata,'{}'::jsonb));
  end if;
  return query select p_requested_amount,v_granted,v_discarded,v_before+v_granted,v_cap,(v_cap is not null and v_before+v_granted>=v_cap);
end;
$$;
revoke all on function public.grant_cultivation_capped_v1(uuid,bigint,text,jsonb) from public,anon,authenticated;

-- 6. 一次性截断所有历史超额修为，并保留审计记录。
insert into public.cultivation_cap_adjustment_logs(character_id,source_code,cultivation_before,cultivation_cap,cultivation_after,discarded_amount,metadata)
select pc.id,'v0130_initial_truncation',pc.cultivation,cap.value,cap.value,pc.cultivation-cap.value,
       jsonb_build_object('version','0.13.0','realm_stage_id',pc.realm_stage_id)
from public.player_characters pc
cross join lateral (select public.character_cultivation_cap_v1(pc.realm_stage_id) value) cap
where cap.value is not null and pc.cultivation>cap.value;
update public.player_characters pc
set cultivation=public.character_cultivation_cap_v1(pc.realm_stage_id),updated_at=now()
where public.character_cultivation_cap_v1(pc.realm_stage_id) is not null
  and pc.cultivation>public.character_cultivation_cap_v1(pc.realm_stage_id);

-- 7. 最后一层数据库防线：任何直接UPDATE也不能越过下一境界门槛。
create or replace function public.enforce_character_cultivation_cap_v0130()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_cap bigint;v_enabled boolean:=true;
begin
  select s.cultivation_cap_enabled into v_enabled from public.progression_v0130_settings s where s.singleton_id=1;
  if not coalesce(v_enabled,true) then return new; end if;
  v_cap:=public.character_cultivation_cap_v1(new.realm_stage_id);
  if v_cap is not null and new.cultivation>v_cap then
    insert into public.cultivation_cap_adjustment_logs(character_id,source_code,cultivation_before,cultivation_cap,cultivation_after,discarded_amount,metadata)
    values(new.id,'runtime_trigger',case when tg_op='INSERT' then 0 else old.cultivation end,v_cap,v_cap,new.cultivation-v_cap,jsonb_build_object('operation',tg_op));
    new.cultivation:=v_cap;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_player_characters_cultivation_cap_v0130 on public.player_characters;
create trigger trg_player_characters_cultivation_cap_v0130
before insert or update of cultivation,realm_stage_id on public.player_characters
for each row execute function public.enforce_character_cultivation_cap_v0130();
revoke all on function public.enforce_character_cultivation_cap_v0130() from public,anon,authenticated;


-- 8. 突破状态：固定5个百分点感悟，最终成功率始终不超过80%。
drop function if exists public.get_breakthrough_status_v1();
create function public.get_breakthrough_status_v1()
returns table (
  status text,character_id uuid,current_stage_id smallint,current_stage_name text,next_stage_id smallint,next_stage_name text,
  cultivation_total bigint,cultivation_required bigint,success_rate numeric,base_success_rate numeric,compensation_bonus numeric,
  compensation_cap numeric,failure_count integer,total_failure_count integer,heavenly_insight_count integer,
  original_target_stage_id smallint,original_target_stage_name text,adversity integer,lifespan_bonus integer,
  affliction_code text,affliction_name text,penalty_enabled boolean,penalty_floor_name text,major_fall_used boolean,
  major_fall_origin_stage_name text,current_base_rate_per_second numeric,next_base_rate_per_second numeric,
  cultivation_cap bigint,cultivation_full boolean
)
language plpgsql security definer set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=auth.uid();v_character public.player_characters%rowtype;v_current public.realm_stages%rowtype;v_next public.realm_stages%rowtype;
  v_next_id smallint;v_base numeric:=0;v_normal numeric:=0;v_insights integer:=0;v_total_failures integer:=0;v_bonus numeric:=0;v_final numeric:=0;
  v_target_id smallint;v_target_name text;v_affliction_code text;v_affliction_name text;v_current_major smallint:=0;v_nascent smallint:=4;
  v_penalty boolean:=false;v_major_used boolean:=false;v_major_origin_name text;v_cap bigint;v_enabled boolean:=true;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED'; end if;
  select pc.* into v_character from public.player_characters pc where pc.user_id=v_user_id and pc.status in('active','secluded','missing') order by pc.created_at desc limit 1;
  if v_character.id is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;
  select rs.* into v_current from public.realm_stages rs where rs.id=v_character.realm_stage_id;
  select r.major_order into v_current_major from public.realms r where r.id=v_current.realm_id;
  select coalesce(min(r.major_order) filter(where r.code='nascent_soul' or r.name like '元婴%'),4) into v_nascent from public.realms r;
  v_penalty:=coalesce(v_current_major,0)>=coalesce(v_nascent,4);
  select rs.id into v_next_id from public.realm_stages rs join public.realms r on r.id=rs.realm_id
  where (r.major_order,rs.minor_level,rs.id)>(select r0.major_order,rs0.minor_level,rs0.id from public.realm_stages rs0 join public.realms r0 on r0.id=rs0.realm_id where rs0.id=v_character.realm_stage_id)
  order by r.major_order,rs.minor_level,rs.id limit 1;
  if v_next_id is null then
    return query select 'maximum'::text,v_character.id,v_current.id,v_current.stage_name,null::smallint,null::text,v_character.cultivation,null::bigint,
      0::numeric,0::numeric,0::numeric,0.8::numeric,0,0,0,null::smallint,null::text,v_character.adversity,0,null::text,null::text,
      v_penalty,'元婴期'::text,false,null::text,public.realm_base_cultivation_rate_v1(v_current.id),null::numeric,null::bigint,false;
    return;
  end if;
  select rs.* into v_next from public.realm_stages rs where rs.id=v_next_id;v_cap:=v_next.cultivation_required;
  select coalesce(bs.total_failure_count,bs.failure_count,0),coalesce(bs.heavenly_insight_count,0),bs.original_target_stage_id,ots.stage_name,
         bs.affliction_code,bs.affliction_name,coalesce(bs.major_fall_used,false),mfs.stage_name
  into v_total_failures,v_insights,v_target_id,v_target_name,v_affliction_code,v_affliction_name,v_major_used,v_major_origin_name
  from (select 1) seed left join public.character_breakthrough_states bs on bs.character_id=v_character.id
  left join public.realm_stages ots on ots.id=bs.original_target_stage_id left join public.realm_stages mfs on mfs.id=bs.major_fall_origin_stage_id;
  v_base:=greatest(0,least(1,coalesce(v_next.breakthrough_base_rate,0)));
  select coalesce(sum(coalesce((f.modifiers->>'breakthrough')::numeric,0)+coalesce((f.modifiers->>'breakthrough_rate')::numeric,0)),0)
  into v_normal from public.character_fates cf join public.fates f on f.id=cf.fate_id where cf.character_id=v_character.id and cf.is_active;
  v_bonus:=case when v_target_id is null or v_target_id=v_next.id then least(0.80,greatest(0,v_insights*0.05)) else 0 end;
  v_final:=least(0.80,greatest(0,v_base+v_normal+v_bonus));
  select s.breakthrough_enabled into v_enabled from public.progression_v0130_settings s where s.singleton_id=1;
  return query select case when coalesce(v_enabled,true) then 'available' else 'disabled' end,v_character.id,v_current.id,v_current.stage_name,v_next.id,v_next.stage_name,
    v_character.cultivation,v_next.cultivation_required,round(v_final,4),round(greatest(0,v_base+v_normal),4),round(v_bonus,4),0.8::numeric,
    v_total_failures,v_total_failures,v_insights,v_target_id,v_target_name,v_character.adversity,coalesce(v_next.lifespan_bonus,0),v_affliction_code,v_affliction_name,
    v_penalty,'元婴期'::text,v_major_used,v_major_origin_name,public.realm_base_cultivation_rate_v1(v_current.id),public.realm_base_cultivation_rate_v1(v_next.id),
    v_cap,v_character.cultivation>=v_cap;
end;
$$;
revoke all on function public.get_breakthrough_status_v1() from public,anon;
grant execute on function public.get_breakthrough_status_v1() to authenticated;

-- 9. 正式突破结算。
drop function if exists public.attempt_breakthrough_v1();
create function public.attempt_breakthrough_v1()
returns table (
  success boolean,outcome_code text,target_stage_name text,current_stage_name text,message text,cultivation_before bigint,cultivation_after bigint,
  cultivation_lost bigint,lifespan_bonus integer,adversity_after integer,failure_count integer,total_failure_count integer,
  heavenly_insight_count integer,insight_gained boolean,compensation_bonus numeric,effective_success_rate numeric,
  affliction_code text,affliction_name text,original_target_stage_name text,character_dead boolean
)
language plpgsql security definer set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=auth.uid();v_character public.player_characters%rowtype;v_current public.realm_stages%rowtype;v_next public.realm_stages%rowtype;
  v_next_id smallint;v_base numeric:=0;v_normal numeric:=0;v_effective numeric:=0;v_total_failures integer:=0;v_insights integer:=0;
  v_original_target_id smallint;v_original_target_name text;v_affliction_code text;v_affliction_name text;v_affliction_steps integer:=0;
  v_roll numeric;v_outcome text;v_message text;v_target public.realm_stages%rowtype;v_current_position integer;v_target_position integer;v_success_position integer;
  v_stage_floor bigint;v_required_delta bigint;v_after bigint;v_dead boolean:=false;v_insight_gained boolean:=false;
  v_current_major smallint:=0;v_nascent smallint:=4;v_penalty boolean:=false;v_major_used boolean:=false;v_major_origin_id smallint;
  v_major_origin_order smallint;v_success_major_order smallint;v_enabled boolean:=true;v_adversity_after integer;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED'; end if;
  select s.breakthrough_enabled into v_enabled from public.progression_v0130_settings s where s.singleton_id=1;
  if not coalesce(v_enabled,true) then raise exception 'BREAKTHROUGH_V0130_DISABLED'; end if;
  select pc.* into v_character from public.player_characters pc where pc.user_id=v_user_id and pc.status in('active','secluded','missing') order by pc.created_at desc limit 1 for update;
  if v_character.id is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;
  select rs.* into v_current from public.realm_stages rs where rs.id=v_character.realm_stage_id;
  select r.major_order into v_current_major from public.realms r where r.id=v_current.realm_id;
  select coalesce(min(r.major_order) filter(where r.code='nascent_soul' or r.name like '元婴%'),4) into v_nascent from public.realms r;
  v_penalty:=coalesce(v_current_major,0)>=coalesce(v_nascent,4);
  select rs.id into v_next_id from public.realm_stages rs join public.realms r on r.id=rs.realm_id
  where (r.major_order,rs.minor_level,rs.id)>(select r0.major_order,rs0.minor_level,rs0.id from public.realm_stages rs0 join public.realms r0 on r0.id=rs0.realm_id where rs0.id=v_character.realm_stage_id)
  order by r.major_order,rs.minor_level,rs.id limit 1;
  if v_next_id is null then raise exception 'MAXIMUM_REALM'; end if;
  select rs.* into v_next from public.realm_stages rs where rs.id=v_next_id;
  if v_character.cultivation<v_next.cultivation_required then raise exception 'INSUFFICIENT_CULTIVATION'; end if;
  insert into public.character_breakthrough_states(character_id) values(v_character.id) on conflict(character_id) do nothing;
  select coalesce(bs.total_failure_count,bs.failure_count,0),coalesce(bs.heavenly_insight_count,0),bs.original_target_stage_id,ots.stage_name,
         bs.affliction_code,bs.affliction_name,bs.affliction_steps_remaining,coalesce(bs.major_fall_used,false),bs.major_fall_origin_stage_id
  into v_total_failures,v_insights,v_original_target_id,v_original_target_name,v_affliction_code,v_affliction_name,v_affliction_steps,v_major_used,v_major_origin_id
  from public.character_breakthrough_states bs left join public.realm_stages ots on ots.id=bs.original_target_stage_id
  where bs.character_id=v_character.id for update of bs;
  v_base:=greatest(0,least(1,coalesce(v_next.breakthrough_base_rate,0)));
  select coalesce(sum(coalesce((f.modifiers->>'breakthrough')::numeric,0)+coalesce((f.modifiers->>'breakthrough_rate')::numeric,0)),0)
  into v_normal from public.character_fates cf join public.fates f on f.id=cf.fate_id where cf.character_id=v_character.id and cf.is_active;
  v_effective:=least(0.80,greatest(0,v_base+v_normal+case when v_original_target_id is null or v_original_target_id=v_next.id then v_insights*0.05 else 0 end));
  if random()<v_effective then
    update public.player_characters set realm_stage_id=v_next.id,lifespan_total=lifespan_total+coalesce(v_next.lifespan_bonus,0),updated_at=now() where id=v_character.id;
    update public.character_cultivation_state set base_rate_per_second=public.realm_base_cultivation_rate_v1(v_next.id),updated_at=now() where character_id=v_character.id;
    if v_affliction_code='severe_injury' then v_affliction_code:='light_injury';v_affliction_name:='轻伤';v_affliction_steps:=1;
      update public.player_characters set health_status='injured',updated_at=now() where id=v_character.id;
    elsif v_affliction_code is not null then v_affliction_code:=null;v_affliction_name:=null;v_affliction_steps:=0;
      update public.player_characters set health_status='healthy',updated_at=now() where id=v_character.id;
    end if;
    if v_major_used and v_major_origin_id is not null then
      select r.major_order into v_major_origin_order from public.realm_stages rs join public.realms r on r.id=rs.realm_id where rs.id=v_major_origin_id;
      select r.major_order into v_success_major_order from public.realms r where r.id=v_next.realm_id;
      if coalesce(v_success_major_order,-1)>=coalesce(v_major_origin_order,32767) then v_major_used:=false;v_major_origin_id:=null;end if;
    end if;
    select stage_index into v_success_position from public.realm_stage_position_v1(v_next.id);
    if v_original_target_id is not null then select stage_index into v_target_position from public.realm_stage_position_v1(v_original_target_id); end if;
    if v_original_target_id is not null and v_success_position>=coalesce(v_target_position,v_success_position+1) then
      update public.character_breakthrough_states set original_target_stage_id=null,failure_count=0,total_failure_count=0,heavenly_insight_count=0,compensation_bonus=0,
        affliction_code=v_affliction_code,affliction_name=v_affliction_name,affliction_steps_remaining=v_affliction_steps,major_fall_used=v_major_used,
        major_fall_origin_stage_id=v_major_origin_id,last_failure_result=null,updated_at=now() where character_id=v_character.id;
      v_total_failures:=0;v_insights:=0;v_original_target_name:=null;
    else
      update public.character_breakthrough_states set affliction_code=v_affliction_code,affliction_name=v_affliction_name,
        affliction_steps_remaining=v_affliction_steps,major_fall_used=v_major_used,major_fall_origin_stage_id=v_major_origin_id,updated_at=now()
      where character_id=v_character.id;
    end if;
    insert into public.cultivation_records(character_id,world_year,action_type,years_spent,cultivation_before,cultivation_delta,cultivation_after,result,calculation_snapshot)
    select v_character.id,gw.current_year,'breakthrough',0,v_character.cultivation,0,v_character.cultivation,'success',
      jsonb_build_object('version','0.13.0','from_stage',v_current.stage_name,'to_stage',v_next.stage_name,'effective_success_rate',v_effective,
      'heavenly_insight_count',v_insights,'original_target',v_original_target_name) from public.game_worlds gw where gw.id=v_character.world_id;
    return query select true,'success'::text,v_next.stage_name,v_next.stage_name,('道关已开，成功踏入'||v_next.stage_name||'。')::text,
      v_character.cultivation,v_character.cultivation,0::bigint,coalesce(v_next.lifespan_bonus,0),v_character.adversity,v_total_failures,v_total_failures,
      v_insights,false,round(v_insights*0.05,4),round(v_effective,4),v_affliction_code,v_affliction_name,v_original_target_name,false;
    return;
  end if;

  v_total_failures:=v_total_failures+1;
  if v_original_target_id is null then v_original_target_id:=v_next.id;v_original_target_name:=v_next.stage_name;end if;
  v_roll:=random();v_after:=v_character.cultivation;v_adversity_after:=v_character.adversity;
  v_stage_floor:=coalesce(v_current.cultivation_required,0);v_required_delta:=greatest(0,coalesce(v_next.cultivation_required,0)-v_stage_floor);

  if not v_penalty then
    v_outcome:='low_realm_no_penalty';v_message:='突破失败——天道护持。元婴期以下不受失败惩罚，本次也未获得新的天劫感悟。';
  elsif v_roll<0.005 then
    v_outcome:='death';v_message:='突破失败——身死道消。劫云彻底失控，此世道途已尽，唯有轮回再问仙缘。';v_dead:=true;
    update public.player_characters set status='dead',health_status='critical',died_year=coalesce((select gw.current_year from public.game_worlds gw where gw.id=v_character.world_id),died_year,1),death_cause='渡劫失败·身死道消',updated_at=now() where id=v_character.id;
    delete from public.character_breakthrough_states where character_id=v_character.id;
  elsif v_roll<0.055 then
    if v_major_used then v_outcome:='major_fall_guarded';v_message:='突破失败——大境跌落保护生效。回到原始大境界前不会再次大跌境，本次不增加天劫感悟。';
    else
      select rs.* into v_target from public.realm_stages rs join public.realms r on r.id=rs.realm_id
      where r.major_order=greatest(v_nascent,(select max(r2.major_order) from public.realms r2 join public.realm_stages rs2 on rs2.realm_id=r2.id join public.realms rc on rc.id=v_current.realm_id where r2.major_order<rc.major_order))
      order by abs(rs.minor_level-v_current.minor_level),rs.minor_level desc,rs.id limit 1;
      if v_target.id is null or v_current_major<=v_nascent then v_outcome:='realm_floor_guarded';v_target:=v_current;v_message:='突破失败——元婴境界下限保护生效，本次不增加天劫感悟。';
      else v_outcome:='major_fall';v_after:=coalesce(v_target.cultivation_required,0);v_affliction_code:='severe_injury';v_affliction_name:='重伤';v_affliction_steps:=2;
        v_message:='突破失败——大境跌落。道基崩裂、境界退转；你在劫雷中看清一丝轨迹，天劫感悟增加一丝。';v_major_used:=true;v_major_origin_id:=v_current.id;v_insight_gained:=true;v_adversity_after:=v_character.adversity+1;
        update public.player_characters set realm_stage_id=v_target.id,cultivation=v_after,health_status='wounded',adversity=v_adversity_after,updated_at=now() where id=v_character.id;
        update public.character_cultivation_state set base_rate_per_second=public.realm_base_cultivation_rate_v1(v_target.id),updated_at=now() where character_id=v_character.id;
      end if;
    end if;
  elsif v_roll<0.135 then
    select rs.* into v_target from public.realm_stages rs join public.realms r on r.id=rs.realm_id
    where (r.major_order,rs.minor_level,rs.id)<(select r0.major_order,rs0.minor_level,rs0.id from public.realm_stages rs0 join public.realms r0 on r0.id=rs0.realm_id where rs0.id=v_current.id)
      and r.major_order>=v_nascent order by r.major_order desc,rs.minor_level desc,rs.id desc limit 1;
    if v_target.id is null then v_outcome:='realm_floor_guarded';v_target:=v_current;v_message:='突破失败——元婴境界下限保护生效，本次不增加天劫感悟。';
    else v_outcome:='minor_fall';v_after:=coalesce(v_target.cultivation_required,0);v_affliction_code:='light_injury';v_affliction_name:='轻伤';v_affliction_steps:=1;
      v_message:='突破失败——小境跌落。雷火侵入经脉，你也从雷霆方向中得到一分明悟，天劫感悟增加一丝。';v_insight_gained:=true;v_adversity_after:=v_character.adversity+1;
      update public.player_characters set realm_stage_id=v_target.id,cultivation=v_after,health_status='injured',adversity=v_adversity_after,updated_at=now() where id=v_character.id;
      update public.character_cultivation_state set base_rate_per_second=public.realm_base_cultivation_rate_v1(v_target.id),updated_at=now() where character_id=v_character.id;
    end if;
  elsif v_roll<0.285 then
    v_outcome:='stage_reset';v_after:=greatest(v_stage_floor,v_character.cultivation-v_required_delta);
    v_message:='突破失败——道基受挫。为冲击瓶颈凝聚的修为尽数崩散，但当前境界仍被守住；天劫感悟增加一丝。';v_insight_gained:=true;v_adversity_after:=v_character.adversity+1;
    update public.player_characters set cultivation=v_after,adversity=v_adversity_after,updated_at=now() where id=v_character.id;
  elsif v_roll<0.585 then
    v_outcome:='stage_half';v_after:=greatest(v_stage_floor,v_character.cultivation-floor(v_required_delta*0.5)::bigint);
    v_message:='突破失败——灵力溃散。突破积蓄损失一半，你从雷霆余韵中捕捉到一缕劫意；天劫感悟增加一丝。';v_insight_gained:=true;v_adversity_after:=v_character.adversity+1;
    update public.player_characters set cultivation=v_after,adversity=v_adversity_after,updated_at=now() where id=v_character.id;
  else
    v_outcome:='no_loss';v_message:='突破失败——有惊无险。境界与修为保持不变，此番未真正触及劫意，本次不增加突破成功率。';
  end if;

  if v_insight_gained then v_insights:=v_insights+1;end if;
  if not v_dead then
    update public.character_breakthrough_states set original_target_stage_id=v_original_target_id,failure_count=v_total_failures,total_failure_count=v_total_failures,
      heavenly_insight_count=v_insights,compensation_bonus=least(0.80,v_insights*0.05),affliction_code=v_affliction_code,affliction_name=v_affliction_name,
      affliction_steps_remaining=v_affliction_steps,major_fall_used=v_major_used,major_fall_origin_stage_id=v_major_origin_id,last_failure_result=v_outcome,updated_at=now()
    where character_id=v_character.id;
  end if;
  insert into public.cultivation_records(character_id,world_year,action_type,years_spent,cultivation_before,cultivation_delta,cultivation_after,result,calculation_snapshot)
  select v_character.id,gw.current_year,'breakthrough',0,v_character.cultivation,v_after-v_character.cultivation,v_after,'failure',
    jsonb_build_object('version','0.13.0','outcome',v_outcome,'from_stage',v_current.stage_name,'attempted_stage',v_next.stage_name,
      'effective_success_rate',v_effective,'total_failure_count',v_total_failures,'heavenly_insight_count',v_insights,'insight_gained',v_insight_gained,
      'compensation_bonus',least(0.80,v_insights*0.05),'original_target',v_original_target_name,'affliction',v_affliction_name,
      'penalty_enabled',v_penalty,'cultivation_required_delta',v_required_delta,'cultivation_lost',greatest(0,v_character.cultivation-v_after))
  from public.game_worlds gw where gw.id=v_character.world_id;
  return query select false,v_outcome,v_next.stage_name,coalesce(v_target.stage_name,v_current.stage_name),v_message,v_character.cultivation,v_after,
    greatest(0,v_character.cultivation-v_after),0,v_adversity_after,v_total_failures,v_total_failures,v_insights,v_insight_gained,
    round(least(0.80,v_insights*0.05),4),round(v_effective,4),v_affliction_code,v_affliction_name,v_original_target_name,v_dead;
end;
$$;
revoke all on function public.attempt_breakthrough_v1() from public,anon;
grant execute on function public.attempt_breakthrough_v1() to authenticated;

-- 10. 自动修炼结算接入修为硬上限。
create or replace function public.claim_cultivation_v1()
returns table (
  character_id uuid,
  gained bigint,
  cultivation_total bigint,
  elapsed_seconds bigint,
  current_rate_per_second numeric,
  base_rate_per_second numeric,
  root_multiplier numeric,
  qi_multiplier numeric,
  fate_bonus numeric,
  technique_flat_rate numeric,
  technique_multiplier_bonus numeric,
  effect_flat_rate numeric,
  effect_multiplier_bonus numeric,
  claimed_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_character_id uuid;
  v_world_id uuid;
  v_realm_stage_id smallint;
  v_age integer;
  v_player_realm_order integer := 0;
  v_mainstream_realm_order integer := 0;
  v_realm_gap integer := 0;
  v_heaven_coefficient numeric := 1;
  v_cultivation_before bigint;
  v_base_rate numeric := 0;
  v_root_multiplier numeric := 1;
  v_qi_base numeric := 1;
  v_effective_qi_multiplier numeric := 1;
  v_fate_bonus numeric := 0;
  v_technique_flat numeric := 0;
  v_technique_multiplier numeric := 0;
  v_effect_flat numeric := 0;
  v_effect_multiplier numeric := 0;
  v_last_claim timestamptz;
  v_now timestamptz := clock_timestamp();
  v_cursor timestamptz;
  v_boundary timestamptz;
  v_segment_seconds numeric;
  v_segment_effect_flat numeric;
  v_segment_effect_multiplier numeric;
  v_segment_fixed_rate numeric;
  v_segment_rate numeric;
  v_exact_gain numeric := 0;
  v_fraction numeric := 0;
  v_gained bigint := 0;
  v_elapsed bigint := 0;
  v_current_fixed_rate numeric := 0;
  v_current_rate numeric := 0;
  v_cultivation_cap bigint;
  v_requested_gain bigint := 0;
  v_discarded_gain bigint := 0;
begin
  if v_user_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select
    pc.id, pc.world_id, pc.realm_stage_id, pc.age, pc.cultivation,
    r.major_order, cs.last_claim_at, cs.fractional_remainder
  into
    v_character_id, v_world_id, v_realm_stage_id, v_age, v_cultivation_before,
    v_player_realm_order, v_last_claim, v_fraction
  from public.player_characters pc
  join public.character_cultivation_state cs on cs.character_id = pc.id
  join public.realm_stages rs on rs.id = pc.realm_stage_id
  join public.realms r on r.id = rs.realm_id
  where pc.user_id = v_user_id
    and pc.status in ('active','secluded','missing')
  order by pc.created_at desc
  limit 1
  for update of pc, cs;

  if v_character_id is null then
    raise exception 'NO_ACTIVE_CHARACTER';
  end if;

  v_base_rate := coalesce(public.realm_base_cultivation_rate_v1(v_realm_stage_id), 10);
  v_last_claim := least(coalesce(v_last_claim, v_now), v_now);
  v_elapsed := greatest(0, floor(extract(epoch from (v_now - v_last_claim)))::bigint);

  select coalesce(sr.cultivation_multiplier, 1.000000)
  into v_root_multiplier
  from public.character_spirit_roots csr
  join public.spirit_roots sr on sr.id = csr.spirit_root_id
  where csr.character_id = v_character_id and csr.is_primary
  limit 1;
  v_root_multiplier := coalesce(v_root_multiplier, 1.000000);

  select coalesce(gw.spiritual_qi_level, 1.000000)
  into v_qi_base
  from public.game_worlds gw
  where gw.id = v_world_id;
  v_qi_base := coalesce(v_qi_base, 1.000000);

  select coalesce(round(avg(r.major_order))::integer, v_player_realm_order)
  into v_mainstream_realm_order
  from public.player_characters pc
  join public.realm_stages rs on rs.id = pc.realm_stage_id
  join public.realms r on r.id = rs.realm_id
  where pc.world_id = v_world_id
    and pc.status in ('active','secluded','missing');

  v_mainstream_realm_order := coalesce(v_mainstream_realm_order, v_player_realm_order);
  v_realm_gap := coalesce(v_player_realm_order, 0) - coalesce(v_mainstream_realm_order, 0);
  v_heaven_coefficient := public.heaven_balance_multiplier_v1(v_realm_gap);
  v_effective_qi_multiplier := greatest(0, v_qi_base * v_heaven_coefficient);

  select coalesce(sum(
    case
      when f.code = 'late_bloomer' then
        case
          when v_age >= coalesce((f.trigger_rules->>'late_age')::integer, 60)
            then coalesce((f.modifiers->>'late_cultivation')::numeric, 0)
          else coalesce((f.modifiers->>'early_cultivation')::numeric, 0)
        end
      else coalesce((f.modifiers->>'cultivation')::numeric, 0)
    end
  ), 0)
  into v_fate_bonus
  from public.character_fates cf
  join public.fates f on f.id = cf.fate_id
  where cf.character_id = v_character_id and cf.is_active;

  select
    coalesce(sum(coalesce((t.fixed_effects->>'cultivation_per_second')::numeric, 0) * ct.level), 0),
    coalesce(sum(greatest(coalesce((t.fixed_effects->>'cultivation_multiplier')::numeric, 1) - 1, 0)), 0)
  into v_technique_flat, v_technique_multiplier
  from public.character_techniques ct
  join public.techniques t on t.id = ct.technique_id
  where ct.character_id = v_character_id
    and ct.is_equipped
    and t.is_active;

  v_exact_gain := coalesce(v_fraction, 0);
  v_cursor := v_last_claim;

  for v_boundary in
    select boundary_at
    from (
      select v_now as boundary_at
      union
      select greatest(e.starts_at, v_last_claim)
      from public.character_cultivation_effects e
      where e.character_id = v_character_id and e.is_active
        and e.starts_at > v_last_claim and e.starts_at < v_now
      union
      select least(e.expires_at, v_now)
      from public.character_cultivation_effects e
      where e.character_id = v_character_id and e.is_active
        and e.expires_at is not null
        and e.expires_at > v_last_claim and e.expires_at < v_now
    ) boundaries
    where boundary_at > v_last_claim
    order by boundary_at
  loop
    if v_boundary <= v_cursor then continue; end if;

    select coalesce(sum(e.flat_rate_per_second), 0), coalesce(sum(e.multiplier_bonus), 0)
    into v_segment_effect_flat, v_segment_effect_multiplier
    from public.character_cultivation_effects e
    where e.character_id = v_character_id and e.is_active
      and e.starts_at <= v_cursor
      and (e.expires_at is null or e.expires_at > v_cursor);

    v_segment_seconds := greatest(0, extract(epoch from (v_boundary - v_cursor)));
    v_segment_fixed_rate := greatest(
      0,
      (v_base_rate + v_technique_flat + v_segment_effect_flat)
      * v_root_multiplier
      * greatest(0, 1 + v_fate_bonus + v_technique_multiplier + v_segment_effect_multiplier)
    );

    -- 天道动态系数是最后一层，对前面完整结果整体相乘。
    v_segment_rate := greatest(0, v_segment_fixed_rate * v_effective_qi_multiplier);
    v_exact_gain := v_exact_gain + (v_segment_rate * v_segment_seconds);
    v_cursor := v_boundary;
  end loop;

  v_requested_gain := floor(v_exact_gain)::bigint;
  v_gained := v_requested_gain;
  v_fraction := v_exact_gain - v_requested_gain;
  v_cultivation_cap := public.character_cultivation_cap_v1(v_realm_stage_id);
  if v_cultivation_cap is not null then
    v_gained := least(v_requested_gain, greatest(0, v_cultivation_cap - v_cultivation_before));
    v_discarded_gain := greatest(0, v_requested_gain - v_gained);
    if v_discarded_gain > 0 or v_cultivation_before >= v_cultivation_cap then
      -- 圆满后的超额修为与小数余量直接舍弃，不能带入下一境界。
      v_fraction := 0;
    end if;
  end if;

  select coalesce(sum(e.flat_rate_per_second), 0), coalesce(sum(e.multiplier_bonus), 0)
  into v_effect_flat, v_effect_multiplier
  from public.character_cultivation_effects e
  where e.character_id = v_character_id and e.is_active
    and e.starts_at <= v_now
    and (e.expires_at is null or e.expires_at > v_now);

  v_current_fixed_rate := greatest(
    0,
    (v_base_rate + v_technique_flat + v_effect_flat)
    * v_root_multiplier
    * greatest(0, 1 + v_fate_bonus + v_technique_multiplier + v_effect_multiplier)
  );
  v_current_rate := greatest(0, v_current_fixed_rate * v_effective_qi_multiplier);
  if v_cultivation_cap is not null and v_cultivation_before + v_gained >= v_cultivation_cap then
    v_current_rate := 0;
  end if;

  if v_gained > 0 then
    update public.player_characters
    set cultivation = cultivation + v_gained, updated_at = now()
    where id = v_character_id;
  end if;

  update public.character_cultivation_state as ccs
  set base_rate_per_second = v_base_rate,
      last_claim_at = v_now,
      fractional_remainder = v_fraction,
      total_cultivation_seconds = ccs.total_cultivation_seconds + v_elapsed,
      updated_at = now()
  where ccs.character_id = v_character_id;

  if v_gained > 0 and v_elapsed >= 300 then
    insert into public.cultivation_records (
      character_id, world_year, action_type, years_spent,
      cultivation_before, cultivation_delta, cultivation_after,
      result, calculation_snapshot
    )
    select
      v_character_id, gw.current_year, 'cultivate', 0,
      v_cultivation_before, v_gained, v_cultivation_before + v_gained,
      'success',
      jsonb_build_object(
        'mode', 'automatic_v0130_realm_cap',
        'elapsed_seconds', v_elapsed,
        'realm_base_rate', v_base_rate,
        'rate_before_heaven', v_current_fixed_rate,
        'rate_per_second', v_current_rate,
        'root_multiplier', v_root_multiplier,
        'world_qi_base', v_qi_base,
        'heaven_balance_coefficient', v_heaven_coefficient,
        'effective_qi_multiplier', v_effective_qi_multiplier,
        'fate_bonus', v_fate_bonus,
        'technique_flat_rate', v_technique_flat,
        'technique_multiplier_bonus', v_technique_multiplier,
        'effect_flat_rate', v_effect_flat,
        'effect_multiplier_bonus', v_effect_multiplier,
        'cultivation_cap', v_cultivation_cap,
        'requested_gain', v_requested_gain,
        'discarded_gain', v_discarded_gain,
        'cap_rule', 'v0130_hard_cap'
      )
    from public.game_worlds gw where gw.id = v_world_id;
  end if;

  return query select
    v_character_id, v_gained, v_cultivation_before + v_gained, v_elapsed,
    round(v_current_rate, 6), round(v_base_rate, 6), round(v_root_multiplier, 6),
    round(v_effective_qi_multiplier, 6), round(v_fate_bonus, 6),
    round(v_technique_flat, 6), round(v_technique_multiplier, 6),
    round(v_effect_flat, 6), round(v_effect_multiplier, 6), v_now;
end;
$$;

-- 11. 自动机缘即时修为接入统一封顶。
create or replace function public.apply_opportunity_v3_effects_v1(
  p_character_id uuid,
  p_lineage_id uuid,
  p_world_year integer,
  p_result_id uuid,
  p_catalog_code text,
  p_rarity text,
  p_positive_text text,
  p_negative_text text,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  m text[];
  v_amount numeric;
  v_hours integer;
  v_name text;
  v_applied jsonb := '[]'::jsonb;
  v_technique jsonb;
  v_cave jsonb;
  v_grant record;
begin
  -- 即时修为。
  m := regexp_match(coalesce(p_positive_text, ''), '修为（([0-9]+)）');
  if m is not null then
    v_amount := m[1]::numeric;
    select * into v_grant from public.grant_cultivation_capped_v1(
      p_character_id, v_amount::bigint, 'opportunity_v3',
      jsonb_build_object('result_id',p_result_id,'catalog_code',p_catalog_code,'rarity',p_rarity)
    );
    v_applied := v_applied || jsonb_build_array(jsonb_build_object(
      'type','instant_cultivation','requested',v_amount,
      'amount',coalesce(v_grant.granted_amount,0),
      'discarded',coalesce(v_grant.discarded_amount,0),
      'cultivation_cap',v_grant.cultivation_cap
    ));
  end if;

  -- 灵石。
  m := regexp_match(coalesce(p_positive_text, ''), '灵石（([0-9]+)）');
  if m is not null then
    v_amount := m[1]::numeric;
    perform public.award_spirit_stones_v3(p_character_id, v_amount::bigint);
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('type','spirit_stone','amount',v_amount));
  end if;

  -- 永久修炼速度。
  m := regexp_match(coalesce(p_positive_text, ''), '永久修炼速度[[:space:]]*\+[[:space:]]*([0-9]+(?:\.[0-9]+)?)%');
  if m is not null then
    v_amount := m[1]::numeric / 100;
    insert into public.character_cultivation_effects(
      character_id, source_type, source_key, display_name,
      flat_rate_per_second, multiplier_bonus, starts_at, expires_at, is_active, metadata
    ) values (
      p_character_id, 'opportunity', 'opportunity_v3:'||p_result_id::text||':permanent_multiplier',
      '机缘·永久修炼速度', 0, v_amount, p_now, null, true,
      jsonb_build_object('result_id',p_result_id,'rarity',p_rarity)
    );
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('type','permanent_multiplier','amount',v_amount));
  end if;

  -- 永久每秒修为。
  m := regexp_match(coalesce(p_positive_text, ''), '永久每秒修为[[:space:]]*\+[[:space:]]*([0-9]+(?:\.[0-9]+)?)');
  if m is not null then
    v_amount := m[1]::numeric;
    insert into public.character_cultivation_effects(
      character_id, source_type, source_key, display_name,
      flat_rate_per_second, multiplier_bonus, starts_at, expires_at, is_active, metadata
    ) values (
      p_character_id, 'opportunity', 'opportunity_v3:'||p_result_id::text||':permanent_flat',
      '机缘·永久每秒修为', v_amount, 0, p_now, null, true,
      jsonb_build_object('result_id',p_result_id,'rarity',p_rarity)
    );
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('type','permanent_flat','amount',v_amount));
  end if;

  -- 临时修炼速度。
  m := regexp_match(coalesce(p_positive_text, ''), '修炼速度临时[[:space:]]*\+[[:space:]]*([0-9]+(?:\.[0-9]+)?)[%％][^0-9]+([0-9]+)[[:space:]]*小时');
  if m is not null then
    v_amount := m[1]::numeric / 100;
    v_hours := m[2]::integer;
    insert into public.character_cultivation_effects(
      character_id, source_type, source_key, display_name,
      flat_rate_per_second, multiplier_bonus, starts_at, expires_at, is_active, metadata
    ) values (
      p_character_id, 'opportunity', 'opportunity_v3:'||p_result_id::text||':temporary_multiplier',
      '机缘·临时修炼速度', 0, v_amount, p_now, p_now + make_interval(hours=>v_hours), true,
      jsonb_build_object('result_id',p_result_id,'rarity',p_rarity,'hours',v_hours)
    );
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('type','temporary_multiplier','amount',v_amount,'hours',v_hours));
  end if;

  -- 功法奖励。
  m := regexp_match(coalesce(p_positive_text, ''), '习得功法《([^》]+)》');
  if m is not null then
    v_name := m[1];
    v_technique := public.award_opportunity_technique_v3(p_character_id, v_name, p_world_year);
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('type','technique','detail',v_technique));
  end if;

  -- 洞府奖励映射。
  m := regexp_match(coalesce(p_positive_text, ''), '日增[[:space:]]*([0-9]+)[[:space:]]*灵石');
  if m is not null then
    v_amount := m[1]::numeric;
    v_cave := public.award_cave_resource_v3(p_lineage_id, p_catalog_code, v_amount);
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('type','cave_resource_mapping','detail',v_cave));
  end if;

  -- 涉险结果只执行负面效果；持续时间直接读取机缘文本，不再使用固定“天机迟滞”。
  if btrim(coalesce(p_negative_text, '')) <> '' then
    m := regexp_match(
      coalesce(p_negative_text, ''),
      '([0-9]+)[[:space:]]*小时内修炼速度[[:space:]]*-[[:space:]]*([0-9]+(?:\.[0-9]+)?)[%％]'
    );
    if m is not null then
      v_hours := m[1]::integer;
      v_amount := -(m[2]::numeric / 100);
    else
      m := regexp_match(
        coalesce(p_negative_text, ''),
        '修炼速度[[:space:]]*-[[:space:]]*([0-9]+(?:\.[0-9]+)?)[%％].*?([0-9]+)[[:space:]]*小时'
      );
      if m is not null then
        v_amount := -(m[1]::numeric / 100);
        v_hours := m[2]::integer;
      end if;
    end if;

    if m is not null and v_hours > 0 then
      insert into public.character_cultivation_effects(
        character_id, source_type, source_key, display_name,
        flat_rate_per_second, multiplier_bonus, starts_at, expires_at, is_active, metadata
      ) values (
        p_character_id, 'opportunity', 'opportunity_v3:'||p_result_id::text||':risk_penalty',
        '涉险·'||p_rarity, 0, v_amount, p_now, p_now + make_interval(hours=>v_hours), true,
        jsonb_build_object('result_id',p_result_id,'rarity',p_rarity,'hours',v_hours,'polarity','negative')
      );
      v_applied := v_applied || jsonb_build_array(
        jsonb_build_object('type','risk_penalty_multiplier','amount',v_amount,'hours',v_hours)
      );
    end if;
  end if;

  return v_applied;
end$$;

-- 12. 修为赌场：圆满者禁止进入，奖励和返还也不得越过上限。
create or replace function public.casino_debit_v1(
  p_character_id uuid,
  p_stake_type text,
  p_amount bigint,
  p_context text,
  p_game_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_item_id uuid;
  v_quantity bigint := 0;
  v_cultivation bigint := 0;
  v_floor bigint := 0;
  v_available bigint := 0;
  v_maximum bigint := 0;
  v_minimum bigint := 0;
  v_major_order smallint;
  v_stage_id smallint;
  v_stage_name text;
begin
  if p_amount is null or p_amount <= 0 then raise exception 'CASINO_INVALID_STAKE_AMOUNT'; end if;
  if p_context not in ('house','duel') then raise exception 'CASINO_INVALID_CONTEXT'; end if;

  if p_stake_type = 'spirit_stone' then
    v_minimum := case
      when p_context='duel' then 10
      when p_game_code='spirit_dice' then 20
      when p_game_code='turtle_oracle' then 30
      else 10 end;
    v_maximum := case
      when p_context='duel' then 5000
      when p_game_code='spirit_dice' then 2000
      when p_game_code='turtle_oracle' then 1500
      else 5000 end;
    if p_amount < v_minimum then raise exception 'CASINO_STAKE_BELOW_MINIMUM'; end if;
    if p_amount > v_maximum then raise exception 'CASINO_STAKE_ABOVE_MAXIMUM'; end if;
    v_item_id := public.casino_stone_item_id_v1();
    select ci.quantity into v_quantity
    from public.character_inventory ci
    where ci.character_id = p_character_id and ci.item_definition_id = v_item_id and ci.is_bound=false
    for update;
    if coalesce(v_quantity,0) < p_amount then raise exception 'CASINO_INSUFFICIENT_SPIRIT_STONES'; end if;
    if v_quantity=p_amount then
      delete from public.character_inventory ci
      where ci.character_id=p_character_id and ci.item_definition_id=v_item_id and ci.is_bound=false;
    else
      update public.character_inventory ci
      set quantity=ci.quantity-p_amount,updated_at=now()
      where ci.character_id=p_character_id and ci.item_definition_id=v_item_id and ci.is_bound=false;
    end if;
    return jsonb_build_object('stake_type',p_stake_type,'amount',p_amount,'available_before',v_quantity,'available_after',v_quantity-p_amount,'bound_stones_used',false);
  elsif p_stake_type = 'cultivation' then
    if public.character_cultivation_full_v1(p_character_id) then
      raise exception 'CULTIVATION_FULL_CASINO_BLOCKED';
    end if;
    select pc.cultivation, pc.realm_stage_id, rs.stage_name, r.major_order
    into v_cultivation, v_stage_id, v_stage_name, v_major_order
    from public.player_characters pc
    join public.realm_stages rs on rs.id = pc.realm_stage_id
    join public.realms r on r.id = rs.realm_id
    where pc.id = p_character_id
    for update of pc;
    if v_stage_id is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;
    if v_major_order < public.casino_nascent_major_order_v1() then raise exception 'CASINO_CULTIVATION_REQUIRES_NASCENT_SOUL'; end if;
    select min(rs.cultivation_required) into v_floor
    from public.realm_stages rs join public.realms r on r.id = rs.realm_id
    where r.major_order = v_major_order;
    v_available := greatest(0, v_cultivation - coalesce(v_floor,0));
    v_minimum := 50000;
    v_maximum := floor(v_available * 0.20)::bigint;
    if p_amount < v_minimum then raise exception 'CULTIVATION_STAKE_MINIMUM'; end if;
    if p_amount > v_available then raise exception 'CASINO_INSUFFICIENT_CULTIVATION'; end if;
    if p_amount > v_maximum then raise exception 'CASINO_CULTIVATION_STAKE_EXCEEDS_TWENTY_PERCENT'; end if;
    update public.player_characters pc
    set cultivation = pc.cultivation - p_amount, updated_at = now()
    where pc.id = p_character_id;
    return jsonb_build_object(
      'stake_type',p_stake_type,'amount',p_amount,
      'available_before',v_available,'available_after',v_available-p_amount,
      'cultivation_before',v_cultivation,'cultivation_after',v_cultivation-p_amount,
      'stage_before_id',v_stage_id,'stage_before_name',v_stage_name,'major_order',v_major_order,'major_floor',v_floor
    );
  end if;
  raise exception 'CASINO_INVALID_STAKE_TYPE';
end;
$$;

create or replace function public.casino_credit_v1(p_character_id uuid, p_stake_type text, p_amount bigint)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_amount is null or p_amount <= 0 then return; end if;
  if p_stake_type='spirit_stone' then
    perform public.award_spirit_stones_v3(p_character_id,p_amount);
  elsif p_stake_type='cultivation' then
    perform public.grant_cultivation_capped_v1(
      p_character_id,p_amount,'casino_credit',jsonb_build_object('stake_type',p_stake_type)
    );
  else
    raise exception 'CASINO_INVALID_STAKE_TYPE';
  end if;
end;
$$;

create or replace function public.casino_draw_pools_v1()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  p record;
  v_winner uuid;
  v_winner_name text;
  v_tickets integer:=0;
  v_interval integer:=coalesce((select s.draw_interval_seconds from public.casino_settings s where s.singleton_id=1),7200);
  v_result_text text;
  v_count integer:=0;
begin
  for p in select * from public.casino_pools x where x.next_draw_at<=now() for update skip locked loop
    select t.character_id into v_winner
    from public.casino_tickets t
    join public.player_characters pc on pc.id=t.character_id and pc.status in ('active','secluded','missing')
    cross join lateral generate_series(1,t.ticket_count) g(n)
    where t.stake_type=p.stake_type and t.round_ends_at=p.next_draw_at
      and (p.stake_type <> 'cultivation' or not public.character_cultivation_full_v1(t.character_id))
    order by random()
    limit 1;
    select coalesce(sum(t.ticket_count),0)::integer into v_tickets
    from public.casino_tickets t
    where t.stake_type=p.stake_type and t.round_ends_at=p.next_draw_at;

    if v_winner is not null and p.amount>0 then
      perform public.casino_credit_v1(v_winner,p.stake_type,p.amount);
      select pc.name into v_winner_name from public.player_characters pc where pc.id=v_winner;
      v_result_text:=format('万运博弈楼钟鸣九响，【%s】手中造化签无火自燃，独得本期%s造化池：%s%s。',
        coalesce(v_winner_name,'无名修士'),case when p.stake_type='cultivation' then '修为' else '灵石' end,
        p.amount,case when p.stake_type='cultivation' then '点修为' else '枚灵石' end);
      insert into public.casino_draws(stake_type,round_ended_at,winner_character_id,prize_amount,ticket_count,result_text)
      values(p.stake_type,p.next_draw_at,v_winner,p.amount,v_tickets,v_result_text);
      update public.casino_pools x
      set amount=0,last_draw_at=now(),last_winner_character_id=v_winner,last_prize=p.amount,
          next_draw_at=now()+make_interval(secs=>v_interval),updated_at=now()
      where x.stake_type=p.stake_type;
      v_count:=v_count+1;
    else
      update public.casino_pools x
      set last_draw_at=now(),next_draw_at=now()+make_interval(secs=>v_interval),updated_at=now()
      where x.stake_type=p.stake_type;
    end if;
    delete from public.casino_tickets t where t.stake_type=p.stake_type and t.round_ends_at=p.next_draw_at;
  end loop;
  return v_count;
end;
$$;

create or replace function public.get_market_v1()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_character_id uuid;
  v_stones bigint:=0;
  v_cultivation_available bigint:=0;
  v_major_order smallint;
  v_stage_name text;
  v_activity jsonb:='{}'::jsonb;
  v_enabled boolean;
  v_cultivation_cap bigint;
  v_cultivation_full boolean := false;
begin
  perform public.casino_process_v1();
  v_character_id:=public.casino_current_character_id_v1();
  select s.enabled into v_enabled from public.casino_settings s where s.singleton_id=1;
  v_stones:=public.casino_available_v1(v_character_id,'spirit_stone');
  v_cultivation_available:=public.casino_available_v1(v_character_id,'cultivation');
  select r.major_order,rs.stage_name,public.character_cultivation_cap_v1(pc.realm_stage_id),public.character_cultivation_full_v1(pc.id)
  into v_major_order,v_stage_name,v_cultivation_cap,v_cultivation_full
  from public.player_characters pc join public.realm_stages rs on rs.id=pc.realm_stage_id join public.realms r on r.id=rs.realm_id
  where pc.id=v_character_id;
  select to_jsonb(a) into v_activity from public.casino_daily_activity a
  where a.character_id=v_character_id and a.activity_date=current_date;

  return jsonb_build_object(
    'status',case when v_enabled then 'active' else 'disabled' end,
    'settings',(select jsonb_build_object('reveal_delay_seconds',s.reveal_delay_seconds,'open_expiry_seconds',s.open_expiry_seconds,'draw_interval_seconds',s.draw_interval_seconds) from public.casino_settings s where s.singleton_id=1),
    'character',jsonb_build_object(
      'stage_name',v_stage_name,'major_order',v_major_order,
      'cultivation_eligible',v_major_order>=public.casino_nascent_major_order_v1() and not v_cultivation_full,
      'cultivation_full',v_cultivation_full,'cultivation_cap',v_cultivation_cap,
      'spirit_stones',v_stones,'cultivation_available',v_cultivation_available,'cultivation_max_stake',floor(v_cultivation_available*0.20)::bigint
    ),
    'activity',coalesce(v_activity,jsonb_build_object('house_count',0,'duel_count',0,'cultivation_count',0,'total_count',0,'spirit_stone_ticket_count',0,'cultivation_ticket_count',0)),
    'pools',(select jsonb_object_agg(p.stake_type,jsonb_build_object(
      'amount',p.amount,'next_draw_at',p.next_draw_at,'seconds_remaining',greatest(0,extract(epoch from p.next_draw_at-now()))::integer,
      'last_prize',p.last_prize,'last_winner_name',pc.name
    )) from public.casino_pools p left join public.player_characters pc on pc.id=p.last_winner_character_id),
    'tickets',(select jsonb_object_agg(p.stake_type,coalesce(t.ticket_count,0))
      from public.casino_pools p left join public.casino_tickets t
      on t.stake_type=p.stake_type and t.round_ends_at=p.next_draw_at and t.character_id=v_character_id),
    'latest_draws',(select coalesce(jsonb_agg(x.obj order by x.created_at desc),'[]'::jsonb) from (
      select d.created_at,jsonb_build_object('stake_type',d.stake_type,'prize_amount',d.prize_amount,'winner_name',pc.name,'result_text',d.result_text,'created_at',d.created_at) obj
      from public.casino_draws d left join public.player_characters pc on pc.id=d.winner_character_id
      order by d.created_at desc limit 5
    ) x),
    'open_duels',(select coalesce(jsonb_agg(x.obj order by x.created_at desc),'[]'::jsonb) from (
      select d.created_at,jsonb_build_object(
        'id',d.id,'creator_name',pc.name,'game_code',d.game_code,'stake_type',d.stake_type,'stake_amount',d.stake_amount,
        'expires_in',greatest(0,extract(epoch from (d.created_at+make_interval(secs=>s.open_expiry_seconds))-now()))::integer
      ) obj
      from public.casino_duels d join public.player_characters pc on pc.id=d.creator_character_id
      cross join public.casino_settings s
      where d.status='open' and d.creator_character_id<>v_character_id
        and (d.stake_type <> 'cultivation' or not v_cultivation_full)
      order by d.created_at desc limit 30
    ) x),
    'my_duels',(select coalesce(jsonb_agg(x.obj order by x.created_at desc),'[]'::jsonb) from (
      select d.created_at,jsonb_build_object(
        'id',d.id,'game_code',d.game_code,'status',d.status,
        'status_name',case d.status when 'open' then '等待应局' when 'sealed' then '赌契封存中' when 'settled' then '胜负已分' when 'draw' then '流局' when 'cancelled' then '已取消' else d.status end,
        'stake_type',d.stake_type,'stake_amount',d.stake_amount,'fee_amount',d.fee_amount,'prize_amount',d.prize_amount,
        'seconds_remaining',case when d.reveal_at is null then 0 else greatest(0,extract(epoch from d.reveal_at-now()))::integer end,
        'result_text',d.result_text,
        'opponent_name',coalesce(case when d.creator_character_id=v_character_id then op.name else cr.name end,'等待道友'),
        'outcome',case when d.status='draw' then 'draw' when d.status='settled' and d.winner_character_id=v_character_id then 'win' when d.status='settled' then 'loss' else d.status end,
        'my_choice',public.casino_choice_name_v1(d.game_code,case when d.creator_character_id=v_character_id then d.creator_choice else d.opponent_choice end),
        'opponent_choice',case when d.status in ('settled','draw') then public.casino_choice_name_v1(d.game_code,case when d.creator_character_id=v_character_id then d.opponent_choice else d.creator_choice end) end,
        'can_cancel',d.status='open' and d.creator_character_id=v_character_id
      ) obj
      from public.casino_duels d
      join public.player_characters cr on cr.id=d.creator_character_id
      left join public.player_characters op on op.id=d.opponent_character_id
      where v_character_id in (d.creator_character_id,d.opponent_character_id)
      order by d.created_at desc limit 20
    ) x)
  );
end;
$$;

-- 14. 权限与版本注释
comment on table public.progression_v0130_settings is 'V0.13.0突破概率、天劫感悟和修为硬上限开关。';
comment on table public.cultivation_cap_adjustment_logs is 'V0.13.0历史及运行期超额修为舍弃审计；不对玩家客户端开放。';
comment on function public.attempt_breakthrough_v1() is 'V0.13.0：失败后二次结果0.5/5/8/15/30/41.5；实际受罚才增加1丝天劫感悟与5个百分点。';
comment on function public.claim_cultivation_v1() is 'V0.13.0：修为达到下一境界门槛后停止增长，所有超额修为直接舍弃。';

commit;
notify pgrst,'reload schema';
