#!/usr/bin/env python3
from pathlib import Path
import hashlib, json, shutil, sys, re
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve(); out=Path(sys.argv[2] if len(sys.argv)>2 else '.pages-site').resolve()
build='v2-2-0-cache129-tiandao-cloudflare-ai-admin36-sql259r2'; label='V2.2.0 CACHE129'
required=[
'.nojekyll','index.html','404.html','styles.css','b-tianxu-v220.css','b-tiandao-person-v220.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json',
'b-tiandao-person-v220.js','b-equipment01.js','b-equipment01.css','b-equipment-v210.js','b-equipment-v210.css','b-secret-realm01.js','b-secret-realm01.css','b-world-boss01.js','b-world-boss01.css','b-sect-v2.js','b-sect-v2.css','b-technique-v220.js','b-technique-v220.css',
'assets/icon-192.png','assets/icon-512.png','assets/secret-realm-portal.webp']
missing=[x for x in required if not (root/x).is_file()]
if missing: raise SystemExit('MISSING:'+','.join(missing))
def text(x): return (root/x).read_text('utf-8')
app=text('app.js'); idx=text('index.html'); styles=text('styles.css'); sw=text('sw.js'); bjs=text('b-tiandao-person-v220.js'); baseline=json.loads(text('CURRENT_BASELINE.json')); release=json.loads(text('release_config.json'))
casino_assets=['b-paigow01.js','b-paigow01.css','b-paigow01.html','b-paigow02-ui.css','b-paigow02-ui.js','b-paigow02-ui03.css','paigow-app.css','paigow-app.js','paigow-realtime.js']
legacy=['get_npc_social_v1','interact_with_npc_v1','form_npc_relationship_v1']
read_rpc=['get_tiandao_people_hub_v1','get_tiandao_person_detail_v1']; direct_write_rpc=['resolve_tiandao_encounter_v1','tiandao_npc_interact_v1','tiandao_romance_action_v1','tiandao_companion_action_v1']
checks={
'version':text('VERSION.txt').splitlines()[0]==label and build in text('VERSION.txt'),
'pages-lock':'PAGES_DEPLOY prebuilt-pages-directory-official-artifact-r1' in text('VERSION.txt'),
'config':all(x in text('config.js') for x in [label,build,'cacheEpoch: 129']),
'release-json':release.get('releaseLabel')==label and release.get('cacheEpoch')==129 and release.get('buildId')==build and release.get('nextSqlNumber')==260 and release.get('gmVersion')=='ADMIN9 R36' and release.get('minimumDatabaseSql')==259,
'baseline-json':baseline.get('releaseLabel')==label and baseline.get('nextSqlNumber')==260 and 'SQL259' in baseline.get('sqlRevision','') and baseline.get('gmVersion')=='ADMIN9 R36',
'index-tiandao':all(x in idx for x in ['b-tiandao-person-v220.css','b-tiandao-person-v220.js','<!-- version: V2.2.0 CACHE129 -->']),
'casino-assets-removed':not any((root/x).exists() for x in casino_assets),
'casino-runtime-removed':not re.search(r'casino|paigow|赌坊|赌场|鱼虾|灵骰|万运',app,re.I),
'tiandao-old-rpc-removed':not any(x in app for x in legacy),
'tiandao-social-container':all(x in app for x in ['九霄人物','缘遇 · 人物志 · 仙缘 · 道侣']) and '红尘录' not in app,
'tiandao-read-rpc':all(x in bjs for x in read_rpc),
'tiandao-direct-write-rpc-removed':not any(x in bjs for x in direct_write_rpc),
'tiandao-edge-ai':all(x in bjs for x in ['/functions/v1/tiandao-ai','tryEdgeAi',"mode:'interaction'","mode:'romance'","mode:'encounter'","mode:'companion'"]),
'tiandao-filter':all(x in bjs for x in ['data-tp-filter','peopleFilter','friend','confidant','enemy']),
'tiandao-multi-actions':'e.actions' in bjs and 'data-tp-encounter-action' in bjs,
'tiandao-observer-scoped':"document.getElementById('app')" in bjs and 'document.documentElement' not in bjs,
'tiandao-no-secret':not re.search(r'CLOUDFLARE_AUTH_TOKEN|CLOUDFLARE_ACCOUNT_ID|service_role|sb_secret_', '\n'.join(text(x) for x in ['app.js','b-tiandao-person-v220.js','config.js','index.html']),re.I),
'tianxu-rpcs':all(x in app for x in ['get_tianxu_market_v255','get_tianxu_listing_detail_v255','get_tianxu_sell_assets_v255','get_my_tianxu_v255','create_tianxu_listing_v255','buy_tianxu_listing_v255','cancel_tianxu_listing_v255']),
'tianxu-equipment-detail':all(x in app for x in ['tianxuEquipmentSnapshotHtmlV255','tianxu-socket-row-v255']),
'tianxu-compact-list':all(x in app for x in ['tianxu-grade-v255','tianxu-name-v255','tianxu-price-v255','data-tianxu-detail']),
'sw-new-assets':all(x in sw for x in ['b-tiandao-person-v220.css','b-tiandao-person-v220.js']) and not re.search(r'paigow|casino',sw,re.I),
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
