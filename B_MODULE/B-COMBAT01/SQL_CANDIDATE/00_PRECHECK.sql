-- B-COMBAT01 候选前检（只读）
select 'baseline_release_control' as check_name,
       to_regclass('public.jiuxiao_app_release_control') is not null as ok,
       '发布控制表必须存在' as detail
union all
select 'cache_epoch_27',
       coalesce((select cache_epoch >= 27 from public.jiuxiao_app_release_control where singleton_id=1),false),
       '正式库至少为CACHE27'
union all
select 'character_tables',
       to_regclass('public.player_characters') is not null
       and to_regclass('public.realms') is not null
       and to_regclass('public.realm_stages') is not null,
       '角色与境界表存在'
union all
select 'fate_tables',
       to_regclass('public.character_fates') is not null and to_regclass('public.fates') is not null,
       '命格表存在'
union all
select 'technique_tables',
       to_regclass('public.character_techniques') is not null and to_regclass('public.techniques') is not null,
       '功法表存在'
union all
select 'cultivation_cap',
       to_regprocedure('public.character_cultivation_cap_v1(smallint)') is not null,
       '修为硬上限函数存在'
union all
select 'world_feed_publisher',
       to_regprocedure('public.world_event_publish_v0140(uuid,integer,text,smallint,uuid,text,text,text,text,text,jsonb,boolean,timestamptz)') is not null,
       '九霄界闻发布函数存在'
union all
select 'sword_heart_fate',
       exists(select 1 from public.fates where code='sword_heart'),
       '天生剑心命格存在';
