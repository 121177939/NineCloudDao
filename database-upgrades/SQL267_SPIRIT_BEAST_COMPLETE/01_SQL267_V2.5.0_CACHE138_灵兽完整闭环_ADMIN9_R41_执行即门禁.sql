-- 九霄问道 SQL267 · V2.5.0 CACHE138 · 灵兽完整闭环 · ADMIN9 R41
-- 目标：一次完成捕捉/兽卵/养成/突破/三段进化/性格/技能/血脉传承/放归回收/洞府兽苑/游历/秘境/BOSS/PVP/战斗接入/图鉴/排行/天墟材料交易/GM/TTL。
-- 数据库原则：不写永久喂养日志、不复制战斗大JSON、不建立排行快照；只保存紧凑状态与短期幂等账本。
-- 前置：SQL255 天墟库存、SQL262 九霄游历、SQL254 战斗三系、SQL245 删档框架；建议先执行 SQL266 R1/R2 洗灵热修。

begin;

DO $pre$
BEGIN
  IF to_regclass('public.player_characters') IS NULL THEN RAISE EXCEPTION 'SQL267_PRECHECK_PLAYER_CHARACTERS_MISSING'; END IF;
  IF to_regclass('public.item_definitions') IS NULL OR to_regclass('public.character_inventory') IS NULL THEN RAISE EXCEPTION 'SQL267_PRECHECK_INVENTORY_MISSING'; END IF;
  IF to_regprocedure('public.tianxu_active_character_v255()') IS NULL OR to_regprocedure('public.tianxu_inventory_adjust_v255(uuid,text,bigint)') IS NULL THEN RAISE EXCEPTION 'SQL267_PRECHECK_TIANXU_HELPERS_MISSING'; END IF;
  IF to_regprocedure('public.exploration_choose_v262(uuid,text)') IS NULL THEN RAISE EXCEPTION 'SQL267_PRECHECK_EXPLORATION_MISSING'; END IF;
  IF to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)') IS NULL OR to_regprocedure('public.bcombat01_resolve_hit_v243(jsonb,jsonb,integer,integer,integer,numeric)') IS NULL THEN RAISE EXCEPTION 'SQL267_PRECHECK_BCOMBAT_MISSING'; END IF;
  IF to_regprocedure('public.get_my_battle_snapshot_v1()') IS NULL THEN RAISE EXCEPTION 'SQL267_PRECHECK_BATTLE_SNAPSHOT_MISSING'; END IF;
  IF to_regprocedure('public.claim_secret_realm_rewards_bsecretrealm01(uuid)') IS NULL THEN RAISE EXCEPTION 'SQL267_PRECHECK_SECRET_REALM_MISSING'; END IF;
  IF to_regprocedure('public.set_world_boss_member_ready_bwboss01(boolean,text,uuid)') IS NULL OR to_regprocedure('public.start_world_boss_run_bwboss01(uuid)') IS NULL OR to_regprocedure('public.bwboss01_active_party(uuid)') IS NULL THEN RAISE EXCEPTION 'SQL267_PRECHECK_WORLD_BOSS_MISSING'; END IF;
  IF to_regclass('public.world_boss_party_members_bwboss01') IS NULL OR to_regclass('public.world_boss_runs_bwboss01') IS NULL OR to_regclass('public.world_boss_contributions_bwboss01') IS NULL THEN RAISE EXCEPTION 'SQL267_PRECHECK_WORLD_BOSS_TABLES_MISSING'; END IF;
  IF to_regprocedure('public.v210_admin_guard()') IS NULL THEN RAISE EXCEPTION 'SQL267_PRECHECK_ADMIN_GUARD_MISSING'; END IF;
END $pre$;

create table if not exists public.spirit_beast_settings_v267(
  singleton_id smallint primary key default 1 check(singleton_id=1),
  enabled boolean not null default true,
  capture_enabled boolean not null default true,
  combat_enabled boolean not null default true,
  daily_supply_food integer not null default 5 check(daily_supply_food between 0 and 100),
  daily_supply_talisman integer not null default 1 check(daily_supply_talisman between 0 and 20),
  base_capacity integer not null default 10 check(base_capacity between 1 and 100),
  capacity_per_stable_level integer not null default 5 check(capacity_per_stable_level between 0 and 50),
  max_stable_level integer not null default 5 check(max_stable_level between 1 and 10),
  feed_exp_per_food integer not null default 120 check(feed_exp_per_food between 1 and 100000),
  max_feed_per_call integer not null default 50 check(max_feed_per_call between 1 and 999),
  exploration_encounter_rate numeric(8,6) not null default .35 check(exploration_encounter_rate between 0 and 1),
  secret_egg_rate numeric(8,6) not null default .08 check(secret_egg_rate between 0 and 1),
  boss_egg_rate numeric(8,6) not null default .12 check(boss_egg_rate between 0 and 1),
  boss_mythic_egg_rate numeric(8,6) not null default .01 check(boss_mythic_egg_rate between 0 and 1),
  encounter_expiry_minutes integer not null default 120 check(encounter_expiry_minutes between 10 and 1440),
  max_capture_attempts integer not null default 3 check(max_capture_attempts between 1 and 20),
  pity_bonus_per_fail numeric(8,6) not null default .05 check(pity_bonus_per_fail between 0 and .50),
  pity_max_bonus numeric(8,6) not null default .30 check(pity_max_bonus between 0 and .90),
  combat_stat_cap numeric(8,6) not null default .15 check(combat_stat_cap between 0 and .50),
  request_ttl_days integer not null default 14 check(request_ttl_days between 1 and 365),
  encounter_ttl_days integer not null default 7 check(encounter_ttl_days between 1 and 365),
  updated_at timestamptz not null default clock_timestamp()
);
insert into public.spirit_beast_settings_v267(singleton_id) values(1) on conflict(singleton_id) do nothing;

create table if not exists public.spirit_beast_skills_v267(
  skill_code text primary key,
  name text not null,
  category text not null check(category in('combat','utility','aux')),
  effect_kind text not null check(effect_kind in('attack','guard','utility')),
  proc_chance numeric(8,6) not null default 0 check(proc_chance between 0 and 1),
  proc_power numeric(8,6) not null default 0 check(proc_power between 0 and 2),
  description text not null,
  enabled boolean not null default true
);

create table if not exists public.spirit_beast_personalities_v267(
  personality_code text primary key,
  name text not null,
  description text not null,
  attack_mult numeric(8,6) not null default 1,
  defense_mult numeric(8,6) not null default 1,
  vitality_mult numeric(8,6) not null default 1,
  agility_mult numeric(8,6) not null default 1,
  intimacy_mult numeric(8,6) not null default 1,
  growth_mult numeric(8,6) not null default 1,
  enabled boolean not null default true
);

create table if not exists public.spirit_beast_species_v267(
  species_code text primary key,
  lineage_code text not null,
  name text not null,
  element text not null check(element in('fire','thunder','wood','water','metal','wind','ice','earth')),
  rarity text not null check(rarity in('common','rare','epic','legendary')),
  evolution_stage integer not null check(evolution_stage between 1 and 3),
  description text not null,
  innate_skill_code text not null references public.spirit_beast_skills_v267(skill_code),
  native_region_code text not null,
  attack_pct numeric(8,6) not null default 0,
  defense_pct numeric(8,6) not null default 0,
  vitality_pct numeric(8,6) not null default 0,
  agility_pct numeric(8,6) not null default 0,
  base_capture_chance numeric(8,6) not null default 0 check(base_capture_chance between 0 and 1),
  rarity_score integer not null default 1 check(rarity_score between 1 and 100),
  next_species_code text,
  enabled boolean not null default true
);

create table if not exists public.spirit_beast_evolutions_v267(
  from_species_code text primary key references public.spirit_beast_species_v267(species_code),
  to_species_code text not null references public.spirit_beast_species_v267(species_code),
  min_owner_realm_order integer not null check(min_owner_realm_order between 1 and 9),
  min_level integer not null check(min_level between 1 and 90),
  min_bloodline integer not null check(min_bloodline between 1 and 100),
  min_intimacy integer not null check(min_intimacy between 0 and 100),
  soul_cost integer not null check(soul_cost>=0),
  essence_item_code text not null,
  essence_cost integer not null check(essence_cost>=0),
  spirit_stone_cost bigint not null check(spirit_stone_cost>=0),
  enabled boolean not null default true
);

create table if not exists public.spirit_beast_region_pool_v267(
  region_code text not null,
  species_code text not null references public.spirit_beast_species_v267(species_code),
  weight integer not null default 100 check(weight between 1 and 10000),
  enabled boolean not null default true,
  primary key(region_code,species_code)
);

create table if not exists public.spirit_beast_egg_map_v267(
  item_code text primary key,
  species_code text not null references public.spirit_beast_species_v267(species_code),
  min_bloodline integer not null check(min_bloodline between 1 and 100),
  max_bloodline integer not null check(max_bloodline between 1 and 100 and max_bloodline>=min_bloodline),
  rarity text not null,
  enabled boolean not null default true
);

create table if not exists public.character_spirit_beasts_v267(
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.player_characters(id) on delete cascade,
  species_code text not null references public.spirit_beast_species_v267(species_code),
  nickname text,
  level integer not null default 1 check(level between 1 and 90),
  exp bigint not null default 0 check(exp>=0),
  beast_realm_order integer not null default 1 check(beast_realm_order between 1 and 9),
  bloodline integer not null check(bloodline between 1 and 100),
  personality_code text not null references public.spirit_beast_personalities_v267(personality_code),
  intimacy integer not null default 0 check(intimacy between 0 and 100),
  skill_level integer not null default 1 check(skill_level between 1 and 10),
  aux_skill_code text references public.spirit_beast_skills_v267(skill_code),
  aux_skill_level integer not null default 0 check(aux_skill_level between 0 and 10),
  locked boolean not null default false,
  source_type text not null default 'unknown',
  source_ref text,
  last_interact_day date,
  obtained_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);
create index if not exists character_spirit_beasts_owner_v267 on public.character_spirit_beasts_v267(character_id,updated_at desc);

create table if not exists public.character_spirit_beast_state_v267(
  character_id uuid primary key references public.player_characters(id) on delete cascade,
  active_beast_id uuid references public.character_spirit_beasts_v267(id) on delete set null,
  stable_level integer not null default 1 check(stable_level between 1 and 10),
  capture_pity jsonb not null default '{}'::jsonb,
  last_supply_day date,
  pvp_exp_day date,
  pvp_exp_count integer not null default 0 check(pvp_exp_count>=0),
  codex_claim_mask integer not null default 0 check(codex_claim_mask between 0 and 31),
  updated_at timestamptz not null default clock_timestamp()
);

create table if not exists public.character_spirit_beast_codex_v267(
  character_id uuid not null references public.player_characters(id) on delete cascade,
  species_code text not null references public.spirit_beast_species_v267(species_code),
  first_obtained_at timestamptz not null default clock_timestamp(),
  last_obtained_at timestamptz not null default clock_timestamp(),
  highest_bloodline integer not null default 1,
  highest_level integer not null default 1,
  times_obtained integer not null default 1,
  primary key(character_id,species_code)
);

create table if not exists public.spirit_beast_encounters_v267(
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.player_characters(id) on delete cascade,
  species_code text not null references public.spirit_beast_species_v267(species_code),
  region_code text,
  source_type text not null,
  source_ref text,
  bloodline integer not null check(bloodline between 1 and 100),
  status text not null default 'pending' check(status in('pending','captured','fled','expired')),
  attempts integer not null default 0 check(attempts>=0),
  base_chance numeric(8,6) not null check(base_chance between 0 and 1),
  expires_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  resolved_at timestamptz
);
create index if not exists spirit_beast_encounters_owner_v267 on public.spirit_beast_encounters_v267(character_id,created_at desc);
create unique index if not exists spirit_beast_encounter_source_unique_v267 on public.spirit_beast_encounters_v267(character_id,source_type,source_ref) where source_ref is not null;

create table if not exists public.spirit_beast_request_ledger_v267(
  request_id uuid primary key,
  character_id uuid not null references public.player_characters(id) on delete cascade,
  action_code text not null,
  result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp()
);
create index if not exists spirit_beast_request_ledger_created_v267 on public.spirit_beast_request_ledger_v267(created_at);

create table if not exists public.spirit_beast_source_ledger_v267(
  character_id uuid not null references public.player_characters(id) on delete cascade,
  source_type text not null,
  source_ref text not null,
  result jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default clock_timestamp(),
  primary key(character_id,source_type,source_ref)
);

create index if not exists spirit_beast_source_ledger_created_v267 on public.spirit_beast_source_ledger_v267(created_at);

create table if not exists public.spirit_beast_admin_audit_v267(
  id bigint generated always as identity primary key,
  admin_user_id uuid,
  action_code text not null,
  target_ref text,
  reason text not null,
  old_value jsonb,
  new_value jsonb,
  created_at timestamptz not null default clock_timestamp()
);

revoke all on public.spirit_beast_settings_v267,public.spirit_beast_skills_v267,public.spirit_beast_personalities_v267,public.spirit_beast_species_v267,public.spirit_beast_evolutions_v267,public.spirit_beast_region_pool_v267,public.spirit_beast_egg_map_v267,public.character_spirit_beasts_v267,public.character_spirit_beast_state_v267,public.character_spirit_beast_codex_v267,public.spirit_beast_encounters_v267,public.spirit_beast_request_ledger_v267,public.spirit_beast_source_ledger_v267,public.spirit_beast_admin_audit_v267 from public,anon,authenticated;

insert into public.spirit_beast_skills_v267(skill_code,name,category,effect_kind,proc_chance,proc_power,description,enabled) values
('blaze_breath','赤炎吐息','combat','attack',0.1,0.18,'火焰爆发，战技折算为稳定道攻修正。',true),
('thunder_claw','雷霆裂爪','combat','attack',0.12,0.2,'雷爪爆发，战技折算为稳定道攻修正。',true),
('verdant_guard','青木护生','combat','guard',0.1,0.16,'草木灵机护主，战技折算为稳定防护修正。',true),
('shell_guard','玄甲护主','combat','guard',0.12,0.24,'玄甲撑开护罩，战技折算为稳定防护修正。',true),
('treasure_instinct','寻宝灵觉','utility','utility',0.0,0.0,'提高游历灵兽遭遇与相关资源权重。',true),
('wind_feather','御风灵羽','combat','attack',0.1,0.14,'借风势强化道攻与身法。',true),
('frost_bite','霜牙噬','combat','attack',0.1,0.18,'寒意侵袭，强化杀伤。',true),
('mist_step','雾隐','combat','guard',0.1,0.15,'借雾卸力，强化道御与身法。',true),
('mountain_roar','撼岳怒吼','combat','attack',0.08,0.22,'蛮力爆发，强化正面杀伤。',true),
('sunfire','大日火羽','combat','attack',0.1,0.2,'阳炎贯体，强化火势杀伐。',true),
('vine_bind','青藤缚','combat','guard',0.1,0.14,'藤蔓牵制来势，强化防护。',true),
('sand_armor','玄沙甲','combat','guard',0.12,0.18,'沙甲护身，强化防护。',true),
('moon_blessing','月华护念','combat','guard',0.1,0.16,'月华照拂，强化护主能力。',true),
('sky_dive','裂空俯冲','combat','attack',0.12,0.16,'高空俯冲，强化道攻与身法。',true),
('golden_roar','金狮镇邪','combat','attack',0.1,0.2,'金气化作狮吼，强化杀伐。',true),
('tidal_guard','沧浪回护','combat','guard',0.12,0.18,'潮势回卷，强化道御与生机。',true),
('void_flash','太虚闪','combat','guard',0.1,0.2,'借裂隙错开锋芒，强化身法。',true),
('earth_embrace','厚土抱岳','combat','guard',0.12,0.22,'厚土承压，强化道御与生机。',true),
('phoenix_flame','凤火涅槃','combat','attack',0.14,0.24,'神凤真火，提供神兽级道攻修正。',true),
('qilin_guard','麒麟瑞障','combat','guard',0.14,0.26,'瑞气成障，提供神兽级防护修正。',true),
('dragon_verdure','青龙生息','combat','guard',0.13,0.22,'青龙生机护持主人。',true),
('tiger_smite','白虎杀伐','combat','attack',0.14,0.26,'白虎杀气爆发，提供神兽级杀伐修正。',true),
('truewater_guard','真武玄水','combat','guard',0.15,0.28,'玄水护体，提供神兽级防护修正。',true),
('kunpeng_wing','鲲鹏垂天','combat','attack',0.14,0.25,'扶摇之势化为神兽级攻伐修正。',true),
('aux_treasure','寻珍','aux','utility',0,0,'提高游历触发灵兽遭遇的权重。',true),
('aux_herb','识草','aux','utility',0,0,'灵兽来源口粮数量小幅提高。',true),
('aux_spirit','灵息共鸣','aux','utility',0,0,'灵兽从活动获得的经验小幅提高。',true),
('aux_secret','秘境灵觉','aux','utility',0,0,'秘境灵兽蛋与材料权重小幅提高。',true),
('aux_boss','镇魔本能','aux','utility',0,0,'世界BOSS灵兽奖励权重小幅提高。',true),
('aux_capture','御兽亲和','aux','utility',0,0,'捕捉灵兽时提供小幅成功率。',true),
('aux_guard','护主','aux','guard',0.06,0.08,'额外提供少量防护折算。',true),
('aux_fury','凶性','aux','attack',0.06,0.08,'额外提供少量攻伐折算。',true),
('aux_agility','灵动','aux','utility',0,0,'增加灵兽提供的身法修正。',true),
('aux_vitality','共生','aux','utility',0,0,'增加灵兽提供的生机修正。',true),
('aux_defense','坚契','aux','utility',0,0,'增加灵兽提供的道御修正。',true),
('aux_attack','战契','aux','utility',0,0,'增加灵兽提供的道攻修正。',true)
on conflict(skill_code) do update set name=excluded.name,category=excluded.category,effect_kind=excluded.effect_kind,proc_chance=excluded.proc_chance,proc_power=excluded.proc_power,description=excluded.description,enabled=excluded.enabled;

