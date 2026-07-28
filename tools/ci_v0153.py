#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
py = sys.executable

def run(label, command):
    print(f'\n=== {label} ===', flush=True)
    subprocess.run(command, cwd=root, check=True)

run('release metadata', [py, 'tools/verify_release_v0153.py', '.'])

for rel in ['app.js', 'config.js', 'update-guard.js', 'sw.js']:
    run(f'node syntax {rel}', ['node', '--check', rel])

for rel in [
    'tools/prepare_pages_site_v0153.py', 'tools/verify_pages_site_v0153.py',
    'tools/verify_release_v0153.py', 'tools/sql_static_audit_v0152.py',
    'tools/sql_static_audit_v0153.py', 'tools/sql_static_audit_v0153_fix1.py', 'tools/sql_static_audit_v0153_fix2.py', 'tools/ci_v0153.py'
]:
    run(f'python syntax {rel}', [py, '-m', 'py_compile', rel])

sql_audits = [
    'tools/sql_static_audit_v0141_fix7a.py', 'tools/sql_static_audit_v0142.py',
    'tools/sql_static_audit_v0143.py', 'tools/sql_static_audit_v0144.py',
    'tools/sql_static_audit_v0145.py', 'tools/sql_static_audit_v0146.py',
    'tools/sql_static_audit_v0147.py', 'tools/sql_static_audit_v0148.py',
    'tools/sql_static_audit_v0150.py', 'tools/sql_static_audit_v0151.py',
    'tools/sql_static_audit_v0152.py', 'tools/sql_static_audit_v0153.py',
    'tools/sql_static_audit_v0153_fix1.py', 'tools/sql_static_audit_v0153_fix2.py'
]
for rel in sql_audits:
    run(f'SQL audit {rel}', [py, rel, '.'])

node_tests = [
    'tools/test_casino_render_v0141.js', 'tools/test_world_events_render_v0142.js',
    'tools/test_ranking_render_v0143.js', 'tools/test_features_v0144.js',
    'tools/test_features_v0145.js', 'tools/test_opportunity_history_v0146.js',
    'tools/test_features_v0147.js', 'tools/test_features_v0148.js',
    'tools/test_fish_render_v0148.js', 'tools/test_fish_entry_click_v0148_fix1.js',
    'tools/test_fish_ui_v0149.js', 'tools/test_fish_continuous_bet_v0150.js',
    'tools/test_casino_feed_fish40_v0151.js'
]
for rel in node_tests:
    run(f'test {rel}', ['node', rel, '.'])

run('build pages', [py, 'tools/prepare_pages_site_v0153.py', '.', '.pages-site'])
run('verify pages', [py, 'tools/verify_pages_site_v0153.py', '.pages-site'])
print('\nV0.15.3 CI PASS')
