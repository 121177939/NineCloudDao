from pathlib import Path
import re,subprocess,tempfile,sys
root=Path(__file__).resolve().parents[1]
html=(root/'CLIENT_CANDIDATE/b-paigow01.html').read_text(encoding='utf-8')
scripts=re.findall(r'<script(?:\s[^>]*)?>(.*?)</script>',html,re.S|re.I)
if not scripts:
 print('inline html scripts: FAIL (none found)');raise SystemExit(1)
with tempfile.NamedTemporaryFile('w',suffix='.js',encoding='utf-8',delete=False) as f:
 f.write('\n;\n'.join(scripts));tmp=f.name
r=subprocess.run(['node','--check',tmp],capture_output=True,text=True)
print('inline html scripts:', 'PASS' if r.returncode==0 else 'FAIL', f'({len(scripts)} blocks)')
if r.stdout: print(r.stdout,end='')
if r.stderr: print(r.stderr,end='')
raise SystemExit(r.returncode)
