-- 九霄问道 V1.2 CACHE37 升级后检查（只读）
select 'release_cache37' check_name,
  exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1 and cache_epoch>=37 and release_name='V1.2 CACHE37') ok,
  '发布门禁已提升至V1.2 CACHE37' detail
union all select 'mutation_mapping_metal',exists(select 1 from public.spirit_roots sr where public.v12_is_mutant_root(sr.id) and public.v12_mutation_element(sr.id,'metal','')='thunder'),'变异灵根+金映射为雷'
union all select 'mutation_mapping_wood',exists(select 1 from public.spirit_roots sr where public.v12_is_mutant_root(sr.id) and public.v12_mutation_element(sr.id,'wood','')='wind'),'变异灵根+木映射为风'
union all select 'mutation_mapping_water',exists(select 1 from public.spirit_roots sr where public.v12_is_mutant_root(sr.id) and public.v12_mutation_element(sr.id,'water','')='ice'),'变异灵根+水映射为冰'
union all select 'fire_earth_no_new_mutation',exists(select 1 from public.spirit_roots sr where public.v12_is_mutant_root(sr.id) and public.v12_mutation_element(sr.id,'fire','') is null and public.v12_mutation_element(sr.id,'earth','') is null),'火土未扩展新的变异属性'
union all select 'sword_blocks_mutation',exists(select 1 from public.spirit_roots sr where public.v12_is_mutant_root(sr.id) and public.v12_mutation_element(sr.id,'metal','sword_heart') is null),'天生剑心不激活变异属性'
union all select 'no_talent_conflict',not exists(select 1 from public.character_spirit_roots csr join public.character_fates cf on cf.character_id=csr.character_id and cf.is_active join public.fates f on f.id=cf.fate_id and f.code='sword_heart' where csr.is_primary and public.v12_is_mutant_root(csr.spirit_root_id)),'当前角色不存在剑心+变异灵根冲突'
union all select 'root_conflict_trigger',exists(select 1 from pg_trigger where tgname='trg_v12_mutant_root_conflict_guard' and not tgisinternal),'剑心先得时后续变异灵根会随机替换'
union all select 'fate_conflict_trigger',exists(select 1 from pg_trigger where tgname='trg_v12_sword_heart_conflict_guard' and not tgisinternal),'变异先得时后续天生剑心会随机替换'
union all select 'mutation_bonus_8',exists(select 1 from public.battle_challenge_settings_bcombat01 where singleton_id=1 and mutation_bonus_enabled and mutation_final_damage_bonus=0.08),'雷风冰最终伤害加成8%'
union all select 'old_element_cycle_unchanged',replace(pg_get_functiondef(to_regprocedure('public.bcombat01_element_overcomes(text,text)')),' ','') like '%(''metal'',''wood'')%' and replace(pg_get_functiondef(to_regprocedure('public.bcombat01_element_overcomes(text,text)')),' ','') like '%(''fire'',''metal'')%','原五行相克循环保持不变'
union all select 'no_mutation_element_cycle',position('thunder' in pg_get_functiondef(to_regprocedure('public.bcombat01_element_overcomes(text,text)')))=0 and position('ice' in pg_get_functiondef(to_regprocedure('public.bcombat01_element_overcomes(text,text)')))=0 and position('wind' in pg_get_functiondef(to_regprocedure('public.bcombat01_element_overcomes(text,text)')))=0,'风冰雷未加入克制关系'
union all select 'damage_mutex',position('elsif' in lower(pg_get_functiondef(to_regprocedure('public.bcombat01_resolve_hit(jsonb,jsonb,integer,integer,integer)'))))>0 and position('v_element*v_sword*v_mutation' in replace(pg_get_functiondef(to_regprocedure('public.bcombat01_resolve_hit(jsonb,jsonb,integer,integer,integer)')),' ',''))>0,'剑心与变异加成互斥且位于最终伤害层'
union all select 'secure_rng_compat',position('gen_random_bytes' in lower(pg_get_functiondef(to_regprocedure('public.casino_secure_random_int_v1(integer)'))))=0,'赌场随机函数不再依赖gen_random_bytes';

select conflict_code,replacement_kind,count(*)::bigint as resolved_count
from public.character_talent_conflict_logs_v12
group by conflict_code,replacement_kind order by conflict_code,replacement_kind;
