from pathlib import Path
import json,re,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parents[1]
checks=[]
def check(name,ok,detail=''): checks.append((name,bool(ok),detail))
def text(path): return (root/path).read_text('utf-8')
required=['index.html','404.html','app.js','styles.css','config.js','sw.js','VERSION.txt','CURRENT_BASELINE.json','release_config.json',
'database/V0.13.0/202607261300_v0130_precheck.sql','database/V0.13.0/202607261300_v0130_breakthrough_cultivation_cap.sql',
'database/V0.13.0/202607261300_v0130_check.sql','database/V0.13.0/202607261300_v0130_emergency_disable.sql',
'database/V0.13.0/202607261300_v0130_resume.sql','database/V0.13.0/202607261300_v0130_rollback.sql',
'database/V0.13.0/202607261300_v0130_data_audit.sql','docs/V0.13.0_FINAL_RULES.md','docs/V0.13.0_DEPLOYMENT_GUIDE.md']
for f in required: check('file:'+f,(root/f).is_file())
check('version.txt',text('VERSION.txt').strip()=='V0.13.0')
for f in ['index.html','404.html','config.js','README.md','CHANGELOG.md','DESKTOP_UPDATE.md']:
    check('version:'+f,'0.13.0' in text(f))
check('sw-cache','nine-cloud-dao-v0.13.0' in text('sw.js'))
base=json.loads(text('CURRENT_BASELINE.json'))
check('baseline.version',base.get('version')=='0.13.0')
check('baseline.source',base.get('sourceBaseline')=='V0.12.0 FIX1 + Deploy Hotfix')
app=text('app.js')
for token in ['cultivation-full-notice','heavenly_insight_count','CULTIVATION_FULL_CASINO_BLOCKED','breakthroughOutcomeName','currentDisplayedCultivation()','最终成功率上限']:
    check('app:'+token,token in app)
sql=text('database/V0.13.0/202607261300_v0130_breakthrough_cultivation_cap.sql')
for token in ['0.005000','0.050000','0.080000','0.150000','0.300000','0.415000','character_cultivation_cap_v1','grant_cultivation_capped_v1','trg_player_characters_cultivation_cap_v0130','heavenly_insight_count',"v_original_target_id=v_next.id","ci.is_bound=false","delete from public.character_inventory"]:
    check('sql:'+token,token in sql)
check('sql-dollar-pairs',sql.count('$$')%2==0,str(sql.count('$$')))
check('sql-transaction',sql.lstrip().startswith('-- 九霄问道') and '\nbegin;' in sql.lower() and sql.rstrip().replace(' ','').endswith("notifypgrst,'reloadschema';"))
check('workflow-v0130','tools/verify_release_v0130.py' in text('.github/workflows/deploy-pages.yml') and 'test_market_render_v0130.js' in text('.github/workflows/deploy-pages.yml'))
check('no-active-old-audit',not (root/'tools/audit_v0120_fix1.py').exists())
check('no-old-version','0.12.0-fix1' not in text('index.html'))
check('old-fix3-deprecated','旧V0.12.0 FIX3' in text('database/MIGRATION_REGISTRY.md'))
failed=[x for x in checks if not x[1]]
for n,ok,d in checks: print(('PASS' if ok else 'FAIL'),n,d)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
sys.exit(1 if failed else 0)
