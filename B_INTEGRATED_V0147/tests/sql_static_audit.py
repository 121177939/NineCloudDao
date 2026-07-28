#!/usr/bin/env python3
from pathlib import Path
import re,sys
ROOT=Path(__file__).resolve().parents[1]
errors=[]

def scan(path: Path):
    s=path.read_text(encoding='utf-8')
    if s.count('$$')%2:
        errors.append(f'{path.name}: odd $$ count')
    # Basic lexical parenthesis balance outside comments, quoted strings, and dollar bodies.
    depth=0; i=0; mode='code'
    while i<len(s):
        if mode=='code':
            if s.startswith('--',i): mode='line'; i+=2; continue
            if s.startswith('/*',i): mode='block'; i+=2; continue
            if s.startswith('$$',i): mode='dollar'; i+=2; continue
            ch=s[i]
            if ch=="'": mode='single'; i+=1; continue
            if ch=='(':
                depth+=1
            elif ch==')':
                depth-=1
                if depth<0: errors.append(f'{path.name}: parenthesis underflow at {i}'); depth=0
            i+=1
        elif mode=='line':
            if s[i]=='\n': mode='code'
            i+=1
        elif mode=='block':
            if s.startswith('*/',i): mode='code'; i+=2
            else: i+=1
        elif mode=='single':
            if s[i]=="'":
                if i+1<len(s) and s[i+1]=="'": i+=2
                else: mode='code'; i+=1
            else: i+=1
        elif mode=='dollar':
            if s.startswith('$$',i): mode='code'; i+=2
            else: i+=1
    if mode not in ('code','line'):
        errors.append(f'{path.name}: unterminated lexical mode {mode}')
    if depth!=0: errors.append(f'{path.name}: parenthesis depth {depth}')
    # Function signatures should be unique inside migration.
    sigs=re.findall(r'create\s+or\s+replace\s+function\s+([\w.]+\s*\([^)]*\))',s,re.I)
    dup={x for x in sigs if sigs.count(x)>1}
    if dup: errors.append(f'{path.name}: duplicate function signatures {sorted(dup)}')
    return len(s.splitlines()),s.count('$$'),len(sigs)

for p in sorted((ROOT/'database').glob('*.sql')):
    lines,dollars,funcs=scan(p)
    print(f'PASS lexical {p.name}: lines={lines} dollar_tokens={dollars} functions={funcs}')

main=(ROOT/'database'/'10_technique_book_library.sql').read_text(encoding='utf-8')
checks={
    'book table': 'create table if not exists public.character_technique_books' in main,
    'ordinary book award': 'technique_book_add_v1(p_character_id,\'ordinary\'' in main,
    'no ordinary auto learn': 'award_opportunity_technique_v3' not in main,
    'exclusive book storage': "technique_book_add_v1(c.id,'exclusive'" in main,
    'mismatch not reclaimed': '天道收回' not in main,
    'mismatch no 100 stones': "'spirit_gain_fixed',100" not in main,
    'fate gate': 'EXCLUSIVE_BOOK_FATE_MISMATCH' in main,
    'no auto equip on study': "values(c.id,etd.code,1,false)" in main,
    'ordinary no auto equip': 'values(c.id,t.id,1,0,false,null' in main,
    'active study rewards': 'apply_technique_book_first_rewards_v1' in main,
    'duplicate manual mastery': "'action','contemplate'" in main,
    'offline book summary': "'technique_books',v_book_list" in main,
    'pity mismatch +2': 'v_pity:=least(100,v_pity+2)' in main,
    'pity natal reset': "to_jsonb(20)" in main,
}
for name,ok in checks.items():
    print(('PASS' if ok else 'FAIL'),name)
    if not ok: errors.append(name)

if errors:
    print('\nERRORS:')
    for e in errors: print('-',e)
    sys.exit(1)
print(f'TOTAL_STATIC_CHECKS={len(checks)} ALL_PASS')
