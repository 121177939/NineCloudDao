#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path('.pages-site').resolve();checks=[]
def ck(n,o): checks.append((n,bool(o)))
def txt(r): return (root/r).read_text('utf-8')
required=['.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','assets/icon-192.png','assets/icon-512.png','PAGES_ARTIFACT_MANIFEST.json']
for rel in required: ck(f'file:{rel}',(root/rel).is_file())
ck('version',txt('VERSION.txt').strip()=='V0.15.4')
ck('config-version',"version: '0.15.4'" in txt('config.js'))
ck('build','v0154-cache24' in txt('config.js'))
ck('epoch','cacheEpoch: 24' in txt('config.js'))
ck('index-cache','0154-cache24' in txt('index.html'))
ck('service-worker-cache','nine-cloud-dao-v0.15.4-cache24' in txt('sw.js'))
app=txt('app.js')
for name,token in {
 'instant-technique':'optimisticTechniqueUpgradeV0154',
 'rate-breakdown':'openCultivationRateBreakdownV0154',
 'treasure-shop':'get_treasure_shop_v0154',
 'washing-pill':'use_spirit_washing_pill_v0154',
 'pill-breakthrough':'attempt_breakthrough_v0154',
 'b02-collapse':'道果崩解0.3%',
 'treasure-instant':'applyTreasurePurchaseResultV0154',
 'treasure-immediate-toast':'已收入储物袋，可立即使用'
}.items(): ck(name,token in app)
manifest=json.loads(txt('PAGES_ARTIFACT_MANIFEST.json'))
ck('manifest-version',manifest.get('version')=='V0.15.4');ck('manifest-build',manifest.get('clientBuild')=='v0154-cache24')
for e in manifest.get('files',[]):
 p=root/e['path'];ck(f"hash:{e['path']}",p.is_file() and p.stat().st_size==e['size'] and hashlib.sha256(p.read_bytes()).hexdigest()==e['sha256'])
failed=[n for n,o in checks if not o]
print(json.dumps({'ok':not failed,'checks':len(checks),'failed':failed},ensure_ascii=False,indent=2));raise SystemExit(1 if failed else 0)
