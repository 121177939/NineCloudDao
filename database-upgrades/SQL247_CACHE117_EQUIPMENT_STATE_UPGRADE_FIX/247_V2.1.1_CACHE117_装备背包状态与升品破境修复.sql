-- 九霄问道 · SQL247 R2 · V2.1.1 CACHE117
-- 装备背包状态确认 + 造化升品玉/乾坤破境石运行时修复
-- R2：修复 R1 门禁误把函数体注释中的旧字段名当成真实代码引用。
--
-- 修复点：
-- 1) 新增 get_equipment_forge_item_state_v247：淬炼/升品/破境前实时读取该装备在数据库中的 location/is_locked，
--    客户端不再只依赖并行缓存中的旧 location。
-- 2) upgrade_equipment_grade_v210 / upgrade_equipment_realm_v210 不再直接引用
--    equipment_grade_config_bequipment01.ring_element_multiplier / main_stat_multiplier。
--    生产库当前 rowtype 不存在 ring_element_multiplier，旧RPC成功判定后会报 record has no field。
-- 3) 升品/破境成功后的基础主属性统一调用既有权威 public.bequipment01_value(template_id, grade_code) 计算，
--    与正常装备生成/秘境装备生成使用同一条数值链，避免品级表结构变化后RPC再次失配。
-- 4) 仍保持：仅背包装备可操作、锁定装备不可操作、材料先扣后随机但任何异常由同一事务自动回滚。
--
-- 前提：SQL246 已安装。若尚未执行 SQL246，请先执行 SQL246，再执行本文件。

begin;

-- ---------- 前置检查 ----------
do $precheck$
begin
  if to_regprocedure('public.equipment_v210_roll_level_except_v246(smallint)') is null
     or to_regprocedure('public.reroll_equipment_socket_attributes_v210(uuid,smallint[],uuid)') is null
     or to_regprocedure('public.reroll_equipment_socket_levels_v210(uuid,smallint[],uuid)') is null then
    raise exception 'SQL247_REQUIRES_SQL246_FIRST';
  end if;

  if not exists (
    select 1
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public' and p.proname='bequipment01_value'
  ) then
    raise exception 'SQL247_CANONICAL_EQUIPMENT_VALUE_FUNCTION_MISSING';
  end if;

  if to_regprocedure('public.upgrade_equipment_grade_v210(uuid,uuid)') is null
     or to_regprocedure('public.upgrade_equipment_realm_v210(uuid,uuid)') is null
     or to_regclass('public.character_equipment_items_bequipment01') is null then
    raise exception 'SQL247_EQUIPMENT_BASELINE_MISSING';
  end if;
end
$precheck$;

