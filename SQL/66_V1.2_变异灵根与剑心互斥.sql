-- 九霄问道 V1.2 CACHE37
-- 变异灵根（雷/风/冰）、天生剑心互斥、冲突随机替换及最终伤害8%。
-- 规则：
-- 1. 变异灵根+金=雷；+木=风；+水=冰；原本五行仍负责既有克制。
-- 2. 风冰雷不建立新的克制关系，只在最终伤害层提供8%加成。
-- 3. 天生剑心与任何变异灵根互斥；后获得的一方发生冲突时，被随机替换为合法灵根或合法命格。
-- 4. 历史冲突因无法可靠判定先后，迁移时随机选择替换灵根或命格，并完整留痕。
begin;

create schema if not exists ncd_release_backup;
revoke all on schema ncd_release_backup from public;
create table if not exists ncd_release_backup.v12_functions(
  signature text primary key,
  definition text not null
);
insert into ncd_release_backup.v12_functions(signature,definition)
select p.oid::regprocedure::text,pg_get_functiondef(p.oid)
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.oid in (
  to_regprocedure('public.bcombat01_character_snapshot(uuid)'),
  to_regprocedure('public.bcombat01_resolve_hit(jsonb,jsonb,integer,integer,integer)'),
  to_regprocedure('public.get_character_fate_status_b01()'),
  to_regprocedure('public.use_spirit_washing_pill_v0154(uuid)')
)
on conflict(signature) do nothing;

create table if not exists public.character_talent_conflict_logs_v12(
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.player_characters(id) on delete cascade,
  conflict_code text not null,
  attempted_kind text not null check(attempted_kind in('spirit_root','fate','migration')),
  replacement_kind text not null check(replacement_kind in('spirit_root','fate')),
  attempted_value jsonb not null default '{}'::jsonb,
  replacement_value jsonb not null default '{}'::jsonb,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp()
);
alter table public.character_talent_conflict_logs_v12 enable row level security;
revoke all on table public.character_talent_conflict_logs_v12 from public,anon,authenticated;
create index if not exists idx_character_talent_conflict_logs_v12_character
  on public.character_talent_conflict_logs_v12(character_id,created_at desc);

create or replace function public.v12_is_mutant_root(p_root_id smallint)
returns boolean
language sql
stable
security definer
set search_path=pg_catalog,public,pg_temp
as $$
  select exists(
    select 1 from public.spirit_roots sr
    where sr.id=p_root_id
      and concat_ws(' ',coalesce(sr.name,''),coalesce(sr.code,''),coalesce(sr.rarity,'')) ~* '(变异|异灵根|variant|mutant)'
  )
$$;
revoke all on function public.v12_is_mutant_root(smallint) from public,anon,authenticated;

create or replace function public.v12_mutation_element(
  p_root_id smallint,
  p_base_element text,
  p_fate_code text default null
)
returns text
language sql
stable
security definer
set search_path=pg_catalog,public,pg_temp
as $$
  select case
    when coalesce(p_fate_code,'')='sword_heart' then null
    when not public.v12_is_mutant_root(p_root_id) then null
    when p_base_element='metal' then 'thunder'
    when p_base_element='wood' then 'wind'
    when p_base_element='water' then 'ice'
    else null
  end
$$;
revoke all on function public.v12_mutation_element(smallint,text,text) from public,anon,authenticated;

create or replace function public.v12_mutation_label(p_mutation text)
returns text
language sql
immutable
set search_path=pg_catalog,pg_temp
as $$
  select case p_mutation when 'thunder' then '雷' when 'ice' then '冰' when 'wind' then '风' else '' end
$$;
revoke all on function public.v12_mutation_label(text) from public,anon,authenticated;

create or replace function public.v12_random_non_mutant_root(
  p_character_id uuid,
  p_exclude_root_id smallint default null
)
returns smallint
language plpgsql
volatile
security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare v_id smallint;
begin
  select sr.id into v_id
  from public.spirit_roots sr
  where not public.v12_is_mutant_root(sr.id)
    and (p_exclude_root_id is null or sr.id<>p_exclude_root_id)
    and not exists(
      select 1 from public.character_spirit_roots csr
      where csr.character_id=p_character_id and csr.spirit_root_id=sr.id
    )
  order by public.casino_secure_random_int_v1(2147483647),sr.id limit 1;
  if v_id is null then
    select sr.id into v_id from public.spirit_roots sr
    where not public.v12_is_mutant_root(sr.id)
      and (p_exclude_root_id is null or sr.id<>p_exclude_root_id)
    order by public.casino_secure_random_int_v1(2147483647),sr.id limit 1;
  end if;
  return v_id;
end
$$;
revoke all on function public.v12_random_non_mutant_root(uuid,smallint) from public,anon,authenticated;

