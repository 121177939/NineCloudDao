-- B-COMBAT01 候选主SQL
-- 战斗四属性、角色五行、战力榜、越阶挑战、修为转移、九霄界闻战报。
-- 仅供A线核验接入；不修改版本号、CACHE27、正式迁移链或既有发布函数。
begin;

-- Preserve the current Sword Heart definition for A-line rollback.
create schema if not exists ncd_b_module_backup;
create table if not exists ncd_b_module_backup.bcombat01_fates (
  code text primary key,
  description text,
  modifiers jsonb,
  trigger_rules jsonb
);
insert into ncd_b_module_backup.bcombat01_fates(code,description,modifiers,trigger_rules)
select code,description,modifiers,trigger_rules
from public.fates
where code='sword_heart'
on conflict(code) do nothing;

-- Sword Heart is a conditional sword-school final-damage bonus, not a four-stat bonus.
update public.fates
set description='修炼速度增加25%。装备剑类武器并使用剑系功法时，剑系最终伤害提高8%。',
    modifiers=(coalesce(modifiers,'{}'::jsonb)-'combat_attribute_bonus'-'combat_effect_enabled')
      || jsonb_build_object('sword_final_damage_bonus',0.08,'sword_combat_effect_enabled',true),
    trigger_rules=coalesce(trigger_rules,'{}'::jsonb)
where code='sword_heart';

create table if not exists public.combat_realm_stats_bcombat01 (
  major_order smallint not null,
  minor_level smallint not null,
  realm_label text not null,
  realm_coefficient numeric(6,2) not null check(realm_coefficient > 0),
  dao_attack integer not null check(dao_attack > 0),
  dao_defense integer not null check(dao_defense >= 0),
  vitality integer not null check(vitality > 0),
  agility integer not null check(agility > 0),
  primary key(major_order,minor_level)
);
alter table public.combat_realm_stats_bcombat01 enable row level security;
revoke all on table public.combat_realm_stats_bcombat01 from public,anon,authenticated;

insert into public.combat_realm_stats_bcombat01(
  major_order,minor_level,realm_label,realm_coefficient,
  dao_attack,dao_defense,vitality,agility
) values
  (0,1,'凡人',1.00,75,45,400,90),
  (1,1,'练气1层',1.10,85,50,450,95),
  (1,2,'练气2层',1.20,95,55,500,101),
  (1,3,'练气3层',1.30,105,60,550,107),
  (1,4,'练气4层',1.40,115,65,600,113),
  (1,5,'练气5层',1.50,125,70,650,119),
  (1,6,'练气6层',1.60,135,75,700,125),
  (1,7,'练气7层',1.70,145,80,750,131),
  (1,8,'练气8层',1.80,155,85,800,137),
  (1,9,'练气9层',1.90,165,90,850,143),
  (1,10,'练气10层',2.00,175,95,900,149),
  (2,1,'筑基初期',2.00,200,115,1100,160),
  (2,2,'筑基中期',2.25,220,125,1200,168),
  (2,3,'筑基后期',2.50,240,140,1320,176),
  (2,4,'筑基圆满',2.75,260,150,1440,185),
  (3,1,'金丹初期',3.00,300,180,1800,200),
  (3,2,'金丹中期',3.25,330,200,2000,210),
  (3,3,'金丹后期',3.50,360,220,2200,220),
  (3,4,'金丹圆满',3.75,390,240,2400,230),
  (4,1,'元婴初期',4.00,450,290,3000,250),
  (4,2,'元婴中期',4.25,495,320,3300,263),
  (4,3,'元婴后期',4.50,540,350,3600,276),
  (4,4,'元婴圆满',4.75,585,380,3900,289),
  (5,1,'化神初期',5.00,675,455,4900,312),
  (5,2,'化神中期',5.25,745,500,5400,328),
  (5,3,'化神后期',5.50,810,545,5900,343),
  (5,4,'化神圆满',5.75,880,590,6350,359),
  (6,1,'炼虚初期',6.00,1010,710,7950,388),
  (6,2,'炼虚中期',6.25,1110,780,8750,407),
  (6,3,'炼虚后期',6.50,1210,850,9550,427),
  (6,4,'炼虚圆满',6.75,1315,925,10350,446),
  (7,1,'合体初期',7.00,1510,1110,12950,482),
  (7,2,'合体中期',7.25,1660,1220,14250,506),
  (7,3,'合体后期',7.50,1810,1330,15550,530),
  (7,4,'合体圆满',7.75,1965,1445,16850,554),
  (8,1,'大乘初期',8.00,2260,1735,21050,598),
  (8,2,'大乘中期',8.25,2485,1910,23150,628),
  (8,3,'大乘后期',8.50,2710,2080,25250,658),
  (8,4,'大乘圆满',8.75,2940,2255,27350,688),
  (9,1,'渡劫初期',9.00,3380,2705,34200,743),
  (9,2,'渡劫中期',9.25,3720,2975,37600,780),
  (9,3,'渡劫后期',9.50,4055,3245,41050,817),
  (9,4,'渡劫圆满',9.75,4395,3515,44450,854),
  (10,1,'飞升',10.00,5055,4220,55550,922)