insert into public.spirit_beast_personalities_v267(personality_code,name,description,attack_mult,defense_mult,vitality_mult,agility_mult,intimacy_mult,growth_mult,enabled) values
('brave','勇猛','道攻倾向',1.04,1.0,1.0,1.0,1.0,1.0,true),
('steady','沉稳','道御倾向',1.0,1.04,1.0,1.0,1.0,1.0,true),
('agile','机敏','身法倾向',1.0,1.0,1.0,1.04,1.0,1.0,true),
('loyal','忠诚','护主与亲密倾向',1.0,1.01,1.02,1.0,1.05,1.0,true),
('curious','好奇','探索倾向',1.0,1.0,1.0,1.01,1.0,1.05,true),
('glutton','贪吃','喂养成长更快',1.0,1.0,1.02,1.0,1.0,1.1,true),
('proud','孤傲','战力略高但亲密提升较慢',1.02,1.02,1.0,1.0,0.9,1.0,true),
('gentle','温顺','亲密提升更快',1.0,1.0,1.0,1.0,1.15,1.0,true)
on conflict(personality_code) do update set name=excluded.name,description=excluded.description,attack_mult=excluded.attack_mult,defense_mult=excluded.defense_mult,vitality_mult=excluded.vitality_mult,agility_mult=excluded.agility_mult,intimacy_mult=excluded.intimacy_mult,growth_mult=excluded.growth_mult,enabled=excluded.enabled;

insert into public.spirit_beast_species_v267(species_code,lineage_code,name,element,rarity,evolution_stage,description,innate_skill_code,native_region_code,attack_pct,defense_pct,vitality_pct,agility_pct,base_capture_chance,rarity_score,next_species_code,enabled) values
('redfox_1','redfox','赤焰狐','fire','common',1,'赤焰狐一族天生亲火，性情灵动，善于在战斗中寻找破绽。','blaze_breath','qingshan',0.014,0.004,0.004,0.005,0.66,1,'redfox_2',true),
('redfox_2','redfox','三尾炎狐','fire','rare',2,'赤焰狐一族天生亲火，性情灵动，善于在战斗中寻找破绽。','blaze_breath','qingshan',0.024,0.008,0.008,0.01,0,3,'redfox_3',true),
('redfox_3','redfox','九尾天狐','fire','epic',3,'赤焰狐一族天生亲火，性情灵动，善于在战斗中寻找破绽。','blaze_breath','qingshan',0.034,0.012,0.012,0.015,0,6,null,true),
('thunderleopard_1','thunderleopard','雷纹豹','thunder','common',1,'雷纹豹体内雷血奔涌，速度与爆发兼备。','thunder_claw','chiyuan',0.014,0.004,0.004,0.005,0.66,1,'thunderleopard_2',true),
('thunderleopard_2','thunderleopard','紫霆灵豹','thunder','rare',2,'雷纹豹体内雷血奔涌，速度与爆发兼备。','thunder_claw','chiyuan',0.024,0.008,0.008,0.01,0,3,'thunderleopard_3',true),
('thunderleopard_3','thunderleopard','雷狱天豹','thunder','epic',3,'雷纹豹体内雷血奔涌，速度与爆发兼备。','thunder_claw','chiyuan',0.034,0.012,0.012,0.015,0,6,null,true),
('greendeer_1','greendeer','青木鹿','wood','common',1,'青木鹿与草木灵机共鸣，性情温和，擅长护主与采药。','verdant_guard','luoxia',0.004,0.013,0.007,0.003,0.66,1,'greendeer_2',true),
('greendeer_2','greendeer','碧灵玄鹿','wood','rare',2,'青木鹿与草木灵机共鸣，性情温和，擅长护主与采药。','verdant_guard','luoxia',0.008,0.022,0.014,0.006,0,3,'greendeer_3',true),
('greendeer_3','greendeer','太古青鹿','wood','epic',3,'青木鹿与草木灵机共鸣，性情温和，擅长护主与采药。','verdant_guard','luoxia',0.012,0.031,0.021,0.009,0,6,null,true),
('blackturtle_1','blackturtle','玄甲龟','water','common',1,'玄甲龟甲壳厚重，寿元绵长，是最可靠的护主灵兽之一。','shell_guard','heishui',0.004,0.013,0.007,0.003,0.66,1,'blackturtle_2',true),
('blackturtle_2','blackturtle','镇岳玄龟','water','rare',2,'玄甲龟甲壳厚重，寿元绵长，是最可靠的护主灵兽之一。','shell_guard','heishui',0.008,0.022,0.014,0.006,0,3,'blackturtle_3',true),
('blackturtle_3','blackturtle','玄武遗种','water','epic',3,'玄甲龟甲壳厚重，寿元绵长，是最可靠的护主灵兽之一。','shell_guard','heishui',0.012,0.031,0.021,0.009,0,6,null,true),
('treasurerat_1','treasurerat','寻宝鼠','metal','common',1,'寻宝鼠嗅觉敏锐，能察觉常人忽略的灵物气息。','treasure_instinct','yunhai',0.014,0.004,0.004,0.005,0.66,1,'treasurerat_2',true),
('treasurerat_2','treasurerat','灵宝鼠','metal','rare',2,'寻宝鼠嗅觉敏锐，能察觉常人忽略的灵物气息。','treasure_instinct','yunhai',0.024,0.008,0.008,0.01,0,3,'treasurerat_3',true),
('treasurerat_3','treasurerat','通灵宝兽','metal','epic',3,'寻宝鼠嗅觉敏锐，能察觉常人忽略的灵物气息。','treasure_instinct','yunhai',0.034,0.012,0.012,0.015,0,6,null,true),
('crane_1','crane','青羽鹤','wind','common',1,'青羽鹤御风而行，身法飘逸，常伴高人洞府。','wind_feather','qingshan',0.014,0.004,0.004,0.005,0.66,1,'crane_2',true),
('crane_2','crane','玄羽灵鹤','wind','rare',2,'青羽鹤御风而行，身法飘逸，常伴高人洞府。','wind_feather','qingshan',0.024,0.008,0.008,0.01,0,3,'crane_3',true),
('crane_3','crane','九霄仙鹤','wind','epic',3,'青羽鹤御风而行，身法飘逸，常伴高人洞府。','wind_feather','qingshan',0.034,0.012,0.012,0.015,0,6,null,true),
('frostwolf_1','frostwolf','霜牙狼','ice','common',1,'霜牙狼生于极寒之地，血脉越纯，寒意越盛。','frost_bite','cangming',0.004,0.013,0.007,0.003,0.66,1,'frostwolf_2',true),
('frostwolf_2','frostwolf','寒月灵狼','ice','rare',2,'霜牙狼生于极寒之地，血脉越纯，寒意越盛。','frost_bite','cangming',0.008,0.022,0.014,0.006,0,3,'frostwolf_3',true),
('frostwolf_3','frostwolf','极夜天狼','ice','epic',3,'霜牙狼生于极寒之地，血脉越纯，寒意越盛。','frost_bite','cangming',0.012,0.031,0.021,0.009,0,6,null,true),
('mistcat_1','mistcat','雾灵猫','water','common',1,'雾灵猫行踪难测，擅长借水雾遮蔽身形。','mist_step','heishui',0.004,0.013,0.007,0.003,0.66,1,'mistcat_2',true),
('mistcat_2','mistcat','幻雾灵猫','water','rare',2,'雾灵猫行踪难测，擅长借水雾遮蔽身形。','mist_step','heishui',0.008,0.022,0.014,0.006,0,3,'mistcat_3',true),
('mistcat_3','mistcat','太阴幻猫','water','epic',3,'雾灵猫行踪难测，擅长借水雾遮蔽身形。','mist_step','heishui',0.012,0.031,0.021,0.009,0,6,null,true),
('stoneape_1','stoneape','岩甲猿','earth','common',1,'岩甲猿力大无穷，越是艰险之地越能激发其血性。','mountain_roar','chiyuan',0.004,0.013,0.007,0.003,0.66,1,'stoneape_2',true),
('stoneape_2','stoneape','镇山灵猿','earth','rare',2,'岩甲猿力大无穷，越是艰险之地越能激发其血性。','mountain_roar','chiyuan',0.008,0.022,0.014,0.006,0,3,'stoneape_3',true),
('stoneape_3','stoneape','撼岳神猿','earth','epic',3,'岩甲猿力大无穷，越是艰险之地越能激发其血性。','mountain_roar','chiyuan',0.012,0.031,0.021,0.009,0,6,null,true),
('suncrow_1','suncrow','赤阳鸦','fire','common',1,'赤阳鸦追逐烈阳火脉，羽翼中蕴藏炽热灵光。','sunfire','chiyuan',0.014,0.004,0.004,0.005,0.66,1,'suncrow_2',true),
('suncrow_2','suncrow','金焰灵鸦','fire','rare',2,'赤阳鸦追逐烈阳火脉，羽翼中蕴藏炽热灵光。','sunfire','chiyuan',0.024,0.008,0.008,0.01,0,3,'suncrow_3',true),
('suncrow_3','suncrow','大日金乌裔','fire','epic',3,'赤阳鸦追逐烈阳火脉，羽翼中蕴藏炽热灵光。','sunfire','chiyuan',0.034,0.012,0.012,0.015,0,6,null,true),
('vineserpent_1','vineserpent','青藤蛇','wood','common',1,'青藤蛇与古木共生，蜕变后可逐渐显露蛟属血脉。','vine_bind','luoxia',0.004,0.013,0.007,0.003,0.66,1,'vineserpent_2',true),
('vineserpent_2','vineserpent','碧鳞灵蟒','wood','rare',2,'青藤蛇与古木共生，蜕变后可逐渐显露蛟属血脉。','vine_bind','luoxia',0.008,0.022,0.014,0.006,0,3,'vineserpent_3',true),
('vineserpent_3','vineserpent','建木青蛟','wood','epic',3,'青藤蛇与古木共生，蜕变后可逐渐显露蛟属血脉。','vine_bind','luoxia',0.012,0.031,0.021,0.009,0,6,null,true),
('sandscorpion_1','sandscorpion','赤沙蝎','earth','common',1,'赤沙蝎潜伏黄沙与荒土，甲壳坚硬，出手迅疾。','sand_armor','taixu',0.004,0.013,0.007,0.003,0.66,1,'sandscorpion_2',true),
('sandscorpion_2','sandscorpion','玄沙毒蝎','earth','rare',2,'赤沙蝎潜伏黄沙与荒土，甲壳坚硬，出手迅疾。','sand_armor','taixu',0.008,0.022,0.014,0.006,0,3,'sandscorpion_3',true),
('sandscorpion_3','sandscorpion','荒古天蝎','earth','epic',3,'赤沙蝎潜伏黄沙与荒土，甲壳坚硬，出手迅疾。','sand_armor','taixu',0.012,0.031,0.021,0.009,0,6,null,true),
('moonrabbit_1','moonrabbit','月灵兔','ice','common',1,'月灵兔亲近月华，灵性极高，擅长温养主人气机。','moon_blessing','yunhai',0.004,0.013,0.007,0.003,0.66,1,'moonrabbit_2',true),
('moonrabbit_2','moonrabbit','太阴玉兔','ice','rare',2,'月灵兔亲近月华，灵性极高，擅长温养主人气机。','moon_blessing','yunhai',0.008,0.022,0.014,0.006,0,3,'moonrabbit_3',true),
('moonrabbit_3','moonrabbit','广寒灵尊','ice','epic',3,'月灵兔亲近月华，灵性极高，擅长温养主人气机。','moon_blessing','yunhai',0.012,0.031,0.021,0.009,0,6,null,true),
('cloudeagle_1','cloudeagle','流云鹰','wind','common',1,'流云鹰视野极远，能在高空锁定机缘与敌踪。','sky_dive','cangming',0.014,0.004,0.004,0.005,0.66,1,'cloudeagle_2',true),
('cloudeagle_2','cloudeagle','裂空灵鹰','wind','rare',2,'流云鹰视野极远，能在高空锁定机缘与敌踪。','sky_dive','cangming',0.024,0.008,0.008,0.01,0,3,'cloudeagle_3',true),
('cloudeagle_3','cloudeagle','天穹神鹰','wind','epic',3,'流云鹰视野极远，能在高空锁定机缘与敌踪。','sky_dive','cangming',0.034,0.012,0.012,0.015,0,6,null,true),
('goldlion_1','goldlion','金鬃狮','metal','common',1,'金鬃狮气势刚烈，对邪祟与强敌有天然压迫。','golden_roar','taixu',0.014,0.004,0.004,0.005,0.66,1,'goldlion_2',true),
('goldlion_2','goldlion','镇邪金狮','metal','rare',2,'金鬃狮气势刚烈，对邪祟与强敌有天然压迫。','golden_roar','taixu',0.024,0.008,0.008,0.01,0,3,'goldlion_3',true),
('goldlion_3','goldlion','天威圣狮','metal','epic',3,'金鬃狮气势刚烈，对邪祟与强敌有天然压迫。','golden_roar','taixu',0.034,0.012,0.012,0.015,0,6,null,true),
('tidedragon_1','tidedragon','潮生蜥','water','common',1,'潮生蜥栖于海潮灵穴，血脉成熟后会逐步向蛟龙蜕变。','tidal_guard','cangming',0.004,0.013,0.007,0.003,0.66,1,'tidedragon_2',true),
('tidedragon_2','tidedragon','沧浪灵蜥','water','rare',2,'潮生蜥栖于海潮灵穴，血脉成熟后会逐步向蛟龙蜕变。','tidal_guard','cangming',0.008,0.022,0.014,0.006,0,3,'tidedragon_3',true),
('tidedragon_3','tidedragon','覆海蛟龙','water','epic',3,'潮生蜥栖于海潮灵穴，血脉成熟后会逐步向蛟龙蜕变。','tidal_guard','cangming',0.012,0.031,0.021,0.009,0,6,null,true),
('voidbutterfly_1','voidbutterfly','空灵蝶','wind','common',1,'空灵蝶能感应空间波动，常在裂隙与遗迹附近现身。','void_flash','taixu',0.014,0.004,0.004,0.005,0.66,1,'voidbutterfly_2',true),
('voidbutterfly_2','voidbutterfly','虚光灵蝶','wind','rare',2,'空灵蝶能感应空间波动，常在裂隙与遗迹附近现身。','void_flash','taixu',0.024,0.008,0.008,0.01,0,3,'voidbutterfly_3',true),
('voidbutterfly_3','voidbutterfly','太虚梦蝶','wind','epic',3,'空灵蝶能感应空间波动，常在裂隙与遗迹附近现身。','void_flash','taixu',0.034,0.012,0.012,0.015,0,6,null,true),
('spiritbear_1','spiritbear','厚土熊','earth','common',1,'厚土熊性情沉稳，体魄强横，最擅长正面护主。','earth_embrace','wujitian',0.004,0.013,0.007,0.003,0.66,1,'spiritbear_2',true),
('spiritbear_2','spiritbear','镇地灵熊','earth','rare',2,'厚土熊性情沉稳，体魄强横，最擅长正面护主。','earth_embrace','wujitian',0.008,0.022,0.014,0.006,0,3,'spiritbear_3',true),
('spiritbear_3','spiritbear','大地圣熊','earth','epic',3,'厚土熊性情沉稳，体魄强横，最擅长正面护主。','earth_embrace','wujitian',0.012,0.031,0.021,0.009,0,6,null,true),
('phoenix','phoenix','不灭火凤','fire','legendary',3,'不灭火凤浴火而生，是火属灵兽中极罕见的天命血脉。','phoenix_flame','wujitian',0.046,0.024,0.024,0.023,0,10,null,true),
('qilin','qilin','瑞土麒麟','earth','legendary',3,'麒麟瑞气镇压灾厄，兼具护主与寻机之能。','qilin_guard','wujitian',0.024,0.043,0.033,0.017,0,10,null,true),
('azure_dragon','azure_dragon','苍木青龙','wood','legendary',3,'青龙引动东方生机，血脉天然亲近木行大道。','dragon_verdure','wujitian',0.024,0.043,0.033,0.017,0,10,null,true),
('white_tiger','white_tiger','庚金白虎','metal','legendary',3,'白虎主杀伐，庚金之气凝于爪牙。','tiger_smite','wujitian',0.046,0.024,0.024,0.023,0,10,null,true),
('black_tortoise','black_tortoise','玄水真武','water','legendary',3,'真武厚重如渊，防护与生机极为强盛。','truewater_guard','wujitian',0.024,0.043,0.033,0.017,0,10,null,true),
('kunpeng','kunpeng','天海鲲鹏','wind','legendary',3,'鲲鹏扶摇九霄，兼具海天之势，世间难觅。','kunpeng_wing','wujitian',0.046,0.024,0.024,0.023,0,10,null,true)
on conflict(species_code) do update set lineage_code=excluded.lineage_code,name=excluded.name,element=excluded.element,rarity=excluded.rarity,evolution_stage=excluded.evolution_stage,description=excluded.description,innate_skill_code=excluded.innate_skill_code,native_region_code=excluded.native_region_code,attack_pct=excluded.attack_pct,defense_pct=excluded.defense_pct,vitality_pct=excluded.vitality_pct,agility_pct=excluded.agility_pct,base_capture_chance=excluded.base_capture_chance,rarity_score=excluded.rarity_score,next_species_code=excluded.next_species_code,enabled=excluded.enabled;

