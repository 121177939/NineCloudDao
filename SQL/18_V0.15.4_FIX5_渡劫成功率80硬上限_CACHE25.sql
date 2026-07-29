-- 九霄问道 V0.15.4 FIX5 CACHE25
-- 全局渡劫成功率硬上限 80%
-- 已完成 FIX4 的数据库只需执行本文件，再执行 19 最终检查。

begin;

create or replace function public.get_breakthrough_status_v1()
returns table (
  status text,character_id uuid,current_stage_id smallint,current_stage_name text,next_stage_id smallint,next_stage_name text,
  cultivation_total bigint,cultivation_required bigint,success_rate numeric,base_success_rate numeric,compensation_bonus numeric,
  compensation_cap numeric,failure_count integer,total_failure_count integer,heavenly_insight_count integer,
  original_target_stage_id smallint,original_target_stage_name text,adversity integer,lifespan_bonus integer,
  affliction_code text,affliction_name text,penalty_enabled boolean,penalty_floor_name text,major_fall_used boolean,
  major_fall_origin_stage_name text,current_base_rate_per_second numeric,next_base_rate_per_second numeric,
  cultivation_cap bigint,cultivation_full boolean
)
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=auth.uid();
  v_character public.player_characters%rowtype;
  v_current public.realm_stages%rowtype;
  v_next public.realm_stages%rowtype;
  v_next_id smallint;
  v_base numeric:=0;
  v_normal numeric:=0;
  v_insights integer:=0;
  v_total_failures integer:=0;
  v_bonus numeric:=0;
  v_final numeric:=0;
  v_fate_code text;
  v_fate_penalty numeric:=0;
  v_unyielding_stacks integer:=0;
  v_unyielding_bonus numeric:=0;
  v_unyielding_per_stack numeric:=0.05;
  v_unyielding_limit integer:=4;
  v_target_id smallint;
  v_target_name text;
  v_affliction_code text;
  v_affliction_name text;
  v_current_major smallint:=0;
  v_nascent smallint:=4;
  v_penalty boolean:=false;
  v_recovery_active boolean:=false;
  v_recovery_anchor_name text;
  v_recovery_floor_name text;
  v_cap bigint;
  v_enabled boolean:=true;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED'; end if;

  select pc.* into v_character
  from public.player_characters pc
  where pc.user_id=v_user_id and pc.status in('active','secluded','missing')
  order by pc.created_at desc limit 1;
  if v_character.id is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;

  select rs.* into v_current from public.realm_stages rs where rs.id=v_character.realm_stage_id;
  select r.major_order into v_current_major from public.realms r where r.id=v_current.realm_id;
  select coalesce(min(r.major_order) filter(where r.code='nascent_soul' or r.name like '元婴%'),4)
  into v_nascent from public.realms r;
  v_penalty:=coalesce(v_current_major,0)>=coalesce(v_nascent,4);

  select rs.id into v_next_id
  from public.realm_stages rs join public.realms r on r.id=rs.realm_id
  where (r.major_order,rs.minor_level,rs.id)>(
    select r0.major_order,rs0.minor_level,rs0.id
    from public.realm_stages rs0 join public.realms r0 on r0.id=rs0.realm_id
    where rs0.id=v_character.realm_stage_id
  )
  order by r.major_order,rs.minor_level,rs.id limit 1;

  if v_next_id is null then
    return query select 'maximum'::text,v_character.id,v_current.id,v_current.stage_name,null::smallint,null::text,
      v_character.cultivation,null::bigint,0::numeric,0::numeric,0::numeric,0.80::numeric,0,0,0,
      null::smallint,null::text,v_character.adversity,0,null::text,null::text,v_penalty,null::text,false,null::text,
      public.realm_base_cultivation_rate_v1(v_current.id),null::numeric,null::bigint,false;
    return;
  end if;

  select rs.* into v_next from public.realm_stages rs where rs.id=v_next_id;
  v_cap:=v_next.cultivation_required;

  select coalesce(bs.total_failure_count,bs.failure_count,0),coalesce(bs.heavenly_insight_count,0),
         coalesce(bs.unyielding_stack_count,0),bs.original_target_stage_id,ots.stage_name,
         bs.affliction_code,bs.affliction_name,coalesce(bs.recovery_active,false),anchor.stage_name,floor_stage.stage_name
  into v_total_failures,v_insights,v_unyielding_stacks,v_target_id,v_target_name,
       v_affliction_code,v_affliction_name,v_recovery_active,v_recovery_anchor_name,v_recovery_floor_name
  from (select 1) seed
  left join public.character_breakthrough_states bs on bs.character_id=v_character.id
  left join public.realm_stages ots on ots.id=bs.original_target_stage_id
  left join public.realm_stages anchor on anchor.id=bs.recovery_anchor_stage_id
  left join public.realm_stages floor_stage on floor_stage.id=bs.recovery_floor_stage_id;

  v_base:=greatest(0,least(1,coalesce(v_next.breakthrough_base_rate,0)));
  select f.code,
         coalesce((f.modifiers->>'tribulation_success_penalty')::numeric,0),
         coalesce((f.modifiers->>'failure_stack_bonus')::numeric,0.05),
         coalesce((f.modifiers->>'failure_stack_limit')::integer,4),
         coalesce((f.modifiers->>'breakthrough')::numeric,0)+coalesce((f.modifiers->>'breakthrough_rate')::numeric,0)
  into v_fate_code,v_fate_penalty,v_unyielding_per_stack,v_unyielding_limit,v_normal
  from public.character_fates cf join public.fates f on f.id=cf.fate_id
  where cf.character_id=v_character.id and cf.is_active order by cf.created_at limit 1;

  v_normal:=coalesce(v_normal,0);
  v_fate_penalty:=case when v_penalty and v_fate_code='heaven_jealous' then greatest(0,coalesce(v_fate_penalty,0)) else 0 end;
  v_unyielding_bonus:=case when v_fate_code='unyielding_heart'
    then least(greatest(0,v_unyielding_stacks),greatest(0,v_unyielding_limit))*greatest(0,v_unyielding_per_stack)
    else 0 end;
  v_bonus:=greatest(0,v_insights*0.05)+v_unyielding_bonus;
  v_final:=least(0.80,greatest(0,v_base+v_normal-v_fate_penalty+v_bonus));

  select s.breakthrough_enabled into v_enabled from public.progression_v0130_settings s where s.singleton_id=1;

  return query select case when coalesce(v_enabled,true) then 'available' else 'disabled' end,
    v_character.id,v_current.id,v_current.stage_name,v_next.id,v_next.stage_name,v_character.cultivation,
    v_next.cultivation_required,round(v_final,4),round(greatest(0,v_base+v_normal),4),
    round(greatest(0,v_insights*0.05),4),0.80::numeric,v_total_failures,v_total_failures,v_insights,
    v_target_id,v_target_name,v_character.adversity,coalesce(v_next.lifespan_bonus,0),v_affliction_code,v_affliction_name,
    v_penalty,v_recovery_floor_name,v_recovery_active,v_recovery_anchor_name,
    public.realm_base_cultivation_rate_v1(v_current.id),public.realm_base_cultivation_rate_v1(v_next.id),
    v_cap,v_character.cultivation>=v_cap;
