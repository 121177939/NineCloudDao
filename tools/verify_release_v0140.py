#!/usr/bin/env python3
from pathlib import Path
import json, re, sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parents[1]
checks=[]; infos=[]
def check(name,ok,detail=''): checks.append((name,bool(ok),detail))
def info(name,detail=''): infos.append((name,detail))
def text(path): return (root/path).read_text('utf-8')
required=[
 'index.html','404.html','app.js','styles.css','config.js','sw.js','manifest.webmanifest',
 'VERSION.txt','CURRENT_BASELINE.json','release_config.json','README.md','CHANGELOG.md','DESKTOP_UPDATE.md','.nojekyll',
 '.github/workflows/deploy-pages.yml',
 'tools/verify_release_v0140.py','tools/prepare_pages_site_v0140.py','tools/verify_pages_site_v0140.py',
 'tools/sql_static_audit_v0140.py','tools/test_bazaar_render_v0140.js',
 'database/V0.14.0/202607261430_v0140_precheck.sql',
 'database/V0.14.0/202607261430_v0140_bazaar_world_events.sql',
 'database/V0.14.0/202607261430_v0140_check.sql',
 'database/V0.14.0/202607261430_v0140_data_audit.sql',
 'database/V0.14.0/202607261430_v0140_emergency_disable.sql',
 'database/V0.14.0/202607261430_v0140_resume.sql',
 'database/V0.14.0/202607261430_v0140_rollback.sql',
 'docs/V0.14.0_SOURCE_CHANGE_REPORT.md','docs/V0.14.0_DATABASE_CHANGELOG.md','docs/V0.14.0_DEPLOYMENT_GUIDE.md',
 'docs/V0.14.0_ROLLBACK_GUIDE.md','docs/V0.14.0_REAL_DEVICE_TEST_CHECKLIST.md','docs/V0.14.0_FINAL_RULES.md','docs/V0.14.0_BUILD_VERIFY_REPORT.md'
]
for f in required: check('file:'+f,(root/f).is_file())
check('version.txt',text('VERSION.txt').strip()=='V0.14.0')
for f in ['index.html','404.html','config.js','README.md','CHANGELOG.md','DESKTOP_UPDATE.md']:
 check('version:'+f,'0.14.0' in text(f))
check('sw-cache','nine-cloud-dao-v0.14.0' in text('sw.js'))
check('styles-release','Current release: Web Alpha 0.14.0' in text('styles.css'))
base=json.loads(text('CURRENT_BASELINE.json')); release=json.loads(text('release_config.json'))
check('baseline.version',base.get('version')=='0.14.0')
check('baseline.source',base.get('sourceBaseline')=='V0.13.1 FINAL')
check('baseline.sql',base.get('databaseChange')=='WORLD_EVENTS' and str(base.get('databaseMigration','')).endswith('v0140_bazaar_world_events.sql'))
check('release.version',release.get('version')=='V0.14.0')
check('release.pages_stage',release.get('pagesStagingDirectory')=='.pages-site')

app=text('app.js'); css=text('styles.css'); html=text('index.html')
for token in ['bazaarPanelHtml','worldEventsPanelHtml','rpcGetWorldEventsV1','refreshWorldEvents','data-bazaar-target="ranking"','data-bazaar-target="casino"','data-bazaar-target="treasure"','返回市坊','九霄界闻','珍宝阁尚在筹备']:
 check('app:'+token,token in app)
for token in ['.bazaar-entry-grid','.bazaar-entry-button','.world-event-row','.bazaar-subpage-head','.treasure-placeholder']:
 check('css:'+token,token in css)
check('ui-name-bazaar','<h3>市坊</h3>' in app and "['market', '市', '市坊']" in app)
check('no-visible-market-title','<h3>市场</h3>' not in app and '>市场<' not in html)
check('ranking-not-bottom-nav',"['ranking', '榜', '天命榜']" not in app)
check('world-poll-20s','worldEventsSyncTimer = setInterval' in app and '}, 20000);' in app)
check('casino-refresh-world','Promise.all([refreshMarketSystem(true), refreshWorldEvents(true)])' in app)

sql=text('database/V0.14.0/202607261430_v0140_bazaar_world_events.sql')
for token in ['create table if not exists public.world_events','create or replace function public.get_world_events_v1','after insert on public.casino_house_games',"'casino_house_' || new.outcome_code",'after update on public.casino_duels','after insert on public.casino_draws','admin_publish_account_erasure_v1','world_events_source_unique','exception when others then']:
 check('sql:'+token,token in sql)
check('sql-house-every-result','每一局胜负均播报' in sql)
check('sql-no-direct-auth-write','grant insert' not in sql.lower() and 'grant update' not in sql.lower() and 'grant delete' not in sql.lower())

workflow=text('.github/workflows/deploy-pages.yml')
for token in ['actions/checkout@v6','actions/setup-python@v6','python-version: "3.13.5"','actions/setup-node@v6','node-version: "24"','verify_release_v0140.py','sql_static_audit_v0140.py','test_bazaar_render_v0140.js','prepare_pages_site_v0140.py','verify_pages_site_v0140.py','.pages-site','actions/upload-pages-artifact@v4','actions/deploy-pages@v4']:
 check('workflow:'+token,token in workflow)
for legacy in ['verify_release_v0131.py','prepare_pages_site_v0131.py','verify_pages_site_v0131.py','test_market_render_v0130.js']:
 check('legacy-not-referenced:'+legacy,legacy not in workflow)
 if (root/('tools/'+legacy if not legacy.startswith('tools/') else legacy)).exists(): info('stale-file-tolerated',legacy)
check('workflow-separated-jobs',bool(re.search(r'(?m)^  build:',workflow)) and bool(re.search(r'(?m)^  deploy:',workflow)) and 'needs: build' in workflow)
check('migration-registry','## V0.14.0' in text('database/MIGRATION_REGISTRY.md'))
check('old-fix3-deprecated','永久废弃' in text('database/MIGRATION_REGISTRY.md') and 'FIX3' in text('database/MIGRATION_REGISTRY.md'))

for n,d in infos: print('INFO',n,d)
failed=[x for x in checks if not x[1]]
for n,ok,d in checks: print(('PASS' if ok else 'FAIL'),n,d)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)} INFO={len(infos)}')
sys.exit(1 if failed else 0)
