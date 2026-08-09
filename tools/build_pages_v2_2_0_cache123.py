#!/usr/bin/env python3
from pathlib import Path
import hashlib, json, shutil, sys, re
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve()
out=Path(sys.argv[2] if len(sys.argv)>2 else '.pages-site').resolve()
build='v2-2-0-cache123-technique-tabs-isolated-admin33-sql254-online'
label='V2.2.0 CACHE123'
required=[
'.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json',
'b-paigow01.js','b-paigow01.css','b-paigow01.html','b-equipment01.js','b-equipment01.css','b-equipment-v210.js','b-equipment-v210.css',
'b-secret-realm01.js','b-secret-realm01.css','b-world-boss01.js','b-world-boss01.css','b-sect-v2.js','b-sect-v2.css','b-technique-v220.js','b-technique-v220.css',
'paigow-realtime.js','paigow-app.js','paigow-app.css','b-paigow02-ui.css','b-paigow02-ui03.css','b-paigow02-ui.js',
'assets/icon-192.png','assets/icon-512.png','assets/secret-realm-portal.webp'
]
missing=[x for x in required if not (root/x).is_file()]
if missing: raise SystemExit('MISSING:'+','.join(missing))
def text(x): return (root/x).read_text('utf-8')
styles=text('styles.css'); app=text('app.js'); tech=text('b-technique-v220.js'); secret=text('b-secret-realm01.js'); boss=text('b-world-boss01.js')
baseline=json.loads(text('CURRENT_BASELINE.json')); release=json.loads(text('release_config.json'))
sql254=root/'database-upgrades/SQL254_V220_COMBAT_TECHNIQUES/01_SQL254_R5_V2.2.0_CACHE122_功法三系_黄品5pct与真实概率展示_执行即门禁.sql'
checks={
 'version':text('VERSION.txt').splitlines()[0]==label and build in text('VERSION.txt'),
 'pages-deploy-lock':'PAGES_DEPLOY default-github-pages-artifact-r3' in text('VERSION.txt'),
 'config':all(x in text('config.js') for x in [label,build,'cacheEpoch: 123']),
 'release-json':release.get('releaseLabel')==label and release.get('cacheEpoch')==123 and release.get('buildId')==build and release.get('nextSqlNumber')==255 and release.get('gmVersion')=='ADMIN9 R33',
 'baseline-json':baseline.get('releaseLabel')==label and baseline.get('nextSqlNumber')==255 and 'SQL254' in baseline.get('sqlRevision','') and baseline.get('deploymentMethod')=='github_actions_pages_default_artifact_r3_LOCKED_VERIFIED',
 'sql254-package':sql254.is_file(),
 'new-assets-index':all(x in text('index.html') for x in ['b-technique-v220.js','b-technique-v220.css','<!-- version: V2.2.0 CACHE123 -->']),
 'three-tabs':all(x in app for x in ['data-v220-tech-tab="cultivation"','data-v220-tech-tab="attack"','data-v220-tech-tab="defense"','combatTechniqueRootV220']),
 'strict-tab-isolation':all(x in tech for x in ["const combatTab=state.tab==='attack'||state.tab==='defense'","root.hidden=!combatTab","if(!combatTab){root.innerHTML='';return;}","pane(state.tab)"]),
 'strict-tab-hidden-css':'#combatTechniqueRootV220[hidden]' in text('b-technique-v220.css') and '[data-v220-cultivation-pane][hidden]' in text('b-technique-v220.css'),
 'compact-root-fate':app.count('class="path-card-v220"')>=2 and app.count('data-v220-path-open')>=2 and 'path-detail-source-v220' in app,
 'cultivation-server-cost':all(x in app for x in ['get_cultivation_technique_system_v220','upgrade_cultivation_technique_v220','get_exclusive_technique_system_v220','upgrade_exclusive_technique_v220']),
 'combat-system-rpcs':all(x in tech for x in ['get_combat_technique_system_v220','combine_combat_technique_shards_v220','learn_combat_technique_v220','set_combat_technique_equipped_v220','upgrade_combat_technique_v220','exchange_combat_technique_shards_v220']),
 'combat-grid':all(x in tech for x in ['technique-dao-grid-v220','attack','defense','10']),
 'combat-report-effects':'technique_effects' in app,
 'secret-shards':all(x in secret for x in ['combat_technique_shards_v220','功法残卷','向下取整']),
 'worldboss-shards':'combat_technique_shard_v220' in boss,
 'forge-fast-path-inherited':all(x in text('b-equipment-v210.js') for x in ['applySocketResult','client_elapsed_ms','正在洗炼…','SQL246 RPC自身在同一事务内强校验']),
 'equipment-state-inherited':all(x in text('b-equipment-v210.js') for x in ['get_equipment_forge_item_state_v247','requireBackpackCurrent','freshItem']),
 'pages-workflow-v220':all(x in text('.github/workflows/deploy-pages.yml') for x in [label,'build_pages_v2_2_0_cache123.py','b-technique-v220.js']),
 'sql254-effect-engine':sql254.is_file() and all(x in sql254.read_text('utf-8') for x in ['combat_technique_definitions_v220','effect_code','technique_effects','admin9_check_combat_technique_integration_v220','SQL254_GATE_PASSED']),
 'sql254-rate-schema':sql254.is_file() and all(x in sql254.read_text('utf-8') for x in ['main_rate+support_rate','opportunity_yellow_shard_rate','combat_technique_opportunity_shard_rate_v220','SQL254_GATE_YELLOW_SHARD_RATE_MISMATCH']),
 'sql254-opportunity-batch':sql254.is_file() and all(x in sql254.read_text('utf-8') for x in ['settlement_batch_id','opportunity_v3_results','SQL254_GATE_OPPORTUNITY_BATCH_ADAPTER_MISSING']),
 'no-sword-exclusive':'九霄问剑录' not in tech and (not sql254.is_file() or '九霄问剑录' not in sql254.read_text('utf-8')),
 'nine-cloud-stack':'九霄凌绝经' in tech or (sql254.is_file() and '九霄凌绝经' in sql254.read_text('utf-8')),
 'text-red':'.world-event-row.is-equipment-enhancement .world-event-copy p' in styles and 'color: #ef5f5f' in styles,
 'no-special-background':not re.search(r'\.world-event-row\.is-equipment-enhancement\s*\{[^}]*(background|border-left)',styles,re.S),
}
failed=[k for k,v in checks.items() if not v]
for k,v in checks.items(): print(('PASS ' if v else 'FAIL ')+k)
if failed: raise SystemExit('FAILED:'+','.join(failed))
if out.exists(): shutil.rmtree(out)
out.mkdir(parents=True)
for rel in required:
 src=root/rel; dst=out/rel; dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)
files=[]
for p in sorted(x for x in out.rglob('*') if x.is_file()):
 files.append({'path':p.relative_to(out).as_posix(),'size':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(out/'PAGES_ARTIFACT_MANIFEST.json').write_text(json.dumps({'version':label,'clientBuild':build,'files':files},ensure_ascii=False,indent=2)+'\n','utf-8')
print(f'{label} Pages artifact PASS files={len(files)}')