-- ---------- 实时装备位置状态：供 CACHE117 客户端在每次操作前二次确认 ----------
create or replace function public.get_equipment_forge_item_state_v247(p_item_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_char uuid:=public.equipment_v210_active_character_id();
  v_item public.character_equipment_items_bequipment01%rowtype;
begin
  select * into v_item
  from public.character_equipment_items_bequipment01
  where id=p_item_id and character_id=v_char;

  if v_item.id is null then raise exception 'EQUIPMENT_ITEM_NOT_FOUND'; end if;

  -- 这里只返回操作资格所需的最小权威字段，避免与装备详情结构耦合。
  return jsonb_build_object(
    'id',v_item.id,
    'location',v_item.location,
    'is_locked',v_item.is_locked
  );
end
$$;

revoke all on function public.get_equipment_forge_item_state_v247(uuid) from public,anon;
grant execute on function public.get_equipment_forge_item_state_v247(uuid) to authenticated;
comment on function public.get_equipment_forge_item_state_v247(uuid) is
'SQL247/CACHE117：装备淬炼、升品、破境前读取数据库实时location/is_locked等状态，防止客户端并行缓存旧location误判。';

-- ---------- 造化升品玉：改为统一装备数值函数 ----------
create or replace function public.upgrade_equipment_grade_v210(p_item_id uuid, p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_char uuid:=public.equipment_v210_active_character_id();
  v_item public.character_equipment_items_bequipment01%rowtype;
  v_template public.equipment_templates_bequipment01%rowtype;
  v_grade public.equipment_grade_config_bequipment01%rowtype;
  v_settings public.equipment_upgrade_settings_v210%rowtype;
  v_existing jsonb;v_result jsonb;v_next text;v_roll numeric;v_success boolean;v_base numeric;v_after bigint;v_state jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED';end if;
  select result into v_existing from public.equipment_v210_request_ledger
    where request_id=p_request_id and user_id=auth.uid();
  if v_existing is not null then return v_existing||jsonb_build_object('duplicate_request',true);end if;

  perform pg_advisory_xact_lock(hashtextextended('v210-grade:'||p_request_id::text,21003));
  select * into v_item from public.character_equipment_items_bequipment01
    where id=p_item_id and character_id=v_char for update;
  if v_item.id is null then raise exception 'EQUIPMENT_ITEM_NOT_FOUND';end if;
  if v_item.location<>'backpack' then raise exception 'EQUIPMENT_V210_BACKPACK_ONLY';end if;
  if v_item.is_locked then raise exception 'EQUIPMENT_V210_LOCKED';end if;

  v_next:=case v_item.grade_code
    when 'yellow' then 'mystic'
    when 'mystic' then 'earth'
    when 'earth' then 'heaven'
    when 'heaven' then 'immortal'
    else null end;
  if v_next is null then raise exception 'EQUIPMENT_V210_GRADE_MAX';end if;

  select * into v_settings from public.equipment_upgrade_settings_v210 where singleton_id=1;
  if not v_settings.enabled then raise exception 'EQUIPMENT_V210_UPGRADE_DISABLED';end if;

  v_after:=public.equipment_v210_debit_item(v_char,v_settings.grade_item_code,v_settings.grade_item_cost);
  v_roll:=random();
  v_success:=v_roll<v_settings.grade_success_rate;

  if v_success then
    select * into v_template from public.equipment_templates_bequipment01 where id=v_item.template_id;
    select * into v_grade from public.equipment_grade_config_bequipment01 where grade_code=v_next;
    if v_template.id is null or v_grade.grade_code is null then raise exception 'EQUIPMENT_CONFIG_MISSING';end if;

    -- 关键修复：不再访问不存在的 v_grade.ring_element_multiplier。
    -- 使用正常装备生成一直在使用的权威数值函数，根据模板 + 目标品级得到基础主属性。
    v_base:=public.bequipment01_value(v_template.id,v_next);
    if v_base is null then raise exception 'EQUIPMENT_V210_TEMPLATE_BASE_MISSING';end if;

    update public.character_equipment_items_bequipment01
      set grade_code=v_next,base_main_stat_value=v_base,updated_at=clock_timestamp()
      where id=v_item.id;
    v_state:=public.equipment_v210_recompute_item(v_item.id);
  end if;

  v_result:=jsonb_build_object(
    'success',true,'upgrade_success',v_success,'item_id',v_item.id,
    'previous_grade',v_item.grade_code,'target_grade',v_next,
    'success_rate',v_settings.grade_success_rate,'success_percent',round(v_settings.grade_success_rate*100,2),
    'random_roll',v_roll,'material_code',v_settings.grade_item_code,'material_after',v_after,
    'value_source','bequipment01_value','item',v_state
  );
  insert into public.equipment_v210_request_ledger(request_id,user_id,character_id,operation,result)
    values(p_request_id,auth.uid(),v_char,'upgrade_grade',v_result);
  return v_result;
end
$$;

revoke all on function public.upgrade_equipment_grade_v210(uuid,uuid) from public,anon;
grant execute on function public.upgrade_equipment_grade_v210(uuid,uuid) to authenticated;
comment on function public.upgrade_equipment_grade_v210(uuid,uuid) is
'SQL247：造化升品玉修复；成功时通过bequipment01_value(template_id,target_grade)统一计算基础属性，不再直接读取品级表已不存在的ring_element_multiplier。';

-- ---------- 乾坤破境石：改为统一装备数值函数 ----------
create or replace function public.upgrade_equipment_realm_v210(p_item_id uuid, p_request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_char uuid:=public.equipment_v210_active_character_id();v_char_major integer;
  v_item public.character_equipment_items_bequipment01%rowtype;
  v_template public.equipment_templates_bequipment01%rowtype;
  v_next_template public.equipment_templates_bequipment01%rowtype;
  v_grade public.equipment_grade_config_bequipment01%rowtype;
  v_settings public.equipment_upgrade_settings_v210%rowtype;
  v_existing jsonb;v_result jsonb;v_target_major integer;v_roll numeric;v_success boolean;v_base numeric;v_after bigint;v_state jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED';end if;
  select result into v_existing from public.equipment_v210_request_ledger
    where request_id=p_request_id and user_id=auth.uid();
  if v_existing is not null then return v_existing||jsonb_build_object('duplicate_request',true);end if;

  perform pg_advisory_xact_lock(hashtextextended('v210-realm:'||p_request_id::text,21004));
  select * into v_item from public.character_equipment_items_bequipment01
    where id=p_item_id and character_id=v_char for update;
  if v_item.id is null then raise exception 'EQUIPMENT_ITEM_NOT_FOUND';end if;
  if v_item.location<>'backpack' then raise exception 'EQUIPMENT_V210_BACKPACK_ONLY';end if;
  if v_item.is_locked then raise exception 'EQUIPMENT_V210_LOCKED';end if;

  select * into v_template from public.equipment_templates_bequipment01 where id=v_item.template_id;
  if v_template.id is null then raise exception 'EQUIPMENT_CONFIG_MISSING'; end if;
  v_target_major:=v_template.major_order+1;

  select r.major_order into v_char_major
  from public.player_characters pc
  join public.realm_stages rs on rs.id=pc.realm_stage_id
  join public.realms r on r.id=rs.realm_id
  where pc.id=v_char;
  if v_target_major>coalesce(v_char_major,-1) then raise exception 'EQUIPMENT_V210_REALM_EXCEEDS_CHARACTER';end if;

  select * into v_next_template from public.equipment_templates_bequipment01 t
  where t.major_order=v_target_major
    and t.slot_code=v_template.slot_code
    and (v_template.slot_code<>'weapon' or t.weapon_kind=v_template.weapon_kind)
  order by t.id limit 1;
  if v_next_template.id is null then raise exception 'EQUIPMENT_V210_NEXT_REALM_TEMPLATE_MISSING';end if;

  select * into v_settings from public.equipment_upgrade_settings_v210 where singleton_id=1;
  if not v_settings.enabled then raise exception 'EQUIPMENT_V210_UPGRADE_DISABLED';end if;

  v_after:=public.equipment_v210_debit_item(v_char,v_settings.realm_item_code,v_settings.realm_item_cost);
  v_roll:=random();
  v_success:=v_roll<v_settings.realm_success_rate;

  if v_success then
    select * into v_grade from public.equipment_grade_config_bequipment01 where grade_code=v_item.grade_code;
    if v_grade.grade_code is null then raise exception 'EQUIPMENT_CONFIG_MISSING'; end if;

    -- 关键修复：目标境界模板 + 当前品级交给同一权威装备数值函数。
    v_base:=public.bequipment01_value(v_next_template.id,v_item.grade_code);
    if v_base is null then raise exception 'EQUIPMENT_V210_TEMPLATE_BASE_MISSING';end if;

    update public.character_equipment_items_bequipment01
      set template_id=v_next_template.id,base_main_stat_value=v_base,updated_at=clock_timestamp()
      where id=v_item.id;
    v_state:=public.equipment_v210_recompute_item(v_item.id);
  end if;

  v_result:=jsonb_build_object(
    'success',true,'upgrade_success',v_success,'item_id',v_item.id,
    'previous_major_order',v_template.major_order,'target_major_order',v_target_major,
    'success_rate',v_settings.realm_success_rate,'success_percent',round(v_settings.realm_success_rate*100,2),
    'random_roll',v_roll,'material_code',v_settings.realm_item_code,'material_after',v_after,
    'value_source','bequipment01_value','item',v_state
  );
  insert into public.equipment_v210_request_ledger(request_id,user_id,character_id,operation,result)
    values(p_request_id,auth.uid(),v_char,'upgrade_realm',v_result);
  return v_result;
end
$$;

revoke all on function public.upgrade_equipment_realm_v210(uuid,uuid) from public,anon;
grant execute on function public.upgrade_equipment_realm_v210(uuid,uuid) to authenticated;
comment on function public.upgrade_equipment_realm_v210(uuid,uuid) is
'SQL247：乾坤破境石修复；成功时通过bequipment01_value(next_template,current_grade)统一计算基础属性，不再直接读取品级表已不存在的ring_element_multiplier。';

-- ---------- R2 静态门禁：先剥离函数体注释，再检查真实可执行代码 ----------
-- R1 的误报原因：pg_get_functiondef() 会返回 PL/pgSQL 函数体中的 -- 注释，
-- 新函数注释为了说明修复原因提到了旧字段名，导致门禁把“注释文字”误当成“真实字段调用”。
do $gate$
declare
  v_grade_def text;
  v_realm_def text;
  v_guard_def text;
  v_grade_code text;
  v_realm_code text;
  v_guard_code text;
begin
  if to_regprocedure('public.get_equipment_forge_item_state_v247(uuid)') is null then
    raise exception 'SQL247_GATE_FORGE_ITEM_STATE_RPC_MISSING';
  end if;

  v_grade_def:=lower(pg_get_functiondef(to_regprocedure('public.upgrade_equipment_grade_v210(uuid,uuid)')));
  v_realm_def:=lower(pg_get_functiondef(to_regprocedure('public.upgrade_equipment_realm_v210(uuid,uuid)')));
  v_guard_def:=lower(pg_get_functiondef(to_regprocedure('public.get_equipment_forge_item_state_v247(uuid)')));

  -- 去掉函数体中的单行 SQL 注释，再压缩空白；门禁只检查真实代码。
  v_grade_code:=regexp_replace(
    regexp_replace(v_grade_def, E'--[^\\n\\r]*', '', 'g'),
    '[[:space:]]+', '', 'g'
  );
  v_realm_code:=regexp_replace(
    regexp_replace(v_realm_def, E'--[^\\n\\r]*', '', 'g'),
    '[[:space:]]+', '', 'g'
  );
  v_guard_code:=regexp_replace(
    regexp_replace(v_guard_def, E'--[^\\n\\r]*', '', 'g'),
    '[[:space:]]+', '', 'g'
  );

  if position('v_base:=public.bequipment01_value(' in v_grade_code)=0
     or position('v_grade.ring_element_multiplier' in v_grade_code)>0 then
    raise exception 'SQL247_GATE_GRADE_VALUE_CHAIN_NOT_FIXED';
  end if;

  if position('v_base:=public.bequipment01_value(' in v_realm_code)=0
     or position('v_grade.ring_element_multiplier' in v_realm_code)>0 then
    raise exception 'SQL247_GATE_REALM_VALUE_CHAIN_NOT_FIXED';
  end if;

  if position('''location'',v_item.location' in v_guard_code)=0
     or position('''is_locked'',v_item.is_locked' in v_guard_code)=0 then
    raise exception 'SQL247_GATE_REALTIME_LOCATION_GUARD_NOT_PROVEN';
  end if;
end
$gate$;

commit;
notify pgrst,'reload schema';

select jsonb_build_object(
  'success',true,
  'sql',247,
  'gate','SQL247_GATE_PASSED',
  'revision','R2_GATE_COMMENT_FALSE_POSITIVE_FIX',
  'client','V2.1.1 CACHE117',
  'forge_location_guard','DATABASE_REALTIME_V247',
  'grade_upgrade_value_source','bequipment01_value',
  'realm_upgrade_value_source','bequipment01_value',
  'ring_element_multiplier_direct_reference_removed',true,
  'gate_checks_executable_code_only',true,
  'player_data_changed',false,
  'release_changed',false,
  'next_sql',248
) as sql247_gate_result;
