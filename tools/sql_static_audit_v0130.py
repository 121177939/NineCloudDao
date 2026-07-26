#!/usr/bin/env python3
from pathlib import Path
import re, sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parents[1]
sql_path=root/'database/V0.13.0/202607261300_v0130_breakthrough_cultivation_cap.sql'
s=sql_path.read_text('utf-8')
checks=[]
def add(name,ok,detail=''): checks.append((name,bool(ok),detail))
# Simple lexer: strip line comments, single-quoted strings and dollar bodies, then balance punctuation.
def neutralize(text):
    out=[];i=0;n=len(text);mode='normal'
    while i<n:
        if mode=='normal':
            if text.startswith('--',i): mode='line';out.extend('  ');i+=2;continue
            if text[i]=="'": mode='single';out.append(' ');i+=1;continue
            if text.startswith('$$',i): mode='dollar';out.extend('  ');i+=2;continue
            out.append(text[i]);i+=1
        elif mode=='line':
            if text[i]=='\n': mode='normal';out.append('\n')
            else: out.append(' ')
            i+=1
        elif mode=='single':
            if text.startswith("''",i): out.extend('  ');i+=2
            elif text[i]=="'": mode='normal';out.append(' ');i+=1
            else: out.append('\n' if text[i]=='\n' else ' ');i+=1
        elif mode=='dollar':
            if text.startswith('$$',i): mode='normal';out.extend('  ');i+=2
            else: out.append('\n' if text[i]=='\n' else ' ');i+=1
    return ''.join(out),mode
neutral,mode=neutralize(s)
add('lexer_closed',mode=='normal',mode)
for a,b,name in [('(',')','parentheses'),('[',']','brackets')]:
    count=0;ok=True
    for ch in neutral:
        if ch==a: count+=1
        elif ch==b:
            count-=1
            if count<0: ok=False;break
    add(name,ok and count==0,str(count))
add('dollar_pairs',s.count('$$')%2==0,str(s.count('$$')))
add('transaction',re.search(r'(?mi)^begin;\s*$',s) is not None and re.search(r'(?mi)^commit;\s*$',s) is not None)
add('probability_sum',abs(sum([0.005,0.05,0.08,0.15,0.30,0.415])-1)<1e-12)
for fn in ['character_cultivation_cap_v1','character_cultivation_full_v1','grant_cultivation_capped_v1','enforce_character_cultivation_cap_v0130','get_breakthrough_status_v1','attempt_breakthrough_v1','claim_cultivation_v1','apply_opportunity_v3_effects_v1','casino_debit_v1','casino_credit_v1','casino_draw_pools_v1','get_market_v1']:
    add('function:'+fn, bool(re.search(r'create(?: or replace)? function public\.'+re.escape(fn)+r'\b',s,re.I)))
add('trigger', 'trg_player_characters_cultivation_cap_v0130' in s)
add('non_bound_stones','ci.is_bound=false' in s)
add('exact_zero_delete','delete from public.character_inventory' in s)
add('target_bound_insight','v_original_target_id=v_next.id' in s and 'v_target_id=v_next.id' in s)
add('old_fix3_not_required','202607' not in '\n'.join(line for line in s.splitlines() if 'FIX3' in line and '废弃' not in line))
failed=[x for x in checks if not x[1]]
for name,ok,detail in checks: print(('PASS' if ok else 'FAIL'),name,detail)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
sys.exit(1 if failed else 0)
