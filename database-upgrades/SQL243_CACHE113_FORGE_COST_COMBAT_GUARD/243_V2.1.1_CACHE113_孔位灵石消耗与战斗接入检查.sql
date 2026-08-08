-- 九霄问道 · V2.1.1 CACHE113 · SQL243
-- 装备孔位洗炼可见反馈 / 兵魄护道百炼灵石成本 / 战斗接入在线检查
-- 执行顺序：SQL242升级+门禁 -> 部署CACHE113客户端与ADMIN9 R25 -> 本SQL -> SQL243门禁。
-- 默认：兵魄道玉20万灵石/次、护道灵玉20万灵石/次、百炼玄铁20万灵石/次；均可由ADMIN9 R25独立调整。

begin;

lock table public.jiuxiao_app_release_control in row exclusive mode;
lock table public.equipment_socket_settings_v210 in row exclusive mode;

do $precheck$
declare v_cache integer; v_release text;
begin
  if to_regclass('public.jiuxiao_app_release_control') is null then raise exception 'SQL243_PRECHECK_RELEASE_CONTROL_MISSING'; end if;
  if to_regclass('public.equipment_socket_settings_v210') is null
     or to_regclass('public.equipment_socket_affixes_v210') is null
     or to_regclass('public.equipment_v210_request_ledger') is null
     or to_regclass('public.character_equipment_items_bequipment01') is null then
    raise exception 'SQL243_PRECHECK_EQUIPMENT_V210_MISSING';
  end if;
  if to_regprocedure('public.admin9_get_database_health_v242(boolean)') is null then
    raise exception 'SQL243_PRECHECK_SQL242_REQUIRED_RUN_SQL242_FIRST';
  end if;
  if to_regprocedure('public.reroll_equipment_socket_attributes_v210(uuid,smallint[],uuid)') is null
     or to_regprocedure('public.reroll_equipment_socket_levels_v210(uuid,smallint[],uuid)') is null
     or to_regprocedure('public.equipment_v210_debit_item(uuid,text,bigint)') is null
     or to_regprocedure('public.equipment_v210_recompute_item(uuid)') is null then
    raise exception 'SQL243_PRECHECK_SQL239_EQUIPMENT_RPC_MISSING';
  end if;
  if to_regprocedure('public.get_spirit_stone_balance_v0141()') is null then
    raise exception 'SQL243_PRECHECK_SPIRIT_STONE_BALANCE_RPC_MISSING';
  end if;
  select release_name,cache_epoch into v_release,v_cache from public.jiuxiao_app_release_control where singleton_id=1 for update;
  if not found then raise exception 'SQL243_PRECHECK_RELEASE_ROW_MISSING'; end if;
  if coalesce(v_cache,-1)>113 then raise exception 'SQL243_PRECHECK_NEWER_RELEASE_BLOCK:%/%',v_release,v_cache; end if;
end
$precheck$;

alter table public.equipment_socket_settings_v210
  add column if not exists weapon_reroll_spirit_stone_cost bigint not null default 200000,
  add column if not exists armor_reroll_spirit_stone_cost bigint not null default 200000,
  add column if not exists level_reroll_spirit_stone_cost bigint not null default 200000;

update public.equipment_socket_settings_v210
set weapon_reroll_spirit_stone_cost=coalesce(weapon_reroll_spirit_stone_cost,200000),
    armor_reroll_spirit_stone_cost=coalesce(armor_reroll_spirit_stone_cost,200000),
    level_reroll_spirit_stone_cost=coalesce(level_reroll_spirit_stone_cost,200000),
    updated_at=clock_timestamp()
where singleton_id=1;

do $constraints$
begin
  if not exists(select 1 from pg_constraint where conname='equipment_socket_settings_v210_weapon_stone_nonnegative') then
    alter table public.equipment_socket_settings_v210 add constraint equipment_socket_settings_v210_weapon_stone_nonnegative check (weapon_reroll_spirit_stone_cost>=0);
  end if;
  if not exists(select 1 from pg_constraint where conname='equipment_socket_settings_v210_armor_stone_nonnegative') then
    alter table public.equipment_socket_settings_v210 add constraint equipment_socket_settings_v210_armor_stone_nonnegative check (armor_reroll_spirit_stone_cost>=0);
  end if;
  if not exists(select 1 from pg_constraint where conname='equipment_socket_settings_v210_level_stone_nonnegative') then
    alter table public.equipment_socket_settings_v210 add constraint equipment_socket_settings_v210_level_stone_nonnegative check (level_reroll_spirit_stone_cost>=0);
  end if;
