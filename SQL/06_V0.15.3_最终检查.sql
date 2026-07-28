-- 九霄问道 V0.15.3 CACHE20 部署后检查
select * from (values
  ('release_v0153_cache20',
   coalesce((select release_name='V0.15.3 CACHE20' and cache_epoch>=20
             from public.jiuxiao_app_release_control where singleton_id=1),false),
   '发布门禁为V0.15.3 CACHE20'),
  ('technique_grade_rules',to_regprocedure('public.technique_grade_rules_v0152(text)') is not null,'功法品级规则函数存在'),
  ('technique_slot_rpc',to_regprocedure('public.set_technique_slot_v2(uuid,text)') is not null,'普通功法槽RPC存在'),
  ('exclusive_upgrade_rpc',to_regprocedure('public.upgrade_exclusive_technique_v1(uuid)') is not null,'专属功法升级RPC存在'),
  ('realm_guard_rpc',to_regprocedure('public.breakthrough_major_fall_target_v0152(uuid,smallint)') is not null,'突破历史小境界保护函数存在'),
  ('fate_status_rpc',to_regprocedure('public.get_character_fate_status_b01()') is not null,'B01命格状态RPC存在')
) x(check_name,ok,detail)
order by check_name;
