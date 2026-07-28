from pathlib import Path
import json,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path.cwd(); checks=[]
def ck(n,o): checks.append((n,bool(o)))
def txt(r): return (root/r).read_text('utf-8')
required=['index.html','404.html','app.js','styles.css','config.js','update-guard.js','sw.js','manifest.webmanifest','VERSION.txt','CURRENT_BASELINE.json','release_config.json','database/V0.14.7/202607280600_v0147_library_opportunity_inventory_house.sql','docs/V0.14.7_FINAL_RULES.md','docs/V0.14.7_DEPLOYMENT_GUIDE.md']
for r in required: ck('file:'+r,(root/r).is_file())
app=txt('app.js'); css=txt('styles.css'); sql=txt('database/V0.14.7/202607280600_v0147_library_opportunity_inventory_house.sql')
for token in ['rpcGetTechniqueLibraryV1','use_technique_book_v1','rpcGetOpportunityHistoryV0147','opportunityResultDetailText','rpcUseInventoryItemQuantityV0147','inventoryQuantityBackdrop','casinoHouseMode','rpcPlayHouseGameV0147','data-house-mode']: ck('app:'+token,token in app)
for token in ['opportunity-history-grade.high-tier','opportunity-grade-badge.high-tier','inventory-quantity-modal','casino-house-switch']: ck('css:'+token,token in css)
for token in ['character_technique_books','get_technique_library_v1','get_opportunity_history_v0147','use_inventory_item_quantity_v0147','play_house_game_v0147','system_cover_amount',"interval '2 hours'",'jiuxiao_app_release_control','CACHE11']: ck('sql:'+token,token in sql)
for r in ['index.html','404.html','sw.js','manifest.webmanifest']: ck('cache:'+r,'0147-cache11' in txt(r))
ck('config-build',"buildId: 'v0147-cache11'" in txt('config.js'))
ck('version',txt('VERSION.txt').strip()=='V0.14.7')
rc=json.loads(txt('release_config.json')); b=json.loads(txt('CURRENT_BASELINE.json'))
ck('release-json',rc.get('clientBuild')=='v0147-cache11')
ck('baseline-json',b.get('clientHotfix')=='V0.14.7_TECHNIQUE_LIBRARY_DUAL_HOUSE_CACHE11')

if (root/'AB_DEV_CONTROL/BASELINE_LOCK.json').is_file():
    lock=json.loads(txt('AB_DEV_CONTROL/BASELINE_LOCK.json')); ck('ab5',lock.get('baselineId')=='V0.14.7_AB5')
if (root/'AB_DEV_CONTROL/AB_DEVELOPMENT_PROTOCOL.md').is_file():
    ck('authorization-gate','未经授权生成的文件不得成为基线' in txt('AB_DEV_CONTROL/AB_DEVELOPMENT_PROTOCOL.md'))
failed=[n for n,o in checks if not o]
print(json.dumps({'ok':not failed,'checks':len(checks),'failed':failed},ensure_ascii=False,indent=2)); raise SystemExit(1 if failed else 0)