on conflict(major_order,minor_level) do update set
  realm_label=excluded.realm_label,
  realm_coefficient=excluded.realm_coefficient,
  dao_attack=excluded.dao_attack,
  dao_defense=excluded.dao_defense,
  vitality=excluded.vitality,
  agility=excluded.agility;

create table if not exists public.character_combat_profiles_bcombat01 (
  character_id uuid primary key references public.player_characters(id) on delete cascade,
  element text not null check(element in('metal','wood','water','fire','earth')),
  assigned_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);
alter table public.character_combat_profiles_bcombat01 enable row level security;
revoke all on table public.character_combat_profiles_bcombat01 from public,anon,authenticated;
create index if not exists idx_character_combat_profiles_bcombat01_element
  on public.character_combat_profiles_bcombat01(element);

create table if not exists public.character_combat_loadouts_bcombat01 (
  character_id uuid primary key references public.player_characters(id) on delete cascade,
  weapon_name text,
  weapon_kind text,
  weapon_attack integer not null default 0 check(weapon_attack >= 0),
  weapon_requirement_coefficient numeric(6,2) not null default 1 check(weapon_requirement_coefficient > 0),
  armor_name text,
  armor_defense integer not null default 0 check(armor_defense >= 0),
  armor_vitality integer not null default 0 check(armor_vitality >= 0),
  armor_agility integer not null default 0 check(armor_agility >= 0),
  armor_requirement_coefficient numeric(6,2) not null default 1 check(armor_requirement_coefficient > 0),
  metadata jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default clock_timestamp()
);
alter table public.character_combat_loadouts_bcombat01 enable row level security;
revoke all on table public.character_combat_loadouts_bcombat01 from public,anon,authenticated;

create table if not exists public.battle_challenge_settings_bcombat01 (
  singleton_id smallint primary key default 1 check(singleton_id=1),
  enabled boolean not null default true,
  active_challenge_daily_limit integer not null default 5 check(active_challenge_daily_limit between 1 and 100),
  target_challenged_daily_limit integer not null default 10 check(target_challenged_daily_limit between 1 and 100),
  pair_transfer_daily_limit integer not null default 1 check(pair_transfer_daily_limit between 1 and 10),
  protection_minutes integer not null default 30 check(protection_minutes between 0 and 1440),
  cultivation_loss_rate numeric(7,6) not null default 0.01 check(cultivation_loss_rate > 0 and cultivation_loss_rate <= 0.10),
  sword_heart_final_damage_bonus numeric(7,6) not null default 0.08 check(sword_heart_final_damage_bonus >= 0 and sword_heart_final_damage_bonus <= 0.20),
  day_timezone text not null default 'Asia/Shanghai',
  updated_at timestamptz not null default clock_timestamp()
);
alter table public.battle_challenge_settings_bcombat01 enable row level security;
revoke all on table public.battle_challenge_settings_bcombat01 from public,anon,authenticated;
insert into public.battle_challenge_settings_bcombat01(singleton_id)
values(1) on conflict(singleton_id) do nothing;

create table if not exists public.character_battle_cultivation_escrow_bcombat01 (
  character_id uuid primary key references public.player_characters(id) on delete cascade,
  pending_cultivation bigint not null default 0 check(pending_cultivation >= 0),
  updated_at timestamptz not null default clock_timestamp()
);
alter table public.character_battle_cultivation_escrow_bcombat01 enable row level security;
revoke all on table public.character_battle_cultivation_escrow_bcombat01 from public,anon,authenticated;