create or replace function public.v12_random_non_sword_fate(
  p_character_id uuid,
  p_exclude_fate_id smallint default null
)
returns smallint
language plpgsql
volatile
security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare v_id smallint;
begin
  select f.id into v_id
  from public.fates f
  where f.code<>'sword_heart'
    and (p_exclude_fate_id is null or f.id<>p_exclude_fate_id)
    and not exists(
      select 1 from public.character_fates cf
      where cf.character_id=p_character_id and cf.fate_id=f.id
    )
  order by public.casino_secure_random_int_v1(2147483647),f.id limit 1;
  if v_id is null then
    select f.id into v_id from public.fates f
    where f.code<>'sword_heart'
      and (p_exclude_fate_id is null or f.id<>p_exclude_fate_id)
    order by public.casino_secure_random_int_v1(2147483647),f.id limit 1;
  end if;
  return v_id;
end
$$;
revoke all on function public.v12_random_non_sword_fate(uuid,smallint) from public,anon,authenticated;

create or replace function public.v12_guard_mutant_root_against_sword_heart()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare v_new_root smallint;v_old_name text;v_new_name text;
begin
  if not coalesce(new.is_primary,false) or not public.v12_is_mutant_root(new.spirit_root_id) then return new; end if;
  if not exists(
    select 1 from public.character_fates cf join public.fates f on f.id=cf.fate_id
    where cf.character_id=new.character_id and cf.is_active and f.code='sword_heart'
  ) then return new; end if;
  select name into v_old_name from public.spirit_roots where id=new.spirit_root_id;
  v_new_root:=public.v12_random_non_mutant_root(new.character_id,new.spirit_root_id);
  if v_new_root is null then raise exception 'V12_NO_LEGAL_SPIRIT_ROOT_REPLACEMENT'; end if;
  select name into v_new_name from public.spirit_roots where id=v_new_root;
  insert into public.character_talent_conflict_logs_v12(
    character_id,conflict_code,attempted_kind,replacement_kind,attempted_value,replacement_value,metadata
  ) values(
    new.character_id,'SWORD_HEART_BLOCKS_MUTANT_ROOT','spirit_root','spirit_root',
    jsonb_build_object('root_id',new.spirit_root_id,'root_name',coalesce(v_old_name,'')),
    jsonb_build_object('root_id',v_new_root,'root_name',coalesce(v_new_name,'')),
    jsonb_build_object('resolution','replace_later_acquired_root')
  );
  new.spirit_root_id:=v_new_root;
  return new;
end
$$;
revoke all on function public.v12_guard_mutant_root_against_sword_heart() from public,anon,authenticated;

drop trigger if exists trg_v12_mutant_root_conflict_guard on public.character_spirit_roots;
create trigger trg_v12_mutant_root_conflict_guard
before insert or update of spirit_root_id,is_primary on public.character_spirit_roots
for each row execute function public.v12_guard_mutant_root_against_sword_heart();

create or replace function public.v12_guard_sword_heart_against_mutant_root()
returns trigger
language plpgsql
security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare v_code text;v_new_fate smallint;v_old_name text;v_new_name text;
begin
  if not coalesce(new.is_active,false) then return new; end if;
  select code,name into v_code,v_old_name from public.fates where id=new.fate_id;
  if coalesce(v_code,'')<>'sword_heart' then return new; end if;
  if not exists(
    select 1 from public.character_spirit_roots csr
    where csr.character_id=new.character_id and csr.is_primary and public.v12_is_mutant_root(csr.spirit_root_id)
  ) then return new; end if;
  v_new_fate:=public.v12_random_non_sword_fate(new.character_id,new.fate_id);
  if v_new_fate is null then raise exception 'V12_NO_LEGAL_FATE_REPLACEMENT'; end if;
  select name into v_new_name from public.fates where id=v_new_fate;
  insert into public.character_talent_conflict_logs_v12(
    character_id,conflict_code,attempted_kind,replacement_kind,attempted_value,replacement_value,metadata
  ) values(
    new.character_id,'MUTANT_ROOT_BLOCKS_SWORD_HEART','fate','fate',
    jsonb_build_object('fate_id',new.fate_id,'fate_name',coalesce(v_old_name,''),'fate_code',v_code),
    jsonb_build_object('fate_id',v_new_fate,'fate_name',coalesce(v_new_name,'')),
    jsonb_build_object('resolution','replace_later_acquired_fate')
  );
  new.fate_id:=v_new_fate;
  return new;
end
$$;
revoke all on function public.v12_guard_sword_heart_against_mutant_root() from public,anon,authenticated;

drop trigger if exists trg_v12_sword_heart_conflict_guard on public.character_fates;
create trigger trg_v12_sword_heart_conflict_guard
before insert or update of fate_id,is_active on public.character_fates
for each row execute function public.v12_guard_sword_heart_against_mutant_root();

