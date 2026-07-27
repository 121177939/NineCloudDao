#!/usr/bin/env python3
from pathlib import Path
import json,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parents[1]; checks=[]
def ck(n,o,d=''): checks.append((n,bool(o),d))
def txt(p): return (root/p).read_text('utf-8')
required=['index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','README.md','CHANGELOG.md','DESKTOP_UPDATE.md','.nojekyll','.github/workflows/deploy-pages.yml','database/V0.14.1/202607261700_v0141_spirit_stone_casino.sql','database/V0.14.1/202607261930_v0141_fix2_loss_pool_rate.sql','database/V0.14.1/202607262030_v0141_fix3_house_win_pool_rate.sql','database/V0.14.1/202607262130_v0141_fix4_duel_pool_payout.sql','database/V0.14.1/202607262230_v0141_fix4_cache1_release_control.sql','database/V0.14.1/202607270100_v0141_fix5_breakthrough_insight_route.sql','database/V0.14.1/202607270230_v0141_fix6_spirit_dice_triple_auto_side.sql','database/V0.14.1/202607270430_v0141_fix7_destiny_triple_expected_value.sql','tools/verify_release_v0141.py','tools/sql_static_audit_v0141.py','tools/test_casino_render_v0141.js','tools/prepare_pages_site_v0141.py','tools/verify_pages_site_v0141.py']
for f in required: ck('file:'+f,(root/f).is_file())
ck('version',txt('VERSION.txt').strip()=='V0.14.1')
for f in ['index.html','404.html','config.js','README.md','CHANGELOG.md','DESKTOP_UPDATE.md']: ck('version:'+f,'0.14.1' in txt(f))
ck('sw','nine-cloud-dao-v0.14.1-fix7-cache4' in txt('sw.js')); ck('css-release','Current release: Web Alpha 0.14.1' in txt('styles.css'))
b=json.loads(txt('CURRENT_BASELINE.json')); r=json.loads(txt('release_config.json')); ck('baseline',b.get('version')=='0.14.1' and b.get('databaseChange')=='SPIRIT_DICE_DESTINY_TRIPLE_EXPECTED_VALUE_FIX7' and b.get('gameplayBaseline')=='V0.14.1 FIX7'); ck('release',r.get('version')=='V0.14.1' and r.get('clientBuild')=='v0141-fix7-cache4' and r.get('pagesStagingDirectory')=='.pages-site')

html=txt('index.html'); guard=txt('update-guard.js'); sw=txt('sw.js')
for t in ['styles.css?v=0141-fix7-cache4','config.js?v=0141-fix7-cache4','update-guard.js?v=0141-fix7-cache4','app.js?v=0141-fix7-cache4']:
 ck('cache-html:'+t,t in html)
for t in ['get_jiuxiao_app_release_control_v1','cache_epoch','clearNineCloudCaches','updateViaCache','registration.update()','CHECK_INTERVAL_MS']:
 ck('cache-guard:'+t,t in guard)
for t in ["CACHE_NAME = 'nine-cloud-dao-v0.14.1-fix7-cache4'", "request.mode === 'navigate'", 'networkFirst(request', 'SKIP_WAITING', 'clients.claim']:
 ck('cache-sw:'+t,t in sw)

fix5=txt('database/V0.14.1/202607270100_v0141_fix5_breakthrough_insight_route.sql')
for t in ['v_bonus:=least(0.80,greatest(0,v_insights*0.05));','v_base+v_normal+v_insights*0.05','three_insights_equal_15_percent',"release_name='V0.14.1 FIX5 CACHE2'"]:
 ck('fix5:'+t,t in fix5)
fix5_functions=fix5.split('-- 已部署CACHE1时')[0]
ck('fix5-old-gates-removed','v_target_id=v_next.id then' not in fix5_functions and 'v_original_target_id=v_next.id then' not in fix5_functions)
fix6=txt('database/V0.14.1/202607270230_v0141_fix6_spirit_dice_triple_auto_side.sql')
for t in ['casino_spirit_dice_rule_v0141_fix6','111_small_wins_34x','666_big_wins_34x','sample_100_triple_total_is_3495',"release_name='V0.14.1 FIX6 CACHE3'"]:
 ck('fix6:'+t,t in fix6)

fix7=txt('database/V0.14.1/202607270430_v0141_fix7_destiny_triple_expected_value.sql')
for t in ['casino_spirit_dice_rule_v0141_fix7','destiny_chance_is_9_of_275','fixed_side_destiny_probability_is_1_of_2200','expected_net_per_100_is_minus_1',"release_name='V0.14.1 FIX7 CACHE4'"]:
 ck('fix7:'+t,t in fix7)

ck('fix6-triple-bet-disabled',"when p_game_code='spirit_dice' then p_choice in ('big','small')" in fix6 and "p_choice in ('big','small','triple')" not in fix6)
app=txt('app.js')
for t in ['rpcGetSpiritStoneBalanceV0141','mergeCanonicalSpiritStoneInventory','data-spirit-stone-balance','casinoView','大堂','贵宾雅间','全服造化池','快捷倍数','自定义赌注数量','已取消每日次数限制','CASINO_STAKE_TOO_LARGE','latestOpportunityResult(state.opportunityStatus)','refreshSpiritStoneBalanceV0141(true)','3—10点为小','11—18点为大','豹子同样按点数归类','天命豹子','9/275','每2200局出现1次','败局余下95%由天道回收','双方各押100','胜者共到账195','败者赌注的5%进入奖池、95%转给胜者']: ck('app:'+t,t in app)
ck('opportunity-no-stale-pending-check',"state.opportunityStatus?.status === 'pending'" not in app and "opportunity?.status === 'pending'" not in app)
ck('no-daily-errors',all(t not in app for t in ['CASINO_TOTAL_DAILY_LIMIT','CASINO_HOUSE_DAILY_LIMIT','CASINO_DUEL_DAILY_LIMIT','CASINO_CULTIVATION_DAILY_LIMIT','CASINO_GREED_COOLDOWN']))
wf=txt('.github/workflows/deploy-pages.yml')
for t in ['verify_release_v0141.py','sql_static_audit_v0141.py','test_casino_render_v0141.js','prepare_pages_site_v0141.py','verify_pages_site_v0141.py','actions/upload-pages-artifact@v4','actions/deploy-pages@v4']: ck('workflow:'+t,t in wf)
ck('registry','## V0.14.1 FIX7' and '202607270430_v0141_fix7_destiny_triple_expected_value.sql' in txt('database/MIGRATION_REGISTRY.md'))
# history still retained
ck('registry-fix6','## V0.14.1 FIX6' in txt('database/MIGRATION_REGISTRY.md') and '202607270230_v0141_fix6_spirit_dice_triple_auto_side.sql' in txt('database/MIGRATION_REGISTRY.md'))
failed=[x for x in checks if not x[1]]
for n,o,d in checks: print(('PASS' if o else 'FAIL'),n,d)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