end;
$$;


create or replace function public.attempt_breakthrough_v1()
returns table (
  success boolean,outcome_code text,target_stage_name text,current_stage_name text,message text,cultivation_before bigint,cultivation_after bigint,
  cultivation_lost bigint,lifespan_bonus integer,adversity_after integer,failure_count integer,total_failure_count integer,
  heavenly_insight_count integer,insight_gained boolean,compensation_bonus numeric,effective_success_rate numeric,
  affliction_code text,affliction_name text,original_target_stage_name text,character_dead boolean
)
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=auth.uid();
  v_character public.player_characters%rowtype;
  v_current public.realm_stages%rowtype;
  v_next public.realm_stages%rowtype;
  v_target public.realm_stages%rowtype;
  v_candidate_id smallint;
  v_next_id smallint;
  v_base numeric:=0;
  v_normal numeric:=0;
  v_effective numeric:=0;
  v_total_failures integer:=0;
  v_insights integer:=0;
  v_fate_code text;
  v_fate_penalty numeric:=0;
  v_unyielding_stacks integer:=0;
  v_unyielding_bonus numeric:=0;
  v_unyielding_per_stack numeric:=0.05;
  v_unyielding_limit integer:=4;
  v_last_attempt_at timestamptz;
  v_original_target_id smallint;
  v_original_target_name text;
  v_affliction_code text;
  v_affliction_name text;
  v_affliction_steps integer:=0;
  v_pre_affliction_code text;
  v_pre_affliction_name text;
  v_pre_affliction_steps integer;
  v_roll numeric;
  v_outcome text;
  v_message text;
  v_stage_floor bigint;
  v_required_delta bigint;
  v_after bigint;
  v_insight_gained boolean:=false;
  v_current_major smallint:=0;
  v_nascent smallint:=4;
  v_penalty boolean:=false;
  v_enabled boolean:=true;
  v_adversity_after integer;
  v_recovery_active boolean:=false;
  v_recovery_anchor_id smallint;
  v_recovery_floor_id smallint;
  v_recovery_floor_name text;
  v_dao_collapse_active boolean:=false;
  v_current_position integer;
  v_next_position integer;
  v_floor_position integer;
  v_target_position integer;
  v_reached_floor boolean:=false;
  v_reached_target boolean:=false;
  v_recovery_completed boolean:=false;
  v_mortal public.realm_stages%rowtype;
  v_pill_quantity integer:=0;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED'; end if;

  select s.breakthrough_enabled into v_enabled from public.progression_v0130_settings s where s.singleton_id=1;
  if not coalesce(v_enabled,true) then raise exception 'BREAKTHROUGH_V0130_DISABLED'; end if;

  select pc.* into v_character
  from public.player_characters pc
  where pc.user_id=v_user_id and pc.status in('active','secluded','missing')
  order by pc.created_at desc limit 1 for update;
  if v_character.id is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;

  select rs.* into v_current from public.realm_stages rs where rs.id=v_character.realm_stage_id;
  v_target:=v_current;
  select r.major_order into v_current_major from public.realms r where r.id=v_current.realm_id;
  select coalesce(min(r.major_order) filter(where r.code='nascent_soul' or r.name like '元婴%'),4)
  into v_nascent from public.realms r;
  v_penalty:=coalesce(v_current_major,0)>=coalesce(v_nascent,4);

  select rs.id into v_next_id
  from public.realm_stages rs join public.realms r on r.id=rs.realm_id
  where (r.major_order,rs.minor_level,rs.id)>(
    select r0.major_order,rs0.minor_level,rs0.id
    from public.realm_stages rs0 join public.realms r0 on r0.id=rs0.realm_id
    where rs0.id=v_character.realm_stage_id
  )
  order by r.major_order,rs.minor_level,rs.id limit 1;
  if v_next_id is null then raise exception 'MAXIMUM_REALM'; end if;

  select rs.* into v_next from public.realm_stages rs where rs.id=v_next_id;
  if v_character.cultivation<v_next.cultivation_required then raise exception 'INSUFFICIENT_CULTIVATION'; end if;

  insert into public.character_breakthrough_states(character_id) values(v_character.id)
  on conflict(character_id) do nothing;

  select coalesce(bs.total_failure_count,bs.failure_count,0),coalesce(bs.heavenly_insight_count,0),
         coalesce(bs.unyielding_stack_count,0),bs.last_attempt_at,bs.original_target_stage_id,ots.stage_name,
         bs.affliction_code,bs.affliction_name,bs.affliction_steps_remaining,
         coalesce(bs.recovery_active,false),bs.recovery_anchor_stage_id,bs.recovery_floor_stage_id,
         coalesce(bs.dao_collapse_active,false),bs.pre_collapse_affliction_code,bs.pre_collapse_affliction_name,bs.pre_collapse_affliction_steps
  into v_total_failures,v_insights,v_unyielding_stacks,v_last_attempt_at,v_original_target_id,v_original_target_name,
       v_affliction_code,v_affliction_name,v_affliction_steps,v_recovery_active,v_recovery_anchor_id,v_recovery_floor_id,
       v_dao_collapse_active,v_pre_affliction_code,v_pre_affliction_name,v_pre_affliction_steps
  from public.character_breakthrough_states bs
  left join public.realm_stages ots on ots.id=bs.original_target_stage_id
  where bs.character_id=v_character.id for update of bs;

  if v_last_attempt_at is not null and v_last_attempt_at>clock_timestamp()-interval '3 seconds' then
    raise exception 'BREAKTHROUGH_REQUEST_TOO_FREQUENT';
  end if;
  update public.character_breakthrough_states
  set last_attempt_at=clock_timestamp(),updated_at=now()
  where character_id=v_character.id;

  v_base:=greatest(0,least(1,coalesce(v_next.breakthrough_base_rate,0)));
  select f.code,
         coalesce((f.modifiers->>'tribulation_success_penalty')::numeric,0),
         coalesce((f.modifiers->>'failure_stack_bonus')::numeric,0.05),
         coalesce((f.modifiers->>'failure_stack_limit')::integer,4),
         coalesce((f.modifiers->>'breakthrough')::numeric,0)+coalesce((f.modifiers->>'breakthrough_rate')::numeric,0)
  into v_fate_code,v_fate_penalty,v_unyielding_per_stack,v_unyielding_limit,v_normal
  from public.character_fates cf join public.fates f on f.id=cf.fate_id
  where cf.character_id=v_character.id and cf.is_active order by cf.created_at limit 1;

  v_normal:=coalesce(v_normal,0);
  v_fate_penalty:=case when v_penalty and v_fate_code='heaven_jealous' then greatest(0,coalesce(v_fate_penalty,0)) else 0 end;
  v_unyielding_bonus:=case when v_fate_code='unyielding_heart'
    then least(greatest(0,v_unyielding_stacks),greatest(0,v_unyielding_limit))*greatest(0,v_unyielding_per_stack)
    else 0 end;
  v_effective:=least(0.80,greatest(0,v_base+v_normal-v_fate_penalty+v_insights*0.05+v_unyielding_bonus));
  begin
    v_pill_quantity:=greatest(0,coalesce(nullif(current_setting('ncd.v0154_breakthrough_pill_quantity',true),''),'0')::integer);
  exception when others then
    v_pill_quantity:=0;
  end;
  v_effective:=least(0.80,v_effective+least(v_pill_quantity,20)*0.05);

  if random()<v_effective then
    select stage_index into v_next_position from public.realm_stage_position_v1(v_next.id);
    if v_recovery_floor_id is not null then
      select stage_index into v_floor_position from public.realm_stage_position_v1(v_recovery_floor_id);
      v_reached_floor:=coalesce(v_next_position,0)>=coalesce(v_floor_position,2147483647);
    end if;
    if v_original_target_id is not null then
      select stage_index into v_target_position from public.realm_stage_position_v1(v_original_target_id);
      v_reached_target:=coalesce(v_next_position,0)>=coalesce(v_target_position,2147483647);
    end if;

    update public.player_characters
    set realm_stage_id=v_next.id,lifespan_total=lifespan_total+coalesce(v_next.lifespan_bonus,0),updated_at=now()
    where id=v_character.id;
    update public.character_cultivation_state
    set base_rate_per_second=public.realm_base_cultivation_rate_v1(v_next.id),updated_at=now()
    where character_id=v_character.id;

    if v_recovery_active and v_dao_collapse_active then
      if v_reached_floor then
        v_dao_collapse_active:=false;
        v_affliction_code:='severe_injury';
        v_affliction_name:='重伤';
        v_affliction_steps:=2;
        update public.player_characters set health_status='wounded',updated_at=now() where id=v_character.id;
        v_message:='道关已开，成功踏入'||v_next.stage_name||'。你已重返普通跌境保护下限，濒死状态转为重伤。';
      else
        v_affliction_code:='near_death';
        v_affliction_name:='濒死';
        v_affliction_steps:=0;
        update public.player_characters set health_status='critical',updated_at=now() where id=v_character.id;
        v_message:='道关已开，成功踏入'||v_next.stage_name||'。尚未回到普通跌境保护下限，仍处于濒死恢复期。';
      end if;
    else
      if v_affliction_code='severe_injury' then
        v_affliction_code:='light_injury';v_affliction_name:='轻伤';v_affliction_steps:=1;
        update public.player_characters set health_status='injured',updated_at=now() where id=v_character.id;
      elsif v_affliction_code is not null and v_affliction_code<>'near_death' then
        v_affliction_code:=null;v_affliction_name:=null;v_affliction_steps:=0;
        update public.player_characters set health_status='healthy',updated_at=now() where id=v_character.id;
      end if;
      v_message:='道关已开，成功踏入'||v_next.stage_name||'。';
    end if;

    if v_recovery_active and v_reached_target then
      v_recovery_completed:=true;
      v_message:=v_message||' 已重新达到本轮首次突破目标，恢复周期结束；天劫感悟与百折层数清空。';
      v_recovery_active:=false;
      v_dao_collapse_active:=false;
      v_original_target_id:=null;
      v_original_target_name:=null;
      v_recovery_anchor_id:=null;
      v_recovery_floor_id:=null;
      v_total_failures:=0;
      v_insights:=0;
      v_unyielding_stacks:=0;
      v_pre_affliction_code:=null;
      v_pre_affliction_name:=null;
      v_pre_affliction_steps:=null;
    elsif v_recovery_active then
      v_message:=v_message||' 本轮恢复目标尚未达成，天劫感悟、百折与保护下限继续保留。';
    else
      v_total_failures:=0;
      v_insights:=0;
      v_unyielding_stacks:=0;
      v_original_target_id:=null;
      v_original_target_name:=null;
    end if;

    update public.character_breakthrough_states
    set original_target_stage_id=v_original_target_id,
        failure_count=v_total_failures,total_failure_count=v_total_failures,
        heavenly_insight_count=v_insights,compensation_bonus=v_insights*0.05,
        unyielding_stack_count=v_unyielding_stacks,
        affliction_code=v_affliction_code,affliction_name=v_affliction_name,affliction_steps_remaining=v_affliction_steps,
        major_fall_used=v_recovery_active,major_fall_origin_stage_id=v_recovery_anchor_id,
        recovery_active=v_recovery_active,recovery_anchor_stage_id=v_recovery_anchor_id,recovery_floor_stage_id=v_recovery_floor_id,
        dao_collapse_active=v_dao_collapse_active,
        recovery_started_at=case when v_recovery_active then recovery_started_at else null end,
        pre_collapse_affliction_code=v_pre_affliction_code,pre_collapse_affliction_name=v_pre_affliction_name,
        pre_collapse_affliction_steps=v_pre_affliction_steps,
        last_failure_result=null,updated_at=now()
    where character_id=v_character.id;

    insert into public.cultivation_records(character_id,world_year,action_type,years_spent,cultivation_before,cultivation_delta,cultivation_after,result,calculation_snapshot)
    select v_character.id,gw.current_year,'breakthrough',0,v_character.cultivation,0,v_character.cultivation,'success',
      jsonb_build_object('version','V0.15.4-CACHE23','from_stage',v_current.stage_name,'to_stage',v_next.stage_name,
        'effective_success_rate',v_effective,'recovery_active',v_recovery_active,'recovery_completed',v_recovery_completed,
        'recovery_target',v_original_target_name,'recovery_floor_stage_id',v_recovery_floor_id,
        'dao_collapse_active',v_dao_collapse_active,'heavenly_insight_count',v_insights,
        'unyielding_stack_count',v_unyielding_stacks,'fate_code',v_fate_code,'fate_success_modifier',-v_fate_penalty)
    from public.game_worlds gw where gw.id=v_character.world_id;

    return query select true,'success'::text,v_next.stage_name,v_next.stage_name,v_message,
      v_character.cultivation,v_character.cultivation,0::bigint,coalesce(v_next.lifespan_bonus,0),v_character.adversity,
      v_total_failures,v_total_failures,v_insights,false,round(v_insights*0.05,4),round(v_effective,4),
      v_affliction_code,v_affliction_name,v_original_target_name,false;
    return;
  end if;

  v_total_failures:=v_total_failures+1;

  -- 只有元婴及以上首次真实失败才开启新恢复周期；道果崩解后的低境界失败不会覆盖原目标与保护下限。
  if v_penalty and not v_recovery_active then
    v_recovery_active:=true;
    v_original_target_id:=v_next.id;
    v_original_target_name:=v_next.stage_name;
    v_recovery_anchor_id:=v_current.id;
    v_recovery_floor_id:=public.breakthrough_recovery_floor_b02(v_current.id);
  end if;

  if v_recovery_floor_id is not null then
    select stage_name into v_recovery_floor_name from public.realm_stages where id=v_recovery_floor_id;
  end if;

  v_roll:=random();
  v_after:=v_character.cultivation;
  v_adversity_after:=v_character.adversity;
  v_stage_floor:=coalesce(v_current.cultivation_required,0);
  v_required_delta:=greatest(0,coalesce(v_next.cultivation_required,0)-v_stage_floor);

  if not v_penalty then
    v_outcome:='low_realm_no_penalty';
    v_message:='突破失败——天道护持。元婴期以下不死亡、不跌境、不扣修为，也不会覆盖已存在的恢复目标、保护下限、天劫感悟或百折。';
  elsif v_roll<0.003 then
    select rs.* into v_mortal
    from public.realm_stages rs join public.realms r on r.id=rs.realm_id
    order by r.major_order,rs.minor_level,rs.id limit 1;

    if v_affliction_code is not null and v_affliction_code<>'near_death' and not v_dao_collapse_active then
      v_pre_affliction_code:=v_affliction_code;
      v_pre_affliction_name:=v_affliction_name;
      v_pre_affliction_steps:=v_affliction_steps;
    end if;

    v_target:=v_mortal;
    v_after:=coalesce(v_mortal.cultivation_required,0);
    v_outcome:='dao_collapse';
    v_affliction_code:='near_death';
    v_affliction_name:='濒死';
    v_affliction_steps:=0;
    v_dao_collapse_active:=true;
    v_message:='突破失败——道果崩解。境界与修为尽失，跌回凡人并陷入濒死；角色仍然存活，恢复目标、普通跌境保护下限、天劫感悟与百折全部保留。';

    update public.player_characters
    set realm_stage_id=v_mortal.id,cultivation=v_after,health_status='critical',updated_at=now()
    where id=v_character.id;
    update public.character_cultivation_state
    set base_rate_per_second=public.realm_base_cultivation_rate_v1(v_mortal.id),updated_at=now()
    where character_id=v_character.id;
  elsif v_roll<0.053 then
    v_candidate_id:=public.breakthrough_recovery_floor_b02(v_current.id);
    v_candidate_id:=public.breakthrough_clamp_fall_target_b02(v_current.id,v_candidate_id,v_recovery_floor_id);
    select rs.* into v_target from public.realm_stages rs where rs.id=coalesce(v_candidate_id,v_current.id);

    if v_target.id=v_current.id then
      v_outcome:='major_fall_guarded';
      v_message:='突破失败——大境跌落被保护下限拦截。当前境界不再降低，本次不增加天劫感悟或百折。';
    else
      v_outcome:='major_fall';
      v_after:=coalesce(v_target.cultivation_required,0);
      v_affliction_code:='severe_injury';v_affliction_name:='重伤';v_affliction_steps:=2;
      v_message:='突破失败——大境跌落。普通跌境最低不会低于'||coalesce(v_recovery_floor_name,'本轮保护下限')||'；天劫感悟增加一丝。';
      v_insight_gained:=true;
      v_adversity_after:=v_character.adversity+1;
      update public.player_characters
      set realm_stage_id=v_target.id,cultivation=v_after,health_status='wounded',adversity=v_adversity_after,updated_at=now()
      where id=v_character.id;
      update public.character_cultivation_state
      set base_rate_per_second=public.realm_base_cultivation_rate_v1(v_target.id),updated_at=now()
      where character_id=v_character.id;
    end if;
  elsif v_roll<0.133 then
    v_candidate_id:=public.breakthrough_previous_stage_b02(v_current.id);
    v_candidate_id:=public.breakthrough_clamp_fall_target_b02(v_current.id,v_candidate_id,v_recovery_floor_id);
    select rs.* into v_target from public.realm_stages rs where rs.id=coalesce(v_candidate_id,v_current.id);

    if v_target.id=v_current.id then
      v_outcome:='minor_fall_guarded';
      v_message:='突破失败——小境跌落被保护下限拦截。当前境界不再降低，本次不增加天劫感悟或百折。';
    else
      v_outcome:='minor_fall';
      v_after:=coalesce(v_target.cultivation_required,0);
      v_affliction_code:='light_injury';v_affliction_name:='轻伤';v_affliction_steps:=1;
      v_message:='突破失败——小境跌落。普通跌境最低不会低于'||coalesce(v_recovery_floor_name,'本轮保护下限')||'；天劫感悟增加一丝。';
      v_insight_gained:=true;
      v_adversity_after:=v_character.adversity+1;
      update public.player_characters
      set realm_stage_id=v_target.id,cultivation=v_after,health_status='injured',adversity=v_adversity_after,updated_at=now()
      where id=v_character.id;
      update public.character_cultivation_state
      set base_rate_per_second=public.realm_base_cultivation_rate_v1(v_target.id),updated_at=now()
      where character_id=v_character.id;
    end if;
  elsif v_roll<0.283 then
    v_outcome:='stage_reset';
    v_after:=greatest(v_stage_floor,v_character.cultivation-v_required_delta);
    v_message:='突破失败——道基受挫。本境突破进度尽数崩散，天劫感悟增加一丝。';
    v_insight_gained:=true;
    v_adversity_after:=v_character.adversity+1;
    update public.player_characters set cultivation=v_after,adversity=v_adversity_after,updated_at=now() where id=v_character.id;
  elsif v_roll<0.583 then
    v_outcome:='stage_half';
    v_after:=greatest(v_stage_floor,v_character.cultivation-floor(v_required_delta*0.5)::bigint);
    v_message:='突破失败——灵力溃散。本境突破进度损失一半，天劫感悟增加一丝。';
    v_insight_gained:=true;
    v_adversity_after:=v_character.adversity+1;
    update public.player_characters set cultivation=v_after,adversity=v_adversity_after,updated_at=now() where id=v_character.id;
  else
    v_outcome:='no_loss';
    v_message:='突破失败——有惊无险。境界与修为保持不变，本次不增加天劫感悟或百折。';
  end if;

  if v_insight_gained then
    v_insights:=v_insights+1;
    if v_fate_code='unyielding_heart' then
      v_unyielding_stacks:=least(greatest(0,v_unyielding_limit),v_unyielding_stacks+1);
      v_message:=v_message||format(' 百折道心凝成第%s层百折，额外增加%s个百分点突破成功率。',
        v_unyielding_stacks,trim(to_char(v_unyielding_stacks*v_unyielding_per_stack*100,'FM999990.##')));
    end if;
  end if;

  update public.character_breakthrough_states
  set original_target_stage_id=v_original_target_id,
      failure_count=v_total_failures,total_failure_count=v_total_failures,
      heavenly_insight_count=v_insights,compensation_bonus=v_insights*0.05,
      unyielding_stack_count=v_unyielding_stacks,
      affliction_code=v_affliction_code,affliction_name=v_affliction_name,affliction_steps_remaining=v_affliction_steps,
      major_fall_used=v_recovery_active,major_fall_origin_stage_id=v_recovery_anchor_id,
      recovery_active=v_recovery_active,recovery_anchor_stage_id=v_recovery_anchor_id,recovery_floor_stage_id=v_recovery_floor_id,
      dao_collapse_active=v_dao_collapse_active,
      recovery_started_at=case when v_recovery_active then coalesce(recovery_started_at,clock_timestamp()) else null end,
      pre_collapse_affliction_code=v_pre_affliction_code,pre_collapse_affliction_name=v_pre_affliction_name,
      pre_collapse_affliction_steps=v_pre_affliction_steps,
      last_failure_result=v_outcome,updated_at=now()
  where character_id=v_character.id;

  insert into public.cultivation_records(character_id,world_year,action_type,years_spent,cultivation_before,cultivation_delta,cultivation_after,result,calculation_snapshot)
  select v_character.id,gw.current_year,'breakthrough',0,v_character.cultivation,v_after-v_character.cultivation,v_after,'failure',
    jsonb_build_object('version','V0.15.4-CACHE23','outcome',v_outcome,'from_stage',v_current.stage_name,'attempted_stage',v_next.stage_name,
      'effective_success_rate',v_effective,'total_failure_count',v_total_failures,'heavenly_insight_count',v_insights,
      'insight_gained',v_insight_gained,'compensation_bonus',v_insights*0.05,
      'unyielding_stack_count',v_unyielding_stacks,'unyielding_bonus',case when v_fate_code='unyielding_heart' then v_unyielding_stacks*v_unyielding_per_stack else 0 end,
      'fate_code',v_fate_code,'fate_success_modifier',-v_fate_penalty,
      'recovery_active',v_recovery_active,'recovery_target_stage_id',v_original_target_id,
      'recovery_anchor_stage_id',v_recovery_anchor_id,'recovery_floor_stage_id',v_recovery_floor_id,
      'dao_collapse_active',v_dao_collapse_active,'dao_collapse_failure_probability',0.003,
      'affliction',v_affliction_name,'penalty_enabled',v_penalty,
      'cultivation_required_delta',v_required_delta,'cultivation_lost',greatest(0,v_character.cultivation-v_after))
  from public.game_worlds gw where gw.id=v_character.world_id;

  return query select false,v_outcome,v_next.stage_name,coalesce(v_target.stage_name,v_current.stage_name),v_message,
    v_character.cultivation,v_after,greatest(0,v_character.cultivation-v_after),0,v_adversity_after,
    v_total_failures,v_total_failures,v_insights,v_insight_gained,round(v_insights*0.05,4),round(v_effective,4),
    v_affliction_code,v_affliction_name,v_original_target_name,false;
