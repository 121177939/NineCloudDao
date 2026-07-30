#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();wf=(root/'.github/workflows/deploy-pages.yml').read_text('utf-8');checks=[]
def ck(n,v): checks.append((n,bool(v)))
ck('push-main','branches: ["main"]' in wf)
ck('manual-dispatch','workflow_dispatch:' in wf)
ck('permissions',all(x in wf for x in ['contents: read','pages: write','id-token: write']))
ck('build-script','python3 tools/ci_v1_3.py .' in wf)
ck('pages-artifact','uses: actions/upload-pages-artifact@v4' in wf and 'path: .pages-site' in wf)
ck('configure-pages','uses: actions/configure-pages@v5' in wf)
ck('deploy-pages','uses: actions/deploy-pages@v4' in wf and 'needs: build' in wf)
ck('no-playwright-install','playwright' not in wf.lower())
ck('no-fixed-browser-path','/usr/bin/chromium' not in wf and '/opt/pyvenv' not in wf)
ck('no-old-ci','ci_v1_2_fix3.py' not in wf)
for n,v in checks: print(('PASS ' if v else 'FAIL ')+n)
failed=[n for n,v in checks if not v]
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(bool(failed))
