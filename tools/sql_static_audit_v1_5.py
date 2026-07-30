#!/usr/bin/env python3
from pathlib import Path
import sys,re
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def ck(name,value): checks.append((name,bool(value)))
def read(rel): return (root/rel).read_text('utf-8')
main=read('SQL/88_V1.5_九霄牌九资金门槛与庄家比例结算.sql')
gate=read('SQL/89_V1.5_CACHE43_正式发布门禁.sql')
post=read('SQL/90_V1.5_CACHE43_升级后检查.sql')
ck('transactions',all('\nbegin;' in x and x.rstrip().endswith('commit;') for x in [main,gate]) and post.lstrip().startswith('--'))
ck('balanced-dollar',all(x.count('$$')%2==0 for x in [main,gate,post]))
ck('settings-columns',all(x in main for x in ['idle_close_seconds integer','minimum_entry_multiplier integer','cultivation_stakes_enabled boolean']))
ck('five-minute-close',all(x in main for x in ["interval '5 minutes'",'idle_close_seconds=300','paigow_cleanup_rooms_bpaigow01']))
ck('ten-times-entry',all(x in main for x in ['paigow_minimum_entry_balance_bpaigow01','return p_base_stake*10','PAIGOW_ENTRY_BALANCE_BELOW_TEN_TIMES_BASE']))
ck('underfunded-eject',all(x in main for x in ['paigow_eject_underfunded_players_bpaigow01',"seat_no=null,role='spectator'",'casino_available_v1(m.character_id']))
ck('cultivation-disabled',all(x in main for x in ["p_stake_type<>'spirit_stone'",'PAIGOW_CULTIVATION_STAKES_TEMPORARILY_DISABLED','cultivation_stakes_enabled=false']))
ck('single-hand-banker-wins',all(x in main for x in ['paigow_pair_compare_vs_dealer_bpaigow01','if (v_player->>\'score\')::bigint>(v_dealer->>\'score\')::bigint then return 1','return -1']))
ck('big-tie',all(x in main for x in ['if v_head=1 and v_tail=1 then return 1','if v_head=-1 and v_tail=-1 then return -1','return 0; -- 大牌九仅一胜一负']))
ck('tie-fee-refund',all(x in main for x in ['fee_refund_amount','paigow_big_tie_fee_refund_v15','v_requested:=rp.stake_amount+rp.fee_amount']))
ck('dealer-full-reserve',all(x in main for x in ['paigow_dealer_full_reserve_v15','reserve_policy','all_available_at_selection']))
ck('pro-rata',all(x in main for x in ['v_profit_pay_total:=least(v_profit_pool,v_winner_claim)','floor(x.stake_amount::numeric*v_profit_pay_total/v_winner_claim)','remainder_rank','pro_rata_triggered']))
ck('no-seat-priority-payment','先统一判定，避免按座位顺序先到先得' in main)
ck('pgrst-reload',"notify pgrst,'reload schema'" in main)
ck('gate-cache43',"release_name='V1.5 CACHE43'" in gate and 'greatest(cache_epoch,43)' in gate)
ck('post-checks',all(x in post for x in ['release_cache43','five_minute_room_close','ten_times_entry_requirement','player_dealer_pro_rata','big_tie_fee_refund','cultivation_paigow_disabled']))
# Crude but useful structural checks for PL/pgSQL bodies.
ck('function-body-count',len(re.findall(r'create or replace function',main,re.I))>=10)
ck('no-old-twenty-minute',"interval '20 minutes'" not in main)
for n,v in checks: print(('PASS ' if v else 'FAIL ')+n)
failed=[n for n,v in checks if not v]
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(bool(failed))
