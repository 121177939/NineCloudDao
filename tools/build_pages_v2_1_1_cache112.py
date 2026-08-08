#!/usr/bin/env python3
from pathlib import Path
import hashlib, json, shutil, sys, re
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve()
out=Path(sys.argv[2] if len(sys.argv)>2 else '.pages-site').resolve()
build='v2-1-1-cache112-perf2-dbcap03-admin23-sql241'
label='V2.1.1 CACHE112'
required=[
'.nojekyll','index.html','404.html','styles.css','app.js','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json',
'b-paigow01.js','b-paigow01.css','b-paigow01.html','b-equipment01.js','b-equipment01.css','b-equipment-v210.js','b-equipment-v210.css',
'b-secret-realm01.js','b-secret-realm01.css','b-world-boss01.js','b-world-boss01.css','b-sect-v2.js','b-sect-v2.css',
'paigow-realtime.js','paigow-app.js','paigow-app.css','b-paigow02-ui.css','b-paigow02-ui03.css','b-paigow02-ui.js',
'assets/icon-192.png','assets/icon-512.png','assets/secret-realm-portal.webp'
]
missing=[x for x in required if not (root/x).is_file()]
if missing: raise SystemExit('MISSING:'+','.join(missing))
def text(x): return (root/x).read_text('utf-8')
styles=text('styles.css'); baseline=json.loads(text('CURRENT_BASELINE.json')); release=json.loads(text('release_config.json'))
checks={
 'version':text('VERSION.txt').splitlines()[0]==label and build in text('VERSION.txt'),
 'config':all(x in text('config.js') for x in [label,build,'cacheEpoch: 112']),
 'release-json':release.get('releaseLabel')==label and release.get('cacheEpoch')==112 and release.get('buildId')==build and release.get('nextSqlNumber')==242,
 'database':baseline.get('nextSqlNumber')==242 and baseline.get('sqlRevision')=='211-221 + 229-241',
 'new-modules':all(x in text('index.html') for x in ['b-world-boss01.js','b-equipment-v210.js','b-world-boss01.css','b-equipment-v210.css']),
 'forge-ui2':all(x in text('b-equipment-v210.js') for x in ['reroll_equipment_socket_levels_v210','最多锁定3个孔位','data-forge-rules-open','runSocket','使用百炼']),
 'forge-ui2-no-single-level-button':'data-forge-level=' not in text('b-equipment-v210.js'),
 'total-stats-entry':'data-total-stats-entry' in text('app.js') and 'openTotalStatsV210' in text('app.js'),
 'total-stats-css':all(x in text('b-equipment-v210.css') for x in ['.total-stats-backdrop-v210','.total-stats-modal-v210','.total-stats-grid-v210']),
 'perf2':all(x in text('app.js') for x in ['heartbeatMs: 5 * 60 * 1000','cultivationSyncMs: 10 * 60 * 1000','cultivationEntryStaleMs: 2 * 60 * 1000','opportunityPollMs: 10 * 60 * 1000','marketSyncMs: 90 * 1000','worldEventsSyncMs: 5 * 60 * 1000','divineNoticeSyncMs: 5 * 60 * 1000','heavenBalanceSyncMs: 30 * 60 * 1000']),
 'perf2-visible-timers':all(x in text('app.js') for x in ['250)', '1000)']),
 'dbcap03-release':release.get('gmVersion')=='ADMIN9 R23' and release.get('migrationSql')==[241] and release.get('runtimeDatabaseGate')=='SQL241_PENDING_USER_EXECUTION',
 'dbcap03-sql-files':(root/'database-upgrades/SQL241_CACHE112_DBCAP03_PERF2/241_V2.1.1_CACHE112_DBCAP03_PERF2_数据库稳定与24小时治理.sql').is_file() and (root/'database-upgrades/SQL241_CACHE112_DBCAP03_PERF2/门禁_V2.1.1_CACHE112_SQL241_DBCAP03_PERF2_数据库稳定.sql').is_file(),
 'db-health-files':(root/'数据库管理_CACHE112/数据库健康检查_只读.sql').is_file() and (root/'数据库管理_CACHE112/PERF热点RPC与临时IO_只读_可选.sql').is_file(),
 'text-red':'.world-event-row.is-equipment-enhancement .world-event-copy p' in styles and 'color: #ef5f5f' in styles,
 'no-special-background':not re.search(r'\.world-event-row\.is-equipment-enhancement\s*\{[^}]*(background|border-left)',styles,re.S),
 'pages-method':baseline.get('deploymentMethod')=='github_actions_pages_default_artifact_r3_LOCKED_VERIFIED'
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
