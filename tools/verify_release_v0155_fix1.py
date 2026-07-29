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
    'index.html', '404.html', 'app.js', 'styles.css', 'config.js',
    'update-guard.js', 'sw.js', 'manifest.webmanifest', 'VERSION.txt',
    'CURRENT_BASELINE.json', 'release_config.json',
    '.github/workflows/deploy-pages.yml',
    'database/V0.15.5_FIX1/202607291500_v0155_fix1_precheck.sql',
    'database/V0.15.5_FIX1/202607291510_v0155_fix1_cache27_cave_visual_release.sql',
    'database/V0.15.5_FIX1/202607291520_v0155_fix1_check.sql',
    'SQL/23_V0.15.5_FIX1_升级前检查.sql',
    'SQL/24_V0.15.5_FIX1_CACHE27_洞府视觉修正发布门禁.sql',
    'SQL/25_V0.15.5_FIX1_升级后检查.sql',
    'tools/prepare_pages_site_v0155_fix1.py',
    'tools/verify_pages_site_v0155_fix1.py',
    'tools/verify_release_v0155_fix1.py',
    'tools/sql_static_audit_v0155_fix1.py',
    'tools/test_cave_visual_v0155_fix1.js',
    'tools/test_b_cave_module.js',
    'tools/test_features_v0155.js',
    'tools/ci_v0155_fix1.py',
]
for rel in required:
    ck(f'required:{rel}', (root / rel).is_file())

ck('version', txt('VERSION.txt').strip() == 'V0.15.5')
for rel in ['index.html', '404.html', 'config.js', 'sw.js', 'manifest.webmanifest', 'update-guard.js']:
    ck(f'cache27:{rel}', '0155-fix1-cache27' in txt(rel) or '0.15.5-fix1-cache27' in txt(rel))

config = txt('config.js')
ck('config-version', "version: '0.15.5'" in config)
ck('config-label', "releaseLabel: 'V0.15.5 FIX1 CACHE27'" in config)
ck('config-epoch', 'cacheEpoch: 27' in config)

release = json.loads(txt('release_config.json'))
baseline = json.loads(txt('CURRENT_BASELINE.json'))
ck('release-build', release.get('clientBuild') == 'v0155-fix1-cache27')
ck('release-version', release.get('version') == 'V0.15.5')
ck('release-migration', release.get('databaseMigration') == 'database/V0.15.5_FIX1/202607291510_v0155_fix1_cache27_cave_visual_release.sql')
ck('baseline-version', baseline.get('version') == '0.15.5')
ck('baseline-hotfix', baseline.get('clientHotfix') == 'V0.15.5_FIX1_CACHE27')
ck('baseline-epoch', baseline.get('cacheEpoch') == 27)
ck('baseline-development', baseline.get('developmentBaseline') == 'V0.15.5_AB14_CACHE27')

workflow = txt('.github/workflows/deploy-pages.yml')
ck('workflow-ci-fix1', 'python3 tools/ci_v0155_fix1.py .' in workflow)
ck('workflow-pages', all(x in workflow for x in [
    'actions/configure-pages@v5', 'actions/upload-pages-artifact@v4', 'actions/deploy-pages@v4'
]))

app = txt('app.js')
css = txt('styles.css')
for name, token in {
    'yuanshen-nav': "['primordial', '元', '元神']",
    'yuanshen-panel': 'primordialSpiritPanelHtmlV0155',
    'yuanshen-placeholder': '不会生成伪造数据',
    'b-cave': 'cave-scene-b01',
    'inventory30': 'CAVE_STORAGE_SLOT_COUNT_B01 = 30',
    'cave-rock-arch': 'cave-rock-arch-b01',
    'cave-spirit-veins': 'cave-spirit-veins-b01',
    'cave-stone-platform': 'cave-stone-platform-b01',
    'cave-copy': '洞天幽居 · 灵脉自运',
    'cap80': '道果崩解0.3%',
}.items():
    ck('app-' + name, token in app)

ck('cave-css-elements', all(x in css for x in [
    '.cave-rock-arch-b01', '.cave-stalactites-b01', '.cave-spirit-veins-b01',
    '.cave-stone-platform-b01', '@keyframes caveVeinFlowB01', '@keyframes caveAuraB01'
]))
ck('cave-no-rotating-mandala', 'caveRingB01' not in css)
ck('css-yuanshen-animation', all(x in css for x in [
    '@keyframes yuanshen-levitate-v0155', '@keyframes yuanshen-meridian-v0155'
]))

sql = txt('SQL/24_V0.15.5_FIX1_CACHE27_洞府视觉修正发布门禁.sql').lower()
ck('sql-cache27', "release_name = 'v0.15.5 fix1 cache27'" in sql and 'greatest(cache_epoch, 27)' in sql)
ck('sql-direct-from-cache25', '不要求先执行 cache26' in sql)
ck('sql-no-schema-change', all(x not in sql for x in [
    'create table', 'create function', 'alter table', 'drop table', 'create trigger'
]))

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(('PASS ' if ok else 'FAIL ') + name)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
