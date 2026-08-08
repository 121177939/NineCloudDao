-- 九霄问道 · V2.1.1 CACHE113 · SQL243 制度门禁
-- 必须在SQL242已通过、CACHE113网页/Android与ADMIN9 R25已部署、SQL243安装成功后执行。
-- 门禁重点：三种孔位材料灵石成本、背包专用洗炼限制、可见RPC、生产战斗函数对命中/闪避/装备V2.1链的实际引用。

begin;
lock table public.jiuxiao_app_release_control in row exclusive mode;

do $gate$
declare
  v_release text;v_cache integer;v_check jsonb;v_def text;
begin
  if to_regprocedure('public.admin9_get_database_health_v242(boolean)') is null then raise exception 'SQL243_GATE_SQL242_MISSING'; end if;
  if to_regprocedure('public.admin9_verify_combat_socket_integration_v243()') is null then raise exception 'SQL243_GATE_VERIFY_RPC_MISSING'; end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='equipment_socket_settings_v210' and column_name='weapon_reroll_spirit_stone_cost' and data_type='bigint') then raise exception 'SQL243_GATE_WEAPON_STONE_COLUMN_MISSING'; end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='equipment_socket_settings_v210' and column_name='armor_reroll_spirit_stone_cost' and data_type='bigint') then raise exception 'SQL243_GATE_ARMOR_STONE_COLUMN_MISSING'; end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='equipment_socket_settings_v210' and column_name='level_reroll_spirit_stone_cost' and data_type='bigint') then raise exception 'SQL243_GATE_LEVEL_STONE_COLUMN_MISSING'; end if;
  if exists(select 1 from public.equipment_socket_settings_v210 where singleton_id=1 and (weapon_reroll_spirit_stone_cost<0 or armor_reroll_spirit_stone_cost<0 or level_reroll_spirit_stone_cost<0)) then raise exception 'SQL243_GATE_NEGATIVE_STONE_COST'; end if;

  v_def:=pg_get_functiondef(to_regprocedure('public.reroll_equipment_socket_attributes_v210(uuid,smallint[],uuid)'));
  if position('equipment_v210_debit_spirit_stone_v243' in v_def)=0 or position('equipment_v210_backpack_only' in lower(v_def))=0 then raise exception 'SQL243_GATE_ATTR_REROLL_BACKPACK_GUARD_MISSING'; end if;
  v_def:=pg_get_functiondef(to_regprocedure('public.reroll_equipment_socket_levels_v210(uuid,smallint[],uuid)'));
  if position('equipment_v210_debit_spirit_stone_v243' in v_def)=0 or position('equipment_v210_backpack_only' in lower(v_def))=0 then raise exception 'SQL243_GATE_LEVEL_REROLL_BACKPACK_GUARD_MISSING'; end if;

  v_check:=public.admin9_verify_combat_socket_integration_v243();
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
    notice_text='V2.1.1 CACHE113：修复装备孔位洗炼静默无反馈；兵魄道玉、护道灵玉、百炼玄铁默认每次额外消耗20万灵石并可由ADMIN9 R25分别调整；穿戴中的装备禁止洗炼，必须卸下回背包；门禁核验天命榜与秘境真实战斗函数的命中/闪避和V2.1装备接入。',
    updated_at=clock_timestamp()
where singleton_id=1;

commit;
notify pgrst,'reload schema';

select jsonb_build_object(
  'success',true,'gate','SQL243_GATE_PASSED','sql',243,
  'release_name',(select release_name from public.jiuxiao_app_release_control where singleton_id=1),
  'cache_epoch',(select cache_epoch from public.jiuxiao_app_release_control where singleton_id=1),
  'socket_costs',(select jsonb_build_object('weapon',weapon_reroll_spirit_stone_cost,'armor',armor_reroll_spirit_stone_cost,'bailian',level_reroll_spirit_stone_cost) from public.equipment_socket_settings_v210 where singleton_id=1),
  'combat_check',public.admin9_verify_combat_socket_integration_v243(),
  'admin9','R25',
  'next_sql',244
) as sql243_gate_result;
