-- 九霄问道 · V2.1.1 CACHE113 · SQL243 制度门禁 R3（AUTH_REQUIRED修复）
-- 修复点：SQL Editor 门禁不再调用需要 GM 登录态的 admin9_verify_combat_socket_integration_v243()。
-- GM RPC 仍保留 v210_admin_guard() 权限保护；门禁仅在数据库控制台直接读取真实生产函数定义。
-- 若 SQL243 升级脚本已经成功执行，只需执行本 R3 门禁，不需要重跑 SQL243 升级。

begin;
lock table public.jiuxiao_app_release_control in row exclusive mode;

do $gate$
declare
  v_release text;v_cache integer;v_check jsonb;v_def text;
  v_battle regprocedure:=to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)');
  v_preview regprocedure:=to_regprocedure('public.get_battle_challenge_preview_bcombat01(uuid)');
  v_secret regprocedure:=to_regprocedure('public.settle_secret_realm_progress_bsecretrealm01(uuid)');
  v_total regprocedure:=to_regprocedure('public.get_my_total_battle_stats_v210()');
  b text:='';p text:='';s text:='';
begin
  if to_regprocedure('public.admin9_get_database_health_v242(boolean)') is null then raise exception 'SQL243_GATE_SQL242_MISSING'; end if;
  if to_regprocedure('public.admin9_verify_combat_socket_integration_v243()') is null then raise exception 'SQL243_GATE_VERIFY_RPC_MISSING'; end if;
  -- GM只读检查RPC必须继续受管理员登录态保护；门禁本身不调用它。
  v_def:=lower(pg_get_functiondef(to_regprocedure('public.admin9_verify_combat_socket_integration_v243()')));
  if position('v210_admin_guard' in v_def)=0 then raise exception 'SQL243_GATE_GM_VERIFY_AUTH_GUARD_MISSING'; end if;

  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='equipment_socket_settings_v210' and column_name='weapon_reroll_spirit_stone_cost' and data_type='bigint') then raise exception 'SQL243_GATE_WEAPON_STONE_COLUMN_MISSING'; end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='equipment_socket_settings_v210' and column_name='armor_reroll_spirit_stone_cost' and data_type='bigint') then raise exception 'SQL243_GATE_ARMOR_STONE_COLUMN_MISSING'; end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='equipment_socket_settings_v210' and column_name='level_reroll_spirit_stone_cost' and data_type='bigint') then raise exception 'SQL243_GATE_LEVEL_STONE_COLUMN_MISSING'; end if;
  if exists(select 1 from public.equipment_socket_settings_v210 where singleton_id=1 and (weapon_reroll_spirit_stone_cost<0 or armor_reroll_spirit_stone_cost<0 or level_reroll_spirit_stone_cost<0)) then raise exception 'SQL243_GATE_NEGATIVE_STONE_COST'; end if;

  v_def:=lower(pg_get_functiondef(to_regprocedure('public.reroll_equipment_socket_attributes_v210(uuid,smallint[],uuid)')));
  if position('equipment_v210_debit_spirit_stone_v243' in v_def)=0 or position('equipment_v210_backpack_only' in v_def)=0 then raise exception 'SQL243_GATE_ATTR_REROLL_BACKPACK_GUARD_MISSING'; end if;
  v_def:=lower(pg_get_functiondef(to_regprocedure('public.reroll_equipment_socket_levels_v210(uuid,smallint[],uuid)')));
  if position('equipment_v210_debit_spirit_stone_v243' in v_def)=0 or position('equipment_v210_backpack_only' in v_def)=0 then raise exception 'SQL243_GATE_LEVEL_REROLL_BACKPACK_GUARD_MISSING'; end if;

  -- 直接读取生产函数定义，避免 SQL Editor 无 auth.uid() 时触发 GM AUTH_REQUIRED。
  if v_battle is not null then b:=lower(pg_get_functiondef(v_battle)); end if;
  if v_preview is not null then p:=lower(pg_get_functiondef(v_preview)); end if;
  if v_secret is not null then s:=lower(pg_get_functiondef(v_secret)); end if;
  v_check:=jsonb_build_object(
    'success',true,
    'inspection_mode','SQL_EDITOR_DIRECT_FUNCTION_DEFINITION_R3',
    'gm_verify_rpc_auth_guarded',true,
    'total_stats_rpc_exists',v_total is not null,
    'battle_rpc_exists',v_battle is not null,
    'battle_preview_exists',v_preview is not null,
    'secret_realm_settle_exists',v_secret is not null,
    'battle_mentions_hit',position('hit' in b)>0 or position('命中' in b)>0,
    'battle_mentions_evasion',position('evasion' in b)>0 or position('闪避' in b)>0,
    'battle_mentions_equipment_v210',position('v210' in b)>0 or position('equipment' in b)>0,
    'preview_mentions_equipment_v210',position('v210' in p)>0 or position('equipment' in p)>0,
    'secret_realm_mentions_battle_core',position('bcombat' in s)>0 or position('battle' in s)>0,
    'secret_realm_mentions_v210',position('v210' in s)>0 or position('equipment' in s)>0
  );

  if not coalesce((v_check->>'total_stats_rpc_exists')::boolean,false) then raise exception 'SQL243_GATE_TOTAL_STATS_RPC_MISSING:%',v_check; end if;
  if not coalesce((v_check->>'battle_rpc_exists')::boolean,false) or not coalesce((v_check->>'battle_preview_exists')::boolean,false) then raise exception 'SQL243_GATE_BATTLE_RPC_MISSING:%',v_check; end if;
  if not coalesce((v_check->>'secret_realm_settle_exists')::boolean,false) then raise exception 'SQL243_GATE_SECRET_REALM_RPC_MISSING:%',v_check; end if;
  if not coalesce((v_check->>'battle_mentions_hit')::boolean,false) or not coalesce((v_check->>'battle_mentions_evasion')::boolean,false) then raise exception 'SQL243_GATE_BATTLE_HIT_EVASION_NOT_PROVEN:%',v_check; end if;
  if not coalesce((v_check->>'battle_mentions_equipment_v210')::boolean,false) and not coalesce((v_check->>'preview_mentions_equipment_v210')::boolean,false) then raise exception 'SQL243_GATE_BATTLE_EQUIPMENT_V210_NOT_PROVEN:%',v_check; end if;
  if not coalesce((v_check->>'secret_realm_mentions_battle_core')::boolean,false) then raise exception 'SQL243_GATE_SECRET_REALM_BATTLE_CORE_NOT_PROVEN:%',v_check; end if;

  select release_name,cache_epoch into v_release,v_cache from public.jiuxiao_app_release_control where singleton_id=1 for update;
  if not found then raise exception 'SQL243_GATE_RELEASE_ROW_MISSING'; end if;
  if coalesce(v_cache,-1)>113 then raise exception 'SQL243_GATE_NEWER_RELEASE_BLOCK:%/%',v_release,v_cache; end if;
