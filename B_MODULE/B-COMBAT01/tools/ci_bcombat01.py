#!/usr/bin/env python3
from pathlib import Path
import subprocess, sys
ROOT=Path(__file__).resolve().parents[3]
commands=[
  ['node','--check','app.js'],
  ['node','B_MODULE/B-COMBAT01/tools/test_client_bcombat01.js',str(ROOT)],
  [sys.executable,'B_MODULE/B-COMBAT01/tools/static_audit_bcombat01.py'],
  [sys.executable,'B_MODULE/B-COMBAT01/tools/test_balance_bcombat01.py'],
  ['node','tools/test_ranking_render_v0143.js',str(ROOT)],
]
for cmd in commands:
  print('\n===',' '.join(cmd),'===',flush=True)
  subprocess.run(cmd,cwd=ROOT,check=True)
print('\nB-COMBAT01 CI PASS')
