from pathlib import Path
import json,sys,re
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path.cwd(); checks=[]
def ck(n,o): checks.append((n,bool(o)))
def txt(r): return (root/r).read_text('utf-8')
required=['index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','database/V0.14.8/202607281630_v0148_fish_shrimp_mobile_casino.sql','docs/V0.14.8_FINAL_RULES.md','docs/V0.14.8_DEPLOYMENT_GUIDE.md']
for r in required: ck('file:'+r,(root/r).is_file())
app=txt('app.js'); css=txt('styles.css'); sql=txt('database/V0.14.8/202607281630_v0148_fish_shrimp_mobile_casino.sql')
for token in ['rpcGetFishShrimpStateV0148','rpcPlaceFishShrimpBetV0148','fishShrimpPanelHtmlV0148','data-fish-symbol','fish_shrimp','最近20局结算历史','荷老局','玩家局']: ck('app:'+token,token in app)
for token in ['fish-game-shell','fish-compact-top','fish-settings-block','fish-target-grid','grid-template-columns: repeat(3','fishWinningGlow']: ck('css:'+token,token in css)
for token in ['casino_fish_rounds_v0148','casino_fish_bets_v0148','get_fish_shrimp_state_v0148','place_fish_shrimp_bet_v0148',"interval '40 seconds'","interval '43 seconds'","interval '49 seconds'","interval '60 seconds'",'CACHE12']: ck('sql:'+token,token in sql)
for r in ['index.html','404.html','sw.js','manifest.webmanifest']: ck('cache:'+r,'0148-cache12' in txt(r))
ck('config-build',"buildId: 'v0148-cache12'" in txt('config.js'))
ck('config-epoch','cacheEpoch: 12' in txt('config.js'))
ck('version',txt('VERSION.txt').strip()=='V0.14.8')
rc=json.loads(txt('release_config.json')); b=json.loads(txt('CURRENT_BASELINE.json'))
ck('release-json',rc.get('clientBuild')=='v0148-cache12')
ck('baseline-json',b.get('clientHotfix')=='V0.14.8_FISH_SHRIMP_MOBILE_CACHE12')
ck('formal-name','赌坊 · 万运博弈楼' in app and '墨玉赌坊' not in app)
ck('no-demo-placeholders','未来玩法一' not in app and '未来玩法二' not in app)
if (root/'AB_DEV_CONTROL/BASELINE_LOCK.json').is_file():
 lock=json.loads(txt('AB_DEV_CONTROL/BASELINE_LOCK.json')); ck('ab6',lock.get('baselineId')=='V0.14.8_AB6')
if (root/'AB_DEV_CONTROL/AB_DEVELOPMENT_PROTOCOL.md').is_file(): ck('authorization-gate','未经授权生成的文件不得成为基线' in txt('AB_DEV_CONTROL/AB_DEVELOPMENT_PROTOCOL.md'))
failed=[n for n,o in checks if not o]
print(json.dumps({'ok':not failed,'checks':len(checks),'failed':failed},ensure_ascii=False,indent=2)); raise SystemExit(1 if failed else 0)
