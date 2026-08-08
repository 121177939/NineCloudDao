-- 九霄问道 · SQL244 R2 · CACHE113 天命榜战斗运行时热修
-- 当前生产前提：
--   V2.1.1 CACHE113 已部署；
--   SQL243 R4 已正式门禁通过；
--   上一份 SQL244 执行失败（54023），事务未上线，因此编号继续使用 SQL244。
--
-- 已确认的两个生产故障：
--   A. bcombat01_resolve_hit_v243(..., double precision) does not exist
--      原因：旧天命榜入口把 random()（float8）直接传给 SQL243 R4 numeric 核心。
--   B. 54023 cannot pass more than 100 arguments to a function
--      原因：SQL243 R4 核心一次 jsonb_build_object 构造 50+ 键值对，
--            超过 PostgreSQL 单次函数调用 100 参数上限。
--
-- R2 修复：
--   1) 重建 numeric 核心，仅把超大 JSON 拆成两个 jsonb_build_object 后用 || 合并；
--      战斗公式、战报字段、命中/闪避、元素、伤害计算全部保持原样。
--   2) 新增 double precision 六参数兼容重载。
--   3) 五参数旧入口显式 random()::numeric。
--   4) 同事务执行真实运行时冒烟门禁：
--      numeric 核心、double precision 重载、五参数旧入口全部实际执行。
--
-- 不修改：玩家数据、挑战次数、冷却、奖励、秘境进度、CACHE113发布状态。
-- 任一门禁失败：整个 SQL244 R2 自动回滚。

begin;

do $precheck$
begin
  if to_regprocedure('public.bcombat01_resolve_hit_v243(jsonb,jsonb,integer,integer,integer,numeric)') is null then
    raise exception 'SQL244_PREREQUISITE_MISSING: numeric core';
  end if;
  if to_regprocedure('public.bcombat01_resolve_hit(jsonb,jsonb,integer,integer,integer)') is null then
    raise exception 'SQL244_PREREQUISITE_MISSING: legacy wrapper';
  end if;
end
$precheck$;

