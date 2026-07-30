#!/usr/bin/env python3
from pathlib import Path
import json,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def ck(n,v): checks.append((n,bool(v)))
def text(r): return (root/r).read_text('utf-8')
config=text('config.js');release=json.loads(text('release_config.json'));baseline=json.loads(text('CURRENT_BASELINE.json'));lock=json.loads(text('AB_CONTROL/BASELINE_LOCK.json'));manifest=json.loads(text('B_BASELINE/DEVELOPMENT_MANIFEST.json'))
ck('version-file',text('VERSION.txt').strip()=='V1.5')
ck('config',all(x in config for x in ["version: '1.5.0'","releaseLabel: 'V1.5 CACHE43'","buildId: 'v1-5-cache43'",'cacheEpoch: 43']))
ck('release-json',release.get('version')=='V1.5' and release.get('cacheEpoch')==43 and release.get('clientBuild')=='v1-5-cache43')
ck('baseline-json',baseline.get('developmentBaseline')=='V1.5_AB28_CACHE43' and baseline.get('cacheEpoch')==43 and baseline.get('sqlRevision')=='V1.5_CACHE43')
ck('ab-lock',lock.get('baseline')=='V1.5_AB28_CACHE43' and lock.get('databaseSqlRange')=='71-90')
ck('next-sql',manifest.get('nextSql')==91 and manifest.get('sourcePackage')=='Jiuxiao_V1.5_CACHE43_Full.zip')
ck('upgrade-doc',(root/'V1.5_升级说明.md').is_file())
ck('migration-files',all((root/r).is_file() for r in ['SQL/88_V1.5_九霄牌九资金门槛与庄家比例结算.sql','SQL/89_V1.5_CACHE43_正式发布门禁.sql','SQL/90_V1.5_CACHE43_升级后检查.sql']))
for n,v in checks: print(('PASS ' if v else 'FAIL ')+n)
failed=[n for n,v in checks if not v]
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(bool(failed))
