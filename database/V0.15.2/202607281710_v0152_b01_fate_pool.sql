-- 九霄问道 B模块 B01-R1：命格方案A + 赌坊奖池抽中必得 + 七成发放三成留池
-- 锁定基线：V0.15.1_AB10_CACHE18
-- 身份：B线候选模块；不得视为正式发布迁移，须由A线核验、合并、升版。
-- 范围：命格基础/专属效果、突破百折、机缘配置化、奖池取消40/60二次判定并实行70%发放上限。
-- 保护：不修改版本号、缓存代号、Pages工作流、鱼虾40秒阶段；不突破修为硬上限。

begin;

create schema if not exists ncd_b_module_backup;
create table if not exists ncd_b_module_backup.b01_fates (
  code text primary key,name text,rarity text,description text,modifiers jsonb,trigger_rules jsonb
);
insert into ncd_b_module_backup.b01_fates(code,name,rarity,description,modifiers,trigger_rules)
select code,name,rarity,description,modifiers,trigger_rules from public.fates
where code in('late_bloomer','lucky_encounter','unyielding_heart','sword_heart','heaven_jealous')
on conflict(code) do nothing;

create table if not exists ncd_b_module_backup.b01_functions (
  signature text primary key,function_def text not null
);
insert into ncd_b_module_backup.b01_functions(signature,function_def)
select x.signature,pg_get_functiondef(to_regprocedure(x.signature))
from (values
 ('public.claim_cultivation_v1()'),
 ('public.get_breakthrough_status_v1()'),
 ('public.attempt_breakthrough_v1()'),
 ('public.opportunity_v3_auspicious_probability_v1(numeric,numeric,boolean)'),
 ('public.settle_opportunity_v4(boolean)'),
 ('public.casino_draw_pools_v1()')
) x(signature)
where to_regprocedure(x.signature) is not null
on conflict(signature) do nothing;

create table if not exists ncd_b_module_backup.b01_settings (
  key text primary key,value jsonb not null
);
insert into ncd_b_module_backup.b01_settings(key,value)
select 'casino_pool_hit_chance',to_jsonb(pool_hit_chance) from public.casino_settings where singleton_id=1
on conflict(key) do nothing;
insert into ncd_b_module_backup.b01_settings(key,value)
values('unyielding_column_preexisted',to_jsonb(exists(select 1 from information_schema.columns where table_schema='public' and table_name='character_breakthrough_states' and column_name='unyielding_stack_count')))
on conflict(key) do nothing;
insert into ncd_b_module_backup.b01_settings(key,value)
values('last_attempt_column_preexisted',to_jsonb(exists(select 1 from information_schema.columns where table_schema='public' and table_name='character_breakthrough_states' and column_name='last_attempt_at')))
on conflict(key) do nothing;
insert into ncd_b_module_backup.b01_settings(key,value)
values('unyielding_constraint_preexisted',to_jsonb(exists(select 1 from pg_constraint where conname='character_breakthrough_states_unyielding_stack_count_check')))
on conflict(key) do nothing;

alter table public.character_breakthrough_states
  add column if not exists unyielding_stack_count integer not null default 0,
  add column if not exists last_attempt_at timestamptz;
do $$ begin
  if not exists(select 1 from pg_constraint where conname='character_breakthrough_states_unyielding_stack_count_check') then
    alter table public.character_breakthrough_states add constraint character_breakthrough_states_unyielding_stack_count_check check(unyielding_stack_count between 0 and 4);
  end if;
end $$;

update public.fates set
  rarity='普通',
  description='修炼速度增加10%。年满100岁后，每增长1岁，额外增加0.1个百分点修炼速度，最多额外增加25个百分点。',
  modifiers=jsonb_build_object('base_cultivation',0.10,'annual_cultivation_gain',0.001,'max_age_cultivation_gain',0.25),
  trigger_rules=jsonb_build_object('growth_start_age',100)
where code='late_bloomer';

update public.fates set
  rarity='优秀',
  description='修炼速度增加15%。机缘趋吉概率额外增加5个百分点，专属及地品以上机缘的出现权重提高10%。',
  modifiers=jsonb_build_object('base_cultivation',0.15,'good_event_chance_bonus',0.05,'high_grade_event_weight_multiplier',1.10),
  trigger_rules='{}'::jsonb
where code='lucky_encounter';

update public.fates set
  rarity='优秀',
  description='修炼速度增加15%。实际受到突破失败惩罚时额外获得1层百折；每层使突破成功率增加5个百分点，最多4层；突破成功后与天劫感悟一起清空。',
  modifiers=jsonb_build_object('base_cultivation',0.15,'failure_stack_bonus',0.05,'failure_stack_limit',4),
  trigger_rules='{}'::jsonb
where code='unyielding_heart';

update public.fates set
  rarity='稀有',
  description='修炼速度增加25%。战斗系统开放后，战斗属性提高10%。',
  modifiers=jsonb_build_object('base_cultivation',0.25,'combat_attribute_bonus',0.10,'combat_effect_enabled',false),
  trigger_rules='{}'::jsonb
where code='sword_heart';

update public.fates set
  rarity='传说',
  description='修炼速度增加35%。元婴期及以上渡劫成功率降低5个百分点。',
  modifiers=jsonb_build_object('base_cultivation',0.35,'tribulation_success_penalty',0.05),
  trigger_rules=jsonb_build_object('tribulation_from_major_order',4)
where code='heaven_jealous';

-- 旧百折字段若曾被其他草案写入，不继承为层数；模块从0层开始。
update public.character_breakthrough_states set unyielding_stack_count=least(4,greatest(0,unyielding_stack_count));

-- 奖池历史设置同步为100%，但正式开奖函数不再依赖二次概率。
update public.casino_settings set pool_hit_chance=1.00000 where singleton_id=1;


-- ============================================================
-- B01 命格配置与通用计算函数
-- ============================================================
create or replace function public.character_fate_cultivation_bonus_b01(
  p_character_id uuid,
  p_age integer
)
returns numeric
language sql
stable
security definer
set search_path=public,pg_temp
as $$
  select coalesce(sum(
    coalesce((f.modifiers->>'base_cultivation')::numeric,0)
    + case when f.code='late_bloomer' then least(
        greatest(0,coalesce((f.modifiers->>'max_age_cultivation_gain')::numeric,0.25)),
        greatest(0,coalesce(p_age,0)-coalesce((f.trigger_rules->>'growth_start_age')::integer,100))
          * greatest(0,coalesce((f.modifiers->>'annual_cultivation_gain')::numeric,0.001))
      ) else 0 end
  ),0)
  from public.character_fates cf
  join public.fates f on f.id=cf.fate_id
  where cf.character_id=p_character_id and cf.is_active
