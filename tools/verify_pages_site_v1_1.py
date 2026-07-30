#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path('.pages-site').resolve();checks=[]
def ck(n,o):checks.append((n,bool(o)))
def t(r):return (root/r).read_text('utf-8')
req=['.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','assets/icon-192.png','assets/icon-512.png','PAGES_ARTIFACT_MANIFEST.json']
for x in req:ck('file:'+x,(root/x).is_file())
ck('version',t('VERSION.txt').strip()=='V1.1')
ck('config',all(x in t('config.js') for x in ["version: '1.1'","buildId: 'v1-1-cache35'",'cacheEpoch: 35']))
ck('index-cache','v1-1-cache35' in t('index.html'));ck('sw-cache','nine-cloud-dao-v1.1-cache35' in t('sw.js'))
app=t('app.js');ck('challenge-rules','高低战力均可互相挑战' in app and '可以重复挑战同一对手' in app)
ck('casino-fix4','rpc/play_house_game_v1_fix4' in app and 'rpc/place_fish_shrimp_bet_v1_fix4' in app)
m=json.loads(t('PAGES_ARTIFACT_MANIFEST.json'));ck('manifest-version',m.get('version')=='V1.1 CACHE35');ck('manifest-build',m.get('clientBuild')=='v1-1-cache35')
for e in m.get('files',[]):
 p=root/e['path'];ck('hash:'+e['path'],p.is_file() and p.stat().st_size==e['size'] and hashlib.sha256(p.read_bytes()).hexdigest()==e['sha256'])
failed=[n for n,o in checks if not o];print(json.dumps({'ok':not failed,'checks':len(checks),'failed':failed},ensure_ascii=False,indent=2));raise SystemExit(1 if failed else 0)