insert into public.spirit_beast_evolutions_v267(from_species_code,to_species_code,min_owner_realm_order,min_level,min_bloodline,min_intimacy,soul_cost,essence_item_code,essence_cost,spirit_stone_cost,enabled) values
('redfox_1','redfox_2',2,20,65,40,30,'spirit_beast_essence_fire',3,30000,true),
('redfox_2','redfox_3',4,40,85,80,100,'spirit_beast_essence_fire',10,150000,true),
('thunderleopard_1','thunderleopard_2',2,20,65,40,30,'spirit_beast_essence_thunder',3,30000,true),
('thunderleopard_2','thunderleopard_3',4,40,85,80,100,'spirit_beast_essence_thunder',10,150000,true),
('greendeer_1','greendeer_2',2,20,65,40,30,'spirit_beast_essence_wood',3,30000,true),
('greendeer_2','greendeer_3',4,40,85,80,100,'spirit_beast_essence_wood',10,150000,true),
('blackturtle_1','blackturtle_2',2,20,65,40,30,'spirit_beast_essence_water',3,30000,true),
('blackturtle_2','blackturtle_3',4,40,85,80,100,'spirit_beast_essence_water',10,150000,true),
('treasurerat_1','treasurerat_2',2,20,65,40,30,'spirit_beast_essence_metal',3,30000,true),
('treasurerat_2','treasurerat_3',4,40,85,80,100,'spirit_beast_essence_metal',10,150000,true),
('crane_1','crane_2',2,20,65,40,30,'spirit_beast_essence_wind',3,30000,true),
('crane_2','crane_3',4,40,85,80,100,'spirit_beast_essence_wind',10,150000,true),
('frostwolf_1','frostwolf_2',2,20,65,40,30,'spirit_beast_essence_ice',3,30000,true),
('frostwolf_2','frostwolf_3',4,40,85,80,100,'spirit_beast_essence_ice',10,150000,true),
('mistcat_1','mistcat_2',2,20,65,40,30,'spirit_beast_essence_water',3,30000,true),
('mistcat_2','mistcat_3',4,40,85,80,100,'spirit_beast_essence_water',10,150000,true),
('stoneape_1','stoneape_2',2,20,65,40,30,'spirit_beast_essence_earth',3,30000,true),
('stoneape_2','stoneape_3',4,40,85,80,100,'spirit_beast_essence_earth',10,150000,true),
('suncrow_1','suncrow_2',2,20,65,40,30,'spirit_beast_essence_fire',3,30000,true),
('suncrow_2','suncrow_3',4,40,85,80,100,'spirit_beast_essence_fire',10,150000,true),
('vineserpent_1','vineserpent_2',2,20,65,40,30,'spirit_beast_essence_wood',3,30000,true),
('vineserpent_2','vineserpent_3',4,40,85,80,100,'spirit_beast_essence_wood',10,150000,true),
('sandscorpion_1','sandscorpion_2',2,20,65,40,30,'spirit_beast_essence_earth',3,30000,true),
('sandscorpion_2','sandscorpion_3',4,40,85,80,100,'spirit_beast_essence_earth',10,150000,true),
('moonrabbit_1','moonrabbit_2',2,20,65,40,30,'spirit_beast_essence_ice',3,30000,true),
('moonrabbit_2','moonrabbit_3',4,40,85,80,100,'spirit_beast_essence_ice',10,150000,true),
('cloudeagle_1','cloudeagle_2',2,20,65,40,30,'spirit_beast_essence_wind',3,30000,true),
('cloudeagle_2','cloudeagle_3',4,40,85,80,100,'spirit_beast_essence_wind',10,150000,true),
('goldlion_1','goldlion_2',2,20,65,40,30,'spirit_beast_essence_metal',3,30000,true),
('goldlion_2','goldlion_3',4,40,85,80,100,'spirit_beast_essence_metal',10,150000,true),
('tidedragon_1','tidedragon_2',2,20,65,40,30,'spirit_beast_essence_water',3,30000,true),
('tidedragon_2','tidedragon_3',4,40,85,80,100,'spirit_beast_essence_water',10,150000,true),
('voidbutterfly_1','voidbutterfly_2',2,20,65,40,30,'spirit_beast_essence_wind',3,30000,true),
('voidbutterfly_2','voidbutterfly_3',4,40,85,80,100,'spirit_beast_essence_wind',10,150000,true),
('spiritbear_1','spiritbear_2',2,20,65,40,30,'spirit_beast_essence_earth',3,30000,true),
('spiritbear_2','spiritbear_3',4,40,85,80,100,'spirit_beast_essence_earth',10,150000,true)
on conflict(from_species_code) do update set to_species_code=excluded.to_species_code,min_owner_realm_order=excluded.min_owner_realm_order,min_level=excluded.min_level,min_bloodline=excluded.min_bloodline,min_intimacy=excluded.min_intimacy,soul_cost=excluded.soul_cost,essence_item_code=excluded.essence_item_code,essence_cost=excluded.essence_cost,spirit_stone_cost=excluded.spirit_stone_cost,enabled=excluded.enabled;

insert into public.spirit_beast_region_pool_v267(region_code,species_code,weight,enabled) values
('qingshan','redfox_1',120,true),
('qingshan','crane_1',110,true),
('qingshan','treasurerat_1',100,true),
('qingshan','greendeer_1',90,true),
('luoxia','greendeer_1',120,true),
('luoxia','vineserpent_1',110,true),
('luoxia','moonrabbit_1',100,true),
('luoxia','redfox_1',90,true),
('yunhai','treasurerat_1',120,true),
('yunhai','crane_1',110,true),
('yunhai','moonrabbit_1',100,true),
('yunhai','cloudeagle_1',90,true),
('heishui','blackturtle_1',120,true),
('heishui','mistcat_1',110,true),
('heishui','tidedragon_1',100,true),
('heishui','vineserpent_1',90,true),
('chiyuan','thunderleopard_1',120,true),
('chiyuan','stoneape_1',110,true),
('chiyuan','suncrow_1',100,true),
('chiyuan','redfox_1',90,true),
('cangming','frostwolf_1',120,true),
('cangming','cloudeagle_1',110,true),
('cangming','tidedragon_1',100,true),
('cangming','mistcat_1',90,true),
('taixu','sandscorpion_1',120,true),
('taixu','goldlion_1',110,true),
('taixu','voidbutterfly_1',100,true),
('taixu','thunderleopard_1',90,true),
('wujitian','spiritbear_1',120,true),
('wujitian','voidbutterfly_1',110,true),
('wujitian','goldlion_1',100,true),
('wujitian','cloudeagle_1',90,true)
on conflict(region_code,species_code) do update set weight=excluded.weight,enabled=excluded.enabled;

insert into public.spirit_beast_egg_map_v267(item_code,species_code,min_bloodline,max_bloodline,rarity,enabled) values
('spirit_beast_egg_redfox','redfox_1',60,92,'rare',true),
('spirit_beast_egg_thunderleopard','thunderleopard_1',60,92,'rare',true),
('spirit_beast_egg_greendeer','greendeer_1',60,92,'rare',true),
('spirit_beast_egg_blackturtle','blackturtle_1',60,92,'rare',true),
('spirit_beast_egg_treasurerat','treasurerat_1',60,92,'rare',true),
('spirit_beast_egg_crane','crane_1',60,92,'rare',true),
('spirit_beast_egg_frostwolf','frostwolf_1',60,92,'rare',true),
('spirit_beast_egg_mistcat','mistcat_1',60,92,'rare',true),
('spirit_beast_egg_stoneape','stoneape_1',60,92,'rare',true),
('spirit_beast_egg_suncrow','suncrow_1',60,92,'rare',true),
('spirit_beast_egg_vineserpent','vineserpent_1',60,92,'rare',true),
('spirit_beast_egg_sandscorpion','sandscorpion_1',60,92,'rare',true),
('spirit_beast_egg_moonrabbit','moonrabbit_1',60,92,'rare',true),
('spirit_beast_egg_cloudeagle','cloudeagle_1',60,92,'rare',true),
('spirit_beast_egg_goldlion','goldlion_1',60,92,'rare',true),
('spirit_beast_egg_tidedragon','tidedragon_1',60,92,'rare',true),
('spirit_beast_egg_voidbutterfly','voidbutterfly_1',60,92,'rare',true),
('spirit_beast_egg_spiritbear','spiritbear_1',60,92,'rare',true),
('spirit_beast_egg_phoenix','phoenix',90,100,'legendary',true),
('spirit_beast_egg_qilin','qilin',90,100,'legendary',true),
('spirit_beast_egg_azure_dragon','azure_dragon',90,100,'legendary',true),
('spirit_beast_egg_white_tiger','white_tiger',90,100,'legendary',true),
('spirit_beast_egg_black_tortoise','black_tortoise',90,100,'legendary',true),
('spirit_beast_egg_kunpeng','kunpeng',90,100,'legendary',true)
on conflict(item_code) do update set species_code=excluded.species_code,min_bloodline=excluded.min_bloodline,max_bloodline=excluded.max_bloodline,rarity=excluded.rarity,enabled=excluded.enabled;

insert into public.item_definitions(code,name,category,rarity,stack_limit,effects,description) values
('spirit_beast_food','灵兽口粮','material','common',9999,'{}'::jsonb,'灵兽喂养基础资源。'),
('spirit_beast_soul','兽魂','material','uncommon',99999,'{}'::jsonb,'放归重复灵兽与高阶玩法获得，用于突破、技能和进化。'),
('spirit_beast_marrow_dew','洗髓露','material','rare',999,'{}'::jsonb,'重塑灵兽性格。'),
('spirit_beast_talisman','御兽符','material','uncommon',999,'{}'::jsonb,'捕捉时提高成功率。'),
('spirit_beast_talisman_high','上品御兽符','material','rare',999,'{}'::jsonb,'捕捉时显著提高成功率。'),
('spirit_beast_skill_scroll','灵兽悟法卷','material','rare',999,'{}'::jsonb,'学习或精进一个辅助天赋。'),
('spirit_beast_essence_fire','炎行血脉精魄','material','rare',9999,'{}'::jsonb,'灵兽进化所需的血脉精魄。'),
('spirit_beast_essence_thunder','雷行血脉精魄','material','rare',9999,'{}'::jsonb,'灵兽进化所需的血脉精魄。'),
('spirit_beast_essence_wood','木行血脉精魄','material','rare',9999,'{}'::jsonb,'灵兽进化所需的血脉精魄。'),
('spirit_beast_essence_water','水行血脉精魄','material','rare',9999,'{}'::jsonb,'灵兽进化所需的血脉精魄。'),
('spirit_beast_essence_metal','金行血脉精魄','material','rare',9999,'{}'::jsonb,'灵兽进化所需的血脉精魄。'),
('spirit_beast_essence_wind','风行血脉精魄','material','rare',9999,'{}'::jsonb,'灵兽进化所需的血脉精魄。'),
('spirit_beast_essence_ice','冰行血脉精魄','material','rare',9999,'{}'::jsonb,'灵兽进化所需的血脉精魄。'),
('spirit_beast_essence_earth','土行血脉精魄','material','rare',9999,'{}'::jsonb,'灵兽进化所需的血脉精魄。'),
('spirit_beast_egg_redfox','赤焰狐兽卵','material','rare',99,'{}'::jsonb,'尚未认主，可在天墟交易并于灵兽苑孵化。'),
('spirit_beast_egg_thunderleopard','雷纹豹兽卵','material','rare',99,'{}'::jsonb,'尚未认主，可在天墟交易并于灵兽苑孵化。'),
('spirit_beast_egg_greendeer','青木鹿兽卵','material','rare',99,'{}'::jsonb,'尚未认主，可在天墟交易并于灵兽苑孵化。'),
('spirit_beast_egg_blackturtle','玄甲龟兽卵','material','rare',99,'{}'::jsonb,'尚未认主，可在天墟交易并于灵兽苑孵化。'),
('spirit_beast_egg_treasurerat','寻宝鼠兽卵','material','rare',99,'{}'::jsonb,'尚未认主，可在天墟交易并于灵兽苑孵化。'),
('spirit_beast_egg_crane','青羽鹤兽卵','material','rare',99,'{}'::jsonb,'尚未认主，可在天墟交易并于灵兽苑孵化。'),
('spirit_beast_egg_frostwolf','霜牙狼兽卵','material','rare',99,'{}'::jsonb,'尚未认主，可在天墟交易并于灵兽苑孵化。'),
('spirit_beast_egg_mistcat','雾灵猫兽卵','material','rare',99,'{}'::jsonb,'尚未认主，可在天墟交易并于灵兽苑孵化。'),
('spirit_beast_egg_stoneape','岩甲猿兽卵','material','rare',99,'{}'::jsonb,'尚未认主，可在天墟交易并于灵兽苑孵化。'),
('spirit_beast_egg_suncrow','赤阳鸦兽卵','material','rare',99,'{}'::jsonb,'尚未认主，可在天墟交易并于灵兽苑孵化。'),
('spirit_beast_egg_vineserpent','青藤蛇兽卵','material','rare',99,'{}'::jsonb,'尚未认主，可在天墟交易并于灵兽苑孵化。'),
('spirit_beast_egg_sandscorpion','赤沙蝎兽卵','material','rare',99,'{}'::jsonb,'尚未认主，可在天墟交易并于灵兽苑孵化。'),
('spirit_beast_egg_moonrabbit','月灵兔兽卵','material','rare',99,'{}'::jsonb,'尚未认主，可在天墟交易并于灵兽苑孵化。'),
('spirit_beast_egg_cloudeagle','流云鹰兽卵','material','rare',99,'{}'::jsonb,'尚未认主，可在天墟交易并于灵兽苑孵化。'),
('spirit_beast_egg_goldlion','金鬃狮兽卵','material','rare',99,'{}'::jsonb,'尚未认主，可在天墟交易并于灵兽苑孵化。'),
('spirit_beast_egg_tidedragon','潮生蜥兽卵','material','rare',99,'{}'::jsonb,'尚未认主，可在天墟交易并于灵兽苑孵化。'),
('spirit_beast_egg_voidbutterfly','空灵蝶兽卵','material','rare',99,'{}'::jsonb,'尚未认主，可在天墟交易并于灵兽苑孵化。'),
('spirit_beast_egg_spiritbear','厚土熊兽卵','material','rare',99,'{}'::jsonb,'尚未认主，可在天墟交易并于灵兽苑孵化。'),
('spirit_beast_egg_phoenix','不灭火凤神卵','material','legendary',9,'{}'::jsonb,'极罕见神兽卵，未孵化前可交易。'),
('spirit_beast_egg_qilin','瑞土麒麟神卵','material','legendary',9,'{}'::jsonb,'极罕见神兽卵，未孵化前可交易。'),
('spirit_beast_egg_azure_dragon','苍木青龙神卵','material','legendary',9,'{}'::jsonb,'极罕见神兽卵，未孵化前可交易。'),
('spirit_beast_egg_white_tiger','庚金白虎神卵','material','legendary',9,'{}'::jsonb,'极罕见神兽卵，未孵化前可交易。'),
('spirit_beast_egg_black_tortoise','玄水真武神卵','material','legendary',9,'{}'::jsonb,'极罕见神兽卵，未孵化前可交易。'),
('spirit_beast_egg_kunpeng','天海鲲鹏神卵','material','legendary',9,'{}'::jsonb,'极罕见神兽卵，未孵化前可交易。')
on conflict(code) do update set name=excluded.name,category=excluded.category,rarity=excluded.rarity,stack_limit=excluded.stack_limit,effects=excluded.effects,description=excluded.description;

-- ==================== INTERNAL HELPERS ====================
create or replace function public.spirit_beast_active_character_v267()
returns uuid language sql stable security definer set search_path='' as $$select public.tianxu_active_character_v255()$$;

create or replace function public.spirit_beast_character_realm_order_v267(p_character_id uuid)
returns integer language sql stable security definer set search_path='' as $$
select r.major_order from public.player_characters pc join public.realm_stages rs on rs.id=pc.realm_stage_id join public.realms r on r.id=rs.realm_id where pc.id=p_character_id
$$;

create or replace function public.spirit_beast_ensure_state_v267(p_character_id uuid)
returns void language plpgsql security definer set search_path='' as $$
begin insert into public.character_spirit_beast_state_v267(character_id) values(p_character_id) on conflict(character_id) do nothing; end $$;

create or replace function public.spirit_beast_capacity_v267(p_character_id uuid)
returns integer language plpgsql stable security definer set search_path='' as $$
declare s public.spirit_beast_settings_v267%rowtype;v_level integer:=1;
begin
 select * into s from public.spirit_beast_settings_v267 where singleton_id=1;
 select stable_level into v_level from public.character_spirit_beast_state_v267 where character_id=p_character_id;
 return s.base_capacity+greatest(0,coalesce(v_level,1)-1)*s.capacity_per_stable_level;
end $$;

create or replace function public.spirit_beast_score_v267(p_beast_id uuid)
returns bigint language sql stable security definer set search_path='' as $$
select coalesce(sp.rarity_score,1)*100000::bigint + sp.evolution_stage*50000::bigint + b.beast_realm_order*10000::bigint + b.level*500::bigint + b.bloodline*100::bigint + b.intimacy*50::bigint + b.skill_level*1000::bigint + b.aux_skill_level*500::bigint
from public.character_spirit_beasts_v267 b join public.spirit_beast_species_v267 sp on sp.species_code=b.species_code where b.id=p_beast_id
$$;

