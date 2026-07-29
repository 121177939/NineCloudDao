-- B-COMBAT01 部署后检查（只读）
select 'realm_stats_44' as check_name,
       (select count(*)=44 from public.combat_realm_stats_bcombat01) as ok,
       '凡人至飞升共44个基础阶段' as detail
union all
select 'element_profile_table',
       to_regclass('public.character_combat_profiles_bcombat01') is not null,
       '角色五行伴生表存在'
union all
select 'all_characters_have_element',
       not exists(
         select 1 from public.player_characters pc
         left join public.character_combat_profiles_bcombat01 cp on cp.character_id=pc.id
         where cp.character_id is null
       ),
       '全部存量角色均有五行'
union all
select 'element_balance',
       coalesce((
         select max(n)-min(n)<=1 from (
           select e.element,count(cp.character_id)::bigint n
           from (values('metal'::text),('wood'),('water'),('fire'),('earth')) e(element)
           left join public.character_combat_profiles_bcombat01 cp on cp.element=e.element
           group by e.element
         ) x
       ),true),
       '首次完整分配时五行数量最多相差1'
union all
select 'new_character_trigger',
       exists(select 1 from pg_trigger where tgname='trg_bcombat01_assign_element' and not tgisinternal),
       '新角色自动获得五行'
union all
select 'challenge_settings',
       exists(select 1 from public.battle_challenge_settings_bcombat01
         where singleton_id=1 and active_challenge_daily_limit=5
           and target_challenged_daily_limit=10 and pair_transfer_daily_limit=1
           and protection_minutes=30 and cultivation_loss_rate=0.01
           and sword_heart_final_damage_bonus=0.08),
       '5次主动、10次被挑战、同对手1次、保护30分钟、修为1%、剑心8%'
union all
select 'sword_heart_rule',
       exists(select 1 from public.fates where code='sword_heart'
         and description like '%剑类武器%剑系功法%8%%'
         and coalesce((modifiers->>'sword_final_damage_bonus')::numeric,0)=0.08
         and not (modifiers ? 'combat_attribute_bonus')),
       '天生剑心只保留剑类武器与剑系功法最终伤害8%'
union all
select 'ranking_rpc',
       to_regprocedure('public.get_battle_power_ranking_bcombat01(integer,integer)') is not null,
       '战力榜RPC存在'
union all
select 'preview_rpc',
       to_regprocedure('public.get_battle_challenge_preview_bcombat01(uuid)') is not null,
       '挑战预览RPC存在'
union all
select 'challenge_rpc',
       to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)') is not null,
       '挑战结算RPC存在'
union all
select 'escrow_rpc',
       to_regprocedure('public.claim_battle_cultivation_escrow_bcombat01()') is not null,
       '战利修为暂存领取RPC存在'
union all
select 'authenticated_permissions',
       has_function_privilege('authenticated','public.get_battle_power_ranking_bcombat01(integer,integer)','execute')
       and has_function_privilege('authenticated','public.get_battle_challenge_preview_bcombat01(uuid)','execute')
       and has_function_privilege('authenticated','public.challenge_battle_power_bcombat01(uuid,uuid)','execute'),
       'authenticated可调用公开RPC'
union all
select 'anon_denied',
       not has_function_privilege('anon','public.get_battle_power_ranking_bcombat01(integer,integer)','execute')
       and not has_function_privilege('anon','public.challenge_battle_power_bcombat01(uuid,uuid)','execute'),
       'anon不可读取或结算挑战'
union all
select 'cap_preserved',
       to_regprocedure('public.character_cultivation_cap_v1(smallint)') is not null
       and exists(select 1 from pg_proc where oid='public.challenge_battle_power_bcombat01(uuid,uuid)'::regprocedure
         and pg_get_functiondef(oid) like '%character_cultivation_cap_v1%'),
       '挑战奖励保留修为硬上限'
union all
select 'world_feed_reused',
       exists(select 1 from pg_proc where oid='public.challenge_battle_power_bcombat01(uuid,uuid)'::regprocedure
         and pg_get_functiondef(oid) like '%world_event_publish_v0140%'),
       '复用既有九霄界闻发布函数，不覆盖其定义';
