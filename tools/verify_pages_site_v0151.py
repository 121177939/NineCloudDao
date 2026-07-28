#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path('.pages-site').resolve();checks=[]
def ck(n,o):checks.append((n,bool(o)))
def txt(r):return(root/r).read_text('utf-8')
req=['.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','assets/icon-192.png','assets/icon-512.png','PAGES_ARTIFACT_MANIFEST.json']
for r in req:ck('file:'+r,(root/r).is_file())
ck('version',txt('VERSION.txt').strip()=='V0.15.1');ck('cache','v0151-cache18' in txt('config.js'));ck('epoch','cacheEpoch: 18' in txt('config.js'))
ck('40 sec client','elapsed/40*100' in txt('app.js') and '公共40秒轮次' in txt('app.js'))
ck('30 2 5 3 client',all(x in txt('app.js') for x in ['前30秒下注','随后2秒封盘','5秒依次开骰','start + 30000','start + 32000','start + 37000']))
ck('continuous queue','enqueueFishShrimpBetV0150' in txt('app.js') and 'processFishShrimpBetQueueV0150' in txt('app.js'))
ck('responsive','width: min(100%, 460px)' not in txt('styles.css') and '.fish-game-shell {' in txt('styles.css') and 'max-width: none;' in txt('styles.css'))
m=json.loads(txt('PAGES_ARTIFACT_MANIFEST.json'));ck('manifest',m.get('clientBuild')=='v0151-cache18')
for e in m.get('files',[]):
 p=root/e['path'];ck('hash:'+e['path'],p.is_file() and p.stat().st_size==e['size'] and hashlib.sha256(p.read_bytes()).hexdigest()==e['sha256'])
failed=[n for n,o in checks if not o];print(json.dumps({'ok':not failed,'checks':len(checks),'failed':failed},ensure_ascii=False,indent=2));raise SystemExit(1 if failed else 0)
