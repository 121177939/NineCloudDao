-- 九霄问道 V0.11.5 FINAL：V0.11.1→V0.11.5 功能激活与一致性修复
-- 前置：已成功执行 V0.11.2 的 202607250020_auto_opportunity_v3.sql。
-- 本脚本会：修复自动机缘在线/离线节奏、真正应用机缘效果、真正发放普通/专属功法、
--           让普通功法按“一级完整效果、每级线性+10%”生效，并接通专属槽与专属升级。
-- 严禁执行已废弃的 202607240019_auto_opportunity_v2.sql。

begin;

-- 1. 将当前系统无法直接承载的文案改写成可实际结算的效果。
update public.opportunity_v3_catalog
set positive_text = '① 永久修炼速度 + 35%② 永久每秒修为 + 25③ 海量修为（200000）'
where code = 'immortal_006';

update public.opportunity_v3_catalog
set positive_text = '① 永久修炼速度 + 50%② 永久每秒修为 + 40③ 大量修为（100000）'
where code = 'immortal_008';

update public.opportunity_v3_catalog
set positive_text = '① 永久修炼速度 + 60%② 永久每秒修为 + 50③ 洞府日产量永久 + 200%（日增 200 灵石）④ 海量修为（200000）⑤ 巨额灵石（50000）'
where code = 'immortal_009';

-- 2. 12 个正式机缘功法（11 门正式表内功法 + 玄品23修正版）改用 V3 基础字段。
--    旧 claim_cultivation_v1 不会读取 v3_base_*，避免错误地按“基础值×等级”重复计算；
--    实际效果由本脚本的专用同步函数按 1 + 0.1×(等级-1) 写入统一修炼效果表。
update public.techniques
set fixed_effects = (coalesce(fixed_effects, '{}'::jsonb) - 'cultivation_per_second' - 'cultivation_multiplier')
                    || jsonb_build_object('v3_base_cultivation_per_second', 25, 'linear_growth_per_level', 0.10)
where code = 'opp_hongmeng';
update public.techniques
set fixed_effects = (coalesce(fixed_effects, '{}'::jsonb) - 'cultivation_per_second' - 'cultivation_multiplier')
                    || jsonb_build_object('v3_base_cultivation_multiplier', 0.20, 'linear_growth_per_level', 0.10)
where code = 'opp_dongtian';
update public.techniques
set fixed_effects = (coalesce(fixed_effects, '{}'::jsonb) - 'cultivation_per_second' - 'cultivation_multiplier')
                    || jsonb_build_object('v3_base_cultivation_per_second', 22, 'linear_growth_per_level', 0.10)
where code = 'opp_cangyuan';
update public.techniques
set fixed_effects = (coalesce(fixed_effects, '{}'::jsonb) - 'cultivation_per_second' - 'cultivation_multiplier')
                    || jsonb_build_object('v3_base_cultivation_multiplier', 0.12, 'linear_growth_per_level', 0.10)
where code = 'opp_liuyun';
update public.techniques
set fixed_effects = (coalesce(fixed_effects, '{}'::jsonb) - 'cultivation_per_second' - 'cultivation_multiplier')
                    || jsonb_build_object('v3_base_cultivation_per_second', 10, 'linear_growth_per_level', 0.10)
where code = 'opp_zhoutian_tuna';
update public.techniques
set fixed_effects = (coalesce(fixed_effects, '{}'::jsonb) - 'cultivation_per_second' - 'cultivation_multiplier')
                    || jsonb_build_object('v3_base_cultivation_multiplier', 0.10, 'linear_growth_per_level', 0.10)
where code = 'opp_qingshi';
update public.techniques
set fixed_effects = (coalesce(fixed_effects, '{}'::jsonb) - 'cultivation_per_second' - 'cultivation_multiplier')
                    || jsonb_build_object('v3_base_cultivation_multiplier', 0.06, 'linear_growth_per_level', 0.10)
where code = 'opp_qianxi';
update public.techniques
set fixed_effects = (coalesce(fixed_effects, '{}'::jsonb) - 'cultivation_per_second' - 'cultivation_multiplier')
                    || jsonb_build_object('v3_base_cultivation_multiplier', 0.05, 'linear_growth_per_level', 0.10)
where code = 'opp_jichu';
update public.techniques
set fixed_effects = (coalesce(fixed_effects, '{}'::jsonb) - 'cultivation_per_second' - 'cultivation_multiplier')
                    || jsonb_build_object('v3_base_cultivation_per_second', 4, 'linear_growth_per_level', 0.10)