$$;

revoke all on function public.character_fate_cultivation_bonus_b01(uuid,integer) from public,anon,authenticated;

create or replace function public.fate_lucky_high_grade_multiplier_b01()
returns numeric
language sql
stable
security definer
set search_path=public,pg_temp
as $$
  select greatest(1,coalesce((select (f.modifiers->>'high_grade_event_weight_multiplier')::numeric from public.fates f where f.code='lucky_encounter' limit 1),1.10))
$$;

revoke all on function public.fate_lucky_high_grade_multiplier_b01() from public,anon,authenticated;

create or replace function public.opportunity_v3_auspicious_probability_v1(
  p_luck numeric,
  p_mindset numeric,
  p_has_lucky_encounter boolean default false
)
returns numeric
language sql
stable
security definer
set search_path=public,pg_temp
as $$
  select least(
    90::numeric,
    greatest(
      10::numeric,
      50::numeric
      + ((coalesce(p_luck,50)+coalesce(p_mindset,50)-100)*0.5)
      + case when coalesce(p_has_lucky_encounter,false) then
          100*coalesce((select (f.modifiers->>'good_event_chance_bonus')::numeric from public.fates f where f.code='lucky_encounter' limit 1),0.05)
        else 0 end
    )
  )
$$;

revoke all on function public.opportunity_v3_auspicious_probability_v1(numeric,numeric,boolean) from public,anon,authenticated;

create or replace function public.get_character_fate_status_b01()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_user uuid:=auth.uid();
  v_character public.player_characters%rowtype;
  v_fate public.fates%rowtype;
  v_stacks integer:=0;
  v_base numeric:=0;
  v_growth numeric:=0;
  v_total numeric:=0;
  v_start_age integer:=100;
  v_annual numeric:=0.001;
  v_growth_max numeric:=0.25;
  v_special_name text;
  v_special_description text;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  select pc.* into v_character from public.player_characters pc
  where pc.user_id=v_user and pc.status in('active','secluded','missing')
  order by pc.created_at desc limit 1;
  if v_character.id is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;
  select f.* into v_fate from public.character_fates cf join public.fates f on f.id=cf.fate_id
  where cf.character_id=v_character.id and cf.is_active order by cf.created_at limit 1;
  if v_fate.id is null then return jsonb_build_object('status','no_fate','character_id',v_character.id); end if;
  select coalesce(bs.unyielding_stack_count,0) into v_stacks from public.character_breakthrough_states bs where bs.character_id=v_character.id;
  v_stacks:=coalesce(v_stacks,0);
  v_base:=coalesce((v_fate.modifiers->>'base_cultivation')::numeric,0);
  v_start_age:=coalesce((v_fate.trigger_rules->>'growth_start_age')::integer,100);
  v_annual:=coalesce((v_fate.modifiers->>'annual_cultivation_gain')::numeric,0.001);
  v_growth_max:=coalesce((v_fate.modifiers->>'max_age_cultivation_gain')::numeric,0.25);
  if v_fate.code='late_bloomer' then
    v_growth:=least(greatest(0,v_growth_max),greatest(0,v_character.age-v_start_age)*greatest(0,v_annual));
  end if;
  v_total:=v_base+v_growth;
  v_special_name:=case v_fate.code when 'late_bloomer' then '厚积薄发' when 'lucky_encounter' then '福缘天成' when 'unyielding_heart' then '败而弥坚' when 'sword_heart' then '剑心通明' when 'heaven_jealous' then '天妒劫身' else '命格专属' end;
  v_special_description:=case v_fate.code
    when 'late_bloomer' then format('年满%s岁后，每增长1岁，额外增加%s个百分点修炼速度，最多额外增加%s个百分点。',v_start_age,trim(to_char(v_annual*100,'FM999990.##')),trim(to_char(v_growth_max*100,'FM999990.##')))
    when 'lucky_encounter' then format('机缘趋吉概率额外增加%s个百分点，专属及地品以上机缘出现权重提高%s%%。',trim(to_char(coalesce((v_fate.modifiers->>'good_event_chance_bonus')::numeric,0.05)*100,'FM999990.##')),trim(to_char((coalesce((v_fate.modifiers->>'high_grade_event_weight_multiplier')::numeric,1.10)-1)*100,'FM999990.##')))
    when 'unyielding_heart' then format('实际受到突破失败惩罚时额外获得1层百折；每层突破成功率增加%s个百分点，最多%s层；突破成功后与天劫感悟一起清空。',trim(to_char(coalesce((v_fate.modifiers->>'failure_stack_bonus')::numeric,0.05)*100,'FM999990.##')),coalesce((v_fate.modifiers->>'failure_stack_limit')::integer,4))
    when 'sword_heart' then format('战斗系统开放后，战斗属性提高%s%%。',trim(to_char(coalesce((v_fate.modifiers->>'combat_attribute_bonus')::numeric,0.10)*100,'FM999990.##')))
    when 'heaven_jealous' then format('元婴期及以上渡劫成功率降低%s个百分点。',trim(to_char(coalesce((v_fate.modifiers->>'tribulation_success_penalty')::numeric,0.05)*100,'FM999990.##')))
    else coalesce(v_fate.description,'') end;
  return jsonb_build_object(
    'status','ok','character_id',v_character.id,'code',v_fate.code,'name',v_fate.name,'rarity',v_fate.rarity,
    'base_cultivation_bonus',v_base,'current_special_cultivation_bonus',v_growth,'total_cultivation_bonus',v_total,
    'special_name',v_special_name,'special_description',v_special_description,
    'growth_start_age',v_start_age,'annual_cultivation_gain',v_annual,'max_age_cultivation_gain',v_growth_max,'current_age',v_character.age,
    'good_event_chance_bonus',coalesce((v_fate.modifiers->>'good_event_chance_bonus')::numeric,0),
    'high_grade_event_weight_multiplier',coalesce((v_fate.modifiers->>'high_grade_event_weight_multiplier')::numeric,1),
    'unyielding_stack_count',case when v_fate.code='unyielding_heart' then v_stacks else 0 end,
    'unyielding_stack_limit',coalesce((v_fate.modifiers->>'failure_stack_limit')::integer,0),
    'unyielding_stack_bonus',coalesce((v_fate.modifiers->>'failure_stack_bonus')::numeric,0),
    'unyielding_current_bonus',case when v_fate.code='unyielding_heart' then v_stacks*coalesce((v_fate.modifiers->>'failure_stack_bonus')::numeric,0) else 0 end,
    'combat_attribute_bonus',coalesce((v_fate.modifiers->>'combat_attribute_bonus')::numeric,0),
    'combat_effect_enabled',coalesce((v_fate.modifiers->>'combat_effect_enabled')::boolean,false),
    'tribulation_success_penalty',coalesce((v_fate.modifiers->>'tribulation_success_penalty')::numeric,0)
  );
