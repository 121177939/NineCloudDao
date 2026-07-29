#!/usr/bin/env python3
from pathlib import Path
import json,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def ck(n,o):checks.append((n,bool(o)))
def txt(r):return (root/r).read_text('utf-8')
required=['index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','.github/workflows/deploy-pages.yml','database/V0.15.4/202607290090_v0154_precheck.sql','database/V0.15.4/202607290100_v0154_cache23_full_upgrade.sql','database/V0.15.4/202607290110_v0154_check.sql','database/V0.15.4/202607290120_v0154_rollback.sql','SQL/11_V0.15.4_升级前检查.sql','SQL/12_V0.15.4_CACHE23_正式升级.sql','SQL/13_V0.15.4_升级后检查.sql','SQL/14_V0.15.4_回滚.sql','tools/prepare_pages_site_v0154.py','tools/verify_pages_site_v0154.py','tools/sql_static_audit_v0154.py','tools/test_features_v0154.js','tools/ci_v0154.py']
for r in required:ck(f'required:{r}',(root/r).is_file())
ck('version',txt('VERSION.txt').strip()=='V0.15.4')
for r in ['index.html','404.html','config.js','sw.js','manifest.webmanifest']:ck(f'cache23:{r}','0154-cache23' in txt(r) or '0.15.4-cache23' in txt(r))
ck('config-version',"version: '0.15.4'" in txt('config.js'));ck('config-epoch','cacheEpoch: 23' in txt('config.js'))
release=json.loads(txt('release_config.json'));baseline=json.loads(txt('CURRENT_BASELINE.json'))
ck('release-build',release.get('clientBuild')=='v0154-cache23');ck('release-version',release.get('version')=='V0.15.4');ck('release-migration',release.get('databaseMigration')=='database/V0.15.4/202607290100_v0154_cache23_full_upgrade.sql')
ck('baseline-version',baseline.get('version')=='0.15.4');ck('baseline-hotfix',baseline.get('clientHotfix')=='V0.15.4_CACHE23')
workflow=txt('.github/workflows/deploy-pages.yml');ck('workflow-ci-v0154','python3 tools/ci_v0154.py .' in workflow);ck('workflow-pages',all(x in workflow for x in ['actions/configure-pages@v5','actions/upload-pages-artifact@v4','actions/deploy-pages@v4']))
app=txt('app.js')
for n,t in {'instant':'optimisticTechniqueUpgradeV0154','breakdown':'openCultivationRateBreakdownV0154','treasure':'rpc/get_treasure_shop_v0154','wash':'rpc/use_spirit_washing_pill_v0154','b02':'道果崩解0.3%'}.items():ck('app-'+n,t in app)
main=txt('database/V0.15.4/202607290100_v0154_cache23_full_upgrade.sql').lower()
ck('sql-no-direct-stone','update public.player_characters set spirit_stones' not in main);ck('sql-cache23',"release_name='v0.15.4 cache23'" in main);ck('sql-security','security definer' in main and 'revoke all' in main)
failed=[n for n,o in checks if not o]
for n,o in checks:print(('PASS ' if o else 'FAIL ')+n)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}');raise SystemExit(1 if failed else 0)