where code = 'opp_zhoutian_yangqi';
update public.techniques
set fixed_effects = (coalesce(fixed_effects, '{}'::jsonb) - 'cultivation_per_second' - 'cultivation_multiplier')
                    || jsonb_build_object('v3_base_cultivation_multiplier', 0.01, 'linear_growth_per_level', 0.10)
where code = 'opp_cuqian';
update public.techniques
set fixed_effects = (coalesce(fixed_effects, '{}'::jsonb) - 'cultivation_per_second' - 'cultivation_multiplier')
                    || jsonb_build_object('v3_base_cultivation_multiplier', 0.01, 'linear_growth_per_level', 0.10)
where code = 'opp_rumen';
update public.techniques
set fixed_effects = (coalesce(fixed_effects, '{}'::jsonb) - 'cultivation_per_second' - 'cultivation_multiplier')
                    || jsonb_build_object('v3_base_cultivation_multiplier', 0.02, 'linear_growth_per_level', 0.10)
where code = 'opp_qingquan';

-- 2.5 修复 V0.11.2 灵石发放函数的冲突键，确保奖励真正到账。
create or replace function public.award_spirit_stones_v3(p_character_id uuid,p_amount bigint)
returns void
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_item_id uuid;
  v_updated integer;
begin
  if p_amount<=0 then return; end if;
  select id into v_item_id from public.item_definitions where code='spirit_stone' limit 1;
  if v_item_id is null then raise exception 'SPIRIT_STONE_ITEM_MISSING'; end if;

  update public.character_inventory
     set quantity=quantity+p_amount,updated_at=now()
   where character_id=p_character_id
     and item_definition_id=v_item_id
     and is_bound=false;
  get diagnostics v_updated=row_count;

  if v_updated=0 then
    insert into public.character_inventory(
      character_id,item_definition_id,quantity,is_bound,item_instance,acquired_year
    ) values (
      p_character_id,v_item_id,p_amount,false,'{}'::jsonb,1
    )
    on conflict(character_id,item_definition_id,is_bound)
    do update set quantity=public.character_inventory.quantity+excluded.quantity,updated_at=now();
  end if;
end$$;

-- 3. 统一线性效果计算。
create or replace function public.v0115_linear_effect_v1(
  p_base numeric,
  p_level integer,
  p_growth numeric default 0.10
)
returns numeric
language sql
immutable
as $$
  select round(
    greatest(0, coalesce(p_base, 0))
    * (1 + greatest(0, coalesce(p_level, 1) - 1) * greatest(0, coalesce(p_growth, 0.10))),
    6
  )
$$;

-- 4. 专属功法当前效果。
create or replace function public.exclusive_technique_effect_bonus_v1(p_level integer, p_base numeric)
returns numeric
language sql
immutable
as $$
  select public.v0115_linear_effect_v1(p_base, p_level, 0.10)
$$;

