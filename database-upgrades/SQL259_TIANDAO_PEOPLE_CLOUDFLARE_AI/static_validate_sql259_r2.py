#!/usr/bin/env python3
from pathlib import Path
import json,re,hashlib,sys
p=Path(__file__).with_name('01_SQL259_R2_V2.2.0_CACHE129_天道人物_CloudflareWorkersAI_执行即门禁.sql')
s=p.read_text('utf-8')
errors=[];checks={}
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
checks['transaction']=len(re.findall(r'(?im)^begin;\s*$',s))==1 and len(re.findall(r'(?im)^commit;\s*$',s))==1
checks['npc_20_core']=len(re.findall(r"\('core_[^']+'",s))==20
checks['npc_30_romance']=len(re.findall(r"\('romance_[^']+'",s))==30
checks['romance_gender_20_10']=len(re.findall(r"\('romance_[^']+','[^']+','female'",s))==20 and len(re.findall(r"\('romance_[^']+','[^']+','male'",s))==10
checks['all_adult_constraint']='age integer not null check(age>=18)' in s
checks['cloudflare_model']=s.count('@cf/qwen/qwen3-30b-a3b-fp8')>=3 and "ai_engine text not null default 'cloudflare_workers_ai'" in s
checks['fallback_exists']='create or replace function public.server_personality_v1(p_context jsonb)' in s
checks['internal_gate_functions']=all(f'create or replace function public.{x}(' in s for x in ['tiandao_ai_runtime_settings_v259','tiandao_ai_prepare_v259','tiandao_ai_apply_v259'])
checks['request_ticket']='create table if not exists public.tiandao_ai_requests_v259' in s and "interval '2 minutes'" in s
checks['ai_goal_intent_state']=all(x in s for x in ['create table if not exists public.tiandao_ai_state_v259','previous_ai_state','next_goal text not null','action_intent text not null','on conflict(character_id,npc_id) do update'])
checks['state_server_audit']=all(x in s for x in ['server_rules_are_authoritative','ai_may_modify_state',"if v_score<v_threshold-10 then v_decision:='reject'",'tianxu_inventory_adjust_v255'])
checks['direct_write_player_revoked']=all(f'revoke all on function public.{sig} from public,anon,authenticated;' in s for sig in ['resolve_tiandao_encounter_v1(uuid,text)','tiandao_npc_interact_v1(uuid,text)','tiandao_romance_action_v1(uuid,text,text)','tiandao_companion_action_v1(text)'])
checks['internal_only_service_role']=all(f'grant execute on function public.{sig} to service_role;' in s for sig in ['server_personality_v1(jsonb)','tiandao_ai_runtime_settings_v259()','tiandao_ai_prepare_v259(uuid,text,uuid,text,text,uuid)','tiandao_ai_apply_v259(uuid,uuid,jsonb,text,text,integer,text)'])
checks['player_read_only']=all(f'grant execute on function public.{sig} to authenticated;' in s for sig in ['get_tiandao_people_hub_v1()','get_tiandao_person_detail_v1(uuid)'])
checks['gm_ai_fields']=all(x in s for x in ['recent_ai_decisions','ai_runtime','last_latency_ms','last_failure_reason','cloudflare_24h','fallback_24h'])
checks['r1_compat_alters']=all(x in s for x in ['add column if not exists ai_enabled','add column if not exists ai_model','add column if not exists request_id uuid','add column if not exists latency_ms'])
checks['legacy_revoke']=all(x in s for x in ['get_npc_social_v1','interact_with_npc_v1','form_npc_relationship_v1','revoke execute'])
checks['raw_table_revoke']='revoke all on table' in s and 'enable row level security' in s
checks['final_gate']='SQL259_GATE_PASSED' in s and "'next_sql',260" in s
checks['no_cloudflare_secret_value_or_id']='CLOUDFLARE_AUTH_TOKEN' not in s and '5b79ea0b023989a461bbb8f8a6f0b374' not in s and 'sb_secret_' not in s
checks['world_news_reuse']='jiuxiao_world_events' in s and 'create table if not exists public.jiuxiao_world_events' not in s
failed=[k for k,v in checks.items() if not v]
if failed: errors.extend('failed:'+x for x in failed)
report={'ok':not errors,'checks':checks,'errors':errors,'lines':len(s.splitlines()),'bytes':len(s.encode()),'sha256':hashlib.sha256(s.encode()).hexdigest()}
Path(__file__).with_name('SQL259_R2_STATIC_VALIDATION.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report,ensure_ascii=False,indent=2))
if errors: sys.exit(1)
