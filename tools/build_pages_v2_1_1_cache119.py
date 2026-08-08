#!/usr/bin/env python3
from pathlib import Path
import hashlib, json, shutil, sys, re
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve()
out=Path(sys.argv[2] if len(sys.argv)>2 else '.pages-site').resolve()
build='v2-1-1-cache119-forgelistenerfix-equipmentstate-admin27-sql247'
label='V2.1.1 CACHE119'
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
 'config':all(x in text('config.js') for x in [label,build,'cacheEpoch: 119']),
 'release-json':release.get('releaseLabel')==label and release.get('cacheEpoch')==119 and release.get('buildId')==build and release.get('nextSqlNumber')==248,
 'database':baseline.get('nextSqlNumber')==248 and 'SQL247 ONLINE' in baseline.get('sqlRevision',''),
 'new-modules':all(x in text('index.html') for x in ['b-world-boss01.js','b-equipment-v210.js','b-world-boss01.css','b-equipment-v210.css']),
 'forge-ui2':all(x in text('b-equipment-v210.js') for x in ['reroll_equipment_socket_levels_v210','最多锁定3个孔位','data-forge-rules-open','runSocket','使用百炼']),
 'forge-ui2-no-single-level-button':'data-forge-level=' not in text('b-equipment-v210.js'),
 'total-stats-entry':'data-total-stats-entry' in text('app.js') and 'openTotalStatsV210' in text('app.js'),
 'total-stats-css':all(x in text('b-equipment-v210.css') for x in ['.total-stats-backdrop-v210','.total-stats-modal-v210','.total-stats-grid-v210']),
 'perf2':all(x in text('app.js') for x in ['heartbeatMs: 5 * 60 * 1000','cultivationSyncMs: 10 * 60 * 1000','cultivationEntryStaleMs: 2 * 60 * 1000','opportunityPollMs: 10 * 60 * 1000','marketSyncMs: 90 * 1000','worldEventsSyncMs: 5 * 60 * 1000','divineNoticeSyncMs: 5 * 60 * 1000','heavenBalanceSyncMs: 30 * 60 * 1000']),
 'perf2-visible-timers':all(x in text('app.js') for x in ['250)', '1000)']),
 'cache119-release':release.get('gmVersion')=='ADMIN9 R27' and release.get('migrationSql')==[245,246,247] and release.get('runtimeDatabaseGate')=='SQL247_GATE_PASSED_PRODUCTION_NO_NEW_SQL_FOR_CACHE119',
 'cache119-equipped-detail':"if (inBag) actions.push('<button class=\"primary-btn\" data-eq-action=\"forge\">孔位 / 升品 / 破境</button>');" in text('b-equipment01.js') and "inBag || equipped" not in text('b-equipment01.js'),
 'forge-cost-ui':all(x in text('b-equipment-v210.js') for x in ['weapon_reroll_spirit_stone_cost','armor_reroll_spirit_stone_cost','level_reroll_spirit_stone_cost','forge-status-v210']),
 'forge-backpack-only':"item.location!=='backpack'" in text('b-equipment-v210.js') and "socketOperable=['backpack','equipped']" not in text('b-equipment-v210.js'),
 'newborn-copy':all(x in text('app.js') for x in ['初生主灵根统一为五行杂灵根','命格与本命五行由天道在服务器端随机判定','初生五行杂灵根规则不限制后续洗灵']),
 'sql245-package':(root/'database-upgrades/SQL245_CACHE115_NEW_SERVER_RESET/245_V2.1.1_CACHE115_新服境界曲线_五行杂灵根_删档重开.sql').is_file(),
 'sql246-package':(root/'database-upgrades/SQL246_CACHE116_SOCKET_REROLL_FIX/246_V2.1.1_CACHE116_兵魄护道属性等级双随机与百炼防空转.sql').is_file(),
 'sql247-package':(root/'database-upgrades/SQL247_CACHE117_EQUIPMENT_STATE_UPGRADE_FIX/247_V2.1.1_CACHE117_装备背包状态与升品破境修复.sql').is_file(),
 'socket-reroll-v246':all(x in text('b-equipment-v210.js') for x in ['所有未锁孔同时重新随机属性类型与LV','孔位属性与等级已刷新','EQUIPMENT_V210_REROLL_NO_EFFECT_ROLLBACK']),
 'equipment-state-v247':all(x in text('b-equipment-v210.js') for x in ['get_equipment_forge_item_state_v247','requireBackpackCurrent','freshItem']) and 'refreshPromise' in text('b-equipment01.js'),
 'cache119-forge-listener-lifecycle':"const root=host().querySelector('.forge-backdrop-v210');" in text('b-equipment-v210.js') and "const item=state.item;" in text('b-equipment-v210.js') and "function bind(item)" not in text('b-equipment-v210.js') and "const root=host();" not in text('b-equipment-v210.js').split('function bind(){',1)[1].split('async function runSocket',1)[0],
 'pages-workflow-cache119':all(x in text('.github/workflows/deploy-pages.yml') for x in ['V2.1.1 CACHE119','build_pages_v2_1_1_cache119.py']) and 'build_pages_v2_1_1_cache116.py' not in text('.github/workflows/deploy-pages.yml'),
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
