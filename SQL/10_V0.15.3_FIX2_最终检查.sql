-- 九霄问道 V0.15.3 FIX2 CACHE22 最终检查
-- 结果应全部为 true。
with defs as (
  select
    lower(regexp_replace(pg_get_functiondef('public.get_technique_system_v2()'::regprocedure), '\s+', '', 'g')) as reader_def,
    lower(regexp_replace(pg_get_functiondef('public.upgrade_technique_v2(uuid)'::regprocedure), '\s+', '', 'g')) as upgrade_def,
    lower(regexp_replace(pg_get_functiondef('public.redeem_technique_book_v0152(uuid,integer,uuid)'::regprocedure), '\s+', '', 'g')) as redeem_def
), checks as (
  select 'release_cache22'::text as item,
         coalesce((
           select release_name='V0.15.3 FIX2 CACHE22' and cache_epoch>=22
           from public.jiuxiao_app_release_control
           where singleton_id=1
         ),false) as ok,
         '发布门禁应为V0.15.3 FIX2 CACHE22'::text as detail
  union all
  select 'reader_uses_inventory_balance',
         position('public.spirit_stone_balance_v0141(c.id)' in reader_def)>0
           and position('c.spirit_stones' in reader_def)=0,
         '功法读取RPC使用统一灵石余额函数，不再读取角色表字段'
  from defs
  union all
  select 'upgrade_uses_atomic_debit',
         position('public.spirit_stone_debit_v0141(c.id,v_cost' in upgrade_def)>0
           and position('c.spirit_stones' in upgrade_def)=0
           and position('updatepublic.player_characterssetspirit_stones' in upgrade_def)=0,
         '普通功法升级使用统一原子扣款函数'
  from defs
  union all
  select 'redeem_uses_inventory_award',
         position('public.award_spirit_stones_v3(c.id,v_total)' in redeem_def)>0
           and position('public.spirit_stone_balance_v0141(c.id)' in redeem_def)>0
           and position('c.spirit_stones' in redeem_def)=0
           and position('updatepublic.player_characterssetspirit_stones' in redeem_def)=0,
         '道卷兑换使用统一灵石入账函数'
  from defs
  union all
  select 'spirit_stone_helpers_ready',
         to_regprocedure('public.spirit_stone_balance_v0141(uuid)') is not null
           and to_regprocedure('public.spirit_stone_debit_v0141(uuid,bigint,text)') is not null
           and to_regprocedure('public.award_spirit_stones_v3(uuid,bigint)') is not null,
         '灵石余额、扣款和奖励函数均存在'
  union all
  select 'five_slot_reader_still_ready',
         position('ordinary_5' in reader_def)>0
           and position('open_ordinary_slots' in reader_def)>0,
         '五槽功法读取规则未被回退'
  from defs
)
select item,ok,detail from checks order by item;
