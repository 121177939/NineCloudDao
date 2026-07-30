#!/usr/bin/env python3
from pathlib import Path
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
checks: list[tuple[str, bool]] = []

def read(rel: str) -> str:
    return (root / rel).read_text('utf-8')

def ck(name: str, ok: object) -> None:
    checks.append((name, bool(ok)))

rng = read('SQL/64_V1.1_FIX1_安全随机兼容修复.sql')
pre = read('SQL/65_V1.2_升级前检查.sql')
main = read('SQL/66_V1.2_变异灵根与剑心互斥.sql')
gate = read('SQL/67_V1.2_CACHE37_正式发布门禁.sql')
post = read('SQL/68_V1.2_升级后检查.sql')
disable = read('SQL/69_V1.2_紧急停用变异加成.sql')
resume = read('SQL/70_V1.2_恢复启用变异加成.sql')
low = main.lower()
compact = re.sub(r'\s+', '', low)

for label, text in [('pre', pre), ('post', post)]:
    executable = '\n'.join(line for line in text.splitlines() if not line.lstrip().startswith('--')).lower()
    ck(label + '-readonly', not re.search(r'(?m)^\s*(update|insert|delete|create|alter|drop|truncate|grant|revoke)\b', executable))

for label, text in [('rng', rng), ('main', main), ('gate', gate), ('disable', disable), ('resume', resume)]:
    stripped = text.lower().strip()
    ck(label + '-transaction', '\nbegin;' in '\n' + stripped and stripped.endswith('commit;'))
    ck(label + '-balanced-dollar-quotes', text.count('$$') % 2 == 0)

rng_exec='\n'.join(line for line in rng.splitlines() if not line.lstrip().startswith('--')).lower()
ck('rng-no-gen-random-bytes-call', 'gen_random_bytes(' not in rng_exec)
ck('rng-uuid-rejection', all(x in rng for x in ['gen_random_uuid()', 'v_raw<v_limit', 'v_raw%p_upper']))
ck('rng-private', 'revoke all on function public.casino_secure_random_int_v1(integer)' in rng.lower())

ck('conflict-log-table', 'create table if not exists public.character_talent_conflict_logs_v12' in low)
ck('mutant-detector', 'function public.v12_is_mutant_root' in low and '(变异|异灵根|variant|mutant)' in main)
ck('mapping-metal-thunder', "when p_base_element='metal' then 'thunder'" in low)
ck('mapping-wood-wind', "when p_base_element='wood' then 'wind'" in low)
ck('mapping-water-ice', "when p_base_element='water' then 'ice'" in low)
ck('fire-earth-no-mapping', "when p_base_element='fire'" not in low and "when p_base_element='earth'" not in low)
ck('sword-heart-blocks-mutation', "when coalesce(p_fate_code,'')='sword_heart' then null" in low)
ck('labels', all(x in main for x in ["when 'thunder' then '雷'", "when 'ice' then '冰'", "when 'wind' then '风'"]))

ck('root-guard-trigger', all(x in low for x in ['trg_v12_mutant_root_conflict_guard', 'v12_guard_mutant_root_against_sword_heart']))
ck('fate-guard-trigger', all(x in low for x in ['trg_v12_sword_heart_conflict_guard', 'v12_guard_sword_heart_against_mutant_root']))
ck('root-conflict-random-replacement', 'v12_random_non_mutant_root' in low and "'replace_later_acquired_root'" in low)
ck('fate-conflict-random-replacement', 'v12_random_non_sword_fate' in low and "'replace_later_acquired_fate'" in low)
ck('secure-random-selection', low.count('order by public.casino_secure_random_int_v1(2147483647)') >= 4)
ck('historical-conflict-random-branch', 'v_replace_root:=public.casino_secure_random_int_v1(2)=0' in compact)
ck('migration-conflict-audit', 'migration_existing_talent_conflict' in low and "'random_existing_conflict'" in low)
ck('final-conflict-assertion', 'v12_talent_conflict_remains' in low)

