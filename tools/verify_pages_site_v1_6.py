#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.pages-site').resolve();checks=[]
def ck(n,v): checks.append((n,bool(v)))
def text(r): return (root/r).read_text('utf-8')
required=['.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','b-paigow01.js','b-paigow01.css','b-paigow01.html','paigow-realtime.js','paigow-app.js','paigow-app.css','VERSION.txt','CURRENT_BASELINE.json','release_config.json','assets/icon-192.png','assets/icon-512.png','PAGES_ARTIFACT_MANIFEST.json']
ck('required-files',all((root/r).is_file() for r in required))
ck('config',all(x in text('config.js') for x in ["buildId: 'v1-6-cache44'",'cacheEpoch: 44']))
ck('index','b-paigow01.js?v=v1-6-cache44' in text('index.html'))
ck('iframe','paigow-realtime.js?v=v1-6-cache44' in text('b-paigow01.html') and 'paigow-app.js?v=v1-6-cache44' in text('b-paigow01.html'))
ck('sw','nine-cloud-dao-v1.6-cache44' in text('sw.js') and 'paigow-realtime.js?v=v1-6-cache44' in text('sw.js'))
ck('no-sql-in-pages',not any(root.rglob('*.sql')))
manifest=json.loads(text('PAGES_ARTIFACT_MANIFEST.json'));ck('manifest-meta',manifest.get('version')=='V1.6 CACHE44' and manifest.get('clientBuild')=='v1-6-cache44')
actual={p.relative_to(root).as_posix():hashlib.sha256(p.read_bytes()).hexdigest() for p in root.rglob('*') if p.is_file() and p.name!='PAGES_ARTIFACT_MANIFEST.json'}
listed={x['path']:x['sha256'] for x in manifest.get('files',[])}
ck('manifest-hashes',all(actual.get(k)==v for k,v in listed.items()) and len(listed)==len(actual))
for n,v in checks: print(('PASS ' if v else 'FAIL ')+n)
failed=[n for n,v in checks if not v]
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(bool(failed))
