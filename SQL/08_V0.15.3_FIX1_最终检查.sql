-- 九霄问道 V0.15.3 FIX1 CACHE21 检查
with checks as (
  select 'equipped_slot_constraint_accepts_ordinary_1'::text as item,
         pg_get_constraintdef(oid) like '%ordinary_1%' as ok
  from pg_constraint
  where conrelid='public.character_techniques'::regclass
    and conname='character_techniques_equipped_slot_check'
  union all
  select 'slot_rpc_writes_ordinary_slots',
         position('ordinary_' in pg_get_functiondef('public.set_technique_slot_v2(uuid,text)'::regprocedure))>0
  union all
  select 'slot_rpc_no_new_slot_type_value',
         position('slot_type=null' in replace(pg_get_functiondef('public.set_technique_slot_v2(uuid,text)'::regprocedure),' ',''))>0
  union all
  select 'technique_system_uses_five_slots',
         position('open_ordinary_slots' in pg_get_functiondef('public.get_technique_system_v2()'::regprocedure))>0
  union all
  select 'grade_rule_has_yellow_fallback',
         position('else ''yellow''' in pg_get_functiondef('public.technique_grade_rules_v0152(text)'::regprocedure))>0
)
select * from checks order by item;
