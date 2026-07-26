-- 《九霄问道》Web Alpha V0.11.10 FIX1
-- 灵根双系数、境界基础吐纳、渡劫失败惩罚与失败补偿。
-- 执行基础：已部署 V0.11.9。
-- 重要规则：
-- 1. 灵根仅影响修炼系数与全部战斗属性系数，不影响资源、机缘或产量；
-- 2. 境界基础吐纳由当前境界唯一决定：首个境界 10/秒；同一大境界每前进一阶 +5；跨入下一大境界 +20；
-- 3. 天道动态系数在全部正常修炼收益结算完毕后最后相乘；
-- 4. 突破失败结果：1%死亡、5%跌大境界、15%跌小境界、30%清空本阶段、30%保留本阶段一半、19%无损；
-- 5. 失败补偿：首次失败 +10 个百分点，之后每次 +30 个百分点；补偿介入后的最终成功率最高 80%；
-- 6. 补偿绑定最初目标境界，中途恢复境界成功不清除，达到最初目标境界后清除；
-- 7. 同一恢复周期只允许跌落一次大境界，回到首次大跌境前所在的大境界后解除；
-- 8. 境界最低不得跌到元婴期以下；元婴期以下突破失败不触发任何惩罚，但仍累计失败补偿。

begin;

-- 在非public架构保存升级前的灵根数值及关键函数定义，供完整回滚使用。
create schema if not exists ncd_release_backup;
revoke all on schema ncd_release_backup from public;

create table if not exists ncd_release_backup.v01110_fix1_spirit_roots as
select id, cultivation_multiplier, event_luck_bonus
from public.spirit_roots
with no data;

create unique index if not exists v01110_fix1_spirit_roots_id_uq
  on ncd_release_backup.v01110_fix1_spirit_roots(id);

insert into ncd_release_backup.v01110_fix1_spirit_roots(id, cultivation_multiplier, event_luck_bonus)
select id, cultivation_multiplier, event_luck_bonus
from public.spirit_roots
on conflict (id) do nothing;

create table if not exists ncd_release_backup.v01110_fix1_functions (
  signature text primary key,
  definition text not null
);

insert into ncd_release_backup.v01110_fix1_functions(signature, definition)
select p.oid::regprocedure::text, pg_get_functiondef(p.oid)
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('claim_cultivation_v1', 'get_breakthrough_status_v1', 'attempt_breakthrough_v1')
  and pg_get_function_identity_arguments(p.oid) = ''
on conflict (signature) do nothing;

create table if not exists ncd_release_backup.v01110_fix1_realm_rates as
select id, breakthrough_base_rate
from public.realm_stages
with no data;

create unique index if not exists v01110_fix1_realm_rates_id_uq
  on ncd_release_backup.v01110_fix1_realm_rates(id);

insert into ncd_release_backup.v01110_fix1_realm_rates(id, breakthrough_base_rate)
select id, breakthrough_base_rate from public.realm_stages
on conflict (id) do nothing;

alter table public.spirit_roots
  add column if not exists combat_multiplier numeric(8,4) not null default 1.0000;

comment on column public.spirit_roots.cultivation_multiplier is
  'V0.11.10 FIX1：灵根修炼系数。天灵根1.00、双灵根0.90、三灵根0.80、四灵根0.70、五灵根0.60、变异灵根0.95。';
comment on column public.spirit_roots.combat_multiplier is
  'V0.11.10 FIX1：灵根对全部战斗属性的统一系数。天灵根1.00、双灵根0.90、三灵根0.80、四灵根0.70、五灵根0.60、变异灵根1.10。';

-- 灵根只保留修炼和战斗两种作用，清除旧的机缘附加值。
update public.spirit_roots
set
  cultivation_multiplier = case
    when concat_ws(' ', name, code, rarity) ~* '(变异|异灵根|variant|mutant)' then 0.9500
    when concat_ws(' ', name, code, rarity) ~* '(天灵根|单灵根|heaven|single)' then 1.0000
    when concat_ws(' ', name, code, rarity) ~* '(双灵根|dual|double)' then 0.9000
    when concat_ws(' ', name, code, rarity) ~* '(三灵根|triple)' then 0.8000
    when concat_ws(' ', name, code, rarity) ~* '(四灵根|quad|four)' then 0.7000
    when concat_ws(' ', name, code, rarity) ~* '(五灵根|杂灵根|five|mixed)' then 0.6000
    else 1.0000
  end,
  combat_multiplier = case
    when concat_ws(' ', name, code, rarity) ~* '(变异|异灵根|variant|mutant)' then 1.1000
    when concat_ws(' ', name, code, rarity) ~* '(天灵根|单灵根|heaven|single)' then 1.0000
    when concat_ws(' ', name, code, rarity) ~* '(双灵根|dual|double)' then 0.9000
    when concat_ws(' ', name, code, rarity) ~* '(三灵根|triple)' then 0.8000
    when concat_ws(' ', name, code, rarity) ~* '(四灵根|quad|four)' then 0.7000
    when concat_ws(' ', name, code, rarity) ~* '(五灵根|杂灵根|five|mixed)' then 0.6000
    else 1.0000
  end,
  event_luck_bonus = 0;

