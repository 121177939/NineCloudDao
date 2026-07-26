-- V0.11.10 FIX1 部署检查。执行主SQL后，预期每一行 result 均为 PASS。
with checks as (
  select 1 as seq, '核心ID类型匹配smallint'::text as item,
    case when
      (select data_type from information_schema.columns where table_schema='public' and table_name='spirit_roots' and column_name='id')='smallint'
      and (select data_type from information_schema.columns where table_schema='public' and table_name='realm_stages' and column_name='id')='smallint'
      and (select data_type from information_schema.columns where table_schema='public' and table_name='player_characters' and column_name='realm_stage_id')='smallint'
    then 'PASS' else 'FAIL' end as result,
    'spirit_roots.id、realm_stages.id、player_characters.realm_stage_id均为smallint'::text as detail

  union all select 2, 'combat_multiplier字段存在',
    case when exists (select 1 from information_schema.columns where table_schema='public' and table_name='spirit_roots' and column_name='combat_multiplier') then 'PASS' else 'FAIL' end,
    'public.spirit_roots.combat_multiplier'

  union all select 3, '突破状态表存在',
    case when to_regclass('public.character_breakthrough_states') is not null then 'PASS' else 'FAIL' end,
    coalesce(to_regclass('public.character_breakthrough_states')::text,'missing')

  union all select 4, '大跌境锁字段存在',
    case when exists (select 1 from information_schema.columns where table_schema='public' and table_name='character_breakthrough_states' and column_name='major_fall_used')
           and exists (select 1 from information_schema.columns where table_schema='public' and table_name='character_breakthrough_states' and column_name='major_fall_origin_stage_id')
      then 'PASS' else 'FAIL' end,
    'major_fall_used + major_fall_origin_stage_id'

  union all select 5, '境界基础吐纳函数类型正确',
    case when to_regprocedure('public.realm_base_cultivation_rate_v1(smallint)') is not null then 'PASS' else 'FAIL' end,
    coalesce(to_regprocedure('public.realm_base_cultivation_rate_v1(smallint)')::text,'missing')

  union all select 6, '突破查询RPC存在',
    case when to_regprocedure('public.get_breakthrough_status_v1()') is not null then 'PASS' else 'FAIL' end,
    coalesce(to_regprocedure('public.get_breakthrough_status_v1()')::text,'missing')

  union all select 7, '突破执行RPC存在',
    case when to_regprocedure('public.attempt_breakthrough_v1()') is not null then 'PASS' else 'FAIL' end,
    coalesce(to_regprocedure('public.attempt_breakthrough_v1()')::text,'missing')

  union all select 8, '修炼结算RPC存在',
    case when to_regprocedure('public.claim_cultivation_v1()') is not null then 'PASS' else 'FAIL' end,
    coalesce(to_regprocedure('public.claim_cultivation_v1()')::text,'missing')

  union all select 9, '灵根系数映射正确',
    case when not exists (
      select 1 from public.spirit_roots sr where
        (concat_ws(' ',sr.name,sr.code,sr.rarity) ~* '(变异|异灵根|variant|mutant)' and (sr.cultivation_multiplier<>0.95 or sr.combat_multiplier<>1.10))
        or (concat_ws(' ',sr.name,sr.code,sr.rarity) !~* '(变异|异灵根|variant|mutant)' and concat_ws(' ',sr.name,sr.code,sr.rarity) ~* '(天灵根|单灵根|heaven|single)' and (sr.cultivation_multiplier<>1.00 or sr.combat_multiplier<>1.00))
        or (concat_ws(' ',sr.name,sr.code,sr.rarity) ~* '(双灵根|dual|double)' and (sr.cultivation_multiplier<>0.90 or sr.combat_multiplier<>0.90))
        or (concat_ws(' ',sr.name,sr.code,sr.rarity) ~* '(三灵根|triple)' and (sr.cultivation_multiplier<>0.80 or sr.combat_multiplier<>0.80))
        or (concat_ws(' ',sr.name,sr.code,sr.rarity) ~* '(四灵根|quad|four)' and (sr.cultivation_multiplier<>0.70 or sr.combat_multiplier<>0.70))
        or (concat_ws(' ',sr.name,sr.code,sr.rarity) ~* '(五灵根|杂灵根|five|mixed)' and (sr.cultivation_multiplier<>0.60 or sr.combat_multiplier<>0.60))
    ) then 'PASS' else 'FAIL' end,
    '天1/1；双0.9/0.9；三0.8/0.8；四0.7/0.7；五0.6/0.6；变异0.95/1.1'

  union all select 10, '灵根旧机缘加成已清除',
    case when not exists(select 1 from public.spirit_roots where coalesce(event_luck_bonus,0)<>0) then 'PASS' else 'FAIL' end,
    'event_luck_bonus=0'

  union all select 11, '境界吐纳相邻增量正确',
    case when not exists (
      with ordered as (
        select rs.id,r.major_order,public.realm_base_cultivation_rate_v1(rs.id) rate,
          lag(r.major_order) over(order by r.major_order,rs.minor_level,rs.id) prev_major,
          lag(public.realm_base_cultivation_rate_v1(rs.id)) over(order by r.major_order,rs.minor_level,rs.id) prev_rate
        from public.realm_stages rs join public.realms r on r.id=rs.realm_id
      )
      select 1 from ordered where prev_rate is not null and rate-prev_rate<>case when major_order=prev_major then 5 else 20 end
    ) then 'PASS' else 'FAIL' end,
    '同一大境界+5；跨大境界+20'

  union all select 12, '现有角色基础吐纳已校准',
    case when not exists (
      select 1 from public.character_cultivation_state cs join public.player_characters pc on pc.id=cs.character_id
      where cs.base_rate_per_second<>public.realm_base_cultivation_rate_v1(pc.realm_stage_id)
    ) then 'PASS' else 'FAIL' end,
    'base_rate_per_second与当前境界一致'

  union all select 13, '天道最后整体相乘',
    case when pg_get_functiondef(to_regprocedure('public.claim_cultivation_v1()')) like '%v_segment_fixed_rate * v_effective_qi_multiplier%'
           and pg_get_functiondef(to_regprocedure('public.claim_cultivation_v1()')) like '%v_current_fixed_rate * v_effective_qi_multiplier%'
      then 'PASS' else 'FAIL' end,
    '完整正常修炼速度×世界灵气×天道系数'

  union all select 14, '失败结果概率完整',
    case when pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')) like '%v_roll < 0.01%'
           and pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')) like '%v_roll < 0.06%'
           and pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')) like '%v_roll < 0.21%'
           and pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')) like '%v_roll < 0.51%'
           and pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')) like '%v_roll < 0.81%'
      then 'PASS' else 'FAIL' end,
    '1%死、5%跌大、15%跌小、30%清完、30%清半、19%无损'

  union all select 15, '失败补偿档位正确',
    case when pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')) like '%when v_failure_count = 0 then 0.1000%'
           and pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')) like '%v_compensation + 0.3000%'
      then 'PASS' else 'FAIL' end,
    '首次+10个百分点；以后每次+30个百分点'

  union all select 16, '补偿后最终成功率封顶80%',
    case when pg_get_functiondef(to_regprocedure('public.get_breakthrough_status_v1()')) like '%least(0.8000%'
           and pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')) like '%least(0.8000%'
      then 'PASS' else 'FAIL' end,
    '上限是最终成功率80%'

  union all select 17, '原始目标绑定与抵达清除',
    case when pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')) like '%original_target_stage_id%'
           and pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')) like '%v_success_position >=%'
      then 'PASS' else 'FAIL' end,
    '恢复途中保留；达到最初目标后归零'

  union all select 18, '元婴期以下失败无惩罚',
    case when pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')) like '%low_realm_no_penalty%'
           and pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')) like '%if not v_penalty_enabled%'
      then 'PASS' else 'FAIL' end,
    '不死亡、不跌境、不清修为、不加伤势；仍累计补偿'

  union all select 19, '元婴境界下限存在',
    case when pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')) like '%r.major_order >= v_nascent_soul_order%'
           and pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')) like '%realm_floor_guarded%'
      then 'PASS' else 'FAIL' end,
    '任何跌境均不得低于元婴期'

  union all select 20, '大境界仅允许跌落一次',
    case when pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')) like '%if v_major_fall_used then%'
           and pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')) like '%major_fall_guarded%'
      then 'PASS' else 'FAIL' end,
    '恢复周期内第二次抽中大跌境转为无损失败'

  union all select 21, '回到原始大境界解除大跌境锁',
    case when pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')) like '%v_success_major_order%'
           and pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')) like '%v_major_fall_origin_order%'
           and pg_get_functiondef(to_regprocedure('public.attempt_breakthrough_v1()')) like '%v_major_fall_used := false%'
      then 'PASS' else 'FAIL' end,
    '达到首次大跌境前所在的大境界后解除'

  union all select 22, '升级前定义备份存在',
    case when to_regclass('ncd_release_backup.v01110_fix1_functions') is not null
           and (select count(*) from ncd_release_backup.v01110_fix1_functions)>=3
      then 'PASS' else 'FAIL' end,
    '支持恢复V0.11.9关键函数'
)
select seq,item,result,detail from checks order by seq;
