#!/usr/bin/env python3
from pathlib import Path
import subprocess,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();py=sys.executable
def run(label,cmd): print('\n=== '+label+' ===',flush=True);subprocess.run(cmd,cwd=root,check=True)
run('release metadata',[py,'tools/verify_release_v1_6.py','.'])
run('GitHub Pages workflow audit',[py,'tools/verify_github_pages_workflow_v1_6.py','.'])
for rel in ['app.js','config.js','update-guard.js','sw.js','b-paigow01.js','paigow-realtime.js','paigow-app.js']:
 run('node syntax '+rel,['node','--check',rel])
for rel in ['tools/prepare_pages_site_v1_6.py','tools/verify_pages_site_v1_6.py','tools/verify_release_v1_6.py','tools/verify_github_pages_workflow_v1_6.py','tools/sql_static_audit_v1_6.py','tools/test_paigow_v1_6_load.py','tools/ci_v1_6.py']:
 run('python syntax '+rel,[py,'-m','py_compile',rel])
run('V1.6 SQL static audit',[py,'tools/sql_static_audit_v1_6.py','.'])
run('V1.6 feature test',['node','tools/test_features_v1_6.js','.'])
run('V1.6 Realtime client test',['node','tools/test_paigow_realtime_v1_6.js','.'])
run('V1.6 nine-player load model',[py,'tools/test_paigow_v1_6_load.py'])
run('V1.5 settlement math regression',[py,'tools/test_paigow_v1_5_rules.py'])
for rel in ['tools/test_features_v1.js','tools/test_features_v1_fix1.js','tools/test_features_v1_fix2.js','tools/test_features_v1_fix3.js','tools/test_features_v1_1.js']:
 run('regression '+rel,['node',rel,'.'])
run('B-COMBAT01 module audit',[py,'B_MODULE/B-COMBAT01/tools/ci_bcombat01.py'])
run('B-PAIGOW01 original candidate audit',[py,'B_MODULE/B-PAIGOW01/tools/ci_bpaigow01.py'])
run('build pages',[py,'tools/prepare_pages_site_v1_6.py','.','.pages-site'])
run('verify pages',[py,'tools/verify_pages_site_v1_6.py','.pages-site'])
print('\nV1.6 CACHE44 CI PASS')