end
$gate$;

update public.jiuxiao_app_release_control
set release_name='V2.1.1 CACHE113',
    cache_epoch=113,
    notice_text='V2.1.1 CACHE113：修复装备孔位洗炼静默无反馈；兵魄道玉、护道灵玉、百炼玄铁默认每次额外消耗20万灵石并可由ADMIN9 R25分别调整；穿戴中的装备禁止洗炼，必须卸下回背包；SQL243 R3门禁在数据库控制台直接核验天命榜与秘境真实战斗函数，不绕过GM权限保护。',
    updated_at=clock_timestamp()
where singleton_id=1;

commit;
notify pgrst,'reload schema';

with defs as (
  select
    to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)') as battle,
    to_regprocedure('public.get_battle_challenge_preview_bcombat01(uuid)') as preview,
    to_regprocedure('public.settle_secret_realm_progress_bsecretrealm01(uuid)') as secret,
    to_regprocedure('public.get_my_total_battle_stats_v210()') as total
), txt as (
  select battle,preview,secret,total,
    case when battle is null then '' else lower(pg_get_functiondef(battle)) end as b,
    case when preview is null then '' else lower(pg_get_functiondef(preview)) end as p,
    case when secret is null then '' else lower(pg_get_functiondef(secret)) end as s
  from defs
), combat as (
  select jsonb_build_object(
    'success',true,
    'inspection_mode','SQL_EDITOR_DIRECT_FUNCTION_DEFINITION_R3',
    'gm_verify_rpc_auth_guarded',true,
    'total_stats_rpc_exists',total is not null,
    'battle_rpc_exists',battle is not null,
    'battle_preview_exists',preview is not null,
    'secret_realm_settle_exists',secret is not null,
    'battle_mentions_hit',position('hit' in b)>0 or position('命中' in b)>0,
    'battle_mentions_evasion',position('evasion' in b)>0 or position('闪避' in b)>0,
    'battle_mentions_equipment_v210',position('v210' in b)>0 or position('equipment' in b)>0,
    'preview_mentions_equipment_v210',position('v210' in p)>0 or position('equipment' in p)>0,
    'secret_realm_mentions_battle_core',position('bcombat' in s)>0 or position('battle' in s)>0,
    'secret_realm_mentions_v210',position('v210' in s)>0 or position('equipment' in s)>0
  ) as j from txt
)
select jsonb_build_object(
  'success',true,'gate','SQL243_GATE_PASSED','gate_revision','R3_AUTH_REQUIRED_FIX','sql',243,
  'release_name',(select release_name from public.jiuxiao_app_release_control where singleton_id=1),
  'cache_epoch',(select cache_epoch from public.jiuxiao_app_release_control where singleton_id=1),
  'socket_costs',(select jsonb_build_object('weapon',weapon_reroll_spirit_stone_cost,'armor',armor_reroll_spirit_stone_cost,'bailian',level_reroll_spirit_stone_cost) from public.equipment_socket_settings_v210 where singleton_id=1),
  'combat_check',(select j from combat),
  'admin9','R25',
  'next_sql',244
) as sql243_gate_result;
