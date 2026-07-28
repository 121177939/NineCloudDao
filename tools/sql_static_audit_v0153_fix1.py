#!/usr/bin/env python3
from pathlib import Path
import json
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
main = (root / 'database/V0.15.3_FIX1/202607281900_v0153_fix1_technique_slot_constraint_ui.sql').read_text('utf-8')
check = (root / 'database/V0.15.3_FIX1/202607281910_v0153_fix1_check.sql').read_text('utf-8')
app = (root / 'app.js').read_text('utf-8')
checks = {
    'transaction': 'begin;' in main.lower() and 'commit;' in main.lower(),
    'drop-old-slot-check': 'drop constraint if exists character_techniques_equipped_slot_check' in main,
    'allow-five-slots': all(f"'ordinary_{i}'" in main for i in range(1,6)),
    'slot-type-null': 'slot_type=null' in main.replace(' ',''),
    'new-reader': 'create or replace function public.get_technique_system_v2()' in main,
    'yellow-fallback': "else 'yellow'" in main,
    'cache21-gate': "release_name='V0.15.3 FIX1 CACHE21'" in main and 'greatest(cache_epoch,21)' in main,
    'check-constraint': 'equipped_slot_constraint_accepts_ordinary_1' in check,
    'client-five-slots': all(x in app for x in ['ordinary_1','ordinary_5','data-apply-technique-slot']),
    'client-old-rule-removed': '主修熟练速度100%，辅修50%' not in app,
}
failed = [k for k,v in checks.items() if not v]
print(json.dumps({'ok': not failed, 'checks': checks, 'failed': failed}, ensure_ascii=False, indent=2))
raise SystemExit(1 if failed else 0)