end
$$;

revoke all on function public.get_character_fate_status_b01() from public,anon;
grant execute on function public.get_character_fate_status_b01() to authenticated;

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
  v_insight_multiplier numeric := 1;
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

  v_insight_multiplier := public.heavenly_insight_cultivation_multiplier_v0144(v_character_id);

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

  -- B01：所有命格先吃基础修炼加成；大器晚成再叠加年龄专属成长。
  v_fate_bonus := public.character_fate_cultivation_bonus_b01(v_character_id, v_age);

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

    select
      coalesce(sum(e.flat_rate_per_second), 0),
      coalesce(sum(e.multiplier_bonus) filter (where e.source_type <> 'opportunity_v4'), 0)
      + coalesce(max(e.multiplier_bonus) filter (where e.source_type = 'opportunity_v4' and e.multiplier_bonus > 0), 0)
      + coalesce(min(e.multiplier_bonus) filter (where e.source_type = 'opportunity_v4' and e.multiplier_bonus < 0), 0)
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
    v_segment_rate := greatest(0, v_segment_fixed_rate * v_effective_qi_multiplier * v_insight_multiplier);
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

  select
    coalesce(sum(e.flat_rate_per_second), 0),
    coalesce(sum(e.multiplier_bonus) filter (where e.source_type <> 'opportunity_v4'), 0)
    + coalesce(max(e.multiplier_bonus) filter (where e.source_type = 'opportunity_v4' and e.multiplier_bonus > 0), 0)
    + coalesce(min(e.multiplier_bonus) filter (where e.source_type = 'opportunity_v4' and e.multiplier_bonus < 0), 0)
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
  v_current_rate := greatest(0, v_current_fixed_rate * v_effective_qi_multiplier * v_insight_multiplier);
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
        'mode', 'automatic_v0144_insight_total_multiplier',
        'elapsed_seconds', v_elapsed,
        'realm_base_rate', v_base_rate,
        'rate_before_heaven', v_current_fixed_rate,
        'rate_per_second', v_current_rate,
        'root_multiplier', v_root_multiplier,
        'world_qi_base', v_qi_base,
        'heaven_balance_coefficient', v_heaven_coefficient,
        'effective_qi_multiplier', v_effective_qi_multiplier,
        'heavenly_insight_multiplier', v_insight_multiplier,
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
  v_fate_code text;v_fate_penalty numeric:=0;v_unyielding_stacks integer:=0;v_unyielding_bonus numeric:=0;v_unyielding_per_stack numeric:=0.05;v_unyielding_limit integer:=4;
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
      0::numeric,0::numeric,0::numeric,0.95::numeric,0,0,0,null::smallint,null::text,v_character.adversity,0,null::text,null::text,
      v_penalty,'元婴期'::text,false,null::text,public.realm_base_cultivation_rate_v1(v_current.id),null::numeric,null::bigint,false;
    return;
  end if;
  select rs.* into v_next from public.realm_stages rs where rs.id=v_next_id;v_cap:=v_next.cultivation_required;
  select coalesce(bs.total_failure_count,bs.failure_count,0),coalesce(bs.heavenly_insight_count,0),coalesce(bs.unyielding_stack_count,0),bs.original_target_stage_id,ots.stage_name,
         bs.affliction_code,bs.affliction_name,coalesce(bs.major_fall_used,false),mfs.stage_name
  into v_total_failures,v_insights,v_unyielding_stacks,v_target_id,v_target_name,v_affliction_code,v_affliction_name,v_major_used,v_major_origin_name
  from (select 1) seed left join public.character_breakthrough_states bs on bs.character_id=v_character.id
  left join public.realm_stages ots on ots.id=bs.original_target_stage_id left join public.realm_stages mfs on mfs.id=bs.major_fall_origin_stage_id;
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
  v_unyielding_bonus:=case when v_fate_code='unyielding_heart' then least(greatest(0,v_unyielding_stacks),greatest(0,v_unyielding_limit))*greatest(0,v_unyielding_per_stack) else 0 end;
  v_bonus:=greatest(0,v_insights*0.05)+v_unyielding_bonus;
  v_final:=least(0.95,greatest(0,v_base+v_normal-v_fate_penalty+v_bonus));
  select s.breakthrough_enabled into v_enabled from public.progression_v0130_settings s where s.singleton_id=1;
  return query select case when coalesce(v_enabled,true) then 'available' else 'disabled' end,v_character.id,v_current.id,v_current.stage_name,v_next.id,v_next.stage_name,
    v_character.cultivation,v_next.cultivation_required,round(v_final,4),round(greatest(0,v_base+v_normal),4),round(greatest(0,v_insights*0.05),4),0.95::numeric,
    v_total_failures,v_total_failures,v_insights,v_target_id,v_target_name,v_character.adversity,coalesce(v_next.lifespan_bonus,0),v_affliction_code,v_affliction_name,
    v_penalty,'元婴期'::text,v_major_used,v_major_origin_name,public.realm_base_cultivation_rate_v1(v_current.id),public.realm_base_cultivation_rate_v1(v_next.id),
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
language plpgsql security definer set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=auth.uid();v_character public.player_characters%rowtype;v_current public.realm_stages%rowtype;v_next public.realm_stages%rowtype;
  v_next_id smallint;v_base numeric:=0;v_normal numeric:=0;v_effective numeric:=0;v_total_failures integer:=0;v_insights integer:=0;
  v_fate_code text;v_fate_penalty numeric:=0;v_unyielding_stacks integer:=0;v_unyielding_bonus numeric:=0;v_unyielding_per_stack numeric:=0.05;v_unyielding_limit integer:=4;v_last_attempt_at timestamptz;
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
  select coalesce(bs.total_failure_count,bs.failure_count,0),coalesce(bs.heavenly_insight_count,0),coalesce(bs.unyielding_stack_count,0),bs.last_attempt_at,bs.original_target_stage_id,ots.stage_name,
         bs.affliction_code,bs.affliction_name,bs.affliction_steps_remaining,coalesce(bs.major_fall_used,false),bs.major_fall_origin_stage_id
  into v_total_failures,v_insights,v_unyielding_stacks,v_last_attempt_at,v_original_target_id,v_original_target_name,v_affliction_code,v_affliction_name,v_affliction_steps,v_major_used,v_major_origin_id
  from public.character_breakthrough_states bs left join public.realm_stages ots on ots.id=bs.original_target_stage_id
  where bs.character_id=v_character.id for update of bs;
  -- B01：兼容旧零参数RPC的服务端短窗去重，阻止双击/网络重放重复增加感悟与百折。
  if v_last_attempt_at is not null and v_last_attempt_at>clock_timestamp()-interval '3 seconds' then
    raise exception 'BREAKTHROUGH_REQUEST_TOO_FREQUENT';
  end if;
  update public.character_breakthrough_states set last_attempt_at=clock_timestamp(),updated_at=now() where character_id=v_character.id;
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
  v_unyielding_bonus:=case when v_fate_code='unyielding_heart' then least(greatest(0,v_unyielding_stacks),greatest(0,v_unyielding_limit))*greatest(0,v_unyielding_per_stack) else 0 end;
  v_effective:=least(0.95,greatest(0,v_base+v_normal-v_fate_penalty+v_insights*0.05+v_unyielding_bonus));
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
    -- B01：任意一次真实突破成功后，天劫感悟与百折层数同时清空。
    update public.character_breakthrough_states set original_target_stage_id=null,failure_count=0,total_failure_count=0,
      heavenly_insight_count=0,compensation_bonus=0,unyielding_stack_count=0,
      affliction_code=v_affliction_code,affliction_name=v_affliction_name,affliction_steps_remaining=v_affliction_steps,
      major_fall_used=v_major_used,major_fall_origin_stage_id=v_major_origin_id,last_failure_result=null,updated_at=now()
    where character_id=v_character.id;
    v_total_failures:=0;v_insights:=0;v_unyielding_stacks:=0;v_original_target_name:=null;
    insert into public.cultivation_records(character_id,world_year,action_type,years_spent,cultivation_before,cultivation_delta,cultivation_after,result,calculation_snapshot)
    select v_character.id,gw.current_year,'breakthrough',0,v_character.cultivation,0,v_character.cultivation,'success',
      jsonb_build_object('version','0.13.0','from_stage',v_current.stage_name,'to_stage',v_next.stage_name,'effective_success_rate',v_effective,
      'heavenly_insight_count',v_insights,'unyielding_stack_count',v_unyielding_stacks,'fate_code',v_fate_code,'fate_success_modifier',-v_fate_penalty,'original_target',v_original_target_name) from public.game_worlds gw where gw.id=v_character.world_id;
    return query select true,'success'::text,v_next.stage_name,v_next.stage_name,('道关已开，成功踏入'||v_next.stage_name||'。')::text,
      v_character.cultivation,v_character.cultivation,0::bigint,coalesce(v_next.lifespan_bonus,0),v_character.adversity,v_total_failures,v_total_failures,
      v_insights,false,0::numeric,round(v_effective,4),v_affliction_code,v_affliction_name,v_original_target_name,false;
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

  if v_insight_gained then
    v_insights:=v_insights+1;
    if v_fate_code='unyielding_heart' then
      v_unyielding_stacks:=least(greatest(0,v_unyielding_limit),v_unyielding_stacks+1);
      v_message:=v_message||format(' 百折道心凝成第%s层百折，额外增加%s个百分点突破成功率。',v_unyielding_stacks,trim(to_char(v_unyielding_stacks*v_unyielding_per_stack*100,'FM999990.##')));
    end if;
  end if;
  if not v_dead then
    update public.character_breakthrough_states set original_target_stage_id=v_original_target_id,failure_count=v_total_failures,total_failure_count=v_total_failures,
      heavenly_insight_count=v_insights,compensation_bonus=v_insights*0.05,unyielding_stack_count=v_unyielding_stacks,affliction_code=v_affliction_code,affliction_name=v_affliction_name,
      affliction_steps_remaining=v_affliction_steps,major_fall_used=v_major_used,major_fall_origin_stage_id=v_major_origin_id,last_failure_result=v_outcome,updated_at=now()
    where character_id=v_character.id;
  end if;
  insert into public.cultivation_records(character_id,world_year,action_type,years_spent,cultivation_before,cultivation_delta,cultivation_after,result,calculation_snapshot)
  select v_character.id,gw.current_year,'breakthrough',0,v_character.cultivation,v_after-v_character.cultivation,v_after,'failure',
    jsonb_build_object('version','0.13.0','outcome',v_outcome,'from_stage',v_current.stage_name,'attempted_stage',v_next.stage_name,
      'effective_success_rate',v_effective,'total_failure_count',v_total_failures,'heavenly_insight_count',v_insights,'insight_gained',v_insight_gained,
      'compensation_bonus',v_insights*0.05,'unyielding_stack_count',v_unyielding_stacks,'unyielding_bonus',case when v_fate_code='unyielding_heart' then v_unyielding_stacks*v_unyielding_per_stack else 0 end,'fate_code',v_fate_code,'fate_success_modifier',-v_fate_penalty,'original_target',v_original_target_name,'affliction',v_affliction_name,
      'penalty_enabled',v_penalty,'cultivation_required_delta',v_required_delta,'cultivation_lost',greatest(0,v_character.cultivation-v_after))
  from public.game_worlds gw where gw.id=v_character.world_id;
  return query select false,v_outcome,v_next.stage_name,coalesce(v_target.stage_name,v_current.stage_name),v_message,v_character.cultivation,v_after,
    greatest(0,v_character.cultivation-v_after),0,v_adversity_after,v_total_failures,v_total_failures,v_insights,v_insight_gained,
    round(v_insights*0.05,4),round(v_effective,4),v_affliction_code,v_affliction_name,v_original_target_name,v_dead;
