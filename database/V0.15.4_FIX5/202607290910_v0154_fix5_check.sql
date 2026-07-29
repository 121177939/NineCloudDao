-- 九霄问道 V0.15.4 FIX5 CACHE25 最终检查（只读）
with defs as (
 select pg_get_functiondef('public.get_breakthrough_status_v1()'::regprocedure) status_v1,
        pg_get_functiondef('public.attempt_breakthrough_v1()'::regprocedure) attempt_v1,
        pg_get_functiondef('public.get_breakthrough_status_v0154()'::regprocedure) status_v0154,
        pg_get_functiondef('public.attempt_breakthrough_v0154(integer,uuid)'::regprocedure) attempt_v0154
), checks(item,ok,detail) as (
 select '发布缓存 CACHE25',coalesce((select cache_epoch>=25 and release_name='V0.15.4 FIX5 CACHE25' from public.jiuxiao_app_release_control where singleton_id=1),false),'发布控制应为 FIX5 CACHE25'
 union all select '状态基础上限80%',strpos(status_v1,'least(0.80')>0 and strpos(status_v1,'0.80::numeric')>0,'get_breakthrough_status_v1 必须以80%截断' from defs
 union all select '实际判定上限80%',strpos(attempt_v1,'least(0.80')>0 and strpos(attempt_v1,'least(0.80,v_effective')>0,'attempt_breakthrough_v1 包含丹药后的最终判定也必须以80%截断' from defs
 union all select '丹药可用数量按80%',strpos(status_v0154,'0.80-v_rate')>0 and strpos(status_v0154,'least(0.80')>0,'状态包装只允许选择提升到80%所需丹药' from defs
 union all select '丹药最终概率按80%',strpos(attempt_v0154,'0.80-v_rate')>0 and strpos(attempt_v0154,'least(0.80')>0,'突破包装返回值和数量校验均以80%为限' from defs
 union all select '丹药说明已更新',exists(select 1 from public.item_definitions where code='breakthrough_clear_origin_pill_v0154' and description like '%不得超过80%'),'商品说明明确全局80%硬上限'
) select * from checks order by item;