create table if not exists public.character_breakthrough_states (
  character_id uuid primary key references public.player_characters(id) on delete cascade,
  original_target_stage_id smallint references public.realm_stages(id) on delete set null,
  failure_count integer not null default 0 check (failure_count >= 0),
  compensation_bonus numeric(8,4) not null default 0 check (compensation_bonus >= 0),
  affliction_code text,
  affliction_name text,
  affliction_steps_remaining integer not null default 0 check (affliction_steps_remaining >= 0),
  major_fall_used boolean not null default false,
  major_fall_origin_stage_id smallint references public.realm_stages(id) on delete set null,
  last_failure_result text,
  updated_at timestamptz not null default now()
);

alter table public.character_breakthrough_states
  add column if not exists major_fall_used boolean not null default false,
  add column if not exists major_fall_origin_stage_id smallint references public.realm_stages(id) on delete set null;

comment on table public.character_breakthrough_states is
  'V0.11.10 FIX1：保存突破失败补偿、名字旁状态、大境界单次跌落锁及元婴期保护状态。';

alter table public.character_breakthrough_states enable row level security;
revoke all on table public.character_breakthrough_states from public;
revoke all on table public.character_breakthrough_states from anon;
revoke all on table public.character_breakthrough_states from authenticated;

create or replace function public.realm_stage_position_v1(p_stage_id smallint)
returns table (
  stage_index integer,
  major_index integer,
  major_order integer,
  minor_level integer
)
language sql
stable
strict
set search_path = public, pg_temp
as $$
  with ordered as (
    select
      rs.id,
      row_number() over (order by r.major_order, rs.minor_level, rs.id)::integer as stage_index,
      dense_rank() over (order by r.major_order)::integer as major_index,
      r.major_order::integer as major_order,
      rs.minor_level::integer as minor_level
    from public.realm_stages rs
    join public.realms r on r.id = rs.realm_id
  )
  select o.stage_index, o.major_index, o.major_order, o.minor_level
  from ordered o
  where o.id = p_stage_id;
$$;

create or replace function public.realm_base_cultivation_rate_v1(p_stage_id smallint)
returns numeric
language sql
stable
strict
set search_path = public, pg_temp
as $$
  select greatest(
    0,
    10
      + (coalesce(p.stage_index, 1) - 1) * 5
      + (coalesce(p.major_index, 1) - 1) * 15
  )::numeric
  from public.realm_stage_position_v1(p_stage_id) p;
$$;

comment on function public.realm_base_cultivation_rate_v1(smallint) is
  '首境10/秒；相邻小境界+5；跨入下一大境界时总增量为+20。由当前境界实时反算，跌境会自动回调。';

revoke all on function public.realm_stage_position_v1(smallint) from public;
revoke all on function public.realm_stage_position_v1(smallint) from anon;
revoke all on function public.realm_stage_position_v1(smallint) from authenticated;
revoke all on function public.realm_base_cultivation_rate_v1(smallint) from public;
revoke all on function public.realm_base_cultivation_rate_v1(smallint) from anon;
revoke all on function public.realm_base_cultivation_rate_v1(smallint) from authenticated;

create or replace function public.character_spirit_root_combat_multiplier_v1(p_character_id uuid)
returns numeric
language sql
stable
strict
set search_path = public, pg_temp
as $$
  select coalesce(max(sr.combat_multiplier) filter (where csr.is_primary), 1.0000)::numeric
  from public.character_spirit_roots csr
  join public.spirit_roots sr on sr.id = csr.spirit_root_id
  where csr.character_id = p_character_id;
$$;

revoke all on function public.character_spirit_root_combat_multiplier_v1(uuid) from public;
revoke all on function public.character_spirit_root_combat_multiplier_v1(uuid) from anon;
revoke all on function public.character_spirit_root_combat_multiplier_v1(uuid) from authenticated;