create table if not exists public.battle_challenges_bcombat01 (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null unique,
  world_id uuid not null,
  day_key date not null,
  challenger_character_id uuid not null references public.player_characters(id),
  target_character_id uuid not null references public.player_characters(id),
  winner_character_id uuid not null references public.player_characters(id),
  loser_character_id uuid not null references public.player_characters(id),
  challenger_power bigint not null,
  target_power bigint not null,
  challenger_snapshot jsonb not null,
  target_snapshot jsonb not null,
  battle_actions jsonb not null default '[]'::jsonb,
  battle_rounds integer not null default 0,
  requested_cultivation_transfer bigint not null default 0,
  cultivation_granted_now bigint not null default 0,
  cultivation_escrowed bigint not null default 0,
  winner_cultivation_before bigint not null default 0,
  winner_cultivation_after bigint not null default 0,
  loser_cultivation_before bigint not null default 0,
  loser_cultivation_after bigint not null default 0,
  world_event_id uuid,
  result jsonb not null,
  status text not null default 'settled' check(status in('settled','void')),
  started_at timestamptz not null default clock_timestamp(),
  completed_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  check(challenger_character_id <> target_character_id)
);
alter table public.battle_challenges_bcombat01 enable row level security;
revoke all on table public.battle_challenges_bcombat01 from public,anon,authenticated;
create index if not exists idx_battle_challenges_bcombat01_challenger_day
  on public.battle_challenges_bcombat01(challenger_character_id,day_key,created_at desc)
  where status='settled';
create index if not exists idx_battle_challenges_bcombat01_target_day
  on public.battle_challenges_bcombat01(target_character_id,day_key,created_at desc)
  where status='settled';
create index if not exists idx_battle_challenges_bcombat01_target_loss
  on public.battle_challenges_bcombat01(target_character_id,loser_character_id,completed_at desc)
  where status='settled';

create or replace function public.bcombat01_element_label(p_element text)
returns text language sql immutable strict set search_path=public,pg_temp as $$
  select case p_element when 'metal' then '金' when 'wood' then '木' when 'water' then '水'
    when 'fire' then '火' when 'earth' then '土' else '无' end
$$;
revoke all on function public.bcombat01_element_label(text) from public,anon,authenticated;

create or replace function public.bcombat01_element_overcomes(p_attacker text,p_defender text)
returns boolean language sql immutable set search_path=public,pg_temp as $$
  select (p_attacker,p_defender) in (
    ('metal','wood'),('wood','earth'),('earth','water'),('water','fire'),('fire','metal')
  )
$$;
revoke all on function public.bcombat01_element_overcomes(text,text) from public,anon,authenticated;

create or replace function public.bcombat01_element_multiplier(
  p_attacker_element text,p_defender_element text,
  p_attacker_major integer,p_attacker_minor integer,
  p_defender_major integer,p_defender_minor integer
)
returns numeric language plpgsql immutable set search_path=public,pg_temp as $$
declare v_strong numeric:=1;v_weak numeric:=1;v_major_gap integer;v_minor_gap integer;
begin
  if p_attacker_element is null or p_defender_element is null or p_attacker_element=p_defender_element then return 1;end if;
  v_major_gap:=abs(coalesce(p_attacker_major,0)-coalesce(p_defender_major,0));
  v_minor_gap:=abs(coalesce(p_attacker_minor,0)-coalesce(p_defender_minor,0));
  if v_major_gap>=2 then return 1;end if;
  if v_major_gap=1 then v_strong:=1.05;v_weak:=0.95;
  elsif v_minor_gap<=1 then v_strong:=1.15;v_weak:=0.85;
  else v_strong:=1.05;v_weak:=0.95;end if;
  if public.bcombat01_element_overcomes(p_attacker_element,p_defender_element) then return v_strong;end if;
  if public.bcombat01_element_overcomes(p_defender_element,p_attacker_element) then return v_weak;end if;
  return 1;
end$$;
revoke all on function public.bcombat01_element_multiplier(text,text,integer,integer,integer,integer) from public,anon,authenticated;

create or replace function public.bcombat01_assign_element(p_character_id uuid)
returns text language plpgsql volatile security definer set search_path=pg_catalog,public,pg_temp as $$
declare v_element text;v_min_count bigint;
begin
  if p_character_id is null then raise exception 'INVALID_CHARACTER';end if;
  -- Serialize element assignment so concurrent registrations remain as even as possible.
  perform pg_advisory_xact_lock(hashtext('B-COMBAT01_ELEMENT_ASSIGN'));
  select p.element into v_element from public.character_combat_profiles_bcombat01 p where p.character_id=p_character_id;
  if v_element is not null then return v_element;end if;
  with elements(element) as (values('metal'::text),('wood'),('water'),('fire'),('earth')),
  counts as (
    select e.element,count(p.character_id)::bigint as n
    from elements e left join public.character_combat_profiles_bcombat01 p on p.element=e.element group by e.element
  )
  select min(n) into v_min_count from counts;
  with elements(element) as (values('metal'::text),('wood'),('water'),('fire'),('earth')),
  counts as (
    select e.element,count(p.character_id)::bigint as n
    from elements e left join public.character_combat_profiles_bcombat01 p on p.element=e.element group by e.element
  )
  select c.element into v_element from counts c where c.n=v_min_count order by random() limit 1;
  insert into public.character_combat_profiles_bcombat01(character_id,element)
  values(p_character_id,v_element)
  on conflict(character_id) do update set updated_at=clock_timestamp()
  returning element into v_element;
  return v_element;
