#!/usr/bin/env python3
from pathlib import Path
import hashlib, json, shutil, sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve()
out=Path(sys.argv[2] if len(sys.argv)>2 else '.pages-site').resolve()
build_id='v2-0-1-cache93-equipment-worldnews1-branchdeploy1'
label='V2.0.1 CACHE93'
required=[
 '.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js',
 'manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','PAGES_BRANCH_DEPLOY.txt',
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
app=text('app.js'); equipment=text('b-equipment01.js'); styles=text('styles.css'); paigow=text('paigow-app.js'); sect=text('b-sect-v2.js'); sw=text('sw.js')
baseline=json.loads(text('CURRENT_BASELINE.json')); release=json.loads(text('release_config.json'))
fixed_notice='服务器检查到当前游戏进行非法活动，已暂停此项功能。'
workflow=text('.github/workflows/deploy-pages.yml')
checks={
 'version':text('VERSION.txt').splitlines()[0].strip()==label and build_id in text('VERSION.txt'),
 'config':all(x in text('config.js') for x in [f"releaseLabel: '{label}'",f"buildId: '{build_id}'",'cacheEpoch: 93']),
 'baseline':baseline.get('clientHotfix')=='EQUIPMENT_WORLDNEWS1_BRANCHDEPLOY1' and baseline.get('gmVersion')=='ADMIN9 R20',
 'database':baseline.get('nextSqlNumber')==226 and str(baseline.get('sqlRevision'))=='211-221 + 224-225',
 'branch-deploy':baseline.get('deploymentMethod')=='github_pages_branch_main_root_no_custom_artifact' and 'Deploy from a branch' in text('README.md'),
 'no-pages-artifact-actions':all(x not in workflow for x in ['upload-pages-artifact','deploy-pages@','configure-pages@']) and 'workflow_dispatch' in workflow,
 'autonomy-dashboard':all(x in sect for x in ['get_sect_v2_dashboard_bsect06','sync_sect_v2_dashboard_bsect06','B-SECT06-AUTONOMY2000']),
 'autonomy-policy':all(x in sect for x in ['set_sect_autonomy_policy_bsect06','function autonomyHtml','弟子是自主生活与修炼的人物']),
 'master-assets':all(x in sect for x in ['contribute_sect_spirit_stones_bsect06','contribute_sect_inventory_item_bsect06','contribute_sect_equipment_bsect06','reward_sect_disciple_asset_bsect06']),
 'casino-status-rpc':'get_casino_feature_switch_v198' in app and 'refreshCasinoFeatureSwitchV198' in app,
 'casino-entry-gate':"target === 'casino'" in app and 'requireCasinoEnabledV198' in app,
 'casino-paigow-gate':'assertCasinoEnabledV198' in paigow and fixed_notice in paigow,
 'equipment-world-news':all(x in app for x in ['equipment_enhancement','is-equipment-enhancement','jiuxiao:world-events-dirty']) and all(x in equipment for x in ['jiuxiao:world-events-dirty','target_level || targetLevel']) and '.world-event-row.is-equipment-enhancement' in styles,
 'cache':'nine-cloud-dao-v2.0.1-cache93-equipment-worldnews1-branchdeploy1' in sw and build_id in sw,
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
(out/'STATIC_SITE_MANIFEST.json').write_text(json.dumps({'version':label,'clientBuild':build_id,'deploymentMethod':'main-root-branch','files':manifest},ensure_ascii=False,indent=2)+'\n','utf-8')
print(f'{label} static branch site build PASS files={len(manifest)}')
