#!/usr/bin/env python3
from pathlib import Path
import json,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def ck(n,v):checks.append((n,bool(v)))
def text(r):return (root/r).read_text('utf-8')
config=text('config.js');release=json.loads(text('release_config.json'));baseline=json.loads(text('CURRENT_BASELINE.json'));lock=json.loads(text('AB_CONTROL/BASELINE_LOCK.json'));manifest=json.loads(text('B_BASELINE/DEVELOPMENT_MANIFEST.json'))
ck('version-file',text('VERSION.txt').strip()=='V1.2 FIX3')
ck('config',all(x in config for x in ["version: '1.2.3'","releaseLabel: 'V1.2 FIX3 CACHE40'","buildId: 'v1-2-fix3-cache40'",'cacheEpoch: 40']))
ck('release-json',release.get('version')=='V1.2 FIX3' and release.get('cacheEpoch')==40 and release.get('clientBuild')=='v1-2-fix3-cache40')
ck('baseline-json',baseline.get('developmentBaseline')=='V1.2_FIX3_AB25_CACHE40' and baseline.get('cacheEpoch')==40 and baseline.get('sqlRevision')=='V1.2_FIX3_CACHE40')
ck('ab-lock',lock.get('baseline')=='V1.2_FIX3_AB25_CACHE40' and lock.get('databaseSqlRange')=='71-82')
ck('next-sql',manifest.get('nextSql')==83 and manifest.get('sourcePackage')=='Jiuxiao_V1.2_FIX3_CACHE40_Full.zip')
for n,v in checks:print(('PASS ' if v else 'FAIL ')+n)
failed=[n for n,v in checks if not v]
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(bool(failed))
