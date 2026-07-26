#!/usr/bin/env python3
from pathlib import Path
import re, sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parents[1]
base=root/'database/V0.14.0'
main=base/'202607261430_v0140_bazaar_world_events.sql'
files=[main,base/'202607261430_v0140_precheck.sql',base/'202607261430_v0140_check.sql',base/'202607261430_v0140_data_audit.sql',base/'202607261430_v0140_emergency_disable.sql',base/'202607261430_v0140_resume.sql',base/'202607261430_v0140_rollback.sql']
checks=[]
def add(name,ok,detail=''): checks.append((name,bool(ok),detail))
def neutralize(text):
    out=[];i=0;n=len(text);mode='normal'
    while i<n:
        if mode=='normal':
            if text.startswith('--',i): mode='line';out.extend('  ');i+=2;continue
            if text[i]=="'": mode='single';out.append(' ');i+=1;continue
            if text.startswith('$$',i): mode='dollar';out.extend('  ');i+=2;continue
            out.append(text[i]);i+=1
        elif mode=='line':
            out.append('\n' if text[i]=='\n' else ' '); mode='normal' if text[i]=='\n' else mode; i+=1
        elif mode=='single':
            if text.startswith("''",i): out.extend('  ');i+=2
            elif text[i]=="'": mode='normal';out.append(' ');i+=1
            else: out.append('\n' if text[i]=='\n' else ' ');i+=1
        else:
            if text.startswith('$$',i): mode='normal';out.extend('  ');i+=2
            else: out.append('\n' if text[i]=='\n' else ' ');i+=1
    return ''.join(out),mode
for f in files: add('file:'+f.name,f.is_file())
s=main.read_text('utf-8')
neutral,mode=neutralize(s)
add('lexer_closed',mode=='normal',mode)
for a,b,name in [('(',')','parentheses'),('[',']','brackets')]:
    c=0;ok=True
    for ch in neutral:
        if ch==a:c+=1
        elif ch==b:
            c-=1
            if c<0:ok=False;break
    add(name,ok and c==0,str(c))
add('transaction',bool(re.search(r'(?mi)^begin;\s*$',s)) and bool(re.search(r'(?mi)^commit;\s*$',s)))
for table in ['world_event_settings','world_events']:
    add('table:'+table,bool(re.search(r'create table if not exists public\.'+table+r'\b',s,re.I)))
for fn in ['world_event_publish_v0140','get_world_events_v1','world_event_from_breakthrough_v0140','world_event_from_opportunity_v0140','world_event_from_house_game_v0140','world_event_from_duel_v0140','world_event_from_casino_draw_v0140','admin_publish_account_erasure_v1']:
    add('function:'+fn,bool(re.search(r'create or replace function public\.'+fn+r'\b',s,re.I)))
for trigger in ['trg_world_event_breakthrough_v0140','trg_world_event_opportunity_v0140','trg_world_event_house_game_v0140','trg_world_event_duel_v0140','trg_world_event_casino_draw_v0140']:
    add('trigger:'+trigger,trigger in s)
add('source_unique','world_events_source_unique unique (source_table, source_key, event_type)' in s)
add('rls','alter table public.world_events enable row level security' in s)
add('direct_table_revoked','revoke all on table public.world_events from public, anon, authenticated' in s)
add('publish_private','revoke all on function public.world_event_publish_v0140' in s)
add('read_authenticated','grant execute on function public.get_world_events_v1(integer) to authenticated' in s)
add('admin_service_only','grant execute on function public.admin_publish_account_erasure_v1(text,text,text,text) to service_role' in s and 'from public, anon, authenticated' in s)
add('every_house_result','after insert on public.casino_house_games' in s and "'casino_house_' || new.outcome_code" in s)
add('duel_settled_only',"new.status <> 'settled'" in s)
add('fault_isolation',s.count('exception when others then')>=5,str(s.count('exception when others then')))
add('no_client_insert_grant',not re.search(r'grant\s+(insert|update|delete).*world_events.*authenticated',s,re.I|re.S))
add('no_market_page_name', '市场' not in s)
# Cross-check referenced baseline columns from authoritative migrations.
casino=(root/'database/V0.12.0/202607260830_v0120_fix1_market_casino.sql').read_text('utf-8')
for col in ['outcome_code','reward_amount','winner_character_id','prize_amount','ticket_count']:
    add('baseline-casino-column:'+col,col in casino)
opp=(root/'database/V0.11.2/202607250020_auto_opportunity_v3.sql').read_text('utf-8')
for col in ['result_data','rarity','path_key','reward_text','penalty_text']:
    add('baseline-opportunity-column:'+col,col in opp)
failed=[x for x in checks if not x[1]]
for n,ok,d in checks: print(('PASS' if ok else 'FAIL'),n,d)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
sys.exit(1 if failed else 0)