end$$;
revoke all on function public.bcombat01_assign_element(uuid) from public,anon,authenticated;

create or replace function public.bcombat01_character_insert_trigger()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
begin perform public.bcombat01_assign_element(new.id);return new;end$$;
revoke all on function public.bcombat01_character_insert_trigger() from public,anon,authenticated;
drop trigger if exists trg_bcombat01_assign_element on public.player_characters;
create trigger trg_bcombat01_assign_element after insert on public.player_characters
for each row execute function public.bcombat01_character_insert_trigger();

-- Backfill every existing character. Each row uses the same least-populated random
-- allocator as future registrations, so reruns and partially populated databases stay balanced.
do $$
declare v_character_id uuid;
begin
  for v_character_id in
    select pc.id
    from public.player_characters pc
    left join public.character_combat_profiles_bcombat01 p on p.character_id=pc.id
    where p.character_id is null
    order by random(),pc.id
  loop
    perform public.bcombat01_assign_element(v_character_id);
  end loop;
end$$;

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

create or replace function public.bcombat01_resolve_hit(
  p_attacker jsonb,p_defender jsonb,p_defender_hp integer,p_round integer,p_sequence integer
)
returns jsonb language plpgsql volatile security definer set search_path=pg_catalog,public,pg_temp as $$
declare v_element numeric;v_base_reduction numeric;v_total_reduction numeric;v_sword numeric:=1;
  v_damage integer;v_hp_after integer;v_settings public.battle_challenge_settings_bcombat01%rowtype;
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
  end if;
  v_damage:=greatest(1,floor((p_attacker->>'attack')::numeric
    *coalesce((p_attacker->>'attack_skill_multiplier')::numeric,1)
    *v_element*v_sword*(1-v_total_reduction)))::integer;
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
    'damage',v_damage,'hp_before',p_defender_hp,'hp_after',v_hp_after,
    'max_hp',(p_defender->>'vitality')::integer,
    'low_health',v_hp_after>0 and v_hp_after<=floor((p_defender->>'vitality')::numeric*0.30),
    'defeated',v_hp_after<=0
  );
end$$;
revoke all on function public.bcombat01_resolve_hit(jsonb,jsonb,integer,integer,integer) from public,anon,authenticated;

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
  ),page as (select * from ranked where rank>p_offset and rank<=p_offset+p_limit order by rank)
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
    'power',(snap->>'power')::bigint,'dao_attack',(snap->>'attack')::integer,
    'dao_defense',(snap->>'defense')::integer,'vitality',(snap->>'vitality')::integer,
    'agility',(snap->>'agility')::integer,'is_self',user_id=v_user_id,
    'can_challenge',id<>v_self_id and (snap->>'power')::bigint>v_self_power
  ) order by rank),'[]'::jsonb) into v_entries from page;
  return jsonb_build_object('status','ok','board_type','battle',
    'ranking_rule','四项永久面板战力由高到低；五行与条件命格不计入常驻战力',
    'entries',v_entries,'total_count',v_total,'offset',p_offset,'limit',p_limit,
    'has_more',p_offset+jsonb_array_length(v_entries)<v_total,'self_power',v_self_power,'self',v_self);
end$$;
revoke all on function public.get_battle_power_ranking_bcombat01(integer,integer) from public,anon,authenticated;
grant execute on function public.get_battle_power_ranking_bcombat01(integer,integer) to authenticated;

