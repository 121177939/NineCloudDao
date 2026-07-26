#!/usr/bin/env python3
from pathlib import Path
import re,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parents[1]
p=root/'database/V0.14.1/202607261700_v0141_spirit_stone_casino.sql'; s=p.read_text('utf-8'); checks=[]
def ck(n,o,d=''): checks.append((n,bool(o),d))
ck('file',p.is_file()); ck('transaction',bool(re.search(r'(?mi)^begin;\s*$',s)) and bool(re.search(r'(?mi)^commit;\s*$',s)))
ck('dollar-pairs',s.count('$$')%2==0,str(s.count('$$')))
for a,b,n in [('(',')','parentheses'),('[',']','brackets')]: ck(n,s.count(a)==s.count(b),f'{s.count(a)}/{s.count(b)}')
for token in [
 'V0141_REQUIRES_EXACTLY_ONE_SPIRIT_STONE_DEFINITION','create or replace function public.spirit_stone_normalize_character_v0141',
 'character_inventory_one_spirit_stone_v0141','create or replace function public.award_spirit_stones_v3',
 'create or replace function public.spirit_stone_debit_v0141','create or replace function public.award_cave_resource_v3',
 'create or replace function public.upgrade_exclusive_technique_v1','create or replace function public.get_spirit_stone_balance_v0141',
 'pool_hit_chance=0.40000','on conflict(stake_type,round_ends_at,character_id) do nothing','check(ticket_count=1)',
 'set amount=p.amount+p_stake_amount','v_pool_contribution:=d.stake_amount*2','random()<v_hit_chance',
 'offset v_pick limit 1','v_rollover:=p.amount','qualification_rule','one_per_character_per_round',
 'CASINO_STAKE_TOO_LARGE','notify pgrst','world_event_from_casino_draw_v0140']:
 ck('token:'+token,token in s)
for forbidden in ['CASINO_TOTAL_DAILY_LIMIT','CASINO_HOUSE_DAILY_LIMIT','CASINO_DUEL_DAILY_LIMIT','CASINO_CULTIVATION_DAILY_LIMIT','CASINO_GREED_COOLDOWN','ticket_count=t.ticket_count+1','sum(t.ticket_count)']:
 ck('removed:'+forbidden,forbidden not in s)
ck('no-ambiguous-pool-update','where p.stake_type=p_stake_type' not in s)
ck('one-definition-check',"count(*) from public.item_definitions where code='spirit_stone'" in s)
ck('private-internals',all(('revoke all on function public.'+fn) in s for fn in ['award_spirit_stones_v3','spirit_stone_debit_v0141','casino_credit_v1','casino_add_ticket_v1','casino_draw_pools_v1']))
ck('public-rpcs',all(('grant execute on function public.'+fn) in s for fn in ['get_market_v1','get_spirit_stone_balance_v0141','play_house_game_v1','create_duel_v1','join_duel_v1','cancel_duel_v1']))
failed=[x for x in checks if not x[1]]
for n,o,d in checks: print(('PASS' if o else 'FAIL'),n,d)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
