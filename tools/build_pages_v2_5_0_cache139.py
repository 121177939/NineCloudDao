#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,shutil,sys,re
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve(); out=Path(sys.argv[2] if len(sys.argv)>2 else '.pages-site').resolve()
build='v2-5-0-cache139-cave-modal-hub-admin41-sql267-gated'; label='V2.5.0 CACHE139'
required=['.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','b-equipment01.js','b-equipment01.css','b-equipment-v210.js','b-equipment-v210.css','b-secret-realm01.js','b-secret-realm01.css','b-world-boss01.js','b-world-boss01.css','b-sect-v2.js','b-sect-v2.css','b-technique-v220.js','b-technique-v220.css','b-tiandao-person-v220.js','b-tiandao-person-v220.css','b-exploration-v220.js','b-exploration-v220.css','b-spirit-beast-v250.js','b-spirit-beast-v250.css','exploration-story-catalog-v262.json','assets/icon-192.png','assets/icon-512.png','assets/secret-realm-portal.webp']
missing=[x for x in required if not (root/x).is_file()]
if missing: raise SystemExit('MISSING:'+','.join(missing))
def text(x): return (root/x).read_text('utf-8')
idx=text('index.html'); app=text('app.js'); beast=text('b-spirit-beast-v250.js'); sw=text('sw.js'); baseline=json.loads(text('CURRENT_BASELINE.json')); release=json.loads(text('release_config.json'))
sqlp=root/'database-upgrades/SQL267_SPIRIT_BEAST_COMPLETE/01_SQL267_V2.5.0_CACHE138_灵兽完整闭环_ADMIN9_R41_执行即门禁.sql'; sql=sqlp.read_text('utf-8')
gm=root/'九霄问道_ADMIN9_R41_V2.5.0_CACHE139_SQL267_灵兽完整管理_手机直用版.html'
checks={
'version':text('VERSION.txt').splitlines()[0]==label and build in text('VERSION.txt'),
'config':all(x in text('config.js') for x in [label,build,'cacheEpoch: 139']),
'release':release.get('releaseLabel')==label and release.get('cacheEpoch')==139 and release.get('buildId')==build and release.get('nextSqlNumber')==268 and release.get('gmVersion')=='ADMIN9 R41' and release.get('runtimeDatabaseGate')=='SQL267_GATE_PASSED',
'baseline':baseline.get('releaseLabel')==label and baseline.get('buildId')==build and baseline.get('nextSqlNumber')==268 and baseline.get('gmVersion')=='ADMIN9 R41' and baseline.get('androidVersionCode')==2001518,
'index':build in idx and '<!-- version: V2.5.0 CACHE139 -->' in idx and 'b-spirit-beast-v250.js' in idx and 'b-spirit-beast-v250.css' in idx,
'client':all(x in app for x in ['CACHE139','openCaveFeatureModalB01',"name: '炼丹'","name: '藏经'","name: '建筑'","name: '灵兽'","name: '待开辟'","name: '未开辟'",'cave-action-bar-compact-b01']) and 'id="caveWorkbenchB01"' not in app and all(x in beast for x in ['get_spirit_beast_hub_v267','spirit_beast_capture_v267','spirit_beast_hatch_egg_v267','spirit_beast_evolve_v267','spirit_beast_inherit_bloodline_v267','get_spirit_beast_ranking_v267']),
'sql':all(x in sql for x in ['SQL267_GATE_PASSED','spirit_beast_species_v267','spirit_beast_capture_v267','spirit_beast_process_exploration_v267','spirit_beast_process_secret_claim_v267','spirit_beast_process_world_boss_run_v267','admin9_check_spirit_beast_v267','SQL267_GATE_BCOMBAT_WRAPPER_MISSING']),
'gm':gm.is_file() and all(x in gm.read_text('utf-8') for x in ['ADMIN9 R41','admin9_get_spirit_beast_config_v267','admin9_check_spirit_beast_v267']),
'sw':build in sw and 'b-spirit-beast-v250.js' in sw and 'b-spirit-beast-v250.css' in sw,
'edge-secret-absent':not re.search(r'CLOUDFLARE_AUTH_TOKEN\s*=|CLOUDFLARE_ACCOUNT_ID\s*=',idx+beast+text('config.js')),
}
for k,v in checks.items(): print(('PASS ' if v else 'FAIL ')+k)
failed=[k for k,v in checks.items() if not v]
if failed: raise SystemExit('FAILED:'+','.join(failed))
if out.exists(): shutil.rmtree(out)
out.mkdir(parents=True)
for rel in required:
 src=root/rel; dst=out/rel; dst.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(src,dst)
files=[]
for p in sorted(x for x in out.rglob('*') if x.is_file()): files.append({'path':p.relative_to(out).as_posix(),'size':p.stat().st_size,'sha256':hashlib.sha256(p.read_bytes()).hexdigest()})
(out/'PAGES_ARTIFACT_MANIFEST.json').write_text(json.dumps({'version':label,'clientBuild':build,'requiredDatabaseGate':'SQL267_GATE_PASSED','gm':'ADMIN9 R41','files':files},ensure_ascii=False,indent=2)+'\n','utf-8')
print(f'{label} Pages artifact PASS files={len(files)}')