end
$constraints$;

create or replace function public.equipment_v210_debit_spirit_stone_v243(p_character_id uuid,p_amount bigint)
returns bigint language plpgsql security definer set search_path='' as $$
declare v_after bigint;
begin
  if coalesce(p_amount,0)<=0 then
    select coalesce(public.get_spirit_stone_balance_v0141(),0)::bigint into v_after;
    return v_after;
  end if;
  begin
    v_after:=public.equipment_v210_debit_item(p_character_id,'spirit_stone',p_amount);
    return v_after;
  exception when others then
    if sqlerrm ilike '%INSUFFICIENT%' or sqlerrm ilike '%ITEM_INSUFFICIENT%' then
      raise exception 'EQUIPMENT_V210_SPIRIT_STONE_INSUFFICIENT';
    end if;
    raise;
  end;
end $$;

-- 属性洗炼：兵魄/护道。仅允许背包装备；穿戴中的装备必须先卸下。材料、锁玉、灵石在同一事务中原子扣除。
create or replace function public.reroll_equipment_socket_attributes_v210(p_item_id uuid,p_locked_positions smallint[],p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_char uuid:=public.equipment_v210_active_character_id();v_item public.character_equipment_items_bequipment01%rowtype;v_template public.equipment_templates_bequipment01%rowtype;
  v_settings public.equipment_socket_settings_v210%rowtype;v_existing jsonb;v_result jsonb;v_material text;v_lock_count integer:=0;v_idx integer;v_old_level smallint;v_pick jsonb;
  v_weapon_element text:='';v_after bigint;v_lock_after bigint;v_stone_after bigint;v_stone_cost bigint;v_sockets jsonb;v_elements text[]:=array['metal','wood','water','fire','earth'];
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
  v_stone_cost:=case when v_template.slot_code='weapon' then v_settings.weapon_reroll_spirit_stone_cost else v_settings.armor_reroll_spirit_stone_cost end;
  select count(distinct x) into v_lock_count from unnest(coalesce(p_locked_positions,array[]::smallint[])) x;
  if v_lock_count>3 then raise exception 'EQUIPMENT_V210_LOCK_LIMIT_EXCEEDED'; end if;
  if exists(select 1 from unnest(coalesce(p_locked_positions,array[]::smallint[])) x where x<1 or x>v_item.opened_sockets) then raise exception 'EQUIPMENT_V210_LOCK_POSITION_INVALID'; end if;
  if exists(select 1 from unnest(coalesce(p_locked_positions,array[]::smallint[])) x where not exists(select 1 from public.equipment_socket_affixes_v210 a where a.equipment_item_id=v_item.id and a.socket_index=x)) then raise exception 'EQUIPMENT_V210_EMPTY_SOCKET_CANNOT_LOCK'; end if;
  if v_lock_count>=v_item.opened_sockets then raise exception 'EQUIPMENT_V210_ALL_SOCKETS_LOCKED'; end if;

  v_after:=public.equipment_v210_debit_item(v_char,v_material,v_settings.reroll_item_cost);
  v_lock_after:=public.equipment_v210_debit_item(v_char,v_settings.lock_item_code,v_lock_count*v_settings.lock_item_cost_per_socket);
  v_stone_after:=public.equipment_v210_debit_spirit_stone_v243(v_char,v_stone_cost);

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
    if coalesce(v_pick->>'attribute_code','')='' then raise exception 'EQUIPMENT_V210_ATTRIBUTE_POOL_EMPTY:%',v_template.slot_code; end if;
    insert into public.equipment_socket_affixes_v210(equipment_item_id,socket_index,attribute_code,element_code,level)
    values(v_item.id,v_idx,v_pick->>'attribute_code',coalesce(v_pick->>'element_code',''),v_old_level);
  end loop;

  perform public.equipment_v210_recompute_item(v_item.id);
  select coalesce(jsonb_agg(public.equipment_v210_affix_display(v_item.id,a.socket_index) order by a.socket_index),'[]'::jsonb)
    into v_sockets from public.equipment_socket_affixes_v210 a where a.equipment_item_id=v_item.id;
  v_result:=jsonb_build_object(
    'success',true,'duplicate_request',false,'item_id',v_item.id,'item_location',v_item.location,
    'material_code',v_material,'material_after',v_after,
    'locked_count',v_lock_count,'lock_item_after',v_lock_after,
    'spirit_stone_cost',v_stone_cost,'spirit_stones_after',v_stone_after,
    'lock_rule','MAX3_ATTR_AND_LEVEL_PROTECTED','combat_recompute',true,'sockets',v_sockets
  );
  insert into public.equipment_v210_request_ledger(request_id,user_id,character_id,operation,result)
  values(p_request_id,auth.uid(),v_char,'reroll_attributes_cache113_stonecost',v_result);
  return v_result;
end $$;

-- 百炼：整装未锁孔等级重炼；仅允许背包装备，穿戴中的装备必须先卸下；同时原子扣除百炼玄铁/锁玉/灵石。
create or replace function public.reroll_equipment_socket_levels_v210(p_item_id uuid,p_locked_positions smallint[],p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_char uuid:=public.equipment_v210_active_character_id();
  v_item public.character_equipment_items_bequipment01%rowtype;
  v_settings public.equipment_socket_settings_v210%rowtype;
  v_existing jsonb;v_result jsonb;v_sockets jsonb;
  v_lock_count integer:=0;v_target_count integer:=0;v_changed_count integer:=0;
  v_after bigint;v_lock_after bigint;v_stone_after bigint;v_stone_cost bigint;v_row record;v_new smallint;
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
  v_stone_cost:=v_settings.level_reroll_spirit_stone_cost;

  select count(distinct x) into v_lock_count from unnest(coalesce(p_locked_positions,array[]::smallint[])) x;
  if v_lock_count>3 then raise exception 'EQUIPMENT_V210_LOCK_LIMIT_EXCEEDED'; end if;
  if exists(select 1 from unnest(coalesce(p_locked_positions,array[]::smallint[])) x where x<1 or x>least(v_item.opened_sockets,8)) then raise exception 'EQUIPMENT_V210_LOCK_POSITION_INVALID'; end if;
  if exists(select 1 from unnest(coalesce(p_locked_positions,array[]::smallint[])) x where not exists(select 1 from public.equipment_socket_affixes_v210 a where a.equipment_item_id=v_item.id and a.socket_index=x)) then raise exception 'EQUIPMENT_V210_EMPTY_SOCKET_CANNOT_LOCK'; end if;

  select count(*) into v_target_count from public.equipment_socket_affixes_v210 a
  where a.equipment_item_id=v_item.id and a.socket_index between 1 and least(v_item.opened_sockets,8)
    and not (a.socket_index=any(coalesce(p_locked_positions,array[]::smallint[])));
  if v_target_count<=0 then raise exception 'EQUIPMENT_V210_NO_UNLOCKED_FILLED_SOCKET'; end if;

  v_after:=public.equipment_v210_debit_item(v_char,v_settings.level_reroll_item_code,v_settings.level_item_cost);
  v_lock_after:=public.equipment_v210_debit_item(v_char,v_settings.lock_item_code,v_lock_count*v_settings.lock_item_cost_per_socket);
  v_stone_after:=public.equipment_v210_debit_spirit_stone_v243(v_char,v_stone_cost);

  for v_row in
    select a.socket_index from public.equipment_socket_affixes_v210 a
    where a.equipment_item_id=v_item.id and a.socket_index between 1 and least(v_item.opened_sockets,8)
      and not (a.socket_index=any(coalesce(p_locked_positions,array[]::smallint[])))
    order by a.socket_index for update
  loop
    v_new:=public.equipment_v210_roll_level();
    update public.equipment_socket_affixes_v210 set level=v_new,updated_at=clock_timestamp()
      where equipment_item_id=v_item.id and socket_index=v_row.socket_index;
    v_changed_count:=v_changed_count+1;
  end loop;

  perform public.equipment_v210_recompute_item(v_item.id);
  select coalesce(jsonb_agg(public.equipment_v210_affix_display(v_item.id,a.socket_index) order by a.socket_index),'[]'::jsonb)
    into v_sockets from public.equipment_socket_affixes_v210 a where a.equipment_item_id=v_item.id;

  v_result:=jsonb_build_object(
    'success',true,'duplicate_request',false,'item_id',v_item.id,'item_location',v_item.location,
    'material_code',v_settings.level_reroll_item_code,'material_after',v_after,
    'locked_count',v_lock_count,'lock_item_after',v_lock_after,
    'spirit_stone_cost',v_stone_cost,'spirit_stones_after',v_stone_after,
    'rerolled_socket_count',v_changed_count,'combat_recompute',true,
    'rule','ALL_UNLOCKED_FILLED_SOCKET_LEVELS_REROLL','sockets',v_sockets
  );
  insert into public.equipment_v210_request_ledger(request_id,user_id,character_id,operation,result)
  values(p_request_id,auth.uid(),v_char,'reroll_levels_cache113_stonecost',v_result);
  return v_result;
end $$;

create or replace function public.reroll_equipment_socket_level_v210(p_item_id uuid,p_socket_index smallint,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_result jsonb;
begin
  v_result:=public.reroll_equipment_socket_levels_v210(p_item_id,array[]::smallint[],p_request_id);
  return v_result||jsonb_build_object('legacy_single_socket_rpc',true,'legacy_requested_socket',p_socket_index);
end $$;

-- ADMIN9 R25：保留原有全部区域，仅扩展socket_settings的三项灵石成本。
create or replace function public.admin_set_v210_core_settings(p_area text,p_patch jsonb,p_reason text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_before jsonb;v_after jsonb;v_code text:=coalesce(p_area,'');
begin
 perform public.v210_admin_guard();if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED';end if;if length(trim(coalesce(p_reason,'')))<2 then raise exception 'V210_ADMIN_REASON_REQUIRED';end if;
 perform pg_advisory_xact_lock(hashtextextended('v210-admin:'||p_request_id::text,21901));
 if v_code='world_boss_settings' then
   select to_jsonb(x) into v_before from public.world_boss_settings_bwboss01 x where singleton_id=1;
   update public.world_boss_settings_bwboss01 set enabled=coalesce((p_patch->>'enabled')::boolean,enabled),timezone_name=coalesce(p_patch->>'timezone_name',timezone_name),daily_start_time=coalesce((p_patch->>'daily_start_time')::time,daily_start_time),daily_duration_minutes=coalesce((p_patch->>'daily_duration_minutes')::integer,daily_duration_minutes),min_major_order=coalesce((p_patch->>'min_major_order')::integer,min_major_order),max_party_size=coalesce((p_patch->>'max_party_size')::smallint,max_party_size),global_progress_target=coalesce((p_patch->>'global_progress_target')::numeric,global_progress_target),reward_multiplier=coalesce((p_patch->>'reward_multiplier')::numeric,reward_multiplier),difficulty_multiplier=coalesce((p_patch->>'difficulty_multiplier')::numeric,difficulty_multiplier),rare_reward_win_limit=coalesce((p_patch->>'rare_reward_win_limit')::integer,rare_reward_win_limit),rare_reward_enabled=coalesce((p_patch->>'rare_reward_enabled')::boolean,rare_reward_enabled),updated_at=clock_timestamp() where singleton_id=1;
   select to_jsonb(x) into v_after from public.world_boss_settings_bwboss01 x where singleton_id=1;
 elsif v_code='socket_settings' then
   select to_jsonb(x) into v_before from public.equipment_socket_settings_v210 x where singleton_id=1;
   update public.equipment_socket_settings_v210 set
    enabled=coalesce((p_patch->>'enabled')::boolean,enabled),level_reroll_enabled=coalesce((p_patch->>'level_reroll_enabled')::boolean,level_reroll_enabled),base_hit_rate=coalesce((p_patch->>'base_hit_rate')::numeric,base_hit_rate),hit_floor=coalesce((p_patch->>'hit_floor')::numeric,hit_floor),hit_ceiling=coalesce((p_patch->>'hit_ceiling')::numeric,hit_ceiling),same_attribute_max=coalesce((p_patch->>'same_attribute_max')::smallint,same_attribute_max),
    main_percent_cap=coalesce((p_patch->>'main_percent_cap')::numeric,main_percent_cap),main_flat_ratio_cap=coalesce((p_patch->>'main_flat_ratio_cap')::numeric,main_flat_ratio_cap),hit_bonus_cap=coalesce((p_patch->>'hit_bonus_cap')::numeric,hit_bonus_cap),evasion_bonus_cap=coalesce((p_patch->>'evasion_bonus_cap')::numeric,evasion_bonus_cap),element_damage_equipment_cap=coalesce((p_patch->>'element_damage_equipment_cap')::numeric,element_damage_equipment_cap),element_damage_character_cap=coalesce((p_patch->>'element_damage_character_cap')::numeric,element_damage_character_cap),single_resist_cap=coalesce((p_patch->>'single_resist_cap')::numeric,single_resist_cap),total_resist_cap=coalesce((p_patch->>'total_resist_cap')::numeric,total_resist_cap),
    element_factor_min=coalesce((p_patch->>'element_factor_min')::numeric,element_factor_min),element_factor_max=coalesce((p_patch->>'element_factor_max')::numeric,element_factor_max),element_advantage_multiplier=coalesce((p_patch->>'element_advantage_multiplier')::numeric,element_advantage_multiplier),element_neutral_multiplier=coalesce((p_patch->>'element_neutral_multiplier')::numeric,element_neutral_multiplier),element_disadvantage_multiplier=coalesce((p_patch->>'element_disadvantage_multiplier')::numeric,element_disadvantage_multiplier),weapon_reroll_item_code=coalesce(p_patch->>'weapon_reroll_item_code',weapon_reroll_item_code),armor_reroll_item_code=coalesce(p_patch->>'armor_reroll_item_code',armor_reroll_item_code),level_reroll_item_code=coalesce(p_patch->>'level_reroll_item_code',level_reroll_item_code),lock_item_code=coalesce(p_patch->>'lock_item_code',lock_item_code),
    reroll_item_cost=coalesce((p_patch->>'reroll_item_cost')::integer,reroll_item_cost),level_item_cost=coalesce((p_patch->>'level_item_cost')::integer,level_item_cost),lock_item_cost_per_socket=coalesce((p_patch->>'lock_item_cost_per_socket')::integer,lock_item_cost_per_socket),weapon_reroll_spirit_stone_cost=coalesce((p_patch->>'weapon_reroll_spirit_stone_cost')::bigint,weapon_reroll_spirit_stone_cost),armor_reroll_spirit_stone_cost=coalesce((p_patch->>'armor_reroll_spirit_stone_cost')::bigint,armor_reroll_spirit_stone_cost),level_reroll_spirit_stone_cost=coalesce((p_patch->>'level_reroll_spirit_stone_cost')::bigint,level_reroll_spirit_stone_cost),updated_at=clock_timestamp() where singleton_id=1;
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

-- 在线检查真实生产函数定义，不凭客户端文案猜测命中/闪避/孔位是否进入天命榜和秘境。
create or replace function public.admin9_verify_combat_socket_integration_v243()
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_battle regprocedure:=to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)');
  v_preview regprocedure:=to_regprocedure('public.get_battle_challenge_preview_bcombat01(uuid)');
  v_secret regprocedure:=to_regprocedure('public.settle_secret_realm_progress_bsecretrealm01(uuid)');
  v_total regprocedure:=to_regprocedure('public.get_my_total_battle_stats_v210()');
  b text:='';p text:='';s text:='';
begin
  perform public.v210_admin_guard();
  if v_battle is not null then b:=lower(pg_get_functiondef(v_battle)); end if;
  if v_preview is not null then p:=lower(pg_get_functiondef(v_preview)); end if;
  if v_secret is not null then s:=lower(pg_get_functiondef(v_secret)); end if;
  return jsonb_build_object(
    'success',true,
    'total_stats_rpc_exists',v_total is not null,
    'battle_rpc_exists',v_battle is not null,
    'battle_preview_exists',v_preview is not null,
    'secret_realm_settle_exists',v_secret is not null,
    'battle_mentions_hit',position('hit' in b)>0 or position('命中' in b)>0,
    'battle_mentions_evasion',position('evasion' in b)>0 or position('闪避' in b)>0,
    'battle_mentions_equipment_v210',position('v210' in b)>0 or position('equipment' in b)>0,
    'preview_mentions_equipment_v210',position('v210' in p)>0 or position('equipment' in p)>0,
    'secret_realm_mentions_battle_core',position('bcombat' in s)>0 or position('battle' in s)>0,
    'secret_realm_mentions_v210',position('v210' in s)>0 or position('equipment' in s)>0,
    'note','此检查读取生产数据库真实函数定义；若任一战斗关键项为false，SQL243门禁会阻止CACHE113发布确认。'
  );
end $$;

comment on column public.equipment_socket_settings_v210.weapon_reroll_spirit_stone_cost is 'SQL243 CACHE113: 兵魄道玉每次属性洗炼额外灵石成本，默认200000，ADMIN9 R25可调。';
comment on column public.equipment_socket_settings_v210.armor_reroll_spirit_stone_cost is 'SQL243 CACHE113: 护道灵玉每次属性洗炼额外灵石成本，默认200000，ADMIN9 R25可调。';
comment on column public.equipment_socket_settings_v210.level_reroll_spirit_stone_cost is 'SQL243 CACHE113: 百炼玄铁整装等级重炼额外灵石成本，默认200000，ADMIN9 R25可调。';
comment on function public.reroll_equipment_socket_attributes_v210(uuid,smallint[],uuid) is 'SQL243 V2.1.1 CACHE113 R2: 兵魄/护道仅允许背包装备使用；穿戴中拒绝；材料+锁玉+GM配置灵石成本原子扣除；重算装备战斗值。';
comment on function public.reroll_equipment_socket_levels_v210(uuid,smallint[],uuid) is 'SQL243 V2.1.1 CACHE113 R2: 百炼整装等级重炼仅允许背包装备；穿戴中拒绝；材料+锁玉+GM配置灵石成本原子扣除；重算装备战斗值。';
comment on function public.admin_set_v210_core_settings(text,jsonb,text,uuid) is 'SQL243 V2.1.1 CACHE113 ADMIN9 R25: socket_settings新增兵魄/护道/百炼三项灵石成本。';
comment on function public.admin9_verify_combat_socket_integration_v243() is 'SQL243: ADMIN9 R25只读检查生产战力榜/秘境函数是否显式接入命中闪避与V2.1装备战斗链。';

revoke all on function public.equipment_v210_debit_spirit_stone_v243(uuid,bigint) from public,anon,authenticated;
revoke all on function public.reroll_equipment_socket_attributes_v210(uuid,smallint[],uuid) from public,anon;
grant execute on function public.reroll_equipment_socket_attributes_v210(uuid,smallint[],uuid) to authenticated;
revoke all on function public.reroll_equipment_socket_levels_v210(uuid,smallint[],uuid) from public,anon;
grant execute on function public.reroll_equipment_socket_levels_v210(uuid,smallint[],uuid) to authenticated;
revoke all on function public.reroll_equipment_socket_level_v210(uuid,smallint,uuid) from public,anon;
grant execute on function public.reroll_equipment_socket_level_v210(uuid,smallint,uuid) to authenticated;
revoke all on function public.admin_set_v210_core_settings(text,jsonb,text,uuid) from public,anon;
grant execute on function public.admin_set_v210_core_settings(text,jsonb,text,uuid) to authenticated;
revoke all on function public.admin9_verify_combat_socket_integration_v243() from public,anon;
grant execute on function public.admin9_verify_combat_socket_integration_v243() to authenticated;

commit;
notify pgrst,'reload schema';

select jsonb_build_object(
  'success',true,'sql',243,'feature','CACHE113_FORGE_STONE_COST_AND_COMBAT_INTEGRATION_GUARD',
  'weapon_reroll_stone_cost',(select weapon_reroll_spirit_stone_cost from public.equipment_socket_settings_v210 where singleton_id=1),
  'armor_reroll_stone_cost',(select armor_reroll_spirit_stone_cost from public.equipment_socket_settings_v210 where singleton_id=1),
  'level_reroll_stone_cost',(select level_reroll_spirit_stone_cost from public.equipment_socket_settings_v210 where singleton_id=1),
  'socket_reroll_location','BACKPACK_ONLY','equipped_socket_reroll',false,
  'next','DEPLOY_CACHE113_ADMIN9_R25_THEN_RUN_SQL243_GATE',
  'next_sql',244
) as sql243_install_result;
