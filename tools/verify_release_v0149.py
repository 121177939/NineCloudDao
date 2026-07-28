#!/usr/bin/env python3
from pathlib import Path
import json,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.')
checks=[]
def ck(n,o): checks.append((n,bool(o))); print(('PASS' if o else 'FAIL'),n)
def txt(p): return (root/p).read_text('utf-8')
required=['index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','.github/workflows/deploy-pages.yml','database/V0.14.9/README_NO_SQL.md','docs/V0.14.9_SOURCE_CHANGE_REPORT.md','docs/V0.14.9_DEPLOYMENT_GUIDE.md','docs/V0.14.9_BUILD_VERIFY_REPORT.md','tools/prepare_pages_site_v0149.py','tools/verify_pages_site_v0149.py','tools/test_fish_ui_v0149.js']
for f in required: ck('required:'+f,(root/f).is_file())
app=txt('app.js'); css=txt('styles.css'); workflow=txt('.github/workflows/deploy-pages.yml')
ck('version',txt('VERSION.txt').strip()=='V0.14.9')
for f in ['index.html','404.html','sw.js','manifest.webmanifest','config.js','update-guard.js']:
 ck('cache15:'+f,'v0149-cache15' in txt(f) or '0149-cache15' in txt(f))
rc=json.loads(txt('release_config.json')); cb=json.loads(txt('CURRENT_BASELINE.json'))
ck('release-build',rc.get('clientBuild')=='v0149-cache15')
ck('baseline-hotfix',cb.get('clientHotfix')=='V0.14.9_FISH_RESPONSIVE_CACHE15')
ck('no-new-sql',rc.get('databaseChange')=='none')
ck('six-svg',all(f'{x}: `<svg' in app for x in ['fish','shrimp','crab','coin','gourd','frog']))
ck('desktop-responsive','.fish-game-shell {' in css and 'width: 100%;' in css and 'max-width: none;' in css and 'width: min(100%, 460px)' not in css)
panel=app[app.index('return `<section id="fishShrimpRoot"'):app.index('function renderFishShrimpPanelV0148')]
ck('confirmed-order',panel.index('押注设置')<panel.index('开盘灵骰')<panel.index('选择压什么')<panel.index('最近20局结算历史')<panel.index('结算明细'))
ck('workflow-pages',all(t in workflow for t in ['actions/checkout@v6','actions/configure-pages@v5','actions/upload-pages-artifact@v4','actions/deploy-pages@v4','python3 tools/ci_v0149.py .']))
ck('workflow-no-fixed-setup','actions/setup-python' not in workflow and 'actions/setup-node' not in workflow and 'package-manager-cache' not in workflow)
failed=[x for x in checks if not x[1]]
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
