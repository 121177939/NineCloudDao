#!/usr/bin/env python3
from pathlib import Path
import json,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def ck(n,o):checks.append((n,bool(o)))
def t(r):return (root/r).read_text('utf-8')
required=['index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','.github/workflows/deploy-pages.yml','SQL/36_V1.0_FIX2_升级前检查.sql','SQL/37_V1.0_FIX2_CACHE32_正式发布门禁.sql','SQL/38_V1.0_FIX2_升级后检查.sql','database/V1.0_FIX2/202607291920_v1_fix2_cache32_release.sql','tools/test_features_v1_fix2.js','tools/sql_static_audit_v1_fix2.py','tools/ci_v1_fix2.py']
for r in required:ck('required:'+r,(root/r).is_file())
ck('version',t('VERSION.txt').strip()=='V1.0 FIX2')
for r in ['index.html','404.html','config.js','sw.js','manifest.webmanifest','update-guard.js']:ck('cache32:'+r,'v1-fix2-cache32' in t(r) or 'v1.0-fix2-cache32' in t(r))
c=t('config.js');ck('config',all(x in c for x in ["version: '1.0-fix2'","releaseLabel: 'V1.0 FIX2 CACHE32'","buildId: 'v1-fix2-cache32'",'cacheEpoch: 32']))
r=json.loads(t('release_config.json'));b=json.loads(t('CURRENT_BASELINE.json'));ck('release-json',r.get('version')=='V1.0 FIX2' and r.get('cacheEpoch')==32 and r.get('clientBuild')=='v1-fix2-cache32');ck('baseline-json',b.get('version')=='1.0-fix2' and b.get('developmentBaseline')=='V1.0_FIX2_AB17_CACHE32')
ck('workflow','python3 tools/ci_v1_fix2.py .' in t('.github/workflows/deploy-pages.yml'))
app=t('app.js');css=t('styles.css')
ck('separate-challenge-popup','showBattleResolvingModalBCombat01' in app and 'window.setTimeout(() => showBattlePlaybackBCombat01(result), 80)' in app)
ck('battle-public-card',all(x in app for x in ['battle-combatant-card-compact-fix2','<b>等级</b>','<b>战力</b>','<b>五行</b>']))
ck('battle-private-hidden','<span>道攻 ${formatNumber(row.dao_attack' not in app and '武器：${escapeHtml(row?.weapon_name' not in app)
ck('champion-removed',all(x not in app for x in ['修为榜首','财富榜首','战力榜首','${champion ? `']))
ck('generic-round-copy','凝聚灵力，正面攻向' in app and '${attacker}赤手空拳，运转' not in app)
ck('css-fix2','.battle-combatant-public-fix2' in css and '.battle-report-modal-fix2' in css)
failed=[n for n,o in checks if not o]
for n,o in checks:print(('PASS ' if o else 'FAIL ')+n)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}');raise SystemExit(1 if failed else 0)
