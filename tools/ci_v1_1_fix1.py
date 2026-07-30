#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
py = sys.executable

def run(label: str, cmd: list[str]) -> None:
    print('\n=== ' + label + ' ===', flush=True)
    subprocess.run(cmd, cwd=root, check=True)

run('release metadata', [py, 'tools/verify_release_v1_1_fix1.py', '.'])
for rel in ['app.js', 'config.js', 'update-guard.js', 'sw.js']:
    run('node syntax ' + rel, ['node', '--check', rel])
for rel in [
    'tools/prepare_pages_site_v1_1_fix1.py', 'tools/verify_pages_site_v1_1_fix1.py',
    'tools/verify_release_v1_1_fix1.py', 'tools/sql_static_audit_v1_1_fix1.py',
    'tools/ci_v1_1_fix1.py'
]:
    run('python syntax ' + rel, [py, '-m', 'py_compile', rel])
run('V1.1 FIX1 SQL audit', [py, 'tools/sql_static_audit_v1_1_fix1.py', '.'])
for rel in [
    'tools/test_features_v1.js', 'tools/test_features_v1_fix1.js',
    'tools/test_features_v1_fix2.js', 'tools/test_features_v1_fix3.js',
    'tools/test_features_v1_1.js', 'tools/test_features_v1_1_fix1.js'
]:
    run('test ' + rel, ['node', rel, '.'])
run('B-COMBAT01 original module audit', [py, 'B_MODULE/B-COMBAT01/tools/ci_bcombat01.py'])
run('build pages', [py, 'tools/prepare_pages_site_v1_1_fix1.py', '.', '.pages-site'])
run('verify pages', [py, 'tools/verify_pages_site_v1_1_fix1.py', '.pages-site'])
print('\nV1.1 FIX1 CACHE36 CI PASS')
