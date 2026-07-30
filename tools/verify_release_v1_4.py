#!/usr/bin/env python3
from pathlib import Path
import json,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def ck(n,v): checks.append((n,bool(v)))
def text(r): return (root/r).read_text('utf-8')
config=text('config.js');release=json.loads(text('release_config.json'));baseline=json.loads(text('CURRENT_BASELINE.json'));lock=json.loads(text('AB_CONTROL/BASELINE_LOCK.json'));manifest=json.loads(text('B_BASELINE/DEVELOPMENT_MANIFEST.json'))
ck('version-file',text('VERSION.txt').strip()=='V1.4')
ck('config',all(x in config for x in ["version: '1.4.0'","releaseLabel: 'V1.4 CACHE42'","buildId: 'v1-4-cache42'",'cacheEpoch: 42']))
ck('release-json',release.get('version')=='V1.4' and release.get('cacheEpoch')==42 and release.get('clientBuild')=='v1-4-cache42')
ck('baseline-json',baseline.get('developmentBaseline')=='V1.4_AB27_CACHE42' and baseline.get('cacheEpoch')==42 and baseline.get('sqlRevision')=='V1.4_CACHE42')
ck('ab-lock',lock.get('baseline')=='V1.4_AB27_CACHE42' and lock.get('databaseSqlRange')=='71-87')
ck('next-sql',manifest.get('nextSql')==88 and manifest.get('sourcePackage')=='Jiuxiao_V1.4_CACHE42_Full.zip')
ck('upgrade-doc',(root/'V1.4_升级说明.md').is_file())
for n,v in checks: print(('PASS ' if v else 'FAIL ')+n)
failed=[n for n,v in checks if not v]
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(bool(failed))
