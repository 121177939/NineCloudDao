#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();s=(root/'.github/workflows/deploy-pages.yml').read_text('utf-8');checks=[]
def ck(n,v): checks.append((n,bool(v)))
ck('push-main','branches: ["main"]' in s)
ck('workflow-dispatch','workflow_dispatch:' in s)
ck('pages-write','pages: write' in s)
ck('id-token','id-token: write' in s)
ck('python-312','python-version: "3.12"' in s)
ck('node-20','node-version: "20"' in s)
ck('v16-ci','python3 tools/ci_v1_6.py .' in s)
ck('pages-artifact','actions/upload-pages-artifact@v4' in s and 'path: .pages-site' in s)
ck('deploy-pages','actions/deploy-pages@v4' in s)
ck('portable',all(x not in s.lower() for x in ['playwright','chromium','/usr/bin/']))
for n,v in checks: print(('PASS ' if v else 'FAIL ')+n)
failed=[n for n,v in checks if not v]
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(bool(failed))
