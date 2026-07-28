#!/usr/bin/env python3
from pathlib import Path
import json
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
main = (root / 'database/V0.15.3/202607281800_v0153_release_cache20.sql').read_text('utf-8')
check = (root / 'database/V0.15.3/202607281810_v0153_check.sql').read_text('utf-8')
checks = {
    'transaction': 'begin;' in main.lower() and 'commit;' in main.lower(),
    'release-name': "release_name = 'V0.15.3 CACHE20'" in main,
    'cache-epoch': 'greatest(cache_epoch, 20)' in main,
    'idempotent-insert': 'where not exists' in main.lower(),
    'final-check': "release_name='V0.15.3 CACHE20'" in check and 'cache_epoch>=20' in check,
    'realm-guard-check': 'breakthrough_major_fall_target_v0152' in check,
}
failed = [k for k,v in checks.items() if not v]
print(json.dumps({'ok': not failed, 'checks': checks, 'failed': failed}, ensure_ascii=False, indent=2))
raise SystemExit(1 if failed else 0)
