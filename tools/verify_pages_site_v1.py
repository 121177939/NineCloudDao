#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path('.pages-site').resolve();checks=[]
def ck(n,o):checks.append((n,bool(o)))
def t(r):return (root/r).read_text('utf-8')
req=['.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','assets/icon-192.png','assets/icon-512.png','PAGES_ARTIFACT_MANIFEST.json']
for r in req:ck('file:'+r,(root/r).is_file())
ck('version',t('VERSION.txt').strip()=='V1.0');ck('config',all(x in t('config.js') for x in ["version: '1.0'","buildId: 'v1-cache30'",'cacheEpoch: 30']))
ck('index-cache','v1-cache30' in t('index.html'));ck('sw-cache','nine-cloud-dao-v1.0-cache30' in t('sw.js'))
app=t('app.js');css=t('styles.css');ck('live-yuanshen','primordialSpiritPanelHtmlV1' in app and 'get_my_battle_snapshot_v1' in app);ck('cave-techniques','caveTechniqueBookStorageItemsV1' in app and 'cave-item-type-b01' in app);ck('mobile-grid','grid-template-columns:repeat(3,minmax(0,1fr))' in css);ck('battle-ui','challenge_battle_power_bcombat01' in app)
m=json.loads(t('PAGES_ARTIFACT_MANIFEST.json'));ck('manifest-version',m.get('version')=='V1.0 CACHE30');ck('manifest-build',m.get('clientBuild')=='v1-cache30')
for e in m.get('files',[]):
 p=root/e['path'];ck('hash:'+e['path'],p.is_file() and p.stat().st_size==e['size'] and hashlib.sha256(p.read_bytes()).hexdigest()==e['sha256'])
failed=[n for n,o in checks if not o];print(json.dumps({'ok':not failed,'checks':len(checks),'failed':failed},ensure_ascii=False,indent=2));raise SystemExit(1 if failed else 0)
