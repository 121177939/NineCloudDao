from pathlib import Path
import hashlib, json, re, sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path.cwd()
checks=[]
def ck(name, ok, detail=''):
    checks.append((name,bool(ok),detail))
def txt(rel): return (root/rel).read_text('utf-8')
required=[
'index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest',
'VERSION.txt','CURRENT_BASELINE.json','release_config.json','README.md','CHANGELOG.md','DESKTOP_UPDATE.md','.nojekyll',
'.github/workflows/deploy-pages.yml','database/V0.14.1/202607270730_v0141_fix7a_fair_dice_pool_split.sql',
'tools/prepare_pages_site_v0141.py','tools/verify_pages_site_v0141.py','tools/test_casino_render_v0141.js'
]
for rel in required: ck('file:'+rel,(root/rel).is_file())
app=txt('app.js'); sql=txt('database/V0.14.1/202607270730_v0141_fix7a_fair_dice_pool_split.sql')
for token in [
'大小各50%','普通豹子毛利润3倍','天命豹子毛利润34倍','普通豹子全服约1/80','天命豹子全服约1/5000',
'赢局仅从毛利润提取5%进入造化池','败局下注额10%进入造化池','余下90%由天道回收'
]: ck('app:'+token,token in app)
for token in [
'casino_spirit_dice_rule_v0141_fix7a','casino_take_pool_share_v0141_fix7a','house_win_profit_pool_bps=500',
'house_loss_pool_bps=1000','spirit_dice_ordinary_triple_denominator=80',
'spirit_dice_destiny_triple_result_denominator=5000','spirit_dice_ordinary_triple_net_odds=3',
'spirit_dice_destiny_triple_net_odds=34',"release_name='V0.14.1 FIX7A CACHE5'",
'fixed_side_expected_value_is_minus_0_999_percent','loss_100_pool_is_10','loss_100_heaven_is_90'
]: ck('sql:'+token,token in sql)
ck('sql-transaction',bool(re.search(r'(?mi)^begin;\s*$',sql)) and bool(re.search(r'(?mi)^commit;\s*$',sql)))
ck('sql-dollar-pairs',sql.count('$$')%2==0,str(sql.count('$$')))
ck('sql-grant','grant execute on function public.play_house_game_v1(text,text,bigint,text) to authenticated;' in sql)
ck('choice-independent','玩家选择和两边下注量不参与随机过程' in sql and 'v_side_roll:=1+floor(random()*2)' in sql)
ck('probability-bins',"when v_kind_roll<=4 then 'destiny_triple'" in sql and "when v_kind_roll<=254 then 'ordinary_triple'" in sql)
for rel in ['index.html','404.html','manifest.webmanifest']:
    ck('build:'+rel,'0141-fix7a-cache5' in txt(rel))
for rel in ['config.js','update-guard.js']:
    ck('build:'+rel,'v0141-fix7a-cache5' in txt(rel))
ck('build:sw.js','nine-cloud-dao-v0.14.1-fix7a-cache5' in txt('sw.js') and '0141-fix7a-cache5' in txt('sw.js'))
ck('sw-cache',"CACHE_NAME = 'nine-cloud-dao-v0.14.1-fix7a-cache5'" in txt('sw.js'))
ck('cache-epoch','cacheEpoch: 5' in txt('config.js'))
b=json.loads(txt('CURRENT_BASELINE.json')); r=json.loads(txt('release_config.json'))
ck('baseline',b.get('databaseChange')=='FAIR_DICE_WIN5_LOSS10_POOL_SPLIT_FIX7A' and b.get('gameplayBaseline')=='V0.14.1 FIX7A')
ck('release',r.get('clientBuild')=='v0141-fix7a-cache5' and r.get('databaseMigration','').endswith('202607270730_v0141_fix7a_fair_dice_pool_split.sql'))
failed=[x for x in checks if not x[1]]
print(json.dumps({'ok':not failed,'checks':len(checks),'failed':[{'name':n,'detail':d} for n,_,d in failed]},ensure_ascii=False,indent=2))
raise SystemExit(1 if failed else 0)
