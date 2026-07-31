#!/usr/bin/env python3
from pathlib import Path
import subprocess,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();py=sys.executable
def run(label,cmd): print('\n=== '+label+' ===',flush=True);subprocess.run(cmd,cwd=root,check=True)
run('release metadata',[py,'tools/verify_release_v1_6_fix1.py','.'])
for rel in ['app.js','config.js','update-guard.js','sw.js','b-paigow01.js','paigow-realtime.js','paigow-app.js']: run('node syntax '+rel,['node','--check',rel])
for rel in ['tools/prepare_pages_site_v1_6_fix1.py','tools/verify_pages_site_v1_6_fix1.py','tools/verify_release_v1_6_fix1.py','tools/sql_static_audit_v1_6_fix1.py','tools/ci_v1_6_fix1.py']: run('python syntax '+rel,[py,'-m','py_compile',rel])
run('SQL static audit',[py,'tools/sql_static_audit_v1_6_fix1.py','.'])
run('feature test',['node','tools/test_features_v1_6_fix1.js','.'])
run('V1.6 realtime regression',['node','tools/test_paigow_realtime_v1_6.js','.'])
run('V1.6 load model regression',[py,'tools/test_paigow_v1_6_load.py'])
run('V1.5 settlement regression',[py,'tools/test_paigow_v1_5_rules.py'])
run('build pages',[py,'tools/prepare_pages_site_v1_6_fix1.py','.','.pages-site'])
run('verify pages',[py,'tools/verify_pages_site_v1_6_fix1.py','.pages-site'])
print('\nV1.6 FIX1 CACHE45 CI PASS')