end;
$$;

comment on function public.get_breakthrough_status_v1() is 'V0.15.4：展示首次失败恢复目标、前一大境同层保护下限、濒死恢复期；常规成功率上限95%，丹药由V0.15.4包装RPC追加至100%。';
comment on function public.attempt_breakthrough_v1() is 'V0.15.4：取消死亡，失败后0.3%道果崩解回凡人；普通跌境按首次失败锚点下限保护，感悟与百折保留至恢复目标。';


create or replace function public.get_breakthrough_status_v0154()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_character_id uuid:=public.v0154_active_character_id();v_status jsonb;v_stock bigint;v_rate numeric;v_max integer;
begin
 select to_jsonb(x) into v_status from public.get_breakthrough_status_v1() x;
 v_status:=coalesce(v_status,jsonb_build_object('status','unavailable'));
 v_stock:=public.v0154_inventory_quantity(v_character_id,'breakthrough_clear_origin_pill_v0154');
 v_rate:=greatest(0,least(1,coalesce((v_status->>'success_rate')::numeric,0)));
 v_max:=greatest(0,ceil(greatest(0,0.80-v_rate)/0.05)::integer);
 return v_status||jsonb_build_object('breakthrough_pill_quantity',v_stock,'pill_bonus_per_item',0.05,
   'max_useful_pills',v_max,'success_rate_with_max_pills',least(0.80,v_rate+least(v_stock,v_max)*0.05));
