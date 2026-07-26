-- 《九霄问道》Web Alpha V0.11.9
-- 天道动态均衡正式整合版。
-- 1. 灵气环境格保持原有UI，只显示“灵气环境（状态）x系数”，点击弹出说明；
-- 2. 天道系数作用于完整自动修炼收益；×0.5约为原速度的一半，×5约为原速度的五倍；
-- 3. 本迁移可在V0.11.6、V0.11.7或V0.11.7 FIX1基础上重复执行，最终结果一致；
-- 4. 不新增业务表，不新增函数数量，只创建或替换既有函数。

begin;

create or replace function public.heaven_balance_multiplier_v1(p_realm_gap integer)
returns numeric
language sql
immutable
strict
set search_path = public, pg_temp
as $$
  select case
    when p_realm_gap <= -5 then 5.0::numeric
    when p_realm_gap = -4 then 4.0::numeric
    when p_realm_gap = -3 then 3.0::numeric
    when p_realm_gap = -2 then 2.0::numeric
    when p_realm_gap = -1 then 1.2::numeric
    when p_realm_gap = 0 then 1.0::numeric
    when p_realm_gap = 1 then 0.8::numeric
    when p_realm_gap = 2 then 0.6::numeric
    else 0.5::numeric
  end;
$$;

revoke all on function public.heaven_balance_multiplier_v1(integer) from public;
revoke all on function public.heaven_balance_multiplier_v1(integer) from anon;
grant execute on function public.heaven_balance_multiplier_v1(integer) to authenticated;