end;
$$;

create or replace function public.settle_opportunity_v4(p_settle_cultivation boolean default true)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  u uuid:=auth.uid();c public.player_characters%rowtype;st public.character_opportunity_v3_state%rowtype;cfg public.opportunity_v3_settings%rowtype;
  nowv timestamptz:=clock_timestamp();v_period_start timestamptz;v_event_at timestamptz;v_due integer:=0;v_capped integer:=0;v_gap numeric:=0;v_offline boolean:=false;
  v_batch uuid:=gen_random_uuid();v_grade text;v_path text;v_story record;v_result record;v_effect jsonb;v_applied jsonb;v_result_id uuid;
  v_fate_code text;v_lucky boolean:=false;v_ausp numeric:=50;v_roll numeric;v_total numeric;v_boost numeric:=1;
  w_ex numeric:=0.2;w_im numeric:=0.5;w_he numeric:=1.5;w_ea numeric:=8;w_my numeric:=25;w_ye numeric:=64.8;
  v_grade_counts jsonb:='{"黄品":0,"玄品":0,"地品":0,"天品":0,"仙品":0,"专属":0}'::jsonb;
  v_path_counts jsonb:='{"趋吉":0,"涉险":0}'::jsonb;
  v_cgain_req bigint:=0;v_closs_req bigint:=0;v_sgain bigint:=0;v_sloss bigint:=0;v_actual_gain bigint:=0;v_actual_loss bigint:=0;
  v_claim jsonb:=null;v_summary jsonb:=null;v_latest jsonb:=null;v_remaining jsonb:='{}'::jsonb;v_floor bigint:=0;v_before bigint;v_grant record;
  v_fate_has boolean:=false;v_has_own boolean:=false;v_pity numeric:=20;v_other numeric:=20;v_pick numeric;v_running numeric;v_exclusive record;v_acquired jsonb;
  v_rates record;v_tech_category text;v_tech_pool record;v_tech_award jsonb;v_tech_new jsonb:='[]'::jsonb;v_tech_dup jsonb:='[]'::jsonb;
  v_mastery integer:=0;v_permanent jsonb:='[]'::jsonb;v_items_gain jsonb:='{}'::jsonb;v_item record;v_item_amount numeric;
  v_book_add jsonb;v_book_gains jsonb:='{}'::jsonb;v_book_list jsonb:='[]'::jsonb;
