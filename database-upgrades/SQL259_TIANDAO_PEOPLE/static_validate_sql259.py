#!/usr/bin/env python3
from pathlib import Path
import json,re,hashlib,sys
p=Path(__file__).with_name('01_SQL259_V2.2.0_CACHE128_天道人物仙缘_彻底替换旧红尘_执行即门禁.sql')
s=p.read_text('utf-8')
errors=[];checks={}
# lexer balance for (), single quote, double quote, dollar quote, comments
paren=0;i=0;n=len(s);state='code';dtag='';line=1
while i<n:
 c=s[i]; nxt=s[i+1] if i+1<n else ''
 if c=='\n': line+=1
 if state=='code':
  if c=="'": state='single'
  elif c=='"': state='double'
  elif c=='-' and nxt=='-': state='linecomment';i+=1
  elif c=='/' and nxt=='*': state='blockcomment';i+=1
  elif c=='$':
   m=re.match(r'\$[A-Za-z_][A-Za-z0-9_]*\$|\$\$',s[i:])
   if m: dtag=m.group(0);state='dollar';i+=len(dtag)-1
  elif c=='(': paren+=1
  elif c==')':
   paren-=1
   if paren<0: errors.append(f'negative parenthesis line {line}');paren=0
 elif state=='single':
  if c=="'":
   if nxt=="'": i+=1
   else: state='code'
 elif state=='double':
  if c=='"':
   if nxt=='"': i+=1
   else: state='code'
 elif state=='linecomment':
  if c=='\n': state='code'
 elif state=='blockcomment':
  if c=='*' and nxt=='/': state='code';i+=1
 elif state=='dollar':
  if s.startswith(dtag,i): i+=len(dtag)-1;state='code'
 i+=1
if state not in ('code','linecomment'): errors.append(f'unclosed lexical state {state} tag={dtag}')
if paren: errors.append(f'parenthesis balance={paren}')
checks['lexical_balance']=not errors
checks['transaction']=len(re.findall(r'(?im)^begin;\s*$',s))==1 and len(re.findall(r'(?im)^commit;\s*$',s))==1 and s.find('begin;')<s.rfind('commit;')
checks['npc_20_core']=len(re.findall(r"\('core_[^']+'",s))==20
checks['npc_30_romance']=len(re.findall(r"\('romance_[^']+'",s))==30
checks['romance_gender_20_10']=len(re.findall(r"\('romance_[^']+','[^']+','female'",s))==20 and len(re.findall(r"\('romance_[^']+','[^']+','male'",s))==10
checks['all_adult_constraint']='age integer not null check(age>=18)' in s
player=['get_tiandao_people_hub_v1','get_tiandao_person_detail_v1','resolve_tiandao_encounter_v1','tiandao_npc_interact_v1','tiandao_romance_action_v1','tiandao_companion_action_v1']
checks['six_player_rpc']=all(f'create or replace function public.{x}(' in s for x in player)
checks['gm_rpc']=all(f'create or replace function public.{x}(' in s for x in ['admin9_get_tiandao_people_v259','admin9_update_tiandao_settings_v259','admin9_check_tiandao_people_v259'])
checks['legacy_revoke']=all(x in s for x in ['get_npc_social_v1','interact_with_npc_v1','form_npc_relationship_v1','revoke execute'])
checks['raw_table_revoke']='revoke all on table' in s and 'enable row level security' in s
checks['final_gate']='SQL259_GATE_PASSED' in s and "'next_sql',260" in s
checks['no_cloudflare_token']=not re.search(r'CLOUDFLARE_AUTH_TOKEN\s*=|sb_secret_',s,re.I)
checks['no_direct_old_partner_core']='relationship_type' not in s
checks['known_person_guard']=s.count('TIANDAO_PERSON_NOT_KNOWN')>=3
checks['world_news_reuse']='jiuxiao_world_events' in s and 'create table if not exists public.jiuxiao_world_events' not in s
failed=[k for k,v in checks.items() if not v]
if failed: errors.extend('failed:'+x for x in failed)
report={'ok':not errors,'checks':checks,'errors':errors,'lines':len(s.splitlines()),'bytes':len(s.encode()),'sha256':hashlib.sha256(s.encode()).hexdigest()}
Path(__file__).with_name('SQL259_STATIC_VALIDATION.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False,indent=2))
if errors: sys.exit(1)
