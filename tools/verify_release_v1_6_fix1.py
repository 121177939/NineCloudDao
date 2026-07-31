#!/usr/bin/env python3
from pathlib import Path
import json,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def ck(n,v): checks.append((n,bool(v)))
def text(r): return (root/r).read_text('utf-8')
config=text('config.js');release=json.loads(text('release_config.json'));baseline=json.loads(text('CURRENT_BASELINE.json'));lock=json.loads(text('AB_CONTROL/BASELINE_LOCK.json'));manifest=json.loads(text('B_BASELINE/DEVELOPMENT_MANIFEST.json'))
ck('version-file',text('VERSION.txt').strip()=='V1.6 FIX1')
ck('config',all(x in config for x in ["version: '1.6.1'","releaseLabel: 'V1.6 FIX1 CACHE45'","buildId: 'v1-6-fix1-cache45'",'cacheEpoch: 45']))
ck('release-json',release.get('version')=='V1.6 FIX1' and release.get('cacheEpoch')==45 and release.get('clientBuild')=='v1-6-fix1-cache45')
ck('baseline-json',baseline.get('developmentBaseline')=='V1.6_FIX1_AB30_CACHE45' and baseline.get('cacheEpoch')==45 and baseline.get('sqlRevision')=='V1.6_FIX1_CACHE45')
ck('ab-lock',lock.get('baseline')=='V1.6_FIX1_AB30_CACHE45' and lock.get('databaseSqlRange')=='71-96')
ck('next-sql',manifest.get('nextSql')==97 and manifest.get('sourcePackage')=='Jiuxiao_V1.6_FIX1_CACHE45_Full.zip' and manifest.get('cacheEpoch')==45)
ck('upgrade-doc',(root/'V1.6_FIX1_升级说明.md').is_file() and (root/'V1.6_FIX1_SOURCE_CHANGE_REPORT.md').is_file())
ck('migration-files',all((root/r).is_file() for r in ['SQL/94_V1.6_FIX1_老何庄大小牌九盲牌.sql','SQL/95_V1.6_FIX1_CACHE45_正式发布门禁.sql','SQL/96_V1.6_FIX1_CACHE45_升级后检查.sql']))
ck('database-migrations',all((root/r).is_file() for r in ['database/V1.6_FIX1/202607310655_v1_6_fix1_laohe_blind_cards.sql','database/V1.6_FIX1/202607310700_v1_6_fix1_cache45_release.sql','database/V1.6_FIX1/202607310705_v1_6_fix1_cache45_check.sql']))
for n,v in checks: print(('PASS ' if v else 'FAIL ')+n)
failed=[n for n,v in checks if not v]
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(bool(failed))
