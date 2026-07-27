from pathlib import Path
import json,re,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path.cwd(); checks=[]
def ck(name,ok,detail=''): checks.append((name,bool(ok),detail))
def txt(rel): return (root/rel).read_text('utf-8')
required=[
'index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest',
'VERSION.txt','CURRENT_BASELINE.json','release_config.json','README.md','CHANGELOG.md','DESKTOP_UPDATE.md','.nojekyll',
'.github/workflows/deploy-pages.yml','database/V0.14.2/202607270900_v0142_world_feed_strict_newest.sql',
'docs/V0.14.2_FINAL_RULES.md','docs/V0.14.2_DEPLOYMENT_GUIDE.md','docs/V0.14.2_SOURCE_CHANGE_REPORT.md',
'tools/prepare_pages_site_v0142.py','tools/verify_pages_site_v0142.py','tools/sql_static_audit_v0142.py','tools/test_world_events_render_v0142.js'
]
for rel in required: ck('file:'+rel,(root/rel).is_file())
app=txt('app.js'); sql=txt('database/V0.14.2/202607270900_v0142_world_feed_strict_newest.sql')
for token in ['sortWorldEventEntriesNewestFirst','feed_sequence','rpcGetWorldEventsV1(limit = 30)','严格按最新消息排序，新消息永远置顶']:
 ck('app:'+token,token in app)
ck('poll-10s','state.worldEventsSyncTimer = setInterval(() => { if (!document.hidden) refreshWorldEvents(true); }, 10000);' in app)
for token in ['jiuxiao_world_events_feed_sequence_seq','order by e.feed_sequence desc',"'sort_mode', 'strict_newest_first'",'rpc_does_not_prioritize_pinned',"release_name = 'V0.14.2 CACHE6'"]:
 ck('sql:'+token,token in sql)
ck('sql-transaction',bool(re.search(r'(?mi)^begin;\s*$',sql)) and bool(re.search(r'(?mi)^commit;\s*$',sql)))
ck('sql-dollar-pairs',sql.count('$$')%2==0,str(sql.count('$$')))
for rel in ['index.html','404.html','manifest.webmanifest','sw.js']:
 ck('build:'+rel,'0142-cache6' in txt(rel))
for rel in ['config.js','update-guard.js']:
 ck('build:'+rel,'v0142-cache6' in txt(rel))
ck('sw-cache',"CACHE_NAME = 'nine-cloud-dao-v0.14.2-cache6'" in txt('sw.js'))
ck('cache-epoch','cacheEpoch: 6' in txt('config.js'))
b=json.loads(txt('CURRENT_BASELINE.json')); r=json.loads(txt('release_config.json'))
ck('baseline',b.get('version')=='0.14.2' and b.get('databaseChange')=='WORLD_FEED_STRICT_NEWEST_FIRST_V0142')
ck('release',r.get('clientBuild')=='v0142-cache6' and r.get('worldFeedBaseline')=='V0.14.2')
failed=[x for x in checks if not x[1]]
print(json.dumps({'ok':not failed,'checks':len(checks),'failed':[{'name':n,'detail':d} for n,_,d in failed]},ensure_ascii=False,indent=2))
raise SystemExit(1 if failed else 0)
