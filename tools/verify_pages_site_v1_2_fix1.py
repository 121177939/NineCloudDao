#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path('.pages-site').resolve();checks=[]
def ck(n,v):checks.append((n,bool(v)))
def text(r):return (root/r).read_text('utf-8')
required=['.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','b-paigow01.js','b-paigow01.css','b-paigow01.html','paigow-app.js','paigow-app.css','VERSION.txt','CURRENT_BASELINE.json','release_config.json','assets/icon-192.png','assets/icon-512.png','PAGES_ARTIFACT_MANIFEST.json']
for r in required:ck('file:'+r,(root/r).is_file())
ck('version',text('VERSION.txt').strip()=='V1.2 FIX1');ck('config',all(x in text('config.js') for x in ["buildId: 'v1-2-fix1-cache38'",'cacheEpoch: 38']));ck('index','data-paigow-open' not in text('index.html') and 'b-paigow01.js?v=v1-2-fix1-cache38' in text('index.html'));ck('sw','nine-cloud-dao-v1.2-fix1-cache38' in text('sw.js'))
manifest=json.loads(text('PAGES_ARTIFACT_MANIFEST.json'));ck('manifest',manifest.get('version')=='V1.2 FIX1 CACHE38' and manifest.get('clientBuild')=='v1-2-fix1-cache38')
for e in manifest.get('files',[]):
 p=root/e['path'];ck('hash:'+e['path'],p.is_file() and p.stat().st_size==e['size'] and hashlib.sha256(p.read_bytes()).hexdigest()==e['sha256'])
failed=[n for n,v in checks if not v];print(json.dumps({'ok':not failed,'checks':len(checks),'failed':failed},ensure_ascii=False,indent=2));raise SystemExit(bool(failed))
