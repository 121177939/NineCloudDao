-- V0.13.0结构回退（非数据恢复）
-- 重要：V0.13.0上线时已经删除的历史超额修为无法由本脚本推算恢复；只能从部署前数据库备份恢复。
begin;
update public.progression_v0130_settings set breakthrough_enabled=false,cultivation_cap_enabled=false,updated_at=now() where singleton_id=1;
drop trigger if exists trg_player_characters_cultivation_cap_v0130 on public.player_characters;
create or replace function public.get_breakthrough_status_v1()
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
create or replace function public.attempt_breakthrough_v1()
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
begin
  -- 即时修为。
  m := regexp_match(coalesce(p_positive_text, ''), '修为（([0-9]+)）');
  if m is not null then
    v_amount := m[1]::numeric;
    update public.player_characters set cultivation = cultivation + v_amount::bigint where id = p_character_id;
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('type','instant_cultivation','amount',v_amount));
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
    where ci.character_id = p_character_id and ci.item_definition_id = v_item_id
    for update;
    if coalesce(v_quantity,0) < p_amount then raise exception 'CASINO_INSUFFICIENT_SPIRIT_STONES'; end if;
    update public.character_inventory ci
    set quantity = ci.quantity - p_amount, updated_at = now()
    where ci.character_id = p_character_id and ci.item_definition_id = v_item_id;
    return jsonb_build_object('stake_type',p_stake_type,'amount',p_amount,'available_before',v_quantity,'available_after',v_quantity-p_amount);
  elsif p_stake_type = 'cultivation' then
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
    update public.player_characters pc
    set cultivation = pc.cultivation + p_amount, updated_at = now()
    where pc.id = p_character_id;
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
begin
  perform public.casino_process_v1();
  v_character_id:=public.casino_current_character_id_v1();
  select s.enabled into v_enabled from public.casino_settings s where s.singleton_id=1;
  v_stones:=public.casino_available_v1(v_character_id,'spirit_stone');
  v_cultivation_available:=public.casino_available_v1(v_character_id,'cultivation');
  select r.major_order,rs.stage_name into v_major_order,v_stage_name
  from public.player_characters pc join public.realm_stages rs on rs.id=pc.realm_stage_id join public.realms r on r.id=rs.realm_id
  where pc.id=v_character_id;
  select to_jsonb(a) into v_activity from public.casino_daily_activity a
  where a.character_id=v_character_id and a.activity_date=current_date;

  return jsonb_build_object(
    'status',case when v_enabled then 'active' else 'disabled' end,
    'settings',(select jsonb_build_object('reveal_delay_seconds',s.reveal_delay_seconds,'open_expiry_seconds',s.open_expiry_seconds,'draw_interval_seconds',s.draw_interval_seconds) from public.casino_settings s where s.singleton_id=1),
    'character',jsonb_build_object(
      'stage_name',v_stage_name,'major_order',v_major_order,'cultivation_eligible',v_major_order>=public.casino_nascent_major_order_v1(),
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
commit;
notify pgrst,'reload schema';
