#!/usr/bin/env python3
from pathlib import Path
import subprocess,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();py=sys.executable
def run(label,cmd):print(f'\n=== {label} ===',flush=True);subprocess.run(cmd,cwd=root,check=True)
run('release metadata',[py,'tools/verify_release_v0154.py','.'])
for rel in ['app.js','config.js','update-guard.js','sw.js']:run('node syntax '+rel,['node','--check',rel])
for rel in ['tools/prepare_pages_site_v0154.py','tools/verify_pages_site_v0154.py','tools/verify_release_v0154.py','tools/sql_static_audit_v0154.py','tools/ci_v0154.py']:run('python syntax '+rel,[py,'-m','py_compile',rel])
for rel in ['tools/sql_static_audit_v0141_fix7a.py','tools/sql_static_audit_v0142.py','tools/sql_static_audit_v0143.py','tools/sql_static_audit_v0144.py','tools/sql_static_audit_v0145.py','tools/sql_static_audit_v0146.py','tools/sql_static_audit_v0147.py','tools/sql_static_audit_v0148.py','tools/sql_static_audit_v0150.py','tools/sql_static_audit_v0151.py','tools/sql_static_audit_v0152.py','tools/sql_static_audit_v0153.py','tools/sql_static_audit_v0153_fix1.py','tools/sql_static_audit_v0153_fix2.py','tools/sql_static_audit_v0154.py']:run('SQL audit '+rel,[py,rel,'.'])
for rel in ['tools/test_casino_render_v0141.js','tools/test_world_events_render_v0142.js','tools/test_ranking_render_v0143.js','tools/test_features_v0144.js','tools/test_features_v0145.js','tools/test_opportunity_history_v0146.js','tools/test_features_v0147.js','tools/test_features_v0148.js','tools/test_fish_render_v0148.js','tools/test_fish_entry_click_v0148_fix1.js','tools/test_fish_ui_v0149.js','tools/test_fish_continuous_bet_v0150.js','tools/test_casino_feed_fish40_v0151.js','tools/test_features_v0154.js']:run('test '+rel,['node',rel,'.'])
run('build pages',[py,'tools/prepare_pages_site_v0154.py','.','.pages-site']);run('verify pages',[py,'tools/verify_pages_site_v0154.py','.pages-site'])
print('\nV0.15.4 CI PASS')
