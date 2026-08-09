-- 九霄问道 · V2.2.0 CACHE122 · SQL254 R5
-- R5修复：保留生产普通功法 grade/main_rate/support_rate 原配置，不修改旧修炼功法掉率。
-- 玄/地/天/仙攻防残卷仍严格按对应普通功法实际总掉率(main_rate+support_rate)×20%；
-- 黄品因旧普通功法体系无黄品掉率行，改为独立条件概率5%（对应“黄品趋吉机缘内”的攻防残卷池概率），并纳入GM可调。
-- 同时将机缘残卷判定改为按本次 settlement_batch_id 的每条真实机缘结果逐条处理，避免批量离线结算只处理返回JSON少数结果。
-- 功法三系 / 攻伐与护体功法 / 同名残卷10合1 / 同品5换1 / 全战斗服务端接入
-- 生产前提：SQL252已由用户确认执行成功；若需要ADMIN9 R31账号删除功能，请先执行SQL253。
-- 本SQL不依赖SQL253对象，但编号按交付顺序继续使用254。
--
-- 设计硬规则：
-- 1. 现有所有功法仍属于修炼功法；新增攻伐10本、护体10本，各只能装备1本。
-- 2. 新功法无境界参悟门槛；10张同名残卷合成1本完整道卷；同品其它残卷5张可换1张指定残卷。
-- 3. 机缘残卷总概率=当前普通功法概率*20%；秘境独立12%/8%/4%/2%；BOSS普通20%天、困难25%天+5%仙。
-- 4. 秘境残卷属于风险资产：同一轮所有残卷合计floor(50%)后随机原物转移；同一对玩家6小时内第1次100%、第2次25%、第3次起0。
-- 5. 修炼普通/专属/攻伐/护体四类升级灵石倍率默认全部10，GM可分别调整；服务端为权威价格。
-- 6. 功法效果必须服务端结算；天命榜/秘境走B-COMBAT，世界BOSS走其生产独立模拟器的effect_code适配器；任一链缺失门禁回滚。
-- 7. 战斗按上下文锁定快照：天命榜开战读取；秘境进入锁定；世界BOSS“锁定快照并准备”锁定。
-- 8. effect_code固定，中文名仅展示，绝不以中文名判断战斗逻辑。
-- 9. V2.2.0起彻底停止旧修炼槽借用的attack_skill_multiplier/defense_technique_reduction，修炼功法不再误参与战斗。

begin;

-- 生产诊断证据（用户导出 Supabase query 46）：worldboss md5=77bdd839a0bf62263a2b05fbf251ebb7；destiny md5=f147c7961fc32e6b0a012affc6cf13df；secret_resolve md5=bba43e9dd952829d459d7be503c8b80d。
-- ---------- 前置门禁 ----------
do $precheck$
declare
  v_secret_capture text:='';
  v_secret_resolve text:='';
  v_secret_process text:='';
  v_secret_settle text:='';
  v_secret_chain boolean:=false;
  v_boss text;
  v_destiny text;
  v_proc regprocedure;
begin
  if to_regprocedure('public.bcombat01_resolve_hit_v243(jsonb,jsonb,integer,integer,integer,numeric)') is null then
    raise exception 'SQL254_PRECHECK_SQL244_BCOMBAT_MISSING';
  end if;
  if to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)') is null
     and to_regprocedure('public.challenge_battle_power_bcombat01_pre_v220(uuid,uuid)') is null then
    raise exception 'SQL254_PRECHECK_DESTINY_BATTLE_RPC_MISSING';
  end if;
  if to_regprocedure('public.equipment_v210_active_character_id()') is null
     or to_regprocedure('public.equipment_v210_debit_spirit_stone_v243(uuid,bigint)') is null then
    raise exception 'SQL254_PRECHECK_SQL243_ECONOMY_MISSING';
  end if;
  if to_regprocedure('public.get_technique_system_v2()') is null
     or to_regprocedure('public.upgrade_technique_v0154(uuid,uuid)') is null
     or to_regprocedure('public.get_exclusive_technique_system_v1()') is null
     or to_regprocedure('public.upgrade_exclusive_technique_v0154(uuid,uuid)') is null then
    raise exception 'SQL254_PRECHECK_CULTIVATION_TECHNIQUE_RPC_MISSING';
  end if;
  if to_regclass('public.opportunity_v4_technique_drop_rates') is null
     or to_regprocedure('public.settle_opportunity_v4(boolean)') is null then
    raise exception 'SQL254_PRECHECK_OPPORTUNITY_V4_MISSING';
  end if;
  -- 生产只读诊断 query(47) 已确认真实结构：grade/main_rate/support_rate。
  -- 这里提前核验，避免执行到最终Gate才发现机缘掉率结构变化。
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='opportunity_v4_technique_drop_rates' and column_name='grade')
     or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='opportunity_v4_technique_drop_rates' and column_name='main_rate')
     or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='opportunity_v4_technique_drop_rates' and column_name='support_rate') then
    raise exception 'SQL254_PRECHECK_ORDINARY_TECHNIQUE_RATE_SCHEMA_CHANGED_EXPECT_GRADE_MAIN_SUPPORT';
  end if;
  if to_regprocedure('public.enter_secret_realm_bsecretrealm01(uuid)') is null
     or to_regprocedure('public.settle_secret_realm_progress_bsecretrealm01(uuid)') is null
     or to_regprocedure('public.claim_secret_realm_rewards_bsecretrealm01(uuid)') is null then
    raise exception 'SQL254_PRECHECK_SECRET_REALM_RPC_MISSING';
  end if;
  if to_regprocedure('public.set_world_boss_member_ready_bwboss01(boolean,text,uuid)') is null
     or to_regprocedure('public.bwboss01_simulate_run(uuid)') is null
     or to_regprocedure('public.start_world_boss_run_bwboss01(uuid)') is null then
    raise exception 'SQL254_PRECHECK_WORLD_BOSS_RPC_MISSING';
  end if;

  -- SQL243 R4生产真实链：settle -> process_due -> resolve_battle -> bcombat01_resolve_hit_v243。
  -- R1只检查最外层settle正文是否直接出现“bcombat”，会把真实传递调用误判为未接入；R2按完整调用链核验。
  if to_regprocedure('public.secret_realm_capture_battle_snapshot_bsecretrealm01(uuid)') is null
     or to_regprocedure('public.secret_realm_resolve_battle_bsecretrealm01(jsonb,jsonb,integer,text)') is null
     or to_regprocedure('public.secret_realm_process_due_minutes_bsecretrealm01(uuid,timestamp with time zone)') is null then
    raise exception 'SQL254_PRECHECK_SECRET_REALM_TRANSITIVE_CHAIN_RPC_MISSING';
  end if;
  select lower(pg_get_functiondef(to_regprocedure('public.secret_realm_capture_battle_snapshot_bsecretrealm01(uuid)'))) into v_secret_capture;
  select lower(pg_get_functiondef(to_regprocedure('public.secret_realm_resolve_battle_bsecretrealm01(jsonb,jsonb,integer,text)'))) into v_secret_resolve;
  select lower(pg_get_functiondef(to_regprocedure('public.secret_realm_process_due_minutes_bsecretrealm01(uuid,timestamp with time zone)'))) into v_secret_process;
  v_proc:=coalesce(to_regprocedure('public.settle_secret_realm_progress_bsecretrealm01_pre_v220(uuid)'),to_regprocedure('public.settle_secret_realm_progress_bsecretrealm01(uuid)'));
  select lower(pg_get_functiondef(v_proc)) into v_secret_settle;
  v_secret_chain:=position('bcombat01_character_snapshot' in coalesce(v_secret_capture,''))>0
    and position('bcombat01_resolve_hit_v243' in coalesce(v_secret_resolve,''))>0
    and position('secret_realm_resolve_battle_bsecretrealm01' in coalesce(v_secret_process,''))>0
    and position('secret_realm_process_due_minutes_bsecretrealm01' in coalesce(v_secret_settle,''))>0;
  if not v_secret_chain then
    raise exception 'SQL254_PRECHECK_SECRET_REALM_BCOMBAT_TRANSITIVE_CHAIN_MISSING:capture=% resolve=% process=% settle=%',
      position('bcombat01_character_snapshot' in coalesce(v_secret_capture,''))>0,
      position('bcombat01_resolve_hit_v243' in coalesce(v_secret_resolve,''))>0,
      position('secret_realm_resolve_battle_bsecretrealm01' in coalesce(v_secret_process,''))>0,
      position('secret_realm_process_due_minutes_bsecretrealm01' in coalesce(v_secret_settle,''))>0;
  end if;

  -- 天命榜原挑战入口必须真实经过B-COMBAT；SQL254在外层锁定双方功法快照。
  v_proc:=coalesce(to_regprocedure('public.challenge_battle_power_bcombat01_pre_v220(uuid,uuid)'),to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)'));
  select lower(pg_get_functiondef(v_proc)) into v_destiny;
  if position('bcombat01_resolve_hit' in coalesce(v_destiny,''))=0 and position('bcombat' in coalesce(v_destiny,''))=0 then
    raise exception 'SQL254_PRECHECK_DESTINY_BCOMBAT_HOOK_MISSING';
  end if;

  -- 诊断CSV已确认：世界BOSS是独立服务端模拟器，并不调用B-COMBAT。R2按生产函数指纹适配其真实公式，拒绝未知函数体。
  v_proc:=to_regprocedure('public.bwboss01_simulate_run(uuid)');select pg_get_functiondef(v_proc) into v_boss;
  if md5(v_boss)<>'77bdd839a0bf62263a2b05fbf251ebb7' then raise exception 'SQL254_PRECHECK_WORLD_BOSS_PRODUCTION_DEFINITION_CHANGED: expected_md5=77bdd839a0bf62263a2b05fbf251ebb7 actual_md5=%',md5(v_boss);end if;
  if position('world_boss_party_members_bwboss01' in lower(v_boss))=0 or position('v_boss_damage' in lower(v_boss))=0 then raise exception 'SQL254_PRECHECK_WORLD_BOSS_SIMULATOR_SHAPE_UNKNOWN';end if;
end
$precheck$;

-- ---------- 统一设置 ----------
create table if not exists public.combat_technique_settings_v220(
  singleton_id smallint primary key default 1 check(singleton_id=1),
  enabled boolean not null default true,
  cultivation_upgrade_multiplier numeric(10,4) not null default 10,
  exclusive_upgrade_multiplier numeric(10,4) not null default 10,
  attack_upgrade_multiplier numeric(10,4) not null default 10,
  defense_upgrade_multiplier numeric(10,4) not null default 10,
  level_effect_growth numeric(10,6) not null default .10,
  mastery_effect_multiplier numeric(10,6) not null default 1.20,
  mastery_cost_multiplier numeric(10,6) not null default 1.50,
  shard_combine_count integer not null default 10,
  shard_exchange_enabled boolean not null default true,
  shard_exchange_cost integer not null default 5,
  shard_exchange_gain integer not null default 1,
  opportunity_relative_rate numeric(10,6) not null default .20,
  opportunity_yellow_shard_rate numeric(10,6) not null default .05,
  opportunity_attack_weight numeric(10,4) not null default 50,
  opportunity_defense_weight numeric(10,4) not null default 50,
  secret_mystic_rate numeric(10,6) not null default .12,
  secret_earth_rate numeric(10,6) not null default .08,
  secret_heaven_rate numeric(10,6) not null default .04,
  secret_immortal_rate numeric(10,6) not null default .02,
  secret_drop_quantity integer not null default 1,
  secret_pvp_steal_rate numeric(10,6) not null default .50,
  secret_antifarm_window_hours integer not null default 6,
  secret_antifarm_second_multiplier numeric(10,6) not null default .25,
  secret_antifarm_third_multiplier numeric(10,6) not null default 0,
  boss_normal_heaven_rate numeric(10,6) not null default .20,
  boss_hard_heaven_rate numeric(10,6) not null default .25,
  boss_hard_immortal_rate numeric(10,6) not null default .05,
  boss_drop_quantity integer not null default 1,
  yellow_book_redeem_stones bigint not null default 100000,
  mystic_book_redeem_stones bigint not null default 500000,
  earth_book_redeem_stones bigint not null default 2000000,
  heaven_book_redeem_stones bigint not null default 6000000,
  immortal_book_redeem_stones bigint not null default 15000000,
  config_version bigint not null default 1,
  updated_at timestamptz not null default clock_timestamp()
);
-- 兼容极端情况下表已存在但尚无R5新增列；正常R1-R4失败均在事务内回滚，不会留下半对象。
alter table public.combat_technique_settings_v220 add column if not exists opportunity_yellow_shard_rate numeric(10,6) not null default .05;
insert into public.combat_technique_settings_v220(singleton_id) values(1) on conflict(singleton_id) do nothing;

-- GM可调，但数据库仍保留安全边界，避免错误配置把概率/倍率写成非法值。
do $settings_constraints$
begin
  alter table public.combat_technique_settings_v220 drop constraint if exists combat_technique_settings_v220_rates_valid;
  alter table public.combat_technique_settings_v220 add constraint combat_technique_settings_v220_rates_valid check(
    opportunity_relative_rate between 0 and 1 and opportunity_yellow_shard_rate between 0 and 1 and secret_mystic_rate between 0 and 1 and secret_earth_rate between 0 and 1
    and secret_heaven_rate between 0 and 1 and secret_immortal_rate between 0 and 1 and secret_pvp_steal_rate between 0 and 1
    and secret_antifarm_second_multiplier between 0 and 1 and secret_antifarm_third_multiplier between 0 and 1
    and boss_normal_heaven_rate between 0 and 1 and boss_hard_heaven_rate between 0 and 1 and boss_hard_immortal_rate between 0 and 1
    and boss_hard_heaven_rate+boss_hard_immortal_rate<=1
  );
  if not exists(select 1 from pg_constraint where conname='combat_technique_settings_v220_costs_valid') then
    alter table public.combat_technique_settings_v220 add constraint combat_technique_settings_v220_costs_valid check(
      cultivation_upgrade_multiplier>=1 and exclusive_upgrade_multiplier>=1 and attack_upgrade_multiplier>=1 and defense_upgrade_multiplier>=1
      and level_effect_growth>=0 and mastery_effect_multiplier>=0 and mastery_cost_multiplier>=0
      and shard_combine_count>0 and shard_exchange_cost>0 and shard_exchange_gain>0
      and secret_drop_quantity>0 and boss_drop_quantity>0 and secret_antifarm_window_hours>0
      and opportunity_attack_weight>=0 and opportunity_defense_weight>=0 and opportunity_attack_weight+opportunity_defense_weight>0
    );
  end if;
end
$settings_constraints$;

-- ---------- 20本功法定义 ----------
create table if not exists public.combat_technique_definitions_v220(
  code text primary key,
  family text not null check(family in ('attack','defense')),
  grade_code text not null check(grade_code in ('yellow','mystic','earth','heaven','immortal')),
  display_name text not null,
  role_name text not null,
  effect_code text not null,
  base_params jsonb not null default '{}'::jsonb,
  description text not null default '',
  acquisition_hint text not null default '',
  pool_weight numeric(10,4) not null default 50,
  enabled boolean not null default true,
  sort_order integer not null,
  updated_at timestamptz not null default clock_timestamp()
);

insert into public.combat_technique_definitions_v220
(code,family,grade_code,display_name,role_name,effect_code,base_params,description,acquisition_hint,pool_weight,sort_order)
values
('atk_yellow_pofeng','attack','yellow','引气破锋诀','稳攻','ATK_FINAL_DAMAGE','{"damage_bonus":0.04}','引气凝锋，招式虽朴，胜在每一击皆有实益。','黄品趋吉机缘。',50,10),
('atk_yellow_zhuiying','attack','yellow','流云追影诀','命中','ATK_HIT','{"hit_bonus":0.03,"damage_bonus":0.01}','身随流云，气机追影，提高命中并略增攻势。','黄品趋吉机缘。',50,20),
('atk_mystic_liejia','attack','mystic','庚金裂甲诀','破御','ATK_DEFENSE_PEN','{"defense_penetration":0.04}','引庚金锐意直破护体，以相对比例削弱目标道御减伤。','玄品趋吉机缘、秘境初期妖兽。',50,30),
('atk_mystic_fengfeng','attack','mystic','赤霄焚锋诀','爆发','ATK_OPENING_BURST','{"opening_damage_bonus":0.04,"later_damage_bonus":0.015,"opening_rounds":2}','赤霄烈意汇于锋端，前两回合攻势最盛。','玄品趋吉机缘、秘境初期妖兽。',50,40),
('atk_earth_zhuiying','attack','earth','青冥逐影经','克闪','ATK_ANTI_EVASION','{"hit_bonus":0.04,"high_evasion_threshold":0.10,"high_evasion_damage_bonus":0.025}','观气锁影，专破身法高绝之敌。','地品趋吉机缘、秘境中期妖兽。',50,50),
('atk_earth_duanmai','attack','earth','崩岳断脉诀','克御','ATK_ANTI_DEFENSE','{"high_defense_threshold":0.35,"high_defense_damage_bonus":0.04,"normal_damage_bonus":0.015}','劲透山岳，道御越厚，越能寻隙断脉。','地品趋吉机缘、秘境中期妖兽。',50,60),
('atk_heaven_wuxing','attack','heaven','五行夺势经','五行','ATK_ELEMENT_ADVANTAGE','{"element_swing_amplify":0.06}','借五行生克夺天地之势：克敌时放大优势，被克时减轻自身攻势惩罚。','天品趋吉机缘、秘境后期妖兽、世界BOSS。',50,70),
('atk_heaven_zhanming','attack','heaven','太虚斩命诀','斩命','ATK_EXECUTE','{"hp_threshold":0.30,"damage_bonus":0.05}','洞察生机衰微之隙，目标残血时杀势骤增。','天品趋吉机缘、秘境后期妖兽、世界BOSS。',50,80),
('atk_immortal_guifeng','attack','immortal','太初归锋典','稳攻','ATK_FINAL_DAMAGE','{"damage_bonus":0.04}','万法归于一锋，不借命格、不拘兵器，始终稳定增幅最终攻势。','仙品趋吉机缘、秘境圆满妖兽、困难世界BOSS。',50,90),
('atk_immortal_lingjue','attack','immortal','九霄凌绝经','久战','ATK_ROUND_STACK','{"per_stack_damage_bonus":0.008,"max_stacks":5}','九霄凌绝，战意层叠；首回合零层，此后每完整回合叠一层，最多五层。','仙品趋吉机缘、秘境圆满妖兽、困难世界BOSS。',50,100),
('def_yellow_huti','defense','yellow','凝元护体诀','减伤','DEF_REDUCTION','{"reduction":0.04}','凝元成罡，以稳定护体之力削减来袭伤害。','黄品趋吉机缘。',50,110),
('def_yellow_bifeng','defense','yellow','流云避锋诀','闪避','DEF_EVASION','{"evasion_bonus":0.03}','步随流云，提高闪避，仍受战斗命中上下限约束。','黄品趋吉机缘。',50,120),
('def_mystic_shouyi','defense','mystic','玄甲守一经','减伤','DEF_REDUCTION','{"reduction":0.035}','玄甲守一，护体威能更胜黄品法门。','玄品趋吉机缘、秘境初期妖兽。',50,130),
('def_mystic_bijie','defense','mystic','五行避劫诀','五抗','DEF_ELEMENT_RESIST','{"element_resistance":0.03}','调和五气，对来袭本命五行伤害提供额外抗性。','玄品趋吉机缘、秘境初期妖兽。',50,140),
('def_earth_zhenyue','defense','earth','厚土镇岳功','坚守','DEF_STEADFAST','{"reduction":0.02,"high_hp_threshold":0.50,"high_hp_extra_reduction":0.02}','厚土镇岳，生机充足时最为沉稳，兼具常驻护体。','地品趋吉机缘、秘境中期妖兽。',50,150),
('def_earth_huiyuan','defense','earth','玄水回元诀','回元','DEF_LOW_HP_RECOVERY','{"hp_threshold":0.30,"low_hp_reduction":0.02,"heal_ratio":0.025}','玄水回元；残血时增强护体，并在每场首次存活跌入三成生机时回元一次。','地品趋吉机缘、秘境中期妖兽。',50,160),
('def_heaven_huajie','defense','heaven','太虚化劫经','抗爆','DEF_OPENING_REDUCTION','{"opening_reduction":0.04,"later_reduction":0.015,"opening_rounds":2}','以太虚化劫，前两回合对爆发攻势尤其有效。','天品趋吉机缘、秘境后期妖兽、世界BOSS。',50,170),
('def_heaven_xiefeng','defense','heaven','清虚卸锋诀','卸锋','DEF_ATTACK_TECH_SUPPRESS','{"attack_tech_suppression":0.08,"reduction":0.015}','清虚卸锋，专门削弱敌方攻伐功法带来的额外增伤，并附带少量护体。','天品趋吉机缘、秘境后期妖兽、世界BOSS。',50,180),
('def_immortal_guiji','defense','immortal','万法归寂典','综合','DEF_ALL_SUPPRESS','{"element_advantage_suppression":0.08,"attack_tech_suppression":0.05,"reduction":0.015}','万法归寂，兼抑五行优势与攻伐增幅，自身亦有护体。','仙品趋吉机缘、秘境圆满妖兽、困难世界BOSS。',50,190),
('def_immortal_bumie','defense','immortal','九霄不灭身','不灭','DEF_LETHAL_GUARD','{"reduction":0.025,"lethal_guard_hp":1}','九霄炼身，常驻护体；唯有圆满后，每场首次致命伤害可保留一线生机。','仙品趋吉机缘、秘境圆满妖兽、困难世界BOSS。',50,200)
on conflict(code) do update set
 family=excluded.family,grade_code=excluded.grade_code,display_name=excluded.display_name,role_name=excluded.role_name,
 effect_code=excluded.effect_code,base_params=excluded.base_params,description=excluded.description,acquisition_hint=excluded.acquisition_hint,
 sort_order=excluded.sort_order,updated_at=clock_timestamp();