create or replace function public.get_battle_challenge_preview_bcombat01(p_target_character_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_self_id uuid;v_self jsonb;v_target jsonb;
  v_settings public.battle_challenge_settings_bcombat01%rowtype;v_day date;
  v_active_count integer;v_target_count integer;v_pair_count integer;v_protected_until timestamptz;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED';end if;
  select * into v_settings from public.battle_challenge_settings_bcombat01 where singleton_id=1;
  if not coalesce(v_settings.enabled,false) then raise exception 'BATTLE_CHALLENGE_DISABLED';end if;
  select pc.id into v_self_id from public.player_characters pc where pc.user_id=v_user_id
    and pc.status in('active','secluded','missing') order by pc.created_at desc limit 1;
  if v_self_id is null then raise exception 'NO_ACTIVE_CHARACTER';end if;
  if p_target_character_id is null or p_target_character_id=v_self_id then raise exception 'INVALID_CHALLENGE_TARGET';end if;
  v_self:=public.bcombat01_character_snapshot(v_self_id);v_target:=public.bcombat01_character_snapshot(p_target_character_id);
  if v_target is null then raise exception 'CHALLENGE_TARGET_NOT_FOUND';end if;
  if v_self->>'world_id'<>v_target->>'world_id' then raise exception 'CHALLENGE_WORLD_MISMATCH';end if;
  if (v_target->>'power')::bigint<=(v_self->>'power')::bigint then raise exception 'TARGET_POWER_NOT_HIGHER';end if;
  v_day:=(now() at time zone v_settings.day_timezone)::date;
  select count(*)::integer into v_active_count from public.battle_challenges_bcombat01
    where challenger_character_id=v_self_id and day_key=v_day and status='settled';
  select count(*)::integer into v_target_count from public.battle_challenges_bcombat01
    where target_character_id=p_target_character_id and day_key=v_day and status='settled';
  select count(*)::integer into v_pair_count from public.battle_challenges_bcombat01
    where day_key=v_day and status='settled' and
      ((challenger_character_id=v_self_id and target_character_id=p_target_character_id)
       or(challenger_character_id=p_target_character_id and target_character_id=v_self_id));
  select max(completed_at)+make_interval(mins=>v_settings.protection_minutes) into v_protected_until
    from public.battle_challenges_bcombat01
    where target_character_id=p_target_character_id and loser_character_id=p_target_character_id
      and status='settled' and completed_at>now()-make_interval(mins=>v_settings.protection_minutes);
  return jsonb_build_object('status','ok','challenger',v_self,'target',v_target,
    'loss_rate',v_settings.cultivation_loss_rate,
    'challenger_potential_loss',floor((v_self->>'cultivation')::numeric*v_settings.cultivation_loss_rate)::bigint,
    'target_potential_loss',floor((v_target->>'cultivation')::numeric*v_settings.cultivation_loss_rate)::bigint,
    'active_challenges_used',v_active_count,'active_challenges_limit',v_settings.active_challenge_daily_limit,
    'target_challenged_count',v_target_count,'target_challenged_limit',v_settings.target_challenged_daily_limit,
    'pair_challenges_used',v_pair_count,'pair_challenges_limit',v_settings.pair_transfer_daily_limit,
    'protected_until',v_protected_until,
    'can_start',v_active_count<v_settings.active_challenge_daily_limit
      and v_target_count<v_settings.target_challenged_daily_limit
      and v_pair_count<v_settings.pair_transfer_daily_limit
      and (v_protected_until is null or v_protected_until<=now()),
    'blocked_reason',case
      when v_active_count>=v_settings.active_challenge_daily_limit then '今日主动挑战次数已用尽'
      when v_target_count>=v_settings.target_challenged_daily_limit then '对方今日已被有效挑战10次'
      when v_pair_count>=v_settings.pair_transfer_daily_limit then '今日与该对手已产生过修为转移'
      when v_protected_until is not null and v_protected_until>now() then '对方正处于战败保护期'
      else null end,
    'escrow_note','胜者若已触及当前境界修为硬上限，超出部分进入战利修为暂存，不会丢失。');
end$$;
revoke all on function public.get_battle_challenge_preview_bcombat01(uuid) from public,anon,authenticated;
grant execute on function public.get_battle_challenge_preview_bcombat01(uuid) to authenticated;

create or replace function public.claim_battle_cultivation_escrow_bcombat01()
returns jsonb language plpgsql volatile security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_character public.player_characters%rowtype;v_pending bigint;v_cap bigint;v_grant bigint;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED';end if;
  select * into v_character from public.player_characters where user_id=v_user_id
    and status in('active','secluded','missing') order by created_at desc limit 1 for update;
  if v_character.id is null then raise exception 'NO_ACTIVE_CHARACTER';end if;
  insert into public.character_battle_cultivation_escrow_bcombat01(character_id) values(v_character.id)
    on conflict(character_id) do nothing;
  select pending_cultivation into v_pending from public.character_battle_cultivation_escrow_bcombat01
    where character_id=v_character.id for update;
  v_cap:=public.character_cultivation_cap_v1(v_character.realm_stage_id);
  v_grant:=least(v_pending,greatest(0,coalesce(v_cap,9223372036854775807::bigint)-v_character.cultivation));
  if v_grant>0 then
    update public.player_characters set cultivation=cultivation+v_grant,updated_at=clock_timestamp() where id=v_character.id;
    update public.character_battle_cultivation_escrow_bcombat01
      set pending_cultivation=pending_cultivation-v_grant,updated_at=clock_timestamp() where character_id=v_character.id;
  end if;
  return jsonb_build_object('status','ok','granted',v_grant,'pending',v_pending-v_grant,
    'cultivation_after',v_character.cultivation+v_grant);
end$$;
revoke all on function public.claim_battle_cultivation_escrow_bcombat01() from public,anon,authenticated;
grant execute on function public.claim_battle_cultivation_escrow_bcombat01() to authenticated;

create or replace function public.challenge_battle_power_bcombat01(
  p_target_character_id uuid,p_request_id uuid default gen_random_uuid()
)
returns jsonb language plpgsql volatile security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare
  v_user_id uuid:=auth.uid();v_self_id uuid;v_settings public.battle_challenge_settings_bcombat01%rowtype;
  v_existing jsonb;v_challenger_row public.player_characters%rowtype;v_target_row public.player_characters%rowtype;
  v_challenger jsonb;v_target jsonb;v_day date;v_active_count integer;v_target_count integer;v_pair_count integer;
  v_protected_until timestamptz;v_first_challenger boolean;v_round integer:=0;v_sequence integer:=0;
  v_challenger_hp integer;v_target_hp integer;v_hit jsonb;v_actions jsonb:='[]'::jsonb;
  v_winner_id uuid;v_loser_id uuid;v_winner jsonb;v_loser jsonb;
  v_transfer bigint;v_granted bigint;v_escrow bigint;v_cap bigint;v_winner_before bigint;v_loser_before bigint;
  v_winner_after bigint;v_loser_after bigint;v_challenge_id uuid:=gen_random_uuid();v_event_id uuid;v_world_year integer:=1;
  v_title text;v_content text;v_result jsonb;v_winner_is_challenger boolean;v_story_variant integer;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED';end if;
  if p_request_id is null then raise exception 'INVALID_REQUEST_ID';end if;
  perform pg_advisory_xact_lock(hashtext('B-COMBAT01:'||p_request_id::text));
  select result into v_existing from public.battle_challenges_bcombat01
    where request_id=p_request_id and challenger_character_id in(
      select id from public.player_characters where user_id=v_user_id
    );
  if v_existing is not null then return v_existing;end if;
  select * into v_settings from public.battle_challenge_settings_bcombat01 where singleton_id=1;
  if not coalesce(v_settings.enabled,false) then raise exception 'BATTLE_CHALLENGE_DISABLED';end if;
  select pc.id into v_self_id from public.player_characters pc where pc.user_id=v_user_id
    and pc.status in('active','secluded','missing') order by pc.created_at desc limit 1;
  if v_self_id is null then raise exception 'NO_ACTIVE_CHARACTER';end if;
  if p_target_character_id is null or p_target_character_id=v_self_id then raise exception 'INVALID_CHALLENGE_TARGET';end if;
  perform 1 from public.player_characters where id in(v_self_id,p_target_character_id) order by id for update;
  select * into v_challenger_row from public.player_characters where id=v_self_id;
  select * into v_target_row from public.player_characters where id=p_target_character_id;
  if v_target_row.id is null or v_target_row.status not in('active','secluded','missing') then raise exception 'CHALLENGE_TARGET_NOT_FOUND';end if;
  if v_challenger_row.world_id<>v_target_row.world_id then raise exception 'CHALLENGE_WORLD_MISMATCH';end if;
  perform public.bcombat01_assign_element(v_self_id);perform public.bcombat01_assign_element(p_target_character_id);
  v_challenger:=public.bcombat01_character_snapshot(v_self_id);v_target:=public.bcombat01_character_snapshot(p_target_character_id);
  if v_challenger is null or v_target is null then raise exception 'COMBAT_STATS_NOT_CONFIGURED';end if;
  if (v_target->>'power')::bigint<=(v_challenger->>'power')::bigint then raise exception 'TARGET_POWER_NOT_HIGHER';end if;
  v_day:=(clock_timestamp() at time zone v_settings.day_timezone)::date;
  select count(*)::integer into v_active_count from public.battle_challenges_bcombat01
    where challenger_character_id=v_self_id and day_key=v_day and status='settled';
  if v_active_count>=v_settings.active_challenge_daily_limit then raise exception 'ACTIVE_CHALLENGE_DAILY_LIMIT';end if;
  select count(*)::integer into v_target_count from public.battle_challenges_bcombat01
    where target_character_id=p_target_character_id and day_key=v_day and status='settled';
  if v_target_count>=v_settings.target_challenged_daily_limit then raise exception 'TARGET_CHALLENGED_DAILY_LIMIT';end if;
  select count(*)::integer into v_pair_count from public.battle_challenges_bcombat01
    where day_key=v_day and status='settled' and
      ((challenger_character_id=v_self_id and target_character_id=p_target_character_id)
       or(challenger_character_id=p_target_character_id and target_character_id=v_self_id));
  if v_pair_count>=v_settings.pair_transfer_daily_limit then raise exception 'PAIR_CHALLENGE_DAILY_LIMIT';end if;
  select max(completed_at)+make_interval(mins=>v_settings.protection_minutes) into v_protected_until
    from public.battle_challenges_bcombat01
    where target_character_id=p_target_character_id and loser_character_id=p_target_character_id
      and status='settled' and completed_at>clock_timestamp()-make_interval(mins=>v_settings.protection_minutes);
  if v_protected_until is not null and v_protected_until>clock_timestamp() then
    raise exception 'TARGET_IN_CHALLENGE_PROTECTION:%',v_protected_until;
  end if;
  v_challenger_hp:=(v_challenger->>'vitality')::integer;v_target_hp:=(v_target->>'vitality')::integer;
  if (v_challenger->>'agility')::integer=(v_target->>'agility')::integer then
    v_first_challenger:=random()<0.5;
  else v_first_challenger:=(v_challenger->>'agility')::integer>(v_target->>'agility')::integer;end if;
  while v_challenger_hp>0 and v_target_hp>0 and v_round<100 loop
    v_round:=v_round+1;
    if v_first_challenger then
      v_sequence:=v_sequence+1;v_hit:=public.bcombat01_resolve_hit(v_challenger,v_target,v_target_hp,v_round,v_sequence);
      v_target_hp:=(v_hit->>'hp_after')::integer;v_actions:=v_actions||jsonb_build_array(v_hit);
      if v_target_hp<=0 then exit;end if;
      v_sequence:=v_sequence+1;v_hit:=public.bcombat01_resolve_hit(v_target,v_challenger,v_challenger_hp,v_round,v_sequence);
      v_challenger_hp:=(v_hit->>'hp_after')::integer;v_actions:=v_actions||jsonb_build_array(v_hit);
    else
      v_sequence:=v_sequence+1;v_hit:=public.bcombat01_resolve_hit(v_target,v_challenger,v_challenger_hp,v_round,v_sequence);
      v_challenger_hp:=(v_hit->>'hp_after')::integer;v_actions:=v_actions||jsonb_build_array(v_hit);
      if v_challenger_hp<=0 then exit;end if;
      v_sequence:=v_sequence+1;v_hit:=public.bcombat01_resolve_hit(v_challenger,v_target,v_target_hp,v_round,v_sequence);
      v_target_hp:=(v_hit->>'hp_after')::integer;v_actions:=v_actions||jsonb_build_array(v_hit);
    end if;
  end loop;
  if v_challenger_hp<=0 then
    v_winner_id:=p_target_character_id;v_loser_id:=v_self_id;v_winner:=v_target;v_loser:=v_challenger;v_winner_is_challenger:=false;
  else
    v_winner_id:=v_self_id;v_loser_id:=p_target_character_id;v_winner:=v_challenger;v_loser:=v_target;v_winner_is_challenger:=true;
  end if;
  select cultivation into v_winner_before from public.player_characters where id=v_winner_id;
  select cultivation into v_loser_before from public.player_characters where id=v_loser_id;
  v_transfer:=greatest(0,floor(v_loser_before::numeric*v_settings.cultivation_loss_rate)::bigint);
  v_cap:=public.character_cultivation_cap_v1((select realm_stage_id from public.player_characters where id=v_winner_id));
  v_granted:=least(v_transfer,greatest(0,coalesce(v_cap,9223372036854775807::bigint)-v_winner_before));
  v_escrow:=v_transfer-v_granted;
  update public.player_characters set cultivation=greatest(0,cultivation-v_transfer),updated_at=clock_timestamp() where id=v_loser_id;
  update public.player_characters set cultivation=cultivation+v_granted,updated_at=clock_timestamp() where id=v_winner_id;
  if v_escrow>0 then
    insert into public.character_battle_cultivation_escrow_bcombat01(character_id,pending_cultivation)
    values(v_winner_id,v_escrow)
    on conflict(character_id) do update set
      pending_cultivation=public.character_battle_cultivation_escrow_bcombat01.pending_cultivation+excluded.pending_cultivation,
      updated_at=clock_timestamp();
  end if;
  v_winner_after:=v_winner_before+v_granted;v_loser_after:=greatest(0,v_loser_before-v_transfer);
  select coalesce(gw.current_year,1) into v_world_year from public.game_worlds gw where gw.id=v_challenger_row.world_id;
  v_story_variant:=1+floor(random()*4)::integer;
  if coalesce((v_winner->>'is_unarmed')::boolean,false) then
    v_title:='赤手破敌';v_content:=format('%s赤手空拳击败%s，鏖战%s回合后夺得修为%s。',
      v_winner->>'name',v_loser->>'name',v_round,v_transfer);
  elsif coalesce((v_winner->>'is_naked')::boolean,false) then
    v_title:='身无寸甲';v_content:=format('%s赤裸迎战，仍于天命榜挑战中击败%s，获得修为%s。',
      v_winner->>'name',v_loser->>'name',v_transfer);
  elsif v_winner_is_challenger then
    v_title:=case v_story_variant when 1 then '以弱胜强' when 2 then '天命争锋' when 3 then '越榜一战' else '逆势夺修' end;
    v_content:=format('战力%s的%s挑战战力%s的%s，以%s配合《%s》鏖战%s回合后取胜，夺得修为%s。',
      v_challenger->>'power',v_challenger->>'name',v_target->>'power',v_target->>'name',
      v_challenger->>'weapon_name',v_challenger->>'attack_technique_name',v_round,v_transfer);
  else
    v_title:=case v_story_variant when 1 then '守榜成功' when 2 then '强者镇榜' when 3 then '一线惜败' else '天命未改' end;
    v_content:=format('%s向%s发起越榜挑战，双方鏖战%s回合，最终%s守住战力榜并获得修为%s。',
      v_challenger->>'name',v_target->>'name',v_round,v_target->>'name',v_transfer);
  end if;
  v_result:=jsonb_build_object('status','settled','battle_id',v_challenge_id,
    'winner_id',v_winner_id,'winner_name',v_winner->>'name','loser_id',v_loser_id,'loser_name',v_loser->>'name',
    'challenger_won',v_winner_is_challenger,'battle_rounds',v_round,
    'first_actor_id',case when v_first_challenger then v_self_id else p_target_character_id end,
    'challenger',v_challenger,'target',v_target,'actions',v_actions,
    'challenger_hp_after',greatest(0,v_challenger_hp),'target_hp_after',greatest(0,v_target_hp),
    'cultivation_transferred',v_transfer,'cultivation_granted_now',v_granted,'cultivation_escrowed',v_escrow,
    'winner_cultivation_after',v_winner_after,'loser_cultivation_after',v_loser_after,
    'self_cultivation_after',case when v_self_id=v_winner_id then v_winner_after else v_loser_after end,
    'protection_minutes',case when v_loser_id=p_target_character_id then v_settings.protection_minutes else 0 end,
    'active_challenges_remaining',greatest(0,v_settings.active_challenge_daily_limit-v_active_count-1));
  insert into public.battle_challenges_bcombat01(
    id,request_id,world_id,day_key,challenger_character_id,target_character_id,winner_character_id,loser_character_id,
    challenger_power,target_power,challenger_snapshot,target_snapshot,battle_actions,battle_rounds,
    requested_cultivation_transfer,cultivation_granted_now,cultivation_escrowed,
    winner_cultivation_before,winner_cultivation_after,loser_cultivation_before,loser_cultivation_after,result
  ) values(
    v_challenge_id,p_request_id,v_challenger_row.world_id,v_day,v_self_id,p_target_character_id,v_winner_id,v_loser_id,
    (v_challenger->>'power')::bigint,(v_target->>'power')::bigint,v_challenger,v_target,v_actions,v_round,
    v_transfer,v_granted,v_escrow,v_winner_before,v_winner_after,v_loser_before,v_loser_after,v_result);
  v_event_id:=public.world_event_publish_v0140(
    v_challenger_row.world_id,v_world_year,'battle_challenge',case when v_winner_is_challenger then 3 else 2 end,
    v_winner_id,v_winner->>'name',v_title,v_content,'battle_challenges_bcombat01',v_challenge_id::text,
    jsonb_build_object('winner_id',v_winner_id,'loser_id',v_loser_id,'rounds',v_round,
      'cultivation_transferred',v_transfer,'challenger_power',(v_challenger->>'power')::bigint,
      'target_power',(v_target->>'power')::bigint),false,null);
  if v_event_id is not null then
    update public.battle_challenges_bcombat01 set world_event_id=v_event_id,
      result=jsonb_set(result,'{world_event_id}',to_jsonb(v_event_id::text),true)
    where id=v_challenge_id returning result into v_result;
  end if;
  return v_result;
end$$;
revoke all on function public.challenge_battle_power_bcombat01(uuid,uuid) from public,anon,authenticated;
grant execute on function public.challenge_battle_power_bcombat01(uuid,uuid) to authenticated;

notify pgrst,'reload schema';
commit;
