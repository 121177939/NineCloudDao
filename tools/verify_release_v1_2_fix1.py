#!/usr/bin/env python3
from pathlib import Path
import json,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def ck(n,v):checks.append((n,bool(v)))
def text(r):return (root/r).read_text('utf-8')
required=['index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest','b-paigow01.js','b-paigow01.css','b-paigow01.html','paigow-app.js','paigow-app.css','VERSION.txt','CURRENT_BASELINE.json','release_config.json','V1.2_FIX1_CACHE38.txt','V1.2_FIX1_升级说明.md','docs/V1.2_FIX1_九霄灵牌规则.md','.github/workflows/deploy-pages.yml']+[f'SQL/{n}' for n in ['71_V1.2_FIX1_升级前检查.sql','72_V1.2_FIX1_九霄灵牌正式并线.sql','73_V1.2_FIX1_CACHE38_正式发布门禁.sql','74_V1.2_FIX1_升级后检查.sql','75_V1.2_FIX1_紧急停用九霄灵牌.sql','76_V1.2_FIX1_恢复九霄灵牌.sql']]
for r in required:ck('required:'+r,(root/r).is_file())
ck('version',text('VERSION.txt').strip()=='V1.2 FIX1')
config=text('config.js');ck('config',all(x in config for x in ["version: '1.2.1'","releaseLabel: 'V1.2 FIX1 CACHE38'","buildId: 'v1-2-fix1-cache38'",'cacheEpoch: 38']))
release=json.loads(text('release_config.json'));baseline=json.loads(text('CURRENT_BASELINE.json'));lock=json.loads(text('AB_CONTROL/BASELINE_LOCK.json'))
ck('release-json',release.get('version')=='V1.2 FIX1' and release.get('cacheEpoch')==38)
ck('baseline-json',baseline.get('developmentBaseline')=='V1.2_FIX1_AB23_CACHE38' and baseline.get('cacheEpoch')==38)
ck('lock-json',lock.get('baseline')=='V1.2_FIX1_AB23_CACHE38' and lock.get('databaseSqlRange')=='71-76')
for r in ['index.html','404.html','config.js','sw.js','manifest.webmanifest','update-guard.js','b-paigow01.html','b-paigow01.js']:
 ck('cache38:'+r,'v1-2-fix1-cache38' in text(r) or 'v1.2-fix1-cache38' in text(r))
ck('sw-paigow',all(x in text('sw.js') for x in ['b-paigow01.html','paigow-app.js','paigow-app.css']))
ck('workflow','python3 tools/ci_v1_2_fix1.py .' in text('.github/workflows/deploy-pages.yml'))
app=text('app.js');ck('paigow-entry','data-paigow-open' in app and '九霄灵牌' in app);ck('mutation-retained','mutationAttributeHtmlV12' in app);ck('casino-retained',all(x in app for x in ['100赔3320','正利润的50%','领取70%']))
failed=[n for n,v in checks if not v]
for n,v in checks:print(('PASS ' if v else 'FAIL ')+n)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(bool(failed))
