#!/usr/bin/env python3
from __future__ import annotations
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SQL = ROOT / 'B_MODULE/B-COMBAT01/SQL_CANDIDATE/10_B_COMBAT01_MAIN.sql'
text = SQL.read_text(encoding='utf-8')
pattern = re.compile(r"\((\d+),(\d+),'([^']+)',([0-9.]+),(\d+),(\d+),(\d+),(\d+)\)")
rows = [
    {
        'major': int(m), 'minor': int(n), 'label': label, 'coefficient': float(c),
        'attack': int(a), 'defense': int(d), 'vitality': int(v), 'agility': int(g)
    }
    for m, n, label, c, a, d, v, g in pattern.findall(text)
]
assert len(rows) == 44, f'expected 44 stage rows, got {len(rows)}'
stats = {(r['major'], r['minor']): r for r in rows}

def damage(attacker, defender, element_multiplier=1.0, sword_multiplier=1.0):
    a = stats[attacker]
    d = stats[defender]
    reduction = min(0.70, d['defense'] / (d['defense'] + d['attack'] * 2))
    return max(1, math.floor(a['attack'] * element_multiplier * sword_multiplier * (1 - reduction)))

def duel(attacker, defender, attacker_element=1.0, defender_element=1.0, attacker_sword=1.0):
    a = stats[attacker]
    d = stats[defender]
    ahp, dhp = a['vitality'], d['vitality']
    first_attacker = a['agility'] > d['agility']
    rounds = 0
    while ahp > 0 and dhp > 0 and rounds < 100:
        rounds += 1
        order = ('a', 'd') if first_attacker else ('d', 'a')
        for actor in order:
            if actor == 'a':
                dhp = max(0, dhp - damage(attacker, defender, attacker_element, attacker_sword))
            else:
                ahp = max(0, ahp - damage(defender, attacker, defender_element, 1.0))
            if ahp <= 0 or dhp <= 0:
                break
    assert rounds < 100, f'battle exceeded round guard: {attacker} vs {defender}'
    return {'winner': 'attacker' if ahp > 0 else 'defender', 'attacker_hp': ahp, 'defender_hp': dhp, 'rounds': rounds}

checks = []

def record(name, ok, detail=''):
    checks.append((name, bool(ok), detail))
    if not ok:
        raise AssertionError(f'{name}: {detail}')

# Power anchors agreed in design discussion.
def power(key):
    r = stats[key]
    return round(r['attack'] * 10 + r['defense'] * 8 + r['vitality'] * 1.5 + r['agility'] * 5)
for key, expected in {
    (3,1): 8140, (3,2): 8950, (3,3): 9760, (3,4): 10570,
    (4,1): 12570, (4,4): 16185, (10,1): 172245
}.items():
    record(f'power_{stats[key]["label"]}', power(key) == expected, f'{power(key)} != {expected}')

adjacent_count = 0
for major in range(1, 10):
    levels = sorted(k[1] for k in stats if k[0] == major)
    for low, high in zip(levels, levels[1:]):
        adjacent_count += 1
        result = duel((major, low), (major, high), 1.15, 0.85)
        record(f'adjacent_overcome_{major}_{low}_{high}', result['winner'] == 'attacker', str(result))
record('adjacent_case_count', adjacent_count == 33, str(adjacent_count))

two_stage_count = 0
for major in range(1, 10):
    levels = sorted(k[1] for k in stats if k[0] == major)
    for index in range(len(levels) - 2):
        two_stage_count += 1
        low, high = levels[index], levels[index + 2]
        result = duel((major, low), (major, high), 1.05, 0.95)
        record(f'two_stage_block_{major}_{low}_{high}', result['winner'] == 'defender', str(result))
record('two_stage_case_count', two_stage_count == 24, str(two_stage_count))

cross_count = 0
for major in range(1, 10):
    low = max((k for k in stats if k[0] == major), key=lambda k: k[1])
    high = min((k for k in stats if k[0] == major + 1), key=lambda k: k[1])
    cross_count += 1
    result = duel(low, high, 1.05, 0.95)
    record(f'cross_major_block_{major}', result['winner'] == 'defender', str(result))
    sword_result = duel(low, high, 1.05, 0.95, 1.08)
    record(f'cross_major_sword_heart_block_{major}', sword_result['winner'] == 'defender', str(sword_result))
record('cross_major_case_count', cross_count == 9, str(cross_count))

key_cases = {
    'golden_initial_beats_middle_with_overcome': duel((3,1),(3,2),1.15,0.85),
    'golden_initial_loses_late_with_weak_overcome': duel((3,1),(3,3),1.05,0.95),
    'golden_late_beats_perfect_with_overcome': duel((3,3),(3,4),1.15,0.85),
    'golden_perfect_loses_nascent_initial': duel((3,4),(4,1),1.05,0.95),
    'golden_perfect_sword_heart_still_loses_nascent_initial': duel((3,4),(4,1),1.05,0.95,1.08),
}
expected_winners = ['attacker','defender','attacker','defender','defender']
for (name, result), expected in zip(key_cases.items(), expected_winners):
    record(name, result['winner'] == expected, str(result))

passed = sum(1 for _, ok, _ in checks if ok)
print(f'B-COMBAT01 BALANCE PASS {passed}/{len(checks)}')
for name, result in key_cases.items():
    print(f'{name}: {result}')
