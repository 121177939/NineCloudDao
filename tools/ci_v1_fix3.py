#!/usr/bin/env python3
from pathlib import Path
import subprocess,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();py=sys.executable
def run(label,cmd):print('\n=== '+label+' ===',flush=True);subprocess.run(cmd,cwd=root,check=True)
run('release metadata',[py,'tools/verify_release_v1_fix3.py','.'])
for r in ['app.js','config.js','update-guard.js','sw.js']:run('node syntax '+r,['node','--check',r])
for r in ['tools/prepare_pages_site_v1_fix3.py','tools/verify_pages_site_v1_fix3.py','tools/verify_release_v1_fix3.py','tools/sql_static_audit_v1_fix3.py','tools/ci_v1_fix3.py']:run('python syntax '+r,[py,'-m','py_compile',r])
for r in ['tools/sql_static_audit_v0141_fix7a.py','tools/sql_static_audit_v0142.py','tools/sql_static_audit_v0143.py','tools/sql_static_audit_v0144.py','tools/sql_static_audit_v0145.py','tools/sql_static_audit_v0146.py','tools/sql_static_audit_v0147.py','tools/sql_static_audit_v0148.py','tools/sql_static_audit_v0150.py','tools/sql_static_audit_v0151.py','tools/sql_static_audit_v0152.py','tools/sql_static_audit_v0153.py','tools/sql_static_audit_v0153_fix1.py','tools/sql_static_audit_v0153_fix2.py','tools/sql_static_audit_v0154.py','tools/sql_static_audit_v0155.py','tools/sql_static_audit_v0155_fix1.py','tools/sql_static_audit_v1.py','tools/sql_static_audit_v1_fix1.py','tools/sql_static_audit_v1_fix2.py','tools/sql_static_audit_v1_fix3.py']:run('SQL audit '+r,[py,r,'.'])
for r in ['tools/test_casino_render_v0141.js','tools/test_world_events_render_v0142.js','tools/test_ranking_render_v0143.js','tools/test_features_v0144.js','tools/test_features_v0145.js','tools/test_opportunity_history_v0146.js','tools/test_features_v0147.js','tools/test_features_v0148.js','tools/test_fish_render_v0148.js','tools/test_fish_entry_click_v0148_fix1.js','tools/test_fish_ui_v0149.js','tools/test_fish_continuous_bet_v0150.js','tools/test_casino_feed_fish40_v0151.js','tools/test_features_v0154.js','tools/test_b_cave_module.js','tools/test_features_v0155.js','tools/test_cave_visual_v0155_fix1.js','tools/test_features_v1.js','tools/test_features_v1_fix1.js','tools/test_features_v1_fix2.js','tools/test_features_v1_fix3.js']:run('test '+r,['node',r,'.'])
run('B-COMBAT01 integrated audit',[py,'B_MODULE/B-COMBAT01/tools/ci_bcombat01.py'])
run('build pages',[py,'tools/prepare_pages_site_v1_fix3.py','.','.pages-site'])
run('verify pages',[py,'tools/verify_pages_site_v1_fix3.py','.pages-site'])
print('\nV1.0 FIX3 CACHE33 CI PASS')