-- ---------- 玩家资产 / 快照 / 审计 ----------
create table if not exists public.character_combat_techniques_v220(
  character_id uuid not null,
  technique_code text not null references public.combat_technique_definitions_v220(code),
  level integer not null default 1 check(level>=1),
  is_mastered boolean not null default false,
  equipped boolean not null default false,
  learned_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp(),
  primary key(character_id,technique_code)
);
create unique index if not exists character_combat_techniques_v220_one_attack_equipped
on public.character_combat_techniques_v220(character_id)
where equipped and technique_code like 'atk_%';
create unique index if not exists character_combat_techniques_v220_one_defense_equipped
on public.character_combat_techniques_v220(character_id)
where equipped and technique_code like 'def_%';

create table if not exists public.combat_technique_shards_v220(
  character_id uuid not null,
  technique_code text not null references public.combat_technique_definitions_v220(code),
  quantity bigint not null default 0 check(quantity>=0),
  updated_at timestamptz not null default clock_timestamp(),
  primary key(character_id,technique_code)
);
create table if not exists public.combat_technique_books_v220(
  character_id uuid not null,
  technique_code text not null references public.combat_technique_definitions_v220(code),
  quantity bigint not null default 0 check(quantity>=0),
  updated_at timestamptz not null default clock_timestamp(),
  primary key(character_id,technique_code)
);
create table if not exists public.combat_technique_secret_pending_v220(
  context_ref text not null,
  character_id uuid not null,
  technique_code text not null references public.combat_technique_definitions_v220(code),
  quantity bigint not null default 0 check(quantity>=0),
  updated_at timestamptz not null default clock_timestamp(),
  primary key(context_ref,character_id,technique_code)
);
create table if not exists public.combat_technique_context_snapshots_v220(
  id bigserial primary key,
  context_kind text not null check(context_kind in ('destiny','secret','worldboss')),
  context_ref text not null,
  character_id uuid not null,
  attack_snapshot jsonb,
  defense_snapshot jsonb,
  config_version bigint not null,
  active boolean not null default true,
  created_at timestamptz not null default clock_timestamp(),
  closed_at timestamptz
);
create index if not exists combat_technique_context_lookup_v220
on public.combat_technique_context_snapshots_v220(context_kind,character_id,active,created_at desc);

create table if not exists public.combat_technique_request_ledger_v220(
  request_id uuid primary key,
  user_id uuid,
  character_id uuid,
  operation text not null,
  result jsonb not null,
  created_at timestamptz not null default clock_timestamp()
);
create table if not exists public.combat_technique_acquisition_ledger_v220(
  id bigserial primary key,
  character_id uuid not null,
  source_kind text not null,
  source_ref text not null,
  technique_code text,
  grade_code text,
  quantity integer not null default 0,
  roll numeric,
  rate numeric,
  at_risk boolean not null default false,
  created_at timestamptz not null default clock_timestamp(),
  unique(character_id,source_kind,source_ref)
);
create table if not exists public.combat_technique_pvp_transfer_ledger_v220(
  id bigserial primary key,
  context_ref text not null,
  winner_character_id uuid not null,
  loser_character_id uuid not null,
  pair_occurrence integer not null,
  raw_pending_total bigint not null,
  base_steal_count bigint not null,
  antifarm_multiplier numeric not null,
  actual_steal_count bigint not null,
  transferred jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default clock_timestamp()
);
create table if not exists public.combat_technique_announcement_ledger_v220(
  announcement_key text primary key,
  technique_code text not null references public.combat_technique_definitions_v220(code),
  character_id uuid not null,
  created_at timestamptz not null default clock_timestamp()
);

revoke all on public.combat_technique_settings_v220,public.combat_technique_definitions_v220,
 public.character_combat_techniques_v220,public.combat_technique_shards_v220,public.combat_technique_books_v220,
 public.combat_technique_secret_pending_v220,public.combat_technique_context_snapshots_v220,
 public.combat_technique_request_ledger_v220,public.combat_technique_acquisition_ledger_v220,
 public.combat_technique_pvp_transfer_ledger_v220,public.combat_technique_announcement_ledger_v220 from anon,authenticated;

-- ---------- 基础帮助函数 ----------
create or replace function public.combat_technique_grade_normalize_v220(p text)
returns text language sql immutable set search_path='' as $$
select case lower(coalesce(p,''))
 when 'yellow' then 'yellow' when '黄' then 'yellow' when '黄品' then 'yellow'
 when 'mystic' then 'mystic' when '玄' then 'mystic' when '玄品' then 'mystic'
 when 'earth' then 'earth' when '地' then 'earth' when '地品' then 'earth'
 when 'heaven' then 'heaven' when '天' then 'heaven' when '天品' then 'heaven'
 when 'immortal' then 'immortal' when '仙' then 'immortal' when '仙品' then 'immortal'
 else lower(coalesce(p,'')) end
$$;

create or replace function public.combat_technique_grade_max_level_v220(p_grade text)
returns integer language sql immutable set search_path='' as $$
select case public.combat_technique_grade_normalize_v220(p_grade)
 when 'yellow' then 6 when 'mystic' then 12 when 'earth' then 18 when 'heaven' then 24 when 'immortal' then 30 when 'exclusive' then 36 else 6 end
$$;
create or replace function public.combat_technique_grade_cost_factor_v220(p_grade text)
returns numeric language sql immutable set search_path='' as $$
select case public.combat_technique_grade_normalize_v220(p_grade)
 when 'yellow' then .75 when 'mystic' then .80 when 'earth' then .85 when 'heaven' then .90 when 'immortal' then .95 else 1.00 end
$$;

create or replace function public.combat_technique_active_character_v220()
returns uuid language sql security definer set search_path='' as $$
select public.equipment_v210_active_character_id()
$$;

create or replace function public.combat_technique_effect_params_v220(p_code text,p_level integer,p_mastered boolean)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  v_def public.combat_technique_definitions_v220%rowtype;
  v_set public.combat_technique_settings_v220%rowtype;
  v_factor numeric;
  v_result jsonb:='{}'::jsonb;
  v_pair record;
  v_value numeric;
begin
  select * into v_def from public.combat_technique_definitions_v220 where code=p_code and enabled;
  if v_def.code is null then return '{}'::jsonb; end if;
  select * into v_set from public.combat_technique_settings_v220 where singleton_id=1;
  v_factor:=1+greatest(0,coalesce(p_level,1)-1)*v_set.level_effect_growth;
  if coalesce(p_mastered,false) then v_factor:=v_factor*v_set.mastery_effect_multiplier; end if;
  for v_pair in select key,value from jsonb_each(v_def.base_params) loop
    begin
      v_value:=(v_pair.value#>>'{}')::numeric;
      if v_pair.key in ('opening_rounds','max_stacks','lethal_guard_hp') then
        v_result:=v_result||jsonb_build_object(v_pair.key,v_value);
      else
        v_result:=v_result||jsonb_build_object(v_pair.key,round(v_value*v_factor,8));
      end if;
    exception when others then
      v_result:=v_result||jsonb_build_object(v_pair.key,v_pair.value);
    end;
  end loop;
  return v_result;
end $$;

create or replace function public.combat_technique_current_snapshot_v220(p_character_id uuid,p_family text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_row record; v_set public.combat_technique_settings_v220%rowtype;
begin
  select * into v_set from public.combat_technique_settings_v220 where singleton_id=1;
  if not coalesce(v_set.enabled,true) then return null; end if;
  select c.technique_code,c.level,c.is_mastered,d.display_name,d.grade_code,d.family,d.effect_code,d.role_name
    into v_row
  from public.character_combat_techniques_v220 c
  join public.combat_technique_definitions_v220 d on d.code=c.technique_code
  where c.character_id=p_character_id and c.equipped and d.family=p_family and d.enabled
  limit 1;
  if v_row.technique_code is null then return null; end if;
  return jsonb_build_object(
    'code',v_row.technique_code,'name',v_row.display_name,'family',v_row.family,'grade_code',v_row.grade_code,
    'level',v_row.level,'is_mastered',v_row.is_mastered,'effect_code',v_row.effect_code,'role_name',v_row.role_name,
    'params',public.combat_technique_effect_params_v220(v_row.technique_code,v_row.level,v_row.is_mastered),
    'config_version',v_set.config_version
  );
end $$;

create or replace function public.combat_technique_capture_context_v220(p_character_id uuid,p_kind text,p_ref text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_set public.combat_technique_settings_v220%rowtype; v_attack jsonb;v_defense jsonb;
begin
  if p_kind not in ('destiny','secret','worldboss') then raise exception 'COMBAT_TECHNIQUE_CONTEXT_INVALID'; end if;
  select * into v_set from public.combat_technique_settings_v220 where singleton_id=1;
  v_attack:=public.combat_technique_current_snapshot_v220(p_character_id,'attack');
  v_defense:=public.combat_technique_current_snapshot_v220(p_character_id,'defense');
  update public.combat_technique_context_snapshots_v220 set active=false,closed_at=clock_timestamp()
    where context_kind=p_kind and character_id=p_character_id and active;
  insert into public.combat_technique_context_snapshots_v220(context_kind,context_ref,character_id,attack_snapshot,defense_snapshot,config_version)
  values(p_kind,coalesce(nullif(p_ref,''),gen_random_uuid()::text),p_character_id,v_attack,v_defense,v_set.config_version);
  return jsonb_build_object('attack',v_attack,'defense',v_defense,'config_version',v_set.config_version);
end $$;

create or replace function public.combat_technique_context_snapshot_v220(p_character_id uuid,p_family text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_kind text;v_snap jsonb;
begin
  v_kind:=nullif(current_setting('jiuxiao_v220.combat_context',true),'');
  if v_kind in ('destiny','secret','worldboss') then
    select case when p_family='attack' then attack_snapshot else defense_snapshot end into v_snap
    from public.combat_technique_context_snapshots_v220
    where context_kind=v_kind and character_id=p_character_id and active
    order by created_at desc limit 1;
    if v_snap is not null then return v_snap; end if;
  end if;
  return public.combat_technique_current_snapshot_v220(p_character_id,p_family);
end $$;

-- ---------- 当前普通功法实际掉率：按生产真实结构动态读取 ----------
-- 生产 opportunity_v4_technique_drop_rates 的一次普通功法判定是：
-- roll < main_rate => 主修；roll < main_rate+support_rate => 辅修。
-- 因而“普通功法实际总掉率”必须是 main_rate+support_rate，不能只取其中一列。
-- 旧普通功法生产表没有黄品行，因此本函数对yellow返回NULL；黄品攻防残卷由独立设置 opportunity_yellow_shard_rate 控制。
create or replace function public.combat_technique_ordinary_drop_rate_v220(p_grade text)
returns numeric language plpgsql stable security definer set search_path='' as $$
declare
  v_row jsonb;
  v_grade text;
  v_target text:=public.combat_technique_grade_normalize_v220(p_grade);
  v_main numeric;
  v_support numeric;
  v_rate numeric;
begin
  if v_target='yellow' then return null; end if;
  for v_row in execute 'select to_jsonb(t) from public.opportunity_v4_technique_drop_rates t' loop
    v_grade:=public.combat_technique_grade_normalize_v220(v_row->>'grade');
    begin
      v_main:=coalesce(nullif(v_row->>'main_rate','')::numeric,0);
      v_support:=coalesce(nullif(v_row->>'support_rate','')::numeric,0);
      v_rate:=v_main+v_support;
      if v_rate>1 then v_rate:=v_rate/100.0; end if;
      if v_rate between 0 and 1 and v_grade=v_target then return v_rate; end if;
    exception when others then
      null;
    end;
  end loop;
  return null;
end $$;

-- 攻防残卷“对应品级趋吉机缘内”的总池概率。
-- 黄品：独立GM配置，默认5%；玄/地/天/仙：普通功法真实总率×opportunity_relative_rate（默认20%=五分之一）。
create or replace function public.combat_technique_opportunity_shard_rate_v220(p_grade text)
returns numeric language plpgsql stable security definer set search_path='' as $$
declare
  v_grade text:=public.combat_technique_grade_normalize_v220(p_grade);
  v_set public.combat_technique_settings_v220%rowtype;
  v_ordinary numeric;
begin
  select * into v_set from public.combat_technique_settings_v220 where singleton_id=1;
  if not coalesce(v_set.enabled,false) then return 0; end if;
  if v_grade='yellow' then return greatest(0,least(1,coalesce(v_set.opportunity_yellow_shard_rate,0))); end if;
  v_ordinary:=public.combat_technique_ordinary_drop_rate_v220(v_grade);
  if v_ordinary is null then return null; end if;
  return greatest(0,least(1,v_ordinary*coalesce(v_set.opportunity_relative_rate,0)));
end $$;

-- ---------- 权威系统读取 ----------
create or replace function public.get_combat_technique_system_v220()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.combat_technique_active_character_v220();v_set jsonb;v_rows jsonb;v_rates jsonb;v_shard_rates jsonb;
begin
  select to_jsonb(s) into v_set from public.combat_technique_settings_v220 s where singleton_id=1;
  select coalesce(jsonb_agg(jsonb_build_object(
    'code',d.code,'family',d.family,'grade_code',d.grade_code,'name',d.display_name,'role_name',d.role_name,'effect_code',d.effect_code,
    'description',d.description,'acquisition_hint',d.acquisition_hint,'pool_weight',d.pool_weight,'enabled',d.enabled,'sort_order',d.sort_order,
    'level',coalesce(c.level,0),'max_level',public.combat_technique_grade_max_level_v220(d.grade_code),
    'is_mastered',coalesce(c.is_mastered,false),'learned',c.character_id is not null,'equipped',coalesce(c.equipped,false),
    'shards',coalesce(s.quantity,0),'books',coalesce(b.quantity,0),
    'current_effects',case when c.character_id is not null then public.combat_technique_effect_params_v220(d.code,c.level,c.is_mastered) else public.combat_technique_effect_params_v220(d.code,1,false) end,
    'level1_effects',public.combat_technique_effect_params_v220(d.code,1,false),
    'mastered_effects',public.combat_technique_effect_params_v220(d.code,public.combat_technique_grade_max_level_v220(d.grade_code),true),
    'upgrade_cost',case when c.character_id is null or c.is_mastered then 0 else ceil(1049*power(greatest(1,c.level),2)*public.combat_technique_grade_cost_factor_v220(d.grade_code)*
      (case when d.family='attack' then (select attack_upgrade_multiplier from public.combat_technique_settings_v220 where singleton_id=1) else (select defense_upgrade_multiplier from public.combat_technique_settings_v220 where singleton_id=1) end)*
      (case when c.level>=public.combat_technique_grade_max_level_v220(d.grade_code) then (select mastery_cost_multiplier from public.combat_technique_settings_v220 where singleton_id=1) else 1 end))::bigint end
  ) order by d.sort_order),'[]'::jsonb) into v_rows
  from public.combat_technique_definitions_v220 d
  left join public.character_combat_techniques_v220 c on c.character_id=v_char and c.technique_code=d.code
  left join public.combat_technique_shards_v220 s on s.character_id=v_char and s.technique_code=d.code
  left join public.combat_technique_books_v220 b on b.character_id=v_char and b.technique_code=d.code
  ;
  v_rates:=jsonb_build_object(
    'yellow',null,
    'mystic',public.combat_technique_ordinary_drop_rate_v220('mystic'),
    'earth',public.combat_technique_ordinary_drop_rate_v220('earth'),
    'heaven',public.combat_technique_ordinary_drop_rate_v220('heaven'),
    'immortal',public.combat_technique_ordinary_drop_rate_v220('immortal')
  );
  v_shard_rates:=jsonb_build_object(
    'yellow',public.combat_technique_opportunity_shard_rate_v220('yellow'),
    'mystic',public.combat_technique_opportunity_shard_rate_v220('mystic'),
    'earth',public.combat_technique_opportunity_shard_rate_v220('earth'),
    'heaven',public.combat_technique_opportunity_shard_rate_v220('heaven'),
    'immortal',public.combat_technique_opportunity_shard_rate_v220('immortal')
  );
  return jsonb_build_object('status','ok','version','V2.2.0','character_id',v_char,'settings',v_set,'ordinary_drop_rates',v_rates,'opportunity_shard_rates',v_shard_rates,'techniques',v_rows,
    'pending_secret_shards',coalesce((select sum(quantity) from public.combat_technique_secret_pending_v220 where character_id=v_char),0));
end $$;

-- 天/仙品传承全服首位参悟者写入九霄界闻。界闻表缺失或字段不兼容时静默跳过，不阻断核心参悟事务。
create or replace function public.combat_technique_try_world_announcement_v220(p_character_id uuid,p_technique_code text)
returns boolean language plpgsql security definer set search_path='' as $$
declare v_def public.combat_technique_definitions_v220%rowtype;v_key text;v_player text:='某位修士';v_level int;v_content text;
begin
  select * into v_def from public.combat_technique_definitions_v220 where code=p_technique_code;
  if v_def.code is null or v_def.grade_code not in ('heaven','immortal') then return false;end if;
  v_key:='server_first_learn:'||v_def.code;
  perform pg_advisory_xact_lock(hashtextextended('v220-world-event:'||v_def.code,22031));
  if exists(select 1 from public.combat_technique_announcement_ledger_v220 where announcement_key=v_key) then return false;end if;
  if to_regclass('public.jiuxiao_world_events') is null then return false;end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='jiuxiao_world_events' and column_name='event_type')
     or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='jiuxiao_world_events' and column_name='title')
     or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='jiuxiao_world_events' and column_name='content')
     or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='jiuxiao_world_events' and column_name='event_level')
     or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='jiuxiao_world_events' and column_name='is_pinned')
     or not exists(select 1 from information_schema.columns where table_schema='public' and table_name='jiuxiao_world_events' and column_name='created_at') then return false;end if;
  begin execute 'select name::text from public.player_characters where id=$1' into v_player using p_character_id;exception when others then v_player:='某位修士';end;
  v_player:=coalesce(nullif(v_player,''),'某位修士');
  v_level:=case when v_def.grade_code='immortal' then 4 else 3 end;
  v_content:='天地有感：'||v_player||'于残卷之中补全'||case v_def.grade_code when 'immortal' then '仙品' else '天品' end||'传承《'||v_def.display_name||'》。';
  begin
    execute 'insert into public.jiuxiao_world_events(event_type,title,content,event_level,is_pinned,created_at) values($1,$2,$3,$4,false,clock_timestamp())'
      using 'combat_technique_v220','天地有感',v_content,v_level;
    insert into public.combat_technique_announcement_ledger_v220(announcement_key,technique_code,character_id) values(v_key,v_def.code,p_character_id);
    return true;
  exception when others then return false;end;
end $$;

