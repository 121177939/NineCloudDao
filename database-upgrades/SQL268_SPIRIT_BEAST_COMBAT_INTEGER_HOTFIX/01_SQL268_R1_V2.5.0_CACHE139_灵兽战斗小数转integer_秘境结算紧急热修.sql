-- 九霄问道 SQL268 R1 HOTFIX
-- V2.5.0 CACHE139 / SQL267 ONLINE / ADMIN9 R41
-- 修复：灵兽百分比战斗加成把顶层战斗属性变成小数，
--      旧秘境/B-COMBAT 某些路径仍用 ::integer 读取，导致：
--      invalid input syntax for type integer: "5893.5555"
--
-- 修复原则：
-- 1) 不降低/删除灵兽加成；
-- 2) 灵兽百分比仍保留 6 位精度在 spirit_beast_v267 元数据中；
-- 3) 只把送给旧战斗引擎的顶层 attack/defense/vitality/agility 规范为整数；
-- 4) 修复当前正在运行/结算中的秘境 battle_snapshot，避免玩家丢失本轮所得；
-- 5) 不动玩家修为、秘境奖励、灵兽成长、背包、装备；
-- 6) 事务化，Gate 失败则整体回滚。
--
-- NEXT SQL: SQL269

begin;

-- ============================================================
-- PRECHECK
-- ============================================================
do $precheck$
begin
  if to_regprocedure('public.spirit_beast_apply_snapshot_v267(jsonb,uuid)') is null then
    raise exception 'SQL268_PRECHECK_SPIRIT_BEAST_APPLY_SNAPSHOT_MISSING';
  end if;

  if to_regprocedure('public.spirit_beast_combat_modifier_v267(uuid)') is null then
    raise exception 'SQL268_PRECHECK_SPIRIT_BEAST_MODIFIER_MISSING';
  end if;

  if to_regclass('public.secret_realm_runs_bsecretrealm01') is null then
    raise exception 'SQL268_PRECHECK_SECRET_REALM_RUNS_MISSING';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema='public'
      and table_name='secret_realm_runs_bsecretrealm01'
      and column_name='battle_snapshot'
  ) then
    raise exception 'SQL268_PRECHECK_SECRET_REALM_BATTLE_SNAPSHOT_MISSING';
  end if;
end
$precheck$;

-- ============================================================
-- 通用安全取整：兼容旧战斗引擎 integer ABI
-- ============================================================
create or replace function public.combat_stat_integer_v268(p_value text)
returns integer
language plpgsql
immutable
set search_path=''
as $body$
declare
  v numeric;
begin
  if p_value is null or btrim(p_value)='' then
    return null;
  end if;

  begin
    v := p_value::numeric;
  exception when others then
    return null;
  end;

  if v::text in ('NaN','Infinity','-Infinity') then
    return null;
  end if;

  -- 旧战斗 ABI 使用 PostgreSQL integer，显式限制范围。
  return least(
    2147483647::numeric,
    greatest(0::numeric, round(v))
  )::integer;
end
$body$;

create or replace function public.combat_snapshot_integerize_v268(p_snapshot jsonb)
returns jsonb
language plpgsql
immutable
set search_path=''
as $body$
declare
  v jsonb := coalesce(p_snapshot,'{}'::jsonb);
  x integer;
begin
  x := public.combat_stat_integer_v268(v->>'attack');
  if x is not null then
    v := jsonb_set(v,'{attack}',to_jsonb(x),true);
  end if;

  x := public.combat_stat_integer_v268(v->>'defense');
  if x is not null then
    v := jsonb_set(v,'{defense}',to_jsonb(x),true);
  end if;

  x := public.combat_stat_integer_v268(v->>'vitality');
  if x is not null then
    v := jsonb_set(v,'{vitality}',to_jsonb(x),true);
  end if;

  x := public.combat_stat_integer_v268(v->>'agility');
  if x is not null then
    v := jsonb_set(v,'{agility}',to_jsonb(x),true);
  end if;

  return v;
