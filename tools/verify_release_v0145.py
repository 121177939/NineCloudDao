from pathlib import Path
import json,re,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path.cwd(); checks=[]
def ck(n,o,d=''): checks.append((n,bool(o),d))
def txt(r): return (root/r).read_text('utf-8')
required=['index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','README.md','CHANGELOG.md','DESKTOP_UPDATE.md','.nojekyll','.github/workflows/deploy-pages.yml','database/V0.14.5/202607272330_v0145_opportunity_v4_techniques_player_house_commission.sql','database/V0.14.5/九霄问道_V0.14.5_机缘功法扩充与玩家庄5%佣金.sql','docs/V0.14.5_FINAL_RULES.md','docs/V0.14.5_DEPLOYMENT_GUIDE.md','docs/V0.14.5_SOURCE_CHANGE_REPORT.md','docs/V0.14.5_BUILD_VERIFY_REPORT.md','docs/V0.14.5_REAL_DEVICE_TEST_CHECKLIST.md','tools/prepare_pages_site_v0145.py','tools/verify_pages_site_v0145.py','tools/sql_static_audit_v0145.py','tools/test_features_v0145.js']
for r in required: ck('file:'+r,(root/r).is_file())
app=txt('app.js'); css=txt('styles.css'); sql=txt('database/V0.14.5/202607272330_v0145_opportunity_v4_techniques_player_house_commission.sql')
for token in ['rpcSettleOpportunityV4','rpcAckOpportunitySummaryV4','showOpportunityOfflineSummary','opportunityOfflineSummaryBackdrop','techniques_new','mastery_points','玩家庄赢家毛利润5%佣金','毛利润的95%发给闲家']:
 ck('app:'+token,token in app)
for token in ['opportunity-offline-summary','offline-opportunity-grade','env(safe-area-inset-bottom)']:
 ck('css:'+token,token in css)
for token in ['opportunity_v4_story_pool','opportunity_v4_result_pool','opportunity_v4_settlement_batches','opportunity_v4_technique_pool','player_house_win_commission_bps','enable row level security',"release_name='V0.14.5 CACHE9'",'cache_epoch=greatest(cache_epoch,9)']:
 ck('sql:'+token,token in sql)
for r in ['index.html','404.html','manifest.webmanifest','sw.js']: ck('build:'+r,'0145-cache9' in txt(r))
for r in ['config.js','update-guard.js']: ck('build:'+r,'v0145-cache9' in txt(r))
ck('version',txt('VERSION.txt').strip()=='V0.14.5'); ck('sw-cache',"nine-cloud-dao-v0.14.5-cache9" in txt('sw.js')); ck('cache-epoch','cacheEpoch: 9' in txt('config.js'))
b=json.loads(txt('CURRENT_BASELINE.json')); rc=json.loads(txt('release_config.json'))
ck('baseline',b.get('version')=='0.14.5' and b.get('databaseChange')=='OPPORTUNITY_V4_TECHNIQUES_PLAYER_HOUSE_COMMISSION_V0145')
ck('release',rc.get('clientBuild')=='v0145-cache9' and rc.get('adminBaseline')=='V0.14.4 ADMIN2')
ck('protected-existing',all(t in app for t in ['荷老','输光后境界不变','应局并立即开契','showDivineNoticeModal']))
ck('no-typo','何老' not in app); ck('no-manual-ranking-refresh','data-ranking-refresh' not in app and '刷新天命' not in app)
failed=[x for x in checks if not x[1]]
print(json.dumps({'ok':not failed,'checks':len(checks),'failed':[{'name':n,'detail':d} for n,_,d in failed]},ensure_ascii=False,indent=2)); raise SystemExit(1 if failed else 0)
