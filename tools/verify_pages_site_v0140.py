from pathlib import Path
import hashlib, json, re, sys

root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path('.pages-site').resolve()
checks=[]
def check(name,ok,detail=''): checks.append((name,bool(ok),detail))
def text(path): return (root/path).read_text('utf-8')
required=['.nojekyll','index.html','404.html','styles.css','app.js','config.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','assets/icon-192.png','assets/icon-512.png','PAGES_ARTIFACT_MANIFEST.json']
for f in required: check('file:'+f,(root/f).is_file())
check('version',text('VERSION.txt').strip()=='V0.14.0')
check('html-version','0.14.0' in text('index.html') and '0.14.0' in text('404.html'))
check('sw-cache','nine-cloud-dao-v0.14.0' in text('sw.js'))
for banned in ['.git','.github','database','docs','tools']:
    check('not-deployed:'+banned,not (root/banned).exists())
for ext in ['*.sql','*.py','*.zip']:
    check('no:'+ext,len(list(root.rglob(ext)))==0)
manifest=json.loads(text('PAGES_ARTIFACT_MANIFEST.json'))
check('manifest.version',manifest.get('version')=='V0.14.0')
for entry in manifest.get('files',[]):
    p=root/entry['path']
    ok=p.is_file() and p.stat().st_size==entry['size'] and hashlib.sha256(p.read_bytes()).hexdigest()==entry['sha256']
    check('hash:'+entry['path'],ok)
html=text('index.html')
for ref in ['styles.css','app.js','config.js','manifest.webmanifest','assets/icon-192.png']:
    check('html-ref:'+ref,ref in html and (root/ref).is_file())
failed=[x for x in checks if not x[1]]
for n,ok,d in checks: print(('PASS' if ok else 'FAIL'),n,d)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
sys.exit(1 if failed else 0)