end
$body$;

revoke all on function public.combat_stat_integer_v268(text)
from public, anon, authenticated;

revoke all on function public.combat_snapshot_integerize_v268(jsonb)
from public, anon, authenticated;

-- ============================================================
-- 根修 SQL267 的灵兽战斗快照适配层
-- ============================================================
create or replace function public.spirit_beast_apply_snapshot_v267(
  p_snapshot jsonb,
  p_character uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $body$
declare
  v jsonb := coalesce(p_snapshot,'{}'::jsonb);
  v_char uuid := p_character;
  m jsonb;
  v_at numeric;
  v_df numeric;
  v_hp numeric;
  v_ag numeric;
begin
  -- SQL267 旧快照可能已经带 applied=true，但四项属性仍是小数。
  -- SQL268 必须先兼容性取整，而不是原样 return。
  if coalesce((v->>'spirit_beast_v267_applied')::boolean,false) then
    return public.combat_snapshot_integerize_v268(v);
  end if;

  if v_char is null then
    begin
      v_char := (v->>'character_id')::uuid;
    exception when others then
      v_char := null;
    end;
  end if;

  -- 即使没有灵兽，也统一满足旧战斗 integer ABI。
  if v_char is null then
    return public.combat_snapshot_integerize_v268(v);
  end if;

  m := public.spirit_beast_combat_modifier_v267(v_char);

  if m='{}'::jsonb then
    return public.combat_snapshot_integerize_v268(v);
  end if;

  v_at := coalesce(nullif(v->>'attack','')::numeric,0)
          * (1 + coalesce((m->>'attack_pct')::numeric,0));
  v_df := coalesce(nullif(v->>'defense','')::numeric,0)
          * (1 + coalesce((m->>'defense_pct')::numeric,0));
  v_hp := coalesce(nullif(v->>'vitality','')::numeric,0)
          * (1 + coalesce((m->>'vitality_pct')::numeric,0));
  v_ag := coalesce(nullif(v->>'agility','')::numeric,0)
          * (1 + coalesce((m->>'agility_pct')::numeric,0));

  -- 灵兽 modifier 本身仍完整保留在 spirit_beast_v267 中；
  -- 顶层四项只为兼容旧战斗 ABI 显式变成整数。
  v := v || jsonb_build_object(
    'attack',    least(2147483647::numeric,greatest(0::numeric,round(v_at)))::integer,
    'defense',   least(2147483647::numeric,greatest(0::numeric,round(v_df)))::integer,
    'vitality',  least(2147483647::numeric,greatest(0::numeric,round(v_hp)))::integer,
    'agility',   least(2147483647::numeric,greatest(0::numeric,round(v_ag)))::integer,
    'spirit_beast_v267_applied', true,
    'spirit_beast_v267', m
  );

  return v;
end
$body$;

revoke all on function public.spirit_beast_apply_snapshot_v267(jsonb,uuid)
from public, anon, authenticated;

-- ============================================================
-- 修复当前已经进入秘境的旧 SQL267 小数快照
-- 不碰 completed/claimed 历史，减少数据库重写和膨胀。
-- ============================================================
update public.secret_realm_runs_bsecretrealm01
set
  battle_snapshot = public.combat_snapshot_integerize_v268(battle_snapshot),
  updated_at = clock_timestamp()
where battle_snapshot is not null
  and status in ('running','settling')
  and (
       coalesce(battle_snapshot->>'attack','') ~ '^-?[0-9]+[.][0-9]+$'
    or coalesce(battle_snapshot->>'defense','') ~ '^-?[0-9]+[.][0-9]+$'
    or coalesce(battle_snapshot->>'vitality','') ~ '^-?[0-9]+[.][0-9]+$'
    or coalesce(battle_snapshot->>'agility','') ~ '^-?[0-9]+[.][0-9]+$'
  );

-- 世界BOSS ready 快照也使用同一 SQL267 适配层。
-- 仅在表/列存在时修正当前保存的快照，避免同类故障。
do $repair_world_boss$
begin
  if to_regclass('public.world_boss_party_members_bwboss01') is not null
     and exists (
       select 1
       from information_schema.columns
       where table_schema='public'
         and table_name='world_boss_party_members_bwboss01'
         and column_name='battle_snapshot'
     ) then
    execute $q$
      update public.world_boss_party_members_bwboss01
      set battle_snapshot=public.combat_snapshot_integerize_v268(battle_snapshot),
          updated_at=clock_timestamp()
      where battle_snapshot is not null
        and (
             coalesce(battle_snapshot->>'attack','') ~ '^-?[0-9]+[.][0-9]+$'
          or coalesce(battle_snapshot->>'defense','') ~ '^-?[0-9]+[.][0-9]+$'
          or coalesce(battle_snapshot->>'vitality','') ~ '^-?[0-9]+[.][0-9]+$'
          or coalesce(battle_snapshot->>'agility','') ~ '^-?[0-9]+[.][0-9]+$'
        )
    $q$;
  end if;
end
$repair_world_boss$;

-- ============================================================
-- GATE
-- ============================================================
do $gate$
declare
  v_test jsonb;
  v_bad bigint;
  v_def text;
begin
  -- 复现用户实际报错形态：5893.5555 必须变成 JSON integer 5894。
  v_test := public.combat_snapshot_integerize_v268(
    '{"attack":5893.5555,"defense":1234.4000,"vitality":9876.5000,"agility":777.1000}'::jsonb
  );

  if v_test->>'attack' <> '5894'
     or v_test->>'defense' <> '1234'
     or v_test->>'vitality' <> '9877'
     or v_test->>'agility' <> '777' then
    raise exception 'SQL268_GATE_INTEGERIZE_FAILED:%', v_test;
  end if;

  select pg_get_functiondef(
    'public.spirit_beast_apply_snapshot_v267(jsonb,uuid)'::regprocedure
  ) into v_def;

  if position('combat_snapshot_integerize_v268' in v_def)=0
     or position('::integer' in v_def)=0 then
    raise exception 'SQL268_GATE_SPIRIT_BEAST_WRAPPER_NOT_PATCHED';
  end if;

  select count(*)
  into v_bad
  from public.secret_realm_runs_bsecretrealm01
  where battle_snapshot is not null
    and status in ('running','settling')
    and (
         coalesce(battle_snapshot->>'attack','') ~ '^-?[0-9]+[.][0-9]+$'
      or coalesce(battle_snapshot->>'defense','') ~ '^-?[0-9]+[.][0-9]+$'
      or coalesce(battle_snapshot->>'vitality','') ~ '^-?[0-9]+[.][0-9]+$'
      or coalesce(battle_snapshot->>'agility','') ~ '^-?[0-9]+[.][0-9]+$'
    );

  if v_bad <> 0 then
    raise exception 'SQL268_GATE_ACTIVE_SECRET_DECIMAL_SNAPSHOTS:%', v_bad;
  end if;

  raise notice 'SQL268_GATE_PASSED';
  raise notice 'SQL268 repaired spirit-beast combat snapshot integer ABI; sample 5893.5555 -> %',
    v_test->>'attack';
end
$gate$;

commit;

-- ============================================================
-- 执行后只读确认（可选）
-- ============================================================
-- 1) 查看当前秘境是否还存在小数战斗快照：
-- select
--   id,status,
--   battle_snapshot->>'attack' attack,
--   battle_snapshot->>'defense' defense,
--   battle_snapshot->>'vitality' vitality,
--   battle_snapshot->>'agility' agility
-- from public.secret_realm_runs_bsecretrealm01
-- where status in ('running','settling')
-- order by updated_at desc;
--
-- 2) 执行 SQL268 成功后，回游戏：
--    刷新状态 -> 再点“结算已到分钟”
--
-- 成功门禁：
-- SQL268_GATE_PASSED