-- 5. 同步普通机缘功法的实际修炼效果。
create or replace function public.refresh_opportunity_technique_effects_v1(p_character_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r record;
  v_flat numeric(20,6);
  v_multiplier numeric(12,6);
begin
  update public.character_cultivation_effects
     set is_active = false,
         expires_at = coalesce(expires_at, clock_timestamp()),
         updated_at = now()
   where character_id = p_character_id
     and source_key like 'opptech:%'
     and is_active = true;

  for r in
    select ct.id,
           ct.level,
           t.code,
           t.name,
           t.fixed_effects,
           coalesce(ct.equipped_slot, case when ct.is_equipped then ct.slot_type end) as active_slot
      from public.character_techniques ct
      join public.techniques t on t.id = ct.technique_id
     where ct.character_id = p_character_id
       and t.code like 'opp\_%' escape '\'
       and t.is_active = true
       and (ct.equipped_slot is not null or ct.is_equipped = true)
  loop
    v_flat := public.v0115_linear_effect_v1(
      coalesce((r.fixed_effects ->> 'v3_base_cultivation_per_second')::numeric, 0),
      r.level,
      coalesce((r.fixed_effects ->> 'linear_growth_per_level')::numeric, 0.10)
    );
    v_multiplier := public.v0115_linear_effect_v1(
      coalesce((r.fixed_effects ->> 'v3_base_cultivation_multiplier')::numeric, 0),
      r.level,
      coalesce((r.fixed_effects ->> 'linear_growth_per_level')::numeric, 0.10)
    );

    if v_flat <> 0 or v_multiplier <> 0 then
      insert into public.character_cultivation_effects(
        character_id, source_type, source_key, display_name,
        instant_cultivation_awarded, flat_rate_per_second, multiplier_bonus,
        starts_at, expires_at, is_active, metadata
      ) values (
        p_character_id,
        'technique',
        'opptech:' || r.id::text,
        '功法·' || r.name,
        0,
        v_flat,
        v_multiplier,
        clock_timestamp(),
        null,
        true,
        jsonb_build_object(
          'kind', 'opportunity_technique_v3',
          'technique_code', r.code,
          'level', r.level,
          'slot', r.active_slot,
          'linear_growth_per_level', 0.10
        )
      );
    end if;
  end loop;
end$$;

create or replace function public.trg_refresh_opportunity_technique_effects_v1()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'DELETE' then
    perform public.refresh_opportunity_technique_effects_v1(old.character_id);
    return old;
  end if;
  perform public.refresh_opportunity_technique_effects_v1(new.character_id);
  return new;
end$$;

drop trigger if exists trg_refresh_opportunity_technique_effects_v1 on public.character_techniques;
create trigger trg_refresh_opportunity_technique_effects_v1
after insert or update of level, is_equipped, slot_type, equipped_slot or delete
on public.character_techniques
for each row execute function public.trg_refresh_opportunity_technique_effects_v1();

-- 6. 专属功法效果同步。
create or replace function public.refresh_exclusive_technique_effects_v1(p_character_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r record;
  v_bonus numeric(12,6);
begin
  update public.character_cultivation_effects
     set is_active = false,
         expires_at = coalesce(expires_at, clock_timestamp()),
         updated_at = now()
   where character_id = p_character_id
     and source_key like 'exclusive:%'
     and is_active = true;

  select cet.id, cet.exclusive_code, cet.level, etd.name, etd.base_cultivation_multiplier
    into r
    from public.character_exclusive_techniques cet
    join public.exclusive_technique_definitions etd on etd.code = cet.exclusive_code
   where cet.character_id = p_character_id
     and cet.equipped = true
   limit 1;

  if r.id is null then return; end if;

  v_bonus := public.exclusive_technique_effect_bonus_v1(r.level, r.base_cultivation_multiplier);

  insert into public.character_cultivation_effects(
    character_id, source_type, source_key, display_name,
    instant_cultivation_awarded, flat_rate_per_second, multiplier_bonus,
    starts_at, expires_at, is_active, metadata
  ) values (
    p_character_id,
    'buff',
    'exclusive:' || r.exclusive_code,
    '专属功法·' || r.name,
    0,
    0,
    v_bonus,
    clock_timestamp(),
    null,
    true,
    jsonb_build_object(
      'kind', 'exclusive_technique',
      'exclusive_code', r.exclusive_code,
      'level', r.level,
      'bonus', v_bonus
    )
  );
end$$;

-- 7. 普通功法奖励。重复获得转为传承点。
create or replace function public.award_opportunity_technique_v3(
  p_character_id uuid,
  p_technique_name text,
  p_world_year integer
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r record;
  v_duplicate_points integer;
  v_character_technique_id uuid;
begin
  select id, code, name, grade
    into r
    from public.techniques
   where name = p_technique_name
     and is_active = true
   limit 1;

  if r.id is null then
    return jsonb_build_object('awarded', false, 'reason', 'TECHNIQUE_REWARD_NOT_FOUND', 'name', p_technique_name);
  end if;

  v_duplicate_points := case r.grade
    when 'immortal' then 80
    when 'heaven' then 65
    when 'earth' then 50
    when 'mystic' then 40
    when 'yellow' then 30
    else 25
  end;

  insert into public.character_techniques(
    character_id, technique_id, level, proficiency,
    is_equipped, slot_type, learned_year,
    acquisition_count, mastery_points, last_practiced_at
  ) values (
    p_character_id, r.id, 1, 0,
    false, null, p_world_year,
    1, 0, clock_timestamp()
  )
  on conflict(character_id, technique_id) do update
     set acquisition_count = coalesce(public.character_techniques.acquisition_count, 1) + 1,
         mastery_points = coalesce(public.character_techniques.mastery_points, 0) + v_duplicate_points,
         updated_at = now()
  returning id into v_character_technique_id;

  perform public.refresh_opportunity_technique_effects_v1(p_character_id);

  return jsonb_build_object(
    'awarded', true,
    'character_technique_id', v_character_technique_id,
    'name', r.name,
    'code', r.code,
    'duplicate_mastery_points', v_duplicate_points
  );
end$$;

-- 8. 洞府资源映射。把“日增 N 灵石”等当前洞府无法直接承载的永久产量效果，
--    按事件编号轮换映射为灵蕴、灵草、灵矿的一次性资源奖励。
create or replace function public.award_cave_resource_v3(
  p_lineage_id uuid,
  p_catalog_code text,
  p_amount numeric
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_suffix integer := 0;
  v_resource_code text;
  v_resource_name text;
  v_amount numeric := greatest(0, coalesce(p_amount, 0));
  v_updated integer := 0;
begin
  if p_lineage_id is null or v_amount <= 0 then
    return jsonb_build_object('awarded', false);
  end if;

  begin
    v_suffix := coalesce((regexp_match(coalesce(p_catalog_code, ''), '([0-9]+)$'))[1]::integer, 0);
  exception when others then
    v_suffix := 0;
  end;

  v_resource_code := case mod(v_suffix, 3)
    when 1 then 'cave_qi'
    when 2 then 'spirit_herb'
    else 'spirit_ore'
  end;
  v_resource_name := case v_resource_code
    when 'cave_qi' then '灵蕴'
    when 'spirit_herb' then '灵草'
    else '灵矿'
  end;

  if to_regclass('public.lineage_cave_resources') is not null
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='lineage_cave_resources' and column_name='lineage_id')
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='lineage_cave_resources' and column_name='resource_code')
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='lineage_cave_resources' and column_name='quantity') then
    execute 'update public.lineage_cave_resources set quantity=quantity+$3,updated_at=now() where lineage_id=$1 and resource_code=$2'
      using p_lineage_id, v_resource_code, v_amount;
    get diagnostics v_updated = row_count;
    if v_updated = 0 then
      execute 'insert into public.lineage_cave_resources(lineage_id,resource_code,quantity) values($1,$2,$3)'
        using p_lineage_id, v_resource_code, v_amount;
    end if;

    return jsonb_build_object('awarded', true, 'resource_code', v_resource_code, 'resource_name', v_resource_name, 'amount', v_amount);
  end if;

  return jsonb_build_object('awarded', false, 'reason', 'CAVE_RESOURCE_SCHEMA_UNAVAILABLE');
end$$;

-- 9. 将机缘文本中可承载的多项效果真正写入现有系统。
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

  -- 天机迟滞：以最终规则为准，黄0、玄1、地6、天12、仙/专属24小时。
  v_hours := public.opportunity_v3_penalty_hours(p_rarity);
  if v_hours > 0 then
    m := regexp_match(coalesce(p_negative_text, ''), '修炼速度[[:space:]]*-[[:space:]]*([0-9]+(?:\.[0-9]+)?)[%％]');
    if m is not null then
      v_amount := -(m[1]::numeric / 100);
      insert into public.character_cultivation_effects(
        character_id, source_type, source_key, display_name,
        flat_rate_per_second, multiplier_bonus, starts_at, expires_at, is_active, metadata
      ) values (
        p_character_id, 'opportunity', 'opportunity_v3:'||p_result_id::text||':penalty',
        '天机迟滞·'||p_rarity, 0, v_amount, p_now, p_now + make_interval(hours=>v_hours), true,
        jsonb_build_object('result_id',p_result_id,'rarity',p_rarity,'hours',v_hours)
      );
      v_applied := v_applied || jsonb_build_array(jsonb_build_object('type','penalty_multiplier','amount',v_amount,'hours',v_hours));
    end if;
  end if;

  return v_applied;
end$$;

-- 10. 专属功法读取、切换与升级。
create or replace function public.get_exclusive_technique_system_v1()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  u uuid := auth.uid();
  c public.player_characters%rowtype;
  v_fate_code text;
  v_fate_name text;
  v_rows jsonb;
  v_equipped_name text;
begin
  if u is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into c from public.player_characters
   where user_id=u and status in('active','secluded','missing')
   order by created_at desc limit 1;
  if c.id is null then raise exception 'CHARACTER_NOT_FOUND'; end if;

  select f.code, f.name into v_fate_code, v_fate_name
    from public.character_fates cf join public.fates f on f.id=cf.fate_id
   where cf.character_id=c.id and cf.is_active
   order by cf.created_at limit 1;

  select jsonb_agg(jsonb_build_object(
    'id',x.id,'exclusive_code',x.exclusive_code,'name',x.name,'description',x.description,
    'fate_code',x.fate_code,'fate_name',x.fate_name,'cave_resource_code',x.cave_resource_code,
    'level',x.level,'max_level',x.max_level,'equipped',x.equipped,
    'is_matching_fate',x.is_matching_fate,'effect_multiplier_bonus',x.effect_multiplier_bonus,
    'next_upgrade_cost',x.next_upgrade_cost
  ) order by x.equipped desc,x.acquired_at)
  into v_rows
  from (
    select cet.id,cet.exclusive_code,cet.level,cet.equipped,cet.acquired_at,
           etd.name,etd.description,etd.fate_code,etd.fate_name,etd.cave_resource_code,etd.max_level,
           (etd.fate_code=v_fate_code) as is_matching_fate,
           public.exclusive_technique_effect_bonus_v1(cet.level,etd.base_cultivation_multiplier) as effect_multiplier_bonus,
           case when cet.level<etd.max_level then etd.upgrade_cost_base*cet.level*cet.level else 0 end as next_upgrade_cost
      from public.character_exclusive_techniques cet
      join public.exclusive_technique_definitions etd on etd.code=cet.exclusive_code
     where cet.character_id=c.id
  ) x;

  select etd.name into v_equipped_name
    from public.character_exclusive_techniques cet
    join public.exclusive_technique_definitions etd on etd.code=cet.exclusive_code
   where cet.character_id=c.id and cet.equipped=true limit 1;

  return jsonb_build_object(
    'status','ok','character_id',c.id,
    'current_fate_code',v_fate_code,'current_fate_name',v_fate_name,
    'equipped_name',v_equipped_name,
    'techniques',coalesce(v_rows,'[]'::jsonb)
  );
end$$;

create or replace function public.set_exclusive_technique_slot_v1(p_character_exclusive_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  u uuid:=auth.uid();
  c public.player_characters%rowtype;
  r record;
begin
  if u is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into c from public.player_characters
   where user_id=u and status in('active','secluded','missing')
   order by created_at desc limit 1;
  if c.id is null then raise exception 'CHARACTER_NOT_FOUND'; end if;

  select cet.id,cet.exclusive_code,etd.name into r
    from public.character_exclusive_techniques cet
    join public.exclusive_technique_definitions etd on etd.code=cet.exclusive_code
   where cet.id=p_character_exclusive_id and cet.character_id=c.id limit 1;
  if r.id is null then raise exception 'EXCLUSIVE_TECHNIQUE_NOT_FOUND'; end if;

  update public.character_exclusive_techniques
     set equipped=(id=r.id)
   where character_id=c.id;
  perform public.refresh_exclusive_technique_effects_v1(c.id);

  return jsonb_build_object('success',true,'technique_name',r.name,'exclusive_code',r.exclusive_code,'equipped',true);
end$$;

create or replace function public.upgrade_exclusive_technique_v1(p_character_exclusive_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  u uuid:=auth.uid();
  r record;
  v_cost bigint;
  v_remaining bigint;
  v_bonus numeric(12,6);
begin
  select cet.id,cet.character_id,cet.level,cet.equipped,
         etd.name,etd.max_level,etd.upgrade_cost_base,etd.base_cultivation_multiplier,
         pc.user_id
    into r
    from public.character_exclusive_techniques cet
    join public.exclusive_technique_definitions etd on etd.code=cet.exclusive_code
    join public.player_characters pc on pc.id=cet.character_id
   where cet.id=p_character_exclusive_id and pc.user_id=u
   for update;

  if r.id is null then raise exception 'EXCLUSIVE_TECHNIQUE_NOT_FOUND'; end if;
  if r.level>=r.max_level then raise exception 'EXCLUSIVE_TECHNIQUE_MAX_LEVEL'; end if;

  v_cost:=r.upgrade_cost_base*r.level*r.level;
  select ci.quantity into v_remaining
    from public.character_inventory ci
    join public.item_definitions i on i.id=ci.item_definition_id
   where ci.character_id=r.character_id and i.code='spirit_stone'
   for update;
  if coalesce(v_remaining,0)<v_cost then raise exception 'INSUFFICIENT_SPIRIT_STONES'; end if;

  update public.character_inventory ci
     set quantity=quantity-v_cost,updated_at=now()
    from public.item_definitions i
   where ci.item_definition_id=i.id and ci.character_id=r.character_id and i.code='spirit_stone';
  update public.character_exclusive_techniques set level=level+1 where id=r.id;
  if r.equipped then perform public.refresh_exclusive_technique_effects_v1(r.character_id); end if;

  select ci.quantity into v_remaining
    from public.character_inventory ci
    join public.item_definitions i on i.id=ci.item_definition_id
   where ci.character_id=r.character_id and i.code='spirit_stone';
  v_bonus:=public.exclusive_technique_effect_bonus_v1(r.level+1,r.base_cultivation_multiplier);

  return jsonb_build_object(
    'success',true,'technique_name',r.name,'level',r.level+1,'cost',v_cost,
    'spirit_stones_remaining',coalesce(v_remaining,0),'effect_multiplier_bonus',v_bonus
  );
end$$;

-- 11. 自动机缘主函数：精确权重、在线5分钟、离线20分钟且最多补1条、开关生效、真正结算效果。
create or replace function public.get_auto_opportunity_v3()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  u uuid:=auth.uid();
  c public.player_characters%rowtype;
  st public.character_opportunity_v3_state%rowtype;
  cfg public.opportunity_v3_settings%rowtype;
  ev public.opportunity_v3_catalog%rowtype;
  nowv timestamptz:=clock_timestamp();
  v_due boolean:=false;
  v_offline boolean:=false;
  v_gap_seconds numeric:=0;
  v_next timestamptz;
  v_roll numeric;
  v_total numeric;
  v_w_ex numeric:=0.2;
  v_w_im numeric:=0.5;
  v_w_he numeric:=1.5;
  v_w_ea numeric:=8;
  v_w_my numeric:=25;
  v_w_ye numeric:=64.8;
  v_boost numeric:=1;
  v_rarity text;
  v_path text;
  v_result_id uuid;
  v_catalog_code text;
  v_title text;
  v_story text;
  v_positive text;
  v_negative text;
  v_fate_code text;
  v_fate_has_definition boolean:=false;
  v_has_own boolean:=false;
  v_pity numeric:=20;
  v_other_weight numeric:=20;
  v_pick numeric;
  v_running numeric:=0;
  v_exclusive record;
  v_acquired jsonb;
  v_applied jsonb;
begin
  if u is null then raise exception 'AUTH_REQUIRED'; end if;

  select * into c from public.player_characters
   where user_id=u and status in('active','secluded','missing')
   order by created_at desc limit 1;
  if c.id is null then raise exception 'CHARACTER_NOT_FOUND'; end if;

  select * into cfg from public.opportunity_v3_settings
   where world_code='jiuxiao_world_1' limit 1;
  if cfg.world_code is null then raise exception 'OPPORTUNITY_V3_SETTINGS_MISSING'; end if;
  if not cfg.enabled then
    return jsonb_build_object('status','disabled','automatic',false,'message','自动机缘已由维护者紧急停用');
  end if;

  insert into public.character_opportunity_v3_state(character_id)
  values(c.id) on conflict do nothing;
  select * into st from public.character_opportunity_v3_state where character_id=c.id for update;

  v_gap_seconds:=greatest(0,extract(epoch from nowv-st.last_seen_at));
  v_offline:=v_gap_seconds>greatest(60,least(180,cfg.online_interval_seconds/2));

  if v_offline then
    v_due:=v_gap_seconds>=cfg.offline_interval_seconds;
    if not v_due then
      v_next:=st.last_seen_at+make_interval(secs=>cfg.offline_interval_seconds);
      update public.character_opportunity_v3_state
         set next_available_at=v_next,last_seen_at=nowv,updated_at=nowv
       where character_id=c.id;
    end if;
  else
    v_due:=nowv>=st.next_available_at;
  end if;

  if v_due then
    select f.code into v_fate_code
      from public.character_fates cf join public.fates f on f.id=cf.fate_id
     where cf.character_id=c.id and cf.is_active
     order by cf.created_at limit 1;

    if v_fate_code='lucky_encounter' then v_boost:=1.10; end if;
    v_w_ex:=v_w_ex*v_boost;
    v_w_im:=v_w_im*v_boost;
    v_w_he:=v_w_he*v_boost;
    v_w_ea:=v_w_ea*v_boost;
    v_total:=v_w_ex+v_w_im+v_w_he+v_w_ea+v_w_my+v_w_ye;
    v_roll:=random()*v_total;

    if v_roll<v_w_ex then v_rarity:='专属';
    elsif v_roll<v_w_ex+v_w_im then v_rarity:='仙品';
    elsif v_roll<v_w_ex+v_w_im+v_w_he then v_rarity:='天品';
    elsif v_roll<v_w_ex+v_w_im+v_w_he+v_w_ea then v_rarity:='地品';
    elsif v_roll<v_w_ex+v_w_im+v_w_he+v_w_ea+v_w_my then v_rarity:='玄品';
    else v_rarity:='黄品'; end if;

    v_path:=case when (c.luck+c.mindset+random()*100)>=110 then 'auspicious' else 'risk' end;
    v_catalog_code:=null;

    if v_rarity='专属' then
      select exists(select 1 from public.exclusive_technique_definitions where fate_code=v_fate_code)
        into v_fate_has_definition;
      select exists(
        select 1 from public.character_exclusive_techniques cet
        join public.exclusive_technique_definitions etd on etd.code=cet.exclusive_code
        where cet.character_id=c.id and etd.fate_code=v_fate_code
      ) into v_has_own;

      if v_fate_has_definition then
        v_pity:=greatest(20,least(100,coalesce((st.exclusive_pity->>v_fate_code)::numeric,20)));
        if v_has_own then v_pity:=0; end if;
        v_other_weight:=case when v_has_own then 25 else (100-v_pity)/4 end;
      else
        v_pity:=0;
        v_other_weight:=20;
      end if;

      v_pick:=random()*100;
      v_running:=0;
      for v_exclusive in
        select etd.*,
          case
            when etd.fate_code=v_fate_code then v_pity
            else v_other_weight
          end as draw_weight
        from public.exclusive_technique_definitions etd
        order by etd.code
      loop
        v_running:=v_running+v_exclusive.draw_weight;
        if v_pick<=v_running then exit; end if;
      end loop;

      if v_exclusive.fate_code=v_fate_code and not v_has_own then
        update public.character_exclusive_techniques set equipped=false where character_id=c.id;
        insert into public.character_exclusive_techniques(character_id,exclusive_code,level,equipped)
        values(c.id,v_exclusive.code,1,true)
        on conflict(character_id,exclusive_code) do update set equipped=true;

        v_acquired:=coalesce(st.acquired_exclusive_codes,'[]'::jsonb);
        if not (v_acquired@>jsonb_build_array(v_exclusive.code)) then
          v_acquired:=v_acquired||jsonb_build_array(v_exclusive.code);
        end if;
        update public.character_opportunity_v3_state
           set acquired_exclusive_codes=v_acquired,
               exclusive_pity=jsonb_set(coalesce(exclusive_pity,'{}'::jsonb),array[v_fate_code],to_jsonb(20),true),
               updated_at=nowv
         where character_id=c.id;
        perform public.refresh_exclusive_technique_effects_v1(c.id);

        v_title:='专属功法·'||v_exclusive.name;
        v_story:='天命牵引，一卷与你命格完全契合的道法自虚空垂落，直接归入独立专属槽。';
        v_positive:='获得专属功法《'||v_exclusive.name||'》，一级修炼速度+30%，效果已实际生效。';
        v_negative:='本命专属已获得，后续不会重复获得本命专属。';
      else
        if v_fate_has_definition and not v_has_own then
          v_pity:=least(100,v_pity+2);
          update public.character_opportunity_v3_state
             set exclusive_pity=jsonb_set(coalesce(exclusive_pity,'{}'::jsonb),array[v_fate_code],to_jsonb(v_pity),true),
                 updated_at=nowv
           where character_id=c.id;
        end if;
        v_title:='专属机缘·天道收回';
        v_story:='天机一转，落下的是《'||v_exclusive.name||'》，却与你命格并不相合，被天道收回。';
        v_positive:='补偿灵石（100）'||case when v_fate_has_definition and not v_has_own then '；下一次本命专属概率提升至'||v_pity||'%' else '' end;
        v_negative:='此次未真正获得专属功法。';
      end if;
    else
      select * into ev from public.opportunity_v3_catalog
       where grade=v_rarity and is_active order by random() limit 1;
      if ev.code is null then raise exception 'OPPORTUNITY_CONTENT_MISSING'; end if;
      v_catalog_code:=ev.code;
      v_title:=ev.title;
      v_story:=ev.story;
      v_positive:=ev.positive_text;
      v_negative:=ev.negative_text;
    end if;

    insert into public.opportunity_v3_results(
      character_id,catalog_code,rarity,path_key,reward_text,penalty_text,result_data
    ) values (
      c.id,v_catalog_code,v_rarity,v_path,v_positive,
      case when public.opportunity_v3_penalty_hours(v_rarity)>0
           then format('天机迟滞%s小时；%s',public.opportunity_v3_penalty_hours(v_rarity),coalesce(v_negative,''))
           else coalesce(v_negative,'') end,
      jsonb_build_object('title',v_title,'story',v_story)
    ) returning id into v_result_id;

    v_applied:=public.apply_opportunity_v3_effects_v1(
      c.id,c.lineage_id,greatest(1,c.birth_year+c.age),v_result_id,v_catalog_code,
      v_rarity,v_positive,v_negative,nowv
    );

    insert into public.opportunity_v3_effect_ledger(
      character_id,result_id,effect_type,amount,expires_at,metadata
    ) values (
      c.id,v_result_id,'resolved',0,
      case when public.opportunity_v3_penalty_hours(v_rarity)>0
           then nowv+make_interval(hours=>public.opportunity_v3_penalty_hours(v_rarity)) else null end,
      jsonb_build_object('applied',v_applied,'positive',v_positive,'negative',v_negative)
    );

    insert into public.history_logs(
      world_id,world_year,scope_type,scope_id,event_type,title,content,importance,visibility,metadata
    ) values (
      c.world_id,greatest(1,c.birth_year+c.age),'character',c.id,'opportunity',
      '机缘·'||coalesce(v_title,v_rarity),
      coalesce(v_story,'')||'【所得】'||coalesce(v_positive,'')||'【代价】'||coalesce(v_negative,''),
      case v_rarity when '专属' then 5 when '仙品' then 5 when '天品' then 4 when '地品' then 3 when '玄品' then 2 else 1 end,
      'owner',jsonb_build_object('v','0.11.5','result_id',v_result_id,'path',v_path,'applied',v_applied)
    );

    v_next:=nowv+make_interval(secs=>cfg.online_interval_seconds);
    update public.character_opportunity_v3_state
       set next_available_at=v_next,last_seen_at=nowv,total_resolved=total_resolved+1,
           last_result=jsonb_build_object(
             'result_id',v_result_id,'title',v_title,'content',v_story,
             'reward_text',v_positive,'penalty_text',v_negative,
             'rarity',v_rarity,'rarity_name',v_rarity,
             'path_name',case v_path when 'auspicious' then '趋吉' else '涉险' end,
             'applied',v_applied,'created_at',nowv
           ),updated_at=nowv
     where character_id=c.id;
  else
    update public.character_opportunity_v3_state set last_seen_at=nowv,updated_at=nowv where character_id=c.id;
  end if;

  select * into st from public.character_opportunity_v3_state where character_id=c.id;
  return jsonb_build_object(
    'status','waiting','automatic',true,'next_available_at',st.next_available_at,
    'seconds_until_next',greatest(0,extract(epoch from st.next_available_at-nowv)::int),
    'last_result',st.last_result,
    'online_interval_seconds',cfg.online_interval_seconds,
    'offline_interval_seconds',cfg.offline_interval_seconds,
    'offline_catchup_limit',cfg.offline_catchup_limit
  );
end$$;

-- 12. 已有数据回填效果。
do $$
declare r record;
begin
  for r in select distinct character_id from public.character_techniques loop
    perform public.refresh_opportunity_technique_effects_v1(r.character_id);
  end loop;
  for r in select distinct character_id from public.character_exclusive_techniques loop
    perform public.refresh_exclusive_technique_effects_v1(r.character_id);
  end loop;
end$$;

-- 13. 权限：只开放玩家必须调用的读取/操作 RPC；内部辅助函数不向客户端开放。
revoke all on function public.award_spirit_stones_v3(uuid,bigint) from public,anon,authenticated;
revoke all on function public.opportunity_v3_penalty_hours(text) from public,anon,authenticated;
revoke all on function public.v0115_linear_effect_v1(numeric,integer,numeric) from public,anon,authenticated;
revoke all on function public.exclusive_technique_effect_bonus_v1(integer,numeric) from public,anon,authenticated;
revoke all on function public.refresh_opportunity_technique_effects_v1(uuid) from public,anon,authenticated;
revoke all on function public.trg_refresh_opportunity_technique_effects_v1() from public,anon,authenticated;
revoke all on function public.refresh_exclusive_technique_effects_v1(uuid) from public,anon,authenticated;
revoke all on function public.award_opportunity_technique_v3(uuid,text,integer) from public,anon,authenticated;
revoke all on function public.award_cave_resource_v3(uuid,text,numeric) from public,anon,authenticated;
revoke all on function public.apply_opportunity_v3_effects_v1(uuid,uuid,integer,uuid,text,text,text,text,timestamptz) from public,anon,authenticated;

revoke all on function public.get_exclusive_technique_system_v1() from public,anon;
revoke all on function public.set_exclusive_technique_slot_v1(uuid) from public,anon;
revoke all on function public.upgrade_exclusive_technique_v1(uuid) from public,anon;
revoke all on function public.get_auto_opportunity_v3() from public,anon;

grant execute on function public.get_exclusive_technique_system_v1() to authenticated;
grant execute on function public.set_exclusive_technique_slot_v1(uuid) to authenticated;
grant execute on function public.upgrade_exclusive_technique_v1(uuid) to authenticated;
grant execute on function public.get_auto_opportunity_v3() to authenticated;

commit;
