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
    'database/V0.15.3_FIX1/202607281900_v0153_fix1_technique_slot_constraint_ui.sql',
    'database/V0.15.3_FIX1/202607281910_v0153_fix1_check.sql',
    'database/V0.15.3_FIX2/202607281930_v0153_fix2_spirit_stone_rpc.sql',
    'database/V0.15.3_FIX2/202607281940_v0153_fix2_check.sql',
    'SQL/00_SQL执行说明.txt', 'SQL/01_升级前检查.sql', 'SQL/02_B01命格与造化池.sql',
    'SQL/03_功法系统与突破保护.sql', 'SQL/04_升级后检查.sql',
    'SQL/05_V0.15.3_CACHE20_发布门禁.sql', 'SQL/06_V0.15.3_最终检查.sql',
    'SQL/07_V0.15.3_FIX1_功法槽与界面数据修复.sql', 'SQL/08_V0.15.3_FIX1_最终检查.sql',
    'SQL/09_V0.15.3_FIX2_灵石账户RPC修复.sql', 'SQL/10_V0.15.3_FIX2_最终检查.sql',
    'tools/prepare_pages_site_v0153.py', 'tools/verify_pages_site_v0153.py',
    'tools/sql_static_audit_v0152.py', 'tools/sql_static_audit_v0153.py',
    'tools/sql_static_audit_v0153_fix1.py', 'tools/sql_static_audit_v0153_fix2.py',
    'tools/ci_v0153.py'
]
for rel in required:
    ck(f'required:{rel}', (root / rel).is_file())

ck('version', txt('VERSION.txt').strip() == 'V0.15.3')
for rel in ['index.html', '404.html', 'config.js', 'sw.js', 'manifest.webmanifest']:
    ck(f'cache22:{rel}', '0153-fix2-cache22' in txt(rel) or '0.15.3-fix2-cache22' in txt(rel))
ck('config-version', "version: '0.15.3'" in txt('config.js'))
ck('config-epoch', 'cacheEpoch: 22' in txt('config.js'))

release = json.loads(txt('release_config.json'))
baseline = json.loads(txt('CURRENT_BASELINE.json'))
ck('release-build', release.get('clientBuild') == 'v0153-fix2-cache22')
ck('release-version', release.get('version') == 'V0.15.3')
ck('release-migration', release.get('databaseMigration') == 'database/V0.15.3_FIX2/202607281930_v0153_fix2_spirit_stone_rpc.sql')
ck('baseline-version', baseline.get('version') == '0.15.3')
ck('baseline-hotfix', baseline.get('clientHotfix') == 'V0.15.3_FIX2_CACHE22')

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
fix1_sql = txt('SQL/07_V0.15.3_FIX1_功法槽与界面数据修复.sql').lower()
fix2_sql = txt('SQL/09_V0.15.3_FIX2_灵石账户RPC修复.sql').lower()
ck('fix1-slot-constraint', 'character_techniques_equipped_slot_check' in fix1_sql and 'ordinary_5' in fix1_sql)
ck('fix1-technique-reader', 'create or replace function public.get_technique_system_v2()' in fix1_sql)
ck('fix2-reader-balance', 'public.spirit_stone_balance_v0141(c.id)' in fix2_sql and 'c.spirit_stones' not in fix2_sql)
ck('fix2-upgrade-debit', 'public.spirit_stone_debit_v0141(c.id,v_cost' in fix2_sql.replace(' ', ''))
ck('fix2-redeem-award', 'public.award_spirit_stones_v3(c.id,v_total)' in fix2_sql.replace(' ', ''))
ck('fix2-no-direct-player-balance-write', 'update public.player_characters set spirit_stones' not in fix2_sql)
ck('fix2-cache22-gate', "release_name='v0.15.3 fix2 cache22'" in fix2_sql and 'greatest(cache_epoch,22)' in fix2_sql)
ck('sql-check-defs', 'with defs as' in check_sql and 'from defs' in check_sql)

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(('PASS ' if ok else 'FAIL ') + name)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