ck('mutation-settings', 'mutation_bonus_enabled' in low and 'mutation_final_damage_bonus' in low and '=0.08' in compact)
ck('snapshot-replaced-in-place', 'create or replace function public.bcombat01_character_snapshot(p_character_id uuid)' in low)
ck('snapshot-no-rename-wrapper', 'rename to bcombat01_character_snapshot_v11_base' not in low and 'bcombat01_character_snapshot_v11_base' not in low)
for field in ['spirit_root_is_mutant','mutation_element','mutation_name','mutation_active','mutation_final_damage_bonus','mutation_display','talent_conflict']:
    ck('snapshot-field:' + field, "'" + field + "'" in low)
ck('sword-active-requires-no-mutation', "mutation.mutation_elementisnull" in compact and "'sword_heart_active'" in low)

ck('ranking-v11-rule-preserved', '高低战力可互相挑战' in main and "'can_challenge',id<>v_self_id" in compact)
ck('ranking-mutation-fields', all("'" + x + "'" in low for x in ['mutation_element','mutation_name','mutation_active','mutation_display']))

ck('damage-sword-elsif-mutation', re.search(r"if\s+coalesce\(\(p_attacker->>'sword_heart_active'\).*?elsif\s+coalesce\(v_settings\.mutation_bonus_enabled", low, re.S) is not None)
ck('damage-final-layer', 'v_element*v_sword*v_mutation' in compact)
ck('damage-eight-percent-default', 'mutation_final_damage_bonus,0.08' in low)
ck('damage-report-fields', all("'" + x + "'" in low for x in ['mutation_multiplier','mutation_element','mutation_name']))
ck('root-reroll-rereads-result', 'v_attempted_root_id' in low and 'conflict_replaced' in low and 'v_new_root_id is distinct from v_attempted_root_id' in low)
ck('birth-result-rpc', 'function public.get_my_birth_result_v12()' in low and "'spirit_root_display'" in low)

# V1.2 must not redefine or extend the original five-element cycle.
element_definitions = re.findall(r'create\s+or\s+replace\s+function\s+public\.bcombat01_element_overcomes', low)
ck('no-element-cycle-redefinition', not element_definitions)
ck('no-new-overcome-pairs', not any(pair in compact for pair in ["('thunder','", "('ice','", "('wind','"]))

ck('gate-cache37', "release_name='v1.2 cache37'" in gate.lower() and 'greatest(cache_epoch,37)' in gate.lower())
ck('gate-damage-layer', 'v_element*v_sword*v_mutation' in gate.replace(' ',''))
ck('post-mapping-checks', all(x in post for x in ['mutation_mapping_metal','mutation_mapping_wood','mutation_mapping_water']))
ck('post-five-elements-unchanged', 'old_element_cycle_unchanged' in post and 'no_mutation_element_cycle' in post)
ck('disable-only-bonus', 'mutation_bonus_enabled=false' in disable.replace(' ', '').lower() and 'drop ' not in disable.lower())
ck('resume-eight-percent', 'mutation_bonus_enabled=true' in resume.replace(' ', '').lower() and 'mutation_final_damage_bonus=0.08' in resume.replace(' ', '').lower())

pairs = [
    ('SQL/64_V1.1_FIX1_安全随机兼容修复.sql','database/V1.1_FIX1/202607300950_v1_1_fix1_secure_rng_compat.sql'),
    ('SQL/65_V1.2_升级前检查.sql','database/V1.2/202607301300_v1_2_precheck.sql'),
    ('SQL/66_V1.2_变异灵根与剑心互斥.sql','database/V1.2/202607301310_v1_2_mutation_roots_sword_heart_mutex.sql'),
    ('SQL/67_V1.2_CACHE37_正式发布门禁.sql','database/V1.2/202607301320_v1_2_cache37_release.sql'),
    ('SQL/68_V1.2_升级后检查.sql','database/V1.2/202607301330_v1_2_check.sql'),
    ('SQL/69_V1.2_紧急停用变异加成.sql','database/V1.2/202607301340_v1_2_emergency_disable_mutation.sql'),
    ('SQL/70_V1.2_恢复启用变异加成.sql','database/V1.2/202607301350_v1_2_resume_mutation.sql'),
]
for left,right in pairs:
    ck('migration-copy:' + left, (root/left).read_bytes() == (root/right).read_bytes())

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(('PASS ' if ok else 'FAIL ') + name)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
