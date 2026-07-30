#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path('.pages-site').resolve()
checks=[]
def ck(name,ok): checks.append((name,bool(ok)))
def text(rel): return (root/rel).read_text('utf-8')
required=['.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','assets/icon-192.png','assets/icon-512.png','PAGES_ARTIFACT_MANIFEST.json']
for rel in required: ck('file:'+rel,(root/rel).is_file())
ck('version',text('VERSION.txt').strip()=='V1.2')
ck('config',all(x in text('config.js') for x in ["version: '1.2'","buildId: 'v1-2-cache37'",'cacheEpoch: 37']))
ck('index-cache','v1-2-cache37' in text('index.html'))
ck('sw-cache','nine-cloud-dao-v1.2-cache37' in text('sw.js'))
app=text('app.js');css=text('styles.css')
ck('mutation-ui',all(x in app for x in ['mutationAttributeHtmlV12','变异灵根（${mutation}）','rpc/get_my_birth_result_v12']))
ck('mutation-colors',all(x in css for x in ['mutation-thunder','mutation-ice','mutation-wind']))
ck('casino-retained',all(x in app for x in ['100赔3320','100:97.5','正利润的50%','领取70%']))
manifest=json.loads(text('PAGES_ARTIFACT_MANIFEST.json'))
ck('manifest-version',manifest.get('version')=='V1.2 CACHE37')
ck('manifest-build',manifest.get('clientBuild')=='v1-2-cache37')
for entry in manifest.get('files',[]):
    p=root/entry['path']; ck('hash:'+entry['path'],p.is_file() and p.stat().st_size==entry['size'] and hashlib.sha256(p.read_bytes()).hexdigest()==entry['sha256'])
failed=[name for name,ok in checks if not ok]
print(json.dumps({'ok':not failed,'checks':len(checks),'failed':failed},ensure_ascii=False,indent=2))
raise SystemExit(1 if failed else 0)