-- ① 修复 SQL243 R4 numeric 核心的超大 jsonb_build_object。
create or replace function public.bcombat01_resolve_hit_v243(
  p_attacker jsonb,
  p_defender jsonb,
  p_defender_hp integer,
  p_round integer,
  p_sequence integer,
  p_hit_roll numeric default null
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_set public.equipment_socket_settings_v210%rowtype;
  v_attack_element text;
  v_defender_element text;
  v_element numeric;
  v_base_reduction numeric;
  v_total_reduction numeric;
  v_ring_base_percent numeric:=0;
  v_ring_effective_percent numeric:=0;
  v_ring_multiplier numeric:=1;
  v_socket_element_damage numeric:=0;
  v_socket_element_resistance numeric:=0;
  v_socket_element_factor numeric:=1;
  v_base_hit numeric;
  v_hit_bonus numeric:=0;
  v_evasion numeric:=0;
  v_hit_floor numeric;
  v_hit_ceiling numeric;
  v_hit_chance numeric;
  v_roll numeric;
  v_is_hit boolean;
  v_damage integer:=0;
  v_hp_after integer;
begin
  select * into v_set
  from public.equipment_socket_settings_v210
  where singleton_id=1;

  v_attack_element:=coalesce(nullif(p_attacker->>'current_attack_element',''),nullif(p_attacker->>'element',''),'');
  v_defender_element:=coalesce(nullif(p_defender->>'element',''),'');

  v_base_hit:=coalesce(nullif(p_attacker->>'base_hit_rate','')::numeric,v_set.base_hit_rate,0.80);
  v_hit_bonus:=greatest(0,coalesce(nullif(p_attacker->>'hit_bonus','')::numeric,0));
  v_evasion:=greatest(0,coalesce(nullif(p_defender->>'evasion_bonus','')::numeric,nullif(p_defender->>'evasion_rate','')::numeric,0));
  v_hit_floor:=coalesce(v_set.hit_floor,0.05);
  v_hit_ceiling:=coalesce(v_set.hit_ceiling,0.98);
  if v_hit_floor>v_hit_ceiling then
    v_hit_floor:=least(v_hit_floor,v_hit_ceiling);
    v_hit_ceiling:=greatest(coalesce(v_set.hit_floor,0.05),coalesce(v_set.hit_ceiling,0.98));
  end if;
  v_hit_chance:=greatest(v_hit_floor,least(v_hit_ceiling,v_base_hit+v_hit_bonus-v_evasion));
  v_roll:=case when p_hit_roll is null then random() else greatest(0,least(0.999999999999,p_hit_roll)) end;
  v_is_hit:=v_roll<v_hit_chance;

  v_element:=public.bcombat01_element_multiplier(
    v_attack_element,v_defender_element,
    coalesce(nullif(p_attacker->>'major_order','')::integer,0),
    coalesce(nullif(p_attacker->>'minor_level','')::integer,0),
    coalesce(nullif(p_defender->>'major_order','')::integer,0),
    coalesce(nullif(p_defender->>'minor_level','')::integer,0)
  );

  v_base_reduction:=least(0.70,
    coalesce(nullif(p_defender->>'defense','')::numeric,0) /
    greatest(1,
      coalesce(nullif(p_defender->>'defense','')::numeric,0)
      + coalesce(nullif(p_defender->>'base_attack','')::numeric,1)*2
    )
  );
  v_total_reduction:=least(0.80,1-(1-v_base_reduction)*
    (1-coalesce(nullif(p_defender->>'defense_technique_reduction','')::numeric,0)));

  -- 旧戒指增伤继续保留；V2.1孔位元素增伤/抗性使用独立因子，避免重复计算戒指。
  v_ring_base_percent:=least(50,greatest(0,coalesce(nullif(p_attacker->>'equipment_element_bonus','')::numeric,0)));
  v_ring_effective_percent:=v_ring_base_percent;
  v_ring_multiplier:=1+v_ring_effective_percent/100.0;

  if coalesce(v_attack_element,'')<>'' then
    v_socket_element_damage:=greatest(0,coalesce(nullif((p_attacker->'socket_element_damage')->>v_attack_element,'')::numeric,0));
    v_socket_element_resistance:=greatest(0,coalesce(
      nullif((p_defender->'socket_element_resistance')->>v_attack_element,'')::numeric,
      nullif((p_defender->'element_resistance')->>v_attack_element,'')::numeric,
      0
    ));
  end if;
  v_socket_element_factor:=greatest(
    coalesce(v_set.element_factor_min,0.50),
    least(coalesce(v_set.element_factor_max,1.50),1+v_socket_element_damage-v_socket_element_resistance)
  );

  if v_is_hit then
    v_damage:=greatest(1,floor(
      coalesce(nullif(p_attacker->>'attack','')::numeric,1)
      *coalesce(nullif(p_attacker->>'attack_skill_multiplier','')::numeric,1)
      *v_element*v_ring_multiplier*v_socket_element_factor*(1-v_total_reduction)
    ))::integer;
    v_hp_after:=greatest(0,p_defender_hp-v_damage);
  else
    v_damage:=0;
    v_hp_after:=greatest(0,p_defender_hp);
  end if;

  -- SQL244 R2: PostgreSQL 单个函数调用最多 100 个参数。
  -- 原 SQL243 R4 把 50+ 对键值一次传给 jsonb_build_object，运行时触发 54023。
  -- 拆成两个 JSONB 对象后用 || 合并；字段名、字段值和战斗公式保持不变。
  return jsonb_build_object(
    'round',p_round,
    'sequence',p_sequence,
    'attacker_id',p_attacker->>'character_id',
    'attacker_name',p_attacker->>'name',
    'defender_id',p_defender->>'character_id',
    'defender_name',p_defender->>'name',
    'weapon_name',p_attacker->>'weapon_name',
    'weapon_kind',p_attacker->>'weapon_kind',
    'is_unarmed',coalesce(nullif(p_attacker->>'is_unarmed','')::boolean,false),
    'attack_technique_name',p_attacker->>'attack_technique_name',
    'armor_name',p_defender->>'armor_name',
    'is_naked',coalesce(nullif(p_defender->>'is_naked','')::boolean,false),
    'defense_technique_name',p_defender->>'defense_technique_name',
    'attack_style',1+floor(random()*5)::integer,
    'defense_style',1+floor(random()*5)::integer,
    'is_hit',v_is_hit,
    'hit',v_is_hit,
    'missed',not v_is_hit,
    'hit_roll',round(v_roll,8),
    'hit_chance',round(v_hit_chance,8),
    'final_hit_rate',round(v_hit_chance,8),
    'base_hit_rate',round(v_base_hit,8),
    'attacker_hit_bonus',round(v_hit_bonus,8),
    'defender_evasion_bonus',round(v_evasion,8),
    'current_attack_element',v_attack_element,
    'element_multiplier',v_element,
    'element_relation',case when v_element>1 then 'overcome' when v_element<1 then 'restrained' else 'neutral' end,
    'defense_reduction',round(v_total_reduction,6),
    'equipment_element_bonus',v_ring_base_percent,
    'ring_base_percent',v_ring_base_percent,
    'ring_effective_percent',v_ring_effective_percent,
    'ring_multiplier',round(v_ring_multiplier,8)
  ) || jsonb_build_object(
    'socket_element_damage_bonus',round(v_socket_element_damage,8),
    'socket_element_resistance',round(v_socket_element_resistance,8),
    'socket_element_factor',round(v_socket_element_factor,8),
    'socket_system_v210',coalesce(nullif(p_attacker->>'socket_system_v210','')::boolean,false)
      or coalesce(nullif(p_defender->>'socket_system_v210','')::boolean,false),
    'talent_ring_amplification_rate',0,
    'talent_ring_amplification_multiplier',1,
    'talent_source','',
    'talent_base_stat_source',coalesce(p_attacker->>'talent_base_stat_source',''),
    'talent_base_stat_bonus',coalesce(nullif(p_attacker->>'talent_base_stat_bonus','')::numeric,0),
    'talent_base_stat_multiplier',coalesce(nullif(p_attacker->>'talent_base_stat_multiplier','')::numeric,1),
    'base_stat_talent_source',coalesce(p_attacker->>'talent_base_stat_source',''),
    'base_stat_talent_bonus',coalesce(nullif(p_attacker->>'talent_base_stat_bonus','')::numeric,0),
    'base_stat_talent_multiplier',coalesce(nullif(p_attacker->>'talent_base_stat_multiplier','')::numeric,1),
    'mutation_name',p_attacker->>'mutation_name',
    'mutation_base_stat_multiplier',coalesce(nullif(p_attacker->>'mutation_base_stat_multiplier','')::numeric,1),
    'mutation_multiplier',1,
    'sword_heart_base_stat_multiplier',coalesce(nullif(p_attacker->>'sword_heart_base_stat_multiplier','')::numeric,1),
    'sword_heart_multiplier',1,
    'damage',v_damage,
    'hp_before',p_defender_hp,
    'hp_after',v_hp_after,
    'max_hp',coalesce(nullif(p_defender->>'vitality','')::integer,p_defender_hp),
    'low_health',v_hp_after>0 and v_hp_after<=floor(coalesce(nullif(p_defender->>'vitality','')::numeric,p_defender_hp)*0.30),
    'defeated',v_hp_after<=0
  );
end
$$;


comment on function public.bcombat01_resolve_hit_v243(jsonb,jsonb,integer,integer,integer,numeric)
  is 'SQL243 R4战斗核心；SQL244 R2仅修复战报JSON超过100参数的运行时错误，公式与字段保持不变。';

-- ② 兼容仍把 PostgreSQL random()/float8 直接传入核心的旧调用点。
create or replace function public.bcombat01_resolve_hit_v243(
  p_attacker jsonb,
  p_defender jsonb,
  p_defender_hp integer,
  p_round integer,
  p_sequence integer,
  p_hit_roll double precision
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
begin
  return public.bcombat01_resolve_hit_v243(
    p_attacker,
    p_defender,
    p_defender_hp,
    p_round,
    p_sequence,
    p_hit_roll::numeric
  );
end
$$;

comment on function public.bcombat01_resolve_hit_v243(jsonb,jsonb,integer,integer,integer,double precision)
  is 'SQL244 R2兼容重载：接受random()的double precision并转入SQL243 R4 numeric核心。';

revoke all on function public.bcombat01_resolve_hit_v243(jsonb,jsonb,integer,integer,integer,double precision)
  from public,anon,authenticated;

-- ③ 修正天命榜共用五参数旧入口，避免依赖隐式类型转换。
create or replace function public.bcombat01_resolve_hit(
  p_attacker jsonb,
  p_defender jsonb,
  p_defender_hp integer,
  p_round integer,
  p_sequence integer
)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','pg_temp'
as $$
begin
  return public.bcombat01_resolve_hit_v243(
    p_attacker,
    p_defender,
    p_defender_hp,
    p_round,
    p_sequence,
    random()::numeric
  );
end
$$;

comment on function public.bcombat01_resolve_hit(jsonb,jsonb,integer,integer,integer)
  is 'SQL244 R2：天命榜旧入口显式把random()转numeric，进入SQL243 R4统一命中/闪避与孔位战斗核心。';

-- ④ 真实运行时门禁。
do $gate$
declare
  v_attacker jsonb := jsonb_build_object(
    'character_id','sql244-r2-smoke-a',
    'name','SQL244-R2-A',
    'attack',100,
    'base_attack',100,
    'defense',20,
    'vitality',1000,
    'agility',100,
    'major_order',0,
    'minor_level',0,
    'base_hit_rate',0.80,
    'hit_bonus',0.05,
    'evasion_bonus',0,
    'equipment_element_bonus',0,
    'attack_skill_multiplier',1,
    'defense_technique_reduction',0,
    'socket_system_v210',true,
    'socket_element_damage','{}'::jsonb,
    'socket_element_resistance','{}'::jsonb
  );
  v_defender jsonb := jsonb_build_object(
    'character_id','sql244-r2-smoke-b',
    'name','SQL244-R2-B',
    'attack',80,
    'base_attack',80,
    'defense',30,
    'vitality',1000,
    'agility',90,
    'major_order',0,
    'minor_level',0,
    'base_hit_rate',0.80,
    'hit_bonus',0,
    'evasion_bonus',0.05,
    'equipment_element_bonus',0,
    'attack_skill_multiplier',1,
    'defense_technique_reduction',0,
    'socket_system_v210',true,
    'socket_element_damage','{}'::jsonb,
    'socket_element_resistance','{}'::jsonb
  );
  v_numeric jsonb;
  v_double jsonb;
  v_legacy jsonb;
  v_wrapper_def text;
begin
  if to_regprocedure('public.bcombat01_resolve_hit_v243(jsonb,jsonb,integer,integer,integer,numeric)') is null then
    raise exception 'SQL244_R2_GATE_NUMERIC_CORE_MISSING';
  end if;
  if to_regprocedure('public.bcombat01_resolve_hit_v243(jsonb,jsonb,integer,integer,integer,double precision)') is null then
    raise exception 'SQL244_R2_GATE_DOUBLE_OVERLOAD_MISSING';
  end if;

  -- 真正执行 numeric 核心：会经过之前触发 54023 的战报 JSON 构造行。
  v_numeric := public.bcombat01_resolve_hit_v243(
    v_attacker,v_defender,1000,1,1,0.10::numeric
  );
  if v_numeric is null
     or not (v_numeric ? 'is_hit')
     or not (v_numeric ? 'hp_after')
     or not (v_numeric ? 'defeated')
     or not (v_numeric ? 'defender_evasion_bonus')
     or not (v_numeric ? 'socket_element_factor') then
    raise exception 'SQL244_R2_GATE_NUMERIC_RUNTIME_FAILED:%',coalesce(v_numeric::text,'null');
  end if;

  -- 精确复现最初截图的 double precision 六参数调用。
  v_double := public.bcombat01_resolve_hit_v243(
    v_attacker,v_defender,1000,1,2,0.50::double precision
  );
  if v_double is null
     or not (v_double ? 'is_hit')
     or not (v_double ? 'hp_after') then
    raise exception 'SQL244_R2_GATE_DOUBLE_RUNTIME_FAILED:%',coalesce(v_double::text,'null');
  end if;

  -- 真正执行天命榜共用五参数旧入口。
  v_legacy := public.bcombat01_resolve_hit(
    v_attacker,v_defender,1000,1,3
  );
  if v_legacy is null
     or not (v_legacy ? 'is_hit')
     or not (v_legacy ? 'hp_after') then
    raise exception 'SQL244_R2_GATE_LEGACY_RUNTIME_FAILED:%',coalesce(v_legacy::text,'null');
  end if;

  v_wrapper_def := lower(pg_get_functiondef(
    to_regprocedure('public.bcombat01_resolve_hit(jsonb,jsonb,integer,integer,integer)')
  ));
  if position('random()::numeric' in v_wrapper_def)=0 then
    raise exception 'SQL244_R2_GATE_RANDOM_CAST_MISSING';
  end if;
end
$gate$;

commit;
notify pgrst,'reload schema';

select jsonb_build_object(
  'success',true,
  'sql',244,
  'gate','SQL244_GATE_PASSED',
  'revision','R2_RUNTIME_JSON_AND_SIGNATURE_FIX',
  'cache','V2.1.1 CACHE113',
  'numeric_core_runtime_tested',true,
  'double_precision_runtime_tested',true,
  'legacy_wrapper_runtime_tested',true,
  'combat_formula_changed',false,
  'release_changed',false,
  'next_sql',245
) as sql244_gate_result;
