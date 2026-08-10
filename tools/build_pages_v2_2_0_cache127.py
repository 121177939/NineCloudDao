#!/usr/bin/env python3
from pathlib import Path
import hashlib, json, shutil, sys, re
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve(); out=Path(sys.argv[2] if len(sys.argv)>2 else '.pages-site').resolve()
build='v2-2-0-cache127-tianxu-detail-admin34-sql258'; label='V2.2.0 CACHE127'
required=[
'.nojekyll','index.html','404.html','styles.css','b-tianxu-v220.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json',
'b-equipment01.js','b-equipment01.css','b-equipment-v210.js','b-equipment-v210.css','b-secret-realm01.js','b-secret-realm01.css','b-world-boss01.js','b-world-boss01.css','b-sect-v2.js','b-sect-v2.css','b-technique-v220.js','b-technique-v220.css',
'assets/icon-192.png','assets/icon-512.png','assets/secret-realm-portal.webp']
missing=[x for x in required if not (root/x).is_file()]
if missing: raise SystemExit('MISSING:'+','.join(missing))
def text(x): return (root/x).read_text('utf-8')
app=text('app.js'); idx=text('index.html'); styles=text('styles.css'); sw=text('sw.js'); baseline=json.loads(text('CURRENT_BASELINE.json')); release=json.loads(text('release_config.json'))
casino_assets=['b-paigow01.js','b-paigow01.css','b-paigow01.html','b-paigow02-ui.css','b-paigow02-ui.js','b-paigow02-ui03.css','paigow-app.css','paigow-app.js','paigow-realtime.js']
checks={
'version':text('VERSION.txt').splitlines()[0]==label and build in text('VERSION.txt'),
'pages-lock':'PAGES_DEPLOY prebuilt-pages-directory-official-artifact-r1' in text('VERSION.txt'),
'config':all(x in text('config.js') for x in [label,build,'cacheEpoch: 127']),
'release-json':release.get('releaseLabel')==label and release.get('cacheEpoch')==127 and release.get('buildId')==build and release.get('nextSqlNumber')==259 and release.get('gmVersion')=='ADMIN9 R34' and release.get('runtimeDatabaseGate')=='SQL258_GATE_PASSED',
'baseline-json':baseline.get('releaseLabel')==label and baseline.get('nextSqlNumber')==259 and 'SQL258' in baseline.get('sqlRevision','') and baseline.get('gmVersion')=='ADMIN9 R34',
'index-tianxu':all(x in idx for x in ['b-tianxu-v220.css','<!-- version: V2.2.0 CACHE127 -->']) and not any(x in idx.lower() for x in ['paigow','赌场','赌坊']),
'casino-assets-removed':not any((root/x).exists() for x in casino_assets),
'casino-runtime-removed':not re.search(r'casino|paigow|赌坊|赌场|鱼虾|灵骰|万运',app,re.I),
'casino-css-removed':not re.search(r'casino|paigow|赌坊|赌场|鱼虾|灵骰|万运',styles,re.I),
'tianxu-rpcs':all(x in app for x in ['get_tianxu_market_v255','get_tianxu_listing_detail_v255','get_tianxu_sell_assets_v255','get_my_tianxu_v255','create_tianxu_listing_v255','buy_tianxu_listing_v255','cancel_tianxu_listing_v255']),
'tianxu-equipment-detail':all(x in app for x in ['tianxuEquipmentSnapshotHtmlV255','开放 ${formatNumber(opened)} 孔','tianxu-socket-row-v255']) and all(x not in app[app.find('function tianxuEquipmentSnapshotHtmlV255'):app.find('async function openTianxuDetailV255')] for x in ['acquired_at','source_type','is_locked']),

'tianxu-compact-list':all(x in app for x in ['tianxu-grade-v255','tianxu-name-v255','tianxu-price-v255','data-tianxu-detail']) and 'seller_name' not in app[app.find('function tianxuListingsHtmlV255'):app.find('function tianxuBrowseHtmlV255')],
'sw-clean':'b-tianxu-v220.css' in sw and not re.search(r'paigow|casino',sw,re.I),
'old-technique-kept':all(x in app for x in ['data-v220-tech-tab="cultivation"','data-v220-tech-tab="attack"','data-v220-tech-tab="defense"']),
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(('PASS ' if v else 'FAIL ')+k)
if failed: raise SystemExit('FAILED:'+','.join(failed))
if out.exists(): shutil.rmtree(out)
out.mkdir(parents=True)
for rel in required:
 src=root/rel; dst=out/rel; dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)
files=[]
for p in sorted(x for x in out.rglob('*') if x.is_file()): files.append({'path':p.relative_to(out).as_posix(),'size':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(out/'PAGES_ARTIFACT_MANIFEST.json').write_text(json.dumps({'version':label,'clientBuild':build,'files':files},ensure_ascii=False,indent=2)+'\n','utf-8')
print(f'{label} Pages artifact PASS files={len(files)}')
