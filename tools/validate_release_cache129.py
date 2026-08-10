#!/usr/bin/env python3
from pathlib import Path
from html.parser import HTMLParser
from collections import Counter
import json, subprocess, re, sys, tempfile
R=Path(__file__).resolve().parents[1]
errors=[]; warnings=[]; checks={}
def ck(name, cond, msg=None):
 checks[name]=bool(cond)
 if not cond: errors.append(msg or name)
def run(cmd,cwd=R):
 p=subprocess.run(cmd,cwd=cwd,text=True,capture_output=True)
 if p.returncode: errors.append(f"command failed: {' '.join(map(str,cmd))}\n{p.stdout}\n{p.stderr}")
 return p
# JS syntax
for rel in ['app.js','b-tiandao-person-v220.js','b-technique-v220.js','b-equipment01.js','b-equipment-v210.js','b-secret-realm01.js','b-world-boss01.js','b-sect-v2.js']:
 ck('js:'+rel,run(['node','--check',str(R/rel)]).returncode==0)
# Edge TS type/syntax with Deno shim
edge=R/'supabase/functions/tiandao-ai/index.ts'
with tempfile.NamedTemporaryFile('w',suffix='.ts',encoding='utf-8',delete=False) as f:
 f.write('declare const Deno: any;\n'+edge.read_text())
 t=f.name
try: ck('edge-ts',run(['tsc','--noEmit','--target','ES2022','--lib','ES2022,DOM','--skipLibCheck',t]).returncode==0)
finally: Path(t).unlink(missing_ok=True)
# frontend contracts
app=(R/'app.js').read_text(); b=(R/'b-tiandao-person-v220.js').read_text(); idx=(R/'index.html').read_text(); sw=(R/'sw.js').read_text()
legacy=['get_npc_social_v1','interact_with_npc_v1','form_npc_relationship_v1']
direct=['resolve_tiandao_encounter_v1','tiandao_npc_interact_v1','tiandao_romance_action_v1','tiandao_companion_action_v1']
ck('legacy-social-client-removed',not any(x in app for x in legacy))
ck('tiandao-read-rpc',all(x in b for x in ['get_tiandao_people_hub_v1','get_tiandao_person_detail_v1']))
ck('direct-write-client-removed',not any(x in b for x in direct))
ck('edge-ai-client',all(x in b for x in ['/functions/v1/tiandao-ai','tryEdgeAi',"mode:'interaction'","mode:'romance'","mode:'encounter'","mode:'companion'"]))
ck('five-views',all(x in b for x in ["['home','总览']","['encounters','缘遇']","['people','人物志']","['romance','仙缘']","['companion','道侣']"]))
ck('observer-scoped',"document.getElementById('app')" in b and 'document.documentElement' not in b)
ck('index-loads-module','b-tiandao-person-v220.js' in idx and 'b-tiandao-person-v220.css' in idx)
ck('sw-loads-module','b-tiandao-person-v220.js' in sw and 'b-tiandao-person-v220.css' in sw)
public_client='\n'.join((R/x).read_text() for x in ['app.js','b-tiandao-person-v220.js','config.js','index.html','404.html','sw.js'])
ck('no-cloudflare-secret-in-client',not re.search(r'CLOUDFLARE_AUTH_TOKEN|CLOUDFLARE_ACCOUNT_ID|5b79ea0b023989a461bbb8f8a6f0b374|sb_secret_',public_client,re.I))
# Edge contracts
et=edge.read_text()
ck('edge-cloudflare-contract',all(x in et for x in ['CLOUDFLARE_ACCOUNT_ID','CLOUDFLARE_AUTH_TOKEN','@cf/qwen/qwen3-30b-a3b-fp8','messages','server_personality_v1','tiandao_ai_prepare_v259','tiandao_ai_apply_v259']))
ck('edge-ai-scope',all(x in et for x in ['accept / defer / reject','禁止决定或修改','server_rules_are_authoritative']) if 'server_rules_are_authoritative' in et else all(x in et for x in ['accept / defer / reject','禁止决定或修改']))
ck('edge-jwt-locked','[functions.tiandao-ai]' in (R/'supabase/config.toml').read_text() and 'verify_jwt = true' in (R/'supabase/config.toml').read_text())
# SQL
sqlreport=json.loads((R/'database-upgrades/SQL259_TIANDAO_PEOPLE_CLOUDFLARE_AI/SQL259_R2_STATIC_VALIDATION.json').read_text())
ck('sql259-r2-static',sqlreport.get('ok') is True)
# GM
GM=R/'九霄问道_ADMIN9_R36_V2.2.0_CACHE129_SQL259_R2_CloudflareAI_手机直用版.html'; g=GM.read_text()
class P(HTMLParser):
 def __init__(self): super().__init__(); self.ids=[]; self.scripts=[]; self._in=False; self._buf=[]
 def handle_starttag(self,t,a):
  d=dict(a)
  if 'id' in d:self.ids.append(d['id'])
  if t=='script' and 'src' not in d:self._in=True;self._buf=[]
 def handle_data(self,d):
  if self._in:self._buf.append(d)
 def handle_endtag(self,t):
  if t=='script' and self._in:self.scripts.append(''.join(self._buf));self._in=False
