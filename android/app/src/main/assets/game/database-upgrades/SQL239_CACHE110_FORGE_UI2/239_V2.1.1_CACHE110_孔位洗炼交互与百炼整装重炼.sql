-- 九霄问道 · V2.1.1 CACHE110 · SQL239
-- 孔位洗炼交互与百炼整装重炼服务端升级。
-- 核心规则：
-- 1) 孔锁最多3个；锁定孔位属性类型与等级都不变化。
-- 2) 每次洗炼按锁孔数额外消耗定灵锁玉：锁1/2/3孔分别消耗1/2/3个（实际单孔成本仍由GM配置）。
-- 3) 兵魄/护道：仅刷新未锁孔属性类型；已有孔等级保持，空孔首次生成时随机等级。
-- 4) 百炼玄铁：每次消耗1次配置成本，整件装备所有“未锁且已有属性”的孔位等级全部重新随机；属性类型不变；空孔不参与。
-- 5) 百炼GM总开关继续服务端强制生效；关闭时先拒绝、后不扣材料。
-- 6) 兼容旧单孔百炼RPC：旧入口不再允许单孔规则，调用时自动执行整装等级重炼（无旧客户端锁孔上下文）。
-- 执行顺序：先部署CACHE110客户端，再执行本升级SQL，最后执行配套制度门禁SQL。

begin;

lock table public.jiuxiao_app_release_control in row exclusive mode;

do $precheck$
declare v_cache integer; v_release text;
begin
  if to_regclass('public.jiuxiao_app_release_control') is null then
    raise exception 'SQL239_PRECHECK_RELEASE_CONTROL_MISSING';
  end if;
  if to_regclass('public.equipment_socket_settings_v210') is null
     or to_regclass('public.equipment_socket_affixes_v210') is null
     or to_regclass('public.equipment_v210_request_ledger') is null
     or to_regclass('public.character_equipment_items_bequipment01') is null then
    raise exception 'SQL239_PRECHECK_EQUIPMENT_SOCKET_V210_MISSING_SQL233_REQUIRED';
  end if;
  if to_regprocedure('public.reroll_equipment_socket_attributes_v210(uuid,smallint[],uuid)') is null
     or to_regprocedure('public.reroll_equipment_socket_level_v210(uuid,smallint,uuid)') is null
     or to_regprocedure('public.equipment_v210_roll_level()') is null
     or to_regprocedure('public.equipment_v210_debit_item(uuid,text,bigint)') is null
     or to_regprocedure('public.equipment_v210_recompute_item(uuid)') is null
     or to_regprocedure('public.equipment_v210_affix_display(uuid,smallint)') is null then
    raise exception 'SQL239_PRECHECK_EQUIPMENT_RPC_MISSING_SQL233_REQUIRED';
  end if;
  if to_regprocedure('public.admin_set_v210_core_settings(text,jsonb,text,uuid)') is null then
    raise exception 'SQL239_PRECHECK_ADMIN_SETTER_MISSING_SQL233_REQUIRED';
  end if;
  if to_regprocedure('public.bwboss01_grant_token(uuid,bigint)') is null then
    raise exception 'SQL239_PRECHECK_WBOSS_BIGINT_GRANT_MISSING_SQL233_REQUIRED';
  end if;
  select release_name,cache_epoch into v_release,v_cache
  from public.jiuxiao_app_release_control where singleton_id=1 for update;
  if not found then raise exception 'SQL239_PRECHECK_RELEASE_ROW_MISSING'; end if;
  if coalesce(v_cache,-1)>110 then
    raise exception 'SQL239_PRECHECK_NEWER_RELEASE_BLOCK:%/%',v_release,v_cache;
  end if;
end
$precheck$;

lock table public.equipment_socket_settings_v210 in row exclusive mode;

-- 幂等吸收SQL236：即便此前未单独执行SQL236，CACHE110也能保留百炼GM总开关。
alter table public.equipment_socket_settings_v210
  add column if not exists level_reroll_enabled boolean not null default true;

