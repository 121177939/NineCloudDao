#!/usr/bin/env python3
from pathlib import Path
import json,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def ck(n,o):checks.append((n,bool(o)))
def t(r):return (root/r).read_text('utf-8')
required=['index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','.github/workflows/deploy-pages.yml','SQL/32_V1.0_FIX1_升级前检查.sql','SQL/33_V1.0_FIX1_挑战战报参数兼容修复.sql','SQL/34_V1.0_FIX1_CACHE31_正式发布门禁.sql','SQL/35_V1.0_FIX1_升级后检查.sql','database/V1.0_FIX1/202607291830_v1_fix1_challenge_compat.sql','tools/test_features_v1_fix1.js','tools/sql_static_audit_v1_fix1.py','tools/ci_v1_fix1.py']
for r in required:ck('required:'+r,(root/r).is_file())
ck('version',t('VERSION.txt').strip()=='V1.0 FIX1')
for r in ['index.html','404.html','config.js','sw.js','manifest.webmanifest','update-guard.js']:ck('cache31:'+r,'v1-fix1-cache31' in t(r) or 'v1.0-fix1-cache31' in t(r))
c=t('config.js');ck('config',all(x in c for x in ["version: '1.0-fix1'","releaseLabel: 'V1.0 FIX1 CACHE31'","buildId: 'v1-fix1-cache31'",'cacheEpoch: 31']))
r=json.loads(t('release_config.json'));b=json.loads(t('CURRENT_BASELINE.json'));ck('release-json',r.get('version')=='V1.0 FIX1' and r.get('cacheEpoch')==31 and r.get('clientBuild')=='v1-fix1-cache31');ck('baseline-json',b.get('version')=='1.0-fix1' and b.get('developmentBaseline')=='V1.0_FIX1_AB16_CACHE31')
ck('workflow','python3 tools/ci_v1_fix1.py .' in t('.github/workflows/deploy-pages.yml'))
app=t('app.js');css=t('styles.css')
for n,tok in {'root-element':'heroSpiritRootChipHtmlV1','live-panel':'primordialSpiritPanelHtmlV1','battle':'challenge_battle_power_bcombat01','inventory36':'CAVE_STORAGE_SLOT_COUNT_B01 = 36'}.items():ck('app-'+n,tok in app)
ck('mobile-yuanshen-compress','min-height:294px' in css and 'width:min(100%,257px)' in css)
ck('cave-six-columns','grid-template-columns:repeat(6,minmax(0,1fr))' in css)
failed=[n for n,o in checks if not o]
for n,o in checks:print(('PASS ' if o else 'FAIL ')+n)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}');raise SystemExit(1 if failed else 0)
