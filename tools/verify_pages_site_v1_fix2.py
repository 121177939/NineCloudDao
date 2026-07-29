#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path('.pages-site').resolve();checks=[]
def ck(n,o):checks.append((n,bool(o)))
def t(r):return (root/r).read_text('utf-8')
req=['.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','assets/icon-192.png','assets/icon-512.png','PAGES_ARTIFACT_MANIFEST.json']
for r in req:ck('file:'+r,(root/r).is_file())
ck('version',t('VERSION.txt').strip()=='V1.0 FIX2');ck('config',all(x in t('config.js') for x in ["version: '1.0-fix2'","buildId: 'v1-fix2-cache32'",'cacheEpoch: 32']))
ck('index-cache','v1-fix2-cache32' in t('index.html'));ck('sw-cache','nine-cloud-dao-v1.0-fix2-cache32' in t('sw.js'))
app=t('app.js');css=t('styles.css');ck('separate-report','showBattleResolvingModalBCombat01' in app and 'battle-report-modal-fix2' in app);ck('battle-privacy','battle-combatant-card-compact-fix2' in app and '道攻 ${formatNumber(row.dao_attack' not in app);ck('no-champion','修为榜首' not in app and '财富榜首' not in app and '战力榜首' not in app);ck('css-fix2','.battle-combatant-public-fix2' in css and '.battle-report-modal-fix2' in css)
m=json.loads(t('PAGES_ARTIFACT_MANIFEST.json'));ck('manifest-version',m.get('version')=='V1.0 FIX2 CACHE32');ck('manifest-build',m.get('clientBuild')=='v1-fix2-cache32')
for e in m.get('files',[]):
 p=root/e['path'];ck('hash:'+e['path'],p.is_file() and p.stat().st_size==e['size'] and hashlib.sha256(p.read_bytes()).hexdigest()==e['sha256'])
failed=[n for n,o in checks if not o];print(json.dumps({'ok':not failed,'checks':len(checks),'failed':failed},ensure_ascii=False,indent=2));raise SystemExit(1 if failed else 0)
