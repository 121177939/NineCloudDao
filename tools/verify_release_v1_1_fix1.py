#!/usr/bin/env python3
from pathlib import Path
import json
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
checks: list[tuple[str, bool]] = []

def ck(name: str, ok: object) -> None:
    checks.append((name, bool(ok)))

def text(rel: str) -> str:
    return (root / rel).read_text('utf-8')

required = [
    'index.html', '404.html', 'app.js', 'styles.css', 'config.js', 'update-guard.js', 'sw.js',
    'manifest.webmanifest', 'VERSION.txt', 'CURRENT_BASELINE.json', 'release_config.json',
    'V1.1_FIX1_CACHE36.txt', 'V1.1_FIX1_升级说明.md',
    'docs/V1.1_FIX1_赌场周期资金与公平结算规则.md',
    '.github/workflows/deploy-pages.yml',
    'SQL/58_V1.1_FIX1_升级前检查.sql',
    'SQL/59_V1.1_FIX1_赌场周期资金与公平结算.sql',
    'SQL/60_V1.1_FIX1_CACHE36_正式发布门禁.sql',
    'SQL/61_V1.1_FIX1_升级后检查.sql',
    'SQL/62_V1.1_FIX1_紧急停用赌坊.sql',
    'SQL/63_V1.1_FIX1_恢复启用赌坊.sql',
    'database/V1.1_FIX1/202607300850_v1_1_fix1_precheck.sql',
    'database/V1.1_FIX1/202607300900_v1_1_fix1_casino_period_bankroll.sql',
    'database/V1.1_FIX1/202607300910_v1_1_fix1_cache36_release.sql',
    'database/V1.1_FIX1/202607300920_v1_1_fix1_check.sql',
    'database/V1.1_FIX1/202607300930_v1_1_fix1_emergency_disable.sql',
    'database/V1.1_FIX1/202607300940_v1_1_fix1_resume.sql',
    'tools/verify_release_v1_1_fix1.py', 'tools/sql_static_audit_v1_1_fix1.py',
    'tools/test_features_v1_1_fix1.js', 'tools/prepare_pages_site_v1_1_fix1.py',
    'tools/verify_pages_site_v1_1_fix1.py', 'tools/ci_v1_1_fix1.py',
]
for rel in required:
    ck('required:' + rel, (root / rel).is_file())

ck('version-file', text('VERSION.txt').strip() == 'V1.1 FIX1')
config = text('config.js')
ck('config-version', "version: '1.1 FIX1'" in config)
ck('config-label', "releaseLabel: 'V1.1 FIX1 CACHE36'" in config)
ck('config-build', "buildId: 'v1-1-fix1-cache36'" in config)
ck('config-epoch', 'cacheEpoch: 36' in config)

release = json.loads(text('release_config.json'))
baseline = json.loads(text('CURRENT_BASELINE.json'))
lock = json.loads(text('AB_CONTROL/BASELINE_LOCK.json'))
ck('release-json', release.get('version') == 'V1.1 FIX1' and release.get('cacheEpoch') == 36 and release.get('clientBuild') == 'v1-1-fix1-cache36')
ck('baseline-json', baseline.get('version') == '1.1 FIX1' and baseline.get('developmentBaseline') == 'V1.1_FIX1_AB21_CACHE36')
ck('baseline-sql-range', baseline.get('packagePolicy', {}).get('database', '').find('58—61') >= 0)
ck('lock-json', lock.get('baseline') == 'V1.1_FIX1_AB21_CACHE36' and lock.get('databaseSqlRange') == '58-63')
ck('next-sql-64', '64号' in text('AB_CONTROL/NEXT_WORK.md'))

for rel in ['index.html', '404.html', 'config.js', 'sw.js', 'manifest.webmanifest', 'update-guard.js']:
    ck('cache36:' + rel, 'v1-1-fix1-cache36' in text(rel) or 'v1.1-fix1-cache36' in text(rel))
ck('workflow', 'python3 tools/ci_v1_1_fix1.py .' in text('.github/workflows/deploy-pages.yml'))

app = text('app.js')
main = text('SQL/59_V1.1_FIX1_赌场周期资金与公平结算.sql')
ck('frontend-30-percent', '单局累计下注不得超过开局时可用灵石或修为的30%' in app)
ck('frontend-true-dice', '任意豹子' in app and '105/216' in app and '100赔3320' in app)
ck('frontend-period', '每两小时独立重置' in app and '正利润的50%' in app and '领取70%' in app)
ck('frontend-player-house', '100:97.5' in app and '系统绝不兜底' in app)
ck('sql-period-targets', all(x in main for x in ['100000000', '1000000000', "interval '2 hours'", "interval '1 minute'"]))
ck('sql-pool-rules', 'v_profit>0' in main.replace(' ', '') and '*0.50' in main and '*0.70' in main)
ck('sql-fair-rng', 'gen_random_bytes(4)' in main and 'random()' not in main.lower())
ck('sql-request-concurrency', 'pg_try_advisory_xact_lock' in main and 'CASINO_REQUEST_IN_PROGRESS' in main)
ck('sql-player-house-no-cover', 'player_house_97_5_fee_to_bankroll_no_cover' in main and 'system_cover_amount=0' in main.replace(' ', ''))

pairs = [
    ('SQL/58_V1.1_FIX1_升级前检查.sql', 'database/V1.1_FIX1/202607300850_v1_1_fix1_precheck.sql'),
    ('SQL/59_V1.1_FIX1_赌场周期资金与公平结算.sql', 'database/V1.1_FIX1/202607300900_v1_1_fix1_casino_period_bankroll.sql'),
    ('SQL/60_V1.1_FIX1_CACHE36_正式发布门禁.sql', 'database/V1.1_FIX1/202607300910_v1_1_fix1_cache36_release.sql'),
    ('SQL/61_V1.1_FIX1_升级后检查.sql', 'database/V1.1_FIX1/202607300920_v1_1_fix1_check.sql'),
    ('SQL/62_V1.1_FIX1_紧急停用赌坊.sql', 'database/V1.1_FIX1/202607300930_v1_1_fix1_emergency_disable.sql'),
    ('SQL/63_V1.1_FIX1_恢复启用赌坊.sql', 'database/V1.1_FIX1/202607300940_v1_1_fix1_resume.sql'),
]
for left, right in pairs:
    ck('migration-copy:' + left, (root / left).read_bytes() == (root / right).read_bytes())

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(('PASS ' if ok else 'FAIL ') + name)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