create or replace function public.spirit_beast_request_get_v267(p_character uuid,p_request uuid,p_action text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v jsonb;v_action text;
begin
 if p_request is null then return null;end if;
 select action_code,result into v_action,v from public.spirit_beast_request_ledger_v267 where request_id=p_request and character_id=p_character;
 if v is not null and v_action<>p_action then raise exception 'SPIRIT_BEAST_REQUEST_ID_REUSED';end if;
 return v;
end $$;

create or replace function public.spirit_beast_request_put_v267(p_character uuid,p_request uuid,p_action text,p_result jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if p_request is not null then insert into public.spirit_beast_request_ledger_v267(request_id,character_id,action_code,result) values(p_request,p_character,p_action,coalesce(p_result,'{}'::jsonb)) on conflict(request_id) do nothing;end if;
 return coalesce(p_result,'{}'::jsonb);
end $$;

create or replace function public.spirit_beast_update_codex_v267(p_beast_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare b public.character_spirit_beasts_v267%rowtype;
begin
 select * into b from public.character_spirit_beasts_v267 where id=p_beast_id;if b.id is null then return;end if;
 insert into public.character_spirit_beast_codex_v267(character_id,species_code,highest_bloodline,highest_level)
 values(b.character_id,b.species_code,b.bloodline,b.level)
 on conflict(character_id,species_code) do update set last_obtained_at=clock_timestamp(),highest_bloodline=greatest(public.character_spirit_beast_codex_v267.highest_bloodline,excluded.highest_bloodline),highest_level=greatest(public.character_spirit_beast_codex_v267.highest_level,excluded.highest_level),times_obtained=public.character_spirit_beast_codex_v267.times_obtained+1;
end $$;

create or replace function public.spirit_beast_create_instance_v267(p_character uuid,p_species text,p_bloodline integer,p_source text,p_source_ref text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_personality text;v_count integer;v_capacity integer;v_stage integer;
begin
 perform public.spirit_beast_ensure_state_v267(p_character);
 select evolution_stage into v_stage from public.spirit_beast_species_v267 where species_code=p_species and enabled;if v_stage is null then raise exception 'SPIRIT_BEAST_SPECIES_NOT_FOUND';end if;
 select count(*) into v_count from public.character_spirit_beasts_v267 where character_id=p_character;v_capacity:=public.spirit_beast_capacity_v267(p_character);if v_count>=v_capacity then raise exception 'SPIRIT_BEAST_STABLE_FULL';end if;
 select personality_code into v_personality from public.spirit_beast_personalities_v267 where enabled order by random() limit 1;
 insert into public.character_spirit_beasts_v267(character_id,species_code,bloodline,personality_code,intimacy,locked,source_type,source_ref)
 values(p_character,p_species,greatest(1,least(100,p_bloodline)),v_personality,case when v_stage>=3 then 10 else 0 end,(p_bloodline>=90 or v_stage>=3),coalesce(nullif(p_source,''),'unknown'),p_source_ref) returning id into v_id;
 perform public.spirit_beast_update_codex_v267(v_id);
 return v_id;
end $$;

create or replace function public.spirit_beast_gain_exp_v267(p_beast_id uuid,p_exp bigint,p_intimacy integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare b public.character_spirit_beasts_v267%rowtype;pr public.spirit_beast_personalities_v267%rowtype;v_exp bigint;v_req bigint;v_cap integer;v_level integer;v_int integer;
begin
 select * into b from public.character_spirit_beasts_v267 where id=p_beast_id for update;if b.id is null then return '{}'::jsonb;end if;
 select * into pr from public.spirit_beast_personalities_v267 where personality_code=b.personality_code;
 v_exp:=b.exp+greatest(0,round(coalesce(p_exp,0)*coalesce(pr.growth_mult,1))::bigint);v_level:=b.level;v_cap:=least(90,b.beast_realm_order*10);
 while v_level<v_cap loop v_req:=100+v_level*50;if v_exp<v_req then exit;end if;v_exp:=v_exp-v_req;v_level:=v_level+1;end loop;
 if v_level>=v_cap then v_exp:=least(v_exp,(100+v_level*50)-1);end if;
 v_int:=greatest(0,least(100,b.intimacy+round(coalesce(p_intimacy,0)*coalesce(pr.intimacy_mult,1))::integer));
 update public.character_spirit_beasts_v267 set level=v_level,exp=v_exp,intimacy=v_int,updated_at=clock_timestamp() where id=b.id;
 insert into public.character_spirit_beast_codex_v267(character_id,species_code,highest_bloodline,highest_level) values(b.character_id,b.species_code,b.bloodline,v_level) on conflict(character_id,species_code) do update set highest_bloodline=greatest(public.character_spirit_beast_codex_v267.highest_bloodline,excluded.highest_bloodline),highest_level=greatest(public.character_spirit_beast_codex_v267.highest_level,excluded.highest_level),last_obtained_at=clock_timestamp();
 return jsonb_build_object('beast_id',b.id,'level',v_level,'exp',v_exp,'level_cap',v_cap,'intimacy',v_int);
end $$;

create or replace function public.spirit_beast_gain_active_exp_v267(p_character uuid,p_exp bigint,p_intimacy integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_id uuid;v_aux text;v_aux_level integer;v_bonus numeric:=1;
begin
 perform public.spirit_beast_ensure_state_v267(p_character);select st.active_beast_id,b.aux_skill_code,b.aux_skill_level into v_id,v_aux,v_aux_level from public.character_spirit_beast_state_v267 st left join public.character_spirit_beasts_v267 b on b.id=st.active_beast_id and b.character_id=st.character_id where st.character_id=p_character;
 if v_id is null then return '{}'::jsonb;end if;if v_aux='aux_spirit' then v_bonus:=1.10+greatest(0,coalesce(v_aux_level,0)-1)*.01;end if;
 return public.spirit_beast_gain_exp_v267(v_id,round(p_exp*v_bonus)::bigint,p_intimacy);
end $$;

create or replace function public.spirit_beast_combat_modifier_v267(p_character uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare s public.spirit_beast_settings_v267%rowtype;b public.character_spirit_beasts_v267%rowtype;sp public.spirit_beast_species_v267%rowtype;pr public.spirit_beast_personalities_v267%rowtype;sk public.spirit_beast_skills_v267%rowtype;v_at numeric;v_df numeric;v_hp numeric;v_ag numeric;v_scale numeric;v_aux text;
begin
 select * into s from public.spirit_beast_settings_v267 where singleton_id=1;if not coalesce(s.enabled,false) or not coalesce(s.combat_enabled,false) then return '{}'::jsonb;end if;
 select b0.* into b from public.character_spirit_beast_state_v267 st join public.character_spirit_beasts_v267 b0 on b0.id=st.active_beast_id and b0.character_id=st.character_id where st.character_id=p_character;if b.id is null then return '{}'::jsonb;end if;
 select * into sp from public.spirit_beast_species_v267 where species_code=b.species_code and enabled;select * into pr from public.spirit_beast_personalities_v267 where personality_code=b.personality_code;select * into sk from public.spirit_beast_skills_v267 where skill_code=sp.innate_skill_code;
 v_scale:=(.70+b.bloodline/250.0)*(.85+b.intimacy/666.0)*(1+greatest(0,b.skill_level-1)*.025);
 v_at:=sp.attack_pct*v_scale*coalesce(pr.attack_mult,1);v_df:=sp.defense_pct*v_scale*coalesce(pr.defense_mult,1);v_hp:=sp.vitality_pct*v_scale*coalesce(pr.vitality_mult,1);v_ag:=sp.agility_pct*v_scale*coalesce(pr.agility_mult,1);
 -- 战技以稳定等效修正接入所有战斗引擎，避免不同战斗模拟器出现随机结果不一致。
 if sk.effect_kind='attack' then v_at:=v_at+sk.proc_chance*sk.proc_power*.45;elsif sk.effect_kind='guard' then v_df:=v_df+sk.proc_chance*sk.proc_power*.35;v_hp:=v_hp+sk.proc_chance*sk.proc_power*.20;end if;
 v_aux:=coalesce(b.aux_skill_code,'');if v_aux='aux_attack' then v_at:=v_at+.006+.001*b.aux_skill_level;elsif v_aux='aux_defense' then v_df:=v_df+.006+.001*b.aux_skill_level;elsif v_aux='aux_vitality' then v_hp:=v_hp+.006+.001*b.aux_skill_level;elsif v_aux='aux_agility' then v_ag:=v_ag+.006+.001*b.aux_skill_level;elsif v_aux='aux_fury' then v_at:=v_at+.005;elsif v_aux='aux_guard' then v_df:=v_df+.005;end if;
 v_at:=least(s.combat_stat_cap,greatest(0,v_at));v_df:=least(s.combat_stat_cap,greatest(0,v_df));v_hp:=least(s.combat_stat_cap,greatest(0,v_hp));v_ag:=least(s.combat_stat_cap,greatest(0,v_ag));
 return jsonb_build_object('beast_id',b.id,'species_code',sp.species_code,'name',coalesce(nullif(b.nickname,''),sp.name),'skill_code',sp.innate_skill_code,'skill_name',sk.name,'attack_pct',round(v_at,6),'defense_pct',round(v_df,6),'vitality_pct',round(v_hp,6),'agility_pct',round(v_ag,6),'bloodline',b.bloodline,'intimacy',b.intimacy,'level',b.level,'realm_order',b.beast_realm_order);
end $$;

create or replace function public.spirit_beast_apply_snapshot_v267(p_snapshot jsonb,p_character uuid default null)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v jsonb:=coalesce(p_snapshot,'{}'::jsonb);v_char uuid:=p_character;m jsonb;v_at numeric;v_df numeric;v_hp numeric;v_ag numeric;
begin
 if coalesce((v->>'spirit_beast_v267_applied')::boolean,false) then return v;end if;
 if v_char is null then begin v_char:=(v->>'character_id')::uuid;exception when others then v_char:=null;end;end if;if v_char is null then return v;end if;
 m:=public.spirit_beast_combat_modifier_v267(v_char);if m='{}'::jsonb then return v;end if;
 v_at:=coalesce(nullif(v->>'attack','')::numeric,0)*(1+coalesce((m->>'attack_pct')::numeric,0));v_df:=coalesce(nullif(v->>'defense','')::numeric,0)*(1+coalesce((m->>'defense_pct')::numeric,0));v_hp:=coalesce(nullif(v->>'vitality','')::numeric,0)*(1+coalesce((m->>'vitality_pct')::numeric,0));v_ag:=coalesce(nullif(v->>'agility','')::numeric,0)*(1+coalesce((m->>'agility_pct')::numeric,0));
 return v||jsonb_build_object('attack',round(v_at,4),'defense',round(v_df,4),'vitality',round(v_hp,4),'agility',round(v_ag,4),'spirit_beast_v267_applied',true,'spirit_beast_v267',m);
end $$;

create or replace function public.spirit_beast_create_encounter_v267(p_character uuid,p_region text,p_source_type text,p_source_ref text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s public.spirit_beast_settings_v267%rowtype;sp public.spirit_beast_species_v267%rowtype;v_id uuid;v_blood integer;v_existing public.spirit_beast_encounters_v267%rowtype;
begin
 select * into s from public.spirit_beast_settings_v267 where singleton_id=1;if not s.enabled or not s.capture_enabled then return jsonb_build_object('status','disabled');end if;
 if p_source_ref is not null then select * into v_existing from public.spirit_beast_encounters_v267 where character_id=p_character and source_type=p_source_type and source_ref=p_source_ref limit 1;if v_existing.id is not null then return jsonb_build_object('status',v_existing.status,'encounter_id',v_existing.id);end if;end if;
 select sp0.* into sp from public.spirit_beast_region_pool_v267 pool join public.spirit_beast_species_v267 sp0 on sp0.species_code=pool.species_code where pool.region_code=p_region and pool.enabled and sp0.enabled order by -ln(greatest(random(),0.000001))/pool.weight limit 1;
 if sp.species_code is null then select * into sp from public.spirit_beast_species_v267 where evolution_stage=1 and enabled order by random() limit 1;end if;
 v_blood:=50+floor(random()*41)::integer;
 insert into public.spirit_beast_encounters_v267(character_id,species_code,region_code,source_type,source_ref,bloodline,base_chance,expires_at) values(p_character,sp.species_code,p_region,p_source_type,p_source_ref,v_blood,sp.base_capture_chance,clock_timestamp()+make_interval(mins=>s.encounter_expiry_minutes)) returning id into v_id;
 return jsonb_build_object('status','encounter','encounter_id',v_id,'species_code',sp.species_code,'species_name',sp.name,'rarity',sp.rarity,'element',sp.element,'bloodline_hint',case when v_blood>=90 then '血脉气息极纯' when v_blood>=75 then '血脉气息不凡' else '血脉气息平稳' end,'expires_at',clock_timestamp()+make_interval(mins=>s.encounter_expiry_minutes));
end $$;

create or replace function public.spirit_beast_source_get_v267(p_character uuid,p_type text,p_ref text)
returns jsonb language sql stable security definer set search_path='' as $$select result from public.spirit_beast_source_ledger_v267 where character_id=p_character and source_type=p_type and source_ref=p_ref$$;

create or replace function public.spirit_beast_source_put_v267(p_character uuid,p_type text,p_ref text,p_result jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$begin insert into public.spirit_beast_source_ledger_v267(character_id,source_type,source_ref,result) values(p_character,p_type,p_ref,coalesce(p_result,'{}'::jsonb)) on conflict(character_id,source_type,source_ref) do nothing;return coalesce((select result from public.spirit_beast_source_ledger_v267 where character_id=p_character and source_type=p_type and source_ref=p_ref),p_result,'{}'::jsonb);end$$;

create or replace function public.spirit_beast_aux_bonus_v267(p_character uuid,p_aux text)
returns numeric language sql stable security definer set search_path='' as $$
select case when b.aux_skill_code=p_aux then .10+greatest(0,b.aux_skill_level-1)*.02 else 0 end from public.character_spirit_beast_state_v267 st join public.character_spirit_beasts_v267 b on b.id=st.active_beast_id and b.character_id=st.character_id where st.character_id=p_character
$$;

-- ==================== SOURCE INTEGRATION ====================
create or replace function public.spirit_beast_process_exploration_v267(p_character uuid,p_run_id uuid,p_status text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_old jsonb;v_region text;v_result jsonb;v_rate numeric;s public.spirit_beast_settings_v267%rowtype;v_food integer:=0;v_bonus numeric:=0;
begin
 if p_run_id is null then return '{}'::jsonb;end if;v_old:=public.spirit_beast_source_get_v267(p_character,'exploration',p_run_id::text);if v_old is not null then return v_old;end if;
 select region_code into v_region from public.exploration_runs_v262 where id=p_run_id and character_id=p_character;perform public.spirit_beast_gain_active_exp_v267(p_character,case when p_status in('completed','paused','retreated') then 35 else 12 end,case when p_status in('completed','paused') then 1 else 0 end);
 select * into s from public.spirit_beast_settings_v267 where singleton_id=1;v_bonus:=coalesce(public.spirit_beast_aux_bonus_v267(p_character,'aux_treasure'),0);v_rate:=least(.95,s.exploration_encounter_rate*(1+v_bonus));
 if p_status in('completed','paused','retreated') and random()<v_rate then v_result:=public.spirit_beast_create_encounter_v267(p_character,v_region,'exploration',p_run_id::text);else v_food:=1+floor(random()*2)::integer+case when coalesce(public.spirit_beast_aux_bonus_v267(p_character,'aux_herb'),0)>0 then 1 else 0 end;perform public.tianxu_inventory_adjust_v255(p_character,'spirit_beast_food',v_food);v_result:=jsonb_build_object('status','resource','food',v_food,'message','游历途中收集到灵兽口粮。');end if;
 return public.spirit_beast_source_put_v267(p_character,'exploration',p_run_id::text,v_result);
end $$;

create or replace function public.spirit_beast_random_base_egg_v267()
returns text language sql volatile security definer set search_path='' as $$select item_code from public.spirit_beast_egg_map_v267 where enabled and rarity='rare' order by random() limit 1$$;
create or replace function public.spirit_beast_random_mythic_egg_v267()
returns text language sql volatile security definer set search_path='' as $$select item_code from public.spirit_beast_egg_map_v267 where enabled and rarity='legendary' order by random() limit 1$$;
create or replace function public.spirit_beast_random_essence_v267()
returns text language sql volatile security definer set search_path='' as $$select x from unnest(array['spirit_beast_essence_fire','spirit_beast_essence_thunder','spirit_beast_essence_wood','spirit_beast_essence_water','spirit_beast_essence_metal','spirit_beast_essence_wind','spirit_beast_essence_ice','spirit_beast_essence_earth']) x order by random() limit 1$$;

create or replace function public.spirit_beast_process_secret_claim_v267(p_character uuid,p_run_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_old jsonb;s public.spirit_beast_settings_v267%rowtype;v_egg text;v_food integer;v_soul integer;v_ess text;v_ess_qty integer:=0;v_bonus numeric:=0;v_rate numeric;v_result jsonb;
begin
 if p_run_id is null then return '{}'::jsonb;end if;v_old:=public.spirit_beast_source_get_v267(p_character,'secret_realm',p_run_id::text);if v_old is not null then return v_old;end if;
 perform public.spirit_beast_gain_active_exp_v267(p_character,55,1);select * into s from public.spirit_beast_settings_v267 where singleton_id=1;v_bonus:=coalesce(public.spirit_beast_aux_bonus_v267(p_character,'aux_secret'),0);v_rate:=least(.50,s.secret_egg_rate*(1+v_bonus));v_food:=2+floor(random()*3)::integer+case when coalesce(public.spirit_beast_aux_bonus_v267(p_character,'aux_herb'),0)>0 then 1 else 0 end;v_soul:=1+floor(random()*4)::integer;
 perform public.tianxu_inventory_adjust_v255(p_character,'spirit_beast_food',v_food);perform public.tianxu_inventory_adjust_v255(p_character,'spirit_beast_soul',v_soul);
 if random()<v_rate then v_egg:=public.spirit_beast_random_base_egg_v267();perform public.tianxu_inventory_adjust_v255(p_character,v_egg,1);end if;
 if random()<.35 then v_ess:=public.spirit_beast_random_essence_v267();v_ess_qty:=1;perform public.tianxu_inventory_adjust_v255(p_character,v_ess,1);end if;
 v_result:=jsonb_build_object('status','reward','food',v_food,'soul',v_soul,'egg_item_code',v_egg,'essence_item_code',v_ess,'essence_quantity',v_ess_qty);
 return public.spirit_beast_source_put_v267(p_character,'secret_realm',p_run_id::text,v_result);
end $$;

create or replace function public.spirit_beast_process_world_boss_run_v267(p_run_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r record;v_old jsonb;s public.spirit_beast_settings_v267%rowtype;v_status text;v_egg text;v_soul integer;v_ess text;v_ess_qty integer;v_bonus numeric;v_result jsonb;v_count integer:=0;
begin
 if p_run_id is null then return '{}'::jsonb;end if;select status into v_status from public.world_boss_runs_bwboss01 where id=p_run_id;select * into s from public.spirit_beast_settings_v267 where singleton_id=1;
 for r in select distinct character_id from public.world_boss_contributions_bwboss01 where run_id=p_run_id loop
  v_old:=public.spirit_beast_source_get_v267(r.character_id,'world_boss',p_run_id::text);if v_old is not null then continue;end if;v_count:=v_count+1;perform public.spirit_beast_gain_active_exp_v267(r.character_id,case when v_status='victory' then 90 else 35 end,case when v_status='victory' then 2 else 0 end);
  v_soul:=case when v_status='victory' then 5+floor(random()*6)::integer else 2 end;perform public.tianxu_inventory_adjust_v255(r.character_id,'spirit_beast_soul',v_soul);v_ess:=null;v_ess_qty:=0;v_egg:=null;
  if v_status='victory' then v_ess:=public.spirit_beast_random_essence_v267();v_ess_qty:=1+floor(random()*2)::integer;perform public.tianxu_inventory_adjust_v255(r.character_id,v_ess,v_ess_qty);v_bonus:=coalesce(public.spirit_beast_aux_bonus_v267(r.character_id,'aux_boss'),0);
    if random()<least(.20,s.boss_mythic_egg_rate*(1+v_bonus)) then v_egg:=public.spirit_beast_random_mythic_egg_v267();elsif random()<least(.60,s.boss_egg_rate*(1+v_bonus)) then v_egg:=public.spirit_beast_random_base_egg_v267();end if;if v_egg is not null then perform public.tianxu_inventory_adjust_v255(r.character_id,v_egg,1);end if;
  end if;
  v_result:=jsonb_build_object('status','reward','victory',v_status='victory','soul',v_soul,'egg_item_code',v_egg,'essence_item_code',v_ess,'essence_quantity',v_ess_qty);perform public.spirit_beast_source_put_v267(r.character_id,'world_boss',p_run_id::text,v_result);
 end loop;return jsonb_build_object('processed_characters',v_count);
end $$;

-- ==================== PLAYER RPC ====================
create or replace function public.get_spirit_beast_hub_v267()
returns jsonb language plpgsql volatile security definer set search_path='' as $$
declare v_char uuid:=public.spirit_beast_active_character_v267();s public.spirit_beast_settings_v267%rowtype;v_state jsonb;v_beasts jsonb;v_enc jsonb;v_inv jsonb;v_codex jsonb;v_species jsonb;v_aux jsonb;v_count integer;v_capacity integer;
begin
 perform public.spirit_beast_ensure_state_v267(v_char);select * into s from public.spirit_beast_settings_v267 where singleton_id=1;update public.spirit_beast_encounters_v267 set status='expired',resolved_at=clock_timestamp() where character_id=v_char and status='pending' and expires_at<=clock_timestamp();
 select count(*) into v_count from public.character_spirit_beasts_v267 where character_id=v_char;v_capacity:=public.spirit_beast_capacity_v267(v_char);
 select jsonb_build_object('active_beast_id',st.active_beast_id,'stable_level',st.stable_level,'capacity',v_capacity,'owned_count',v_count,'last_supply_day',st.last_supply_day,'capture_pity',st.capture_pity,'codex_claim_mask',st.codex_claim_mask) into v_state from public.character_spirit_beast_state_v267 st where st.character_id=v_char;
 select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'species_code',b.species_code,'lineage_code',sp.lineage_code,'species_name',sp.name,'display_name',coalesce(nullif(b.nickname,''),sp.name),'nickname',b.nickname,'element',sp.element,'rarity',sp.rarity,'evolution_stage',sp.evolution_stage,'description',sp.description,'level',b.level,'exp',b.exp,'level_cap',least(90,b.beast_realm_order*10),'next_level_exp',100+b.level*50,'beast_realm_order',b.beast_realm_order,'bloodline',b.bloodline,'personality_code',b.personality_code,'personality_name',pr.name,'personality_description',pr.description,'intimacy',b.intimacy,'skill_level',b.skill_level,'innate_skill_code',sp.innate_skill_code,'innate_skill_name',sk.name,'innate_skill_description',sk.description,'aux_skill_code',b.aux_skill_code,'aux_skill_name',ask.name,'aux_skill_level',b.aux_skill_level,'locked',b.locked,'last_interact_day',b.last_interact_day,'score',public.spirit_beast_score_v267(b.id),'is_active',st.active_beast_id=b.id,'next_species_code',sp.next_species_code,'obtained_at',b.obtained_at) order by (st.active_beast_id=b.id) desc,public.spirit_beast_score_v267(b.id) desc),'[]'::jsonb) into v_beasts from public.character_spirit_beasts_v267 b join public.spirit_beast_species_v267 sp on sp.species_code=b.species_code join public.spirit_beast_personalities_v267 pr on pr.personality_code=b.personality_code join public.spirit_beast_skills_v267 sk on sk.skill_code=sp.innate_skill_code left join public.spirit_beast_skills_v267 ask on ask.skill_code=b.aux_skill_code join public.character_spirit_beast_state_v267 st on st.character_id=b.character_id where b.character_id=v_char;
 select jsonb_build_object('id',e.id,'species_code',e.species_code,'species_name',sp.name,'element',sp.element,'rarity',sp.rarity,'description',sp.description,'region_code',e.region_code,'source_type',e.source_type,'attempts',e.attempts,'max_attempts',s.max_capture_attempts,'bloodline_hint',case when e.bloodline>=90 then '血脉气息极纯' when e.bloodline>=75 then '血脉气息不凡' else '血脉气息平稳' end,'base_chance',e.base_chance,'expires_at',e.expires_at) into v_enc from public.spirit_beast_encounters_v267 e join public.spirit_beast_species_v267 sp on sp.species_code=e.species_code where e.character_id=v_char and e.status='pending' and e.expires_at>clock_timestamp() order by e.created_at desc limit 1;
 select coalesce(jsonb_agg(jsonb_build_object('code',d.code,'name',d.name,'rarity',d.rarity,'quantity',ci.quantity) order by d.code),'[]'::jsonb) into v_inv from public.character_inventory ci join public.item_definitions d on d.id=ci.item_definition_id where ci.character_id=v_char and ci.quantity>0 and d.code like 'spirit_beast_%';
 select coalesce(jsonb_agg(jsonb_build_object('species_code',sp.species_code,'lineage_code',sp.lineage_code,'name',sp.name,'element',sp.element,'rarity',sp.rarity,'evolution_stage',sp.evolution_stage,'description',sp.description,'unlocked',c.species_code is not null,'highest_bloodline',c.highest_bloodline,'highest_level',c.highest_level,'times_obtained',c.times_obtained) order by sp.rarity_score,sp.lineage_code,sp.evolution_stage),'[]'::jsonb) into v_codex from public.spirit_beast_species_v267 sp left join public.character_spirit_beast_codex_v267 c on c.character_id=v_char and c.species_code=sp.species_code where sp.enabled;
 select coalesce(jsonb_agg(to_jsonb(sp) order by sp.rarity_score,sp.lineage_code,sp.evolution_stage),'[]'::jsonb) into v_species from public.spirit_beast_species_v267 sp where sp.enabled;
 select coalesce(jsonb_agg(jsonb_build_object('skill_code',skill_code,'name',name,'description',description) order by skill_code),'[]'::jsonb) into v_aux from public.spirit_beast_skills_v267 where category='aux' and enabled;
 return jsonb_build_object('status',case when s.enabled then 'ok' else 'disabled' end,'build','SPIRIT_BEAST_V267_COMPLETE','settings',jsonb_build_object('daily_supply_food',s.daily_supply_food,'daily_supply_talisman',s.daily_supply_talisman,'max_stable_level',s.max_stable_level,'feed_exp_per_food',s.feed_exp_per_food,'max_feed_per_call',s.max_feed_per_call),'state',v_state,'beasts',v_beasts,'pending_encounter',v_enc,'inventory',v_inv,'codex',v_codex,'species',v_species,'aux_skills',v_aux,'codex_unlocked',(select count(*) from public.character_spirit_beast_codex_v267 where character_id=v_char),'codex_total',(select count(*) from public.spirit_beast_species_v267 where enabled),'server_day',(clock_timestamp() at time zone 'Asia/Shanghai')::date);
end $$;

create or replace function public.spirit_beast_claim_daily_supply_v267(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.spirit_beast_active_character_v267();v_old jsonb;s public.spirit_beast_settings_v267%rowtype;v_day date:=(clock_timestamp() at time zone 'Asia/Shanghai')::date;v_result jsonb;
begin v_old:=public.spirit_beast_request_get_v267(v_char,p_request_id,'daily_supply');if v_old is not null then return v_old;end if;perform public.spirit_beast_ensure_state_v267(v_char);select * into s from public.spirit_beast_settings_v267 where singleton_id=1;perform 1 from public.character_spirit_beast_state_v267 where character_id=v_char for update;if (select last_supply_day from public.character_spirit_beast_state_v267 where character_id=v_char)=v_day then raise exception 'SPIRIT_BEAST_DAILY_SUPPLY_CLAIMED';end if;perform public.tianxu_inventory_adjust_v255(v_char,'spirit_beast_food',s.daily_supply_food);perform public.tianxu_inventory_adjust_v255(v_char,'spirit_beast_talisman',s.daily_supply_talisman);update public.character_spirit_beast_state_v267 set last_supply_day=v_day,updated_at=clock_timestamp() where character_id=v_char;v_result:=jsonb_build_object('status','ok','food',s.daily_supply_food,'talisman',s.daily_supply_talisman,'day',v_day);return public.spirit_beast_request_put_v267(v_char,p_request_id,'daily_supply',v_result);end $$;

create or replace function public.spirit_beast_capture_v267(p_encounter_id uuid,p_talisman_code text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.spirit_beast_active_character_v267();v_old jsonb;e public.spirit_beast_encounters_v267%rowtype;sp public.spirit_beast_species_v267%rowtype;s public.spirit_beast_settings_v267%rowtype;st public.character_spirit_beast_state_v267%rowtype;v_pity integer:=0;v_bonus numeric:=0;v_talisman_bonus numeric:=0;v_chance numeric;v_success boolean;v_id uuid;v_key text;v_result jsonb;
begin
 v_old:=public.spirit_beast_request_get_v267(v_char,p_request_id,'capture');if v_old is not null then return v_old;end if;select * into s from public.spirit_beast_settings_v267 where singleton_id=1;if not s.enabled or not s.capture_enabled then raise exception 'SPIRIT_BEAST_CAPTURE_DISABLED';end if;perform public.spirit_beast_ensure_state_v267(v_char);select * into e from public.spirit_beast_encounters_v267 where id=p_encounter_id and character_id=v_char for update;if e.id is null or e.status<>'pending' then raise exception 'SPIRIT_BEAST_ENCOUNTER_NOT_ACTIVE';end if;if e.expires_at<=clock_timestamp() then update public.spirit_beast_encounters_v267 set status='expired',resolved_at=clock_timestamp() where id=e.id;raise exception 'SPIRIT_BEAST_ENCOUNTER_EXPIRED';end if;select * into sp from public.spirit_beast_species_v267 where species_code=e.species_code;select * into st from public.character_spirit_beast_state_v267 where character_id=v_char for update;v_key:=sp.rarity;v_pity:=coalesce((st.capture_pity->>v_key)::integer,0);
 p_talisman_code:=coalesce(nullif(p_talisman_code,''),'none');if p_talisman_code='spirit_beast_talisman' then perform public.tianxu_inventory_adjust_v255(v_char,p_talisman_code,-1);v_talisman_bonus:=.15;elsif p_talisman_code='spirit_beast_talisman_high' then perform public.tianxu_inventory_adjust_v255(v_char,p_talisman_code,-1);v_talisman_bonus:=.30;elsif p_talisman_code<>'none' then raise exception 'SPIRIT_BEAST_TALISMAN_INVALID';end if;
 v_bonus:=coalesce(public.spirit_beast_aux_bonus_v267(v_char,'aux_capture'),0)*.30;v_chance:=least(.95,e.base_chance+v_talisman_bonus+least(s.pity_max_bonus,v_pity*s.pity_bonus_per_fail)+v_bonus);v_success:=random()<v_chance;
 if v_success then v_id:=public.spirit_beast_create_instance_v267(v_char,e.species_code,e.bloodline,'capture',e.id::text);update public.spirit_beast_encounters_v267 set status='captured',attempts=attempts+1,resolved_at=clock_timestamp() where id=e.id;update public.character_spirit_beast_state_v267 set capture_pity=jsonb_set(capture_pity,array[v_key],'0'::jsonb,true),updated_at=clock_timestamp() where character_id=v_char;v_result:=jsonb_build_object('status','captured','beast_id',v_id,'species_name',sp.name,'bloodline',e.bloodline,'chance',round(v_chance,4));
 else update public.spirit_beast_encounters_v267 set attempts=attempts+1,status=case when attempts+1>=s.max_capture_attempts then 'fled' else 'pending' end,resolved_at=case when attempts+1>=s.max_capture_attempts then clock_timestamp() else null end where id=e.id;update public.character_spirit_beast_state_v267 set capture_pity=jsonb_set(capture_pity,array[v_key],to_jsonb(v_pity+1),true),updated_at=clock_timestamp() where character_id=v_char;v_result:=jsonb_build_object('status',case when e.attempts+1>=s.max_capture_attempts then 'fled' else 'failed' end,'species_name',sp.name,'chance',round(v_chance,4),'attempts',e.attempts+1,'max_attempts',s.max_capture_attempts);end if;
 return public.spirit_beast_request_put_v267(v_char,p_request_id,'capture',v_result);
end $$;

create or replace function public.spirit_beast_hatch_egg_v267(p_item_code text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.spirit_beast_active_character_v267();v_old jsonb;m public.spirit_beast_egg_map_v267%rowtype;v_blood integer;v_id uuid;v_name text;v_result jsonb;
begin v_old:=public.spirit_beast_request_get_v267(v_char,p_request_id,'hatch');if v_old is not null then return v_old;end if;select * into m from public.spirit_beast_egg_map_v267 where item_code=p_item_code and enabled;if m.item_code is null then raise exception 'SPIRIT_BEAST_EGG_INVALID';end if;perform public.tianxu_inventory_adjust_v255(v_char,p_item_code,-1);v_blood:=m.min_bloodline+floor(random()*(m.max_bloodline-m.min_bloodline+1))::integer;v_id:=public.spirit_beast_create_instance_v267(v_char,m.species_code,v_blood,'egg',p_item_code);select name into v_name from public.spirit_beast_species_v267 where species_code=m.species_code;v_result:=jsonb_build_object('status','hatched','beast_id',v_id,'species_name',v_name,'bloodline',v_blood);return public.spirit_beast_request_put_v267(v_char,p_request_id,'hatch',v_result);end $$;

create or replace function public.spirit_beast_set_active_v267(p_beast_id uuid,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_char uuid:=public.spirit_beast_active_character_v267();v_old jsonb;v_result jsonb;begin v_old:=public.spirit_beast_request_get_v267(v_char,p_request_id,'set_active');if v_old is not null then return v_old;end if;if p_beast_id is not null and not exists(select 1 from public.character_spirit_beasts_v267 where id=p_beast_id and character_id=v_char) then raise exception 'SPIRIT_BEAST_NOT_OWNED';end if;perform public.spirit_beast_ensure_state_v267(v_char);update public.character_spirit_beast_state_v267 set active_beast_id=p_beast_id,updated_at=clock_timestamp() where character_id=v_char;v_result:=jsonb_build_object('status','ok','active_beast_id',p_beast_id);return public.spirit_beast_request_put_v267(v_char,p_request_id,'set_active',v_result);end$$;

create or replace function public.spirit_beast_feed_v267(p_beast_id uuid,p_food_count integer,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_char uuid:=public.spirit_beast_active_character_v267();v_old jsonb;s public.spirit_beast_settings_v267%rowtype;v_result jsonb;begin v_old:=public.spirit_beast_request_get_v267(v_char,p_request_id,'feed');if v_old is not null then return v_old;end if;select * into s from public.spirit_beast_settings_v267 where singleton_id=1;if coalesce(p_food_count,0)<1 or p_food_count>s.max_feed_per_call then raise exception 'SPIRIT_BEAST_FEED_COUNT_INVALID';end if;if not exists(select 1 from public.character_spirit_beasts_v267 where id=p_beast_id and character_id=v_char) then raise exception 'SPIRIT_BEAST_NOT_OWNED';end if;perform public.tianxu_inventory_adjust_v255(v_char,'spirit_beast_food',-p_food_count);v_result:=public.spirit_beast_gain_exp_v267(p_beast_id,p_food_count*s.feed_exp_per_food,least(3,greatest(1,p_food_count/5)));return public.spirit_beast_request_put_v267(v_char,p_request_id,'feed',jsonb_build_object('status','ok','food_used',p_food_count,'growth',v_result));end$$;

create or replace function public.spirit_beast_interact_v267(p_beast_id uuid,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_char uuid:=public.spirit_beast_active_character_v267();v_old jsonb;v_day date:=(clock_timestamp() at time zone 'Asia/Shanghai')::date;b public.character_spirit_beasts_v267%rowtype;v_result jsonb;begin v_old:=public.spirit_beast_request_get_v267(v_char,p_request_id,'interact');if v_old is not null then return v_old;end if;select * into b from public.character_spirit_beasts_v267 where id=p_beast_id and character_id=v_char for update;if b.id is null then raise exception 'SPIRIT_BEAST_NOT_OWNED';end if;if b.last_interact_day=v_day then raise exception 'SPIRIT_BEAST_INTERACT_DAILY_DONE';end if;perform public.spirit_beast_gain_exp_v267(p_beast_id,30,3);update public.character_spirit_beasts_v267 set last_interact_day=v_day,updated_at=clock_timestamp() where id=p_beast_id;v_result:=jsonb_build_object('status','ok','intimacy_gain',3,'exp_gain',30,'day',v_day);return public.spirit_beast_request_put_v267(v_char,p_request_id,'interact',v_result);end$$;
create or replace function public.spirit_beast_rename_v267(p_beast_id uuid,p_name text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_char uuid:=public.spirit_beast_active_character_v267();v_old jsonb;v_name text;v_result jsonb;begin v_old:=public.spirit_beast_request_get_v267(v_char,p_request_id,'rename');if v_old is not null then return v_old;end if;v_name:=trim(coalesce(p_name,''));if length(v_name)<1 or length(v_name)>12 then raise exception 'SPIRIT_BEAST_NAME_INVALID';end if;update public.character_spirit_beasts_v267 set nickname=v_name,updated_at=clock_timestamp() where id=p_beast_id and character_id=v_char;if not found then raise exception 'SPIRIT_BEAST_NOT_OWNED';end if;v_result:=jsonb_build_object('status','ok','name',v_name);return public.spirit_beast_request_put_v267(v_char,p_request_id,'rename',v_result);end$$;

create or replace function public.spirit_beast_set_lock_v267(p_beast_id uuid,p_locked boolean,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_char uuid:=public.spirit_beast_active_character_v267();v_old jsonb;v_result jsonb;begin v_old:=public.spirit_beast_request_get_v267(v_char,p_request_id,'set_lock');if v_old is not null then return v_old;end if;update public.character_spirit_beasts_v267 set locked=coalesce(p_locked,false),updated_at=clock_timestamp() where id=p_beast_id and character_id=v_char;if not found then raise exception 'SPIRIT_BEAST_NOT_OWNED';end if;v_result:=jsonb_build_object('status','ok','locked',coalesce(p_locked,false));return public.spirit_beast_request_put_v267(v_char,p_request_id,'set_lock',v_result);end$$;

create or replace function public.spirit_beast_breakthrough_v267(p_beast_id uuid,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_char uuid:=public.spirit_beast_active_character_v267();v_old jsonb;b public.character_spirit_beasts_v267%rowtype;v_owner integer;v_soul integer;v_stones bigint;v_result jsonb;begin v_old:=public.spirit_beast_request_get_v267(v_char,p_request_id,'breakthrough');if v_old is not null then return v_old;end if;select * into b from public.character_spirit_beasts_v267 where id=p_beast_id and character_id=v_char for update;if b.id is null then raise exception 'SPIRIT_BEAST_NOT_OWNED';end if;if b.beast_realm_order>=9 then raise exception 'SPIRIT_BEAST_REALM_MAX';end if;if b.level<b.beast_realm_order*10 then raise exception 'SPIRIT_BEAST_LEVEL_CAP_NOT_REACHED';end if;v_owner:=public.spirit_beast_character_realm_order_v267(v_char);if v_owner<=b.beast_realm_order then raise exception 'SPIRIT_BEAST_OWNER_REALM_REQUIRED';end if;v_soul:=10*b.beast_realm_order*b.beast_realm_order;v_stones:=5000::bigint*b.beast_realm_order*b.beast_realm_order;perform public.tianxu_inventory_adjust_v255(v_char,'spirit_beast_soul',-v_soul);perform public.tianxu_inventory_adjust_v255(v_char,'spirit_stone',-v_stones);update public.character_spirit_beasts_v267 set beast_realm_order=beast_realm_order+1,updated_at=clock_timestamp() where id=b.id;v_result:=jsonb_build_object('status','ok','beast_id',b.id,'realm_order',b.beast_realm_order+1,'soul_cost',v_soul,'spirit_stone_cost',v_stones);return public.spirit_beast_request_put_v267(v_char,p_request_id,'breakthrough',v_result);end$$;

create or replace function public.spirit_beast_evolve_v267(p_beast_id uuid,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_char uuid:=public.spirit_beast_active_character_v267();v_old jsonb;b public.character_spirit_beasts_v267%rowtype;e public.spirit_beast_evolutions_v267%rowtype;v_owner integer;v_name text;v_result jsonb;begin v_old:=public.spirit_beast_request_get_v267(v_char,p_request_id,'evolve');if v_old is not null then return v_old;end if;select * into b from public.character_spirit_beasts_v267 where id=p_beast_id and character_id=v_char for update;if b.id is null then raise exception 'SPIRIT_BEAST_NOT_OWNED';end if;select * into e from public.spirit_beast_evolutions_v267 where from_species_code=b.species_code and enabled;if e.from_species_code is null then raise exception 'SPIRIT_BEAST_NO_EVOLUTION';end if;v_owner:=public.spirit_beast_character_realm_order_v267(v_char);if v_owner<e.min_owner_realm_order then raise exception 'SPIRIT_BEAST_EVOLVE_OWNER_REALM_REQUIRED';end if;if b.level<e.min_level then raise exception 'SPIRIT_BEAST_EVOLVE_LEVEL_REQUIRED';end if;if b.bloodline<e.min_bloodline then raise exception 'SPIRIT_BEAST_EVOLVE_BLOODLINE_REQUIRED';end if;if b.intimacy<e.min_intimacy then raise exception 'SPIRIT_BEAST_EVOLVE_INTIMACY_REQUIRED';end if;perform public.tianxu_inventory_adjust_v255(v_char,'spirit_beast_soul',-e.soul_cost);perform public.tianxu_inventory_adjust_v255(v_char,e.essence_item_code,-e.essence_cost);perform public.tianxu_inventory_adjust_v255(v_char,'spirit_stone',-e.spirit_stone_cost);update public.character_spirit_beasts_v267 set species_code=e.to_species_code,locked=true,updated_at=clock_timestamp() where id=b.id;perform public.spirit_beast_update_codex_v267(b.id);select name into v_name from public.spirit_beast_species_v267 where species_code=e.to_species_code;v_result:=jsonb_build_object('status','evolved','beast_id',b.id,'species_code',e.to_species_code,'species_name',v_name);return public.spirit_beast_request_put_v267(v_char,p_request_id,'evolve',v_result);end$$;

create or replace function public.spirit_beast_release_v267(p_beast_id uuid,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_char uuid:=public.spirit_beast_active_character_v267();v_old jsonb;b public.character_spirit_beasts_v267%rowtype;sp public.spirit_beast_species_v267%rowtype;v_soul integer;v_result jsonb;begin v_old:=public.spirit_beast_request_get_v267(v_char,p_request_id,'release');if v_old is not null then return v_old;end if;select * into b from public.character_spirit_beasts_v267 where id=p_beast_id and character_id=v_char for update;if b.id is null then raise exception 'SPIRIT_BEAST_NOT_OWNED';end if;if b.locked then raise exception 'SPIRIT_BEAST_LOCKED';end if;if exists(select 1 from public.character_spirit_beast_state_v267 where character_id=v_char and active_beast_id=b.id) then raise exception 'SPIRIT_BEAST_ACTIVE_CANNOT_RELEASE';end if;select * into sp from public.spirit_beast_species_v267 where species_code=b.species_code;v_soul:=greatest(5,sp.rarity_score*4+sp.evolution_stage*6+floor(b.bloodline/10)::integer+floor(b.level/5)::integer);delete from public.character_spirit_beasts_v267 where id=b.id;perform public.tianxu_inventory_adjust_v255(v_char,'spirit_beast_soul',v_soul);v_result:=jsonb_build_object('status','released','species_name',sp.name,'soul_gained',v_soul);return public.spirit_beast_request_put_v267(v_char,p_request_id,'release',v_result);end$$;

create or replace function public.spirit_beast_inherit_bloodline_v267(p_target_beast_id uuid,p_donor_beast_id uuid,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_char uuid:=public.spirit_beast_active_character_v267();v_old jsonb;t public.character_spirit_beasts_v267%rowtype;d public.character_spirit_beasts_v267%rowtype;ts public.spirit_beast_species_v267%rowtype;ds public.spirit_beast_species_v267%rowtype;v_gain integer;v_new integer;v_result jsonb;begin v_old:=public.spirit_beast_request_get_v267(v_char,p_request_id,'inherit');if v_old is not null then return v_old;end if;if p_target_beast_id=p_donor_beast_id then raise exception 'SPIRIT_BEAST_INHERIT_SAME_BEAST';end if;select * into t from public.character_spirit_beasts_v267 where id=p_target_beast_id and character_id=v_char for update;select * into d from public.character_spirit_beasts_v267 where id=p_donor_beast_id and character_id=v_char for update;if t.id is null or d.id is null then raise exception 'SPIRIT_BEAST_NOT_OWNED';end if;if d.locked then raise exception 'SPIRIT_BEAST_DONOR_LOCKED';end if;if exists(select 1 from public.character_spirit_beast_state_v267 where character_id=v_char and active_beast_id=d.id) then raise exception 'SPIRIT_BEAST_DONOR_ACTIVE';end if;select * into ts from public.spirit_beast_species_v267 where species_code=t.species_code;select * into ds from public.spirit_beast_species_v267 where species_code=d.species_code;if ts.lineage_code<>ds.lineage_code then raise exception 'SPIRIT_BEAST_INHERIT_LINEAGE_MISMATCH';end if;v_gain:=case when d.bloodline>t.bloodline then greatest(1,floor((d.bloodline-t.bloodline)*.35)::integer) else 1 end;v_new:=least(99,t.bloodline+v_gain);if d.bloodline=100 and t.bloodline>=99 then v_new:=100;end if;delete from public.character_spirit_beasts_v267 where id=d.id;update public.character_spirit_beasts_v267 set bloodline=v_new,updated_at=clock_timestamp() where id=t.id;perform public.spirit_beast_update_codex_v267(t.id);v_result:=jsonb_build_object('status','ok','target_beast_id',t.id,'old_bloodline',t.bloodline,'new_bloodline',v_new,'donor_consumed',d.id);return public.spirit_beast_request_put_v267(v_char,p_request_id,'inherit',v_result);end$$;

create or replace function public.spirit_beast_reroll_personality_v267(p_beast_id uuid,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_char uuid:=public.spirit_beast_active_character_v267();v_old jsonb;b public.character_spirit_beasts_v267%rowtype;v_new text;v_name text;v_result jsonb;begin v_old:=public.spirit_beast_request_get_v267(v_char,p_request_id,'reroll_personality');if v_old is not null then return v_old;end if;select * into b from public.character_spirit_beasts_v267 where id=p_beast_id and character_id=v_char for update;if b.id is null then raise exception 'SPIRIT_BEAST_NOT_OWNED';end if;perform public.tianxu_inventory_adjust_v255(v_char,'spirit_beast_marrow_dew',-1);select personality_code,name into v_new,v_name from public.spirit_beast_personalities_v267 where enabled and personality_code<>b.personality_code order by random() limit 1;update public.character_spirit_beasts_v267 set personality_code=v_new,updated_at=clock_timestamp() where id=b.id;v_result:=jsonb_build_object('status','ok','personality_code',v_new,'personality_name',v_name);return public.spirit_beast_request_put_v267(v_char,p_request_id,'reroll_personality',v_result);end$$;

create or replace function public.spirit_beast_learn_aux_skill_v267(p_beast_id uuid,p_skill_code text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_char uuid:=public.spirit_beast_active_character_v267();v_old jsonb;b public.character_spirit_beasts_v267%rowtype;v_name text;v_result jsonb;begin v_old:=public.spirit_beast_request_get_v267(v_char,p_request_id,'learn_aux');if v_old is not null then return v_old;end if;select * into b from public.character_spirit_beasts_v267 where id=p_beast_id and character_id=v_char for update;if b.id is null then raise exception 'SPIRIT_BEAST_NOT_OWNED';end if;select name into v_name from public.spirit_beast_skills_v267 where skill_code=p_skill_code and category='aux' and enabled;if v_name is null then raise exception 'SPIRIT_BEAST_AUX_SKILL_INVALID';end if;perform public.tianxu_inventory_adjust_v255(v_char,'spirit_beast_skill_scroll',-1);update public.character_spirit_beasts_v267 set aux_skill_code=p_skill_code,aux_skill_level=1,updated_at=clock_timestamp() where id=b.id;v_result:=jsonb_build_object('status','ok','aux_skill_code',p_skill_code,'aux_skill_name',v_name,'aux_skill_level',1);return public.spirit_beast_request_put_v267(v_char,p_request_id,'learn_aux',v_result);end$$;

create or replace function public.spirit_beast_upgrade_skill_v267(p_beast_id uuid,p_slot text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_char uuid:=public.spirit_beast_active_character_v267();v_old jsonb;b public.character_spirit_beasts_v267%rowtype;v_level integer;v_cost integer;v_result jsonb;begin v_old:=public.spirit_beast_request_get_v267(v_char,p_request_id,'upgrade_skill');if v_old is not null then return v_old;end if;select * into b from public.character_spirit_beasts_v267 where id=p_beast_id and character_id=v_char for update;if b.id is null then raise exception 'SPIRIT_BEAST_NOT_OWNED';end if;if p_slot='innate' then v_level:=b.skill_level;if v_level>=10 then raise exception 'SPIRIT_BEAST_SKILL_MAX';end if;v_cost:=5*v_level*v_level;perform public.tianxu_inventory_adjust_v255(v_char,'spirit_beast_soul',-v_cost);update public.character_spirit_beasts_v267 set skill_level=skill_level+1,updated_at=clock_timestamp() where id=b.id;v_result:=jsonb_build_object('status','ok','slot','innate','level',v_level+1,'soul_cost',v_cost);elsif p_slot='aux' then if b.aux_skill_code is null then raise exception 'SPIRIT_BEAST_AUX_SKILL_EMPTY';end if;v_level:=b.aux_skill_level;if v_level>=10 then raise exception 'SPIRIT_BEAST_SKILL_MAX';end if;v_cost:=3*greatest(1,v_level)*greatest(1,v_level);perform public.tianxu_inventory_adjust_v255(v_char,'spirit_beast_soul',-v_cost);perform public.tianxu_inventory_adjust_v255(v_char,'spirit_beast_skill_scroll',-1);update public.character_spirit_beasts_v267 set aux_skill_level=aux_skill_level+1,updated_at=clock_timestamp() where id=b.id;v_result:=jsonb_build_object('status','ok','slot','aux','level',v_level+1,'soul_cost',v_cost);else raise exception 'SPIRIT_BEAST_SKILL_SLOT_INVALID';end if;return public.spirit_beast_request_put_v267(v_char,p_request_id,'upgrade_skill',v_result);end$$;

create or replace function public.spirit_beast_upgrade_stable_v267(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_char uuid:=public.spirit_beast_active_character_v267();v_old jsonb;s public.spirit_beast_settings_v267%rowtype;st public.character_spirit_beast_state_v267%rowtype;v_soul integer;v_stones bigint;v_result jsonb;begin v_old:=public.spirit_beast_request_get_v267(v_char,p_request_id,'upgrade_stable');if v_old is not null then return v_old;end if;perform public.spirit_beast_ensure_state_v267(v_char);select * into s from public.spirit_beast_settings_v267 where singleton_id=1;select * into st from public.character_spirit_beast_state_v267 where character_id=v_char for update;if st.stable_level>=s.max_stable_level then raise exception 'SPIRIT_BEAST_STABLE_MAX';end if;v_soul:=20*st.stable_level;v_stones:=20000::bigint*st.stable_level*st.stable_level;perform public.tianxu_inventory_adjust_v255(v_char,'spirit_beast_soul',-v_soul);perform public.tianxu_inventory_adjust_v255(v_char,'spirit_stone',-v_stones);update public.character_spirit_beast_state_v267 set stable_level=stable_level+1,updated_at=clock_timestamp() where character_id=v_char;v_result:=jsonb_build_object('status','ok','stable_level',st.stable_level+1,'capacity',s.base_capacity+st.stable_level*s.capacity_per_stable_level,'soul_cost',v_soul,'spirit_stone_cost',v_stones);return public.spirit_beast_request_put_v267(v_char,p_request_id,'upgrade_stable',v_result);end$$;

create or replace function public.spirit_beast_claim_codex_reward_v267(p_milestone integer,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.spirit_beast_active_character_v267();v_old jsonb;st public.character_spirit_beast_state_v267%rowtype;v_count integer;v_bit integer;v_food integer:=0;v_soul integer:=0;v_talisman integer:=0;v_high integer:=0;v_marrow integer:=0;v_scroll integer:=0;v_result jsonb;
begin
 v_old:=public.spirit_beast_request_get_v267(v_char,p_request_id,'codex_reward:'||coalesce(p_milestone,0)::text);if v_old is not null then return v_old;end if;
 perform public.spirit_beast_ensure_state_v267(v_char);select * into st from public.character_spirit_beast_state_v267 where character_id=v_char for update;select count(*) into v_count from public.character_spirit_beast_codex_v267 where character_id=v_char;
 if p_milestone=10 then v_bit:=1;v_food:=20;v_soul:=20;v_talisman:=3;
 elsif p_milestone=20 then v_bit:=2;v_food:=30;v_soul:=40;v_high:=2;v_marrow:=1;
 elsif p_milestone=30 then v_bit:=4;v_soul:=80;v_scroll:=2;v_marrow:=1;
 elsif p_milestone=45 then v_bit:=8;v_soul:=150;v_high:=5;v_marrow:=3;v_scroll:=3;
 elsif p_milestone=60 then v_bit:=16;v_soul:=300;v_high:=10;v_marrow:=5;v_scroll:=5;
 else raise exception 'SPIRIT_BEAST_CODEX_MILESTONE_INVALID';end if;
 if v_count<p_milestone then raise exception 'SPIRIT_BEAST_CODEX_MILESTONE_NOT_REACHED';end if;if (st.codex_claim_mask & v_bit)<>0 then raise exception 'SPIRIT_BEAST_CODEX_REWARD_CLAIMED';end if;
 if v_food>0 then perform public.tianxu_inventory_adjust_v255(v_char,'spirit_beast_food',v_food);end if;if v_soul>0 then perform public.tianxu_inventory_adjust_v255(v_char,'spirit_beast_soul',v_soul);end if;if v_talisman>0 then perform public.tianxu_inventory_adjust_v255(v_char,'spirit_beast_talisman',v_talisman);end if;if v_high>0 then perform public.tianxu_inventory_adjust_v255(v_char,'spirit_beast_talisman_high',v_high);end if;if v_marrow>0 then perform public.tianxu_inventory_adjust_v255(v_char,'spirit_beast_marrow_dew',v_marrow);end if;if v_scroll>0 then perform public.tianxu_inventory_adjust_v255(v_char,'spirit_beast_skill_scroll',v_scroll);end if;
 update public.character_spirit_beast_state_v267 set codex_claim_mask=codex_claim_mask|v_bit,updated_at=clock_timestamp() where character_id=v_char;
 v_result:=jsonb_build_object('status','ok','milestone',p_milestone,'codex_unlocked',v_count,'reward',jsonb_build_object('food',v_food,'soul',v_soul,'talisman',v_talisman,'high_talisman',v_high,'marrow_dew',v_marrow,'skill_scroll',v_scroll));return public.spirit_beast_request_put_v267(v_char,p_request_id,'codex_reward:'||p_milestone::text,v_result);
end$$;

create or replace function public.get_spirit_beast_ranking_v267(p_limit integer default 100)
returns jsonb language plpgsql stable security definer set search_path='' as $$declare v_char uuid:=public.spirit_beast_active_character_v267();v_rows jsonb;begin select coalesce(jsonb_agg(x.obj order by x.score desc,x.obtained_at asc),'[]'::jsonb) into v_rows from (select public.spirit_beast_score_v267(b.id) score,b.obtained_at,jsonb_build_object('rank',row_number() over(order by public.spirit_beast_score_v267(b.id) desc,b.obtained_at asc),'beast_id',b.id,'character_id',b.character_id,'character_name',pc.name,'species_name',sp.name,'display_name',coalesce(nullif(b.nickname,''),sp.name),'rarity',sp.rarity,'evolution_stage',sp.evolution_stage,'level',b.level,'realm_order',b.beast_realm_order,'bloodline',b.bloodline,'intimacy',b.intimacy,'score',public.spirit_beast_score_v267(b.id),'is_mine',b.character_id=v_char) obj from public.character_spirit_beasts_v267 b join public.spirit_beast_species_v267 sp on sp.species_code=b.species_code join public.player_characters pc on pc.id=b.character_id order by public.spirit_beast_score_v267(b.id) desc,b.obtained_at asc limit greatest(1,least(coalesce(p_limit,100),100))) x;return jsonb_build_object('status','ok','rows',v_rows);end$$;

-- ==================== WRAP EXISTING SYSTEMS ====================
-- get_my_battle_snapshot：游历、世界BOSS准备等共同读取此快照；只在最终四维上加灵兽修正，基础境界值保持不变。
do $wrap_snapshot$ begin if to_regprocedure('public.get_my_battle_snapshot_pre_v267()') is null then execute 'alter function public.get_my_battle_snapshot_v1() rename to get_my_battle_snapshot_pre_v267';end if;end $wrap_snapshot$;
create or replace function public.get_my_battle_snapshot_v1() returns jsonb language plpgsql security definer set search_path='' as $$declare v jsonb;begin v:=public.get_my_battle_snapshot_pre_v267();return public.spirit_beast_apply_snapshot_v267(v,null);end$$;

-- B-COMBAT统一命中入口：双方快照都走灵兽修正，因此天命PVP与秘境战斗无需复制另一套逻辑。
do $wrap_hit$ begin if to_regprocedure('public.bcombat01_resolve_hit_v243_pre_v267(jsonb,jsonb,integer,integer,integer,numeric)') is null then execute 'alter function public.bcombat01_resolve_hit_v243(jsonb,jsonb,integer,integer,integer,numeric) rename to bcombat01_resolve_hit_v243_pre_v267';end if;end $wrap_hit$;
create or replace function public.bcombat01_resolve_hit_v243(p_attacker jsonb,p_defender jsonb,p_defender_hp integer,p_round integer,p_sequence integer,p_hit_roll numeric default null) returns jsonb language plpgsql security definer set search_path='' as $$begin return public.bcombat01_resolve_hit_v243_pre_v267(public.spirit_beast_apply_snapshot_v267(p_attacker,null),public.spirit_beast_apply_snapshot_v267(p_defender,null),p_defender_hp,p_round,p_sequence,p_hit_roll);end$$;

-- 天命PVP：沿用当前完整战斗包装，仅追加灵兽参与经验（每日前10场）。
do $wrap_destiny$ begin if to_regprocedure('public.challenge_battle_power_bcombat01_pre_v267(uuid,uuid)') is null then execute 'alter function public.challenge_battle_power_bcombat01(uuid,uuid) rename to challenge_battle_power_bcombat01_pre_v267';end if;end $wrap_destiny$;
create or replace function public.challenge_battle_power_bcombat01(p_target_character_id uuid,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare v_char uuid:=public.spirit_beast_active_character_v267();v_result jsonb;st public.character_spirit_beast_state_v267%rowtype;v_day date:=(clock_timestamp() at time zone 'Asia/Shanghai')::date;v_gain jsonb:='{}'::jsonb;begin v_result:=public.challenge_battle_power_bcombat01_pre_v267(p_target_character_id,p_request_id);perform public.spirit_beast_ensure_state_v267(v_char);select * into st from public.character_spirit_beast_state_v267 where character_id=v_char for update;if st.pvp_exp_day is distinct from v_day then st.pvp_exp_count:=0;update public.character_spirit_beast_state_v267 set pvp_exp_day=v_day,pvp_exp_count=0 where character_id=v_char;end if;if st.pvp_exp_count<10 then v_gain:=public.spirit_beast_gain_active_exp_v267(v_char,20,0);update public.character_spirit_beast_state_v267 set pvp_exp_day=v_day,pvp_exp_count=pvp_exp_count+1,updated_at=clock_timestamp() where character_id=v_char;end if;return coalesce(v_result,'{}'::jsonb)||jsonb_build_object('spirit_beast_v267',jsonb_build_object('pvp_exp',v_gain));end$$;

-- 秘境领取：原奖励事务完成后，同一事务发灵兽资源；以秘境run做唯一来源防重复。
do $wrap_secret$ begin if to_regprocedure('public.claim_secret_realm_rewards_bsecretrealm01_pre_v267(uuid)') is null then execute 'alter function public.claim_secret_realm_rewards_bsecretrealm01(uuid) rename to claim_secret_realm_rewards_bsecretrealm01_pre_v267';end if;end $wrap_secret$;
create or replace function public.claim_secret_realm_rewards_bsecretrealm01(p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare v_char uuid:=public.spirit_beast_active_character_v267();v_result jsonb;v_run uuid;v_beast jsonb:='{}'::jsonb;begin v_result:=public.claim_secret_realm_rewards_bsecretrealm01_pre_v267(p_request_id);begin v_run:=coalesce(nullif(v_result->>'run_id','')::uuid,nullif(v_result#>>'{run,id}','')::uuid);exception when others then v_run:=null;end;if v_run is null then select id into v_run from public.secret_realm_runs_bsecretrealm01 where character_id=v_char and claim_status='claimed' order by claimed_at desc nulls last,updated_at desc limit 1;end if;if v_run is not null then v_beast:=public.spirit_beast_process_secret_claim_v267(v_char,v_run);end if;return coalesce(v_result,'{}'::jsonb)||jsonb_build_object('spirit_beast_v267',v_beast);end$$;

-- 九霄游历：只在一次run真正结束/暂停/败退时处理一次灵兽来源。
do $wrap_explore$ begin if to_regprocedure('public.exploration_choose_v262_pre_v267(uuid,text)') is null then execute 'alter function public.exploration_choose_v262(uuid,text) rename to exploration_choose_v262_pre_v267';end if;end $wrap_explore$;
create or replace function public.exploration_choose_v262(p_run_id uuid,p_choice_code text) returns jsonb language plpgsql security definer set search_path='' as $$declare v_char uuid:=public.spirit_beast_active_character_v267();v_result jsonb;v_status text;v_beast jsonb:='{}'::jsonb;begin v_result:=public.exploration_choose_v262_pre_v267(p_run_id,p_choice_code);v_status:=coalesce(v_result->>'status','');if v_status in('completed','paused','retreated','defeated','failed') then v_beast:=public.spirit_beast_process_exploration_v267(v_char,p_run_id,v_status);end if;return coalesce(v_result,'{}'::jsonb)||jsonb_build_object('spirit_beast_v267',v_beast);end$$;

-- 世界BOSS准备：当前完整准备函数执行完后，把灵兽等效四维修正锁进该成员battle_snapshot。
do $wrap_boss_ready$ begin if to_regprocedure('public.set_world_boss_member_ready_bwboss01_pre_v267(boolean,text,uuid)') is null then execute 'alter function public.set_world_boss_member_ready_bwboss01(boolean,text,uuid) rename to set_world_boss_member_ready_bwboss01_pre_v267';end if;end $wrap_boss_ready$;
create or replace function public.set_world_boss_member_ready_bwboss01(p_ready boolean,p_strategy text,p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare v_char uuid:=public.spirit_beast_active_character_v267();v_result jsonb;v_party uuid;v_snap jsonb;begin v_result:=public.set_world_boss_member_ready_bwboss01_pre_v267(p_ready,p_strategy,p_request_id);if p_ready then v_party:=public.bwboss01_active_party(v_char);select battle_snapshot into v_snap from public.world_boss_party_members_bwboss01 where party_id=v_party and character_id=v_char;v_snap:=public.spirit_beast_apply_snapshot_v267(v_snap,v_char);update public.world_boss_party_members_bwboss01 set battle_snapshot=v_snap,updated_at=clock_timestamp() where party_id=v_party and character_id=v_char;return coalesce(v_result,'{}'::jsonb)||jsonb_build_object('spirit_beast_v267',v_snap->'spirit_beast_v267');end if;return v_result;end$$;

-- 世界BOSS开战：战斗结束后按run一次性给所有贡献成员发灵兽资源/经验。
do $wrap_boss_start$ begin if to_regprocedure('public.start_world_boss_run_bwboss01_pre_v267(uuid)') is null then execute 'alter function public.start_world_boss_run_bwboss01(uuid) rename to start_world_boss_run_bwboss01_pre_v267';end if;end $wrap_boss_start$;
create or replace function public.start_world_boss_run_bwboss01(p_request_id uuid) returns jsonb language plpgsql security definer set search_path='' as $$declare v_char uuid:=public.spirit_beast_active_character_v267();v_result jsonb;v_run uuid;v_self jsonb:='{}'::jsonb;begin v_result:=public.start_world_boss_run_bwboss01_pre_v267(p_request_id);begin v_run:=coalesce(nullif(v_result#>>'{run,id}','')::uuid,nullif(v_result->>'run_id','')::uuid,nullif(v_result->>'id','')::uuid);exception when others then v_run:=null;end;if v_run is not null then perform public.spirit_beast_process_world_boss_run_v267(v_run);v_self:=coalesce(public.spirit_beast_source_get_v267(v_char,'world_boss',v_run::text),'{}'::jsonb);end if;return coalesce(v_result,'{}'::jsonb)||jsonb_build_object('spirit_beast_v267',v_self);end$$;

-- ==================== TTL ====================
create or replace function public.spirit_beast_cleanup_v267()
returns jsonb language plpgsql security definer set search_path='' as $$declare s public.spirit_beast_settings_v267%rowtype;v_req integer;v_enc integer;v_src integer;begin select * into s from public.spirit_beast_settings_v267 where singleton_id=1;delete from public.spirit_beast_request_ledger_v267 where created_at<clock_timestamp()-make_interval(days=>s.request_ttl_days);get diagnostics v_req=row_count;update public.spirit_beast_encounters_v267 set status='expired',resolved_at=clock_timestamp() where status='pending' and expires_at<=clock_timestamp();delete from public.spirit_beast_encounters_v267 where status<>'pending' and created_at<clock_timestamp()-make_interval(days=>s.encounter_ttl_days);get diagnostics v_enc=row_count;delete from public.spirit_beast_source_ledger_v267 where created_at<clock_timestamp()-interval '30 days';get diagnostics v_src=row_count;return jsonb_build_object('request_deleted',v_req,'encounter_deleted',v_enc,'source_deleted',v_src);end$$;

DO $cron$ BEGIN
 IF to_regclass('cron.job') IS NOT NULL THEN
  BEGIN perform cron.unschedule(jobid) from cron.job where jobname='jiuxiao-spirit-beast-v267-cleanup';exception when others then null;end;
  BEGIN perform cron.schedule('jiuxiao-spirit-beast-v267-cleanup','45 */6 * * *','select public.spirit_beast_cleanup_v267();');exception when others then raise notice 'SQL267_CRON_SKIPPED:%',SQLERRM;end;
 END IF;
END $cron$;

-- ==================== ADMIN9 R41 ====================
create or replace function public.admin9_get_spirit_beast_config_v267()
returns jsonb language plpgsql stable security definer set search_path='' as $$declare v_species jsonb;v_skills jsonb;v_recent jsonb;v_enc jsonb;begin perform public.v210_admin_guard();select coalesce(jsonb_agg(to_jsonb(s) order by s.rarity_score,s.lineage_code,s.evolution_stage),'[]'::jsonb) into v_species from public.spirit_beast_species_v267 s;select coalesce(jsonb_agg(to_jsonb(k) order by k.category,k.skill_code),'[]'::jsonb) into v_skills from public.spirit_beast_skills_v267 k;select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'character_id',b.character_id,'character_name',pc.name,'species_code',b.species_code,'species_name',sp.name,'display_name',coalesce(nullif(b.nickname,''),sp.name),'level',b.level,'realm_order',b.beast_realm_order,'bloodline',b.bloodline,'intimacy',b.intimacy,'personality',pr.name,'locked',b.locked,'score',public.spirit_beast_score_v267(b.id),'obtained_at',b.obtained_at) order by b.obtained_at desc),'[]'::jsonb) into v_recent from (select * from public.character_spirit_beasts_v267 order by obtained_at desc limit 100)b join public.player_characters pc on pc.id=b.character_id join public.spirit_beast_species_v267 sp on sp.species_code=b.species_code join public.spirit_beast_personalities_v267 pr on pr.personality_code=b.personality_code;select coalesce(jsonb_agg(to_jsonb(e) order by e.created_at desc),'[]'::jsonb) into v_enc from (select * from public.spirit_beast_encounters_v267 order by created_at desc limit 50)e;return jsonb_build_object('status','ok','build','SPIRIT_BEAST_V267_COMPLETE','settings',(select to_jsonb(s) from public.spirit_beast_settings_v267 s where singleton_id=1),'species',v_species,'skills',v_skills,'recent_beasts',v_recent,'recent_encounters',v_enc,'counts',jsonb_build_object('species',(select count(*) from public.spirit_beast_species_v267),'owned',(select count(*) from public.character_spirit_beasts_v267),'codex',(select count(*) from public.character_spirit_beast_codex_v267),'pending_encounters',(select count(*) from public.spirit_beast_encounters_v267 where status='pending')));end$$;

create or replace function public.admin9_update_spirit_beast_settings_v267(p_patch jsonb,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_old jsonb;v_new jsonb;begin perform public.v210_admin_guard();if length(trim(coalesce(p_reason,'')))<2 then raise exception 'ADMIN_REASON_REQUIRED';end if;select to_jsonb(s) into v_old from public.spirit_beast_settings_v267 s where singleton_id=1;update public.spirit_beast_settings_v267 set enabled=coalesce((p_patch->>'enabled')::boolean,enabled),capture_enabled=coalesce((p_patch->>'capture_enabled')::boolean,capture_enabled),combat_enabled=coalesce((p_patch->>'combat_enabled')::boolean,combat_enabled),daily_supply_food=coalesce((p_patch->>'daily_supply_food')::integer,daily_supply_food),daily_supply_talisman=coalesce((p_patch->>'daily_supply_talisman')::integer,daily_supply_talisman),base_capacity=coalesce((p_patch->>'base_capacity')::integer,base_capacity),capacity_per_stable_level=coalesce((p_patch->>'capacity_per_stable_level')::integer,capacity_per_stable_level),max_stable_level=coalesce((p_patch->>'max_stable_level')::integer,max_stable_level),feed_exp_per_food=coalesce((p_patch->>'feed_exp_per_food')::integer,feed_exp_per_food),max_feed_per_call=coalesce((p_patch->>'max_feed_per_call')::integer,max_feed_per_call),exploration_encounter_rate=coalesce((p_patch->>'exploration_encounter_rate')::numeric,exploration_encounter_rate),secret_egg_rate=coalesce((p_patch->>'secret_egg_rate')::numeric,secret_egg_rate),boss_egg_rate=coalesce((p_patch->>'boss_egg_rate')::numeric,boss_egg_rate),boss_mythic_egg_rate=coalesce((p_patch->>'boss_mythic_egg_rate')::numeric,boss_mythic_egg_rate),encounter_expiry_minutes=coalesce((p_patch->>'encounter_expiry_minutes')::integer,encounter_expiry_minutes),max_capture_attempts=coalesce((p_patch->>'max_capture_attempts')::integer,max_capture_attempts),pity_bonus_per_fail=coalesce((p_patch->>'pity_bonus_per_fail')::numeric,pity_bonus_per_fail),pity_max_bonus=coalesce((p_patch->>'pity_max_bonus')::numeric,pity_max_bonus),combat_stat_cap=coalesce((p_patch->>'combat_stat_cap')::numeric,combat_stat_cap),request_ttl_days=coalesce((p_patch->>'request_ttl_days')::integer,request_ttl_days),encounter_ttl_days=coalesce((p_patch->>'encounter_ttl_days')::integer,encounter_ttl_days),updated_at=clock_timestamp() where singleton_id=1;select to_jsonb(s) into v_new from public.spirit_beast_settings_v267 s where singleton_id=1;insert into public.spirit_beast_admin_audit_v267(admin_user_id,action_code,target_ref,reason,old_value,new_value) values(auth.uid(),'settings','singleton',trim(p_reason),v_old,v_new);return jsonb_build_object('status','ok','settings',v_new);end$$;
create or replace function public.admin9_update_spirit_beast_species_v267(p_species_code text,p_patch jsonb,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_old jsonb;v_new jsonb;begin perform public.v210_admin_guard();if length(trim(coalesce(p_reason,'')))<2 then raise exception 'ADMIN_REASON_REQUIRED';end if;select to_jsonb(s) into v_old from public.spirit_beast_species_v267 s where species_code=p_species_code;if v_old is null then raise exception 'SPIRIT_BEAST_SPECIES_NOT_FOUND';end if;update public.spirit_beast_species_v267 set enabled=coalesce((p_patch->>'enabled')::boolean,enabled),base_capture_chance=coalesce((p_patch->>'base_capture_chance')::numeric,base_capture_chance),attack_pct=coalesce((p_patch->>'attack_pct')::numeric,attack_pct),defense_pct=coalesce((p_patch->>'defense_pct')::numeric,defense_pct),vitality_pct=coalesce((p_patch->>'vitality_pct')::numeric,vitality_pct),agility_pct=coalesce((p_patch->>'agility_pct')::numeric,agility_pct) where species_code=p_species_code;select to_jsonb(s) into v_new from public.spirit_beast_species_v267 s where species_code=p_species_code;insert into public.spirit_beast_admin_audit_v267(admin_user_id,action_code,target_ref,reason,old_value,new_value) values(auth.uid(),'species_update',p_species_code,trim(p_reason),v_old,v_new);return jsonb_build_object('status','ok','species',v_new);end$$;

create or replace function public.admin9_grant_spirit_beast_v267(p_character_id uuid,p_species_code text,p_bloodline integer,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_id uuid;v_new jsonb;begin perform public.v210_admin_guard();if length(trim(coalesce(p_reason,'')))<2 then raise exception 'ADMIN_REASON_REQUIRED';end if;if not exists(select 1 from public.player_characters where id=p_character_id) then raise exception 'CHARACTER_NOT_FOUND';end if;v_id:=public.spirit_beast_create_instance_v267(p_character_id,p_species_code,greatest(1,least(100,coalesce(p_bloodline,80))),'gm',auth.uid()::text);select to_jsonb(b) into v_new from public.character_spirit_beasts_v267 b where id=v_id;insert into public.spirit_beast_admin_audit_v267(admin_user_id,action_code,target_ref,reason,new_value) values(auth.uid(),'grant',v_id::text,trim(p_reason),v_new);return jsonb_build_object('status','ok','beast_id',v_id);end$$;

create or replace function public.admin9_manage_spirit_beast_v267(p_beast_id uuid,p_action text,p_value text,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$declare b public.character_spirit_beasts_v267%rowtype;v_old jsonb;v_new jsonb;begin perform public.v210_admin_guard();if length(trim(coalesce(p_reason,'')))<2 then raise exception 'ADMIN_REASON_REQUIRED';end if;select * into b from public.character_spirit_beasts_v267 where id=p_beast_id for update;if b.id is null then raise exception 'SPIRIT_BEAST_NOT_FOUND';end if;v_old:=to_jsonb(b);if p_action='set_bloodline' then update public.character_spirit_beasts_v267 set bloodline=greatest(1,least(100,p_value::integer)),updated_at=clock_timestamp() where id=b.id;elsif p_action='set_intimacy' then update public.character_spirit_beasts_v267 set intimacy=greatest(0,least(100,p_value::integer)),updated_at=clock_timestamp() where id=b.id;elsif p_action='set_level' then update public.character_spirit_beasts_v267 set level=greatest(1,least(beast_realm_order*10,p_value::integer)),updated_at=clock_timestamp() where id=b.id;elsif p_action='lock' then update public.character_spirit_beasts_v267 set locked=true,updated_at=clock_timestamp() where id=b.id;elsif p_action='unlock' then update public.character_spirit_beasts_v267 set locked=false,updated_at=clock_timestamp() where id=b.id;elsif p_action='delete' then update public.character_spirit_beast_state_v267 set active_beast_id=null where active_beast_id=b.id;delete from public.character_spirit_beasts_v267 where id=b.id;v_new:=jsonb_build_object('deleted',true);insert into public.spirit_beast_admin_audit_v267(admin_user_id,action_code,target_ref,reason,old_value,new_value) values(auth.uid(),'beast_delete',b.id::text,trim(p_reason),v_old,v_new);return jsonb_build_object('status','ok','deleted',true);else raise exception 'SPIRIT_BEAST_ADMIN_ACTION_INVALID';end if;select to_jsonb(x) into v_new from public.character_spirit_beasts_v267 x where id=b.id;insert into public.spirit_beast_admin_audit_v267(admin_user_id,action_code,target_ref,reason,old_value,new_value) values(auth.uid(),'beast_'||p_action,b.id::text,trim(p_reason),v_old,v_new);return jsonb_build_object('status','ok','beast',v_new);end$$;

create or replace function public.admin9_check_spirit_beast_v267()
returns jsonb language plpgsql stable security definer set search_path='' as $$declare v_species integer;v_skills integer;v_person integer;v_eggs integer;v_wrap integer:=0;begin perform public.v210_admin_guard();select count(*) into v_species from public.spirit_beast_species_v267 where enabled;select count(*) into v_skills from public.spirit_beast_skills_v267 where enabled;select count(*) into v_person from public.spirit_beast_personalities_v267 where enabled;select count(*) into v_eggs from public.spirit_beast_egg_map_v267 where enabled;if position('spirit_beast' in lower(pg_get_functiondef(to_regprocedure('public.exploration_choose_v262(uuid,text)'))))>0 then v_wrap:=v_wrap+1;end if;if position('spirit_beast' in lower(pg_get_functiondef(to_regprocedure('public.claim_secret_realm_rewards_bsecretrealm01(uuid)'))))>0 then v_wrap:=v_wrap+1;end if;if position('spirit_beast' in lower(pg_get_functiondef(to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)'))))>0 then v_wrap:=v_wrap+1;end if;if position('spirit_beast' in lower(pg_get_functiondef(to_regprocedure('public.set_world_boss_member_ready_bwboss01(boolean,text,uuid)'))))>0 then v_wrap:=v_wrap+1;end if;if position('spirit_beast' in lower(pg_get_functiondef(to_regprocedure('public.start_world_boss_run_bwboss01(uuid)'))))>0 then v_wrap:=v_wrap+1;end if;if position('spirit_beast' in lower(pg_get_functiondef(to_regprocedure('public.get_my_battle_snapshot_v1()'))))>0 then v_wrap:=v_wrap+1;end if;if position('spirit_beast' in lower(pg_get_functiondef(to_regprocedure('public.bcombat01_resolve_hit_v243(jsonb,jsonb,integer,integer,integer,numeric)'))))>0 then v_wrap:=v_wrap+1;end if;return jsonb_build_object('status',case when v_species=60 and v_skills=36 and v_person=8 and v_eggs=24 and v_wrap=7 then 'passed' else 'failed' end,'species',v_species,'skills',v_skills,'personalities',v_person,'eggs',v_eggs,'integration_wrappers',v_wrap,'expected_wrappers',7,'build','SQL267_SPIRIT_BEAST_COMPLETE');end$$;

-- ==================== PRIVILEGES ====================
revoke all on function public.spirit_beast_active_character_v267(),public.spirit_beast_character_realm_order_v267(uuid),public.spirit_beast_ensure_state_v267(uuid),public.spirit_beast_capacity_v267(uuid),public.spirit_beast_score_v267(uuid),public.spirit_beast_request_get_v267(uuid,uuid,text),public.spirit_beast_request_put_v267(uuid,uuid,text,jsonb),public.spirit_beast_update_codex_v267(uuid),public.spirit_beast_create_instance_v267(uuid,text,integer,text,text),public.spirit_beast_gain_exp_v267(uuid,bigint,integer),public.spirit_beast_gain_active_exp_v267(uuid,bigint,integer),public.spirit_beast_combat_modifier_v267(uuid),public.spirit_beast_apply_snapshot_v267(jsonb,uuid),public.spirit_beast_create_encounter_v267(uuid,text,text,text),public.spirit_beast_source_get_v267(uuid,text,text),public.spirit_beast_source_put_v267(uuid,text,text,jsonb),public.spirit_beast_aux_bonus_v267(uuid,text),public.spirit_beast_process_exploration_v267(uuid,uuid,text),public.spirit_beast_random_base_egg_v267(),public.spirit_beast_random_mythic_egg_v267(),public.spirit_beast_random_essence_v267(),public.spirit_beast_process_secret_claim_v267(uuid,uuid),public.spirit_beast_process_world_boss_run_v267(uuid),public.spirit_beast_cleanup_v267() from public,anon,authenticated;

grant execute on function public.get_spirit_beast_hub_v267(),public.spirit_beast_claim_daily_supply_v267(uuid),public.spirit_beast_capture_v267(uuid,text,uuid),public.spirit_beast_hatch_egg_v267(text,uuid),public.spirit_beast_set_active_v267(uuid,uuid),public.spirit_beast_feed_v267(uuid,integer,uuid),public.spirit_beast_interact_v267(uuid,uuid),public.spirit_beast_rename_v267(uuid,text,uuid),public.spirit_beast_set_lock_v267(uuid,boolean,uuid),public.spirit_beast_breakthrough_v267(uuid,uuid),public.spirit_beast_evolve_v267(uuid,uuid),public.spirit_beast_release_v267(uuid,uuid),public.spirit_beast_inherit_bloodline_v267(uuid,uuid,uuid),public.spirit_beast_reroll_personality_v267(uuid,uuid),public.spirit_beast_learn_aux_skill_v267(uuid,text,uuid),public.spirit_beast_upgrade_skill_v267(uuid,text,uuid),public.spirit_beast_upgrade_stable_v267(uuid),public.spirit_beast_claim_codex_reward_v267(integer,uuid),public.get_spirit_beast_ranking_v267(integer) to authenticated;
revoke all on function public.get_spirit_beast_hub_v267(),public.spirit_beast_claim_daily_supply_v267(uuid),public.spirit_beast_capture_v267(uuid,text,uuid),public.spirit_beast_hatch_egg_v267(text,uuid),public.spirit_beast_set_active_v267(uuid,uuid),public.spirit_beast_feed_v267(uuid,integer,uuid),public.spirit_beast_interact_v267(uuid,uuid),public.spirit_beast_rename_v267(uuid,text,uuid),public.spirit_beast_set_lock_v267(uuid,boolean,uuid),public.spirit_beast_breakthrough_v267(uuid,uuid),public.spirit_beast_evolve_v267(uuid,uuid),public.spirit_beast_release_v267(uuid,uuid),public.spirit_beast_inherit_bloodline_v267(uuid,uuid,uuid),public.spirit_beast_reroll_personality_v267(uuid,uuid),public.spirit_beast_learn_aux_skill_v267(uuid,text,uuid),public.spirit_beast_upgrade_skill_v267(uuid,text,uuid),public.spirit_beast_upgrade_stable_v267(uuid),public.spirit_beast_claim_codex_reward_v267(integer,uuid),public.get_spirit_beast_ranking_v267(integer) from anon;

grant execute on function public.admin9_get_spirit_beast_config_v267(),public.admin9_update_spirit_beast_settings_v267(jsonb,text),public.admin9_update_spirit_beast_species_v267(text,jsonb,text),public.admin9_grant_spirit_beast_v267(uuid,text,integer,text),public.admin9_manage_spirit_beast_v267(uuid,text,text,text),public.admin9_check_spirit_beast_v267() to authenticated;
revoke all on function public.admin9_get_spirit_beast_config_v267(),public.admin9_update_spirit_beast_settings_v267(jsonb,text),public.admin9_update_spirit_beast_species_v267(text,jsonb,text),public.admin9_grant_spirit_beast_v267(uuid,text,integer,text),public.admin9_manage_spirit_beast_v267(uuid,text,text,text),public.admin9_check_spirit_beast_v267() from anon;

-- ==================== GATE ====================
DO $gate$
DECLARE v_species integer;v_skills integer;v_person integer;v_evo integer;v_pool integer;v_eggs integer;v_items integer;v_bad integer;v_check jsonb;
BEGIN
 select count(*) into v_species from public.spirit_beast_species_v267 where enabled;if v_species<>60 then raise exception 'SQL267_GATE_SPECIES_COUNT:%',v_species;end if;
 select count(*) into v_skills from public.spirit_beast_skills_v267 where enabled;if v_skills<>36 then raise exception 'SQL267_GATE_SKILL_COUNT:%',v_skills;end if;
 select count(*) into v_person from public.spirit_beast_personalities_v267 where enabled;if v_person<>8 then raise exception 'SQL267_GATE_PERSONALITY_COUNT:%',v_person;end if;
 select count(*) into v_evo from public.spirit_beast_evolutions_v267 where enabled;if v_evo<>36 then raise exception 'SQL267_GATE_EVOLUTION_COUNT:%',v_evo;end if;
 select count(*) into v_pool from public.spirit_beast_region_pool_v267 where enabled;if v_pool<>32 then raise exception 'SQL267_GATE_REGION_POOL_COUNT:%',v_pool;end if;
 select count(*) into v_eggs from public.spirit_beast_egg_map_v267 where enabled;if v_eggs<>24 then raise exception 'SQL267_GATE_EGG_COUNT:%',v_eggs;end if;
 select count(*) into v_items from public.item_definitions where code like 'spirit_beast_%';if v_items<38 then raise exception 'SQL267_GATE_ITEM_DEFS:%',v_items;end if;
 select count(*) into v_bad from public.spirit_beast_species_v267 where evolution_stage=1 and base_capture_chance<=0;if v_bad<>0 then raise exception 'SQL267_GATE_BASE_CAPTURE_INVALID:%',v_bad;end if;
 if to_regprocedure('public.get_spirit_beast_hub_v267()') is null or to_regprocedure('public.spirit_beast_capture_v267(uuid,text,uuid)') is null or to_regprocedure('public.spirit_beast_claim_codex_reward_v267(integer,uuid)') is null or to_regprocedure('public.get_spirit_beast_ranking_v267(integer)') is null then raise exception 'SQL267_GATE_PLAYER_RPC_MISSING';end if;
 if to_regprocedure('public.admin9_get_spirit_beast_config_v267()') is null then raise exception 'SQL267_GATE_ADMIN_RPC_MISSING';end if;
 if position('spirit_beast' in lower(pg_get_functiondef(to_regprocedure('public.get_my_battle_snapshot_v1()'))))=0 then raise exception 'SQL267_GATE_SNAPSHOT_WRAPPER_MISSING';end if;
 if position('spirit_beast' in lower(pg_get_functiondef(to_regprocedure('public.bcombat01_resolve_hit_v243(jsonb,jsonb,integer,integer,integer,numeric)'))))=0 then raise exception 'SQL267_GATE_BCOMBAT_WRAPPER_MISSING';end if;
 if position('spirit_beast' in lower(pg_get_functiondef(to_regprocedure('public.exploration_choose_v262(uuid,text)'))))=0 then raise exception 'SQL267_GATE_EXPLORATION_WRAPPER_MISSING';end if;
 if position('spirit_beast' in lower(pg_get_functiondef(to_regprocedure('public.claim_secret_realm_rewards_bsecretrealm01(uuid)'))))=0 then raise exception 'SQL267_GATE_SECRET_WRAPPER_MISSING';end if;
 if position('spirit_beast' in lower(pg_get_functiondef(to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)'))))=0 then raise exception 'SQL267_GATE_PVP_WRAPPER_MISSING';end if;
 if position('spirit_beast' in lower(pg_get_functiondef(to_regprocedure('public.set_world_boss_member_ready_bwboss01(boolean,text,uuid)'))))=0 then raise exception 'SQL267_GATE_BOSS_READY_WRAPPER_MISSING';end if;
 if position('spirit_beast' in lower(pg_get_functiondef(to_regprocedure('public.start_world_boss_run_bwboss01(uuid)'))))=0 then raise exception 'SQL267_GATE_BOSS_START_WRAPPER_MISSING';end if;
 raise notice 'SQL267_GATE_PASSED';raise notice 'V2.5.0 CACHE138 / SPIRIT_BEAST_COMPLETE / species=% skills=% evo=% eggs=%',v_species,v_skills,v_evo,v_eggs;
END $gate$;

commit;

-- 执行成功唯一门禁：SQL267_GATE_PASSED