end$$;
revoke all on function public.get_breakthrough_status_v0154() from public,anon;
grant execute on function public.get_breakthrough_status_v0154() to authenticated;


create or replace function public.attempt_breakthrough_v0154(
  p_pill_quantity integer default 0,p_request_id uuid default gen_random_uuid()
)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
 v_user_id uuid:=auth.uid();v_character public.player_characters%rowtype;v_status jsonb;v_result jsonb;
 v_rate numeric:=0;v_final numeric:=0;v_max integer:=0;v_item_id uuid;v_inventory_id uuid;v_stock bigint:=0;
begin
 if v_user_id is null then raise exception 'AUTH_REQUIRED';end if;
 if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED';end if;
 if p_pill_quantity is null or p_pill_quantity<0 then raise exception 'BREAKTHROUGH_PILL_QUANTITY_INVALID';end if;
 select pc.* into v_character from public.player_characters pc
 where pc.user_id=v_user_id and pc.status in('active','secluded','missing')
 order by pc.created_at desc limit 1 for update;
 if v_character.id is null then raise exception 'NO_ACTIVE_CHARACTER';end if;
 select r.result into v_result from public.player_operation_requests_v0154 r
 where r.request_id=p_request_id and r.character_id=v_character.id and r.operation='attempt_breakthrough';
 if found then return v_result;end if;
 select to_jsonb(x) into v_status from public.get_breakthrough_status_v1() x;
 if coalesce(v_status->>'status','')<>'ready' then
   if coalesce(v_status->>'status','')='maximum' then raise exception 'MAXIMUM_REALM';end if;
   if coalesce(v_status->>'status','')='disabled' then raise exception 'BREAKTHROUGH_V0130_DISABLED';end if;
 end if;
 v_rate:=greatest(0,least(1,coalesce((v_status->>'success_rate')::numeric,0)));
 v_max:=greatest(0,ceil(greatest(0,0.80-v_rate)/0.05)::integer);
 if p_pill_quantity>v_max then raise exception 'BREAKTHROUGH_PILL_QUANTITY_EXCESS';end if;
 if p_pill_quantity>0 then
   v_item_id:=public.v0154_item_id('breakthrough_clear_origin_pill_v0154');
   select ci.id,ci.quantity into v_inventory_id,v_stock from public.character_inventory ci
   where ci.character_id=v_character.id and ci.item_definition_id=v_item_id
   order by ci.created_at,ci.id limit 1 for update;
   if v_inventory_id is null or coalesce(v_stock,0)<p_pill_quantity then raise exception 'BREAKTHROUGH_PILL_INSUFFICIENT';end if;
   if v_stock=p_pill_quantity then delete from public.character_inventory where id=v_inventory_id;
   else update public.character_inventory set quantity=quantity-p_pill_quantity,updated_at=now() where id=v_inventory_id;end if;
 end if;
 perform set_config('ncd.v0154_breakthrough_pill_quantity',p_pill_quantity::text,true);
 select to_jsonb(x) into v_result from public.attempt_breakthrough_v1() x;
 v_final:=least(0.80,v_rate+p_pill_quantity*0.05);
 v_result:=coalesce(v_result,'{}'::jsonb)||jsonb_build_object(
   'pill_quantity_used',p_pill_quantity,'pill_bonus',p_pill_quantity*0.05,
   'normal_success_rate',v_rate,'final_success_rate',v_final,'request_id',p_request_id);
 insert into public.player_operation_requests_v0154(request_id,character_id,operation,result)
 values(p_request_id,v_character.id,'attempt_breakthrough',v_result);
 return v_result;