-- 将现有角色的基础吐纳统一校准为当前境界应有数值。
update public.character_cultivation_state cs
set base_rate_per_second = public.realm_base_cultivation_rate_v1(pc.realm_stage_id),
    updated_at = now()
from public.player_characters pc
where pc.id = cs.character_id;

create or replace function public.get_spirit_root_coefficients_v1()
returns table (
  character_id uuid,
  spirit_root_name text,
  cultivation_multiplier numeric,
  combat_multiplier numeric
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
begin
  if v_user_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  return query
  select
    pc.id,
    sr.name,
    round(coalesce(sr.cultivation_multiplier, 1), 4),
    round(coalesce(sr.combat_multiplier, 1), 4)
  from public.player_characters pc
  left join public.character_spirit_roots csr
    on csr.character_id = pc.id and csr.is_primary
  left join public.spirit_roots sr on sr.id = csr.spirit_root_id
  where pc.user_id = v_user_id
    and pc.status in ('active','secluded','missing')
  order by pc.created_at desc
  limit 1;
end;
$$;

revoke all on function public.get_spirit_root_coefficients_v1() from public;
revoke all on function public.get_spirit_root_coefficients_v1() from anon;
grant execute on function public.get_spirit_root_coefficients_v1() to authenticated;

-- 重建突破状态RPC，返回失败补偿、原始目标与渡劫状态。
drop function if exists public.get_breakthrough_status_v1();
create function public.get_breakthrough_status_v1()
returns table (
  status text,
  character_id uuid,
  current_stage_id smallint,
  current_stage_name text,
  next_stage_id smallint,
  next_stage_name text,
  cultivation_total bigint,
  cultivation_required bigint,
  success_rate numeric,
  base_success_rate numeric,
  compensation_bonus numeric,
  compensation_cap numeric,
  failure_count integer,
  original_target_stage_id smallint,
  original_target_stage_name text,
  adversity integer,
  lifespan_bonus integer,
  affliction_code text,
  affliction_name text,
  penalty_enabled boolean,
  penalty_floor_name text,
  major_fall_used boolean,
  major_fall_origin_stage_name text,
  current_base_rate_per_second numeric,
  next_base_rate_per_second numeric
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_character public.player_characters%rowtype;
  v_current_stage public.realm_stages%rowtype;
  v_next_stage public.realm_stages%rowtype;
  v_next_id smallint;
  v_base numeric := 0;
  v_normal_bonus numeric := 0;
  v_compensation numeric := 0;
  v_final numeric := 0;
  v_failure_count integer := 0;
  v_target_id smallint;
  v_target_name text;
  v_affliction_code text;
  v_affliction_name text;
  v_current_major_order smallint := 0;
  v_nascent_soul_order smallint := 4;
  v_penalty_enabled boolean := false;
  v_major_fall_used boolean := false;
  v_major_fall_origin_id smallint;
  v_major_fall_origin_name text;
begin
  if v_user_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select pc.* into v_character
  from public.player_characters pc
  where pc.user_id = v_user_id
    and pc.status in ('active','secluded','missing')
  order by pc.created_at desc
  limit 1;

  if v_character.id is null then
    raise exception 'NO_ACTIVE_CHARACTER';
  end if;

  select rs.* into v_current_stage
  from public.realm_stages rs
  where rs.id = v_character.realm_stage_id;

  select r.major_order into v_current_major_order
  from public.realms r where r.id = v_current_stage.realm_id;

  select coalesce(min(r.major_order) filter (where r.code = 'nascent_soul' or r.name like '元婴%'), 4)
  into v_nascent_soul_order
  from public.realms r;

  v_penalty_enabled := coalesce(v_current_major_order, 0) >= coalesce(v_nascent_soul_order, 4);

  select rs.id into v_next_id
  from public.realm_stages rs
  join public.realms r on r.id = rs.realm_id
  where (r.major_order, rs.minor_level, rs.id) > (
    select r0.major_order, rs0.minor_level, rs0.id
    from public.realm_stages rs0
    join public.realms r0 on r0.id = rs0.realm_id
    where rs0.id = v_character.realm_stage_id
  )
  order by r.major_order, rs.minor_level, rs.id
  limit 1;

  if v_next_id is null then
    return query select
      'maximum'::text, v_character.id, v_current_stage.id, v_current_stage.stage_name,
      null::smallint, null::text, v_character.cultivation, null::bigint,
      0::numeric, 0::numeric, 0::numeric, 0.8::numeric, 0,
      null::smallint, null::text, v_character.adversity, 0,
      null::text, null::text,
      v_penalty_enabled, '元婴期'::text, false, null::text,
      public.realm_base_cultivation_rate_v1(v_current_stage.id), null::numeric;
    return;
  end if;

  select rs.* into v_next_stage from public.realm_stages rs where rs.id = v_next_id;

  select
    coalesce(bs.failure_count, 0),
    coalesce(bs.compensation_bonus, 0),
    bs.original_target_stage_id,
    ots.stage_name,
    bs.affliction_code,
    bs.affliction_name,
    coalesce(bs.major_fall_used, false),
    bs.major_fall_origin_stage_id,
    mfs.stage_name
  into
    v_failure_count, v_compensation, v_target_id, v_target_name,
    v_affliction_code, v_affliction_name,
    v_major_fall_used, v_major_fall_origin_id, v_major_fall_origin_name
  from (select 1) seed
  left join public.character_breakthrough_states bs on bs.character_id = v_character.id
  left join public.realm_stages ots on ots.id = bs.original_target_stage_id
  left join public.realm_stages mfs on mfs.id = bs.major_fall_origin_stage_id;

  v_base := greatest(0, least(1, coalesce(v_next_stage.breakthrough_base_rate, 0)));

  select coalesce(sum(
    coalesce((f.modifiers->>'breakthrough')::numeric, 0)
    + coalesce((f.modifiers->>'breakthrough_rate')::numeric, 0)
  ), 0)
  into v_normal_bonus
  from public.character_fates cf
  join public.fates f on f.id = cf.fate_id
  where cf.character_id = v_character.id and cf.is_active;

  -- 补偿介入后的最终成功率最高80%，不是“额外最多加80%”。
  if v_failure_count > 0 or v_compensation > 0 then
    v_final := least(0.8000, greatest(0, v_base + v_normal_bonus + v_compensation));
  else
    v_final := least(1.0000, greatest(0, v_base + v_normal_bonus));
  end if;

  return query select
    'available'::text,
    v_character.id,
    v_current_stage.id,
    v_current_stage.stage_name,
    v_next_stage.id,
    v_next_stage.stage_name,
    v_character.cultivation,
    v_next_stage.cultivation_required,
    round(v_final, 4),
    round(greatest(0, v_base + v_normal_bonus), 4),
    round(v_compensation, 4),
    0.8000::numeric,
    v_failure_count,
    v_target_id,
    v_target_name,
    v_character.adversity,
    coalesce(v_next_stage.lifespan_bonus, 0),
    v_affliction_code,
    v_affliction_name,
    v_penalty_enabled,
    '元婴期'::text,
    v_major_fall_used,
    v_major_fall_origin_name,
    public.realm_base_cultivation_rate_v1(v_current_stage.id),
    public.realm_base_cultivation_rate_v1(v_next_stage.id);
end;
$$;

revoke all on function public.get_breakthrough_status_v1() from public;
revoke all on function public.get_breakthrough_status_v1() from anon;
grant execute on function public.get_breakthrough_status_v1() to authenticated;

-- 重建突破执行RPC。
drop function if exists public.attempt_breakthrough_v1();
create function public.attempt_breakthrough_v1()
returns table (
  success boolean,
  outcome_code text,
  target_stage_name text,
  current_stage_name text,
  message text,
  cultivation_after bigint,
  lifespan_bonus integer,
  adversity_after integer,
  failure_count integer,
  compensation_bonus numeric,
  effective_success_rate numeric,
  affliction_code text,
  affliction_name text,
  original_target_stage_name text,
  character_dead boolean
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_character public.player_characters%rowtype;
  v_current_stage public.realm_stages%rowtype;
  v_next_stage public.realm_stages%rowtype;
  v_next_id smallint;
  v_base numeric := 0;
  v_normal_bonus numeric := 0;
  v_compensation numeric := 0;
  v_effective_rate numeric := 0;
  v_failure_count integer := 0;
  v_original_target_id smallint;
  v_original_target_name text;
  v_affliction_code text;
  v_affliction_name text;
  v_affliction_steps integer := 0;
  v_roll numeric;
  v_outcome text;
  v_result_message text;
  v_target_fall_stage public.realm_stages%rowtype;
  v_current_position integer;
  v_original_target_position integer;
  v_success_position integer;
  v_stage_floor bigint;
  v_stage_ceiling bigint;
  v_cultivation_after bigint;
  v_new_compensation numeric;
  v_new_failure_count integer;
  v_dead boolean := false;
  v_current_major_order smallint := 0;
  v_next_major_order smallint := 0;
  v_nascent_soul_order smallint := 4;
  v_penalty_enabled boolean := false;
  v_major_fall_used boolean := false;
  v_major_fall_origin_id smallint;
  v_major_fall_origin_name text;
  v_major_fall_origin_order smallint;
  v_success_major_order smallint;
begin
  if v_user_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select pc.* into v_character
  from public.player_characters pc
  where pc.user_id = v_user_id
    and pc.status in ('active','secluded','missing')
  order by pc.created_at desc
  limit 1
  for update;

  if v_character.id is null then
    raise exception 'NO_ACTIVE_CHARACTER';
  end if;

  select rs.* into v_current_stage
  from public.realm_stages rs
  where rs.id = v_character.realm_stage_id;

  select r.major_order into v_current_major_order
  from public.realms r where r.id = v_current_stage.realm_id;

  select coalesce(min(r.major_order) filter (where r.code = 'nascent_soul' or r.name like '元婴%'), 4)
  into v_nascent_soul_order
  from public.realms r;

  v_penalty_enabled := coalesce(v_current_major_order, 0) >= coalesce(v_nascent_soul_order, 4);

  select rs.id into v_next_id
  from public.realm_stages rs
  join public.realms r on r.id = rs.realm_id
  where (r.major_order, rs.minor_level, rs.id) > (
    select r0.major_order, rs0.minor_level, rs0.id
    from public.realm_stages rs0
    join public.realms r0 on r0.id = rs0.realm_id
    where rs0.id = v_character.realm_stage_id
  )
  order by r.major_order, rs.minor_level, rs.id
  limit 1;

  if v_next_id is null then
    raise exception 'MAXIMUM_REALM';
  end if;

  select rs.* into v_next_stage from public.realm_stages rs where rs.id = v_next_id;
  select r.major_order into v_next_major_order from public.realms r where r.id = v_next_stage.realm_id;

  if v_character.cultivation < v_next_stage.cultivation_required then
    raise exception 'INSUFFICIENT_CULTIVATION';
  end if;

  insert into public.character_breakthrough_states(character_id)
  values (v_character.id)
  on conflict (character_id) do nothing;

  select
    bs.failure_count,
    bs.compensation_bonus,
    bs.original_target_stage_id,
    ots.stage_name,
    bs.affliction_code,
    bs.affliction_name,
    bs.affliction_steps_remaining,
    coalesce(bs.major_fall_used, false),
    bs.major_fall_origin_stage_id,
    mfs.stage_name
  into
    v_failure_count, v_compensation, v_original_target_id, v_original_target_name,
    v_affliction_code, v_affliction_name, v_affliction_steps,
    v_major_fall_used, v_major_fall_origin_id, v_major_fall_origin_name
  from public.character_breakthrough_states bs
  left join public.realm_stages ots on ots.id = bs.original_target_stage_id
  left join public.realm_stages mfs on mfs.id = bs.major_fall_origin_stage_id
  where bs.character_id = v_character.id
  for update of bs;

  v_base := greatest(0, least(1, coalesce(v_next_stage.breakthrough_base_rate, 0)));

  select coalesce(sum(
    coalesce((f.modifiers->>'breakthrough')::numeric, 0)
    + coalesce((f.modifiers->>'breakthrough_rate')::numeric, 0)
  ), 0)
  into v_normal_bonus
  from public.character_fates cf
  join public.fates f on f.id = cf.fate_id
  where cf.character_id = v_character.id and cf.is_active;

  if v_failure_count > 0 or v_compensation > 0 then
    v_effective_rate := least(0.8000, greatest(0, v_base + v_normal_bonus + v_compensation));
  else
    v_effective_rate := least(1.0000, greatest(0, v_base + v_normal_bonus));
  end if;

  if random() < v_effective_rate then
    update public.player_characters
    set realm_stage_id = v_next_stage.id,
        lifespan_total = lifespan_total + coalesce(v_next_stage.lifespan_bonus, 0),
        updated_at = now()
    where id = v_character.id;

    update public.character_cultivation_state
    set base_rate_per_second = public.realm_base_cultivation_rate_v1(v_next_stage.id),
        updated_at = now()
    where character_id = v_character.id;

    -- 伤势恢复：重伤成功一次变轻伤；轻伤、跑得快、命好成功一次即解除。
    if v_affliction_code = 'severe_injury' then
      v_affliction_code := 'light_injury';
      v_affliction_name := '轻伤';
      v_affliction_steps := 1;
      update public.player_characters
      set health_status = 'injured', updated_at = now()
      where id = v_character.id;
    elsif v_affliction_code is not null then
      v_affliction_code := null;
      v_affliction_name := null;
      v_affliction_steps := 0;
      update public.player_characters
      set health_status = 'healthy', updated_at = now()
      where id = v_character.id;
    end if;

    select stage_index into v_success_position
    from public.realm_stage_position_v1(v_next_stage.id);

    if v_original_target_id is not null then
      select stage_index into v_original_target_position
      from public.realm_stage_position_v1(v_original_target_id);
    end if;

    -- 大境界只允许跌落一次；成功回到首次大跌境前所在的大境界后解除锁定。
    if v_major_fall_used and v_major_fall_origin_id is not null then
      select r.major_order into v_major_fall_origin_order
      from public.realm_stages rs join public.realms r on r.id = rs.realm_id
      where rs.id = v_major_fall_origin_id;

      select r.major_order into v_success_major_order
      from public.realms r where r.id = v_next_stage.realm_id;

      if coalesce(v_success_major_order, -1) >= coalesce(v_major_fall_origin_order, 32767) then
        v_major_fall_used := false;
        v_major_fall_origin_id := null;
        v_major_fall_origin_name := null;
      end if;
    end if;

    if v_original_target_id is not null
       and v_success_position >= coalesce(v_original_target_position, v_success_position + 1) then
      update public.character_breakthrough_states
      set original_target_stage_id = null,
          failure_count = 0,
          compensation_bonus = 0,
          affliction_code = v_affliction_code,
          affliction_name = v_affliction_name,
          affliction_steps_remaining = v_affliction_steps,
          major_fall_used = v_major_fall_used,
          major_fall_origin_stage_id = v_major_fall_origin_id,
          last_failure_result = null,
          updated_at = now()
      where character_id = v_character.id;

      v_failure_count := 0;
      v_compensation := 0;
      v_original_target_name := null;
    else
      update public.character_breakthrough_states
      set affliction_code = v_affliction_code,
          affliction_name = v_affliction_name,
          affliction_steps_remaining = v_affliction_steps,
          major_fall_used = v_major_fall_used,
          major_fall_origin_stage_id = v_major_fall_origin_id,
          updated_at = now()
      where character_id = v_character.id;
    end if;

    insert into public.cultivation_records (
      character_id, world_year, action_type, years_spent,
      cultivation_before, cultivation_delta, cultivation_after,
      result, calculation_snapshot
    )
    select
      v_character.id, gw.current_year, 'breakthrough', 0,
      v_character.cultivation, 0, v_character.cultivation,
      'success',
      jsonb_build_object(
        'version', '0.11.10-fix1',
        'from_stage', v_current_stage.stage_name,
        'to_stage', v_next_stage.stage_name,
        'effective_success_rate', v_effective_rate,
        'compensation_bonus', v_compensation,
        'original_target', v_original_target_name
      )
    from public.game_worlds gw where gw.id = v_character.world_id;

    return query select
      true, 'success'::text, v_next_stage.stage_name, v_next_stage.stage_name,
      ('道关已开，成功踏入' || v_next_stage.stage_name || '。')::text,
      v_character.cultivation, coalesce(v_next_stage.lifespan_bonus, 0),
      v_character.adversity, v_failure_count, round(v_compensation, 4),
      round(v_effective_rate, 4), v_affliction_code, v_affliction_name,
      v_original_target_name, false;
    return;
  end if;

  -- 所有失败都会推进补偿档位。第一次+10个百分点，后续每次+30个百分点。
  v_new_failure_count := v_failure_count + 1;
  v_new_compensation := case
    when v_failure_count = 0 then 0.1000
    else least(0.8000, v_compensation + 0.3000)
  end;

  if v_original_target_id is null then
    v_original_target_id := v_next_stage.id;
    v_original_target_name := v_next_stage.stage_name;
  end if;

  v_roll := random();
  v_cultivation_after := v_character.cultivation;

  -- 元婴期以下：突破失败只记录失败与补偿，不死亡、不跌境、不清修为、不加伤势。
  if not v_penalty_enabled then
    v_outcome := 'low_realm_no_penalty';
    v_result_message := '元婴期以下受天道护持：突破虽未成功，但不触发任何失败惩罚。';

  elsif v_roll < 0.01 then
    v_outcome := 'death';
    v_result_message := '渡劫失败，道基崩毁，角色身死，等待转世。';
    v_dead := true;

    update public.player_characters
    set status = 'dead',
        health_status = 'critical',
        died_year = coalesce((select gw.current_year from public.game_worlds gw where gw.id = v_character.world_id), died_year, 1),
        death_cause = '渡劫失败',
        updated_at = now()
    where id = v_character.id;

    delete from public.character_breakthrough_states where character_id = v_character.id;

  elsif v_roll < 0.06 then
    -- 同一恢复周期只允许一次“大境界跌落”。再次抽中时转为无损失败。
    if v_major_fall_used then
      v_outcome := 'major_fall_guarded';
      v_result_message := '大境界跌落保护生效：回到原始大境界前不会再次跌落一个大境界。';

      update public.player_characters
      set adversity = adversity + 1,
          updated_at = now()
      where id = v_character.id;
    else
      v_outcome := 'major_fall';

      select rs.* into v_target_fall_stage
      from public.realm_stages rs
      join public.realms r on r.id = rs.realm_id
      where r.major_order = greatest(
        v_nascent_soul_order,
        (
          select max(r2.major_order)
          from public.realms r2
          join public.realm_stages rs2 on rs2.realm_id = r2.id
          join public.realms rc on rc.id = v_current_stage.realm_id
          where r2.major_order < rc.major_order
        )
      )
      order by abs(rs.minor_level - v_current_stage.minor_level), rs.minor_level desc, rs.id
      limit 1;

      -- 已处于元婴期时，不允许跌到元婴期以下。
      if v_target_fall_stage.id is null or v_current_major_order <= v_nascent_soul_order then
        v_outcome := 'realm_floor_guarded';
        v_target_fall_stage := v_current_stage;
        v_result_message := '元婴境界下限保护生效：不会跌落到元婴期以下。';

        update public.player_characters
        set adversity = adversity + 1,
            updated_at = now()
        where id = v_character.id;
      else
        v_cultivation_after := coalesce(v_target_fall_stage.cultivation_required, 0);
        v_affliction_code := 'severe_injury';
        v_affliction_name := '重伤';
        v_affliction_steps := 2;
        v_result_message := '渡劫反噬，跌落一个大境界，身受重伤；回到原始大境界前不会再次大跌境。';
        v_major_fall_used := true;
        v_major_fall_origin_id := v_current_stage.id;
        v_major_fall_origin_name := v_current_stage.stage_name;

        update public.player_characters
        set realm_stage_id = v_target_fall_stage.id,
            cultivation = v_cultivation_after,
            health_status = 'wounded',
            adversity = adversity + 1,
            updated_at = now()
        where id = v_character.id;

        update public.character_cultivation_state
        set base_rate_per_second = public.realm_base_cultivation_rate_v1(v_target_fall_stage.id),
            updated_at = now()
        where character_id = v_character.id;
      end if;
    end if;
  elsif v_roll < 0.21 then
    v_outcome := 'minor_fall';

    select rs.* into v_target_fall_stage
    from public.realm_stages rs
    join public.realms r on r.id = rs.realm_id
    where (r.major_order, rs.minor_level, rs.id) < (
      select r0.major_order, rs0.minor_level, rs0.id
      from public.realm_stages rs0
      join public.realms r0 on r0.id = rs0.realm_id
      where rs0.id = v_current_stage.id
    )
      and r.major_order >= v_nascent_soul_order
    order by r.major_order desc, rs.minor_level desc, rs.id desc
    limit 1;

    if v_target_fall_stage.id is null then
      v_outcome := 'realm_floor_guarded';
      v_target_fall_stage := v_current_stage;
      v_result_message := '元婴境界下限保护生效：不会跌落到元婴期以下。';

      update public.player_characters
      set adversity = adversity + 1,
          updated_at = now()
      where id = v_character.id;
    else
      v_cultivation_after := coalesce(v_target_fall_stage.cultivation_required, 0);
      v_affliction_code := 'light_injury';
      v_affliction_name := '轻伤';
      v_affliction_steps := 1;
      v_result_message := '渡劫失利，跌落一个小境界，身受轻伤。';

      update public.player_characters
      set realm_stage_id = v_target_fall_stage.id,
          cultivation = v_cultivation_after,
          health_status = 'injured',
          adversity = adversity + 1,
          updated_at = now()
      where id = v_character.id;

      update public.character_cultivation_state
      set base_rate_per_second = public.realm_base_cultivation_rate_v1(v_target_fall_stage.id),
          updated_at = now()
      where character_id = v_character.id;
    end if;
  elsif v_roll < 0.51 then
    v_outcome := 'stage_reset';
    v_stage_floor := coalesce(v_current_stage.cultivation_required, 0);
    v_cultivation_after := v_stage_floor;
    v_affliction_code := 'lucky_escape';
    v_affliction_name := '命好';
    v_affliction_steps := 1;
    v_result_message := '侥幸保住境界，但当前阶段修为尽失。';

    update public.player_characters
    set cultivation = v_cultivation_after,
        health_status = 'healthy',
        adversity = adversity + 1,
        updated_at = now()
    where id = v_character.id;

  elsif v_roll < 0.81 then
    v_outcome := 'stage_half';
    v_stage_floor := coalesce(v_current_stage.cultivation_required, 0);
    v_stage_ceiling := coalesce(v_next_stage.cultivation_required, v_stage_floor);
    v_cultivation_after := floor(v_stage_floor + (v_stage_ceiling - v_stage_floor) * 0.5)::bigint;
    v_affliction_code := 'quick_escape';
    v_affliction_name := '跑得快';
    v_affliction_steps := 1;
    v_result_message := '及时遁走，保住当前阶段一半修为进度。';

    update public.player_characters
    set cultivation = v_cultivation_after,
        health_status = 'healthy',
        adversity = adversity + 1,
        updated_at = now()
    where id = v_character.id;

  else
    v_outcome := 'no_loss';
    v_result_message := '渡劫虽未成功，但境界与修为均无损。';

    update public.player_characters
    set adversity = adversity + 1,
        updated_at = now()
    where id = v_character.id;
  end if;

  if not v_dead then
    update public.character_breakthrough_states
    set original_target_stage_id = v_original_target_id,
        failure_count = v_new_failure_count,
        compensation_bonus = v_new_compensation,
        affliction_code = v_affliction_code,
        affliction_name = v_affliction_name,
        affliction_steps_remaining = v_affliction_steps,
        major_fall_used = v_major_fall_used,
        major_fall_origin_stage_id = v_major_fall_origin_id,
        last_failure_result = v_outcome,
        updated_at = now()
    where character_id = v_character.id;
  end if;

  insert into public.cultivation_records (
    character_id, world_year, action_type, years_spent,
    cultivation_before, cultivation_delta, cultivation_after,
    result, calculation_snapshot
  )
  select
    v_character.id, gw.current_year, 'breakthrough', 0,
    v_character.cultivation,
    v_cultivation_after - v_character.cultivation,
    v_cultivation_after,
    'failure',
    jsonb_build_object(
      'version', '0.11.10-fix1',
      'outcome', v_outcome,
      'from_stage', v_current_stage.stage_name,
      'attempted_stage', v_next_stage.stage_name,
      'effective_success_rate', v_effective_rate,
      'failure_count', v_new_failure_count,
      'compensation_bonus', v_new_compensation,
      'compensation_final_cap', 0.8,
      'original_target', v_original_target_name,
      'affliction', v_affliction_name,
      'penalty_enabled', v_penalty_enabled,
      'major_fall_used', v_major_fall_used,
      'major_fall_origin', v_major_fall_origin_name
    )
  from public.game_worlds gw where gw.id = v_character.world_id;

  return query select
    false, v_outcome, v_next_stage.stage_name,
    coalesce(v_target_fall_stage.stage_name, v_current_stage.stage_name),
    v_result_message, v_cultivation_after, 0,
    case when v_outcome = 'low_realm_no_penalty' then v_character.adversity else v_character.adversity + 1 end, v_new_failure_count,
    round(v_new_compensation, 4), round(v_effective_rate, 4),
    v_affliction_code, v_affliction_name,
    v_original_target_name, v_dead;
end;
$$;

revoke all on function public.attempt_breakthrough_v1() from public;
revoke all on function public.attempt_breakthrough_v1() from anon;
grant execute on function public.attempt_breakthrough_v1() to authenticated;

-- V0.11.10 FIX1完整修炼结算：境界基础吐纳实时计算，灵根系数生效，天道系数最后整体相乘。
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

  v_gained := floor(v_exact_gain)::bigint;
  v_fraction := v_exact_gain - v_gained;

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

  if v_gained > 0 then
    update public.player_characters
    set cultivation = cultivation + v_gained, updated_at = now()
    where id = v_character_id;
  end if;

  update public.character_cultivation_state
  set base_rate_per_second = v_base_rate,
      last_claim_at = v_now,
      fractional_remainder = v_fraction,
      total_cultivation_seconds = total_cultivation_seconds + v_elapsed,
      updated_at = now()
  where character_id = v_character_id;

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
        'mode', 'automatic_v01110_fix1_realm_root_heaven_final',
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
        'effect_multiplier_bonus', v_effect_multiplier
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

revoke all on function public.claim_cultivation_v1() from public;
revoke all on function public.claim_cultivation_v1() from anon;
grant execute on function public.claim_cultivation_v1() to authenticated;

commit;

notify pgrst, 'reload schema';