begin
  if u is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into c from public.player_characters where user_id=u and status in('active','secluded','missing') order by created_at desc limit 1 for update;
  if c.id is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;
  select * into cfg from public.opportunity_v3_settings where world_code='jiuxiao_world_1';
  if cfg.world_code is null then raise exception 'OPPORTUNITY_SETTINGS_MISSING'; end if;
  insert into public.character_opportunity_v3_state(character_id,next_available_at,last_seen_at)
  values(c.id,nowv+interval '5 minutes',nowv) on conflict(character_id) do nothing;
  select * into st from public.character_opportunity_v3_state where character_id=c.id for update;
  select f.code into v_fate_code from public.character_fates cf join public.fates f on f.id=cf.fate_id where cf.character_id=c.id and cf.is_active order by cf.created_at limit 1;
  v_lucky:=coalesce(v_fate_code='lucky_encounter',false);
  v_ausp:=public.opportunity_v3_auspicious_probability_v1(c.luck,c.mindset,v_lucky);
  v_period_start:=least(coalesce(st.last_seen_at,nowv),nowv);v_gap:=greatest(0,extract(epoch from(nowv-v_period_start)));v_offline:=v_gap>=300;
  if cfg.enabled and nowv>=st.next_available_at then
    v_due:=floor(extract(epoch from(nowv-st.next_available_at))/300)::integer+1;
    v_capped:=greatest(0,v_due-least(v_due,coalesce(cfg.offline_catchup_limit,864)));v_due:=least(v_due,coalesce(cfg.offline_catchup_limit,864));
  end if;

  if v_due>0 then
    for i in 0..v_due-1 loop
      v_event_at:=st.next_available_at+make_interval(secs=>300*i);
      if v_lucky then v_boost:=public.fate_lucky_high_grade_multiplier_b01(); else v_boost:=1; end if;
      w_ex:=0.2*v_boost;w_im:=0.5*v_boost;w_he:=1.5*v_boost;w_ea:=8*v_boost;w_my:=25;w_ye:=64.8;v_total:=w_ex+w_im+w_he+w_ea+w_my+w_ye;v_roll:=random()*v_total;
      if v_roll<w_ex then v_grade:='专属';elsif v_roll<w_ex+w_im then v_grade:='仙品';elsif v_roll<w_ex+w_im+w_he then v_grade:='天品';elsif v_roll<w_ex+w_im+w_he+w_ea then v_grade:='地品';elsif v_roll<w_ex+w_im+w_he+w_ea+w_my then v_grade:='玄品';else v_grade:='黄品';end if;
      v_path:=case when random()*100<v_ausp then 'auspicious' else 'risk' end;
      select * into v_story from public.opportunity_v4_story_pool where grade=v_grade and polarity=v_path and is_active order by -ln(greatest(random(),0.000001))/weight limit 1;
      if v_story.code is null then raise exception 'OPPORTUNITY_V4_STORY_MISSING:%:%',v_grade,v_path; end if;
      v_grade_counts:=jsonb_set(v_grade_counts,array[v_grade],to_jsonb(coalesce((v_grade_counts->>v_grade)::int,0)+1),true);
      v_path_counts:=jsonb_set(v_path_counts,array[case when v_path='auspicious' then '趋吉' else '涉险' end],to_jsonb(coalesce((v_path_counts->>(case when v_path='auspicious' then '趋吉' else '涉险' end))::int,0)+1),true);
      v_tech_award:=null;v_tech_category:=null;v_applied:='{}'::jsonb;

      if v_grade='专属' and v_path='auspicious' then
        select exists(select 1 from public.exclusive_technique_definitions where fate_code=v_fate_code) into v_fate_has;
        if v_fate_has then
          v_pity:=greatest(20,least(100,coalesce((st.exclusive_pity->>v_fate_code)::numeric,20)));
          v_other:=(100-v_pity)/4;
        else
          v_pity:=0;v_other:=20;
        end if;
        v_pick:=random()*100;v_running:=0;
        for v_exclusive in
          select etd.*,case when etd.fate_code=v_fate_code then v_pity else v_other end draw_weight
          from public.exclusive_technique_definitions etd order by etd.code
        loop
          v_running:=v_running+v_exclusive.draw_weight;
          if v_pick<=v_running then exit;end if;
        end loop;
        if v_exclusive.code is null then raise exception 'EXCLUSIVE_TECHNIQUE_POOL_MISSING';end if;
        v_book_add:=public.technique_book_add_v1(c.id,'exclusive',v_exclusive.code,1,v_event_at,jsonb_build_object('source','opportunity_v4','grade','专属'));
        v_acquired:=coalesce(st.acquired_exclusive_codes,'[]'::jsonb);
        if not(v_acquired@>jsonb_build_array(v_exclusive.code)) then v_acquired:=v_acquired||jsonb_build_array(v_exclusive.code);end if;
        st.acquired_exclusive_codes:=v_acquired;
        if v_exclusive.fate_code=v_fate_code then
          select * into v_result from public.opportunity_v4_result_pool where grade='专属' and polarity='auspicious' and effect_spec->>'exclusive_outcome'='success' and is_active order by random() limit 1;
          st.exclusive_pity:=jsonb_set(coalesce(st.exclusive_pity,'{}'::jsonb),array[v_fate_code],to_jsonb(20),true);
          v_result.title:='本命专属道卷·'||v_exclusive.name;
          v_result.narrative:='本命天机与你的命格共鸣，获得专属道卷《'||v_exclusive.name||'》×1，已收入洞府藏经架。可自行研习，研习后不会自动装备。';
        else
          select * into v_result from public.opportunity_v4_result_pool where grade='专属' and polarity='auspicious' and effect_spec->>'exclusive_outcome'='mismatch' and is_active order by random() limit 1;
          if v_fate_has then v_pity:=least(100,v_pity+2);st.exclusive_pity:=jsonb_set(coalesce(st.exclusive_pity,'{}'::jsonb),array[v_fate_code],to_jsonb(v_pity),true);end if;
          v_result.title:='异命专属道卷·'||v_exclusive.name;
          v_result.narrative:='获得异命专属道卷《'||v_exclusive.name||'》×1，已收入洞府藏经架。此道卷与你当前命格不契合，只能收藏，不能研习。';
        end if;
        update public.character_opportunity_v3_state set acquired_exclusive_codes=st.acquired_exclusive_codes,exclusive_pity=st.exclusive_pity,updated_at=nowv where character_id=c.id;
        v_effect='{}'::jsonb;
        v_applied:=jsonb_build_object('cultivation_gain_requested',0,'cultivation_loss_requested',0,'spirit_gain',0,'spirit_loss',0,'speed_bonus',0,'duration_minutes',0);
        v_tech_award:=jsonb_build_object(
          'awarded',true,'book_kind','exclusive','technique_code',v_exclusive.code,'technique_name',v_exclusive.name,
          'grade','专属','category','exclusive','quantity_added',1,'quantity_total',coalesce((v_book_add->>'quantity_total')::int,1),
          'is_matching_fate',(v_exclusive.fate_code=v_fate_code),'applied',v_applied,'narrative',v_result.narrative
        );
        v_book_gains:=public.technique_book_summary_add_v1(v_book_gains,v_tech_award);
      elsif v_path='auspicious' and v_grade in('玄品','地品','天品','仙品') then
        select * into v_rates from public.opportunity_v4_technique_drop_rates where grade=v_grade;
        v_roll:=random();
        if v_roll<coalesce(v_rates.main_rate,0) then v_tech_category:='main';
        elsif v_roll<coalesce(v_rates.main_rate,0)+coalesce(v_rates.support_rate,0) then v_tech_category:='support';end if;
        if v_tech_category is not null then
          select * into v_tech_pool from public.opportunity_v4_technique_pool where grade=v_grade and category=v_tech_category and is_active order by -ln(greatest(random(),0.000001))/weight limit 1;
          if v_tech_pool.technique_code is null then raise exception 'OPPORTUNITY_V4_TECHNIQUE_POOL_MISSING:%:%',v_grade,v_tech_category;end if;
          v_tech_award:=public.opportunity_v4_award_ordinary_technique(c.id,c.lineage_id,greatest(1,c.birth_year+c.age),v_tech_pool.technique_code,v_event_at);
          select ('technique:'||v_tech_pool.technique_code)::text as code,('功法书·'||v_tech_pool.technique_name)::text as title,(v_tech_award->>'narrative')::text as narrative,'{}'::jsonb as effect_spec into v_result;
          v_effect:='{}'::jsonb;v_applied:=coalesce(v_tech_award->'applied','{}'::jsonb);
          v_book_gains:=public.technique_book_summary_add_v1(v_book_gains,v_tech_award);
        else
          select * into v_result from public.opportunity_v4_result_pool where grade=v_grade and polarity=v_path and is_active order by -ln(greatest(random(),0.000001))/weight limit 1;
          v_effect:=v_result.effect_spec;
        end if;
      else
        select * into v_result from public.opportunity_v4_result_pool where grade=v_grade and polarity=v_path and is_active order by -ln(greatest(random(),0.000001))/weight limit 1;
        v_effect:=v_result.effect_spec;
      end if;

      if v_tech_award is null then
        if v_effect ? 'spirit_gain_fixed' then
          v_applied:=jsonb_build_object('cultivation_gain_requested',0,'cultivation_loss_requested',0,'spirit_gain',greatest(0,public.opportunity_v4_adjust_spirit_stones(c.id,(v_effect->>'spirit_gain_fixed')::bigint)),'spirit_loss',0,'speed_bonus',0,'duration_minutes',0);
        else
          v_applied:=public.opportunity_v4_prepare_effect(c.id,gen_random_uuid(),v_grade,v_path,v_effect,v_event_at);
        end if;
      end if;
      insert into public.opportunity_v3_results(character_id,catalog_code,rarity,path_key,reward_text,penalty_text,result_data,settlement_batch_id,scheduled_at)
      values(c.id,null,v_grade,v_path,case when v_path='auspicious' then v_result.narrative else '' end,case when v_path='risk' then v_result.narrative else null end,
        jsonb_build_object('v','opportunity_v4','story_code',v_story.code,'result_code',v_result.code,'title',v_result.title,'story',v_story.story,'applied',v_applied,'effect_spec',v_effect,'technique',v_tech_award),v_batch,v_event_at)
      returning id into v_result_id;
      update public.character_cultivation_effects set source_key='opportunity_v4:'||v_result_id::text,metadata=jsonb_set(metadata,'{result_id}',to_jsonb(v_result_id),true) where character_id=c.id and source_type='opportunity_v4' and starts_at=v_event_at and source_key like 'opportunity_v4:%' and metadata->>'grade'=v_grade;
      v_cgain_req:=v_cgain_req+coalesce((v_applied->>'cultivation_gain_requested')::bigint,0);v_closs_req:=v_closs_req+coalesce((v_applied->>'cultivation_loss_requested')::bigint,0);v_sgain:=v_sgain+coalesce((v_applied->>'spirit_gain')::bigint,0);v_sloss:=v_sloss+coalesce((v_applied->>'spirit_loss')::bigint,0);
      v_latest:=jsonb_build_object('result_id',v_result_id,'title',v_result.title,'content',v_story.story,'result_text',v_result.narrative,'rarity',v_grade,'rarity_name',v_grade,'path_name',case when v_path='auspicious' then '趋吉' else '涉险' end,'applied',v_applied,'technique',v_tech_award,'result_detail',public.opportunity_result_detail_v0147(jsonb_build_object('applied',v_applied,'technique',v_tech_award),v_path,case when v_path='auspicious' then v_result.narrative else '' end,case when v_path='risk' then v_result.narrative else null end),'created_at',v_event_at);
      if v_grade in('天品','仙品','专属') then
        insert into public.history_logs(world_id,world_year,scope_type,scope_id,event_type,title,content,importance,visibility,metadata)
        values(c.world_id,greatest(1,c.birth_year+c.age),'character',c.id,'opportunity','机缘·'||v_result.title,v_story.story||'【'||case when v_path='auspicious' then '趋吉所得' else '涉险结果' end||'】'||v_result.narrative,
          case v_grade when '专属' then 5 when '仙品' then 5 else 4 end,'owner',jsonb_build_object('v','opportunity_v4','result_id',v_result_id,'batch_id',v_batch,'scheduled_at',v_event_at,'applied',v_applied));
      end if;
    end loop;
  end if;

  if v_due>0 then
    update public.character_opportunity_v3_state set next_available_at=case when v_capped>0 then nowv+interval '5 minutes' else st.next_available_at+make_interval(secs=>300*v_due) end,last_seen_at=nowv,total_resolved=total_resolved+v_due,last_result=v_latest,updated_at=nowv where character_id=c.id;
  else update public.character_opportunity_v3_state set last_seen_at=nowv,updated_at=nowv where character_id=c.id;end if;

  if p_settle_cultivation then select to_jsonb(x) into v_claim from public.claim_cultivation_v1() x;end if;
  select pc.cultivation,coalesce(rs.cultivation_required,0) into v_before,v_floor from public.player_characters pc join public.realm_stages rs on rs.id=pc.realm_stage_id where pc.id=c.id for update;
  v_actual_loss:=least(v_closs_req,greatest(0,v_before-v_floor));if v_actual_loss>0 then update public.player_characters set cultivation=cultivation-v_actual_loss,updated_at=now() where id=c.id;end if;
  if v_cgain_req>0 then select * into v_grant from public.grant_cultivation_capped_v1(c.id,v_cgain_req,'opportunity_v4',jsonb_build_object('batch_id',v_batch));v_actual_gain:=coalesce(v_grant.granted_amount,0);end if;
  v_remaining:=public.opportunity_v4_remaining_effects(c.id,nowv);
  select coalesce(jsonb_agg(e.value order by e.value->>'book_kind',e.value->>'grade',e.value->>'name'),'[]'::jsonb)
    into v_book_list from jsonb_each(v_book_gains) e;
  if v_due>0 then
    insert into public.opportunity_v4_settlement_batches(id,character_id,period_started_at,period_ended_at,event_count,is_offline,capped_event_count,grade_counts,polarity_counts,gains,losses,net_result,remaining_effects,cultivation_claim,shown_at)
    values(v_batch,c.id,v_period_start,nowv,v_due,v_offline,v_capped,v_grade_counts,v_path_counts,
      jsonb_build_object('cultivation_direct',v_actual_gain,'spirit_stones',v_sgain,'items',v_items_gain,'technique_books',v_book_list,'techniques_new','[]'::jsonb,'techniques_duplicate','[]'::jsonb,'mastery_points',0,'permanent_effects','[]'::jsonb),
      jsonb_build_object('cultivation_direct',v_actual_loss,'spirit_stones',v_sloss,'items','{}'::jsonb),
      jsonb_build_object('cultivation',coalesce((v_claim->>'gained')::bigint,0)+v_actual_gain-v_actual_loss,'spirit_stones',v_sgain-v_sloss,'items',v_items_gain,'effects',v_remaining,'technique_books',v_book_list,'techniques_new','[]'::jsonb,'techniques_duplicate','[]'::jsonb,'mastery_points',0,'permanent_effects','[]'::jsonb),
      v_remaining,v_claim,case when v_offline then null else nowv end);
  end if;
  select to_jsonb(b) into v_summary from public.opportunity_v4_settlement_batches b where b.character_id=c.id and b.shown_at is null order by b.created_at desc limit 1;
  select * into st from public.character_opportunity_v3_state where character_id=c.id;
  if v_claim is not null then
    v_claim:=jsonb_set(v_claim,'{gained}',to_jsonb(coalesce((v_claim->>'gained')::bigint,0)+v_actual_gain-v_actual_loss),true);
    v_claim:=jsonb_set(v_claim,'{cultivation_total}',(select to_jsonb(cultivation) from public.player_characters where id=c.id),true);
  end if;
  return jsonb_build_object(
    'opportunity',jsonb_build_object('status','waiting','automatic',true,'next_available_at',st.next_available_at,'seconds_until_next',greatest(0,extract(epoch from(st.next_available_at-nowv))::int),'last_result',st.last_result,'auspicious_probability',v_ausp,'risk_probability',100-v_ausp,'lucky_auspicious_bonus',case when v_lucky then 100*coalesce((select (f.modifiers->>'good_event_chance_bonus')::numeric from public.fates f where f.code='lucky_encounter' limit 1),0.05) else 0 end,'online_interval_seconds',300,'offline_interval_seconds',300,'offline_catchup_limit',864),
    'cultivation',v_claim,'offline_summary',v_summary,'events_resolved',v_due,'capped_events',v_capped
  );
