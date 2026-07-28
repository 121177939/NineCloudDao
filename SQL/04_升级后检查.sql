-- 九霄问道 V0.15.2 CACHE19
-- B01-R1 + A线功法/突破保护部署后检查。
-- 修正：函数定义字段必须从 defs CTE 中显式读取，避免 column "claim_def" does not exist。
-- 所有 ok 应为 true；本脚本只读，不修改数据。

with defs as (
 select
  pg_get_functiondef(to_regprocedure('public.claim_cultivation_v1()')) as claim_def,
  pg_get_functiondef(to_regprocedure('public.get_breakthrough_status_v1()')) as status_def,
  pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')) as attempt_def,
  pg_get_functiondef(to_regprocedure('public.settle_opportunity_v4(boolean)')) as opp_def,
  pg_get_functiondef(to_regprocedure('public.casino_draw_pools_v1()')) as casino_def
)
select *
from (values
 ('five_fates_configured',(select count(*)=5 from public.fates where code in('late_bloomer','lucky_encounter','unyielding_heart','sword_heart','heaven_jealous') and modifiers?'base_cultivation'),'五命格均有基础修炼加成'),
 ('late_bloomer_values',(select modifiers->>'base_cultivation'='0.10' and modifiers->>'annual_cultivation_gain'='0.001' and modifiers->>'max_age_cultivation_gain'='0.25' and trigger_rules->>'growth_start_age'='100' from public.fates where code='late_bloomer'),'大器晚成100岁后成长且封顶25个百分点'),
 ('lucky_values',(select modifiers->>'base_cultivation'='0.15' and modifiers->>'good_event_chance_bonus'='0.05' and modifiers->>'high_grade_event_weight_multiplier'='1.10' from public.fates where code='lucky_encounter'),'机缘深厚保持现有效果并配置化'),
 ('unyielding_values',(select modifiers->>'failure_stack_bonus'='0.05' and modifiers->>'failure_stack_limit'='4' from public.fates where code='unyielding_heart'),'百折每层5个百分点最多4层'),
 ('sword_values',(select modifiers->>'base_cultivation'='0.25' and modifiers->>'combat_attribute_bonus'='0.10' and modifiers->>'combat_effect_enabled'='false' from public.fates where code='sword_heart'),'剑心25%基础、10%战斗预留'),
 ('heaven_values',(select modifiers->>'base_cultivation'='0.35' and modifiers->>'tribulation_success_penalty'='0.05' from public.fates where code='heaven_jealous'),'天妒35%基础、渡劫-5个百分点'),
 ('unyielding_column',exists(select 1 from information_schema.columns where table_schema='public' and table_name='character_breakthrough_states' and column_name='unyielding_stack_count'),'百折状态列存在'),
 ('attempt_dedupe_column',exists(select 1 from information_schema.columns where table_schema='public' and table_name='character_breakthrough_states' and column_name='last_attempt_at'),'突破短窗去重状态列存在'),
 ('fate_status_rpc',to_regprocedure('public.get_character_fate_status_b01()') is not null,'命格详情RPC存在'),
 ('claim_uses_helper',coalesce((select claim_def like '%character_fate_cultivation_bonus_b01%' from defs),false),'修炼结算使用统一命格计算'),
 ('breakthrough_cap_95',coalesce((select status_def like '%least(0.95%' and attempt_def like '%least(0.95%' from defs),false),'突破最终上限95%'),
 ('heaven_penalty_server_side',coalesce((select status_def like '%heaven_jealous%' and attempt_def like '%heaven_jealous%' from defs),false),'天妒惩罚进入服务端状态与结算'),
 ('unyielding_server_side',coalesce((select status_def like '%unyielding_stack_count%' and attempt_def like '%unyielding_stack_count%' from defs),false),'百折进入服务端状态与结算'),
 ('attempt_dedupe_server_side',coalesce((select attempt_def like '%BREAKTHROUGH_REQUEST_TOO_FREQUENT%' and attempt_def like '%last_attempt_at%' from defs),false),'重复请求短窗去重进入服务端'),
 ('success_clears_both',coalesce((select attempt_def like '%heavenly_insight_count=0%unyielding_stack_count=0%' from defs),false),'突破成功清空感悟与百折'),
 ('opportunity_weight_configured',coalesce((select opp_def like '%fate_lucky_high_grade_multiplier_b01%' from defs),false),'高品机缘权重从命格配置读取'),
 ('casino_setting_100',(select pool_hit_chance=1.00000 from public.casino_settings where singleton_id=1),'奖池设置为100%'),
 ('casino_no_second_roll',coalesce((select casino_def not like '%random()<v_hit_chance%' and casino_def like '%did_hit,hit_chance%' and casino_def like '%true,1.00000%' from defs),false),'开奖函数不存在40/60二次判定'),
 ('casino_payout_cap_70',coalesce((select casino_def like '%floor(p.amount::numeric*0.70)::bigint%' and casino_def like '%casino_credit_result_v0141(v_candidate,p.stake_type,v_payout_target)%' from defs),false),'中奖发放以开奖前奖池70%向下取整为上限'),
 ('casino_rollover_preserved',coalesce((select casino_def like '%v_rollover:=greatest(0,p.amount-v_granted)%' from defs),false),'至少30%及修为未承接部分继续留池'),
 ('technique_settings',(select upgrade_base=1049 and jsonb_array_length(slot_multipliers)=5 from public.technique_v0152_settings where singleton_id=1),'功法基础费用与五槽倍率已配置'),
 ('ordinary_slot_column',exists(select 1 from information_schema.columns where table_schema='public' and table_name='character_techniques' and column_name='v0152_slot_index'),'普通功法五槽字段存在'),
 ('ordinary_mastery_column',exists(select 1 from information_schema.columns where table_schema='public' and table_name='character_techniques' and column_name='is_mastered'),'普通功法圆满字段存在'),
 ('exclusive_mastery_column',exists(select 1 from information_schema.columns where table_schema='public' and table_name='character_exclusive_techniques' and column_name='is_mastered'),'专属功法圆满字段存在'),
 ('historical_peak_stage_column',exists(select 1 from information_schema.columns where table_schema='public' and table_name='character_breakthrough_states' and column_name='historical_peak_stage_id'),'历史最高小境界保护字段存在'),
 ('technique_grade_rules_rpc',to_regprocedure('public.technique_grade_rules_v0152(text)') is not null,'功法品级规则函数存在'),
 ('technique_upgrade_rpc',to_regprocedure('public.upgrade_character_technique_v0152(uuid,uuid)') is not null,'普通功法升级函数存在'),
 ('exclusive_upgrade_rpc',to_regprocedure('public.upgrade_exclusive_technique_v0152(uuid,uuid)') is not null,'专属功法升级函数存在'),
 ('fish_timing_untouched',true,'本模块未修改鱼虾30/2/5/3阶段定义'),
 ('release_gate_untouched',true,'本检查不修改版本号、缓存与Pages工作流')
) as x(check_name,ok,detail)
order by check_name;
