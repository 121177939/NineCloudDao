-- 九霄问道 V0.15.4 CACHE23 回滚
-- 注意：为避免玩家已购买丹药丢失，本脚本保留丹药定义与背包数据，只撤销V0.15.4入口和结算函数。
begin;

do $$
declare r record;
begin
 if to_regclass('ncd_b_module_backup.b02_functions') is null then raise exception 'V0154_BACKUP_FUNCTIONS_NOT_FOUND';end if;
 for r in select signature,function_def from ncd_b_module_backup.b02_functions
          where signature in('public.claim_cultivation_v1()','public.get_breakthrough_status_v1()','public.attempt_breakthrough_v1()')
          order by signature loop
   execute r.function_def;
 end loop;
end$$;

drop function if exists public.attempt_breakthrough_v0154(integer,uuid);
drop function if exists public.get_breakthrough_status_v0154();
drop function if exists public.use_spirit_washing_pill_v0154(uuid);
drop function if exists public.roll_spirit_root_v0154();
drop function if exists public.use_inventory_item_quantity_v0154(uuid,integer,uuid);
drop function if exists public.upgrade_exclusive_technique_v0154(uuid,uuid);
drop function if exists public.upgrade_technique_v0154(uuid,uuid);
drop function if exists public.purchase_treasure_item_v0154(text,integer,uuid);
drop function if exists public.get_treasure_shop_v0154();
drop function if exists public.v0154_inventory_quantity(uuid,text);
drop function if exists public.v0154_item_id(text);
drop function if exists public.v0154_active_character_id();
drop function if exists public.breakthrough_clamp_fall_target_b02(smallint,smallint,smallint);
drop function if exists public.breakthrough_previous_stage_b02(smallint);
drop function if exists public.breakthrough_recovery_floor_b02(smallint);

-- 幂等记录保留用于审计，不删除玩家经济操作证据。
update public.jiuxiao_app_release_control
set notice_text='V0.15.4服务端功能已回滚；请同时回退前端部署包。',updated_at=now()
where singleton_id=1;
select pg_notify('pgrst','reload schema');
commit;
