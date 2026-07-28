#!/usr/bin/env python3
from pathlib import Path
import json, sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.')
checks=[]
def ck(name,ok):
    checks.append((name,bool(ok))); print(('PASS' if ok else 'FAIL'),name)
def txt(p): return (root/p).read_text('utf-8')
required=['index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','docs/V0.14.8_FIX1_SOURCE_CHANGE_REPORT.md','docs/V0.14.8_FIX1_DEPLOYMENT_GUIDE.md']
for f in required: ck('required:'+f,(root/f).is_file())
app=txt('app.js')
block=app[app.index("document.querySelectorAll('[data-house-select-game]')"):app.index("if (houseChoice && houseChoice.dataset.bound",app.index("document.querySelectorAll('[data-house-select-game]')"))]
ck('fix-order',block.index('houseGameInput.value = game') < block.index('renderCasinoPanel();'))
ck('version',txt('VERSION.txt').strip()=='V0.14.8 FIX1')
for f in ['index.html','404.html','sw.js','manifest.webmanifest','config.js','update-guard.js']:
    ck('cache13:'+f,'v0148-fix1-cache13' in txt(f) or '0148-fix1-cache13' in txt(f))
rc=json.loads(txt('release_config.json')); cb=json.loads(txt('CURRENT_BASELINE.json'))
ck('release-build',rc.get('clientBuild')=='v0148-fix1-cache13')
ck('baseline-hotfix',cb.get('clientHotfix')=='V0.14.8_FIX1_FISH_ENTRY_CACHE13')
ck('no-new-sql',rc.get('databaseChange')=='none')
failed=[x for x in checks if not x[1]]
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
