#!/usr/bin/env python3
from pathlib import Path
from html.parser import HTMLParser
from collections import Counter
import json, subprocess, hashlib, re, sys
R=Path(__file__).resolve().parents[1]
errors=[]; warnings=[]; checks={}
def ck(name, cond, msg=None):
 checks[name]=bool(cond)
 if not cond: errors.append(msg or name)
def run(cmd):
 p=subprocess.run(cmd,cwd=R,text=True,capture_output=True)
 if p.returncode: errors.append(f"command failed: {' '.join(cmd)}\n{p.stdout}\n{p.stderr}")
 return p
# syntax
for rel in ['app.js','b-tiandao-person-v220.js','b-technique-v220.js','b-equipment01.js','b-equipment-v210.js','b-secret-realm01.js','b-world-boss01.js','b-sect-v2.js']:
 ck('js:'+rel,run(['node','--check',str(R/rel)]).returncode==0)
# frontend contracts
app=(R/'app.js').read_text(); b=(R/'b-tiandao-person-v220.js').read_text(); idx=(R/'index.html').read_text(); sw=(R/'sw.js').read_text()
legacy=['get_npc_social_v1','interact_with_npc_v1','form_npc_relationship_v1']
new=['get_tiandao_people_hub_v1','get_tiandao_person_detail_v1','resolve_tiandao_encounter_v1','tiandao_npc_interact_v1','tiandao_romance_action_v1','tiandao_companion_action_v1']
ck('legacy-social-client-removed',not any(x in app for x in legacy))
ck('new-rpc-contract',all(x in b for x in new))
ck('five-views',all(x in b for x in ["['home','总览']","['encounters','缘遇']","['people','人物志']","['romance','仙缘']","['companion','道侣']"]))
ck('multi-action-encounter','data-tp-encounter-action' in b and 'e.actions' in b)
ck('people-filter','data-tp-filter' in b and 'peopleFilter' in b)
ck('observer-scoped',"document.getElementById('app')" in b and 'document.documentElement' not in b)
ck('index-loads-module','b-tiandao-person-v220.js' in idx and 'b-tiandao-person-v220.css' in idx)
ck('sw-loads-module','b-tiandao-person-v220.js' in sw and 'b-tiandao-person-v220.css' in sw)
ck('no-client-secret',not re.search(r'CLOUDFLARE_AUTH_TOKEN\s*=|sb_secret_|service_role\s*=', '\n'.join([(R/x).read_text() for x in ['app.js','b-tiandao-person-v220.js','config.js','index.html']]),re.I))
# SQL static report
sqlreport=json.loads((R/'database-upgrades/SQL259_TIANDAO_PEOPLE/SQL259_STATIC_VALIDATION.json').read_text())
ck('sql259-static',sqlreport.get('ok') is True)
# GM DOM/script contract
GM=R/'九霄问道_ADMIN9_R35_V2.2.0_CACHE128_SQL259_天道人物仙缘_手机直用版.html'; g=GM.read_text()
class P(HTMLParser):
 def __init__(self):super().__init__();self.ids=[]
 def handle_starttag(self,t,a):
  d=dict(a)
  if 'id' in d:self.ids.append(d['id'])
p=P();p.feed(g); c=Counter(p.ids)
ck('gm-no-duplicate-id',not [x for x,n in c.items() if n>1])
ck('gm-r35-contract',all(x in g for x in ['ADMIN9 R35','view-tiandao','admin9_get_tiandao_people_v259','admin9_update_tiandao_settings_v259','admin9_check_tiandao_people_v259']))
# builders / Android
ck('pages-build',run(['python','tools/build_pages_v2_2_0_cache128.py','.','.pages-site-validation']).returncode==0)
ck('web-android-sync',run(['python','tools/verify_web_android_sync.py']).returncode==0)
ck('android-validation',run(['python','android/tools/validate_project.py']).returncode==0)
# deploy chain
wf=(R/'.github/workflows/deploy-pages.yml').read_text()
ck('pages-prebuilt-deploy','path: ./pages' in wf and 'upload-pages-artifact' in wf and 'deploy-pages' in wf and 'python ' not in wf and 'node ' not in wf)
report={'ok':not errors,'release':'V2.2.0 CACHE128','buildId':'v2-2-0-cache128-tiandao-people-admin35-sql259','gm':'ADMIN9 R35','database':'SQL258 ONLINE; SQL259 REQUIRED','nextSql':260,'androidVersionCode':2001507,'checks':checks,'errors':errors,'warnings':warnings,'sql259Sha256':sqlreport.get('sha256')}
(R/'RELEASE_VALIDATION_REPORT.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False,indent=2))
if errors: sys.exit(1)
