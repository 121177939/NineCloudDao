#!/usr/bin/env python3
from pathlib import Path
import hashlib, json, shutil, sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();out=Path(sys.argv[2] if len(sys.argv)>2 else '.pages-site').resolve()
required=['.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','b-paigow01.js','b-paigow01.css','b-paigow01.html','b-equipment01.js','b-equipment01.css','b-secret-realm01.js','b-secret-realm01.css','paigow-realtime.js','paigow-app.js','paigow-app.css','b-paigow02-ui.css','b-paigow02-ui03.css','b-paigow02-ui.js','assets/icon-192.png','assets/icon-512.png']
for rel in required:
    if not (root/rel).is_file():raise SystemExit(f'MISSING:{rel}')
for rel in ['gm-admin.html','gm-admin.css','gm-admin.js','gm-operations.html','GM入口说明.txt']:
    if (root/rel).exists():raise SystemExit(f'LOCAL_GM_ASSET_NOT_ALLOWED_IN_PUBLIC_PAGES:{rel}')
def text(rel):return (root/rel).read_text('utf-8')
app=text('app.js');pg=text('paigow-app.js');b02=text('b-paigow02-ui.js');sw=text('sw.js');workflow=text('.github/workflows/deploy-pages.yml');baseline=json.loads(text('CURRENT_BASELINE.json'));release=json.loads(text('release_config.json'))
runtime=['index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest','b-paigow01.html','b-paigow01.js','b-equipment01.css','b-equipment01.js','b-secret-realm01.css','b-secret-realm01.js','paigow-app.js','paigow-realtime.js','paigow-app.css','b-paigow02-ui.css','b-paigow02-ui03.css','b-paigow02-ui.js']
texts=[text(x) for x in runtime];text_blob='\n'.join(texts);build_id='v1-7-8-2-cache58-caveui1';label='V1.7.8.2 CACHE58'
checks={
'version':text('VERSION.txt').strip()=='V1.7.8.2',
'config':all(t in text('config.js') for t in ["version: '1.7.8.2'","releaseLabel: 'V1.7.8.2 CACHE58'","buildId: 'v1-7-8-2-cache58-caveui1'",'cacheEpoch: 58']),
'deployment-enabled':baseline.get('deploymentStatus')=='formal_release' and release.get('deploymentAllowed') is True and baseline.get('sqlRevision')=='117-121',
'local-gm-mode':baseline.get('gmDeliveryMode')=='local_only' and release.get('gmDeliveryMode')=='local_only',
'index-assets':all(t in text('index.html') for t in ['<!-- version: V1.7.8.2 CACHE58 -->',f'b-secret-realm01.js?v={build_id}',f'b-equipment01.js?v={build_id}',f'b-paigow01.js?v={build_id}']),
'service-worker':all(t in sw for t in ['nine-cloud-dao-v1.7.8.2-cache58-caveui1',f'b-secret-realm01.js?v={build_id}',f'paigow-app.js?v={build_id}']) and all(t not in sw for t in ['gm-admin','gm-operations']),
'secret-realm-nav':all(t in app for t in ["['secret_realm', '秘', '秘境']",'id="secretRealmSection"','jiuxiao:secret-realm-rendered']),
'secret-realm-rpc':all(t in text('b-secret-realm01.js') for t in ['get_secret_realm_state_bsecretrealm01','enter_secret_realm_bsecretrealm01','settle_secret_realm_progress_bsecretrealm01']),
'secret-realm-live-config':all(t in text('b-secret-realm01.js') for t in ['live_config?.depths','equipmentRateText(data)','配置纪元']),
'paigow-version':label in pg,
'paigow-multipliers':all(t in pg for t in ['data-multiplier="10"','data-multiplier="30"','data-multiplier="50"','data-multiplier="100"','10、30、50、100倍']),
'paigow-ui03':all(t in text('b-paigow01.html') for t in ['<html class="b-paigow02-ui b-paigow02-ui03"',f'b-paigow02-ui03.css?v={build_id}',f'paigow-app.js?v={build_id}']),
'b02-no-network':all(t not in b02 for t in ['fetch(','XMLHttpRequest','WebSocket','setInterval(','MutationObserver']),
'workflow-builder':'python3 tools/build_pages_v1_7_8.py' in workflow,
'workflow-js':'gm-admin.js' not in workflow and 'b-secret-realm01.js' in workflow,
'no-old-build':not any(x in text_blob for x in ['v1-7-7-fix1-cache57','v1-7-8-cache58-equipfix2']),
'cave-workbench-default-visible':all(t in app for t in ['showCaveWorkbenchB01','caveWorkbenchB01\" class=\"cave-workbench-b01\" aria-hidden=\"false','不再依赖先点击灵脉或矿室']) and '<div data-cave-workbench-panel=\"buildings\">' in app,
'no-conflicts':not any('<<<<<<<' in x or '>>>>>>>' in x for x in texts)}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items():print(('PASS ' if v else 'FAIL ')+k)
if failed:raise SystemExit('VERSION_CHECK_FAILED:'+','.join(failed))
if out.exists():shutil.rmtree(out)
out.mkdir(parents=True)
for rel in required:
    src=root/rel;dst=out/rel;dst.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(src,dst)
manifest=[]
for path in sorted(x for x in out.rglob('*') if x.is_file()):
    if path.is_symlink():raise SystemExit(f'SYMLINK_NOT_ALLOWED:{path}')
    manifest.append({'path':path.relative_to(out).as_posix(),'size':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(out/'PAGES_ARTIFACT_MANIFEST.json').write_text(json.dumps({'version':label,'clientBuild':build_id,'deploymentAllowed':True,'gmDeliveryMode':'local_only','files':manifest},ensure_ascii=False,indent=2)+'\n','utf-8')
if any(out.rglob('*.sql')):raise SystemExit('SQL_NOT_ALLOWED_IN_PAGES')
if (out/'B_HANDOFF').exists():raise SystemExit('B_HANDOFF_NOT_ALLOWED_IN_PAGES')
if any((out/x).exists() for x in ['gm-admin.html','gm-admin.css','gm-admin.js','gm-operations.html']):raise SystemExit('LOCAL_GM_ASSET_LEAKED_TO_PAGES')
print(f'{label} public production pages build PASS files={len(manifest)}')
