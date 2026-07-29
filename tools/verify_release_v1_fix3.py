#!/usr/bin/env python3
from pathlib import Path
import json,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def ck(n,o):checks.append((n,bool(o)))
def t(r):return (root/r).read_text('utf-8')
required=['index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','.github/workflows/deploy-pages.yml','SQL/39_V1.0_FIX3_升级前检查.sql','SQL/40_V1.0_FIX3_挑战界闻趣味文案.sql','SQL/41_V1.0_FIX3_CACHE33_正式发布门禁.sql','SQL/42_V1.0_FIX3_升级后检查.sql','SQL/43_V1.0_FIX3_界闻趣味文案回滚.sql','database/V1.0_FIX3/202607292020_v1_fix3_precheck.sql','database/V1.0_FIX3/202607292030_v1_fix3_battle_story.sql','database/V1.0_FIX3/202607292040_v1_fix3_cache33_release.sql','database/V1.0_FIX3/202607292050_v1_fix3_check.sql','database/V1.0_FIX3/202607292060_v1_fix3_rollback.sql','tools/test_features_v1_fix3.js','tools/sql_static_audit_v1_fix3.py','tools/prepare_pages_site_v1_fix3.py','tools/verify_pages_site_v1_fix3.py','tools/ci_v1_fix3.py']
for r in required:ck('required:'+r,(root/r).is_file())
ck('version',t('VERSION.txt').strip()=='V1.0 FIX3')
for r in ['index.html','404.html','config.js','sw.js','manifest.webmanifest','update-guard.js']:ck('cache33:'+r,'v1-fix3-cache33' in t(r) or 'v1.0-fix3-cache33' in t(r))
c=t('config.js');ck('config',all(x in c for x in ["version: '1.0-fix3'","releaseLabel: 'V1.0 FIX3 CACHE33'","buildId: 'v1-fix3-cache33'",'cacheEpoch: 33']))
r=json.loads(t('release_config.json'));b=json.loads(t('CURRENT_BASELINE.json'))
ck('release-json',r.get('version')=='V1.0 FIX3' and r.get('cacheEpoch')==33 and r.get('clientBuild')=='v1-fix3-cache33')
ck('baseline-json',b.get('version')=='1.0-fix3' and b.get('developmentBaseline')=='V1.0_FIX3_AB18_CACHE33')
ck('workflow','python3 tools/ci_v1_fix3.py .' in t('.github/workflows/deploy-pages.yml'))
app=t('app.js');css=t('styles.css');story=t('SQL/40_V1.0_FIX3_挑战界闻趣味文案.sql')
ck('duel-summary',all(x in app for x in ['battleDuelCombatantHtmlFix3','battle-duel-summary-fix3',"'我方'","'对方'"]))
ck('log-before-controls',app.find('battle-log-bcombat01 battle-log-fix3')<app.find('battle-playback-controls-bcombat01 battle-controls-fix3'))
ck('battle-public-only','function battleDuelCombatantHtmlFix3' in app and '<b>战力</b>' in app and '<b>五行</b>' in app)
ck('css-fix3',all(x in css for x in ['.battle-duel-summary-fix3','.battle-log-bcombat01.battle-log-fix3','.battle-playback-controls-bcombat01.battle-controls-fix3']))
ck('story-rich',all(x in story for x in ['向%s发起挑战','被夺走%s点修为','摧枯拉朽','守榜退敌']))
ck('champion-removed',all(x not in app for x in ['修为榜首','财富榜首','战力榜首','${champion ? `']))
failed=[n for n,o in checks if not o]
for n,o in checks:print(('PASS ' if o else 'FAIL ')+n)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}');raise SystemExit(1 if failed else 0)
