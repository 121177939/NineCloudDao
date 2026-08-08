-- 九霄问道 · V2.1.1 CACHE108 · SQL236
-- 百炼玄铁等级刷新 GM 总开关。
-- 默认保持开启；GM关闭后，客户端按钮禁用且服务端RPC强制拒绝，不消耗百炼玄铁。
-- 本SQL不要求SQL235已执行；只要求SQL233装备孔位体系已经存在。

begin;

lock table public.jiuxiao_app_release_control in row exclusive mode;

do $precheck$
declare v_cache integer; v_release text;
begin
  if to_regclass('public.equipment_socket_settings_v210') is null then
    raise exception 'SQL236_PRECHECK_SOCKET_SETTINGS_MISSING_SQL233_REQUIRED';
  end if;
  if to_regprocedure('public.reroll_equipment_socket_level_v210(uuid,smallint,uuid)') is null then
    raise exception 'SQL236_PRECHECK_LEVEL_REROLL_RPC_MISSING_SQL233_REQUIRED';
  end if;
  if to_regprocedure('public.admin_set_v210_core_settings(text,jsonb,text,uuid)') is null then
    raise exception 'SQL236_PRECHECK_ADMIN_SETTER_MISSING_SQL233_REQUIRED';
  end if;
  if to_regprocedure('public.admin_get_v210_equipment_boss_control()') is null then
    raise exception 'SQL236_PRECHECK_ADMIN_READER_MISSING_SQL233_REQUIRED';
  end if;
  if to_regclass('public.jiuxiao_app_release_control') is null then
    raise exception 'SQL236_PRECHECK_RELEASE_CONTROL_MISSING';
  end if;
  select release_name,cache_epoch into v_release,v_cache from public.jiuxiao_app_release_control where singleton_id=1 for update;
  if not found then raise exception 'SQL236_PRECHECK_RELEASE_ROW_MISSING'; end if;
  if coalesce(v_cache,-1)>108 then
    raise exception 'SQL236_PRECHECK_NEWER_RELEASE_BLOCK:%/%',v_release,v_cache;
  end if;
end
$precheck$;

lock table public.equipment_socket_settings_v210 in row exclusive mode;

alter table public.equipment_socket_settings_v210
  add column if not exists level_reroll_enabled boolean not null default true;

update public.equipment_socket_settings_v210
set level_reroll_enabled=coalesce(level_reroll_enabled,true),updated_at=clock_timestamp()
where singleton_id=1;

create or replace function public.reroll_equipment_socket_level_v210(p_item_id uuid,p_socket_index smallint,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.equipment_v210_active_character_id();v_item public.character_equipment_items_bequipment01%rowtype;v_settings public.equipment_socket_settings_v210%rowtype;v_affix public.equipment_socket_affixes_v210%rowtype;v_existing jsonb;v_result jsonb;v_new smallint;v_after bigint;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED';end if;
  select result into v_existing from public.equipment_v210_request_ledger where request_id=p_request_id and user_id=auth.uid();if v_existing is not null then return v_existing||jsonb_build_object('duplicate_request',true);end if;
  perform pg_advisory_xact_lock(hashtextextended('v210-reroll-level:'||p_request_id::text,21002));
  select * into v_item from public.character_equipment_items_bequipment01 where id=p_item_id and character_id=v_char for update;
  if v_item.id is null then raise exception 'EQUIPMENT_ITEM_NOT_FOUND';end if;if v_item.location<>'backpack' then raise exception 'EQUIPMENT_V210_BACKPACK_ONLY';end if;if v_item.is_locked then raise exception 'EQUIPMENT_V210_LOCKED';end if;
  select * into v_affix from public.equipment_socket_affixes_v210 where equipment_item_id=v_item.id and socket_index=p_socket_index for update;
  if v_affix.equipment_item_id is null then raise exception 'EQUIPMENT_V210_SOCKET_EMPTY';end if;
  select * into v_settings from public.equipment_socket_settings_v210 where singleton_id=1;
  if not coalesce(v_settings.level_reroll_enabled,true) then
    raise exception 'EQUIPMENT_V210_LEVEL_REROLL_DISABLED';
  end if;
  v_after:=public.equipment_v210_debit_item(v_char,v_settings.level_reroll_item_code,v_settings.level_item_cost);
  v_new:=public.equipment_v210_roll_level();
  update public.equipment_socket_affixes_v210 set level=v_new,updated_at=clock_timestamp() where equipment_item_id=v_item.id and socket_index=p_socket_index;
  perform public.equipment_v210_recompute_item(v_item.id);
  v_result:=jsonb_build_object('success',true,'item_id',v_item.id,'socket_index',p_socket_index,'previous_level',v_affix.level,'new_level',v_new,'material_code',v_settings.level_reroll_item_code,'material_after',v_after,'socket',public.equipment_v210_affix_display(v_item.id,p_socket_index));
  insert into public.equipment_v210_request_ledger(request_id,user_id,character_id,operation,result) values(p_request_id,auth.uid(),v_char,'reroll_level',v_result);
  return v_result;
end $$;

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

comment on column public.equipment_socket_settings_v210.level_reroll_enabled is 'SQL236: GM可控制百炼玄铁孔位等级随机刷新。关闭后服务端拒绝reroll_equipment_socket_level_v210且不扣材料。';
comment on function public.reroll_equipment_socket_level_v210(uuid,smallint,uuid) is 'SQL236 V2.1.1 CACHE108 BAILIAN_SWITCH1: enforce equipment_socket_settings_v210.level_reroll_enabled before material debit.';
comment on function public.admin_set_v210_core_settings(text,jsonb,text,uuid) is 'SQL236 V2.1.1 CACHE108 ADMIN9 R22: socket_settings patch supports level_reroll_enabled.';

-- 继续锁定权限边界。
revoke all on function public.reroll_equipment_socket_level_v210(uuid,smallint,uuid) from public,anon;
grant execute on function public.reroll_equipment_socket_level_v210(uuid,smallint,uuid) to authenticated;
revoke all on function public.admin_set_v210_core_settings(text,jsonb,text,uuid) from public,anon;
grant execute on function public.admin_set_v210_core_settings(text,jsonb,text,uuid) to authenticated;

commit;
notify pgrst,'reload schema';

select jsonb_build_object(
  'success',true,
  'sql',236,
  'feature','BAILIAN_LEVEL_REROLL_GM_SWITCH',
  'default_enabled',(select level_reroll_enabled from public.equipment_socket_settings_v210 where singleton_id=1),
  'release_control_unchanged',(select release_name from public.jiuxiao_app_release_control where singleton_id=1),
  'cache_epoch_unchanged',(select cache_epoch from public.jiuxiao_app_release_control where singleton_id=1),
  'next','RUN_V2.1.1_CACHE108_SQL236_GATE',
  'next_sql',237
) as sql236_install_result;
