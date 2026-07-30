from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parents[1]
cmds=[
 [sys.executable,str(root/'tools/static_audit_bpaigow01.py')],
 ['node','--check',str(root/'CLIENT_CANDIDATE/app.js')],
 ['node','--check',str(root/'CLIENT_CANDIDATE/b-paigow01.js')],
 [sys.executable,str(root/'tools/check_inline_html_js.py')],
 ['node',str(root/'tools/test_client_bpaigow01.js')],
]
for c in cmds:
 print('$',' '.join(c));r=subprocess.run(c,cwd=root)
 if r.returncode: raise SystemExit(r.returncode)
print('B-PAIGOW01 MODULE CI PASS')