p=P();p.feed(g); c=Counter(p.ids)
ck('gm-no-duplicate-id',not [x for x,n in c.items() if n>1])
ck('gm-r36-ai-contract',all(x in g for x in ['ADMIN9 R36','tiandaoAiTestButton','tiandaoAiDecisionList','tiandaoAiTimeout','tiandaoAiMaxTokens','Cloudflare Workers AI','/functions/v1/']))
for i,script in enumerate(p.scripts):
 if script.strip():
  with tempfile.NamedTemporaryFile('w',suffix='.js',encoding='utf-8',delete=False) as f: f.write(script); q=f.name
  try: ck(f'gm-script-{i}',run(['node','--check',q]).returncode==0)
  finally: Path(q).unlink(missing_ok=True)
# builders/android
ck('pages-build',run(['python','tools/build_pages_v2_2_0_cache129.py','.','.pages-site-validation']).returncode==0)
ck('web-android-sync',run(['python','tools/verify_web_android_sync.py']).returncode==0)
ck('android-validation',run(['python','android/tools/validate_project.py']).returncode==0)
# deployed public artifacts secret scan if directories exist
for dirname in ['pages','android/app/src/main/assets/game']:
 root=R/dirname
 if root.exists():
  hit=[]
  for f in root.rglob('*'):
   if f.is_file() and f.suffix.lower() in {'.js','.html','.json','.txt','.css','.webmanifest','.md'}:
    try: tx=f.read_text(errors='ignore')
    except: continue
    if re.search(r'CLOUDFLARE_AUTH_TOKEN|CLOUDFLARE_ACCOUNT_ID|5b79ea0b023989a461bbb8f8a6f0b374|sb_secret_',tx,re.I): hit.append(str(f.relative_to(root)))
  ck('secret-scan:'+dirname,not hit,'secret marker leaked in '+dirname+':'+','.join(hit))
wf=(R/'.github/workflows/deploy-pages.yml').read_text()
ck('pages-prebuilt-deploy','path: ./pages' in wf and 'upload-pages-artifact' in wf and 'deploy-pages' in wf and 'python ' not in wf and 'node ' not in wf)
report={'ok':not errors,'release':'V2.2.0 CACHE129','buildId':'v2-2-0-cache129-tiandao-cloudflare-ai-admin36-sql259r2','gm':'ADMIN9 R36','database':'SQL258 ONLINE; SQL259 R2 REQUIRED','nextSql':260,'androidVersionCode':2001508,'edgeFunction':'tiandao-ai','checks':checks,'errors':errors,'warnings':warnings,'sql259R2Sha256':sqlreport.get('sha256')}
(R/'RELEASE_VALIDATION_REPORT.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False,indent=2))
if errors: sys.exit(1)
