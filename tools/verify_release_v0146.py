from pathlib import Path
import json,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path.cwd(); checks=[]
def ck(n,o): checks.append((n,bool(o)))
def txt(r): return (root/r).read_text('utf-8')
required=['index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','database/V0.14.6/202607280230_v0146_opportunity_history_detail.sql','docs/V0.14.6_FINAL_RULES.md','docs/V0.14.6_DEPLOYMENT_GUIDE.md']
for r in required: ck('file:'+r,(root/r).is_file())
app=txt('app.js'); sql=txt('database/V0.14.6/202607280230_v0146_opportunity_history_detail.sql')
for token in ['rpcGetOpportunityHistoryV0146','mergeHistoryWithOpportunityResults','refreshOpportunityHistoryTimeline','result?.result_text','historyTimelineRoot']: ck('app:'+token,token in app)
for token in ['get_opportunity_history_v0146','opportunity_v3_results','opportunity_v4','deferrable initially deferred','CACHE10']: ck('sql:'+token,token in sql)
for r in ['index.html','404.html','sw.js','manifest.webmanifest']: ck('cache:'+r,'0146-cache10' in txt(r))
ck('config-build',"buildId: 'v0146-cache10'" in txt('config.js'))
ck('version',txt('VERSION.txt').strip()=='V0.14.6')
rc=json.loads(txt('release_config.json')); b=json.loads(txt('CURRENT_BASELINE.json'))
ck('release-json',rc.get('clientBuild')=='v0146-cache10')
ck('baseline-json',b.get('clientHotfix')=='V0.14.6_OPPORTUNITY_HISTORY_DETAIL_CACHE10')
failed=[n for n,o in checks if not o]
print(json.dumps({'ok':not failed,'checks':len(checks),'failed':failed},ensure_ascii=False,indent=2)); raise SystemExit(1 if failed else 0)
