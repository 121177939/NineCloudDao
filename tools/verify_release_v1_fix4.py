#!/usr/bin/env python3
from pathlib import Path
import json,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def ck(n,o):checks.append((n,bool(o)))
def t(r):return (root/r).read_text('utf-8')
required=['index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','.github/workflows/deploy-pages.yml','SQL/44_V1.0_FIX4_升级前检查.sql','SQL/45_V1.0_FIX4_赌坊安全结算.sql','SQL/46_V1.0_FIX4_CACHE34_正式发布门禁.sql','SQL/47_V1.0_FIX4_升级后检查.sql','SQL/48_V1.0_FIX4_紧急停用玩家庄.sql','database/V1.0_FIX4/202607292130_v1_fix4_precheck.sql','database/V1.0_FIX4/202607292140_v1_fix4_casino_security.sql','database/V1.0_FIX4/202607292150_v1_fix4_cache34_release.sql','database/V1.0_FIX4/202607292160_v1_fix4_check.sql','database/V1.0_FIX4/202607292170_v1_fix4_emergency_disable.sql','tools/test_features_v1_fix4.js','tools/sql_static_audit_v1_fix4.py','tools/prepare_pages_site_v1_fix4.py','tools/verify_pages_site_v1_fix4.py','tools/ci_v1_fix4.py']
for r in required:ck('required:'+r,(root/r).is_file())
ck('version',t('VERSION.txt').strip()=='V1.0 FIX4')
for r in ['index.html','404.html','config.js','sw.js','manifest.webmanifest','update-guard.js']:ck('cache34:'+r,'v1-fix4-cache34' in t(r) or 'v1.0-fix4-cache34' in t(r))
c=t('config.js');ck('config',all(x in c for x in ["version: '1.0-fix4'","releaseLabel: 'V1.0 FIX4 CACHE34'","buildId: 'v1-fix4-cache34'",'cacheEpoch: 34']))
r=json.loads(t('release_config.json'));b=json.loads(t('CURRENT_BASELINE.json'))
ck('release-json',r.get('version')=='V1.0 FIX4' and r.get('cacheEpoch')==34 and r.get('clientBuild')=='v1-fix4-cache34')
ck('baseline-json',b.get('version')=='1.0-fix4' and b.get('developmentBaseline')=='V1.0_FIX4_AB19_CACHE34')
ck('workflow','python3 tools/ci_v1_fix4.py .' in t('.github/workflows/deploy-pages.yml'))
app=t('app.js');main=t('SQL/45_V1.0_FIX4_赌坊安全结算.sql')
ck('rpc-updated','rpc/play_house_game_v1_fix4' in app and 'rpc/place_fish_shrimp_bet_v1_fix4' in app)
ck('safety-rules',all(x in main for x in ['house_stake_limit_bps','casino_bet_requests_v1','dealer_reserved_amount','system_cover_amount=0']))
ck('unsafe-copy-removed','玩家庄局不限下注金额' not in app and '不足由荷老补足' not in app)
failed=[n for n,o in checks if not o]
for n,o in checks:print(('PASS ' if o else 'FAIL ')+n)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}');raise SystemExit(1 if failed else 0)