update public.equipment_socket_settings_v210
set level_reroll_enabled=coalesce(level_reroll_enabled,true),updated_at=clock_timestamp()
where singleton_id=1;

-- 属性洗炼：新增服务端“最多锁3孔”硬限制；其余既有属性池/等级保留规则不变。
create or replace function public.reroll_equipment_socket_attributes_v210(p_item_id uuid,p_locked_positions smallint[],p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_char uuid:=public.equipment_v210_active_character_id();v_item public.character_equipment_items_bequipment01%rowtype;v_template public.equipment_templates_bequipment01%rowtype;
  v_settings public.equipment_socket_settings_v210%rowtype;v_existing jsonb;v_result jsonb;v_material text;v_lock_count integer:=0;v_idx integer;v_old_level smallint;v_pick jsonb;
  v_weapon_element text:='';v_after bigint;v_lock_after bigint;v_sockets jsonb;v_elements text[]:=array['metal','wood','water','fire','earth'];
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select result into v_existing from public.equipment_v210_request_ledger where request_id=p_request_id and user_id=auth.uid();
  if v_existing is not null then return v_existing||jsonb_build_object('duplicate_request',true); end if;
  perform pg_advisory_xact_lock(hashtextextended('v210-reroll-attr:'||p_request_id::text,21001));
  select * into v_item from public.character_equipment_items_bequipment01 where id=p_item_id and character_id=v_char for update;
  if v_item.id is null then raise exception 'EQUIPMENT_ITEM_NOT_FOUND'; end if;
  if v_item.location<>'backpack' then raise exception 'EQUIPMENT_V210_BACKPACK_ONLY'; end if;
  if v_item.is_locked then raise exception 'EQUIPMENT_V210_LOCKED'; end if;
  select * into v_template from public.equipment_templates_bequipment01 where id=v_item.template_id;
  select * into v_settings from public.equipment_socket_settings_v210 where singleton_id=1;
  if not v_settings.enabled then raise exception 'EQUIPMENT_V210_SOCKET_DISABLED'; end if;
  v_material:=case when v_template.slot_code='weapon' then v_settings.weapon_reroll_item_code else v_settings.armor_reroll_item_code end;
  select count(distinct x) into v_lock_count from unnest(coalesce(p_locked_positions,array[]::smallint[])) x;
  if v_lock_count>3 then raise exception 'EQUIPMENT_V210_LOCK_LIMIT_EXCEEDED'; end if;
  if exists(select 1 from unnest(coalesce(p_locked_positions,array[]::smallint[])) x where x<1 or x>v_item.opened_sockets) then raise exception 'EQUIPMENT_V210_LOCK_POSITION_INVALID'; end if;
  if exists(select 1 from unnest(coalesce(p_locked_positions,array[]::smallint[])) x where not exists(select 1 from public.equipment_socket_affixes_v210 a where a.equipment_item_id=v_item.id and a.socket_index=x)) then raise exception 'EQUIPMENT_V210_EMPTY_SOCKET_CANNOT_LOCK'; end if;
  if v_lock_count>=v_item.opened_sockets then raise exception 'EQUIPMENT_V210_ALL_SOCKETS_LOCKED'; end if;

  v_after:=public.equipment_v210_debit_item(v_char,v_material,v_settings.reroll_item_cost);
  v_lock_after:=public.equipment_v210_debit_item(v_char,v_settings.lock_item_code,v_lock_count*v_settings.lock_item_cost_per_socket);

  if v_template.slot_code='weapon' then
    select a.element_code into v_weapon_element from public.equipment_socket_affixes_v210 a
      where a.equipment_item_id=v_item.id and a.attribute_code='element_damage' and a.socket_index=any(coalesce(p_locked_positions,array[]::smallint[])) limit 1;
    if coalesce(v_weapon_element,'')='' then v_weapon_element:=v_elements[1+floor(random()*5)::int]; end if;
  end if;

  for v_idx in 1..least(v_item.opened_sockets,8) loop
    if v_idx=any(coalesce(p_locked_positions,array[]::smallint[])) then continue; end if;
    select level into v_old_level from public.equipment_socket_affixes_v210 where equipment_item_id=v_item.id and socket_index=v_idx;
    delete from public.equipment_socket_affixes_v210 where equipment_item_id=v_item.id and socket_index=v_idx;
    if v_old_level is null then v_old_level:=public.equipment_v210_roll_level(); end if;
    v_pick:=public.equipment_v210_weighted_pool_pick(v_item.id,v_template.slot_code,v_weapon_element);
    insert into public.equipment_socket_affixes_v210(equipment_item_id,socket_index,attribute_code,element_code,level)
    values(v_item.id,v_idx,v_pick->>'attribute_code',coalesce(v_pick->>'element_code',''),v_old_level);
  end loop;

  perform public.equipment_v210_recompute_item(v_item.id);
  select coalesce(jsonb_agg(public.equipment_v210_affix_display(v_item.id,a.socket_index) order by a.socket_index),'[]'::jsonb)
    into v_sockets from public.equipment_socket_affixes_v210 a where a.equipment_item_id=v_item.id;
  v_result:=jsonb_build_object(
    'success',true,'duplicate_request',false,'item_id',v_item.id,
    'material_code',v_material,'material_after',v_after,
    'locked_count',v_lock_count,'lock_item_after',v_lock_after,
    'lock_rule','MAX3_ATTR_AND_LEVEL_PROTECTED','sockets',v_sockets
  );
  insert into public.equipment_v210_request_ledger(request_id,user_id,character_id,operation,result)
  values(p_request_id,auth.uid(),v_char,'reroll_attributes_cache110',v_result);
  return v_result;
end $$;

-- CACHE110新百炼入口：一次重炼整件装备所有未锁且已有属性的孔位等级。
create or replace function public.reroll_equipment_socket_levels_v210(p_item_id uuid,p_locked_positions smallint[],p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_char uuid:=public.equipment_v210_active_character_id();
  v_item public.character_equipment_items_bequipment01%rowtype;
  v_settings public.equipment_socket_settings_v210%rowtype;
  v_existing jsonb;v_result jsonb;v_sockets jsonb;
  v_lock_count integer:=0;v_target_count integer:=0;v_changed_count integer:=0;
  v_after bigint;v_lock_after bigint;v_row record;v_new smallint;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  select result into v_existing from public.equipment_v210_request_ledger where request_id=p_request_id and user_id=auth.uid();
  if v_existing is not null then return v_existing||jsonb_build_object('duplicate_request',true); end if;
  perform pg_advisory_xact_lock(hashtextextended('v210-reroll-levels:'||p_request_id::text,21006));

  select * into v_item from public.character_equipment_items_bequipment01 where id=p_item_id and character_id=v_char for update;
  if v_item.id is null then raise exception 'EQUIPMENT_ITEM_NOT_FOUND'; end if;
  if v_item.location<>'backpack' then raise exception 'EQUIPMENT_V210_BACKPACK_ONLY'; end if;
  if v_item.is_locked then raise exception 'EQUIPMENT_V210_LOCKED'; end if;

  select * into v_settings from public.equipment_socket_settings_v210 where singleton_id=1;
  if not v_settings.enabled then raise exception 'EQUIPMENT_V210_SOCKET_DISABLED'; end if;
  if not coalesce(v_settings.level_reroll_enabled,true) then raise exception 'EQUIPMENT_V210_LEVEL_REROLL_DISABLED'; end if;

  select count(distinct x) into v_lock_count from unnest(coalesce(p_locked_positions,array[]::smallint[])) x;
  if v_lock_count>3 then raise exception 'EQUIPMENT_V210_LOCK_LIMIT_EXCEEDED'; end if;
  if exists(select 1 from unnest(coalesce(p_locked_positions,array[]::smallint[])) x where x<1 or x>least(v_item.opened_sockets,8)) then
    raise exception 'EQUIPMENT_V210_LOCK_POSITION_INVALID';
  end if;
  if exists(select 1 from unnest(coalesce(p_locked_positions,array[]::smallint[])) x where not exists(
    select 1 from public.equipment_socket_affixes_v210 a where a.equipment_item_id=v_item.id and a.socket_index=x
  )) then raise exception 'EQUIPMENT_V210_EMPTY_SOCKET_CANNOT_LOCK'; end if;

  select count(*) into v_target_count
  from public.equipment_socket_affixes_v210 a
  where a.equipment_item_id=v_item.id
    and a.socket_index between 1 and least(v_item.opened_sockets,8)
    and not (a.socket_index=any(coalesce(p_locked_positions,array[]::smallint[])));
  if v_target_count<=0 then raise exception 'EQUIPMENT_V210_NO_UNLOCKED_FILLED_SOCKET'; end if;

  v_after:=public.equipment_v210_debit_item(v_char,v_settings.level_reroll_item_code,v_settings.level_item_cost);
  v_lock_after:=public.equipment_v210_debit_item(v_char,v_settings.lock_item_code,v_lock_count*v_settings.lock_item_cost_per_socket);

  for v_row in
    select a.socket_index from public.equipment_socket_affixes_v210 a
    where a.equipment_item_id=v_item.id
      and a.socket_index between 1 and least(v_item.opened_sockets,8)
      and not (a.socket_index=any(coalesce(p_locked_positions,array[]::smallint[])))
    order by a.socket_index
    for update
  loop
    v_new:=public.equipment_v210_roll_level();
    update public.equipment_socket_affixes_v210
      set level=v_new,updated_at=clock_timestamp()
      where equipment_item_id=v_item.id and socket_index=v_row.socket_index;
    v_changed_count:=v_changed_count+1;
  end loop;

  perform public.equipment_v210_recompute_item(v_item.id);
  select coalesce(jsonb_agg(public.equipment_v210_affix_display(v_item.id,a.socket_index) order by a.socket_index),'[]'::jsonb)
    into v_sockets from public.equipment_socket_affixes_v210 a where a.equipment_item_id=v_item.id;

  v_result:=jsonb_build_object(
    'success',true,'duplicate_request',false,'item_id',v_item.id,
    'material_code',v_settings.level_reroll_item_code,'material_after',v_after,
    'locked_count',v_lock_count,'lock_item_after',v_lock_after,
    'rerolled_socket_count',v_changed_count,
    'rule','ALL_UNLOCKED_FILLED_SOCKET_LEVELS_REROLL','sockets',v_sockets
  );
  insert into public.equipment_v210_request_ledger(request_id,user_id,character_id,operation,result)
  values(p_request_id,auth.uid(),v_char,'reroll_levels_bulk_cache110',v_result);
  return v_result;
end $$;

-- 旧CACHE108/109单孔RPC兼容入口：不再执行单孔百炼，避免绕过新规则。
create or replace function public.reroll_equipment_socket_level_v210(p_item_id uuid,p_socket_index smallint,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb;
begin
  v_result:=public.reroll_equipment_socket_levels_v210(p_item_id,array[]::smallint[],p_request_id);
  return v_result||jsonb_build_object('legacy_single_socket_rpc',true,'legacy_requested_socket',p_socket_index);
end $$;

-- 幂等吸收SQL236的ADMIN9 R22百炼开关写入能力。
create or replace function public.admin_set_v210_core_settings(p_area text,p_patch jsonb,p_reason text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_before jsonb;v_after jsonb;v_code text:=coalesce(p_area,'');
begin
 perform public.v210_admin_guard();if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED';end if;if length(trim(coalesce(p_reason,'')))<2 then raise exception 'V210_ADMIN_REASON_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('v210-admin:'||p_request_id::text,21901));
 if v_code='world_boss_settings' then
   select to_jsonb(x) into v_before from public.world_boss_settings_bwboss01 x where singleton_id=1;
   update public.world_boss_settings_bwboss01 set
    enabled=coalesce((p_patch->>'enabled')::boolean,enabled),timezone_name=coalesce(p_patch->>'timezone_name',timezone_name),daily_start_time=coalesce((p_patch->>'daily_start_time')::time,daily_start_time),daily_duration_minutes=coalesce((p_patch->>'daily_duration_minutes')::integer,daily_duration_minutes),
    min_major_order=coalesce((p_patch->>'min_major_order')::integer,min_major_order),max_party_size=coalesce((p_patch->>'max_party_size')::smallint,max_party_size),global_progress_target=coalesce((p_patch->>'global_progress_target')::numeric,global_progress_target),
    reward_multiplier=coalesce((p_patch->>'reward_multiplier')::numeric,reward_multiplier),difficulty_multiplier=coalesce((p_patch->>'difficulty_multiplier')::numeric,difficulty_multiplier),rare_reward_win_limit=coalesce((p_patch->>'rare_reward_win_limit')::integer,rare_reward_win_limit),rare_reward_enabled=coalesce((p_patch->>'rare_reward_enabled')::boolean,rare_reward_enabled),updated_at=clock_timestamp() where singleton_id=1;
   select to_jsonb(x) into v_after from public.world_boss_settings_bwboss01 x where singleton_id=1;
 elsif v_code='socket_settings' then
   select to_jsonb(x) into v_before from public.equipment_socket_settings_v210 x where singleton_id=1;
   update public.equipment_socket_settings_v210 set
    enabled=coalesce((p_patch->>'enabled')::boolean,enabled),level_reroll_enabled=coalesce((p_patch->>'level_reroll_enabled')::boolean,level_reroll_enabled),base_hit_rate=coalesce((p_patch->>'base_hit_rate')::numeric,base_hit_rate),hit_floor=coalesce((p_patch->>'hit_floor')::numeric,hit_floor),hit_ceiling=coalesce((p_patch->>'hit_ceiling')::numeric,hit_ceiling),same_attribute_max=coalesce((p_patch->>'same_attribute_max')::smallint,same_attribute_max),
    main_percent_cap=coalesce((p_patch->>'main_percent_cap')::numeric,main_percent_cap),main_flat_ratio_cap=coalesce((p_patch->>'main_flat_ratio_cap')::numeric,main_flat_ratio_cap),hit_bonus_cap=coalesce((p_patch->>'hit_bonus_cap')::numeric,hit_bonus_cap),evasion_bonus_cap=coalesce((p_patch->>'evasion_bonus_cap')::numeric,evasion_bonus_cap),
    element_damage_equipment_cap=coalesce((p_patch->>'element_damage_equipment_cap')::numeric,element_damage_equipment_cap),element_damage_character_cap=coalesce((p_patch->>'element_damage_character_cap')::numeric,element_damage_character_cap),single_resist_cap=coalesce((p_patch->>'single_resist_cap')::numeric,single_resist_cap),total_resist_cap=coalesce((p_patch->>'total_resist_cap')::numeric,total_resist_cap),
    element_factor_min=coalesce((p_patch->>'element_factor_min')::numeric,element_factor_min),element_factor_max=coalesce((p_patch->>'element_factor_max')::numeric,element_factor_max),element_advantage_multiplier=coalesce((p_patch->>'element_advantage_multiplier')::numeric,element_advantage_multiplier),element_neutral_multiplier=coalesce((p_patch->>'element_neutral_multiplier')::numeric,element_neutral_multiplier),element_disadvantage_multiplier=coalesce((p_patch->>'element_disadvantage_multiplier')::numeric,element_disadvantage_multiplier),
    weapon_reroll_item_code=coalesce(p_patch->>'weapon_reroll_item_code',weapon_reroll_item_code),armor_reroll_item_code=coalesce(p_patch->>'armor_reroll_item_code',armor_reroll_item_code),level_reroll_item_code=coalesce(p_patch->>'level_reroll_item_code',level_reroll_item_code),lock_item_code=coalesce(p_patch->>'lock_item_code',lock_item_code),reroll_item_cost=coalesce((p_patch->>'reroll_item_cost')::integer,reroll_item_cost),level_item_cost=coalesce((p_patch->>'level_item_cost')::integer,level_item_cost),lock_item_cost_per_socket=coalesce((p_patch->>'lock_item_cost_per_socket')::integer,lock_item_cost_per_socket),updated_at=clock_timestamp() where singleton_id=1;
   select to_jsonb(x) into v_after from public.equipment_socket_settings_v210 x where singleton_id=1;
 elsif v_code='upgrade_settings' then
   select to_jsonb(x) into v_before from public.equipment_upgrade_settings_v210 x where singleton_id=1;
   update public.equipment_upgrade_settings_v210 set enabled=coalesce((p_patch->>'enabled')::boolean,enabled),grade_item_code=coalesce(p_patch->>'grade_item_code',grade_item_code),realm_item_code=coalesce(p_patch->>'realm_item_code',realm_item_code),grade_item_cost=coalesce((p_patch->>'grade_item_cost')::integer,grade_item_cost),realm_item_cost=coalesce((p_patch->>'realm_item_cost')::integer,realm_item_cost),grade_success_rate=coalesce((p_patch->>'grade_success_rate')::numeric,grade_success_rate),realm_success_rate=coalesce((p_patch->>'realm_success_rate')::numeric,realm_success_rate),updated_at=clock_timestamp() where singleton_id=1;
   select to_jsonb(x) into v_after from public.equipment_upgrade_settings_v210 x where singleton_id=1;
 elsif v_code in ('boss_normal','boss_hard','boss_phase') then
   select to_jsonb(x) into v_before from public.world_boss_definitions_bwboss01 x where code='jiuyou_devourer';
   if v_code='boss_normal' then update public.world_boss_definitions_bwboss01 set normal_config=normal_config||coalesce(p_patch,'{}'::jsonb),updated_at=clock_timestamp() where code='jiuyou_devourer';
   elsif v_code='boss_hard' then update public.world_boss_definitions_bwboss01 set hard_config=hard_config||coalesce(p_patch,'{}'::jsonb),updated_at=clock_timestamp() where code='jiuyou_devourer';
   else update public.world_boss_definitions_bwboss01 set phase_config=phase_config||coalesce(p_patch,'{}'::jsonb),updated_at=clock_timestamp() where code='jiuyou_devourer';end if;
   select to_jsonb(x) into v_after from public.world_boss_definitions_bwboss01 x where code='jiuyou_devourer';
 elsif v_code='boss_definition' then
   select to_jsonb(x) into v_before from public.world_boss_definitions_bwboss01 x where code='jiuyou_devourer';
   update public.world_boss_definitions_bwboss01 set name=coalesce(p_patch->>'name',name),element_code=coalesce(p_patch->>'element_code',element_code),enabled=coalesce((p_patch->>'enabled')::boolean,enabled),description=coalesce(p_patch->>'description',description),updated_at=clock_timestamp() where code='jiuyou_devourer';
   select to_jsonb(x) into v_after from public.world_boss_definitions_bwboss01 x where code='jiuyou_devourer';
 else raise exception 'V210_ADMIN_AREA_INVALID:%',v_code;end if;
 perform public.v210_admin_audit_write(v_code,'update',v_code,v_before,v_after,p_reason);return jsonb_build_object('success',true,'area',v_code,'after',v_after);
end $$;

-- 幂等吸收SQL237/238：保留世界BOSS镇魔令 numeric -> bigint 内部兼容入口。
create or replace function public.bwboss01_grant_token(p_character_id uuid,p_amount numeric)
returns bigint language plpgsql security definer set search_path='' as $$
declare v_amount bigint;
begin
  if p_amount is null or p_amount<=0 then return 0; end if;
  v_amount:=floor(p_amount)::bigint;
  if v_amount<=0 then return 0; end if;
  return public.bwboss01_grant_token(p_character_id,v_amount);
end $$;

comment on function public.bwboss01_grant_token(uuid,numeric) is
'SQL239 V2.1.1 CACHE110 COMPAT: retains BWBOSS numeric->bigint token grant compatibility from SQL237/238.';
revoke all on function public.bwboss01_grant_token(uuid,numeric) from public,anon,authenticated;

comment on column public.equipment_socket_settings_v210.level_reroll_enabled is
'SQL239 CACHE110: ADMIN9 R22百炼玄铁整装等级重炼总开关；关闭后服务端在扣材料前拒绝。';
comment on function public.reroll_equipment_socket_attributes_v210(uuid,smallint[],uuid) is
'SQL239 V2.1.1 CACHE110 FORGE_UI2: 属性洗炼最多锁3孔；锁孔属性与等级同时保护，并按锁孔数消耗定灵锁玉。';
comment on function public.reroll_equipment_socket_levels_v210(uuid,smallint[],uuid) is
'SQL239 V2.1.1 CACHE110 FORGE_UI2: 百炼玄铁一次重炼全部未锁且已有属性孔的等级；属性不变；最多锁3孔；空孔不参与。';
comment on function public.reroll_equipment_socket_level_v210(uuid,smallint,uuid) is
'SQL239 V2.1.1 CACHE110 LEGACY_COMPAT: 旧单孔百炼入口已改为整装等级重炼，禁止继续单孔百炼规则。';
comment on function public.admin_set_v210_core_settings(text,jsonb,text,uuid) is
'SQL239 V2.1.1 CACHE110 ADMIN9 R22 COMPAT: socket_settings继续支持level_reroll_enabled。';

revoke all on function public.reroll_equipment_socket_attributes_v210(uuid,smallint[],uuid) from public,anon;
grant execute on function public.reroll_equipment_socket_attributes_v210(uuid,smallint[],uuid) to authenticated;
revoke all on function public.reroll_equipment_socket_levels_v210(uuid,smallint[],uuid) from public,anon;
grant execute on function public.reroll_equipment_socket_levels_v210(uuid,smallint[],uuid) to authenticated;
revoke all on function public.reroll_equipment_socket_level_v210(uuid,smallint,uuid) from public,anon;
grant execute on function public.reroll_equipment_socket_level_v210(uuid,smallint,uuid) to authenticated;
revoke all on function public.admin_set_v210_core_settings(text,jsonb,text,uuid) from public,anon;
grant execute on function public.admin_set_v210_core_settings(text,jsonb,text,uuid) to authenticated;

commit;
notify pgrst,'reload schema';

select jsonb_build_object(
  'success',true,
  'sql',239,
  'feature','FORGE_UI_COMPACT_LOCK3_BULK_BAILIAN_INLINE_CLIENT',
  'bulk_bailian_rpc',to_regprocedure('public.reroll_equipment_socket_levels_v210(uuid,smallint[],uuid)') is not null,
  'boss_token_numeric_compat',to_regprocedure('public.bwboss01_grant_token(uuid,numeric)') is not null,
  'max_locked_sockets',3,
  'bailian_gm_switch',(select level_reroll_enabled from public.equipment_socket_settings_v210 where singleton_id=1),
  'release_control_unchanged',(select release_name from public.jiuxiao_app_release_control where singleton_id=1),
  'cache_epoch_unchanged',(select cache_epoch from public.jiuxiao_app_release_control where singleton_id=1),
  'next','RUN_V2.1.1_CACHE110_SQL239_GATE',
  'next_sql',240
) as sql239_install_result;