end$$;
revoke all on function public.attempt_breakthrough_v0154(integer,uuid) from public,anon;
grant execute on function public.attempt_breakthrough_v0154(integer,uuid) to authenticated;



update public.item_definitions
set description='突破前可选用。每枚令本次最终突破成功率增加5个百分点；渡境成功率无论受到丹药、天劫感悟、百折道心或其他加成影响，最终均不得超过80%。只在有效突破事务成立时消耗。',
    effects=jsonb_set(coalesce(effects,'{}'::jsonb),'{success_rate_cap}','0.80'::jsonb,true),
    updated_at=now()
where code='breakthrough_clear_origin_pill_v0154';

update public.jiuxiao_app_release_control
set release_name='V0.15.4 FIX5 CACHE25',cache_epoch=greatest(cache_epoch,25),
    notice_text='V0.15.4 FIX5：渡劫成功率实行全局80%硬上限，丹药、天劫感悟、百折道心及其他加成均不能突破。',updated_at=now()
where singleton_id=1;
insert into public.jiuxiao_app_release_control(singleton_id,release_name,cache_epoch,notice_text,updated_at)
select 1,'V0.15.4 FIX5 CACHE25',25,'V0.15.4 FIX5：渡劫成功率实行全局80%硬上限，丹药、天劫感悟、百折道心及其他加成均不能突破。',now()
where not exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1);

select pg_notify('pgrst','reload schema');
commit;
