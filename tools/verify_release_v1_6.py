#!/usr/bin/env python3
from pathlib import Path
import json,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def ck(n,v): checks.append((n,bool(v)))
def text(r): return (root/r).read_text('utf-8')
config=text('config.js');release=json.loads(text('release_config.json'));baseline=json.loads(text('CURRENT_BASELINE.json'));lock=json.loads(text('AB_CONTROL/BASELINE_LOCK.json'));manifest=json.loads(text('B_BASELINE/DEVELOPMENT_MANIFEST.json'))
ck('version-file',text('VERSION.txt').strip()=='V1.6')
ck('config',all(x in config for x in ["version: '1.6.0'","releaseLabel: 'V1.6 CACHE44'","buildId: 'v1-6-cache44'",'cacheEpoch: 44']))
ck('release-json',release.get('version')=='V1.6' and release.get('cacheEpoch')==44 and release.get('clientBuild')=='v1-6-cache44')
ck('baseline-json',baseline.get('developmentBaseline')=='V1.6_AB29_CACHE44' and baseline.get('cacheEpoch')==44 and baseline.get('sqlRevision')=='V1.6_CACHE44')
ck('ab-lock',lock.get('baseline')=='V1.6_AB29_CACHE44' and lock.get('databaseSqlRange')=='71-93')
ck('next-sql',manifest.get('nextSql')==94 and manifest.get('sourcePackage')=='Jiuxiao_V1.6_CACHE44_Full.zip' and manifest.get('cacheEpoch')==44)
ck('upgrade-doc',(root/'V1.6_升级说明.md').is_file() and (root/'V1.6_SOURCE_CHANGE_REPORT.md').is_file())
ck('migration-files',all((root/r).is_file() for r in ['SQL/91_V1.6_九霄牌九事件驱动与主游戏隔离.sql','SQL/92_V1.6_CACHE44_正式发布门禁.sql','SQL/93_V1.6_CACHE44_升级后检查.sql']))
ck('database-migrations',all((root/r).is_file() for r in ['database/V1.6/202607302210_v1_6_paigow_event_driven.sql','database/V1.6/202607302220_v1_6_cache44_release.sql','database/V1.6/202607302230_v1_6_cache44_check.sql']))
for n,v in checks: print(('PASS ' if v else 'FAIL ')+n)
failed=[n for n,v in checks if not v]
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(bool(failed))
