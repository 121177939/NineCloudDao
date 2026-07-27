from pathlib import Path
import json,re,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path.cwd(); checks=[]
def ck(name,ok,detail=''): checks.append((name,bool(ok),detail))
def txt(rel): return (root/rel).read_text('utf-8')
required=[
'index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest',
'VERSION.txt','CURRENT_BASELINE.json','release_config.json','README.md','CHANGELOG.md','DESKTOP_UPDATE.md','.nojekyll',
'.github/workflows/deploy-pages.yml','database/V0.14.3/202607271720_v0143_multi_ranking_wealth.sql',
'docs/V0.14.3_FINAL_RULES.md','docs/V0.14.3_DEPLOYMENT_GUIDE.md','docs/V0.14.3_SOURCE_CHANGE_REPORT.md','docs/V0.14.3_BUILD_VERIFY_REPORT.md','docs/V0.14.3_REAL_DEVICE_TEST_CHECKLIST.md',
'tools/prepare_pages_site_v0143.py','tools/verify_pages_site_v0143.py','tools/sql_static_audit_v0143.py','tools/test_ranking_render_v0143.js'
]
for rel in required: ck('file:'+rel,(root/rel).is_file())
app=txt('app.js'); sql=txt('database/V0.14.3/202607271720_v0143_multi_ranking_wealth.sql')
for token in ['rankingBoardTabsHtml','rankingCenterPanelHtml','rpcGetWealthRankingV1','refreshRankingBoard','修为榜','财富榜','战力榜暂未开放']:
 ck('app:'+token,token in app)
ck('no-manual-ranking-refresh','data-ranking-refresh' not in app and '刷新天命' not in app)
ck('no-periodic-ranking-refresh','state.destinyRankingSyncTimer = setInterval' not in app)
ck('entry-auto-refresh',"if (safeView === 'ranking' && previousView !== 'ranking')" in app and "refreshRankingBoard('cultivation', false, true)" in app)
ck('switch-auto-refresh',"if (safeBoard !== 'battle') refreshRankingBoard(safeBoard, false, true);" in app)
for token in ['get_wealth_ranking_v1','coalesce(stones.wealth, 0) desc',"release_name = 'V0.14.3 CACHE7'",'cache_epoch = greatest(cache_epoch, 7)']:
 ck('sql:'+token,token in sql)
ck('sql-transaction',bool(re.search(r'(?mi)^begin;\s*$',sql)) and bool(re.search(r'(?mi)^commit;\s*$',sql)))
ck('sql-dollar-pairs',sql.count('$$')%2==0,str(sql.count('$$')))
for rel in ['index.html','404.html','manifest.webmanifest','sw.js']:
 ck('build:'+rel,'0143-cache7' in txt(rel))
for rel in ['config.js','update-guard.js']:
 ck('build:'+rel,'v0143-cache7' in txt(rel))
ck('sw-cache',"CACHE_NAME = 'nine-cloud-dao-v0.14.3-cache7'" in txt('sw.js'))
ck('cache-epoch','cacheEpoch: 7' in txt('config.js'))
b=json.loads(txt('CURRENT_BASELINE.json')); r=json.loads(txt('release_config.json'))
ck('baseline',b.get('version')=='0.14.3' and b.get('databaseChange')=='MULTI_RANKING_WEALTH_V0143')
ck('release',r.get('clientBuild')=='v0143-cache7' and r.get('rankingBaseline')=='V0.14.3')
failed=[x for x in checks if not x[1]]
print(json.dumps({'ok':not failed,'checks':len(checks),'failed':[{'name':n,'detail':d} for n,_,d in failed]},ensure_ascii=False,indent=2))
raise SystemExit(1 if failed else 0)
