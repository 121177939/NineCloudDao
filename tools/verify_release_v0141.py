#!/usr/bin/env python3
from pathlib import Path
import json,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parents[1]; checks=[]
def ck(n,o,d=''): checks.append((n,bool(o),d))
def txt(p): return (root/p).read_text('utf-8')
required=['index.html','404.html','app.js','styles.css','config.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','README.md','CHANGELOG.md','DESKTOP_UPDATE.md','.nojekyll','.github/workflows/deploy-pages.yml','database/V0.14.1/202607261700_v0141_spirit_stone_casino.sql','tools/verify_release_v0141.py','tools/sql_static_audit_v0141.py','tools/test_casino_render_v0141.js','tools/prepare_pages_site_v0141.py','tools/verify_pages_site_v0141.py']
for f in required: ck('file:'+f,(root/f).is_file())
ck('version',txt('VERSION.txt').strip()=='V0.14.1')
for f in ['index.html','404.html','config.js','README.md','CHANGELOG.md','DESKTOP_UPDATE.md']: ck('version:'+f,'0.14.1' in txt(f))
ck('sw','nine-cloud-dao-v0.14.1' in txt('sw.js')); ck('css-release','Current release: Web Alpha 0.14.1' in txt('styles.css'))
b=json.loads(txt('CURRENT_BASELINE.json')); r=json.loads(txt('release_config.json')); ck('baseline',b.get('version')=='0.14.1' and b.get('databaseChange')=='UNIFIED_SPIRIT_STONE_AND_CASINO_V2'); ck('release',r.get('version')=='V0.14.1' and r.get('pagesStagingDirectory')=='.pages-site')
app=txt('app.js')
for t in ['rpcGetSpiritStoneBalanceV0141','mergeCanonicalSpiritStoneInventory','data-spirit-stone-balance','casinoView','大堂','贵宾雅间','全服造化池','快捷倍数','自定义赌注数量','已取消每日次数限制','CASINO_STAKE_TOO_LARGE','latestOpportunityResult(state.opportunityStatus)','refreshSpiritStoneBalanceV0141(true)']: ck('app:'+t,t in app)
ck('opportunity-no-stale-pending-check',"state.opportunityStatus?.status === 'pending'" not in app and "opportunity?.status === 'pending'" not in app)
ck('no-daily-errors',all(t not in app for t in ['CASINO_TOTAL_DAILY_LIMIT','CASINO_HOUSE_DAILY_LIMIT','CASINO_DUEL_DAILY_LIMIT','CASINO_CULTIVATION_DAILY_LIMIT','CASINO_GREED_COOLDOWN']))
wf=txt('.github/workflows/deploy-pages.yml')
for t in ['verify_release_v0141.py','sql_static_audit_v0141.py','test_casino_render_v0141.js','prepare_pages_site_v0141.py','verify_pages_site_v0141.py','actions/upload-pages-artifact@v4','actions/deploy-pages@v4']: ck('workflow:'+t,t in wf)
ck('registry','## V0.14.1' in txt('database/MIGRATION_REGISTRY.md') and 'V0.14.0 FIX2 / FIX3' in txt('database/MIGRATION_REGISTRY.md'))
failed=[x for x in checks if not x[1]]
for n,o,d in checks: print(('PASS' if o else 'FAIL'),n,d)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
