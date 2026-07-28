#!/usr/bin/env python3
from pathlib import Path
import json,sys,re
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def ck(n,o): checks.append((n,bool(o))); print(('PASS' if o else 'FAIL'),n)
def txt(p): return (root/p).read_text('utf-8')
required=['index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','.github/workflows/deploy-pages.yml','database/V0.15.0/202607281900_v0150_precheck.sql','database/V0.15.0/202607281910_v0150_fish_continuous_bet_world_feed_exclusion.sql','database/V0.15.0/202607281920_v0150_check.sql','database/V0.15.0/202607281930_v0150_rollback.sql','docs/V0.15.0_SOURCE_CHANGE_REPORT.md','docs/V0.15.0_DEPLOYMENT_GUIDE.md','docs/V0.15.0_BUILD_VERIFY_REPORT.md','tools/prepare_pages_site_v0150.py','tools/verify_pages_site_v0150.py','tools/test_fish_continuous_bet_v0150.js','tools/sql_static_audit_v0150.py']
for f in required: ck('required:'+f,(root/f).is_file())
app=txt('app.js');css=txt('styles.css');workflow=txt('.github/workflows/deploy-pages.yml')
ck('version',txt('VERSION.txt').strip()=='V0.15.0')
for f in ['index.html','404.html','sw.js','manifest.webmanifest','config.js','update-guard.js']:
 ck('cache16:'+f,'v0150-cache16' in txt(f) or '0150-cache16' in txt(f))
rc=json.loads(txt('release_config.json'));cb=json.loads(txt('CURRENT_BASELINE.json'))
ck('release-build',rc.get('clientBuild')=='v0150-cache16')
ck('baseline-hotfix',cb.get('clientHotfix')=='V0.15.0_FISH_CONTINUOUS_BET_CACHE16')
ck('database-change',rc.get('databaseChange')=='world_feed_guard_and_release_control')
ck('queue-functions',all(x in app for x in ['enqueueFishShrimpBetV0150','processFishShrimpBetQueueV0150','fishShrimpQueuedAmountV0150']))
handler_start=app.rindex("document.querySelectorAll('[data-fish-symbol]')")
handler=app[handler_start:app.index("document.querySelectorAll('[data-fish-refresh]')",handler_start)]
ck('no-button-busy','setBusy(' not in handler and '落注中' not in handler)
ck('serial-batch','while (queue.length)' in app and 'existing.amount = nextAmount' in app and '}, 120);' in app)
ck('pending-ui','data-fish-pending' in app and '.fish-target-card.queued' in css)
ck('desktop-responsive','.fish-game-shell {' in css and 'width: 100%;' in css and 'max-width: none;' in css and 'width: min(100%, 460px)' not in css)
sql=txt('database/V0.15.0/202607281910_v0150_fish_continuous_bet_world_feed_exclusion.sql')
ck('world-feed-exclusion',"coalesce(new.game_code, '') = 'fish_shrimp'" in sql)
ck('workflow-pages',all(t in workflow for t in ['actions/checkout@v6','actions/configure-pages@v5','actions/upload-pages-artifact@v4','actions/deploy-pages@v4','python3 tools/ci_v0150.py .']))
failed=[x for x in checks if not x[1]]
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