create or replace function public.get_heaven_balance_v1()
returns table (
  status text,
  character_id uuid,
  status_code text,
  status_name text,
  reason_label text,
  coefficient numeric,
  world_qi_base numeric,
  qi_gain_per_second numeric,
  realm_gap integer,
  player_realm_order integer,
  player_realm_name text,
  mainstream_realm_order integer,
  mainstream_realm_name text,
  active_population bigint,
  calculated_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_character_id uuid;
  v_world_id uuid;
  v_player_order integer;
  v_player_realm_name text;
  v_mainstream_order integer;
  v_mainstream_realm_name text;
  v_active_population bigint := 0;
  v_gap integer := 0;
  v_coefficient numeric := 1;
  v_qi_base numeric := 1;
  v_status_code text := 'dao_balance';
  v_status_name text := '大道均衡';
  v_reason_label text := '修为贴近全服平均，无加成无压制';
begin
  if v_user_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select pc.id, pc.world_id, r.major_order, r.name
  into v_character_id, v_world_id, v_player_order, v_player_realm_name
  from public.player_characters pc
  join public.realm_stages rs on rs.id = pc.realm_stage_id
  join public.realms r on r.id = rs.realm_id
  where pc.user_id = v_user_id
    and pc.status in ('active','secluded','missing')
  order by pc.created_at desc
  limit 1;

  if v_character_id is null then
    raise exception 'NO_ACTIVE_CHARACTER';
  end if;

  select
    coalesce(round(avg(r.major_order))::integer, v_player_order),
    count(*)::bigint
  into v_mainstream_order, v_active_population
  from public.player_characters pc
  join public.realm_stages rs on rs.id = pc.realm_stage_id
  join public.realms r on r.id = rs.realm_id
  where pc.world_id = v_world_id
    and pc.status in ('active','secluded','missing');

  v_mainstream_order := coalesce(v_mainstream_order, v_player_order);

  select r.name
  into v_mainstream_realm_name
  from public.realms r
  where r.major_order = v_mainstream_order
  order by r.id
  limit 1;

  v_mainstream_realm_name := coalesce(v_mainstream_realm_name, v_player_realm_name, '未知境界');

  select coalesce(gw.spiritual_qi_level, 1.0)
  into v_qi_base
  from public.game_worlds gw
  where gw.id = v_world_id;
  v_qi_base := coalesce(v_qi_base, 1.0);

  v_gap := coalesce(v_player_order, 0) - coalesce(v_mainstream_order, 0);
  v_coefficient := public.heaven_balance_multiplier_v1(v_gap);

  if v_gap < 0 then
    v_status_code := 'heavenly_blessing';
    v_status_name := '天道福泽';
    v_reason_label := '低修为，拥有灵气加成';
  elsif v_gap > 0 then
    v_status_code := 'heaven_obstruction';
    v_status_name := '天道阻滞';
    v_reason_label := '高修为，灵气收益衰减';
  end if;

  return query
  select
    'ready'::text,
    v_character_id,
    v_status_code,
    v_status_name,
    v_reason_label,
    round(v_coefficient, 4),
    round(v_qi_base, 4),
    round(v_qi_base * v_coefficient, 4),
    v_gap,
    v_player_order,
    v_player_realm_name,
    v_mainstream_order,
    v_mainstream_realm_name,
    v_active_population,
    clock_timestamp();
end;
$$;

revoke all on function public.get_heaven_balance_v1() from public;
revoke all on function public.get_heaven_balance_v1() from anon;
grant execute on function public.get_heaven_balance_v1() to authenticated;

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
    pc.id,
    pc.world_id,
    pc.age,
    pc.cultivation,
    r.major_order,
    cs.base_rate_per_second,
    cs.last_claim_at,
    cs.fractional_remainder
  into
    v_character_id,
    v_world_id,
    v_age,
    v_cultivation_before,
    v_player_realm_order,
    v_base_rate,
    v_last_claim,
    v_fraction
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

  -- 将领取区间按临时效果开始/结束时间切段，离线期间的临时加成仍精确结算。
  v_exact_gain := coalesce(v_fraction, 0);
  v_cursor := v_last_claim;

  for v_boundary in
    select boundary_at
    from (
      select v_now as boundary_at
      union
      select greatest(e.starts_at, v_last_claim)
      from public.character_cultivation_effects e
      where e.character_id = v_character_id
        and e.is_active
        and e.starts_at > v_last_claim
        and e.starts_at < v_now
      union
      select least(e.expires_at, v_now)
      from public.character_cultivation_effects e
      where e.character_id = v_character_id
        and e.is_active
        and e.expires_at is not null
        and e.expires_at > v_last_claim
        and e.expires_at < v_now
    ) boundaries
    where boundary_at > v_last_claim
    order by boundary_at
  loop
    if v_boundary <= v_cursor then
      continue;
    end if;

    select
      coalesce(sum(e.flat_rate_per_second), 0),
      coalesce(sum(e.multiplier_bonus), 0)
    into v_segment_effect_flat, v_segment_effect_multiplier
    from public.character_cultivation_effects e
    where e.character_id = v_character_id
      and e.is_active
      and e.starts_at <= v_cursor
      and (e.expires_at is null or e.expires_at > v_cursor);

    v_segment_seconds := greatest(0, extract(epoch from (v_boundary - v_cursor)));
    v_segment_fixed_rate := greatest(
      0,
      (v_base_rate + v_technique_flat + v_segment_effect_flat)
      * v_root_multiplier
      * greatest(0, 1 + v_fate_bonus + v_technique_multiplier + v_segment_effect_multiplier)
    );

    -- FIX1：天道系数作用于完整自动修炼收益。
    -- ×0.5约为原最终速度的一半；×5约为原最终速度的五倍。
    v_segment_rate := greatest(0, v_segment_fixed_rate * v_effective_qi_multiplier);

    v_exact_gain := v_exact_gain + (v_segment_rate * v_segment_seconds);
    v_cursor := v_boundary;
  end loop;

  v_gained := floor(v_exact_gain)::bigint;
  v_fraction := v_exact_gain - v_gained;

  select
    coalesce(sum(e.flat_rate_per_second), 0),
    coalesce(sum(e.multiplier_bonus), 0)
  into v_effect_flat, v_effect_multiplier
  from public.character_cultivation_effects e
  where e.character_id = v_character_id
    and e.is_active
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
    set cultivation = cultivation + v_gained,
        updated_at = now()
    where id = v_character_id;
  end if;

  update public.character_cultivation_state as ccs
  set last_claim_at = v_now,
      fractional_remainder = v_fraction,
      total_cultivation_seconds = total_cultivation_seconds + v_elapsed,
      updated_at = now()
  where ccs.character_id = v_character_id;

  if v_gained > 0 and v_elapsed >= 300 then
    insert into public.cultivation_records (
      character_id, world_year, action_type, years_spent,
      cultivation_before, cultivation_delta, cultivation_after,
      result, calculation_snapshot
    )
    select
      v_character_id,
      gw.current_year,
      'cultivate',
      0,
      v_cultivation_before,
      v_gained,
      v_cultivation_before + v_gained,
      'success',
      jsonb_build_object(
        'mode', 'automatic_v0119_full_heaven_multiplier',
        'elapsed_seconds', v_elapsed,
        'rate_per_second', v_current_rate,
        'fixed_rate_per_second', v_current_fixed_rate,
        'root_multiplier', v_root_multiplier,
        'world_qi_base', v_qi_base,
        'heaven_balance_coefficient', v_heaven_coefficient,
        'effective_qi_multiplier', v_effective_qi_multiplier,
        'player_realm_order', v_player_realm_order,
        'mainstream_realm_order', v_mainstream_realm_order,
        'realm_gap', v_realm_gap,
        'fate_bonus', v_fate_bonus,
        'technique_flat_rate', v_technique_flat,
        'technique_multiplier_bonus', v_technique_multiplier,
        'effect_flat_rate', v_effect_flat,
        'effect_multiplier_bonus', v_effect_multiplier
      )
    from public.game_worlds gw
    where gw.id = v_world_id;
  end if;

  return query
  select
    v_character_id,
    v_gained,
    v_cultivation_before + v_gained,
    v_elapsed,
    round(v_current_rate, 6),
    round(v_base_rate, 6),
    round(v_root_multiplier, 6),
    round(v_effective_qi_multiplier, 6),
    round(v_fate_bonus, 6),
    round(v_technique_flat, 6),
    round(v_technique_multiplier, 6),
    round(v_effect_flat, 6),
    round(v_effect_multiplier, 6),
    v_now;
end;
$$;

revoke all on function public.claim_cultivation_v1() from public;
revoke all on function public.claim_cultivation_v1() from anon;
grant execute on function public.claim_cultivation_v1() to authenticated;

commit;

notify pgrst, 'reload schema';

select
  public.heaven_balance_multiplier_v1(-5) as blessing_x5,
  public.heaven_balance_multiplier_v1(0) as balance_x1,
  public.heaven_balance_multiplier_v1(3) as obstruction_x05;
