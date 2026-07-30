#!/usr/bin/env python3
from pathlib import Path
import json,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def ck(n,o):checks.append((n,bool(o)))
def t(r):return (root/r).read_text('utf-8')
required=['index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','.github/workflows/deploy-pages.yml','SQL/49_V1.1_升级前检查.sql','SQL/50_V1.1_双向战力挑战与界闻修复.sql','SQL/51_V1.1_CACHE35_正式发布门禁.sql','SQL/52_V1.1_升级后检查.sql','SQL/53_V1.1_紧急停用战力挑战.sql','SQL/54_V1.1_恢复启用战力挑战.sql','database/V1.1/202607300230_v1_1_precheck.sql','database/V1.1/202607300240_v1_1_battle_rules_world_event_fix.sql','database/V1.1/202607300250_v1_1_cache35_release.sql','database/V1.1/202607300260_v1_1_check.sql','tools/test_features_v1_1.js','tools/sql_static_audit_v1_1.py','tools/prepare_pages_site_v1_1.py','tools/verify_pages_site_v1_1.py','tools/ci_v1_1.py']
for x in required:ck('required:'+x,(root/x).is_file())
ck('version',t('VERSION.txt').strip()=='V1.1')
for x in ['index.html','404.html','config.js','sw.js','manifest.webmanifest','update-guard.js']:ck('cache35:'+x,'v1-1-cache35' in t(x) or 'v1.1-cache35' in t(x))
c=t('config.js');ck('config',all(x in c for x in ["version: '1.1'","releaseLabel: 'V1.1 CACHE35'","buildId: 'v1-1-cache35'",'cacheEpoch: 35']))
r=json.loads(t('release_config.json'));b=json.loads(t('CURRENT_BASELINE.json'))
ck('release-json',r.get('version')=='V1.1' and r.get('cacheEpoch')==35 and r.get('clientBuild')=='v1-1-cache35')
ck('baseline-json',b.get('version')=='1.1' and b.get('developmentBaseline')=='V1.1_AB20_CACHE35')
ck('workflow','python3 tools/ci_v1_1.py .' in t('.github/workflows/deploy-pages.yml'))
app=t('app.js');main=t('SQL/50_V1.1_双向战力挑战与界闻修复.sql')
ck('bidirectional','高低战力均可互相挑战' in app and "'can_challenge',id<>v_self_id" in main)
ck('transfer-rules',all(x in main for x in ['higher_power_win_rate=0.005','lower_power_win_rate=0.01','v_loser_stage_progress','v_loser_stage_floor']))
ck('world-event-fix','update public.jiuxiao_world_events' in main and 'update public.world_events' not in main)
failed=[n for n,o in checks if not o]
for n,o in checks:print(('PASS ' if o else 'FAIL ')+n)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}');raise SystemExit(1 if failed else 0)