end$$;
revoke all on function public.settle_opportunity_v4(boolean) from public,anon;
grant execute on function public.settle_opportunity_v4(boolean) to authenticated;

create or replace function public.casino_draw_pools_v1()
returns integer
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  p record;
  v_candidate uuid;
  v_candidate_name text;
  v_participants integer:=0;
  v_pick integer:=0;
  v_interval integer:=coalesce((select s.draw_interval_seconds from public.casino_settings s where s.singleton_id=1),7200);
  v_result_text text;
  v_count integer:=0;
  v_credit jsonb;
  v_payout_target bigint:=0;
  v_granted bigint:=0;
  v_rollover bigint:=0;
begin
  for p in
    select * from public.casino_pools x
    where x.next_draw_at<=now()
    for update skip locked
  loop
    select count(*)::integer into v_participants
    from public.casino_tickets t
    join public.player_characters pc on pc.id=t.character_id and pc.status in('active','secluded','missing')
    where t.stake_type=p.stake_type and t.round_ends_at=p.next_draw_at;

    if v_participants>0 then
      v_pick:=floor(random()*v_participants)::integer;
      select t.character_id into v_candidate
      from public.casino_tickets t
      join public.player_characters pc on pc.id=t.character_id and pc.status in('active','secluded','missing')
      where t.stake_type=p.stake_type and t.round_ends_at=p.next_draw_at
      order by t.character_id
      offset v_pick limit 1;
    else
      v_candidate:=null;
    end if;

    select pc.name into v_candidate_name from public.player_characters pc where pc.id=v_candidate;

    if v_candidate is not null and p.amount>0 then
      -- B01-R1：票被抽中即中奖，不再进行40%/60%二次判定。
      -- 中奖者最多领取开奖前奖池的70%；整数奖励向下取整，至少30%留存下期。
      v_payout_target:=floor(p.amount::numeric*0.70)::bigint;
      if v_payout_target>0 then
        v_credit:=public.casino_credit_result_v0141(v_candidate,p.stake_type,v_payout_target);
        v_granted:=coalesce((v_credit->>'granted_amount')::bigint,0);
      else
        v_credit:=jsonb_build_object('granted_amount',0);
        v_granted:=0;
      end if;
      -- 修为受硬上限时，未承接部分也与基础30%一并滚存，因此实际留池可能高于30%。
      v_rollover:=greatest(0,p.amount-v_granted);

      if v_granted>0 then
        if p.stake_type='cultivation' and v_granted<v_payout_target then
          v_result_text:=format(
            '万运博弈楼从本期%s名参与者中等概率抽出【%s】。其票号既中，本期奖池共%s点修为，按七成上限可领取%s点，实际承接%s点；基础留存与受境界修为硬上限未承接部分共%s点修为留存下期。',
            v_participants,coalesce(v_candidate_name,'无名修士'),p.amount,v_payout_target,v_granted,v_rollover
          );
        else
          v_result_text:=format(
            '万运博弈楼从本期%s名参与者中等概率抽出【%s】。其票号既中，从本期%s%s奖池中领取%s%s（不超过七成），余下%s%s留存下期。',
            v_participants,coalesce(v_candidate_name,'无名修士'),p.amount,
            case when p.stake_type='cultivation' then '点修为' else '枚灵石' end,
            v_granted,case when p.stake_type='cultivation' then '点修为' else '枚灵石' end,
            v_rollover,case when p.stake_type='cultivation' then '点修为' else '枚灵石' end
          );
        end if;
      elsif v_payout_target=0 then
        v_result_text:=format(
          '万运博弈楼从本期%s名参与者中等概率抽出【%s】。其票号既中，但本期奖池仅%s%s，按七成向下取整后不足1单位，本期奖池全部留存下期。',
          v_participants,coalesce(v_candidate_name,'无名修士'),p.amount,
          case when p.stake_type='cultivation' then '点修为' else '枚灵石' end
        );
      else
        v_result_text:=format(
          '万运博弈楼从本期%s名参与者中等概率抽出【%s】。其票号既中，按七成上限本可领取%s点修为；但其修为已至当前境界硬上限，本期%s点修为全部留存下期。',
          v_participants,coalesce(v_candidate_name,'无名修士'),v_payout_target,p.amount
        );
      end if;

      insert into public.casino_draws(
        stake_type,round_ended_at,winner_character_id,candidate_character_id,
        prize_amount,pool_amount,ticket_count,did_hit,hit_chance,result_text
      ) values(
        p.stake_type,p.next_draw_at,case when v_granted>0 then v_candidate else null end,v_candidate,
        v_granted,p.amount,v_participants,true,1.00000,v_result_text
      );
      update public.casino_pools x
      set amount=v_rollover,last_draw_at=now(),last_winner_character_id=case when v_granted>0 then v_candidate else null end,last_prize=v_granted,
          last_draw_hit=true,last_candidate_character_id=v_candidate,last_ticket_count=v_participants,
          next_draw_at=now()+make_interval(secs=>v_interval),updated_at=now()
      where x.stake_type=p.stake_type;
      v_count:=v_count+1;
    else
      update public.casino_pools x
      set last_draw_at=now(),last_winner_character_id=null,last_prize=0,
          last_draw_hit=null,last_candidate_character_id=null,last_ticket_count=0,
          next_draw_at=now()+make_interval(secs=>v_interval),updated_at=now()
      where x.stake_type=p.stake_type;
    end if;

    delete from public.casino_tickets t
    where t.stake_type=p.stake_type and t.round_ends_at=p.next_draw_at;
    v_candidate:=null;v_candidate_name:=null;v_participants:=0;v_pick:=0;
    v_credit:=null;v_payout_target:=0;v_granted:=0;v_rollover:=0;
  end loop;
  return v_count;
end;
$$;


comment on function public.get_character_fate_status_b01() is 'B01：返回当前命格基础效果、专属效果及百折/年龄实时状态。';
comment on function public.claim_cultivation_v1() is 'B01候选：五种命格统一吃base_cultivation；大器晚成100岁后每年+0.1个百分点，专属最多+25个百分点。';
comment on function public.get_breakthrough_status_v1() is 'B01候选：百折每层+5个百分点最多4层；天妒元婴及以上渡劫-5个百分点；最终成功率上限95%。';
comment on function public.attempt_breakthrough_v1() is 'B01候选：实际受罚失败时百折与天劫感悟同步增长；任意突破成功后同时清空。';
comment on function public.casino_draw_pools_v1() is 'B01-R1候选：奖池仅抽票一次，抽中即中奖；中奖者最多领取开奖前奖池70%，至少30%留存；修为硬上限未承接部分继续滚存。';

notify pgrst,'reload schema';
commit;
