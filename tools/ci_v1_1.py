#!/usr/bin/env python3
from pathlib import Path
import subprocess,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();py=sys.executable
def run(label,cmd):print('\n=== '+label+' ===',flush=True);subprocess.run(cmd,cwd=root,check=True)
run('release metadata',[py,'tools/verify_release_v1_1.py','.'])
for x in ['app.js','config.js','update-guard.js','sw.js']:run('node syntax '+x,['node','--check',x])
for x in ['tools/prepare_pages_site_v1_1.py','tools/verify_pages_site_v1_1.py','tools/verify_release_v1_1.py','tools/sql_static_audit_v1_1.py','tools/ci_v1_1.py']:run('python syntax '+x,[py,'-m','py_compile',x])
for x in ['tools/sql_static_audit_v0154.py','tools/sql_static_audit_v0155_fix1.py','tools/sql_static_audit_v1.py','tools/sql_static_audit_v1_fix1.py','tools/sql_static_audit_v1_fix2.py','tools/sql_static_audit_v1_fix4.py','tools/sql_static_audit_v1_1.py']:run('SQL audit '+x,[py,x,'.'])
for x in ['tools/test_features_v0154.js','tools/test_b_cave_module.js','tools/test_features_v0155.js','tools/test_cave_visual_v0155_fix1.js','tools/test_features_v1.js','tools/test_features_v1_fix1.js','tools/test_features_v1_fix2.js','tools/test_features_v1_fix4.js','tools/test_features_v1_1.js']:run('test '+x,['node',x,'.'])
run('B-COMBAT01 original module audit',[py,'B_MODULE/B-COMBAT01/tools/ci_bcombat01.py'])
run('build pages',[py,'tools/prepare_pages_site_v1_1.py','.','.pages-site'])
run('verify pages',[py,'tools/verify_pages_site_v1_1.py','.pages-site'])
print('\nV1.1 CACHE35 CI PASS')