-- ---------- 残卷/道卷/参悟/装备/升级 ----------
create or replace function public.combine_combat_technique_shards_v220(p_technique_code text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.combat_technique_active_character_v220();v_need integer;v_have bigint;v_result jsonb;v_old jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select result into v_old from public.combat_technique_request_ledger_v220 where request_id=p_request_id and user_id=auth.uid();if v_old is not null then return v_old||jsonb_build_object('duplicate_request',true);end if;
  perform pg_advisory_xact_lock(hashtextextended('v220-combine:'||p_request_id::text,22001));
  select shard_combine_count into v_need from public.combat_technique_settings_v220 where singleton_id=1;
  select quantity into v_have from public.combat_technique_shards_v220 where character_id=v_char and technique_code=p_technique_code for update;
  if coalesce(v_have,0)<v_need then raise exception 'COMBAT_TECHNIQUE_SHARDS_INSUFFICIENT'; end if;
  update public.combat_technique_shards_v220 set quantity=quantity-v_need,updated_at=clock_timestamp() where character_id=v_char and technique_code=p_technique_code;
  insert into public.combat_technique_books_v220(character_id,technique_code,quantity) values(v_char,p_technique_code,1)
  on conflict(character_id,technique_code) do update set quantity=public.combat_technique_books_v220.quantity+1,updated_at=clock_timestamp();
  v_result:=jsonb_build_object('status','ok','technique_code',p_technique_code,'consumed',v_need,'book_gain',1,
    'shards_after',v_have-v_need,'books_after',(select quantity from public.combat_technique_books_v220 where character_id=v_char and technique_code=p_technique_code));
  insert into public.combat_technique_request_ledger_v220 values(p_request_id,auth.uid(),v_char,'combine',v_result,clock_timestamp());return v_result;
end $$;

create or replace function public.learn_combat_technique_v220(p_technique_code text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.combat_technique_active_character_v220();v_book bigint;v_result jsonb;v_old jsonb;v_announced boolean:=false;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select result into v_old from public.combat_technique_request_ledger_v220 where request_id=p_request_id and user_id=auth.uid();if v_old is not null then return v_old||jsonb_build_object('duplicate_request',true);end if;
  if exists(select 1 from public.character_combat_techniques_v220 where character_id=v_char and technique_code=p_technique_code) then raise exception 'COMBAT_TECHNIQUE_ALREADY_LEARNED'; end if;
  select quantity into v_book from public.combat_technique_books_v220 where character_id=v_char and technique_code=p_technique_code for update;
  if coalesce(v_book,0)<1 then raise exception 'COMBAT_TECHNIQUE_BOOK_REQUIRED'; end if;
  update public.combat_technique_books_v220 set quantity=quantity-1,updated_at=clock_timestamp() where character_id=v_char and technique_code=p_technique_code;
  insert into public.character_combat_techniques_v220(character_id,technique_code,level) values(v_char,p_technique_code,1);
  v_announced:=public.combat_technique_try_world_announcement_v220(v_char,p_technique_code);
  v_result:=jsonb_build_object('status','ok','technique_code',p_technique_code,'learned',true,'level',1,'world_announcement',v_announced);
  insert into public.combat_technique_request_ledger_v220 values(p_request_id,auth.uid(),v_char,'learn',v_result,clock_timestamp());return v_result;
end $$;

create or replace function public.set_combat_technique_equipped_v220(p_family text,p_technique_code text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.combat_technique_active_character_v220();v_def public.combat_technique_definitions_v220%rowtype;
begin
  if p_family not in ('attack','defense') then raise exception 'COMBAT_TECHNIQUE_FAMILY_INVALID'; end if;
  update public.character_combat_techniques_v220 c set equipped=false,updated_at=clock_timestamp()
  from public.combat_technique_definitions_v220 d where c.character_id=v_char and c.technique_code=d.code and d.family=p_family and c.equipped;
  if p_technique_code is not null and p_technique_code<>'' then
    select * into v_def from public.combat_technique_definitions_v220 where code=p_technique_code and family=p_family and enabled;
    if v_def.code is null then raise exception 'COMBAT_TECHNIQUE_INVALID'; end if;
    update public.character_combat_techniques_v220 set equipped=true,updated_at=clock_timestamp() where character_id=v_char and technique_code=p_technique_code;
    if not found then raise exception 'COMBAT_TECHNIQUE_NOT_LEARNED'; end if;
  end if;
  return jsonb_build_object('status','ok','family',p_family,'equipped_code',nullif(p_technique_code,''));
end $$;

create or replace function public.upgrade_combat_technique_v220(p_technique_code text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.combat_technique_active_character_v220();v_row public.character_combat_techniques_v220%rowtype;v_def public.combat_technique_definitions_v220%rowtype;v_set public.combat_technique_settings_v220%rowtype;v_max int;v_cost bigint;v_mult numeric;v_after bigint;v_result jsonb;v_old jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select result into v_old from public.combat_technique_request_ledger_v220 where request_id=p_request_id and user_id=auth.uid();if v_old is not null then return v_old||jsonb_build_object('duplicate_request',true);end if;
  perform pg_advisory_xact_lock(hashtextextended('v220-upgrade:'||p_request_id::text,22002));
  select * into v_row from public.character_combat_techniques_v220 where character_id=v_char and technique_code=p_technique_code for update;
  if v_row.technique_code is null then raise exception 'COMBAT_TECHNIQUE_NOT_LEARNED'; end if;
  if v_row.is_mastered then raise exception 'COMBAT_TECHNIQUE_ALREADY_MASTERED'; end if;
  select * into v_def from public.combat_technique_definitions_v220 where code=p_technique_code;
  select * into v_set from public.combat_technique_settings_v220 where singleton_id=1;
  v_max:=public.combat_technique_grade_max_level_v220(v_def.grade_code);v_mult:=case when v_def.family='attack' then v_set.attack_upgrade_multiplier else v_set.defense_upgrade_multiplier end;
  v_cost:=ceil(1049*power(greatest(1,v_row.level),2)*public.combat_technique_grade_cost_factor_v220(v_def.grade_code)*v_mult*(case when v_row.level>=v_max then v_set.mastery_cost_multiplier else 1 end))::bigint;
  v_after:=public.equipment_v210_debit_spirit_stone_v243(v_char,v_cost);
  if v_row.level>=v_max then
    update public.character_combat_techniques_v220 set is_mastered=true,updated_at=clock_timestamp() where character_id=v_char and technique_code=p_technique_code;
  else
    update public.character_combat_techniques_v220 set level=level+1,updated_at=clock_timestamp() where character_id=v_char and technique_code=p_technique_code;
  end if;
  select * into v_row from public.character_combat_techniques_v220 where character_id=v_char and technique_code=p_technique_code;
  v_result:=jsonb_build_object('status','ok','technique_code',p_technique_code,'level',v_row.level,'is_mastered',v_row.is_mastered,'cost',v_cost,'spirit_stones_after',v_after,'effects',public.combat_technique_effect_params_v220(p_technique_code,v_row.level,v_row.is_mastered));
  insert into public.combat_technique_request_ledger_v220 values(p_request_id,auth.uid(),v_char,'upgrade',v_result,clock_timestamp());return v_result;
end $$;

create or replace function public.exchange_combat_technique_shards_v220(p_target_code text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.combat_technique_active_character_v220();v_set public.combat_technique_settings_v220%rowtype;v_target public.combat_technique_definitions_v220%rowtype;v_need int;v_total bigint;v_take bigint;v_row record;v_consumed jsonb:='[]'::jsonb;v_result jsonb;v_old jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select result into v_old from public.combat_technique_request_ledger_v220 where request_id=p_request_id and user_id=auth.uid();if v_old is not null then return v_old||jsonb_build_object('duplicate_request',true);end if;
  select * into v_set from public.combat_technique_settings_v220 where singleton_id=1;
  if not v_set.shard_exchange_enabled then raise exception 'COMBAT_TECHNIQUE_SHARD_EXCHANGE_DISABLED'; end if;
  select * into v_target from public.combat_technique_definitions_v220 where code=p_target_code and enabled;if v_target.code is null then raise exception 'COMBAT_TECHNIQUE_INVALID';end if;
  v_need:=v_set.shard_exchange_cost;
  select coalesce(sum(s.quantity),0) into v_total from public.combat_technique_shards_v220 s join public.combat_technique_definitions_v220 d on d.code=s.technique_code where s.character_id=v_char and d.grade_code=v_target.grade_code and s.technique_code<>p_target_code;
  if v_total<v_need then raise exception 'COMBAT_TECHNIQUE_EXCHANGE_SHARDS_INSUFFICIENT'; end if;
  for v_row in select s.technique_code,s.quantity from public.combat_technique_shards_v220 s join public.combat_technique_definitions_v220 d on d.code=s.technique_code where s.character_id=v_char and d.grade_code=v_target.grade_code and s.technique_code<>p_target_code and s.quantity>0 order by s.quantity desc,s.technique_code for update of s loop
    exit when v_need<=0;v_take:=least(v_need,v_row.quantity);
    update public.combat_technique_shards_v220 set quantity=quantity-v_take,updated_at=clock_timestamp() where character_id=v_char and technique_code=v_row.technique_code;
    v_consumed:=v_consumed||jsonb_build_array(jsonb_build_object('code',v_row.technique_code,'quantity',v_take));v_need:=v_need-v_take;
  end loop;
  insert into public.combat_technique_shards_v220(character_id,technique_code,quantity) values(v_char,p_target_code,v_set.shard_exchange_gain)
  on conflict(character_id,technique_code) do update set quantity=public.combat_technique_shards_v220.quantity+excluded.quantity,updated_at=clock_timestamp();
  v_result:=jsonb_build_object('status','ok','target_code',p_target_code,'gain',v_set.shard_exchange_gain,'consumed',v_consumed);
  insert into public.combat_technique_request_ledger_v220 values(p_request_id,auth.uid(),v_char,'exchange',v_result,clock_timestamp());return v_result;
end $$;

-- ---------- 现有修炼/专属功法升级默认×10，服务端权威 ----------
create or replace function public.combat_technique_scale_upgrade_costs_v220(p_system jsonb,p_multiplier numeric)
returns jsonb language plpgsql stable set search_path='' as $$
declare v_arr jsonb:='[]'::jsonb;v_row jsonb;v_cost numeric;
begin
  if p_system is null then return p_system; end if;
  for v_row in select value from jsonb_array_elements(coalesce(p_system->'techniques','[]'::jsonb)) loop
    begin
      v_cost:=coalesce(nullif(v_row->>'upgrade_cost','')::numeric,nullif(v_row->>'next_upgrade_cost','')::numeric,0);
      if v_row ? 'upgrade_cost' then v_row:=jsonb_set(v_row,'{upgrade_cost}',to_jsonb(ceil(v_cost*p_multiplier)::bigint));end if;
      if v_row ? 'next_upgrade_cost' then v_row:=jsonb_set(v_row,'{next_upgrade_cost}',to_jsonb(ceil(v_cost*p_multiplier)::bigint));end if;
    exception when others then null; end;
    v_arr:=v_arr||jsonb_build_array(v_row);
  end loop;
  return jsonb_set(p_system,'{techniques}',v_arr,true);
end $$;

create or replace function public.get_cultivation_technique_system_v220()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb;v_mult numeric;begin v_result:=public.get_technique_system_v2();select cultivation_upgrade_multiplier into v_mult from public.combat_technique_settings_v220 where singleton_id=1;return public.combat_technique_scale_upgrade_costs_v220(v_result,v_mult);end $$;
create or replace function public.get_exclusive_technique_system_v220()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb;v_mult numeric;begin v_result:=public.get_exclusive_technique_system_v1();select exclusive_upgrade_multiplier into v_mult from public.combat_technique_settings_v220 where singleton_id=1;return public.combat_technique_scale_upgrade_costs_v220(v_result,v_mult);end $$;

create or replace function public.upgrade_cultivation_technique_v220(p_character_technique_id uuid,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.combat_technique_active_character_v220();v_sys jsonb;v_row jsonb;v_base bigint:=0;v_mult numeric;v_extra bigint;v_after bigint;v_result jsonb;v_old jsonb;
begin
 if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED';end if;select result into v_old from public.combat_technique_request_ledger_v220 where request_id=p_request_id and user_id=auth.uid();if v_old is not null then return v_old||jsonb_build_object('duplicate_request',true);end if;
 v_sys:=public.get_technique_system_v2();for v_row in select value from jsonb_array_elements(coalesce(v_sys->'techniques','[]'::jsonb)) loop if coalesce(v_row->>'character_technique_id',v_row->>'id')=p_character_technique_id::text then v_base:=coalesce(nullif(v_row->>'upgrade_cost','')::bigint,0);exit;end if;end loop;
 if v_base<=0 then raise exception 'CULTIVATION_TECHNIQUE_UPGRADE_COST_NOT_FOUND';end if;select cultivation_upgrade_multiplier into v_mult from public.combat_technique_settings_v220 where singleton_id=1;v_extra:=greatest(0,ceil(v_base*(v_mult-1))::bigint);if v_extra>0 then v_after:=public.equipment_v210_debit_spirit_stone_v243(v_char,v_extra);end if;
 v_result:=public.upgrade_technique_v0154(p_character_technique_id,p_request_id);v_result:=coalesce(v_result,'{}'::jsonb)||jsonb_build_object('v220_multiplier',v_mult,'v220_total_cost',ceil(v_base*v_mult)::bigint,'spirit_stones_after',coalesce((v_result->>'spirit_stones_after')::bigint,v_after));insert into public.combat_technique_request_ledger_v220 values(p_request_id,auth.uid(),v_char,'cultivation_upgrade',v_result,clock_timestamp());return v_result;
end $$;

create or replace function public.upgrade_exclusive_technique_v220(p_character_exclusive_id uuid,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.combat_technique_active_character_v220();v_sys jsonb;v_row jsonb;v_base bigint:=0;v_mult numeric;v_extra bigint;v_after bigint;v_result jsonb;v_old jsonb;
begin
 if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED';end if;select result into v_old from public.combat_technique_request_ledger_v220 where request_id=p_request_id and user_id=auth.uid();if v_old is not null then return v_old||jsonb_build_object('duplicate_request',true);end if;
 v_sys:=public.get_exclusive_technique_system_v1();for v_row in select value from jsonb_array_elements(coalesce(v_sys->'techniques','[]'::jsonb)) loop if coalesce(v_row->>'id',v_row->>'character_exclusive_id')=p_character_exclusive_id::text then v_base:=coalesce(nullif(v_row->>'next_upgrade_cost','')::bigint,nullif(v_row->>'upgrade_cost','')::bigint,0);exit;end if;end loop;
 if v_base<=0 then raise exception 'EXCLUSIVE_TECHNIQUE_UPGRADE_COST_NOT_FOUND';end if;select exclusive_upgrade_multiplier into v_mult from public.combat_technique_settings_v220 where singleton_id=1;v_extra:=greatest(0,ceil(v_base*(v_mult-1))::bigint);if v_extra>0 then v_after:=public.equipment_v210_debit_spirit_stone_v243(v_char,v_extra);end if;
 v_result:=public.upgrade_exclusive_technique_v0154(p_character_exclusive_id,p_request_id);v_result:=coalesce(v_result,'{}'::jsonb)||jsonb_build_object('v220_multiplier',v_mult,'v220_total_cost',ceil(v_base*v_mult)::bigint,'spirit_stones_after',coalesce((v_result->>'spirit_stones_after')::bigint,v_after));insert into public.combat_technique_request_ledger_v220 values(p_request_id,auth.uid(),v_char,'exclusive_upgrade',v_result,clock_timestamp());return v_result;
end $$;

-- ---------- 残卷随机发放 ----------
create or replace function public.combat_technique_pick_code_v220(p_grade text,p_family text default null)
returns text language plpgsql volatile security definer set search_path='' as $$
declare v_total numeric;v_roll numeric;v_sum numeric:=0;v_row record;begin
 select sum(pool_weight) into v_total from public.combat_technique_definitions_v220 where enabled and grade_code=public.combat_technique_grade_normalize_v220(p_grade) and (p_family is null or family=p_family);if coalesce(v_total,0)<=0 then return null;end if;v_roll:=random()*v_total;
 for v_row in select code,pool_weight from public.combat_technique_definitions_v220 where enabled and grade_code=public.combat_technique_grade_normalize_v220(p_grade) and (p_family is null or family=p_family) order by sort_order loop v_sum:=v_sum+v_row.pool_weight;if v_roll<v_sum then return v_row.code;end if;end loop;return null;end $$;

create or replace function public.combat_technique_grant_shard_v220(p_character_id uuid,p_grade text,p_quantity integer,p_pending_ref text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_set public.combat_technique_settings_v220%rowtype;v_family text;v_code text;v_name text;begin
 select * into v_set from public.combat_technique_settings_v220 where singleton_id=1;
 if not coalesce(v_set.enabled,true) or coalesce(p_quantity,0)<=0 then return null;end if;
 if random() < v_set.opportunity_attack_weight/greatest(1,v_set.opportunity_attack_weight+v_set.opportunity_defense_weight) then v_family:='attack';else v_family:='defense';end if;
 v_code:=public.combat_technique_pick_code_v220(p_grade,v_family);if v_code is null then return null;end if;
 select display_name into v_name from public.combat_technique_definitions_v220 where code=v_code;
 if p_pending_ref is not null then
   insert into public.combat_technique_secret_pending_v220(context_ref,character_id,technique_code,quantity) values(p_pending_ref,p_character_id,v_code,p_quantity)
   on conflict(context_ref,character_id,technique_code) do update set quantity=public.combat_technique_secret_pending_v220.quantity+excluded.quantity,updated_at=clock_timestamp();
 else
   insert into public.combat_technique_shards_v220(character_id,technique_code,quantity) values(p_character_id,v_code,p_quantity)
   on conflict(character_id,technique_code) do update set quantity=public.combat_technique_shards_v220.quantity+excluded.quantity,updated_at=clock_timestamp();
 end if;
 return jsonb_build_object('technique_code',v_code,'technique_name',v_name,'family',v_family,'quantity',p_quantity,'at_risk',p_pending_ref is not null);
end $$;

-- ---------- 机缘：包装现有settle，按真实settlement batch逐条判定，概率=普通功法*20% ----------
do $wrap_opportunity$
begin
  if to_regprocedure('public.settle_opportunity_v4_pre_v220(boolean)') is null then
    execute 'alter function public.settle_opportunity_v4(boolean) rename to settle_opportunity_v4_pre_v220';
  end if;
end $wrap_opportunity$;

create or replace function public.settle_opportunity_v4(p_settle_cultivation boolean default true)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_result jsonb;
  v_char uuid:=public.combat_technique_active_character_v220();
  v_prev_batch uuid;
  v_batch uuid;
  v_event record;
  v_grade text;
  v_ref text;
  v_rate numeric;
  v_roll numeric;
  v_grant jsonb;
  v_set public.combat_technique_settings_v220%rowtype;
  v_awards jsonb:='[]'::jsonb;
begin
  -- 先记住调用前最后一个批次。原settle对同一角色会锁角色/机缘状态；
  -- 一次调用最多生成一个新的 settlement batch，因此可无歧义定位本次真实机缘明细。
  select id into v_prev_batch
  from public.opportunity_v4_settlement_batches
  where character_id=v_char
  order by created_at desc limit 1;

  v_result:=public.settle_opportunity_v4_pre_v220(p_settle_cultivation);
  select * into v_set from public.combat_technique_settings_v220 where singleton_id=1;
  if not coalesce(v_set.enabled,true) then
    return v_result||jsonb_build_object('combat_technique_v220',jsonb_build_object('system','disabled'));
  end if;

  select id into v_batch
  from public.opportunity_v4_settlement_batches
  where character_id=v_char
  order by created_at desc limit 1;
  if v_batch is not distinct from v_prev_batch then v_batch:=null; end if;

  if v_batch is not null then
    for v_event in
      select id,rarity,path_key,scheduled_at
      from public.opportunity_v3_results
      where character_id=v_char and settlement_batch_id=v_batch
      order by scheduled_at,id
    loop
      if lower(coalesce(v_event.path_key,''))<>'auspicious' then continue; end if;
      v_grade:=public.combat_technique_grade_normalize_v220(v_event.rarity);
      if v_grade not in ('yellow','mystic','earth','heaven','immortal') then continue; end if;
      v_ref:=v_event.id::text;
      if exists(
        select 1 from public.combat_technique_acquisition_ledger_v220
        where character_id=v_char and source_kind='opportunity' and source_ref=v_ref
      ) then continue; end if;

      v_rate:=coalesce(public.combat_technique_opportunity_shard_rate_v220(v_grade),0);
      v_roll:=random();
      v_grant:=null;
      if v_roll<v_rate then
        v_grant:=public.combat_technique_grant_shard_v220(v_char,v_grade,1,null);
      end if;

      insert into public.combat_technique_acquisition_ledger_v220(
        character_id,source_kind,source_ref,technique_code,grade_code,quantity,roll,rate,at_risk
      ) values(
        v_char,'opportunity',v_ref,v_grant->>'technique_code',v_grade,
        case when v_grant is null then 0 else 1 end,v_roll,v_rate,false
      ) on conflict do nothing;

      if v_grant is not null then
        v_awards:=v_awards||jsonb_build_array(
          v_grant||jsonb_build_object(
            'grade_code',v_grade,
            'source','opportunity',
            'ordinary_total_rate',public.combat_technique_ordinary_drop_rate_v220(v_grade),
            'combat_shard_rate',v_rate,
            'yellow_independent_rate',case when v_grade='yellow' then v_set.opportunity_yellow_shard_rate else null end,
            'opportunity_result_id',v_ref
          )
        );
      end if;
    end loop;
  end if;

  return v_result||jsonb_build_object(
    'combat_technique_v220',
    jsonb_build_object(
      'system','enabled',
      'relative_to_ordinary',v_set.opportunity_relative_rate,
      'settlement_batch_id',v_batch,
      'awards',v_awards
    )
  );
end $$;

-- ---------- 天命榜：开战时锁定双方功法快照 ----------
do $wrap_destiny$
begin
 if to_regprocedure('public.challenge_battle_power_bcombat01_pre_v220(uuid,uuid)') is null then
   execute 'alter function public.challenge_battle_power_bcombat01(uuid,uuid) rename to challenge_battle_power_bcombat01_pre_v220';
 end if;
end $wrap_destiny$;

create or replace function public.challenge_battle_power_bcombat01(p_target_character_id uuid,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb;v_char uuid:=public.combat_technique_active_character_v220();v_ref text:=coalesce(p_request_id::text,gen_random_uuid()::text);
begin
 if p_target_character_id is null then raise exception 'BCOMBAT01_TARGET_REQUIRED';end if;
 perform set_config('jiuxiao_v220.combat_context','destiny',true);
 perform public.combat_technique_capture_context_v220(v_char,'destiny',v_ref);
 perform public.combat_technique_capture_context_v220(p_target_character_id,'destiny',v_ref);
 v_result:=public.challenge_battle_power_bcombat01_pre_v220(p_target_character_id,p_request_id);
 update public.combat_technique_context_snapshots_v220 set active=false,closed_at=clock_timestamp()
  where context_kind='destiny' and context_ref=v_ref and character_id in (v_char,p_target_character_id) and active;
 return coalesce(v_result,'{}'::jsonb)||jsonb_build_object('combat_technique_snapshot_v220',true);
end $$;

-- ---------- 秘境快照 / 独立残卷 / 夺卷反对刷 ----------
create or replace function public.combat_technique_secret_context_ref_v220(p_character_id uuid)
returns text language sql stable security definer set search_path='' as $$
select context_ref from public.combat_technique_context_snapshots_v220 where context_kind='secret' and character_id=p_character_id and active order by created_at desc limit 1
$$;

create or replace function public.combat_technique_secret_drop_rate_v220(p_stage text)
returns numeric language plpgsql stable security definer set search_path='' as $$
declare v public.combat_technique_settings_v220%rowtype;begin select * into v from public.combat_technique_settings_v220 where singleton_id=1;return case lower(coalesce(p_stage,'')) when 'early' then v.secret_mystic_rate when 'middle' then v.secret_earth_rate when 'late' then v.secret_heaven_rate when 'complete' then v.secret_immortal_rate else 0 end;end $$;
create or replace function public.combat_technique_secret_stage_grade_v220(p_stage text)
returns text language sql immutable set search_path='' as $$select case lower(coalesce(p_stage,'')) when 'early' then 'mystic' when 'middle' then 'earth' when 'late' then 'heaven' when 'complete' then 'immortal' else null end$$;

create or replace function public.combat_technique_steal_secret_pending_v220(p_winner uuid,p_loser uuid,p_context_ref text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_set public.combat_technique_settings_v220%rowtype;v_total bigint;v_base bigint;v_occ integer;v_mult numeric;v_take bigint;v_left bigint;v_code text;v_name text;v_winner_ref text;v_transferred jsonb:='[]'::jsonb;
begin
 select * into v_set from public.combat_technique_settings_v220 where singleton_id=1;
 if not coalesce(v_set.enabled,true) then return jsonb_build_object('actual_steal',0,'reason','system_disabled');end if;
 select coalesce(sum(quantity),0) into v_total from public.combat_technique_secret_pending_v220 where context_ref=p_context_ref and character_id=p_loser and quantity>0;
 v_base:=floor(v_total*v_set.secret_pvp_steal_rate)::bigint;
 select count(*)+1 into v_occ from public.combat_technique_pvp_transfer_ledger_v220 where winner_character_id=p_winner and loser_character_id=p_loser and created_at>=clock_timestamp()-make_interval(hours=>v_set.secret_antifarm_window_hours);
 v_mult:=case when v_occ<=1 then 1 when v_occ=2 then v_set.secret_antifarm_second_multiplier else v_set.secret_antifarm_third_multiplier end;
 v_take:=floor(v_base*v_mult)::bigint;v_left:=v_take;v_winner_ref:=public.combat_technique_secret_context_ref_v220(p_winner);
 -- 每次按“真实剩余张数”加权抽取一个单位，保证3种各1张时确实是从3个真实单位随机抽，而不是按品种等权整堆搬走。
 while v_left>0 loop
   select p.technique_code into v_code
   from public.combat_technique_secret_pending_v220 p
   where p.context_ref=p_context_ref and p.character_id=p_loser and p.quantity>0
   order by (-ln(greatest(random(),0.000000000001))/greatest(1,p.quantity::numeric)) asc limit 1;
   exit when v_code is null;
   update public.combat_technique_secret_pending_v220 set quantity=quantity-1,updated_at=clock_timestamp() where context_ref=p_context_ref and character_id=p_loser and technique_code=v_code and quantity>0;
   if not found then continue;end if;
   if v_winner_ref is not null then
     insert into public.combat_technique_secret_pending_v220(context_ref,character_id,technique_code,quantity) values(v_winner_ref,p_winner,v_code,1)
     on conflict(context_ref,character_id,technique_code) do update set quantity=public.combat_technique_secret_pending_v220.quantity+1,updated_at=clock_timestamp();
   else
     -- 胜者没有可识别的进行中秘境上下文时直接安全入账，避免使用永远无法claim的伪pending上下文造成残卷丢失。
     insert into public.combat_technique_shards_v220(character_id,technique_code,quantity) values(p_winner,v_code,1)
     on conflict(character_id,technique_code) do update set quantity=public.combat_technique_shards_v220.quantity+1,updated_at=clock_timestamp();
   end if;
   select display_name into v_name from public.combat_technique_definitions_v220 where code=v_code;
   v_transferred:=v_transferred||jsonb_build_array(jsonb_build_object('code',v_code,'name',v_name,'quantity',1,'winner_pending',v_winner_ref is not null));v_left:=v_left-1;
 end loop;
 insert into public.combat_technique_pvp_transfer_ledger_v220(context_ref,winner_character_id,loser_character_id,pair_occurrence,raw_pending_total,base_steal_count,antifarm_multiplier,actual_steal_count,transferred)
 values(p_context_ref,p_winner,p_loser,v_occ,v_total,v_base,v_mult,v_take-v_left,v_transferred);
 return jsonb_build_object('pending_total',v_total,'base_steal',v_base,'pair_occurrence',v_occ,'antifarm_multiplier',v_mult,'actual_steal',v_take-v_left,'transferred',v_transferred);
end $$;

create or replace function public.combat_technique_process_secret_result_v220(p_result jsonb,p_context_ref text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.combat_technique_active_character_v220();v_event jsonb;v_stage text;v_grade text;v_ref text;v_rate numeric;v_roll numeric;v_grant jsonb;v_events jsonb;v_set public.combat_technique_settings_v220%rowtype;v_opp uuid;v_outcome text;v_transfer jsonb;v_summary jsonb:='[]'::jsonb;
begin
 select * into v_set from public.combat_technique_settings_v220 where singleton_id=1;if not coalesce(v_set.enabled,true) then return '[]'::jsonb;end if;v_events:=coalesce(p_result#>'{run,events}',p_result->'events','[]'::jsonb);
 if jsonb_typeof(v_events)<>'array' then return '[]'::jsonb;end if;
 for v_event in select value from jsonb_array_elements(v_events) loop
   v_ref:=p_context_ref||':'||coalesce(v_event->>'event_id',v_event->>'id',v_event->>'minute_index',md5(v_event::text));
   if v_event->>'event_type'='monster' then
     v_grant:=null;
     if exists(select 1 from public.combat_technique_acquisition_ledger_v220 where character_id=v_char and source_kind='secret_monster' and source_ref=v_ref) then continue;end if;
     v_stage:=coalesce(v_event#>>'{opponent,minor_stage}',v_event->>'minor_stage',v_event->>'monster_stage');v_grade:=public.combat_technique_secret_stage_grade_v220(v_stage);v_rate:=public.combat_technique_secret_drop_rate_v220(v_stage);v_roll:=random();
     -- 只有击败妖兽才判定。outcome未知时以事件内容明确的胜利标志优先；默认monster事件由原系统的胜利事件产生。
     if v_grade is not null and coalesce(v_event->>'outcome','win') not in ('loss','defeat','lost') and v_roll<v_rate then v_grant:=public.combat_technique_grant_shard_v220(v_char,v_grade,v_set.secret_drop_quantity,p_context_ref);end if;
     insert into public.combat_technique_acquisition_ledger_v220(character_id,source_kind,source_ref,technique_code,grade_code,quantity,roll,rate,at_risk) values(v_char,'secret_monster',v_ref,v_grant->>'technique_code',v_grade,case when v_grant is null then 0 else v_set.secret_drop_quantity end,v_roll,v_rate,true) on conflict do nothing;
     if v_grant is not null then v_summary:=v_summary||jsonb_build_array(v_grant||jsonb_build_object('grade_code',v_grade,'source','secret_monster'));end if;
   elsif v_event->>'event_type'='pvp' then
     v_outcome:=lower(coalesce(v_event->>'outcome',''));if v_outcome in ('loss','defeat','lost','pvp_defeated') then begin v_opp:=coalesce(nullif(v_event#>>'{opponent,character_id}','')::uuid,nullif(v_event->>'opponent_character_id','')::uuid);exception when others then v_opp:=null;end;if v_opp is not null then v_transfer:=public.combat_technique_steal_secret_pending_v220(v_opp,v_char,p_context_ref);v_summary:=v_summary||jsonb_build_array(jsonb_build_object('source','pvp_loss','transfer',v_transfer));end if;end if;
   end if;
 end loop;return v_summary;
end $$;

-- 包装进入/结算/领取，保持原RPC名称，旧客户端也不会绕过快照。
do $wrap_secret$
begin
 if to_regprocedure('public.enter_secret_realm_bsecretrealm01_pre_v220(uuid)') is null then execute 'alter function public.enter_secret_realm_bsecretrealm01(uuid) rename to enter_secret_realm_bsecretrealm01_pre_v220';end if;
 if to_regprocedure('public.settle_secret_realm_progress_bsecretrealm01_pre_v220(uuid)') is null then execute 'alter function public.settle_secret_realm_progress_bsecretrealm01(uuid) rename to settle_secret_realm_progress_bsecretrealm01_pre_v220';end if;
 if to_regprocedure('public.claim_secret_realm_rewards_bsecretrealm01_pre_v220(uuid)') is null then execute 'alter function public.claim_secret_realm_rewards_bsecretrealm01(uuid) rename to claim_secret_realm_rewards_bsecretrealm01_pre_v220';end if;
end $wrap_secret$;

create or replace function public.enter_secret_realm_bsecretrealm01(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_result jsonb;v_char uuid:=public.combat_technique_active_character_v220();v_ref text;begin v_result:=public.enter_secret_realm_bsecretrealm01_pre_v220(p_request_id);v_ref:=coalesce(v_result#>>'{run,run_id}',v_result#>>'{run,id}',v_result->>'run_id',p_request_id::text);perform public.combat_technique_capture_context_v220(v_char,'secret',v_ref);return v_result||jsonb_build_object('combat_technique_snapshot_v220',public.combat_technique_context_snapshot_v220(v_char,'attack'));end $$;
create or replace function public.settle_secret_realm_progress_bsecretrealm01(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_result jsonb;v_char uuid:=public.combat_technique_active_character_v220();v_ref text;v_extra jsonb;begin perform set_config('jiuxiao_v220.combat_context','secret',true);v_ref:=public.combat_technique_secret_context_ref_v220(v_char);v_result:=public.settle_secret_realm_progress_bsecretrealm01_pre_v220(p_request_id);v_extra:=public.combat_technique_process_secret_result_v220(v_result,coalesce(v_ref,'secret-'||v_char::text));return v_result||jsonb_build_object('combat_technique_shards_v220',v_extra);end $$;
create or replace function public.claim_secret_realm_rewards_bsecretrealm01(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$declare v_result jsonb;v_char uuid:=public.combat_technique_active_character_v220();v_ref text;v_row record;v_claim jsonb:='[]'::jsonb;begin v_ref:=public.combat_technique_secret_context_ref_v220(v_char);v_result:=public.claim_secret_realm_rewards_bsecretrealm01_pre_v220(p_request_id);if v_ref is not null then for v_row in select technique_code,quantity from public.combat_technique_secret_pending_v220 where context_ref=v_ref and character_id=v_char and quantity>0 for update loop insert into public.combat_technique_shards_v220(character_id,technique_code,quantity) values(v_char,v_row.technique_code,v_row.quantity) on conflict(character_id,technique_code) do update set quantity=public.combat_technique_shards_v220.quantity+excluded.quantity,updated_at=clock_timestamp();v_claim:=v_claim||jsonb_build_array(jsonb_build_object('code',v_row.technique_code,'quantity',v_row.quantity));end loop;delete from public.combat_technique_secret_pending_v220 where context_ref=v_ref and character_id=v_char;update public.combat_technique_context_snapshots_v220 set active=false,closed_at=clock_timestamp() where context_kind='secret' and context_ref=v_ref and character_id=v_char and active;end if;return v_result||jsonb_build_object('combat_technique_shards_claimed_v220',v_claim);end $$;


-- 世界BOSS保持原独立模拟器，但功法按与B-COMBAT一致的effect_code语义进入真实公式。
-- 两个helper只处理已锁定的功法快照，便于门禁用合成输入直接验证，不读取实时装备。
create or replace function public.combat_technique_worldboss_attack_effect_v220(
  p_tech jsonb,p_round integer,p_boss_hp_ratio numeric,p_boss_evasion numeric,p_boss_defense_proxy numeric,p_element_multiplier numeric
) returns jsonb language plpgsql immutable set search_path='' as $$
declare v_code text:=coalesce(p_tech->>'effect_code','');v_p jsonb:=coalesce(p_tech->'params','{}'::jsonb);v_hit numeric:=0;v_bonus numeric:=0;v_pen numeric:=0;v_elem numeric:=coalesce(p_element_multiplier,1);v_value numeric:=0;v_stacks int:=0;v_effects jsonb:='[]'::jsonb;
begin
 if p_tech is null or jsonb_typeof(p_tech)='null' then return jsonb_build_object('hit_bonus',0,'damage_bonus',0,'defense_penetration',0,'element_multiplier',v_elem,'effects','[]'::jsonb);end if;
 if v_code='ATK_HIT' then v_hit:=coalesce((v_p->>'hit_bonus')::numeric,0);v_bonus:=v_bonus+coalesce((v_p->>'damage_bonus')::numeric,0);
 elsif v_code='ATK_ANTI_EVASION' then v_hit:=coalesce((v_p->>'hit_bonus')::numeric,0);if coalesce(p_boss_evasion,0)>=coalesce((v_p->>'high_evasion_threshold')::numeric,.10) then v_bonus:=v_bonus+coalesce((v_p->>'high_evasion_damage_bonus')::numeric,0);end if;
 elsif v_code='ATK_DEFENSE_PEN' then v_pen:=least(.80,greatest(0,coalesce((v_p->>'defense_penetration')::numeric,0)));
 elsif v_code='ATK_FINAL_DAMAGE' then v_bonus:=v_bonus+coalesce((v_p->>'damage_bonus')::numeric,0);
 elsif v_code='ATK_OPENING_BURST' then v_bonus:=v_bonus+case when coalesce(p_round,1)<=coalesce((v_p->>'opening_rounds')::int,2) then coalesce((v_p->>'opening_damage_bonus')::numeric,0) else coalesce((v_p->>'later_damage_bonus')::numeric,0) end;
 elsif v_code='ATK_ANTI_DEFENSE' then v_bonus:=v_bonus+case when coalesce(p_boss_defense_proxy,0)>=coalesce((v_p->>'high_defense_threshold')::numeric,.35) then coalesce((v_p->>'high_defense_damage_bonus')::numeric,0) else coalesce((v_p->>'normal_damage_bonus')::numeric,0) end;
 elsif v_code='ATK_ELEMENT_ADVANTAGE' then v_value:=least(.90,greatest(0,coalesce((v_p->>'element_swing_amplify')::numeric,0)));if v_elem>1 then v_elem:=1+(v_elem-1)*(1+v_value);elsif v_elem<1 then v_elem:=1-(1-v_elem)*(1-v_value);end if;
 elsif v_code='ATK_EXECUTE' then if coalesce(p_boss_hp_ratio,1)<=coalesce((v_p->>'hp_threshold')::numeric,.30) then v_bonus:=v_bonus+coalesce((v_p->>'damage_bonus')::numeric,0);end if;
 elsif v_code='ATK_ROUND_STACK' then v_stacks:=least(coalesce((v_p->>'max_stacks')::int,5),greatest(0,coalesce(p_round,1)-1));v_bonus:=v_bonus+v_stacks*coalesce((v_p->>'per_stack_damage_bonus')::numeric,0);
 end if;
 if v_code<>'' then v_effects:=jsonb_build_array(jsonb_build_object('side','attack','name',coalesce(p_tech->>'name',''),'effect_code',v_code,'damage_bonus',v_bonus,'hit_bonus',v_hit,'defense_penetration',v_pen,'stacks',v_stacks));end if;
 return jsonb_build_object('hit_bonus',v_hit,'damage_bonus',v_bonus,'defense_penetration',v_pen,'element_multiplier',v_elem,'stacks',v_stacks,'effects',v_effects);
end $$;

create or replace function public.combat_technique_worldboss_defense_effect_v220(
  p_tech jsonb,p_round integer,p_hp_ratio numeric,p_element_multiplier numeric
) returns jsonb language plpgsql immutable set search_path='' as $$
declare v_code text:=coalesce(p_tech->>'effect_code','');v_p jsonb:=coalesce(p_tech->'params','{}'::jsonb);v_ev numeric:=0;v_red numeric:=0;v_er numeric:=0;v_elem numeric:=coalesce(p_element_multiplier,1);v_heal numeric:=0;v_threshold numeric:=.30;v_lethal boolean:=false;v_lethal_hp numeric:=1;v_extra numeric:=0;v_suppress numeric:=0;v_effects jsonb:='[]'::jsonb;
begin
 if p_tech is null or jsonb_typeof(p_tech)='null' then return jsonb_build_object('evasion_bonus',0,'damage_reduction',0,'element_resistance',0,'element_multiplier',v_elem,'heal_ratio',0,'heal_threshold',v_threshold,'lethal_guard',false,'lethal_guard_hp',1,'effects','[]'::jsonb);end if;
 if v_code='DEF_EVASION' then v_ev:=coalesce((v_p->>'evasion_bonus')::numeric,0);
 elsif v_code='DEF_REDUCTION' then v_red:=coalesce((v_p->>'reduction')::numeric,0);
 elsif v_code='DEF_ELEMENT_RESIST' then v_er:=coalesce((v_p->>'element_resistance')::numeric,0);
 elsif v_code='DEF_STEADFAST' then v_red:=coalesce((v_p->>'reduction')::numeric,0);if coalesce(p_hp_ratio,1)>=coalesce((v_p->>'high_hp_threshold')::numeric,.50) then v_extra:=coalesce((v_p->>'high_hp_extra_reduction')::numeric,0);v_red:=1-(1-v_red)*(1-v_extra);end if;
 elsif v_code='DEF_LOW_HP_RECOVERY' then v_threshold:=coalesce((v_p->>'hp_threshold')::numeric,.30);v_heal:=coalesce((v_p->>'heal_ratio')::numeric,0);if coalesce(p_hp_ratio,1)<=v_threshold then v_red:=coalesce((v_p->>'low_hp_reduction')::numeric,0);end if;
 elsif v_code='DEF_OPENING_REDUCTION' then v_red:=case when coalesce(p_round,1)<=coalesce((v_p->>'opening_rounds')::int,2) then coalesce((v_p->>'opening_reduction')::numeric,0) else coalesce((v_p->>'later_reduction')::numeric,0) end;
 elsif v_code='DEF_ATTACK_TECH_SUPPRESS' then v_red:=coalesce((v_p->>'reduction')::numeric,0); -- BOSS无攻伐功法，因此只生效其自身护体部分。
 elsif v_code='DEF_ALL_SUPPRESS' then v_red:=coalesce((v_p->>'reduction')::numeric,0);if v_elem>1 then v_suppress:=least(.90,greatest(0,coalesce((v_p->>'element_advantage_suppression')::numeric,0)));v_elem:=1+(v_elem-1)*(1-v_suppress);end if;
 elsif v_code='DEF_LETHAL_GUARD' then v_red:=coalesce((v_p->>'reduction')::numeric,0);v_lethal:=coalesce((p_tech->>'is_mastered')::boolean,false);v_lethal_hp:=greatest(1,coalesce((v_p->>'lethal_guard_hp')::numeric,1));
 end if;
 v_red:=least(.80,greatest(0,v_red));
 if v_code<>'' then v_effects:=jsonb_build_array(jsonb_build_object('side','defense','name',coalesce(p_tech->>'name',''),'effect_code',v_code,'damage_reduction',v_red,'evasion_bonus',v_ev,'element_resistance',v_er));end if;
 return jsonb_build_object('evasion_bonus',v_ev,'damage_reduction',v_red,'element_resistance',v_er,'element_multiplier',v_elem,'heal_ratio',v_heal,'heal_threshold',v_threshold,'lethal_guard',v_lethal,'lethal_guard_hp',v_lethal_hp,'effects',v_effects);
end $$;

-- 世界BOSS功法残卷：沿用生产world_boss_settings的时区/每日珍稀胜场上限，逐队员独立结算。
create or replace function public.combat_technique_process_boss_member_v220(p_run_id uuid,p_character_id uuid,p_difficulty text,p_victory boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_set public.combat_technique_settings_v220%rowtype;v_tz text:='UTC';v_limit int:=3;v_enabled boolean:=true;v_today date;v_win_no int:=0;v_roll numeric:=0;v_grade text;v_rate numeric:=0;v_grant jsonb;v_ref text:=p_run_id::text;
begin
 select * into v_set from public.combat_technique_settings_v220 where singleton_id=1;if not coalesce(v_set.enabled,true) or not coalesce(p_victory,false) then return null;end if;
 begin select coalesce(timezone_name,'UTC'),coalesce(rare_reward_win_limit,3),coalesce(rare_reward_enabled,true) into v_tz,v_limit,v_enabled from public.world_boss_settings_bwboss01 where singleton_id=1;exception when undefined_column then v_tz:='UTC';v_limit:=3;v_enabled:=true;end;
 if not v_enabled then return jsonb_build_object('eligible',false,'reason','world_boss_rare_disabled');end if;
 perform pg_advisory_xact_lock(hashtextextended('v220-boss-tech:'||p_character_id::text||':'||((clock_timestamp() at time zone v_tz)::date)::text,22041));
 v_today:=(clock_timestamp() at time zone v_tz)::date;
 select count(*) into v_win_no from public.world_boss_contributions_bwboss01 c join public.world_boss_runs_bwboss01 r on r.id=c.run_id where c.character_id=p_character_id and r.status='victory' and r.ended_at is not null and (r.ended_at at time zone v_tz)::date=v_today;
 if exists(select 1 from public.combat_technique_acquisition_ledger_v220 where character_id=p_character_id and source_kind='worldboss' and source_ref=v_ref) then select jsonb_build_object('eligible',roll is not null,'already_settled',true,'daily_win_number',v_win_no,'technique_code',technique_code,'quantity',quantity,'grade_code',grade_code) into v_grant from public.combat_technique_acquisition_ledger_v220 where character_id=p_character_id and source_kind='worldboss' and source_ref=v_ref;return v_grant;end if;
 if v_win_no>greatest(0,v_limit) then insert into public.combat_technique_acquisition_ledger_v220(character_id,source_kind,source_ref,quantity,roll,rate,at_risk) values(p_character_id,'worldboss',v_ref,0,null,0,false);return jsonb_build_object('eligible',false,'daily_win_number',v_win_no,'limit',v_limit);end if;
 v_roll:=random();if lower(coalesce(p_difficulty,'normal'))='hard' then if v_roll<v_set.boss_hard_immortal_rate then v_grade:='immortal';v_rate:=v_set.boss_hard_immortal_rate;elsif v_roll<v_set.boss_hard_immortal_rate+v_set.boss_hard_heaven_rate then v_grade:='heaven';v_rate:=v_set.boss_hard_heaven_rate;end if;else if v_roll<v_set.boss_normal_heaven_rate then v_grade:='heaven';v_rate:=v_set.boss_normal_heaven_rate;end if;end if;
 if v_grade is not null then v_grant:=public.combat_technique_grant_shard_v220(p_character_id,v_grade,v_set.boss_drop_quantity,null);end if;
 insert into public.combat_technique_acquisition_ledger_v220(character_id,source_kind,source_ref,technique_code,grade_code,quantity,roll,rate,at_risk) values(p_character_id,'worldboss',v_ref,v_grant->>'technique_code',v_grade,case when v_grant is null then 0 else v_set.boss_drop_quantity end,v_roll,coalesce(v_rate,0),false);
 return jsonb_build_object('eligible',true,'daily_win_number',v_win_no,'limit',v_limit,'roll',v_roll,'rate',coalesce(v_rate,0),'grade_code',v_grade,'technique_code',v_grant->>'technique_code','technique_name',v_grant->>'technique_name','quantity',case when v_grant is null then 0 else v_set.boss_drop_quantity end);
end $$;

-- ---------- 世界BOSS：准备时把功法直接锁入生产battle_snapshot；独立模拟器真实应用effect_code ----------
do $wrap_boss$
begin
 if to_regprocedure('public.set_world_boss_member_ready_bwboss01_pre_v220(boolean,text,uuid)') is null then execute 'alter function public.set_world_boss_member_ready_bwboss01(boolean,text,uuid) rename to set_world_boss_member_ready_bwboss01_pre_v220';end if;
 if to_regprocedure('public.bwboss01_simulate_run_pre_v220(uuid)') is null then execute 'alter function public.bwboss01_simulate_run(uuid) rename to bwboss01_simulate_run_pre_v220';end if;
 if to_regprocedure('public.start_world_boss_run_bwboss01_pre_v220(uuid)') is null then execute 'alter function public.start_world_boss_run_bwboss01(uuid) rename to start_world_boss_run_bwboss01_pre_v220';end if;
end $wrap_boss$;

create or replace function public.set_world_boss_member_ready_bwboss01(p_ready boolean,p_strategy text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb;v_char uuid:=public.combat_technique_active_character_v220();v_party uuid;v_ref text;v_ct jsonb;
begin
 v_result:=public.set_world_boss_member_ready_bwboss01_pre_v220(p_ready,p_strategy,p_request_id);v_party:=public.bwboss01_active_party(v_char);
 if p_ready then
   v_ref:=coalesce(v_party::text,p_request_id::text);v_ct:=public.combat_technique_capture_context_v220(v_char,'worldboss',v_ref);
   update public.world_boss_party_members_bwboss01 set battle_snapshot=coalesce(battle_snapshot,'{}'::jsonb)||jsonb_build_object('combat_attack_technique_v220',v_ct->'attack','combat_defense_technique_v220',v_ct->'defense','combat_technique_config_version_v220',v_ct->'config_version','combat_technique_locked_at_v220',clock_timestamp()),updated_at=clock_timestamp() where party_id=v_party and character_id=v_char;
 else update public.combat_technique_context_snapshots_v220 set active=false,closed_at=clock_timestamp() where context_kind='worldboss' and character_id=v_char and active;end if;
 return coalesce(v_result,'{}'::jsonb)||jsonb_build_object('combat_technique_snapshot_v220',case when p_ready then v_ct else null end);
end $$;

CREATE OR REPLACE FUNCTION public.bwboss01_simulate_run(p_run_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- SQL254_R5_WORLD_BOSS_EFFECT_ADAPTER: locked battle_snapshot + shared effect_code semantics.
declare
  v_run public.world_boss_runs_bwboss01%rowtype; v_party public.world_boss_parties_bwboss01%rowtype; v_def public.world_boss_definitions_bwboss01%rowtype;
  v_cfg jsonb; v_party_size integer; v_target_rounds integer; v_round_cap integer; v_hp_scale numeric;v_attack_scale numeric;v_diff_hp numeric;v_diff_attack numeric;v_diff_def numeric;v_diff_agility numeric;
  v_global_difficulty numeric:=1;v_global_reward numeric:=1;
  v_avg_base_attack numeric;v_avg_base_defense numeric;v_avg_base_vitality numeric;v_avg_base_agility numeric;v_boss_max_hp numeric;v_boss_hp numeric;v_boss_attack numeric;v_boss_defense numeric;v_boss_agility numeric;
  v_states jsonb:='{}'::jsonb;v_actions jsonb:='[]'::jsonb;v_contrib jsonb:='{}'::jsonb;v_member record;v_id text;v_snapshot jsonb;v_round integer;v_phase text:='armor';v_prev_phase text:='';v_damage numeric;v_ratio numeric;v_elem numeric;v_strategy numeric;v_phase_mult numeric;v_hp numeric;v_max_hp numeric;v_alive integer;v_target_id text;v_target_name text;v_target_state jsonb;v_target_def numeric;v_target_elem text;v_target_strategy text;v_boss_elem text:='earth';v_boss_damage numeric;v_pct numeric;v_victory boolean:=false;v_mechanic numeric:=0;v_rescue_target text;v_rescue_name text;v_team_break numeric;v_world_contribution numeric;v_token integer;v_result jsonb;v_names text:='';v_party_label text:='';v_member_contribution numeric;v_qty bigint;v_socket public.equipment_socket_settings_v210%rowtype;v_hit_chance numeric;v_hit_roll numeric;v_attack_element text;v_element_damage numeric;v_element_resist numeric;v_element_factor numeric;v_boss_hit_bonus numeric:=0;v_boss_evasion_bonus numeric:=0;v_boss_element_damage numeric:=0;v_boss_element_resist numeric:=0;v_defense_factor numeric:=1;v_agility_pressure numeric:=1;v_at jsonb;v_dt jsonb;v_fx jsonb:='{}'::jsonb;v_attack_tech_bonus numeric:=0;v_def_tech_reduction numeric:=0;v_effective_boss_defense numeric;v_boss_defense_proxy numeric:=0;v_tech_effects jsonb:='[]'::jsonb;v_heal numeric:=0;v_huiyuan_used boolean:=false;v_bumie_used boolean:=false;v_target_evasion numeric:=0;v_tech_reward jsonb;
begin
  select * into v_run from public.world_boss_runs_bwboss01 where id=p_run_id for update;
  if v_run.id is null then raise exception 'BWBOSS01_RUN_NOT_FOUND'; end if;
  select * into v_party from public.world_boss_parties_bwboss01 where id=v_run.party_id;
  select * into v_def from public.world_boss_definitions_bwboss01 where code=v_run.boss_code;
  v_cfg:=case when v_run.difficulty='hard' then v_def.hard_config else v_def.normal_config end;
  select * into v_socket from public.equipment_socket_settings_v210 where singleton_id=1;
  v_boss_hit_bonus:=coalesce((v_cfg->>'hit_bonus')::numeric,0);v_boss_evasion_bonus:=coalesce((v_cfg->>'evasion_bonus')::numeric,0);
  v_boss_element_damage:=coalesce((v_cfg->>'element_damage_bonus')::numeric,0);v_boss_element_resist:=coalesce((v_cfg->>'element_resistance')::numeric,0);
  v_party_size:=v_run.party_size;v_target_rounds:=coalesce((v_cfg->>'target_rounds')::integer,24);v_round_cap:=v_target_rounds;
  select coalesce(s.difficulty_multiplier,1),coalesce(s.reward_multiplier,1) into v_global_difficulty,v_global_reward from public.world_boss_settings_bwboss01 s where singleton_id=1;
  select coalesce(ps.hp_multiplier,1),coalesce(ps.attack_multiplier,1) into v_hp_scale,v_attack_scale from public.world_boss_party_scale_v210 ps where ps.party_size=v_party_size;
  v_hp_scale:=coalesce(v_hp_scale,1);v_attack_scale:=coalesce(v_attack_scale,1);
  v_diff_hp:=coalesce((v_cfg->>'hp_multiplier')::numeric,1)*v_global_difficulty;v_diff_attack:=coalesce((v_cfg->>'attack_multiplier')::numeric,1)*v_global_difficulty;
  v_diff_def:=coalesce((v_cfg->>'defense_multiplier')::numeric,1)*v_global_difficulty;v_diff_agility:=coalesce((v_cfg->>'agility_multiplier')::numeric,1)*v_global_difficulty;

  select avg(coalesce(nullif(m.battle_snapshot->>'realm_base_attack','')::numeric,nullif(m.battle_snapshot->>'base_attack','')::numeric,nullif(m.battle_snapshot->>'attack','')::numeric)),
         avg(coalesce(nullif(m.battle_snapshot->>'realm_base_defense','')::numeric,nullif(m.battle_snapshot->>'base_defense','')::numeric,nullif(m.battle_snapshot->>'defense','')::numeric)),
         avg(coalesce(nullif(m.battle_snapshot->>'realm_base_vitality','')::numeric,nullif(m.battle_snapshot->>'base_vitality','')::numeric,nullif(m.battle_snapshot->>'vitality','')::numeric)),
         avg(coalesce(nullif(m.battle_snapshot->>'realm_base_agility','')::numeric,nullif(m.battle_snapshot->>'base_agility','')::numeric,nullif(m.battle_snapshot->>'agility','')::numeric))
  into v_avg_base_attack,v_avg_base_defense,v_avg_base_vitality,v_avg_base_agility
  from public.world_boss_party_members_bwboss01 m where m.party_id=v_party.id;
  v_avg_base_attack:=greatest(1,coalesce(v_avg_base_attack,1));v_avg_base_defense:=greatest(1,coalesce(v_avg_base_defense,1));v_avg_base_vitality:=greatest(1,coalesce(v_avg_base_vitality,1));v_avg_base_agility:=greatest(1,coalesce(v_avg_base_agility,1));
  -- BOSS生机只看境界基础道攻与人数，不跟随装备战力实时追平。
  v_boss_max_hp:=greatest(100,round(v_avg_base_attack*v_party_size*v_target_rounds*0.72*v_hp_scale*v_diff_hp));
  v_boss_hp:=v_boss_max_hp;v_boss_attack:=v_avg_base_attack*v_attack_scale*v_diff_attack;v_boss_defense:=v_avg_base_defense*v_diff_def;v_boss_agility:=v_avg_base_agility*v_diff_agility;
  v_agility_pressure:=greatest(0.25,least(4.0,v_boss_agility/greatest(1,v_avg_base_agility)));
  v_boss_hit_bonus:=v_boss_hit_bonus+greatest(-0.15,least(0.25,(v_agility_pressure-1)*0.04));
  v_boss_evasion_bonus:=v_boss_evasion_bonus+greatest(-0.10,least(0.20,(v_agility_pressure-1)*0.03));

  for v_member in select m.*,pc.name from public.world_boss_party_members_bwboss01 m join public.player_characters pc on pc.id=m.character_id where m.party_id=v_party.id order by m.position loop
    v_id:=v_member.character_id::text;v_snapshot:=v_member.battle_snapshot;
    v_max_hp:=greatest(1,coalesce(nullif(v_snapshot->>'vitality','')::numeric,1));
    v_states:=jsonb_set(v_states,array[v_id],jsonb_build_object('hp',v_max_hp,'max_hp',v_max_hp,'downed',false,'rescued',false,'eliminated',false,'name',v_member.name,'element',coalesce(nullif(v_snapshot->>'innate_element',''),v_snapshot->>'element',''),'current_attack_element',coalesce(nullif(v_snapshot->>'current_attack_element',''),v_snapshot->>'element',''),'hit_bonus',coalesce(nullif(v_snapshot->>'hit_bonus','')::numeric,0),'evasion_bonus',coalesce(nullif(v_snapshot->>'evasion_bonus','')::numeric,0),'element_damage',coalesce(v_snapshot->'element_damage','{}'::jsonb),'element_resistance',coalesce(v_snapshot->'element_resistance','{}'::jsonb),'strategy',v_member.strategy,'position',v_member.position,'attack',coalesce(nullif(v_snapshot->>'attack','')::numeric,1),'base_attack',coalesce(nullif(v_snapshot->>'realm_base_attack','')::numeric,nullif(v_snapshot->>'base_attack','')::numeric,nullif(v_snapshot->>'attack','')::numeric,1),'defense',coalesce(nullif(v_snapshot->>'defense','')::numeric,1),'agility',coalesce(nullif(v_snapshot->>'agility','')::numeric,1),'attack_technique',coalesce(v_snapshot->'combat_attack_technique_v220','null'::jsonb),'defense_technique',coalesce(v_snapshot->'combat_defense_technique_v220','null'::jsonb),'huiyuan_used',false,'bumie_used',false),true);
    v_contrib:=jsonb_set(v_contrib,array[v_id],jsonb_build_object('damage',0,'damage_taken',0,'mechanic',0,'rescues',0),true);
    v_names:=v_names||case when v_names='' then '' else '、' end||v_member.name;
  end loop;
  v_party_label:=v_names;

  update public.world_boss_runs_bwboss01 set boss_snapshot=jsonb_build_object('name',v_def.name,'element',v_boss_elem,'max_hp',v_boss_max_hp,'attack',v_boss_attack,'defense',v_boss_defense,'agility',v_boss_agility,'hp_scale',v_hp_scale,'attack_scale',v_attack_scale,'difficulty',v_run.difficulty,'hit_bonus',v_boss_hit_bonus,'evasion_bonus',v_boss_evasion_bonus,'element_damage_bonus',v_boss_element_damage,'element_resistance',v_boss_element_resist,'global_difficulty_multiplier',v_global_difficulty,'global_reward_multiplier',v_global_reward) where id=v_run.id;

  for v_round in 1..v_round_cap loop
    exit when v_boss_hp<=0;
    select count(*) into v_alive from jsonb_each(v_states) e where not coalesce((e.value->>'eliminated')::boolean,false) and coalesce((e.value->>'hp')::numeric,0)>0;
    exit when v_alive=0;

    if v_boss_hp/v_boss_max_hp>0.70 then v_phase:='armor'; elsif v_boss_hp/v_boss_max_hp>0.35 then v_phase:='core'; else v_phase:='rage'; end if;
    if v_phase<>v_prev_phase then
      v_actions:=v_actions||jsonb_build_array(jsonb_build_object('type','phase','round',v_round,'title',case v_phase when 'armor' then '玄甲护体' when 'core' then '吞灵之域' else '九幽暴走' end,
        'text',case v_phase when 'armor' then '玄甲压制普通攻势，木行与机制优先策略更擅长破甲。' when 'core' then '吞灵核心显化，队伍会按五行与策略自动处理机制目标。' else '九幽吞天兽进入暴走，攻击压力明显提高。' end,'boss_hp_percent',round(v_boss_hp/v_boss_max_hp*100,2)));
      v_prev_phase:=v_phase;
    end if;

    -- 玩家按身法从高到低自动行动。倒地队友存在时，非强攻策略优先救援一次。
    for v_member in
      select m.*,pc.name from public.world_boss_party_members_bwboss01 m join public.player_characters pc on pc.id=m.character_id
      where m.party_id=v_party.id order by coalesce(nullif(m.battle_snapshot->>'agility','')::numeric,0) desc,m.position
    loop
      v_id:=v_member.character_id::text;v_target_state:=v_states->v_id;
      if coalesce((v_target_state->>'eliminated')::boolean,false) or coalesce((v_target_state->>'downed')::boolean,false) or coalesce((v_target_state->>'hp')::numeric,0)<=0 then continue; end if;

      v_rescue_target:=null;
      if v_member.strategy<>'assault' then
        select e.key into v_rescue_target from jsonb_each(v_states) e
        where e.key<>v_id and coalesce((e.value->>'downed')::boolean,false) and not coalesce((e.value->>'eliminated')::boolean,false)
        order by coalesce((e.value->>'position')::integer,3) limit 1;
      end if;
      if v_rescue_target is not null then
        v_rescue_name:=v_states->v_rescue_target->>'name';v_max_hp:=coalesce((v_states->v_rescue_target->>'max_hp')::numeric,1);
        v_states:=jsonb_set(v_states,array[v_rescue_target,'hp'],to_jsonb(round(v_max_hp*0.25)),true);
        v_states:=jsonb_set(v_states,array[v_rescue_target,'downed'],'false'::jsonb,true);
        v_states:=jsonb_set(v_states,array[v_rescue_target,'rescued'],'true'::jsonb,true);
        v_contrib:=jsonb_set(v_contrib,array[v_id,'rescues'],to_jsonb(coalesce((v_contrib->v_id->>'rescues')::integer,0)+1),true);
        v_actions:=v_actions||jsonb_build_array(jsonb_build_object('type','rescue','round',v_round,'actor_id',v_id,'actor_name',v_member.name,'target_id',v_rescue_target,'target_name',v_rescue_name,'hp_after',round(v_max_hp*0.25),'boss_hp_percent',round(v_boss_hp/v_boss_max_hp*100,2)));
        continue;
      end if;

      v_snapshot:=v_member.battle_snapshot;
      v_at:=v_snapshot->'combat_attack_technique_v220';
      v_attack_element:=coalesce(nullif(v_snapshot->>'current_attack_element',''),nullif(v_snapshot->>'element',''),'');
      v_ratio:=greatest(0.50,least(3.00,coalesce(nullif(v_snapshot->>'attack','')::numeric,1)/greatest(1,coalesce(nullif(v_snapshot->>'realm_base_attack','')::numeric,nullif(v_snapshot->>'base_attack','')::numeric,nullif(v_snapshot->>'attack','')::numeric,1))));
      v_elem:=public.bwboss01_element_multiplier(v_attack_element,v_boss_elem);
      v_boss_defense_proxy:=least(.70,greatest(0,v_boss_defense)/greatest(1,greatest(0,v_boss_defense)+coalesce(nullif(v_snapshot->>'realm_base_attack','')::numeric,nullif(v_snapshot->>'base_attack','')::numeric,nullif(v_snapshot->>'attack','')::numeric,1)*2));
      v_fx:=public.combat_technique_worldboss_attack_effect_v220(v_at,v_round,v_boss_hp/greatest(1,v_boss_max_hp),v_boss_evasion_bonus,v_boss_defense_proxy,v_elem);
      v_attack_tech_bonus:=coalesce((v_fx->>'damage_bonus')::numeric,0);v_elem:=coalesce((v_fx->>'element_multiplier')::numeric,v_elem);v_tech_effects:=coalesce(v_fx->'effects','[]'::jsonb);
      v_hit_chance:=greatest(v_socket.hit_floor,least(v_socket.hit_ceiling,v_socket.base_hit_rate+coalesce(nullif(v_snapshot->>'hit_bonus','')::numeric,0)+coalesce((v_fx->>'hit_bonus')::numeric,0)-v_boss_evasion_bonus));
      v_hit_roll:=random();
      if v_hit_roll>v_hit_chance then
        v_actions:=v_actions||jsonb_build_array(jsonb_build_object('type','miss','round',v_round,'actor_id',v_id,'actor_name',v_member.name,'target_name',v_def.name,'hit_rate',v_hit_chance,'attack_element',v_attack_element,'attack_technique_name',coalesce(v_at->>'name',''),'attack_technique',v_at,'technique_effects',v_tech_effects,'boss_hp_percent',round(v_boss_hp/v_boss_max_hp*100,2)));
        continue;
      end if;
      v_element_damage:=coalesce(nullif(v_snapshot->'element_damage'->>v_attack_element,'')::numeric,0);
      v_element_resist:=v_boss_element_resist;
      v_element_factor:=greatest(v_socket.element_factor_min,least(v_socket.element_factor_max,1+v_element_damage-v_element_resist));
      v_effective_boss_defense:=greatest(0,v_boss_defense*(1-coalesce((v_fx->>'defense_penetration')::numeric,0)));
      v_defense_factor:=greatest(0.45,least(1.35,(coalesce(nullif(v_snapshot->>'attack','')::numeric,1)/(coalesce(nullif(v_snapshot->>'attack','')::numeric,1)+greatest(1,v_effective_boss_defense)))*2));
      v_strategy:=case v_member.strategy when 'assault' then 1.10 when 'guard' then 0.78 when 'mechanic' then 0.94 else 1.0 end;
      v_phase_mult:=case when v_phase='armor' then (case when v_member.strategy='mechanic' then 0.82 else 0.65 end) else 1.0 end;
      v_damage:=greatest(1,round((v_boss_max_hp/(greatest(1,v_party_size)*v_target_rounds))*v_ratio*v_defense_factor*v_elem*v_element_factor*v_strategy*v_phase_mult*(1+v_attack_tech_bonus)*(0.92+random()*0.16)));
      v_boss_hp:=greatest(0,v_boss_hp-v_damage);
      v_contrib:=jsonb_set(v_contrib,array[v_id,'damage'],to_jsonb(coalesce((v_contrib->v_id->>'damage')::numeric,0)+v_damage),true);
      if v_member.strategy='mechanic' or v_elem>1 then
        v_mechanic:=round(v_damage*0.15);v_contrib:=jsonb_set(v_contrib,array[v_id,'mechanic'],to_jsonb(coalesce((v_contrib->v_id->>'mechanic')::numeric,0)+v_mechanic),true);
      end if;
      v_actions:=v_actions||jsonb_build_array(jsonb_build_object('type','attack','round',v_round,'actor_id',v_id,'actor_name',v_member.name,'target_name',v_def.name,'damage',v_damage,'hit_rate',v_hit_chance,'attack_element',v_attack_element,'element_multiplier',v_elem,'element_factor',v_element_factor,'strategy',v_member.strategy,'attack_technique_name',coalesce(v_at->>'name',''),'attack_technique',v_at,'attack_technique_factor',1+v_attack_tech_bonus,'technique_effects',v_tech_effects,'boss_hp',v_boss_hp,'boss_hp_percent',round(v_boss_hp/v_boss_max_hp*100,2)));
      exit when v_boss_hp<=0;
    end loop;
    exit when v_boss_hp<=0;

    -- 每5回合一次团队破势检查；无需主动技能。
    if v_round%5=0 then
      select coalesce(sum(greatest(0.5,least(3.0,coalesce(nullif(m.battle_snapshot->>'attack','')::numeric,1)/greatest(1,coalesce(nullif(m.battle_snapshot->>'realm_base_attack','')::numeric,nullif(m.battle_snapshot->>'base_attack','')::numeric,nullif(m.battle_snapshot->>'attack','')::numeric,1))))),0)
      into v_team_break from public.world_boss_party_members_bwboss01 m where m.party_id=v_party.id;
      if v_team_break>=greatest(0.8,v_party_size*0.85) then
        v_damage:=round(v_boss_max_hp*0.03);v_boss_hp:=greatest(0,v_boss_hp-v_damage);
        v_actions:=v_actions||jsonb_build_array(jsonb_build_object('type','phase','round',v_round,'title','破势成功','text','三人攻势在蓄力节点汇合，九幽吞天兽的地脉蓄力被截断。','damage',v_damage,'boss_hp_percent',round(v_boss_hp/v_boss_max_hp*100,2)));
        for v_member in select character_id::text id from public.world_boss_party_members_bwboss01 where party_id=v_party.id loop
          v_contrib:=jsonb_set(v_contrib,array[v_member.id,'mechanic'],to_jsonb(coalesce((v_contrib->v_member.id->>'mechanic')::numeric,0)+20),true);
        end loop;
      else
        v_actions:=v_actions||jsonb_build_array(jsonb_build_object('type','phase','round',v_round,'title','破势失败','text','队伍未能及时压住地脉蓄力，九幽冲击席卷全场。','boss_hp_percent',round(v_boss_hp/v_boss_max_hp*100,2)));
        -- 失败时追加的范围伤害在随后BOSS攻击中通过倍率体现。
      end if;
    end if;

    -- BOSS目标：守御策略优先，其次前位、中位、后位。首版不使用客户端随机目标。
    v_target_id:=null;
    for v_member in
      select m.character_id::text id,m.strategy,m.position,pc.name from public.world_boss_party_members_bwboss01 m join public.player_characters pc on pc.id=m.character_id
      where m.party_id=v_party.id order by (m.strategy='guard') desc,m.position
    loop
      if not coalesce((v_states->v_member.id->>'eliminated')::boolean,false) and not coalesce((v_states->v_member.id->>'downed')::boolean,false) and coalesce((v_states->v_member.id->>'hp')::numeric,0)>0 then
        v_target_id:=v_member.id;v_target_name:=v_member.name;exit;
      end if;
    end loop;
    if v_target_id is not null then
      v_target_state:=v_states->v_target_id;v_hp:=coalesce((v_target_state->>'hp')::numeric,1);v_max_hp:=coalesce((v_target_state->>'max_hp')::numeric,1);v_target_def:=greatest(1,coalesce((v_target_state->>'defense')::numeric,1));v_target_elem:=v_target_state->>'element';v_target_strategy:=v_target_state->>'strategy';
      v_dt:=v_target_state->'defense_technique';v_elem:=public.bwboss01_element_multiplier(v_boss_elem,v_target_elem);
      v_fx:=public.combat_technique_worldboss_defense_effect_v220(v_dt,v_round,v_hp/greatest(1,v_max_hp),v_elem);
      v_elem:=coalesce((v_fx->>'element_multiplier')::numeric,v_elem);v_def_tech_reduction:=coalesce((v_fx->>'damage_reduction')::numeric,0);v_tech_effects:=coalesce(v_fx->'effects','[]'::jsonb);
      v_target_evasion:=coalesce((v_target_state->>'evasion_bonus')::numeric,0)+coalesce((v_fx->>'evasion_bonus')::numeric,0);
      v_hit_chance:=greatest(v_socket.hit_floor,least(v_socket.hit_ceiling,v_socket.base_hit_rate+v_boss_hit_bonus-v_target_evasion));
      v_hit_roll:=random();
      if v_hit_roll>v_hit_chance then
        v_actions:=v_actions||jsonb_build_array(jsonb_build_object('type','boss_miss','round',v_round,'actor_name',v_def.name,'target_id',v_target_id,'target_name',v_target_name,'hit_rate',v_hit_chance,'defense_technique_name',coalesce(v_dt->>'name',''),'defense_technique',v_dt,'technique_effects',v_tech_effects,'boss_hp_percent',round(v_boss_hp/v_boss_max_hp*100,2)));
      else
        v_element_resist:=coalesce(nullif(v_target_state->'element_resistance'->>v_boss_elem,'')::numeric,0)+coalesce((v_fx->>'element_resistance')::numeric,0);
        v_element_factor:=greatest(v_socket.element_factor_min,least(v_socket.element_factor_max,1+v_boss_element_damage-v_element_resist));
        v_pct:=0.12*v_elem*v_element_factor*(v_boss_attack/(v_boss_attack+v_target_def))*2;
        v_pct:=greatest(0.035,least(case when v_run.difficulty='hard' then 0.32 else 0.26 end,v_pct));
        if v_phase='rage' then v_pct:=v_pct*1.20; end if;
        if v_target_strategy='guard' then v_pct:=v_pct*0.72; elsif v_target_strategy='balanced' and v_hp/v_max_hp<0.40 then v_pct:=v_pct*0.86; end if;
        v_pct:=v_pct*(1-least(.80,greatest(0,v_def_tech_reduction)));
        v_boss_damage:=greatest(1,round(v_max_hp*v_pct*(0.92+random()*0.16)));
        v_hp:=greatest(0,v_hp-v_boss_damage);
        v_huiyuan_used:=coalesce((v_target_state->>'huiyuan_used')::boolean,false);v_bumie_used:=coalesce((v_target_state->>'bumie_used')::boolean,false);
        if v_hp>0 and coalesce((v_fx->>'heal_ratio')::numeric,0)>0 and not v_huiyuan_used
           and coalesce((v_target_state->>'hp')::numeric,0)>v_max_hp*coalesce((v_fx->>'heal_threshold')::numeric,.30)
           and v_hp<=v_max_hp*coalesce((v_fx->>'heal_threshold')::numeric,.30) then
          v_heal:=greatest(0,round(v_max_hp*coalesce((v_fx->>'heal_ratio')::numeric,0)));v_hp:=least(v_max_hp,v_hp+v_heal);
          v_states:=jsonb_set(v_states,array[v_target_id,'huiyuan_used'],'true'::jsonb,true);
          v_tech_effects:=v_tech_effects||jsonb_build_array(jsonb_build_object('side','defense','name',coalesce(v_dt->>'name',''),'text','玄水回元 +'||v_heal,'heal',v_heal));
        end if;
        if v_hp<=0 and coalesce((v_fx->>'lethal_guard')::boolean,false) and not v_bumie_used then
          v_hp:=greatest(1,coalesce((v_fx->>'lethal_guard_hp')::numeric,1));v_states:=jsonb_set(v_states,array[v_target_id,'bumie_used'],'true'::jsonb,true);
          v_tech_effects:=v_tech_effects||jsonb_build_array(jsonb_build_object('side','defense','name',coalesce(v_dt->>'name',''),'text','九霄不灭 · 生机保留1点','lethal_guard',true));
        end if;
        v_states:=jsonb_set(v_states,array[v_target_id,'hp'],to_jsonb(v_hp),true);
        v_contrib:=jsonb_set(v_contrib,array[v_target_id,'damage_taken'],to_jsonb(coalesce((v_contrib->v_target_id->>'damage_taken')::numeric,0)+v_boss_damage),true);
        if v_hp<=0 then
          if coalesce((v_states->v_target_id->>'rescued')::boolean,false) then
            v_states:=jsonb_set(v_states,array[v_target_id,'eliminated'],'true'::jsonb,true);
            v_states:=jsonb_set(v_states,array[v_target_id,'downed'],'false'::jsonb,true);
          else
            v_states:=jsonb_set(v_states,array[v_target_id,'downed'],'true'::jsonb,true);
          end if;
        end if;
        v_actions:=v_actions||jsonb_build_array(jsonb_build_object('type','boss_attack','round',v_round,'actor_name',v_def.name,'target_id',v_target_id,'target_name',v_target_name,'damage',v_boss_damage,'hit_rate',v_hit_chance,'element_multiplier',v_elem,'element_factor',v_element_factor,'defense_technique_name',coalesce(v_dt->>'name',''),'defense_technique',v_dt,'defense_technique_reduction',v_def_tech_reduction,'technique_effects',v_tech_effects,'hp_after',v_hp,'boss_hp_percent',round(v_boss_hp/v_boss_max_hp*100,2)));
      end if;
    end if;
  end loop;

  v_victory:=v_boss_hp<=0;
  v_token:=greatest(0,round(coalesce((v_cfg->>'token_reward')::numeric,case when v_run.difficulty='hard' then 18 else 10 end)*v_global_reward))::integer;
  v_world_contribution:=case when v_victory then round(100*v_party_size*(case when v_run.difficulty='hard' then 1.5 else 1 end)) else round(20*v_party_size) end;
  v_result:=jsonb_build_object('victory',v_victory,'boss_name',v_def.name,'party_size',v_party_size,'rounds',least(v_round,v_round_cap),'token_reward',case when v_victory then v_token else greatest(1,floor(v_token*0.25)) end,
    'world_contribution',v_world_contribution,'summary',case when v_victory then '队伍在狂暴时限前完成镇压。' else '队伍未能在本场时限内完成镇压。' end,'party_label',v_party_label);

  update public.world_boss_runs_bwboss01 set actions=v_actions,result=v_result,status=case when v_victory then 'victory' else 'defeat' end,ended_at=clock_timestamp() where id=v_run.id;
  update public.world_boss_parties_bwboss01 set status='completed',updated_at=clock_timestamp() where id=v_party.id;
  if v_victory then
    update public.world_boss_events_bwboss01 set progress=least(progress_target,progress+v_world_contribution),updated_at=clock_timestamp() where id=v_run.event_id;
    update public.world_boss_events_bwboss01 set status='echo',updated_at=clock_timestamp() where id=v_run.event_id and progress>=progress_target and status='open';
  end if;

  for v_member in select m.*,pc.name from public.world_boss_party_members_bwboss01 m join public.player_characters pc on pc.id=m.character_id where m.party_id=v_party.id loop
    v_id:=v_member.character_id::text;
    v_member_contribution:=round(coalesce((v_contrib->v_id->>'damage')::numeric,0)+coalesce((v_contrib->v_id->>'damage_taken')::numeric,0)*0.25+coalesce((v_contrib->v_id->>'mechanic')::numeric,0)*10+coalesce((v_contrib->v_id->>'rescues')::numeric,0)*500);
    insert into public.world_boss_contributions_bwboss01(run_id,character_id,user_id,damage,damage_taken,mechanic_points,rescues,survived,contribution)
    values(v_run.id,v_member.character_id,v_member.user_id,coalesce((v_contrib->v_id->>'damage')::numeric,0),coalesce((v_contrib->v_id->>'damage_taken')::numeric,0),coalesce((v_contrib->v_id->>'mechanic')::numeric,0),coalesce((v_contrib->v_id->>'rescues')::integer,0),not coalesce((v_states->v_id->>'eliminated')::boolean,false),v_member_contribution)
    on conflict(run_id,character_id) do nothing;
    if not exists(select 1 from public.world_boss_reward_ledger_bwboss01 where run_id=v_run.id and character_id=v_member.character_id) then
      v_qty:=public.bwboss01_grant_token(v_member.character_id,case when v_victory then v_token else greatest(1,floor(v_token*0.25)) end);
      insert into public.world_boss_reward_ledger_bwboss01(run_id,character_id,user_id,token_reward,reward_payload)
      values(v_run.id,v_member.character_id,v_member.user_id,case when v_victory then v_token else greatest(1,floor(v_token*0.25)) end,jsonb_build_object('token_item_code','world_boss_token_bwboss01','inventory_quantity_after',v_qty));
    end if;
    v_tech_reward:=public.combat_technique_process_boss_member_v220(v_run.id,v_member.character_id,v_run.difficulty,v_victory);
    if v_tech_reward is not null then
      update public.world_boss_reward_ledger_bwboss01
      set reward_payload=coalesce(reward_payload,'{}'::jsonb)||jsonb_build_object('combat_technique_shard_v220',v_tech_reward,'combat_technique_rare_eligible_v220',coalesce((v_tech_reward->>'eligible')::boolean,false))
      where run_id=v_run.id and character_id=v_member.character_id;
    end if;
  end loop;

  return jsonb_build_object('id',v_run.id,'boss_name',v_def.name,'difficulty',v_run.difficulty,'party_size',v_party_size,'actions',v_actions,'result',v_result,'ended_at',clock_timestamp());
end $function$;


-- start入口仍沿用生产逻辑；生产start会动态调用上面已替换的真实模拟器。这里只把本人奖励里的残卷同时暴露到顶层，方便CACHE122即时toast。
create or replace function public.start_world_boss_run_bwboss01(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb;v_grant jsonb;
begin
 v_result:=public.start_world_boss_run_bwboss01_pre_v220(p_request_id);v_grant:=coalesce(v_result#>'{run,my_reward,combat_technique_shard_v220}','null'::jsonb);
 return coalesce(v_result,'{}'::jsonb)||jsonb_build_object('combat_technique_shard_v220',case when jsonb_typeof(v_grant)='object' and coalesce((v_grant->>'quantity')::int,0)>0 then v_grant else null end);
end $$;

-- 兼容旧R1函数名：R2不再由leader RPC二次发奖，避免队友漏奖/leader重复奖；只读取已由模拟器写入的本人reward_payload。
create or replace function public.combat_technique_process_boss_result_v220(p_result jsonb)
returns jsonb language sql stable security definer set search_path='' as $$select coalesce(p_result#>'{run,my_reward,combat_technique_shard_v220}',p_result#>'{my_reward,combat_technique_shard_v220}')$$;

-- ---------- B-COMBAT V2.2.0 功法效果引擎 ----------
create or replace function public.bcombat01_resolve_hit_v243(
  p_attacker jsonb,p_defender jsonb,p_defender_hp integer,p_round integer,p_sequence integer,p_hit_roll numeric default null
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_set public.equipment_socket_settings_v210%rowtype;
  v_attack_element text;v_defender_element text;v_element numeric;v_element_raw numeric;
  v_base_reduction numeric;v_total_reduction numeric;v_extra_reduction numeric:=0;v_pen numeric:=0;
  v_ring_base_percent numeric:=0;v_ring_effective_percent numeric:=0;v_ring_multiplier numeric:=1;
  v_socket_element_damage numeric:=0;v_socket_element_resistance numeric:=0;v_socket_element_factor numeric:=1;
  v_base_hit numeric;v_hit_bonus numeric:=0;v_evasion numeric:=0;v_hit_floor numeric;v_hit_ceiling numeric;v_hit_chance numeric;v_roll numeric;v_is_hit boolean;
  v_damage integer:=0;v_hp_after integer;v_max_hp integer;
  v_atk uuid;v_def uuid;v_at jsonb;v_dt jsonb;v_acode text;v_dcode text;v_ap jsonb:='{}';v_dp jsonb:='{}';
  v_attack_factor numeric:=1;v_attack_tech_bonus numeric:=0;v_suppress numeric:=0;v_elem_suppress numeric:=0;v_value numeric;v_stacks int;
  v_effects jsonb:='[]'::jsonb;v_key text;v_used boolean;v_heal integer:=0;
begin
  select * into v_set from public.equipment_socket_settings_v210 where singleton_id=1;
  begin v_atk:=(p_attacker->>'character_id')::uuid;exception when others then v_atk:=null;end;
  begin v_def:=(p_defender->>'character_id')::uuid;exception when others then v_def:=null;end;
  if v_atk is not null then v_at:=public.combat_technique_context_snapshot_v220(v_atk,'attack');end if;
  if v_def is not null then v_dt:=public.combat_technique_context_snapshot_v220(v_def,'defense');end if;
  v_acode:=coalesce(v_at->>'effect_code','');v_dcode:=coalesce(v_dt->>'effect_code','');v_ap:=coalesce(v_at->'params','{}'::jsonb);v_dp:=coalesce(v_dt->'params','{}'::jsonb);

  v_attack_element:=coalesce(nullif(p_attacker->>'current_attack_element',''),nullif(p_attacker->>'element',''),'');v_defender_element:=coalesce(nullif(p_defender->>'element',''),'');
  v_base_hit:=coalesce(nullif(p_attacker->>'base_hit_rate','')::numeric,v_set.base_hit_rate,0.80);v_hit_bonus:=greatest(0,coalesce(nullif(p_attacker->>'hit_bonus','')::numeric,0));v_evasion:=greatest(0,coalesce(nullif(p_defender->>'evasion_bonus','')::numeric,nullif(p_defender->>'evasion_rate','')::numeric,0));
  if v_acode='ATK_HIT' then v_hit_bonus:=v_hit_bonus+coalesce((v_ap->>'hit_bonus')::numeric,0);v_attack_tech_bonus:=v_attack_tech_bonus+coalesce((v_ap->>'damage_bonus')::numeric,0);v_effects:=v_effects||jsonb_build_array(jsonb_build_object('side','attack','name',v_at->>'name','text','命中提升'));end if;
  if v_acode='ATK_ANTI_EVASION' then v_hit_bonus:=v_hit_bonus+coalesce((v_ap->>'hit_bonus')::numeric,0);if v_evasion>=coalesce((v_ap->>'high_evasion_threshold')::numeric,.10) then v_attack_tech_bonus:=v_attack_tech_bonus+coalesce((v_ap->>'high_evasion_damage_bonus')::numeric,0);end if;end if;
  if v_dcode='DEF_EVASION' then v_evasion:=v_evasion+coalesce((v_dp->>'evasion_bonus')::numeric,0);end if;
  v_hit_floor:=coalesce(v_set.hit_floor,0.05);v_hit_ceiling:=coalesce(v_set.hit_ceiling,0.98);v_hit_chance:=greatest(v_hit_floor,least(v_hit_ceiling,v_base_hit+v_hit_bonus-v_evasion));v_roll:=case when p_hit_roll is null then random() else greatest(0,least(.999999999999,p_hit_roll)) end;v_is_hit:=v_roll<v_hit_chance;

  v_element_raw:=public.bcombat01_element_multiplier(v_attack_element,v_defender_element,coalesce(nullif(p_attacker->>'major_order','')::integer,0),coalesce(nullif(p_attacker->>'minor_level','')::integer,0),coalesce(nullif(p_defender->>'major_order','')::integer,0),coalesce(nullif(p_defender->>'minor_level','')::integer,0));v_element:=v_element_raw;
  if v_acode='ATK_ELEMENT_ADVANTAGE' then v_value:=least(.90,coalesce((v_ap->>'element_swing_amplify')::numeric,0));if v_element>1 then v_element:=1+(v_element-1)*(1+v_value);elsif v_element<1 then v_element:=1-(1-v_element)*(1-v_value);end if;end if;
  if v_dcode='DEF_ALL_SUPPRESS' and v_element>1 then v_elem_suppress:=least(.90,coalesce((v_dp->>'element_advantage_suppression')::numeric,0));v_element:=1+(v_element-1)*(1-v_elem_suppress);end if;

  v_base_reduction:=least(.70,coalesce(nullif(p_defender->>'defense','')::numeric,0)/greatest(1,coalesce(nullif(p_defender->>'defense','')::numeric,0)+coalesce(nullif(p_defender->>'base_attack','')::numeric,1)*2));
  if v_acode='ATK_DEFENSE_PEN' then v_pen:=least(.80,coalesce((v_ap->>'defense_penetration')::numeric,0));v_base_reduction:=v_base_reduction*(1-v_pen);end if;
  if v_acode='ATK_FINAL_DAMAGE' then v_attack_tech_bonus:=v_attack_tech_bonus+coalesce((v_ap->>'damage_bonus')::numeric,0);end if;
  if v_acode='ATK_OPENING_BURST' then v_attack_tech_bonus:=v_attack_tech_bonus+case when p_round<=coalesce((v_ap->>'opening_rounds')::int,2) then coalesce((v_ap->>'opening_damage_bonus')::numeric,0) else coalesce((v_ap->>'later_damage_bonus')::numeric,0) end;end if;
  if v_acode='ATK_ANTI_DEFENSE' then v_attack_tech_bonus:=v_attack_tech_bonus+case when v_base_reduction>=coalesce((v_ap->>'high_defense_threshold')::numeric,.35) then coalesce((v_ap->>'high_defense_damage_bonus')::numeric,0) else coalesce((v_ap->>'normal_damage_bonus')::numeric,0) end;end if;
  v_max_hp:=coalesce(nullif(p_defender->>'vitality','')::integer,p_defender_hp);
  if v_acode='ATK_EXECUTE' and p_defender_hp<=floor(v_max_hp*coalesce((v_ap->>'hp_threshold')::numeric,.30)) then v_attack_tech_bonus:=v_attack_tech_bonus+coalesce((v_ap->>'damage_bonus')::numeric,0);end if;
  if v_acode='ATK_ROUND_STACK' then v_stacks:=least(coalesce((v_ap->>'max_stacks')::int,5),greatest(0,p_round-1));v_attack_tech_bonus:=v_attack_tech_bonus+v_stacks*coalesce((v_ap->>'per_stack_damage_bonus')::numeric,0);v_effects:=v_effects||jsonb_build_array(jsonb_build_object('side','attack','name',v_at->>'name','text','凌绝'||v_stacks||'层','stacks',v_stacks));end if;

  if v_dcode='DEF_REDUCTION' then v_extra_reduction:=v_extra_reduction+coalesce((v_dp->>'reduction')::numeric,0);end if;
  if v_dcode='DEF_STEADFAST' then v_extra_reduction:=v_extra_reduction+coalesce((v_dp->>'reduction')::numeric,0);if p_defender_hp>=v_max_hp*coalesce((v_dp->>'high_hp_threshold')::numeric,.50) then v_extra_reduction:=1-(1-v_extra_reduction)*(1-coalesce((v_dp->>'high_hp_extra_reduction')::numeric,0));end if;end if;
  if v_dcode='DEF_LOW_HP_RECOVERY' and p_defender_hp<=v_max_hp*coalesce((v_dp->>'hp_threshold')::numeric,.30) then v_extra_reduction:=1-(1-v_extra_reduction)*(1-coalesce((v_dp->>'low_hp_reduction')::numeric,0));end if;
  if v_dcode='DEF_OPENING_REDUCTION' then v_extra_reduction:=1-(1-v_extra_reduction)*(1-(case when p_round<=coalesce((v_dp->>'opening_rounds')::int,2) then coalesce((v_dp->>'opening_reduction')::numeric,0) else coalesce((v_dp->>'later_reduction')::numeric,0) end));end if;
  if v_dcode='DEF_ATTACK_TECH_SUPPRESS' then v_suppress:=least(.90,coalesce((v_dp->>'attack_tech_suppression')::numeric,0));v_extra_reduction:=1-(1-v_extra_reduction)*(1-coalesce((v_dp->>'reduction')::numeric,0));end if;
  if v_dcode='DEF_ALL_SUPPRESS' then v_suppress:=least(.90,coalesce((v_dp->>'attack_tech_suppression')::numeric,0));v_extra_reduction:=1-(1-v_extra_reduction)*(1-coalesce((v_dp->>'reduction')::numeric,0));end if;
  if v_dcode='DEF_LETHAL_GUARD' then v_extra_reduction:=1-(1-v_extra_reduction)*(1-coalesce((v_dp->>'reduction')::numeric,0));end if;
  v_attack_tech_bonus:=v_attack_tech_bonus*(1-v_suppress);v_attack_factor:=1+v_attack_tech_bonus;
  v_total_reduction:=least(.80,1-(1-v_base_reduction)*(1-least(.80,greatest(0,v_extra_reduction))));

  v_ring_base_percent:=least(50,greatest(0,coalesce(nullif(p_attacker->>'equipment_element_bonus','')::numeric,0)));v_ring_effective_percent:=v_ring_base_percent;v_ring_multiplier:=1+v_ring_effective_percent/100.0;
  if coalesce(v_attack_element,'')<>'' then v_socket_element_damage:=greatest(0,coalesce(nullif((p_attacker->'socket_element_damage')->>v_attack_element,'')::numeric,0));v_socket_element_resistance:=greatest(0,coalesce(nullif((p_defender->'socket_element_resistance')->>v_attack_element,'')::numeric,nullif((p_defender->'element_resistance')->>v_attack_element,'')::numeric,0));end if;
  if v_dcode='DEF_ELEMENT_RESIST' then v_socket_element_resistance:=v_socket_element_resistance+coalesce((v_dp->>'element_resistance')::numeric,0);end if;
  v_socket_element_factor:=greatest(coalesce(v_set.element_factor_min,.50),least(coalesce(v_set.element_factor_max,1.50),1+v_socket_element_damage-v_socket_element_resistance));

  if v_is_hit then v_damage:=greatest(1,floor(coalesce(nullif(p_attacker->>'attack','')::numeric,1)*v_attack_factor*v_element*v_ring_multiplier*v_socket_element_factor*(1-v_total_reduction)))::integer;v_hp_after:=greatest(0,p_defender_hp-v_damage);else v_damage:=0;v_hp_after:=greatest(0,p_defender_hp);end if;

  -- 首次存活跌入三成生机：玄水回元。使用事务级GUC防重复，刷新客户端无法重置。
  if v_is_hit and v_dcode='DEF_LOW_HP_RECOVERY' and v_hp_after>0 and p_defender_hp>v_max_hp*coalesce((v_dp->>'hp_threshold')::numeric,.30) and v_hp_after<=v_max_hp*coalesce((v_dp->>'hp_threshold')::numeric,.30) then
    v_key:='jiuxiao_v220.huiyuan_'||md5(coalesce(v_def::text,'')||':'||coalesce(current_setting('jiuxiao_v220.combat_context',true),'live'));
    v_used:=coalesce(current_setting(v_key,true),'')='1';if not v_used then v_heal:=floor(v_max_hp*coalesce((v_dp->>'heal_ratio')::numeric,0))::int;v_hp_after:=least(v_max_hp,v_hp_after+v_heal);perform set_config(v_key,'1',true);v_effects:=v_effects||jsonb_build_array(jsonb_build_object('side','defense','name',v_dt->>'name','text','玄水回元 +'||v_heal,'heal',v_heal));end if;
  end if;
  -- 圆满九霄不灭：每场首次致命伤保留1生机。
  if v_is_hit and v_hp_after<=0 and v_dcode='DEF_LETHAL_GUARD' and coalesce((v_dt->>'is_mastered')::boolean,false) then
    v_key:='jiuxiao_v220.bumie_'||md5(coalesce(v_def::text,'')||':'||coalesce(current_setting('jiuxiao_v220.combat_context',true),'live'));
    v_used:=coalesce(current_setting(v_key,true),'')='1';if not v_used then v_hp_after:=greatest(1,coalesce((v_dp->>'lethal_guard_hp')::int,1));perform set_config(v_key,'1',true);v_effects:=v_effects||jsonb_build_array(jsonb_build_object('side','defense','name',v_dt->>'name','text','九霄不灭 · 生机保留1点','lethal_guard',true));end if;
  end if;
  if v_at is not null and v_acode<>'ATK_ROUND_STACK' then v_effects:=v_effects||jsonb_build_array(jsonb_build_object('side','attack','name',v_at->>'name','effect_code',v_acode,'bonus',round(v_attack_tech_bonus,8)));end if;
  if v_dt is not null then v_effects:=v_effects||jsonb_build_array(jsonb_build_object('side','defense','name',v_dt->>'name','effect_code',v_dcode,'reduction',round(v_extra_reduction,8),'suppression',round(v_suppress,8)));end if;

  return jsonb_build_object('round',p_round,'sequence',p_sequence,'attacker_id',p_attacker->>'character_id','attacker_name',p_attacker->>'name','defender_id',p_defender->>'character_id','defender_name',p_defender->>'name','weapon_name',p_attacker->>'weapon_name','weapon_kind',p_attacker->>'weapon_kind','is_unarmed',coalesce(nullif(p_attacker->>'is_unarmed','')::boolean,false),'attack_technique_name',coalesce(v_at->>'name',''),'armor_name',p_defender->>'armor_name','is_naked',coalesce(nullif(p_defender->>'is_naked','')::boolean,false),'defense_technique_name',coalesce(v_dt->>'name',''),'attack_style',1+floor(random()*5)::integer,'defense_style',1+floor(random()*5)::integer,'is_hit',v_is_hit,'hit',v_is_hit,'missed',not v_is_hit,'hit_roll',round(v_roll,8),'hit_chance',round(v_hit_chance,8),'final_hit_rate',round(v_hit_chance,8),'base_hit_rate',round(v_base_hit,8),'attacker_hit_bonus',round(v_hit_bonus,8),'defender_evasion_bonus',round(v_evasion,8),'current_attack_element',v_attack_element,'element_multiplier',v_element,'element_relation',case when v_element>1 then 'overcome' when v_element<1 then 'restrained' else 'neutral' end,'defense_reduction',round(v_total_reduction,6),'equipment_element_bonus',v_ring_base_percent,'ring_base_percent',v_ring_base_percent,'ring_effective_percent',v_ring_effective_percent,'ring_multiplier',round(v_ring_multiplier,8)) ||
  jsonb_build_object('socket_element_damage_bonus',round(v_socket_element_damage,8),'socket_element_resistance',round(v_socket_element_resistance,8),'socket_element_factor',round(v_socket_element_factor,8),'socket_system_v210',coalesce(nullif(p_attacker->>'socket_system_v210','')::boolean,false) or coalesce(nullif(p_defender->>'socket_system_v210','')::boolean,false),'talent_ring_amplification_rate',0,'talent_ring_amplification_multiplier',1,'talent_source','','talent_base_stat_source',coalesce(p_attacker->>'talent_base_stat_source',''),'talent_base_stat_bonus',coalesce(nullif(p_attacker->>'talent_base_stat_bonus','')::numeric,0),'talent_base_stat_multiplier',coalesce(nullif(p_attacker->>'talent_base_stat_multiplier','')::numeric,1),'base_stat_talent_source',coalesce(p_attacker->>'talent_base_stat_source',''),'base_stat_talent_bonus',coalesce(nullif(p_attacker->>'talent_base_stat_bonus','')::numeric,0),'base_stat_talent_multiplier',coalesce(nullif(p_attacker->>'talent_base_stat_multiplier','')::numeric,1),'mutation_name',p_attacker->>'mutation_name','mutation_base_stat_multiplier',coalesce(nullif(p_attacker->>'mutation_base_stat_multiplier','')::numeric,1),'mutation_multiplier',1,'sword_heart_base_stat_multiplier',coalesce(nullif(p_attacker->>'sword_heart_base_stat_multiplier','')::numeric,1),'sword_heart_multiplier',1,'damage',v_damage,'hp_before',p_defender_hp,'hp_after',v_hp_after,'max_hp',v_max_hp,'low_health',v_hp_after>0 and v_hp_after<=floor(v_max_hp*.30),'defeated',v_hp_after<=0,'combat_technique_v220',true,'attack_combat_technique',v_at,'defense_combat_technique',v_dt,'attack_technique_factor',round(v_attack_factor,8),'technique_effects',v_effects);
end $$;

-- 保留SQL244兼容重载与五参数旧入口。
create or replace function public.bcombat01_resolve_hit_v243(p_attacker jsonb,p_defender jsonb,p_defender_hp integer,p_round integer,p_sequence integer,p_hit_roll double precision)
returns jsonb language plpgsql security definer set search_path='' as $$begin return public.bcombat01_resolve_hit_v243(p_attacker,p_defender,p_defender_hp,p_round,p_sequence,p_hit_roll::numeric);end$$;
create or replace function public.bcombat01_resolve_hit(p_attacker jsonb,p_defender jsonb,p_defender_hp integer,p_round integer,p_sequence integer)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','public','pg_temp' as $$begin return public.bcombat01_resolve_hit_v243(p_attacker,p_defender,p_defender_hp,p_round,p_sequence,random()::numeric);end$$;

-- ---------- GM RPC ----------
create or replace function public.admin9_get_combat_technique_config_v220()
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  perform public.v210_admin_guard();
  return jsonb_build_object(
    'settings',(select to_jsonb(s) from public.combat_technique_settings_v220 s where singleton_id=1),
    'ordinary_rates',jsonb_build_object(
      'yellow',null,
      'mystic',public.combat_technique_ordinary_drop_rate_v220('mystic'),
      'earth',public.combat_technique_ordinary_drop_rate_v220('earth'),
      'heaven',public.combat_technique_ordinary_drop_rate_v220('heaven'),
      'immortal',public.combat_technique_ordinary_drop_rate_v220('immortal')
    ),
    'opportunity_shard_rates',jsonb_build_object(
      'yellow',public.combat_technique_opportunity_shard_rate_v220('yellow'),
      'mystic',public.combat_technique_opportunity_shard_rate_v220('mystic'),
      'earth',public.combat_technique_opportunity_shard_rate_v220('earth'),
      'heaven',public.combat_technique_opportunity_shard_rate_v220('heaven'),
      'immortal',public.combat_technique_opportunity_shard_rate_v220('immortal')
    ),
    'definitions',(select coalesce(jsonb_agg(to_jsonb(d) order by sort_order),'[]'::jsonb) from public.combat_technique_definitions_v220 d),
    'recent_transfers',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (select to_jsonb(t) x from public.combat_technique_pvp_transfer_ledger_v220 t order by id desc limit 50) q),
    'recent_acquisition',(select coalesce(jsonb_agg(x),'[]'::jsonb) from (select to_jsonb(a) x from public.combat_technique_acquisition_ledger_v220 a order by id desc limit 100) q)
  );
end $$;

create or replace function public.admin9_update_combat_technique_settings_v220(p_patch jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v public.combat_technique_settings_v220%rowtype;
begin
 perform public.v210_admin_guard();
 update public.combat_technique_settings_v220 set
 enabled=coalesce((p_patch->>'enabled')::boolean,enabled),
 cultivation_upgrade_multiplier=coalesce((p_patch->>'cultivation_upgrade_multiplier')::numeric,cultivation_upgrade_multiplier),exclusive_upgrade_multiplier=coalesce((p_patch->>'exclusive_upgrade_multiplier')::numeric,exclusive_upgrade_multiplier),attack_upgrade_multiplier=coalesce((p_patch->>'attack_upgrade_multiplier')::numeric,attack_upgrade_multiplier),defense_upgrade_multiplier=coalesce((p_patch->>'defense_upgrade_multiplier')::numeric,defense_upgrade_multiplier),
 level_effect_growth=coalesce((p_patch->>'level_effect_growth')::numeric,level_effect_growth),mastery_effect_multiplier=coalesce((p_patch->>'mastery_effect_multiplier')::numeric,mastery_effect_multiplier),mastery_cost_multiplier=coalesce((p_patch->>'mastery_cost_multiplier')::numeric,mastery_cost_multiplier),
 shard_combine_count=coalesce((p_patch->>'shard_combine_count')::int,shard_combine_count),shard_exchange_enabled=coalesce((p_patch->>'shard_exchange_enabled')::boolean,shard_exchange_enabled),shard_exchange_cost=coalesce((p_patch->>'shard_exchange_cost')::int,shard_exchange_cost),shard_exchange_gain=coalesce((p_patch->>'shard_exchange_gain')::int,shard_exchange_gain),
 opportunity_relative_rate=coalesce((p_patch->>'opportunity_relative_rate')::numeric,opportunity_relative_rate),opportunity_yellow_shard_rate=coalesce((p_patch->>'opportunity_yellow_shard_rate')::numeric,opportunity_yellow_shard_rate),opportunity_attack_weight=coalesce((p_patch->>'opportunity_attack_weight')::numeric,opportunity_attack_weight),opportunity_defense_weight=coalesce((p_patch->>'opportunity_defense_weight')::numeric,opportunity_defense_weight),
 secret_mystic_rate=coalesce((p_patch->>'secret_mystic_rate')::numeric,secret_mystic_rate),secret_earth_rate=coalesce((p_patch->>'secret_earth_rate')::numeric,secret_earth_rate),secret_heaven_rate=coalesce((p_patch->>'secret_heaven_rate')::numeric,secret_heaven_rate),secret_immortal_rate=coalesce((p_patch->>'secret_immortal_rate')::numeric,secret_immortal_rate),secret_drop_quantity=coalesce((p_patch->>'secret_drop_quantity')::int,secret_drop_quantity),
 secret_pvp_steal_rate=coalesce((p_patch->>'secret_pvp_steal_rate')::numeric,secret_pvp_steal_rate),secret_antifarm_window_hours=coalesce((p_patch->>'secret_antifarm_window_hours')::int,secret_antifarm_window_hours),secret_antifarm_second_multiplier=coalesce((p_patch->>'secret_antifarm_second_multiplier')::numeric,secret_antifarm_second_multiplier),secret_antifarm_third_multiplier=coalesce((p_patch->>'secret_antifarm_third_multiplier')::numeric,secret_antifarm_third_multiplier),
 boss_normal_heaven_rate=coalesce((p_patch->>'boss_normal_heaven_rate')::numeric,boss_normal_heaven_rate),boss_hard_heaven_rate=coalesce((p_patch->>'boss_hard_heaven_rate')::numeric,boss_hard_heaven_rate),boss_hard_immortal_rate=coalesce((p_patch->>'boss_hard_immortal_rate')::numeric,boss_hard_immortal_rate),boss_drop_quantity=coalesce((p_patch->>'boss_drop_quantity')::int,boss_drop_quantity),
 yellow_book_redeem_stones=coalesce((p_patch->>'yellow_book_redeem_stones')::bigint,yellow_book_redeem_stones),mystic_book_redeem_stones=coalesce((p_patch->>'mystic_book_redeem_stones')::bigint,mystic_book_redeem_stones),earth_book_redeem_stones=coalesce((p_patch->>'earth_book_redeem_stones')::bigint,earth_book_redeem_stones),heaven_book_redeem_stones=coalesce((p_patch->>'heaven_book_redeem_stones')::bigint,heaven_book_redeem_stones),immortal_book_redeem_stones=coalesce((p_patch->>'immortal_book_redeem_stones')::bigint,immortal_book_redeem_stones),
 config_version=config_version+1,updated_at=clock_timestamp() where singleton_id=1 returning * into v;
 return to_jsonb(v);
end $$;

create or replace function public.admin9_update_combat_technique_definition_v220(p_code text,p_patch jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$declare v public.combat_technique_definitions_v220%rowtype;begin perform public.v210_admin_guard();update public.combat_technique_definitions_v220 set display_name=coalesce(p_patch->>'display_name',display_name),role_name=coalesce(p_patch->>'role_name',role_name),description=coalesce(p_patch->>'description',description),acquisition_hint=coalesce(p_patch->>'acquisition_hint',acquisition_hint),pool_weight=coalesce((p_patch->>'pool_weight')::numeric,pool_weight),enabled=coalesce((p_patch->>'enabled')::boolean,enabled),base_params=coalesce(p_patch->'base_params',base_params),updated_at=clock_timestamp() where code=p_code returning * into v;if v.code is null then raise exception 'COMBAT_TECHNIQUE_INVALID';end if;update public.combat_technique_settings_v220 set config_version=config_version+1,updated_at=clock_timestamp() where singleton_id=1;return to_jsonb(v);end $$;

create or replace function public.admin9_check_combat_technique_integration_v220()
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_world text;v_secret_capture text:='';v_secret_resolve text:='';v_secret_process text:='';v_secret_settle text:='';v_destiny text;v_secret_chain boolean:=false;
  v_at uuid:=gen_random_uuid();
  v_df uuid:=gen_random_uuid();
  j_at jsonb:=jsonb_build_object('character_id',v_at::text,'name','TEST-A','attack',10000,'base_attack',10000,'defense',0,'vitality',10000,'major_order',0,'minor_level',0,'base_hit_rate',1,'hit_bonus',0,'evasion_bonus',0,'equipment_element_bonus',0,'socket_element_damage','{}'::jsonb,'socket_element_resistance','{}'::jsonb);
  j_df jsonb:=jsonb_build_object('character_id',v_df::text,'name','TEST-D','attack',10000,'base_attack',10000,'defense',13333.3333,'vitality',10000,'major_order',0,'minor_level',0,'base_hit_rate',1,'hit_bonus',0,'evasion_bonus',0,'equipment_element_bonus',0,'socket_element_damage','{}'::jsonb,'socket_element_resistance','{}'::jsonb);
  r_base jsonb;r_attack jsonb;r_defense jsonb;r_stack1 jsonb;r_stack6 jsonb;r_lethal jsonb;
begin
  perform public.v210_admin_guard();
  select lower(pg_get_functiondef(to_regprocedure('public.bwboss01_simulate_run(uuid)'))) into v_world;
  select lower(pg_get_functiondef(to_regprocedure('public.secret_realm_capture_battle_snapshot_bsecretrealm01(uuid)'))) into v_secret_capture;
  select lower(pg_get_functiondef(to_regprocedure('public.secret_realm_resolve_battle_bsecretrealm01(jsonb,jsonb,integer,text)'))) into v_secret_resolve;
  select lower(pg_get_functiondef(to_regprocedure('public.secret_realm_process_due_minutes_bsecretrealm01(uuid,timestamp with time zone)'))) into v_secret_process;
  select lower(pg_get_functiondef(to_regprocedure('public.settle_secret_realm_progress_bsecretrealm01_pre_v220(uuid)'))) into v_secret_settle;
  v_secret_chain:=position('bcombat01_character_snapshot' in coalesce(v_secret_capture,''))>0
    and position('bcombat01_resolve_hit_v243' in coalesce(v_secret_resolve,''))>0
    and position('secret_realm_resolve_battle_bsecretrealm01' in coalesce(v_secret_process,''))>0
    and position('secret_realm_process_due_minutes_bsecretrealm01' in coalesce(v_secret_settle,''))>0;
  select lower(pg_get_functiondef(to_regprocedure('public.challenge_battle_power_bcombat01_pre_v220(uuid,uuid)'))) into v_destiny;

  delete from public.character_combat_techniques_v220 where character_id in (v_at,v_df);
  r_base:=public.bcombat01_resolve_hit_v243(j_at,j_df,10000,1,1,0::numeric);

  insert into public.character_combat_techniques_v220(character_id,technique_code,level,is_mastered,equipped) values(v_at,'atk_yellow_pofeng',1,false,true);
  r_attack:=public.bcombat01_resolve_hit_v243(j_at,j_df,10000,1,1,0::numeric);
  delete from public.character_combat_techniques_v220 where character_id=v_at;

  insert into public.character_combat_techniques_v220(character_id,technique_code,level,is_mastered,equipped) values(v_df,'def_yellow_huti',1,false,true);
  r_defense:=public.bcombat01_resolve_hit_v243(j_at,j_df,10000,1,1,0::numeric);
  delete from public.character_combat_techniques_v220 where character_id=v_df;

  insert into public.character_combat_techniques_v220(character_id,technique_code,level,is_mastered,equipped) values(v_at,'atk_immortal_lingjue',30,false,true);
  r_stack1:=public.bcombat01_resolve_hit_v243(j_at,j_df,10000,1,1,0::numeric);
  r_stack6:=public.bcombat01_resolve_hit_v243(j_at,j_df,10000,6,1,0::numeric);
  delete from public.character_combat_techniques_v220 where character_id=v_at;

  insert into public.character_combat_techniques_v220(character_id,technique_code,level,is_mastered,equipped) values(v_df,'def_immortal_bumie',30,true,true);
  r_lethal:=public.bcombat01_resolve_hit_v243(j_at||jsonb_build_object('attack',1000000),j_df,1000,1,1,0::numeric);
  delete from public.character_combat_techniques_v220 where character_id=v_df;

  return jsonb_build_object(
    'status','ok',
    'attack_definitions',(select count(*) from public.combat_technique_definitions_v220 where family='attack' and enabled),
    'defense_definitions',(select count(*) from public.combat_technique_definitions_v220 where family='defense' and enabled),
    'effect_engine',jsonb_build_object(
      'base_damage',(r_base->>'damage')::int,
      'attack_damage',(r_attack->>'damage')::int,
      'attack_increased',(r_attack->>'damage')::int>(r_base->>'damage')::int,
      'defense_damage',(r_defense->>'damage')::int,
      'defense_reduced',(r_defense->>'damage')::int<(r_base->>'damage')::int,
      'round1_damage',(r_stack1->>'damage')::int,
      'round6_damage',(r_stack6->>'damage')::int,
      'round_stack_increased',(r_stack6->>'damage')::int>(r_stack1->>'damage')::int,
      'lethal_hp_after',(r_lethal->>'hp_after')::int,
      'lethal_guard_pass',(r_lethal->>'hp_after')::int=1
    ),
    'destiny_bcombat_hook',position('bcombat' in coalesce(v_destiny,''))>0,
    'secret_bcombat_hook',v_secret_chain,
    'secret_chain_mode','settle→process_due→resolve_battle→bcombat01_resolve_hit_v243',
    'worldboss_combat_hook',position('sql254_r5_world_boss_effect_adapter' in coalesce(v_world,''))>0 and position('combat_technique_worldboss_attack_effect_v220' in coalesce(v_world,''))>0 and position('combat_technique_worldboss_defense_effect_v220' in coalesce(v_world,''))>0,
    'worldboss_engine_mode','独立服务端模拟器 + 锁定battle_snapshot + effect_code适配器',
    'worldboss_effect_engine',jsonb_build_object(
      'attack_helper_pass',coalesce((public.combat_technique_worldboss_attack_effect_v220(jsonb_build_object('name','T','effect_code','ATK_FINAL_DAMAGE','params',jsonb_build_object('damage_bonus',.10)),1,1,0,0,1)->>'damage_bonus')::numeric,0)=.10,
      'round_stack_pass',coalesce((public.combat_technique_worldboss_attack_effect_v220(jsonb_build_object('name','T','effect_code','ATK_ROUND_STACK','params',jsonb_build_object('per_stack_damage_bonus',.02,'max_stacks',5)),6,1,0,0,1)->>'damage_bonus')::numeric,0)=.10,
      'lethal_guard_pass',coalesce((public.combat_technique_worldboss_defense_effect_v220(jsonb_build_object('name','T','effect_code','DEF_LETHAL_GUARD','is_mastered',true,'params',jsonb_build_object('reduction',.02,'lethal_guard_hp',1)),1,1,1)->>'lethal_guard')::boolean,false)
    ),
    'hit_floor_ceiling','5%-98%',
    'snapshot_destiny',to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)') is not null,
    'snapshot_secret',to_regprocedure('public.enter_secret_realm_bsecretrealm01(uuid)') is not null,
    'snapshot_worldboss',to_regprocedure('public.set_world_boss_member_ready_bwboss01(boolean,text,uuid)') is not null
  );
exception when others then
  delete from public.character_combat_techniques_v220 where character_id in (v_at,v_df);
  raise;
end $$;

-- ---------- 权限 ----------
revoke all on function public.combat_technique_grade_normalize_v220(text),public.combat_technique_grade_max_level_v220(text),public.combat_technique_grade_cost_factor_v220(text),public.combat_technique_active_character_v220(),public.combat_technique_effect_params_v220(text,integer,boolean),public.combat_technique_current_snapshot_v220(uuid,text),public.combat_technique_capture_context_v220(uuid,text,text),public.combat_technique_context_snapshot_v220(uuid,text),public.combat_technique_ordinary_drop_rate_v220(text),public.combat_technique_opportunity_shard_rate_v220(text),public.combat_technique_pick_code_v220(text,text),public.combat_technique_grant_shard_v220(uuid,text,integer,text),public.combat_technique_secret_context_ref_v220(uuid),public.combat_technique_secret_drop_rate_v220(text),public.combat_technique_secret_stage_grade_v220(text),public.combat_technique_steal_secret_pending_v220(uuid,uuid,text),public.combat_technique_process_secret_result_v220(jsonb,text),public.combat_technique_process_boss_result_v220(jsonb),public.combat_technique_process_boss_member_v220(uuid,uuid,text,boolean),public.combat_technique_worldboss_attack_effect_v220(jsonb,integer,numeric,numeric,numeric,numeric),public.combat_technique_worldboss_defense_effect_v220(jsonb,integer,numeric,numeric),public.combat_technique_scale_upgrade_costs_v220(jsonb,numeric),public.combat_technique_try_world_announcement_v220(uuid,text) from public,anon,authenticated;

grant execute on function public.get_combat_technique_system_v220(),public.combine_combat_technique_shards_v220(text,uuid),public.learn_combat_technique_v220(text,uuid),public.set_combat_technique_equipped_v220(text,text),public.upgrade_combat_technique_v220(text,uuid),public.exchange_combat_technique_shards_v220(text,uuid),public.get_cultivation_technique_system_v220(),public.get_exclusive_technique_system_v220(),public.upgrade_cultivation_technique_v220(uuid,uuid),public.upgrade_exclusive_technique_v220(uuid,uuid) to authenticated;
revoke all on function public.get_combat_technique_system_v220(),public.combine_combat_technique_shards_v220(text,uuid),public.learn_combat_technique_v220(text,uuid),public.set_combat_technique_equipped_v220(text,text),public.upgrade_combat_technique_v220(text,uuid),public.exchange_combat_technique_shards_v220(text,uuid),public.get_cultivation_technique_system_v220(),public.get_exclusive_technique_system_v220(),public.upgrade_cultivation_technique_v220(uuid,uuid),public.upgrade_exclusive_technique_v220(uuid,uuid) from anon;

revoke all on function public.challenge_battle_power_bcombat01(uuid,uuid),public.settle_opportunity_v4(boolean),public.enter_secret_realm_bsecretrealm01(uuid),public.settle_secret_realm_progress_bsecretrealm01(uuid),public.claim_secret_realm_rewards_bsecretrealm01(uuid),public.set_world_boss_member_ready_bwboss01(boolean,text,uuid),public.start_world_boss_run_bwboss01(uuid) from anon;
grant execute on function public.challenge_battle_power_bcombat01(uuid,uuid),public.settle_opportunity_v4(boolean),public.enter_secret_realm_bsecretrealm01(uuid),public.settle_secret_realm_progress_bsecretrealm01(uuid),public.claim_secret_realm_rewards_bsecretrealm01(uuid),public.set_world_boss_member_ready_bwboss01(boolean,text,uuid),public.start_world_boss_run_bwboss01(uuid) to authenticated;
revoke all on function public.admin9_get_combat_technique_config_v220(),public.admin9_update_combat_technique_settings_v220(jsonb),public.admin9_update_combat_technique_definition_v220(text,jsonb),public.admin9_check_combat_technique_integration_v220() from anon;
grant execute on function public.admin9_get_combat_technique_config_v220(),public.admin9_update_combat_technique_settings_v220(jsonb),public.admin9_update_combat_technique_definition_v220(text,jsonb),public.admin9_check_combat_technique_integration_v220() to authenticated;

-- ---------- 发布门禁：对象、20本、配置、真正伤害公式、四链钩子 ----------
do $gate$
declare v_count int;v_grade record;v_destiny text;v_opportunity text;v_secret_capture text:='';v_secret_resolve text:='';v_secret_process text:='';v_secret_settle text:='';v_secret_chain boolean:=false;v_world text;v_bcombat text;v_expected numeric;v_actual numeric;v_at uuid:=gen_random_uuid();v_df uuid:=gen_random_uuid();r0 jsonb;r1 jsonb;r2 jsonb;r3 jsonb;r4 jsonb;r5 jsonb;j_at jsonb;j_df jsonb;
begin
 select count(*) into v_count from public.combat_technique_definitions_v220 where enabled;if v_count<>20 then raise exception 'SQL254_GATE_DEFINITIONS_%_EXPECTED_20',v_count;end if;
 if (select count(*) from public.combat_technique_definitions_v220 where family='attack')<>10 or (select count(*) from public.combat_technique_definitions_v220 where family='defense')<>10 then raise exception 'SQL254_GATE_FAMILY_COUNT';end if;
 if (select shard_combine_count from public.combat_technique_settings_v220 where singleton_id=1)<>10 then raise exception 'SQL254_GATE_COMBINE_NOT_10';end if;
 if (select cultivation_upgrade_multiplier from public.combat_technique_settings_v220 where singleton_id=1)<>10 or (select exclusive_upgrade_multiplier from public.combat_technique_settings_v220 where singleton_id=1)<>10 or (select attack_upgrade_multiplier from public.combat_technique_settings_v220 where singleton_id=1)<>10 or (select defense_upgrade_multiplier from public.combat_technique_settings_v220 where singleton_id=1)<>10 then raise exception 'SQL254_GATE_UPGRADE_MULTIPLIER_NOT_10';end if;
 if (select opportunity_relative_rate from public.combat_technique_settings_v220 where singleton_id=1)<>.20 then raise exception 'SQL254_GATE_OPPORTUNITY_NOT_ONE_FIFTH';end if;
 if (select opportunity_yellow_shard_rate from public.combat_technique_settings_v220 where singleton_id=1)<>.05 then raise exception 'SQL254_GATE_YELLOW_SHARD_RATE_NOT_5_PERCENT';end if;
 if not (select enabled from public.combat_technique_settings_v220 where singleton_id=1) then raise exception 'SQL254_GATE_SYSTEM_DISABLED';end if;
 if (select shard_exchange_cost from public.combat_technique_settings_v220 where singleton_id=1)<>5 or (select shard_exchange_gain from public.combat_technique_settings_v220 where singleton_id=1)<>1 then raise exception 'SQL254_GATE_EXCHANGE_NOT_5_TO_1';end if;
 if (select secret_mystic_rate from public.combat_technique_settings_v220 where singleton_id=1)<>.12 or (select secret_earth_rate from public.combat_technique_settings_v220 where singleton_id=1)<>.08 or (select secret_heaven_rate from public.combat_technique_settings_v220 where singleton_id=1)<>.04 or (select secret_immortal_rate from public.combat_technique_settings_v220 where singleton_id=1)<>.02 then raise exception 'SQL254_GATE_SECRET_RATE_MISMATCH';end if;
 if (select boss_normal_heaven_rate from public.combat_technique_settings_v220 where singleton_id=1)<>.20 or (select boss_hard_heaven_rate from public.combat_technique_settings_v220 where singleton_id=1)<>.25 or (select boss_hard_immortal_rate from public.combat_technique_settings_v220 where singleton_id=1)<>.05 then raise exception 'SQL254_GATE_BOSS_RATE_MISMATCH';end if;
 -- 生产普通功法掉率结构门禁：真实总概率必须等于 main_rate+support_rate。
 for v_grade in select * from (values('mystic','玄品'),('earth','地品'),('heaven','天品'),('immortal','仙品')) as g(code,grade_label) loop
   select main_rate+support_rate into v_expected from public.opportunity_v4_technique_drop_rates where grade=v_grade.grade_label;
   v_actual:=public.combat_technique_ordinary_drop_rate_v220(v_grade.code);
   if v_expected is null or v_actual is null or abs(v_actual-v_expected)>0.00000001 then
     raise exception 'SQL254_GATE_ORDINARY_TECHNIQUE_RATE_MISMATCH:% expected=% actual=%',v_grade.code,v_expected,v_actual;
   end if;
 end loop;
 v_actual:=public.combat_technique_ordinary_drop_rate_v220('yellow');
 if v_actual is not null then raise exception 'SQL254_GATE_YELLOW_MUST_NOT_FAKE_ORDINARY_RATE:%',v_actual; end if;
 v_actual:=public.combat_technique_opportunity_shard_rate_v220('yellow');
 if v_actual is null or abs(v_actual-.05)>0.00000001 then raise exception 'SQL254_GATE_YELLOW_SHARD_RATE_MISMATCH:%',v_actual; end if;
 for v_grade in select * from (values('mystic'),('earth'),('heaven'),('immortal')) as g(code) loop
   v_expected:=public.combat_technique_ordinary_drop_rate_v220(v_grade.code)*.20;
   v_actual:=public.combat_technique_opportunity_shard_rate_v220(v_grade.code);
   if v_expected is null or v_actual is null or abs(v_actual-v_expected)>0.00000001 then
     raise exception 'SQL254_GATE_COMBAT_SHARD_RATE_MISMATCH:% expected=% actual=%',v_grade.code,v_expected,v_actual;
   end if;
 end loop;
 select lower(pg_get_functiondef(to_regprocedure('public.settle_opportunity_v4(boolean)'))) into v_opportunity;
 if position('opportunity_v3_results' in coalesce(v_opportunity,''))=0
    or position('settlement_batch_id' in coalesce(v_opportunity,''))=0
    or position('combat_technique_opportunity_shard_rate_v220' in coalesce(v_opportunity,''))=0 then
   raise exception 'SQL254_GATE_OPPORTUNITY_BATCH_ADAPTER_MISSING';
 end if;
 select lower(pg_get_functiondef(to_regprocedure('public.bcombat01_resolve_hit_v243(jsonb,jsonb,integer,integer,integer,numeric)'))) into v_bcombat;if position('combat_technique_context_snapshot_v220' in v_bcombat)=0 or position('technique_effects' in v_bcombat)=0 or position('def_lethal_guard' in v_bcombat)=0 then raise exception 'SQL254_GATE_BCOMBAT_EFFECT_ENGINE_MISSING';end if;
 select lower(pg_get_functiondef(to_regprocedure('public.challenge_battle_power_bcombat01_pre_v220(uuid,uuid)'))) into v_destiny;if position('bcombat' in coalesce(v_destiny,''))=0 then raise exception 'SQL254_GATE_DESTINY_BCOMBAT_MISSING';end if;
 select lower(pg_get_functiondef(to_regprocedure('public.secret_realm_capture_battle_snapshot_bsecretrealm01(uuid)'))) into v_secret_capture;
 select lower(pg_get_functiondef(to_regprocedure('public.secret_realm_resolve_battle_bsecretrealm01(jsonb,jsonb,integer,text)'))) into v_secret_resolve;
 select lower(pg_get_functiondef(to_regprocedure('public.secret_realm_process_due_minutes_bsecretrealm01(uuid,timestamp with time zone)'))) into v_secret_process;
 select lower(pg_get_functiondef(to_regprocedure('public.settle_secret_realm_progress_bsecretrealm01_pre_v220(uuid)'))) into v_secret_settle;
 v_secret_chain:=position('bcombat01_character_snapshot' in coalesce(v_secret_capture,''))>0 and position('bcombat01_resolve_hit_v243' in coalesce(v_secret_resolve,''))>0 and position('secret_realm_resolve_battle_bsecretrealm01' in coalesce(v_secret_process,''))>0 and position('secret_realm_process_due_minutes_bsecretrealm01' in coalesce(v_secret_settle,''))>0;
 if not v_secret_chain then raise exception 'SQL254_GATE_SECRET_BCOMBAT_TRANSITIVE_CHAIN_MISSING';end if;
 select lower(pg_get_functiondef(to_regprocedure('public.bwboss01_simulate_run(uuid)'))) into v_world;if position('sql254_r5_world_boss_effect_adapter' in coalesce(v_world,''))=0 or position('combat_technique_worldboss_attack_effect_v220' in coalesce(v_world,''))=0 or position('combat_technique_worldboss_defense_effect_v220' in coalesce(v_world,''))=0 or position('combat_attack_technique_v220' in coalesce(v_world,''))=0 or position('combat_defense_technique_v220' in coalesce(v_world,''))=0 then raise exception 'SQL254_GATE_WORLD_BOSS_EFFECT_ADAPTER_MISSING';end if;
 -- 世界BOSS独立模拟器不能直接造正式run做破坏性测试，因此对其实际调用的纯effect helper做数值门禁。
 if coalesce((public.combat_technique_worldboss_attack_effect_v220(jsonb_build_object('name','T','effect_code','ATK_FINAL_DAMAGE','params',jsonb_build_object('damage_bonus',.10)),1,1,0,0,1)->>'damage_bonus')::numeric,0)<>.10 then raise exception 'SQL254_GATE_WORLD_BOSS_ATTACK_HELPER_FAIL';end if;
 if coalesce((public.combat_technique_worldboss_attack_effect_v220(jsonb_build_object('name','T','effect_code','ATK_ROUND_STACK','params',jsonb_build_object('per_stack_damage_bonus',.02,'max_stacks',5)),6,1,0,0,1)->>'damage_bonus')::numeric,0)<>.10 then raise exception 'SQL254_GATE_WORLD_BOSS_STACK_HELPER_FAIL';end if;
 if not coalesce((public.combat_technique_worldboss_defense_effect_v220(jsonb_build_object('name','T','effect_code','DEF_LETHAL_GUARD','is_mastered',true,'params',jsonb_build_object('reduction',.02,'lethal_guard_hp',1)),1,1,1)->>'lethal_guard')::boolean,false) then raise exception 'SQL254_GATE_WORLD_BOSS_LETHAL_HELPER_FAIL';end if;
 if to_regprocedure('public.admin9_check_combat_technique_integration_v220()') is null then raise exception 'SQL254_GATE_ADMIN_CHECK_MISSING';end if;
 -- 实际调用伤害函数，不只查字段/函数名：增伤、减伤、凌绝叠层、不灭保命必须真实改变结果。
 j_at:=jsonb_build_object('character_id',v_at::text,'name','SQL254-GATE-A','attack',10000,'base_attack',10000,'defense',0,'vitality',10000,'major_order',0,'minor_level',0,'base_hit_rate',1,'hit_bonus',0,'evasion_bonus',0,'equipment_element_bonus',0,'socket_element_damage','{}'::jsonb,'socket_element_resistance','{}'::jsonb);
 j_df:=jsonb_build_object('character_id',v_df::text,'name','SQL254-GATE-D','attack',10000,'base_attack',10000,'defense',13333.3333,'vitality',10000,'major_order',0,'minor_level',0,'base_hit_rate',1,'hit_bonus',0,'evasion_bonus',0,'equipment_element_bonus',0,'socket_element_damage','{}'::jsonb,'socket_element_resistance','{}'::jsonb);
 r0:=public.bcombat01_resolve_hit_v243(j_at,j_df,10000,1,1,0::numeric);
 insert into public.character_combat_techniques_v220(character_id,technique_code,level,is_mastered,equipped) values(v_at,'atk_yellow_pofeng',1,false,true);r1:=public.bcombat01_resolve_hit_v243(j_at,j_df,10000,1,1,0::numeric);delete from public.character_combat_techniques_v220 where character_id=v_at;
 insert into public.character_combat_techniques_v220(character_id,technique_code,level,is_mastered,equipped) values(v_df,'def_yellow_huti',1,false,true);r2:=public.bcombat01_resolve_hit_v243(j_at,j_df,10000,1,1,0::numeric);delete from public.character_combat_techniques_v220 where character_id=v_df;
 insert into public.character_combat_techniques_v220(character_id,technique_code,level,is_mastered,equipped) values(v_at,'atk_immortal_lingjue',30,false,true);r3:=public.bcombat01_resolve_hit_v243(j_at,j_df,10000,1,1,0::numeric);r4:=public.bcombat01_resolve_hit_v243(j_at,j_df,10000,6,1,0::numeric);delete from public.character_combat_techniques_v220 where character_id=v_at;
 insert into public.character_combat_techniques_v220(character_id,technique_code,level,is_mastered,equipped) values(v_df,'def_immortal_bumie',30,true,true);r5:=public.bcombat01_resolve_hit_v243(j_at||jsonb_build_object('attack',1000000),j_df,1000,1,1,0::numeric);delete from public.character_combat_techniques_v220 where character_id=v_df;
 if (r1->>'damage')::int<=(r0->>'damage')::int then raise exception 'SQL254_GATE_REAL_ATTACK_EFFECT_FAIL';end if;
 if (r2->>'damage')::int>=(r0->>'damage')::int then raise exception 'SQL254_GATE_REAL_DEFENSE_EFFECT_FAIL';end if;
 if (r4->>'damage')::int<=(r3->>'damage')::int then raise exception 'SQL254_GATE_REAL_ROUND_STACK_FAIL';end if;
 if (r5->>'hp_after')::int<>1 then raise exception 'SQL254_GATE_REAL_LETHAL_GUARD_FAIL';end if;
end $gate$;

-- release_control结构在历史包中可能继续使用旧字段；只在存在时更新，绝不假设列。
do $release$
begin
 if to_regclass('public.jiuxiao_app_release_control') is not null then
   begin execute $$update public.jiuxiao_app_release_control set release_name='V2.2.0 CACHE122',cache_epoch=122,updated_at=clock_timestamp() where singleton_id=1$$;exception when undefined_column then null;end;
 end if;
end $release$;

commit;
notify pgrst,'reload schema';

select jsonb_build_object(
 'success',true,'gate','SQL254_GATE_PASSED','sql',254,'patch','R5_YELLOW_5PCT_AND_TRUE_RATE_UI','release','V2.2.0 CACHE122','attack_techniques',10,'defense_techniques',10,
 'shards','10同名合1整卷；同品其它5换1','upgrade_multiplier','普通/专属/攻伐/护体默认全部10×',
 'opportunity','黄品趋吉机缘内攻防残卷池独立5%；玄/地/天/仙=普通功法实际总掉率(main_rate+support_rate)×20%','secret_rates','玄12%/地8%/天4%/仙2%','secret_pvp','总残卷floor(50%)，6小时同对手第1次100%/第2次25%/第3次0',
 'world_boss','普通20%天；困难25%天+5%仙；每日珍稀资格沿用原前3胜',
 'combat','天命榜/秘境走B-COMBAT effect_code；世界BOSS按生产独立模拟器接入同语义effect_code+准备时快照',
 'opportunity_pool_rates',jsonb_build_object('yellow',public.combat_technique_opportunity_shard_rate_v220('yellow'),'mystic',public.combat_technique_opportunity_shard_rate_v220('mystic'),'earth',public.combat_technique_opportunity_shard_rate_v220('earth'),'heaven',public.combat_technique_opportunity_shard_rate_v220('heaven'),'immortal',public.combat_technique_opportunity_shard_rate_v220('immortal')),
 'next_sql',255
) as sql254_install_result;
