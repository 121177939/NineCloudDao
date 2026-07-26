from pathlib import Path
import json, sys, re

root = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parents[1]
checks = []
infos = []

def check(name, ok, detail=''):
    checks.append((name, bool(ok), detail))

def info(name, detail=''):
    infos.append((name, detail))

def text(path):
    return (root / path).read_text('utf-8')

required = [
    'index.html','404.html','app.js','styles.css','config.js','sw.js','manifest.webmanifest',
    'VERSION.txt','CURRENT_BASELINE.json','release_config.json','.nojekyll',
    '.github/workflows/deploy-pages.yml',
    'tools/verify_release_v0131.py','tools/prepare_pages_site_v0131.py','tools/verify_pages_site_v0131.py',
    'tools/sql_static_audit_v0130.py','tools/test_market_render_v0130.js',
    'database/V0.13.0/202607261300_v0130_breakthrough_cultivation_cap.sql',
    'database/V0.13.0/202607261300_v0130_check.sql',
    'database/V0.13.1/README_NO_SQL.md',
    'docs/V0.13.1_DEPLOYMENT_HOTFIX.md','docs/V0.13.1_BUILD_VERIFY_REPORT.md',
]
for f in required:
    check('file:' + f, (root / f).is_file())

check('version.txt', text('VERSION.txt').strip() == 'V0.13.1')
for f in ['index.html','404.html','config.js','README.md','CHANGELOG.md','DESKTOP_UPDATE.md']:
    check('version:' + f, '0.13.1' in text(f))
check('sw-cache', 'nine-cloud-dao-v0.13.1' in text('sw.js'))
check('styles-release', 'Current release: Web Alpha 0.13.1' in text('styles.css'))

base = json.loads(text('CURRENT_BASELINE.json'))
release = json.loads(text('release_config.json'))
check('baseline.version', base.get('version') == '0.13.1')
check('baseline.source', base.get('sourceBaseline') == 'V0.13.0 FINAL')
check('baseline.no_sql', base.get('databaseChange') == 'NONE' and base.get('databaseMigration') is None)
check('release.version', release.get('version') == 'V0.13.1')
check('release.pages_stage', release.get('pagesStagingDirectory') == '.pages-site')

app = text('app.js')
for token in ['cultivation-full-notice','heavenly_insight_count','CULTIVATION_FULL_CASINO_BLOCKED','breakthroughOutcomeName','currentDisplayedCultivation()','最终成功率上限']:
    check('inherited-app:' + token, token in app)

sql = text('database/V0.13.0/202607261300_v0130_breakthrough_cultivation_cap.sql')
for token in ['0.005000','0.050000','0.080000','0.150000','0.300000','0.415000','character_cultivation_cap_v1','grant_cultivation_capped_v1','trg_player_characters_cultivation_cap_v0130']:
    check('inherited-sql:' + token, token in sql)

workflow = text('.github/workflows/deploy-pages.yml')
for token in ['actions/checkout@v6','actions/setup-python@v6','python-version: "3.13.5"','actions/setup-node@v6','node-version: "24"','prepare_pages_site_v0131.py','.pages-site','verify_pages_site_v0131.py','actions/upload-pages-artifact@v4','actions/deploy-pages@v4']:
    check('workflow:' + token, token in workflow)

# Important V0.13.1 rule: stale files may exist after an overlay update, but none may be invoked by the active workflow.
legacy_active = ['tools/audit_v0120_fix1.py','tools/test_market_render_v0120_fix1.js','tools/verify_release.py']
for legacy in legacy_active:
    check('legacy-not-referenced:' + legacy, legacy not in workflow)
    if (root / legacy).exists():
        info('stale-file-tolerated', legacy)

check('workflow-no-checkout-v4', 'actions/checkout@v4' not in workflow)
check('workflow-separated-jobs', re.search(r'(?m)^  build:', workflow) is not None and re.search(r'(?m)^  deploy:', workflow) is not None and 'needs: build' in workflow)
check('old-fix3-deprecated', '旧V0.12.0 FIX3' in text('database/MIGRATION_REGISTRY.md'))

for n,d in infos:
    print('INFO', n, d)
failed = [x for x in checks if not x[1]]
for n,ok,d in checks:
    print(('PASS' if ok else 'FAIL'), n, d)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)} INFO={len(infos)}')
sys.exit(1 if failed else 0)
