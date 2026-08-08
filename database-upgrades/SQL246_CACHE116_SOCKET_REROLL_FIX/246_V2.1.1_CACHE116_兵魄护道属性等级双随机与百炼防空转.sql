-- 九霄问道 · SQL246 · V2.1.1 CACHE116
-- 装备孔位付费洗炼规则修复：
-- 1) 兵魄道玉/护道灵玉：未锁孔同时重新随机“属性类型 + 等级”；锁孔属性与等级都保护。
-- 2) 百炼玄铁：未锁且已有属性孔只重新随机等级；属性不变；空孔不参与。
-- 3) 有其它可用等级时，付费重炼优先排除原等级，避免百炼Lv10后再次原样Lv10造成“扣费无变化”。
-- 4) 兵魄/护道优先排除原属性+元素组合；若受属性池/上限约束没有其它合法属性，则允许属性相同，但等级仍重新随机。
-- 5) 若最终整次操作没有任何孔位发生实际变化，抛错并回滚整个事务：材料、锁玉、灵石都不会扣除。
-- 6) 保留：仅背包装备、最多锁3孔、GM灵石成本、百炼总开关、战斗属性重算。
-- 前提：SQL245 R2 已安装（若未安装，本SQL会在任何改动前明确拒绝）。

begin;

-- ---------- 前置检查 ----------
do $precheck$
begin
  if to_regprocedure('public.enforce_newborn_five_element_mixed_root_v245()') is null
     or to_regprocedure('public.admin9_game_reset_v245(text,bigint,text,uuid)') is null then
    raise exception 'SQL246_REQUIRES_SQL245_R2_FIRST';
  end if;
  if to_regclass('public.equipment_socket_settings_v210') is null
     or to_regclass('public.equipment_socket_level_config_v210') is null
     or to_regclass('public.equipment_socket_attribute_pool_v210') is null
     or to_regclass('public.equipment_socket_affixes_v210') is null
     or to_regclass('public.character_equipment_items_bequipment01') is null then
    raise exception 'SQL246_EQUIPMENT_V210_TABLES_MISSING';
  end if;
  if to_regprocedure('public.equipment_v210_roll_level()') is null
     or to_regprocedure('public.equipment_v210_weighted_pool_pick(uuid,text,text)') is null
     or to_regprocedure('public.equipment_v210_attribute_total(uuid,text,text)') is null
     or to_regprocedure('public.equipment_v210_recompute_item(uuid)') is null
     or to_regprocedure('public.equipment_v210_debit_item(uuid,text,bigint)') is null
     or to_regprocedure('public.equipment_v210_debit_spirit_stone_v243(uuid,bigint)') is null then
    raise exception 'SQL246_EQUIPMENT_V210_HELPERS_MISSING';
  end if;
  if to_regprocedure('public.reroll_equipment_socket_attributes_v210(uuid,smallint[],uuid)') is null
     or to_regprocedure('public.reroll_equipment_socket_levels_v210(uuid,smallint[],uuid)') is null then
    raise exception 'SQL246_REROLL_RPC_MISSING';
  end if;
end
$precheck$;

-- ---------- 等级随机：有其它可用等级时排除当前等级 ----------
create or replace function public.equipment_v210_roll_level_except_v246(p_old_level smallint)
returns smallint
language plpgsql
security definer
set search_path=''
as $$
declare v_level smallint;
begin
  select c.level into v_level
  from public.equipment_socket_level_config_v210 c
  where c.enabled and c.roll_weight>0
    and (p_old_level is null or c.level<>p_old_level)
  order by (-ln(greatest(random(),0.0000000001))/c.roll_weight) asc
  limit 1;

  -- 若GM把等级池配置到只剩一个可用等级，仍保留原始随机函数作为兼容回退。
  if v_level is null then
    v_level:=public.equipment_v210_roll_level();
  end if;
  if v_level is null then raise exception 'EQUIPMENT_V210_NO_SOCKET_LEVEL_CONFIG'; end if;
  return v_level;
end
$$;

