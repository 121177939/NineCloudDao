#!/usr/bin/env python3
from pathlib import Path
import json
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
main = (root / 'database/V0.15.2/202607281720_v0152_technique_slots_realm_guard.sql').read_text('utf-8')
check = (root / 'database/V0.15.2/202607281730_v0152_b01_check.sql').read_text('utf-8')
checks = {
    'grade-return-columns-fixed': 'select x.max_level, x.cost_factor, x.redeem_rating' in main,
    'grade-no-select-star': 'select * from (values' not in main,
    'slot-index-dropped-before-migration': 'drop index if exists public.uq_character_techniques_v0152_slot' in main,
    'slot-dedupe-window': 'row_number() over' in main and 'partition by ct.character_id' in main and 'legacy_ranked' in main,
    'slot-index-rebuilt': 'create unique index uq_character_techniques_v0152_slot' in main,
    'five-slot-multipliers': "'[1.0,0.6,0.5,0.4,0.3]'::jsonb" in main,
    'exclusive-level-36': "('exclusive',36,1.00::numeric,1000)" in main,
    'realm-guard-helper': 'breakthrough_major_fall_target_v0152' in main,
    'check-cte-used': 'from defs' in check.lower(),
}
failed = [k for k,v in checks.items() if not v]
print(json.dumps({'ok': not failed, 'checks': checks, 'failed': failed}, ensure_ascii=False, indent=2))
raise SystemExit(1 if failed else 0)
