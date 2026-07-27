from pathlib import Path
import json,re,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path.cwd(); checks=[]
def ck(n,o,d=''): checks.append((n,bool(o),d))
def txt(r): return (root/r).read_text('utf-8')
required=['index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','README.md','CHANGELOG.md','DESKTOP_UPDATE.md','.nojekyll','.github/workflows/deploy-pages.yml','database/V0.14.4/202607272200_v0144_player_house_casino_notice_insight.sql','docs/V0.14.4_FINAL_RULES.md','docs/V0.14.4_DEPLOYMENT_GUIDE.md','docs/V0.14.4_SOURCE_CHANGE_REPORT.md','docs/V0.14.4_BUILD_VERIFY_REPORT.md','docs/V0.14.4_REAL_DEVICE_TEST_CHECKLIST.md','tools/prepare_pages_site_v0144.py','tools/verify_pages_site_v0144.py','tools/sql_static_audit_v0144.py','tools/test_features_v0144.js']
for r in required: ck('file:'+r,(root/r).is_file())
app=txt('app.js'); sql=txt('database/V0.14.4/202607272200_v0144_player_house_casino_notice_insight.sql')
for token in ['rpcGetCasinoPlayerHouseStatusV1','data-player-house-toggle','荷老','data-cultivation-all-in','输光后境界不变','rpcClaimNextDivineNoticeV1','showDivineNoticeModal','总修炼速度','应局并立即开契']:
 ck('app:'+token,token in app)
ck('no-typo','何老' not in app); ck('no-manual-ranking-refresh','data-ranking-refresh' not in app and '刷新天命' not in app)
for token in ['casino_current_stage_floor_v0144','reveal_delay_seconds=0','heavenly_insight_cultivation_multiplier_v0144','player_divine_notices',"release_name='V0.14.4 CACHE8'"]:
 ck('sql:'+token,token in sql)
for r in ['index.html','404.html','manifest.webmanifest','sw.js']: ck('build:'+r,'0144-cache8' in txt(r))
for r in ['config.js','update-guard.js']: ck('build:'+r,'v0144-cache8' in txt(r))
ck('sw-cache',"CACHE_NAME = 'nine-cloud-dao-v0.14.4-cache8'" in txt('sw.js')); ck('cache-epoch','cacheEpoch: 8' in txt('config.js'))
b=json.loads(txt('CURRENT_BASELINE.json')); rc=json.loads(txt('release_config.json'))
ck('baseline',b.get('version')=='0.14.4' and b.get('databaseChange')=='PLAYER_HOUSE_CASINO_NOTICE_INSIGHT_V0144')
ck('release',rc.get('clientBuild')=='v0144-cache8' and rc.get('adminBaseline')=='V0.14.4 ADMIN2')
failed=[x for x in checks if not x[1]]
print(json.dumps({'ok':not failed,'checks':len(checks),'failed':[{'name':n,'detail':d} for n,_,d in failed]},ensure_ascii=False,indent=2)); raise SystemExit(1 if failed else 0)
