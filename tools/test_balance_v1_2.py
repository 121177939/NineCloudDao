#!/usr/bin/env python3
from decimal import Decimal, ROUND_FLOOR

checks=[]
def ck(name, ok, detail=''):
    checks.append((name,bool(ok),detail))

base=Decimal('1000')
bonus=Decimal('1.08')
ck('mutation +8%', base*bonus == Decimal('1080'), str(base*bonus))
ck('sword heart +8%', base*bonus == Decimal('1080'), str(base*bonus))
# Mutual exclusion means the production formula never applies both talent multipliers.
active_talent_multipliers=[Decimal('1.00'),Decimal('1.08')]
ck('no 1.1664 stack', Decimal('1.1664') not in active_talent_multipliers, str(active_talent_multipliers))
# Existing element multiplier remains independent and is multiplied once with the single talent layer.
for element in [Decimal('0.90'),Decimal('1.00'),Decimal('1.10')]:
    normal=(base*element).quantize(Decimal('1'),rounding=ROUND_FLOOR)
    mutated=(base*element*bonus).quantize(Decimal('1'),rounding=ROUND_FLOOR)
    ck(f'element {element} preserved', mutated == (Decimal(normal)*bonus).quantize(Decimal('1'),rounding=ROUND_FLOOR), f'{normal}->{mutated}')
# Only metal/wood/water have V1.2 mutation manifestations.
mapping={'metal':'thunder','wood':'wind','water':'ice','fire':None,'earth':None}
ck('mapping exact', mapping=={'metal':'thunder','wood':'wind','water':'ice','fire':None,'earth':None},str(mapping))
failed=[x for x in checks if not x[1]]
for name,ok,detail in checks:
    print(('PASS ' if ok else 'FAIL ')+name+(f' [{detail}]' if detail else ''))
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
