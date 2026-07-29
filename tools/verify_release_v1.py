#!/usr/bin/env python3
from pathlib import Path
import json,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def ck(n,o):checks.append((n,bool(o)))
def t(r):return (root/r).read_text('utf-8')
required=['index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','.github/workflows/deploy-pages.yml','SQL/26_V1.0_升级前检查.sql','SQL/27_V1.0_BCOMBAT01_五行战斗与越阶挑战.sql','SQL/28_V1.0_CACHE30_正式发布门禁.sql','SQL/29_V1.0_升级后检查.sql','SQL/30_V1.0_战斗挑战紧急停用.sql','SQL/31_V1.0_BCOMBAT01_完整回滚.sql','database/V1.0/202607291710_v1_bcombat01.sql','B_MODULE/B-COMBAT01/00_MODULE_README.md','tools/test_features_v1.js','tools/sql_static_audit_v1.py','tools/ci_v1.py']
for r in required:ck('required:'+r,(root/r).is_file())
ck('version',t('VERSION.txt').strip()=='V1.0')
for r in ['index.html','404.html','config.js','sw.js','manifest.webmanifest','update-guard.js']:ck('cache30:'+r,'v1-cache30' in t(r) or 'v1.0-cache30' in t(r))
c=t('config.js');ck('config',all(x in c for x in ["version: '1.0'","releaseLabel: 'V1.0 CACHE30'","buildId: 'v1-cache30'",'cacheEpoch: 30']))
r=json.loads(t('release_config.json'));b=json.loads(t('CURRENT_BASELINE.json'));ck('release-json',r.get('version')=='V1.0' and r.get('cacheEpoch')==30 and r.get('clientBuild')=='v1-cache30');ck('baseline-json',b.get('version')=='1.0' and b.get('developmentBaseline')=='V1.0_AB15_CACHE30')
wf=t('.github/workflows/deploy-pages.yml');ck('workflow','python3 tools/ci_v1.py .' in wf)
app=t('app.js');css=t('styles.css')
for name,tok in {'nav':"['primordial', '元', '元神']",'live-panel':'primordialSpiritPanelHtmlV1','snapshot':'get_my_battle_snapshot_v1','battle-ranking':'get_battle_power_ranking_bcombat01','battle-challenge':'challenge_battle_power_bcombat01','cave':'cave-depth-shrine-v1','technique-storage':'caveTechniqueBookStorageItemsV1','item-type':'cave-item-type-b01','inventory30':'CAVE_STORAGE_SLOT_COUNT_B01 = 30'}.items():ck('app-'+name,tok in app)
ck('mobile-three-columns','grid-template-columns:repeat(3,minmax(0,1fr))' in css)
ck('cave-animations',all(x in css for x in ['caveWaterfallV1','caveQiWispV1','caveFireflyV1','cavePondGlowV1']))
failed=[n for n,o in checks if not o]
for n,o in checks:print(('PASS ' if o else 'FAIL ')+n)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}');raise SystemExit(1 if failed else 0)
