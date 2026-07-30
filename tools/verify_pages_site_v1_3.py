#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.pages-site').resolve();checks=[]
def ck(n,v): checks.append((n,bool(v)))
def text(r): return (root/r).read_text('utf-8')
required=['.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','b-paigow01.js','b-paigow01.css','b-paigow01.html','paigow-app.js','paigow-app.css','VERSION.txt','CURRENT_BASELINE.json','release_config.json','assets/icon-192.png','assets/icon-512.png','PAGES_ARTIFACT_MANIFEST.json']
for r in required: ck('required:'+r,(root/r).is_file() and not (root/r).is_symlink())
ck('version',text('VERSION.txt').strip()=='V1.3')
ck('config',all(x in text('config.js') for x in ["buildId: 'v1-3-cache41'",'cacheEpoch: 41']))
ck('index','b-paigow01.js?v=v1-3-cache41' in text('index.html'))
ck('iframe','paigow-app.js?v=v1-3-cache41' in text('b-paigow01.html'))
ck('sw','nine-cloud-dao-v1.3-cache41' in text('sw.js'))
manifest=json.loads(text('PAGES_ARTIFACT_MANIFEST.json'));ck('manifest-meta',manifest.get('version')=='V1.3 CACHE41' and manifest.get('clientBuild')=='v1-3-cache41')
for row in manifest.get('files',[]):
 p=root/row['path'];ck('hash:'+row['path'],p.is_file() and not p.is_symlink() and p.stat().st_size==row['size'] and hashlib.sha256(p.read_bytes()).hexdigest()==row['sha256'])
failed=[n for n,v in checks if not v]
for n,v in checks: print(('PASS ' if v else 'FAIL ')+n)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(bool(failed))
