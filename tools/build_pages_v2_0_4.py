#!/usr/bin/env python3
from pathlib import Path
import json, re, sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve()
build='v2-0-5-cache97-equipment-worldnews3-pagesunlock1-appdialogupdate1'; label='V2.0.5 CACHE97'
required=['.nojekyll','index.html','404.html','styles.css','app.js','config.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json']
missing=[x for x in required if not (root/x).is_file()]
if missing: raise SystemExit('MISSING:'+','.join(missing))
assert (root/'VERSION.txt').read_text('utf-8').splitlines()[0]==label
assert build in (root/'config.js').read_text('utf-8')
assert build in (root/'index.html').read_text('utf-8')
base=json.loads((root/'CURRENT_BASELINE.json').read_text('utf-8'))
assert base['cacheEpoch']==96 and base['nextSqlNumber']==232
yaml=(root/'.github/workflows/deploy-pages.yml').read_text('utf-8')
for forbidden in ['deploy-pages@','upload-pages-artifact@','environment:','pages: write','id-token: write']:
    assert forbidden not in yaml, forbidden
print(f'PASS {label} branch-source static site; no custom Pages deploy job')