-- 修复升级前已同时拥有天生剑心与变异灵根的历史角色。
-- 无法可靠判定先后，因此逐角色随机替换其中一项；替换结果写入审计日志。
do $$
declare
  r record;v_replace_root boolean;v_new_id smallint;v_old_name text;v_new_name text;
begin
  for r in
    select distinct csr.character_id,csr.spirit_root_id,cf.fate_id
    from public.character_spirit_roots csr
    join public.character_fates cf on cf.character_id=csr.character_id and cf.is_active
    join public.fates f on f.id=cf.fate_id and f.code='sword_heart'
    where csr.is_primary and public.v12_is_mutant_root(csr.spirit_root_id)
    order by csr.character_id
  loop
    v_replace_root:=public.casino_secure_random_int_v1(2)=0;
    if v_replace_root then
      v_new_id:=public.v12_random_non_mutant_root(r.character_id,r.spirit_root_id);
      if v_new_id is not null then
        select name into v_old_name from public.spirit_roots where id=r.spirit_root_id;
        select name into v_new_name from public.spirit_roots where id=v_new_id;
        update public.character_spirit_roots set spirit_root_id=v_new_id
        where character_id=r.character_id and is_primary and spirit_root_id=r.spirit_root_id;
        insert into public.character_talent_conflict_logs_v12(character_id,conflict_code,attempted_kind,replacement_kind,attempted_value,replacement_value,metadata)
        values(r.character_id,'MIGRATION_EXISTING_TALENT_CONFLICT','migration','spirit_root',
          jsonb_build_object('root_id',r.spirit_root_id,'root_name',coalesce(v_old_name,''),'fate_id',r.fate_id),
          jsonb_build_object('root_id',v_new_id,'root_name',coalesce(v_new_name,'')),
          jsonb_build_object('resolution','random_existing_conflict','random_branch','spirit_root'));
        continue;
      end if;
    end if;
    v_new_id:=public.v12_random_non_sword_fate(r.character_id,r.fate_id);
    if v_new_id is null then raise exception 'V12_EXISTING_CONFLICT_NO_REPLACEMENT:%',r.character_id; end if;
    select name into v_old_name from public.fates where id=r.fate_id;
    select name into v_new_name from public.fates where id=v_new_id;
    update public.character_fates set fate_id=v_new_id
    where character_id=r.character_id and fate_id=r.fate_id and is_active;
    insert into public.character_talent_conflict_logs_v12(character_id,conflict_code,attempted_kind,replacement_kind,attempted_value,replacement_value,metadata)
    values(r.character_id,'MIGRATION_EXISTING_TALENT_CONFLICT','migration','fate',
      jsonb_build_object('fate_id',r.fate_id,'fate_name',coalesce(v_old_name,''),'root_id',r.spirit_root_id),
      jsonb_build_object('fate_id',v_new_id,'fate_name',coalesce(v_new_name,'')),
      jsonb_build_object('resolution','random_existing_conflict','random_branch','fate'));
  end loop;
end
$$;

alter table public.battle_challenge_settings_bcombat01
  add column if not exists mutation_bonus_enabled boolean not null default true,
  add column if not exists mutation_final_damage_bonus numeric(7,6) not null default 0.08;
do $$ begin
  if not exists(select 1 from pg_constraint where conname='battle_settings_v12_mutation_bonus_check') then
    alter table public.battle_challenge_settings_bcombat01
      add constraint battle_settings_v12_mutation_bonus_check
      check(mutation_final_damage_bonus>=0 and mutation_final_damage_bonus<=0.20);
  end if;
end $$;
update public.battle_challenge_settings_bcombat01
set mutation_bonus_enabled=true,mutation_final_damage_bonus=0.08,updated_at=clock_timestamp()
where singleton_id=1;

