#!/usr/bin/env python3
from pathlib import Path
import hashlib, json, shutil, sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve()
out=Path(sys.argv[2] if len(sys.argv)>2 else '.pages-site').resolve()
build_id='v2-0-0-cache91-bsect06-autonomy2000-dbmaint1'
label='V2.0.0 CACHE91'
required=[
 '.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js',
 'manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json',
 'b-paigow01.js','b-paigow01.css','b-paigow01.html','b-equipment01.js','b-equipment01.css',
 'b-secret-realm01.js','b-secret-realm01.css','b-sect-v2.js','b-sect-v2.css',
 'paigow-realtime.js','paigow-app.js','paigow-app.css','b-paigow02-ui.css','b-paigow02-ui03.css',
 'b-paigow02-ui.js','assets/icon-192.png','assets/icon-512.png','assets/secret-realm-portal.webp'
]
missing=[x for x in required if not (root/x).is_file()]
if missing: raise SystemExit('MISSING_REQUIRED_FILES:'+','.join(missing))
for rel in ['gm-admin.html','gm-admin.css','gm-admin.js','gm-operations.html','GM入口说明.txt']:
 if (root/rel).exists(): raise SystemExit('LOCAL_GM_ASSET_NOT_ALLOWED_IN_PUBLIC_PAGES:'+rel)
def text(rel): return (root/rel).read_text('utf-8')
app=text('app.js'); paigow=text('paigow-app.js'); sect=text('b-sect-v2.js'); sw=text('sw.js')
baseline=json.loads(text('CURRENT_BASELINE.json')); release=json.loads(text('release_config.json'))
fixed_notice='服务器检查到当前游戏进行非法活动，已暂停此项功能。'
checks={
 'version':text('VERSION.txt').splitlines()[0].strip()==label and build_id in text('VERSION.txt'),
 'config':all(x in text('config.js') for x in [f"releaseLabel: '{label}'",f"buildId: '{build_id}'",'cacheEpoch: 91']),
 'baseline':baseline.get('sourceBaseline')=='V1.8.7 CACHE89 + SQL210' and baseline.get('clientHotfix')=='BSECT06_AUTONOMY2000_DBMAINT1' and baseline.get('gmVersion')=='ADMIN9 R20',
 'database':baseline.get('nextSqlNumber')==221 and str(baseline.get('sqlRevision'))=='211-220',
 'autonomy-dashboard':all(x in sect for x in ['get_sect_v2_dashboard_bsect06','sync_sect_v2_dashboard_bsect06','B-SECT06-AUTONOMY2000']),
 'autonomy-policy':all(x in sect for x in ['set_sect_autonomy_policy_bsect06','function autonomyHtml','弟子是自主生活与修炼的人物']),
 'master-assets':all(x in sect for x in ['contribute_sect_spirit_stones_bsect06','contribute_sect_inventory_item_bsect06','contribute_sect_equipment_bsect06','reward_sect_disciple_asset_bsect06']),
 'event-ui':all(x in sect for x in ['宗门动态','宗主案牍','function chronicleHtml','ordinary_hard_cap_per_sect']),
 'casino-status-rpc':'get_casino_feature_switch_v198' in app and 'refreshCasinoFeatureSwitchV198' in app,
 'casino-entry-gate':"target === 'casino'" in app and 'requireCasinoEnabledV198' in app,
 'casino-paigow-gate':'assertCasinoEnabledV198' in paigow and fixed_notice in paigow,
 'casino-fixed-notice':fixed_notice in app,
 'heartbeat':'PERF_E80.heartbeatMs' in app and 'heartbeatMs: 30 * 1000' in app,
 'polling':all(x in app for x in ['cultivationSyncMs: 60 * 1000','opportunityPollMs: 60 * 1000','worldEventsSyncMs: 60 * 1000','divineNoticeSyncMs: 60 * 1000']),
 'on-demand':all(x in app for x in ['refreshActiveTabDataE80','洞府、功法、红尘、宗门不再全局轮询','resumeCooldownMs: 15 * 1000']),
 'games-preserved':all((root/x).is_file() for x in ['b-paigow01.js','b-paigow01.html','paigow-app.js']) and 'rpcGetFishShrimpStateV0148' in app,
 'cache':'nine-cloud-dao-v2.0.0-cache91-bsect06-autonomy2000-dbmaint1' in sw and build_id in sw,
 'no-secrets':'sb_secret_' not in '\n'.join(text(x) for x in ['app.js','config.js','index.html']).lower(),
 'deployment':release.get('deploymentAllowed') is True and release.get('gmPublicDeployment') is False,
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(('PASS ' if v else 'FAIL ')+k)
if failed: raise SystemExit('VERSION_CHECK_FAILED:'+','.join(failed))
if out.exists(): shutil.rmtree(out)
out.mkdir(parents=True)
for rel in required:
 src=root/rel; dst=out/rel; dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)
manifest=[]
for path in sorted(x for x in out.rglob('*') if x.is_file()):
 manifest.append({'path':path.relative_to(out).as_posix(),'size':path.stat().st_size,'sha256':hashlib.sha256(path.read_bytes()).hexdigest()})
(out/'PAGES_ARTIFACT_MANIFEST.json').write_text(json.dumps({'version':label,'clientBuild':build_id,'deploymentAllowed':True,'gmDeliveryMode':'local_only','files':manifest},ensure_ascii=False,indent=2)+'\n','utf-8')
print(f'{label} public production pages build PASS files={len(manifest)}')