revoke all on function public.equipment_v210_roll_level_except_v246(smallint) from public,anon,authenticated;
comment on function public.equipment_v210_roll_level_except_v246(smallint) is
'SQL246：付费孔位重炼等级辅助函数；存在其它可用等级时排除原等级，避免扣费后等级原样不变。';

-- ---------- 属性随机：优先排除原属性+元素组合，同时完整保留原池上限规则 ----------
create or replace function public.equipment_v210_weighted_pool_pick_except_v246(
  p_item_id uuid,
  p_slot_code text,
  p_weapon_element text,
  p_old_attribute_code text,
  p_old_element_code text
)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_settings public.equipment_socket_settings_v210%rowtype;
  v_row record;
  v_count integer;
  v_total numeric;
  v_effective_element text;
begin
  select * into v_settings from public.equipment_socket_settings_v210 where singleton_id=1;

  for v_row in
    select p.* from public.equipment_socket_attribute_pool_v210 p
    where p.slot_code=p_slot_code and p.enabled and p.roll_weight>0
    order by (-ln(greatest(random(),0.0000000001))/p.roll_weight) asc
  loop
    v_effective_element:=case
      when p_slot_code='weapon' and v_row.attribute_code='element_damage'
        then coalesce(nullif(p_weapon_element,''),'')
      else v_row.element_code
    end;

    -- 有其它合法候选时，优先不回到原属性/原元素组合。
    if p_old_attribute_code is not null
       and v_row.attribute_code=p_old_attribute_code
       and coalesce(v_effective_element,'')=coalesce(p_old_element_code,'') then
      continue;
    end if;

    select count(*) into v_count
    from public.equipment_socket_affixes_v210 a
    where a.equipment_item_id=p_item_id and a.attribute_code=v_row.attribute_code
      and (v_row.attribute_code not in ('element_damage','element_resist') or a.element_code=v_effective_element);
    if v_count>=v_settings.same_attribute_max then continue; end if;

    v_total:=public.equipment_v210_attribute_total(p_item_id,v_row.attribute_code,v_effective_element);
    if v_row.attribute_code in ('attack_pct','defense_pct','vitality_pct','agility_pct') and v_total>=v_settings.main_percent_cap then continue; end if;
    if v_row.attribute_code in ('attack_flat','defense_flat','vitality_flat','agility_flat') and v_total>=v_settings.main_flat_ratio_cap then continue; end if;
    if v_row.attribute_code='hit' and v_total>=v_settings.hit_bonus_cap then continue; end if;
    if v_row.attribute_code='evasion' and v_total>=v_settings.evasion_bonus_cap then continue; end if;
    if v_row.attribute_code='element_damage' and v_total>=v_settings.element_damage_equipment_cap then continue; end if;
    if v_row.attribute_code='element_resist' and v_total>=v_settings.single_resist_cap then continue; end if;

    return jsonb_build_object('attribute_code',v_row.attribute_code,'element_code',v_effective_element);
  end loop;

  -- 若受当前装备属性上限/同属性上限限制，没有其它合法属性，则回退原权威随机池。
  return public.equipment_v210_weighted_pool_pick(p_item_id,p_slot_code,p_weapon_element);
end
$$;

revoke all on function public.equipment_v210_weighted_pool_pick_except_v246(uuid,text,text,text,text) from public,anon,authenticated;
comment on function public.equipment_v210_weighted_pool_pick_except_v246(uuid,text,text,text,text) is
'SQL246：兵魄/护道属性随机辅助函数；优先排除原属性+元素组合，完整保留same_attribute_max及属性上限规则。';

