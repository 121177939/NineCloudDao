#!/usr/bin/env python3
from pathlib import Path
import json
import sys

root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve()
checks=[]
def ck(name,ok): checks.append((name,bool(ok)))
def text(rel): return (root/rel).read_text('utf-8')

required=[
 'index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest',
 'VERSION.txt','CURRENT_BASELINE.json','release_config.json','V1.2_CACHE37.txt','V1.2_升级说明.md',
 'docs/V1.2_变异灵根与剑心互斥规则.md','.github/workflows/deploy-pages.yml',
 'SQL/64_V1.1_FIX1_安全随机兼容修复.sql','SQL/65_V1.2_升级前检查.sql',
 'SQL/66_V1.2_变异灵根与剑心互斥.sql','SQL/67_V1.2_CACHE37_正式发布门禁.sql',
 'SQL/68_V1.2_升级后检查.sql','SQL/69_V1.2_紧急停用变异加成.sql','SQL/70_V1.2_恢复启用变异加成.sql',
 'database/V1.1_FIX1/202607300950_v1_1_fix1_secure_rng_compat.sql',
 'database/V1.2/202607301300_v1_2_precheck.sql','database/V1.2/202607301310_v1_2_mutation_roots_sword_heart_mutex.sql',
 'database/V1.2/202607301320_v1_2_cache37_release.sql','database/V1.2/202607301330_v1_2_check.sql',
 'database/V1.2/202607301340_v1_2_emergency_disable_mutation.sql','database/V1.2/202607301350_v1_2_resume_mutation.sql',
 'tools/verify_release_v1_2.py','tools/sql_static_audit_v1_2.py','tools/test_features_v1_2.js',
 'tools/test_balance_v1_2.py','tools/prepare_pages_site_v1_2.py','tools/verify_pages_site_v1_2.py','tools/ci_v1_2.py'
]
for rel in required: ck('required:'+rel,(root/rel).is_file())
ck('version-file',text('VERSION.txt').strip()=='V1.2')
config=text('config.js')
ck('config-version',"version: '1.2'" in config)
ck('config-label',"releaseLabel: 'V1.2 CACHE37'" in config)
ck('config-build',"buildId: 'v1-2-cache37'" in config)
ck('config-epoch','cacheEpoch: 37' in config)
release=json.loads(text('release_config.json'))
baseline=json.loads(text('CURRENT_BASELINE.json'))
lock=json.loads(text('AB_CONTROL/BASELINE_LOCK.json'))
ck('release-json',release.get('version')=='V1.2' and release.get('cacheEpoch')==37 and release.get('clientBuild')=='v1-2-cache37')
ck('baseline-json',baseline.get('version')=='1.2' and baseline.get('developmentBaseline')=='V1.2_AB22_CACHE37')
ck('baseline-sql-range','64—68' in baseline.get('packagePolicy',{}).get('database',''))
ck('lock-json',lock.get('baseline')=='V1.2_AB22_CACHE37' and lock.get('databaseSqlRange')=='64-70')
for rel in ['index.html','404.html','config.js','sw.js','manifest.webmanifest','update-guard.js']:
    body=text(rel).lower()
    ck('cache37:'+rel,'v1-2-cache37' in body or 'v1.2-cache37' in body)
ck('workflow','python3 tools/ci_v1_2.py .' in text('.github/workflows/deploy-pages.yml'))
app=text('app.js');css=text('styles.css');sql=text('SQL/66_V1.2_变异灵根与剑心互斥.sql')
ck('frontend-mutation',all(x in app for x in ['mutationAttributeHtmlV12','变异灵根（${mutation}）','rpc/get_my_birth_result_v12']))
ck('frontend-colors',all(x in css for x in ['mutation-thunder','mutation-ice','mutation-wind']))
ck('sql-mutex',all(x in sql for x in ['trg_v12_mutant_root_conflict_guard','trg_v12_sword_heart_conflict_guard','v12_random_non_mutant_root','v12_random_non_sword_fate']))
ck('sql-damage','v_element*v_sword*v_mutation' in sql.replace(' ',''))
ck('casino-regression',all(x in app for x in ['100赔3320','100:97.5','正利润的50%','领取70%']))
failed=[name for name,ok in checks if not ok]
for name,ok in checks: print(('PASS ' if ok else 'FAIL ')+name)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