-- 原位替换战斗快照，保持函数OID不变，确保所有既有调用方均读取变异状态。
create or replace function public.bcombat01_character_snapshot(p_character_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,pg_temp as $$
declare v_result jsonb;
begin
  select jsonb_build_object(
    'character_id',pc.id,'user_id',pc.user_id,'world_id',pc.world_id,'name',pc.name,
    'generation',pc.generation_number,'cultivation',greatest(0,pc.cultivation),
    'realm_stage_id',pc.realm_stage_id,'major_order',r.major_order,'minor_level',rs.minor_level,
    'realm',case when r.code='mortal' then coalesce(rs.stage_name,r.name,'凡人')
      else concat(r.name,case when coalesce(rs.stage_name,'')='' then '' else ' · '||rs.stage_name end) end,
    'realm_coefficient',s.realm_coefficient,
    'element',p.element,'element_name',public.bcombat01_element_label(p.element),
    'fate_code',coalesce(fate.fate_code,''),'fate_name',coalesce(fate.fate_name,'未定命格'),
    'spirit_root_id',rootinfo.spirit_root_id,
    'spirit_root_name',coalesce(rootinfo.spirit_root_name,'未知灵根'),
    'spirit_root_is_mutant',coalesce(rootinfo.is_mutant,false),
    'mutation_element',coalesce(mutation.mutation_element,''),
    'mutation_name',public.v12_mutation_label(mutation.mutation_element),
    'mutation_active',settings.mutation_bonus_enabled and mutation.mutation_element is not null,
    'mutation_final_damage_bonus',case
      when settings.mutation_bonus_enabled and mutation.mutation_element is not null
      then settings.mutation_final_damage_bonus else 0 end,
    'mutation_display',case when mutation.mutation_element is not null
      then '变异灵根（'||public.v12_mutation_label(mutation.mutation_element)||'）' else '' end,
    'talent_conflict',coalesce(rootinfo.is_mutant,false) and coalesce(fate.fate_code,'')='sword_heart',
    'base_attack',s.dao_attack,'base_defense',s.dao_defense,'base_vitality',s.vitality,'base_agility',s.agility,
    'weapon_name',coalesce(nullif(btrim(loadout.weapon_name),''),'赤手空拳'),
    'weapon_kind',coalesce(nullif(btrim(loadout.weapon_kind),''),'unarmed'),
    'armor_name',coalesce(nullif(btrim(loadout.armor_name),''),'赤裸'),
    'is_unarmed',nullif(btrim(loadout.weapon_name),'') is null,
    'is_naked',nullif(btrim(loadout.armor_name),'') is null,
    'effective_weapon_attack',calc.weapon_attack,'effective_armor_defense',calc.armor_defense,
    'effective_armor_vitality',calc.armor_vitality,'effective_armor_agility',calc.armor_agility,
    'attack_technique_name',coalesce(atk.name,'未修攻伐功法'),
    'attack_technique_code',coalesce(atk.code,''),'attack_skill_multiplier',calc.skill_multiplier,
    'is_sword_technique',calc.is_sword_technique,
    'defense_technique_name',coalesce(deftech.name,'未修护体功法'),
    'defense_technique_reduction',calc.defense_technique_reduction,
    'attack',calc.final_attack,'defense',calc.final_defense,'vitality',calc.final_vitality,'agility',calc.final_agility,
    'power',round(calc.final_attack*10+calc.final_defense*8+calc.final_vitality*1.5+calc.final_agility*5)::bigint,
    'sword_heart_active',(coalesce(fate.fate_code,'')='sword_heart'
      and mutation.mutation_element is null
      and coalesce(loadout.weapon_kind,'')='sword' and calc.is_sword_technique)
  ) into v_result
  from public.player_characters pc
  join public.realm_stages rs on rs.id=pc.realm_stage_id
  join public.realms r on r.id=rs.realm_id
  join public.combat_realm_stats_bcombat01 s on s.major_order=r.major_order and s.minor_level=rs.minor_level
  join public.character_combat_profiles_bcombat01 p on p.character_id=pc.id
  left join public.character_combat_loadouts_bcombat01 loadout on loadout.character_id=pc.id
  left join lateral (
    select f.code as fate_code,f.name as fate_name
    from public.character_fates cf join public.fates f on f.id=cf.fate_id
    where cf.character_id=pc.id and cf.is_active order by cf.created_at asc,cf.fate_id asc limit 1
  ) fate on true
  left join lateral (
    select csr.spirit_root_id,sr.name as spirit_root_name,
      public.v12_is_mutant_root(csr.spirit_root_id) as is_mutant
    from public.character_spirit_roots csr join public.spirit_roots sr on sr.id=csr.spirit_root_id
    where csr.character_id=pc.id and csr.is_primary
    order by csr.awakened_year nulls last,csr.spirit_root_id limit 1
  ) rootinfo on true
  cross join lateral (
    select public.v12_mutation_element(
      rootinfo.spirit_root_id,p.element,coalesce(fate.fate_code,'')
    ) as mutation_element
  ) mutation
  cross join lateral (
    select
      coalesce((select b.mutation_bonus_enabled
        from public.battle_challenge_settings_bcombat01 b where b.singleton_id=1),true) as mutation_bonus_enabled,
      coalesce((select b.mutation_final_damage_bonus
        from public.battle_challenge_settings_bcombat01 b where b.singleton_id=1),0.08) as mutation_final_damage_bonus
  ) settings
  left join lateral (
    select t.code,t.name,coalesce(t.fixed_effects,'{}'::jsonb) fixed_effects
    from public.character_techniques ct join public.techniques t on t.id=ct.technique_id
    where ct.character_id=pc.id and ct.v0152_slot_index=1 and coalesce(t.is_active,true)
    order by ct.created_at asc,ct.id asc limit 1
  ) atk on true
  left join lateral (
    select t.code,t.name,coalesce(t.fixed_effects,'{}'::jsonb) fixed_effects
    from public.character_techniques ct join public.techniques t on t.id=ct.technique_id
    where ct.character_id=pc.id and ct.v0152_slot_index between 2 and 5
      and t.category='support' and coalesce(t.is_active,true)
    order by ct.v0152_slot_index asc,ct.created_at asc,ct.id asc limit 1
  ) deftech on true
  cross join lateral (
    select
      round(coalesce(loadout.weapon_attack,0)*least(1,s.realm_coefficient/greatest(0.01,coalesce(loadout.weapon_requirement_coefficient,1))))::integer weapon_attack,
      round(coalesce(loadout.armor_defense,0)*least(1,s.realm_coefficient/greatest(0.01,coalesce(loadout.armor_requirement_coefficient,1))))::integer armor_defense,
      round(coalesce(loadout.armor_vitality,0)*least(1,s.realm_coefficient/greatest(0.01,coalesce(loadout.armor_requirement_coefficient,1))))::integer armor_vitality,
      round(coalesce(loadout.armor_agility,0)*least(1,s.realm_coefficient/greatest(0.01,coalesce(loadout.armor_requirement_coefficient,1))))::integer armor_agility,
      least(1.8,greatest(1,coalesce(nullif(atk.fixed_effects->>'combat_skill_multiplier','')::numeric,1))) skill_multiplier,
      least(0.20,greatest(0,coalesce(nullif(deftech.fixed_effects->>'combat_damage_reduction','')::numeric,0))) defense_technique_reduction,
      (coalesce(atk.fixed_effects->>'combat_school','')='sword' or coalesce(atk.name,'') like '%剑%') is_sword_technique
  ) raw
  cross join lateral (
    select raw.weapon_attack,raw.armor_defense,raw.armor_vitality,raw.armor_agility,
      raw.skill_multiplier,raw.defense_technique_reduction,raw.is_sword_technique,
      greatest(1,s.dao_attack+raw.weapon_attack)::integer final_attack,
      greatest(0,s.dao_defense+raw.armor_defense)::integer final_defense,
      greatest(1,s.vitality+raw.armor_vitality)::integer final_vitality,
      greatest(1,s.agility+raw.armor_agility)::integer final_agility
  ) calc
  where pc.id=p_character_id and pc.status in('active','secluded','missing');
  return v_result;
end$$;
revoke all on function public.bcombat01_character_snapshot(uuid) from public,anon,authenticated;

-- 排行榜继续使用V1.1双向挑战规则，只追加变异灵根展示字段。
create or replace function public.get_battle_power_ranking_bcombat01(p_limit integer default 50,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_self_id uuid;v_self jsonb;v_self_power bigint:=0;v_total integer;v_entries jsonb;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED';end if;
  if p_limit is null or p_limit<1 or p_limit>100 or p_offset is null or p_offset<0 then raise exception 'INVALID_RANKING_PAGE';end if;
  select pc.id into v_self_id from public.player_characters pc
  where pc.user_id=v_user_id and pc.status in('active','secluded','missing') order by pc.created_at desc limit 1;
  if v_self_id is null then raise exception 'NO_ACTIVE_CHARACTER';end if;
  v_self:=public.bcombat01_character_snapshot(v_self_id);
  v_self_power:=coalesce((v_self->>'power')::bigint,0);
  with source as (
    select pc.id,pc.user_id,pc.created_at,public.bcombat01_character_snapshot(pc.id) snap
    from public.player_characters pc join public.character_combat_profiles_bcombat01 cp on cp.character_id=pc.id
    where pc.status in('active','secluded','missing')
  ),valid as (select * from source where snap is not null),
  ranked as (
    select row_number() over(order by (snap->>'power')::bigint desc,(snap->>'major_order')::int desc,
      (snap->>'minor_level')::int desc,(snap->>'cultivation')::bigint desc,created_at asc,id asc)::integer rank,
      id,user_id,snap from valid
  )
  select count(*)::integer into v_total from ranked;
  with source as (
    select pc.id,pc.user_id,pc.created_at,public.bcombat01_character_snapshot(pc.id) snap
    from public.player_characters pc join public.character_combat_profiles_bcombat01 cp on cp.character_id=pc.id
    where pc.status in('active','secluded','missing')
  ),valid as (select * from source where snap is not null),
  ranked as (
    select row_number() over(order by (snap->>'power')::bigint desc,(snap->>'major_order')::int desc,
      (snap->>'minor_level')::int desc,(snap->>'cultivation')::bigint desc,created_at asc,id asc)::integer rank,
      id,user_id,snap from valid
  ),page as (select * from ranked where rank>p_offset and rank<=p_offset+p_limit order by rank)
  select coalesce(jsonb_agg(jsonb_build_object(
    'rank',rank,'character_id',id,'name',snap->>'name','realm',snap->>'realm',
    'fate',snap->>'fate_name','generation',(snap->>'generation')::integer,
    'element',snap->>'element','element_name',snap->>'element_name',
    'mutation_element',snap->>'mutation_element','mutation_name',snap->>'mutation_name',
    'mutation_active',coalesce((snap->>'mutation_active')::boolean,false),
    'mutation_display',snap->>'mutation_display',
    'power',(snap->>'power')::bigint,'is_self',user_id=v_user_id,
    'can_challenge',id<>v_self_id
  ) order by rank),'[]'::jsonb) into v_entries from page;
  return jsonb_build_object('status','ok','board_type','battle',
    'ranking_rule','高低战力可互相挑战；低战力胜高战力转移阶段进度1%，高战力胜低战力转移0.5%',
    'entries',v_entries,'total_count',v_total,'offset',p_offset,'limit',p_limit,
    'has_more',p_offset+jsonb_array_length(v_entries)<v_total,'self_power',v_self_power,'self',v_self);
end$$;
revoke all on function public.get_battle_power_ranking_bcombat01(integer,integer) from public,anon,authenticated;
grant execute on function public.get_battle_power_ranking_bcombat01(integer,integer) to authenticated;

create or replace function public.bcombat01_resolve_hit(
  p_attacker jsonb,p_defender jsonb,p_defender_hp integer,p_round integer,p_sequence integer
)
returns jsonb
language plpgsql
volatile
security definer
set search_path=pg_catalog,public,pg_temp
as $$
declare
  v_element numeric;v_base_reduction numeric;v_total_reduction numeric;
  v_sword numeric:=1;v_mutation numeric:=1;v_damage integer;v_hp_after integer;
  v_settings public.battle_challenge_settings_bcombat01%rowtype;
begin
  select * into v_settings from public.battle_challenge_settings_bcombat01 where singleton_id=1;
  v_element:=public.bcombat01_element_multiplier(
    p_attacker->>'element',p_defender->>'element',
    (p_attacker->>'major_order')::integer,(p_attacker->>'minor_level')::integer,
    (p_defender->>'major_order')::integer,(p_defender->>'minor_level')::integer
  );
  v_base_reduction:=least(0.70,(p_defender->>'defense')::numeric/
    greatest(1,(p_defender->>'defense')::numeric+(p_defender->>'base_attack')::numeric*2));
  v_total_reduction:=least(0.80,1-(1-v_base_reduction)*
    (1-coalesce((p_defender->>'defense_technique_reduction')::numeric,0)));
  if coalesce((p_attacker->>'sword_heart_active')::boolean,false) then
    v_sword:=1+coalesce(v_settings.sword_heart_final_damage_bonus,0.08);
  elsif coalesce(v_settings.mutation_bonus_enabled,true)
    and coalesce((p_attacker->>'mutation_active')::boolean,false) then
    v_mutation:=1+coalesce(v_settings.mutation_final_damage_bonus,0.08);
  end if;
  v_damage:=greatest(1,floor((p_attacker->>'attack')::numeric
    *coalesce((p_attacker->>'attack_skill_multiplier')::numeric,1)
    *v_element*v_sword*v_mutation*(1-v_total_reduction)))::integer;
  v_hp_after:=greatest(0,p_defender_hp-v_damage);
  return jsonb_build_object(
    'round',p_round,'sequence',p_sequence,'attacker_id',p_attacker->>'character_id',
    'attacker_name',p_attacker->>'name','defender_id',p_defender->>'character_id',
    'defender_name',p_defender->>'name','weapon_name',p_attacker->>'weapon_name',
    'weapon_kind',p_attacker->>'weapon_kind','is_unarmed',coalesce((p_attacker->>'is_unarmed')::boolean,false),
    'attack_technique_name',p_attacker->>'attack_technique_name','armor_name',p_defender->>'armor_name',
    'is_naked',coalesce((p_defender->>'is_naked')::boolean,false),
    'defense_technique_name',p_defender->>'defense_technique_name',
    'attack_style',1+floor(random()*5)::integer,'defense_style',1+floor(random()*5)::integer,
    'element_multiplier',v_element,'element_relation',
      case when v_element>1 then 'overcome' when v_element<1 then 'restrained' else 'neutral' end,
    'defense_reduction',round(v_total_reduction,6),'sword_heart_multiplier',v_sword,
    'mutation_multiplier',v_mutation,'mutation_element',p_attacker->>'mutation_element',
    'mutation_name',p_attacker->>'mutation_name',
    'damage',v_damage,'hp_before',p_defender_hp,'hp_after',v_hp_after,
    'max_hp',(p_defender->>'vitality')::integer,
    'low_health',v_hp_after>0 and v_hp_after<=floor((p_defender->>'vitality')::numeric*0.30),
    'defeated',v_hp_after<=0
  );
end
$$;
revoke all on function public.bcombat01_resolve_hit(jsonb,jsonb,integer,integer,integer) from public,anon,authenticated;

-- 修正命格状态RPC对天生剑心的旧版“战斗未开放”文案。
do $$ begin
  if to_regprocedure('public.get_character_fate_status_b01_v11_base()') is null then
    alter function public.get_character_fate_status_b01() rename to get_character_fate_status_b01_v11_base;
  end if;
end $$;
create or replace function public.get_character_fate_status_b01()
returns jsonb
language plpgsql
volatile
security definer
set search_path=pg_catalog,public,auth,pg_temp
as $$
declare v_result jsonb;
begin
  v_result:=public.get_character_fate_status_b01_v11_base();
  if coalesce(v_result->>'code','')='sword_heart' then
    v_result:=v_result||jsonb_build_object(
      'special_name','剑心通明',
      'special_description','装备剑类武器并使用剑系功法时，最终伤害提高8%；不能与变异灵根共存。',
      'combat_effect_enabled',true,
      'sword_final_damage_bonus',0.08
    );
  end if;
  return v_result;
end
$$;
revoke all on function public.get_character_fate_status_b01() from public,anon;
grant execute on function public.get_character_fate_status_b01() to authenticated;

-- 洗灵丹返回触发器冲突替换后的真实灵根，而不是被拦截的候选灵根。
create or replace function public.use_spirit_washing_pill_v0154(p_request_id uuid default gen_random_uuid())
returns jsonb language plpgsql security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare
 v_user_id uuid:=auth.uid();v_character public.player_characters%rowtype;v_item_id uuid;v_inventory_id uuid;v_stock bigint;
 v_old_root_id smallint;v_attempted_root_id smallint;v_new_root_id smallint;
 v_old_name text;v_attempted_name text;v_new_name text;
 v_old_multiplier numeric:=1;v_attempted_multiplier numeric:=1;v_new_multiplier numeric:=1;
 v_year integer:=1;v_claim jsonb;v_result jsonb;v_element text;v_fate_code text;v_mutation text;
begin
 if v_user_id is null then raise exception 'AUTH_REQUIRED';end if;
 if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED';end if;
 select pc.* into v_character from public.player_characters pc
 where pc.user_id=v_user_id and pc.status in('active','secluded','missing')
 order by pc.created_at desc limit 1 for update;
 if v_character.id is null then raise exception 'NO_ACTIVE_CHARACTER';end if;
 select r.result into v_result from public.player_operation_requests_v0154 r
 where r.request_id=p_request_id and r.character_id=v_character.id and r.operation='spirit_root_reroll';
 if found then return v_result;end if;
 perform public.claim_cultivation_v1();
 v_item_id:=public.v0154_item_id('spirit_washing_pill_v0154');
 select ci.id,ci.quantity into v_inventory_id,v_stock from public.character_inventory ci
 where ci.character_id=v_character.id and ci.item_definition_id=v_item_id
 order by ci.created_at,ci.id limit 1 for update;
 if v_inventory_id is null or coalesce(v_stock,0)<1 then raise exception 'SPIRIT_WASHING_PILL_INSUFFICIENT';end if;
 select csr.spirit_root_id,sr.name,sr.cultivation_multiplier
 into v_old_root_id,v_old_name,v_old_multiplier
 from public.character_spirit_roots csr join public.spirit_roots sr on sr.id=csr.spirit_root_id
 where csr.character_id=v_character.id and csr.is_primary limit 1 for update of csr;
 if v_old_root_id is null then raise exception 'PRIMARY_SPIRIT_ROOT_MISSING';end if;
 v_attempted_root_id:=public.roll_spirit_root_v0154();
 if v_attempted_root_id is null then raise exception 'SPIRIT_ROOT_POOL_EMPTY';end if;
 select sr.name,sr.cultivation_multiplier into v_attempted_name,v_attempted_multiplier
 from public.spirit_roots sr where sr.id=v_attempted_root_id;
 update public.character_spirit_roots
 set spirit_root_id=v_attempted_root_id,awakened_year=coalesce(awakened_year,v_year)
 where character_id=v_character.id and is_primary;
 select csr.spirit_root_id,sr.name,sr.cultivation_multiplier
 into v_new_root_id,v_new_name,v_new_multiplier
 from public.character_spirit_roots csr join public.spirit_roots sr on sr.id=csr.spirit_root_id
 where csr.character_id=v_character.id and csr.is_primary limit 1;
 if v_stock=1 then delete from public.character_inventory where id=v_inventory_id;
 else update public.character_inventory set quantity=quantity-1,updated_at=now() where id=v_inventory_id;end if;
 select p.element into v_element from public.character_combat_profiles_bcombat01 p where p.character_id=v_character.id;
 select f.code into v_fate_code from public.character_fates cf join public.fates f on f.id=cf.fate_id
 where cf.character_id=v_character.id and cf.is_active order by cf.created_at limit 1;
 v_mutation:=public.v12_mutation_element(v_new_root_id,v_element,v_fate_code);
 select to_jsonb(x) into v_claim from public.claim_cultivation_v1() x;
 v_result:=jsonb_build_object('success',true,'old_root_id',v_old_root_id,'old_root_name',v_old_name,
   'old_cultivation_multiplier',coalesce(v_old_multiplier,1),
   'attempted_root_id',v_attempted_root_id,'attempted_root_name',v_attempted_name,
   'new_root_id',v_new_root_id,'new_root_name',v_new_name,
   'new_cultivation_multiplier',coalesce(v_new_multiplier,1),
   'conflict_replaced',v_new_root_id is distinct from v_attempted_root_id,
   'mutation_element',coalesce(v_mutation,''),'mutation_name',public.v12_mutation_label(v_mutation),
   'mutation_display',case when v_mutation is not null then '变异灵根（'||public.v12_mutation_label(v_mutation)||'）' else '' end,
   'current_rate_per_second',coalesce((v_claim->>'current_rate_per_second')::numeric,0),
   'quantity_remaining',greatest(0,v_stock-1),'request_id',p_request_id);
 insert into public.player_operation_requests_v0154(request_id,character_id,operation,result)
 values(p_request_id,v_character.id,'spirit_root_reroll',v_result);
 return v_result;
end
$$;
revoke all on function public.use_spirit_washing_pill_v0154(uuid) from public,anon;
grant execute on function public.use_spirit_washing_pill_v0154(uuid) to authenticated;

create or replace function public.get_my_birth_result_v12()
returns jsonb
language plpgsql
stable
security definer
set search_path=pg_catalog,public,auth,pg_temp
as $$
declare
  v_user uuid:=auth.uid();v_character uuid;v_root_id smallint;v_root_name text;
  v_fate_code text;v_fate_name text;v_element text;v_mutation text;
begin
  if v_user is null then raise exception 'AUTH_REQUIRED'; end if;
  select id into v_character from public.player_characters
  where user_id=v_user and status in('active','secluded','missing') order by created_at desc limit 1;
  if v_character is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;
  select csr.spirit_root_id,sr.name into v_root_id,v_root_name
  from public.character_spirit_roots csr join public.spirit_roots sr on sr.id=csr.spirit_root_id
  where csr.character_id=v_character and csr.is_primary limit 1;
  select f.code,f.name into v_fate_code,v_fate_name
  from public.character_fates cf join public.fates f on f.id=cf.fate_id
  where cf.character_id=v_character and cf.is_active order by cf.created_at limit 1;
  select p.element into v_element from public.character_combat_profiles_bcombat01 p where p.character_id=v_character;
  v_mutation:=public.v12_mutation_element(v_root_id,v_element,v_fate_code);
  return jsonb_build_object(
    'character_id',v_character,'spirit_root_id',v_root_id,'spirit_root_name',coalesce(v_root_name,'未知灵根'),
    'fate_code',coalesce(v_fate_code,''),'fate_name',coalesce(v_fate_name,'未知命格'),
    'element',coalesce(v_element,''),'element_name',public.bcombat01_element_label(v_element),
    'mutation_element',coalesce(v_mutation,''),'mutation_name',public.v12_mutation_label(v_mutation),
    'mutation_display',case when v_mutation is not null then '变异灵根（'||public.v12_mutation_label(v_mutation)||'）' else '' end,
    'spirit_root_display',case when v_mutation is not null then '变异灵根（'||public.v12_mutation_label(v_mutation)||'）' else coalesce(v_root_name,'未知灵根') end
  );
end
$$;
revoke all on function public.get_my_birth_result_v12() from public,anon;
grant execute on function public.get_my_birth_result_v12() to authenticated;

-- 双重保险：迁移完成后不允许遗留剑心+变异灵根冲突。
do $$ begin
  if exists(
    select 1 from public.character_spirit_roots csr
    join public.character_fates cf on cf.character_id=csr.character_id and cf.is_active
    join public.fates f on f.id=cf.fate_id and f.code='sword_heart'
    where csr.is_primary and public.v12_is_mutant_root(csr.spirit_root_id)
  ) then raise exception 'V12_TALENT_CONFLICT_REMAINS'; end if;
end $$;

comment on function public.v12_mutation_element(smallint,text,text) is
  'V1.2：变异灵根+金/木/水分别映射雷/风/冰；不修改原五行。';
comment on function public.bcombat01_resolve_hit(jsonb,jsonb,integer,integer,integer) is
  'V1.2：原五行倍率保持不变；天生剑心或风冰雷在最终伤害层互斥增加8%。';
notify pgrst,'reload schema';
commit;