-- ---------- 兵魄/护道：属性 + 等级同时重随机 ----------
create or replace function public.reroll_equipment_socket_attributes_v210(p_item_id uuid,p_locked_positions smallint[],p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  v_char uuid:=public.equipment_v210_active_character_id();
  v_item public.character_equipment_items_bequipment01%rowtype;
  v_template public.equipment_templates_bequipment01%rowtype;
  v_settings public.equipment_socket_settings_v210%rowtype;
  v_existing jsonb;v_result jsonb;v_material text;v_lock_count integer:=0;v_idx integer;
  v_old_attribute text;v_old_element text;v_old_level smallint;v_new_level smallint;v_pick jsonb;
  v_weapon_element text:='';v_after bigint;v_lock_after bigint;v_stone_after bigint;v_stone_cost bigint;v_sockets jsonb;
  v_elements text[]:=array['metal','wood','water','fire','earth'];
  v_changed_count integer:=0;v_target_count integer:=0;
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

  v_target_count:=least(v_item.opened_sockets,8)-v_lock_count;
  if v_target_count<=0 then raise exception 'EQUIPMENT_V210_ALL_SOCKETS_LOCKED'; end if;

  -- 所有扣除与后续写入处于同一事务；任何异常/无变化都会整体回滚。
  v_after:=public.equipment_v210_debit_item(v_char,v_material,v_settings.reroll_item_cost);
  v_lock_after:=public.equipment_v210_debit_item(v_char,v_settings.lock_item_code,v_lock_count*v_settings.lock_item_cost_per_socket);
  v_stone_after:=public.equipment_v210_debit_spirit_stone_v243(v_char,v_stone_cost);

  if v_template.slot_code='weapon' then
    select a.element_code into v_weapon_element from public.equipment_socket_affixes_v210 a
      where a.equipment_item_id=v_item.id and a.attribute_code='element_damage'
        and a.socket_index=any(coalesce(p_locked_positions,array[]::smallint[])) limit 1;
    if coalesce(v_weapon_element,'')='' then v_weapon_element:=v_elements[1+floor(random()*5)::int]; end if;
  end if;

  for v_idx in 1..least(v_item.opened_sockets,8) loop
    if v_idx=any(coalesce(p_locked_positions,array[]::smallint[])) then continue; end if;

    v_old_attribute:=null;v_old_element:=null;v_old_level:=null;
    select a.attribute_code,a.element_code,a.level
      into v_old_attribute,v_old_element,v_old_level
    from public.equipment_socket_affixes_v210 a
    where a.equipment_item_id=v_item.id and a.socket_index=v_idx;

    delete from public.equipment_socket_affixes_v210
    where equipment_item_id=v_item.id and socket_index=v_idx;

    -- SQL246核心：无论原孔是否已有属性，兵魄/护道都重新抽等级；不再保留v_old_level。
    v_new_level:=public.equipment_v210_roll_level_except_v246(v_old_level);
    v_pick:=public.equipment_v210_weighted_pool_pick_except_v246(
      v_item.id,v_template.slot_code,v_weapon_element,v_old_attribute,v_old_element
    );
    if coalesce(v_pick->>'attribute_code','')='' then raise exception 'EQUIPMENT_V210_ATTRIBUTE_POOL_EMPTY:%',v_template.slot_code; end if;

    insert into public.equipment_socket_affixes_v210(equipment_item_id,socket_index,attribute_code,element_code,level)
    values(v_item.id,v_idx,v_pick->>'attribute_code',coalesce(v_pick->>'element_code',''),v_new_level);

    if v_old_attribute is null
       or v_old_attribute is distinct from (v_pick->>'attribute_code')
       or coalesce(v_old_element,'') is distinct from coalesce(v_pick->>'element_code','')
       or v_old_level is distinct from v_new_level then
      v_changed_count:=v_changed_count+1;
    end if;
  end loop;

  if v_changed_count<=0 then
    raise exception 'EQUIPMENT_V210_REROLL_NO_EFFECT_ROLLBACK';
  end if;

  perform public.equipment_v210_recompute_item(v_item.id);
  select coalesce(jsonb_agg(public.equipment_v210_affix_display(v_item.id,a.socket_index) order by a.socket_index),'[]'::jsonb)
    into v_sockets from public.equipment_socket_affixes_v210 a where a.equipment_item_id=v_item.id;

  v_result:=jsonb_build_object(
    'success',true,'duplicate_request',false,'item_id',v_item.id,'item_location',v_item.location,
    'material_code',v_material,'material_after',v_after,
    'locked_count',v_lock_count,'lock_item_after',v_lock_after,
    'spirit_stone_cost',v_stone_cost,'spirit_stones_after',v_stone_after,
    'rerolled_socket_count',v_target_count,'changed_socket_count',v_changed_count,
    'attribute_rerolled',true,'level_rerolled',true,
    'lock_rule','MAX3_ATTR_AND_LEVEL_PROTECTED','rule','UNLOCKED_ATTRIBUTE_AND_LEVEL_REROLL_V246',
    'combat_recompute',true,'sockets',v_sockets
  );
  insert into public.equipment_v210_request_ledger(request_id,user_id,character_id,operation,result)
  values(p_request_id,auth.uid(),v_char,'reroll_attributes_and_levels_sql246',v_result);
  return v_result;
end
$$;

comment on function public.reroll_equipment_socket_attributes_v210(uuid,smallint[],uuid) is
'SQL246 / CACHE116：兵魄/护道对全部未锁开放孔同时随机属性+等级；锁孔双保护；无实际变化整事务回滚；材料/锁玉/灵石原子扣除。';
revoke all on function public.reroll_equipment_socket_attributes_v210(uuid,smallint[],uuid) from public,anon;
grant execute on function public.reroll_equipment_socket_attributes_v210(uuid,smallint[],uuid) to authenticated;

-- ---------- 百炼：只重随机等级，并避免付费后整次等级原样不变 ----------
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
    select a.socket_index,a.level as old_level from public.equipment_socket_affixes_v210 a
    where a.equipment_item_id=v_item.id and a.socket_index between 1 and least(v_item.opened_sockets,8)
      and not (a.socket_index=any(coalesce(p_locked_positions,array[]::smallint[])))
    order by a.socket_index for update
  loop
    v_new:=public.equipment_v210_roll_level_except_v246(v_row.old_level);
    update public.equipment_socket_affixes_v210 set level=v_new,updated_at=clock_timestamp()
      where equipment_item_id=v_item.id and socket_index=v_row.socket_index;
    if v_new is distinct from v_row.old_level then v_changed_count:=v_changed_count+1; end if;
  end loop;

  -- 若GM把等级池配置到无法产生任何新等级，整次回滚，不产生付费空转。
  if v_changed_count<=0 then
    raise exception 'EQUIPMENT_V210_LEVEL_REROLL_NO_CHANGE_ROLLBACK';
  end if;

  perform public.equipment_v210_recompute_item(v_item.id);
  select coalesce(jsonb_agg(public.equipment_v210_affix_display(v_item.id,a.socket_index) order by a.socket_index),'[]'::jsonb)
    into v_sockets from public.equipment_socket_affixes_v210 a where a.equipment_item_id=v_item.id;

  v_result:=jsonb_build_object(
    'success',true,'duplicate_request',false,'item_id',v_item.id,'item_location',v_item.location,
    'material_code',v_settings.level_reroll_item_code,'material_after',v_after,
    'locked_count',v_lock_count,'lock_item_after',v_lock_after,
    'spirit_stone_cost',v_stone_cost,'spirit_stones_after',v_stone_after,
    'rerolled_socket_count',v_target_count,'changed_socket_count',v_changed_count,
    'attribute_rerolled',false,'level_rerolled',true,
    'combat_recompute',true,'rule','ALL_UNLOCKED_FILLED_SOCKET_LEVELS_REROLL_NO_PAID_NOOP_V246','sockets',v_sockets
  );
  insert into public.equipment_v210_request_ledger(request_id,user_id,character_id,operation,result)
  values(p_request_id,auth.uid(),v_char,'reroll_levels_sql246_no_paid_noop',v_result);
  return v_result;
end
$$;

comment on function public.reroll_equipment_socket_levels_v210(uuid,smallint[],uuid) is
'SQL246 / CACHE116：百炼只随机未锁且已有属性孔等级，属性不变；有其它可用等级时排除原等级；整次无变化则回滚全部消耗。';
revoke all on function public.reroll_equipment_socket_levels_v210(uuid,smallint[],uuid) from public,anon;
grant execute on function public.reroll_equipment_socket_levels_v210(uuid,smallint[],uuid) to authenticated;

-- 旧单孔入口仍统一转入整装百炼规则。
comment on function public.reroll_equipment_socket_level_v210(uuid,smallint,uuid) is
'SQL246兼容：旧单孔入口继续转入reroll_equipment_socket_levels_v210整装百炼；百炼只变等级。';

-- ---------- 静态 + 无玩家资产运行门禁 ----------
do $gate$
declare
  v_attr text;
  v_level text;
  v_old smallint;
  v_new smallint;
  v_trials integer;
  v_tested integer:=0;
begin
  if to_regprocedure('public.equipment_v210_roll_level_except_v246(smallint)') is null
     or to_regprocedure('public.equipment_v210_weighted_pool_pick_except_v246(uuid,text,text,text,text)') is null then
    raise exception 'SQL246_GATE_HELPERS_MISSING';
  end if;

  v_attr:=lower(pg_get_functiondef(to_regprocedure('public.reroll_equipment_socket_attributes_v210(uuid,smallint[],uuid)')));
  v_level:=lower(pg_get_functiondef(to_regprocedure('public.reroll_equipment_socket_levels_v210(uuid,smallint[],uuid)')));

  if position('equipment_v210_roll_level_except_v246(v_old_level)' in v_attr)=0
     or position('equipment_v210_weighted_pool_pick_except_v246' in v_attr)=0
     or position('attribute_rerolled' in v_attr)=0
     or position('level_rerolled' in v_attr)=0
     or position('reroll_no_effect_rollback' in v_attr)=0 then
    raise exception 'SQL246_GATE_ATTR_AND_LEVEL_RULE_NOT_PROVEN';
  end if;

  if position('equipment_v210_roll_level_except_v246(v_row.old_level)' in v_level)=0
     or position('level_reroll_no_change_rollback' in v_level)=0
     or position('attribute_rerolled' in v_level)=0 then
    raise exception 'SQL246_GATE_BAILIAN_RULE_NOT_PROVEN';
  end if;

  -- 不接触玩家装备，只对等级辅助函数做真实随机运行测试。
  for v_old in
    select c.level from public.equipment_socket_level_config_v210 c
    where c.enabled and c.roll_weight>0
      and exists(select 1 from public.equipment_socket_level_config_v210 x where x.enabled and x.roll_weight>0 and x.level<>c.level)
    order by c.level
  loop
    v_tested:=v_tested+1;
    for v_trials in 1..5 loop
      v_new:=public.equipment_v210_roll_level_except_v246(v_old);
      if v_new=v_old then raise exception 'SQL246_GATE_LEVEL_EXCLUSION_FAILED:%',v_old; end if;
    end loop;
  end loop;

  if v_tested=0 then
    raise exception 'SQL246_GATE_LEVEL_CONFIG_HAS_NO_ALTERNATIVE_LEVEL';
  end if;
end
$gate$;

commit;
notify pgrst,'reload schema';

select jsonb_build_object(
  'success',true,
  'sql',246,
  'gate','SQL246_GATE_PASSED',
  'revision','R1_SOCKET_ATTRIBUTE_LEVEL_REROLL_FIX',
  'client','V2.1.1 CACHE116',
  'weapon_guardian_rule','UNLOCKED_ATTRIBUTE_AND_LEVEL_REROLL',
  'bailian_rule','UNLOCKED_FILLED_LEVEL_ONLY_REROLL',
  'paid_noop_rollback',true,
  'locked_socket_rule','ATTRIBUTE_AND_LEVEL_BOTH_PROTECTED',
  'spirit_stone_cost_rule','UNCHANGED_GM_CONFIG',
  'release_changed',false,
  'next_sql',247
) as sql246_gate_result;
