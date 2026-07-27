-- 九霄问道 V0.14.1 FIX5：跌境后天劫感悟成功率未生效热修复
-- 基线：V0.14.1 FIX4 + CACHE1
-- 作用：已有天劫感悟在跌落小境界或大境界后的恢复途中继续生效，直到真正抵达原始目标境界后清除。
-- 本脚本不会改动任何角色现有境界、修为或感悟数量；只修复成功率计算。

begin;

do $$
begin
  if to_regprocedure('public.get_breakthrough_status_v1()') is null then
    raise exception 'FIX5_REQUIRES_GET_BREAKTHROUGH_STATUS_V1';
  end if;
  if to_regprocedure('public.attempt_breakthrough_v1()') is null then
    raise exception 'FIX5_REQUIRES_ATTEMPT_BREAKTHROUGH_V1';
  end if;
  if to_regclass('public.character_breakthrough_states') is null then
    raise exception 'FIX5_REQUIRES_CHARACTER_BREAKTHROUGH_STATES';
  end if;
  if not exists (
    select 1 from information_schema.columns
    where table_schema='public' and table_name='character_breakthrough_states' and column_name='heavenly_insight_count'
  ) then
    raise exception 'FIX5_REQUIRES_HEAVENLY_INSIGHT_COUNT';
  end if;
end;
$$;

-- 状态页：感悟在原始目标尚未抵达前，对当前恢复路线上的每次突破均生效。
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
  v_bonus:=least(0.80,greatest(0,v_insights*0.05));
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

-- 正式结算：服务端实际判定使用与状态页完全相同的累计感悟加成。
create or replace function public.attempt_breakthrough_v1()
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
  v_effective:=least(0.80,greatest(0,v_base+v_normal+v_insights*0.05));
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

comment on function public.get_breakthrough_status_v1() is
'V0.14.1 FIX5：天劫感悟每丝+5个百分点；跌境恢复途中持续生效，抵达原始目标后清除，最终成功率不超过80%。';
comment on function public.attempt_breakthrough_v1() is
'V0.14.1 FIX5：修复跌落境界后感悟被隐藏；已有感悟对恢复途中及原始目标突破持续生效，抵达原始目标后清零。';

-- 已部署CACHE1时，提高服务器缓存代号，使客户端尽快重新读取状态。
do $$
begin
  if to_regclass('public.jiuxiao_app_release_control') is not null then
    update public.jiuxiao_app_release_control
    set cache_epoch=greatest(cache_epoch+1,2),
        release_name='V0.14.1 FIX5 CACHE2',
        notice_text='突破成功率规则已修复，正在重新加载。',
        updated_at=now()
    where singleton_id=1;
  end if;
end;
$$;

notify pgrst, 'reload schema';

commit;

-- 部署后自检：所有ok均应为true。
with defs as (
  select
    pg_get_functiondef(to_regprocedure('public.get_breakthrough_status_v1()')) as status_def,
    pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')) as attempt_def
)
select * from (
  values
    ('status_function_exists', to_regprocedure('public.get_breakthrough_status_v1()') is not null, '突破状态函数存在'),
    ('attempt_function_exists', to_regprocedure('public.attempt_breakthrough_v1()') is not null, '突破结算函数存在'),
    ('status_bonus_always_uses_insight', (select status_def like '%v_bonus:=least(0.80,greatest(0,v_insights*0.05));%' from defs), '状态页不再因跌境隐藏感悟'),
    ('attempt_bonus_always_uses_insight', (select attempt_def like '%v_base+v_normal+v_insights*0.05%' from defs), '服务端判定始终使用累计感悟'),
    ('old_target_gate_removed_status', (select status_def not like '%v_target_id=v_next.id then%' from defs), '状态页旧目标门控已移除'),
    ('old_target_gate_removed_attempt', (select attempt_def not like '%v_original_target_id=v_next.id then%' from defs), '结算旧目标门控已移除'),
    ('three_insights_equal_15_percent', round(3*0.05::numeric,2)=0.15::numeric, '3丝感悟等于15个百分点'),
    ('success_rate_cap_is_80_percent', (select status_def like '%v_final:=least(0.80%' and attempt_def like '%v_effective:=least(0.80%' from defs), '最终成功率上限仍为80%')
) as checks(check_name,ok,detail)
order by check_name;
