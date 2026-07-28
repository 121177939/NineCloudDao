from pathlib import Path
import sys,json,re
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path.cwd()
p=root/'database/V0.14.8/202607281630_v0148_fish_shrimp_mobile_casino.sql'; s=p.read_text('utf-8'); low=s.lower(); checks=[]
def ck(n,o): checks.append((n,bool(o)))
for token in ['begin;','commit;','security definer','casino_fish_rounds_v0148','casino_fish_bets_v0148','enable row level security','revoke all','grant execute',"notify pgrst",'cache_epoch=greatest(cache_epoch,12)']: ck(token,token in low)
ck('balanced-dollar',s.count('$$')%2==0)
ck('one-transaction',len(re.findall(r'(?im)^begin;\s*$',s))==1 and len(re.findall(r'(?im)^commit;\s*$',s))==1)
ck('six-symbols',all(x in s for x in ["'fish'","'shrimp'","'crab'","'coin'","'gourd'","'frog'"]))
ck('round-timing',all(x in low for x in ["interval '40 seconds'","interval '43 seconds'","interval '49 seconds'","interval '60 seconds'"]))
ck('player-stones-only',"house_mode<>'player' or stake_type='spirit_stone'" in low and "casino_player_house_only_spirit_stone" in low)
ck('self-bet-denied','casino_player_house_self_bet_forbidden' in low)
ck('commission-5pct','v_commission_bps integer:=500' in low and '/10000' in low)
ck('system-cover','v_system_cover:=greatest(v_player_profit-v_dealer_debit,0)' in low)
ck('fix7a-pool',"casino_take_pool_share_v0141_fix7a(v_bet.stake_type,v_gross,500,'win')" in low and "casino_take_pool_share_v0141_fix7a(v_bet.stake_type,v_bet.stake_amount,1000,'loss')" in low)
ck('server-persisted','insert into public.casino_fish_bets_v0148' in low)
ck('lazy-settlement','where not is_settled and settles_at<=now()' in low)
ck('auth-only',"grant execute on function public.get_fish_shrimp_state_v0148(integer) to authenticated" in low and "grant execute on function public.place_fish_shrimp_bet_v0148(text,text,text,bigint) to authenticated" in low)
ck('no-client-table-grant','grant select' not in low and 'grant insert' not in low and 'grant update' not in low)
failed=[n for n,o in checks if not o]
print(json.dumps({'ok':not failed,'checks':len(checks),'failed':failed},ensure_ascii=False,indent=2)); raise SystemExit(1 if failed else 0)
