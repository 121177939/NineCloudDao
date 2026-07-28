#!/usr/bin/env python3
from pathlib import Path
import json,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def ck(n,o):checks.append((n,bool(o)));print(('PASS' if o else 'FAIL'),n)
def txt(p):return(root/p).read_text('utf-8')
required=['index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','.github/workflows/deploy-pages.yml','database/V0.15.1/202607282000_v0151_precheck.sql','database/V0.15.1/202607282010_v0151_casino_world_feed_dealer_and_fish_40s.sql','database/V0.15.1/202607282020_v0151_check.sql','database/V0.15.1/202607282030_v0151_rollback.sql','database/V0.15.1/202607282040_v0151_fix1_fish_30_2_5_3.sql','database/V0.15.1/202607282050_v0151_fix1_check.sql','database/V0.15.1/202607282060_v0151_fix1_rollback.sql','docs/V0.15.1_SOURCE_CHANGE_REPORT.md','docs/V0.15.1_DEPLOYMENT_GUIDE.md','docs/V0.15.1_BUILD_VERIFY_REPORT.md','docs/V0.15.1_FINAL_RULES.md','tools/prepare_pages_site_v0151.py','tools/verify_pages_site_v0151.py','tools/test_casino_feed_fish40_v0151.js','tools/sql_static_audit_v0151.py']
for f in required:ck('required:'+f,(root/f).is_file())
app=txt('app.js');css=txt('styles.css');workflow=txt('.github/workflows/deploy-pages.yml');sql=txt('database/V0.15.1/202607282010_v0151_casino_world_feed_dealer_and_fish_40s.sql')
ck('version',txt('VERSION.txt').strip()=='V0.15.1')
for f in ['index.html','404.html','sw.js','manifest.webmanifest','config.js','update-guard.js']:ck('cache18:'+f,'v0151-cache18' in txt(f) or '0151-cache18' in txt(f))
rc=json.loads(txt('release_config.json'));cb=json.loads(txt('CURRENT_BASELINE.json'))
ck('release-build',rc.get('clientBuild')=='v0151-cache18');ck('baseline-hotfix',cb.get('clientHotfix')=='V0.15.1_FISH_TIMING_30_2_5_3_CACHE18');ck('database-change',rc.get('databaseChange')=='casino_world_feed_dealer_and_fish_40s_timing_fix')
ck('40-second-ui','elapsed/40*100' in app and '每局40秒' in app and '公共40秒轮次' in app)
ck('30-2-5-3-ui',all(x in app for x in ['前30秒下注','随后2秒封盘','5秒依次开骰','start + 30000','start + 32000','start + 37000','33 + index * 2']))
ck('continuous-preserved',all(x in app for x in ['enqueueFishShrimpBetV0150','processFishShrimpBetQueueV0150','fishShrimpQueuedAmountV0150']))
ck('responsive','.fish-game-shell {' in css and 'width: 100%;' in css and 'max-width: none;' in css and 'width: min(100%, 460px)' not in css)
ck('feed-restored','world_event_publish_fish_round_v0151' in sql and '本局净赢' in sql and '本局净输' in sql)
ck('dealer-names',"format('玩家庄【%s】'" in sql and 'dealer_name_snapshot' in sql and "else '荷老' end" in sql)
ck('workflow-pages',all(t in workflow for t in ['actions/checkout@v6','actions/configure-pages@v5','actions/upload-pages-artifact@v4','actions/deploy-pages@v4','python3 tools/ci_v0151.py .']))
failed=[x for x in checks if not x[1]];print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}');raise SystemExit(1 if failed else 0)
