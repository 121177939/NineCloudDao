#!/usr/bin/env python3
from pathlib import Path
import json
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
checks = []

def ck(name, ok):
    checks.append((name, bool(ok)))

def txt(rel):
    return (root / rel).read_text('utf-8')

required = [
    'index.html', '404.html', 'app.js', 'styles.css', 'config.js', 'update-guard.js',
    'sw.js', 'manifest.webmanifest', 'VERSION.txt', 'CURRENT_BASELINE.json',
    'release_config.json', '.github/workflows/deploy-pages.yml',
    'database/V0.15.2/202607281720_v0152_technique_slots_realm_guard.sql',
    'database/V0.15.2/202607281730_v0152_b01_check.sql',
    'database/V0.15.3/202607281800_v0153_release_cache20.sql',
    'database/V0.15.3/202607281810_v0153_check.sql',
    'SQL/00_SQL执行说明.txt', 'SQL/01_升级前检查.sql', 'SQL/02_B01命格与造化池.sql',
    'SQL/03_功法系统与突破保护.sql', 'SQL/04_升级后检查.sql',
    'SQL/05_V0.15.3_CACHE20_发布门禁.sql', 'SQL/06_V0.15.3_最终检查.sql',
    'tools/prepare_pages_site_v0153.py', 'tools/verify_pages_site_v0153.py',
    'tools/sql_static_audit_v0152.py', 'tools/sql_static_audit_v0153.py',
    'tools/ci_v0153.py'
]
for rel in required:
    ck(f'required:{rel}', (root / rel).is_file())

ck('version', txt('VERSION.txt').strip() == 'V0.15.3')
for rel in ['index.html', '404.html', 'config.js', 'sw.js', 'manifest.webmanifest']:
    ck(f'cache20:{rel}', '0153-cache20' in txt(rel) or '0.15.3-cache20' in txt(rel))
ck('config-version', "version: '0.15.3'" in txt('config.js'))
ck('config-epoch', 'cacheEpoch: 20' in txt('config.js'))

release = json.loads(txt('release_config.json'))
baseline = json.loads(txt('CURRENT_BASELINE.json'))
ck('release-build', release.get('clientBuild') == 'v0153-cache20')
ck('release-version', release.get('version') == 'V0.15.3')
ck('baseline-version', baseline.get('version') == '0.15.3')
ck('baseline-hotfix', baseline.get('clientHotfix') == 'V0.15.3_CACHE20')

workflow = txt('.github/workflows/deploy-pages.yml')
ck('workflow-checkout-v4', 'actions/checkout@v4' in workflow)
ck('workflow-ci-v0153', 'python3 tools/ci_v0153.py .' in workflow)
ck('workflow-pages', all(x in workflow for x in [
    'actions/configure-pages@v5', 'actions/upload-pages-artifact@v4', 'actions/deploy-pages@v4'
]))
ck('workflow-old-ci-removed', 'ci_v0151.py' not in workflow)

sql = txt('SQL/03_功法系统与突破保护.sql')
ck('sql-return-fix', 'select x.max_level, x.cost_factor, x.redeem_rating' in sql)
ck('sql-slot-dedupe', 'row_number() over' in sql and 'drop index if exists public.uq_character_techniques_v0152_slot' in sql)
check_sql = txt('SQL/04_升级后检查.sql').lower()
ck('sql-check-defs', 'with defs as' in check_sql and 'from defs' in check_sql)

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(('PASS ' if ok else 'FAIL ') + name)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
