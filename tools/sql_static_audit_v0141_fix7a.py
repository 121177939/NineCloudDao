from pathlib import Path
from fractions import Fraction
import json,re,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path.cwd()
p=root/'database/V0.14.1/202607270730_v0141_fix7a_fair_dice_pool_split.sql'
s=p.read_text('utf-8')
checks=[]
def ck(name,ok,detail=''): checks.append((name,bool(ok),detail))
ck('file',p.is_file())
ck('transaction',bool(re.search(r'(?mi)^begin;\s*$',s)) and bool(re.search(r'(?mi)^commit;\s*$',s)))
ck('dollar-pairs',s.count('$$')%2==0,str(s.count('$$')))
for fn in ['casino_pool_share_preview_v0141_fix7a','casino_take_pool_share_v0141_fix7a','casino_spirit_dice_rule_v0141_fix7a','play_house_game_v1']:
    ck('function:'+fn,f'function public.{fn}' in s)
for token in ['p_choice not in (\'big\',\'small\')','v_side_roll:=1+floor(random()*2)','v_kind_roll:=1+floor(random()*20000)',
              "v_kind_roll<=4","v_kind_roll<=254",'v_nominal_profit:=p_stake_amount*v_net_odds',
              "v_stake_type,v_nominal_profit,v_win_pool_bps,'win'", "v_stake_type,p_stake_amount,v_loss_pool_bps,'loss'",
              'v_heaven_recovery:=greatest(0,p_stake_amount-v_pool_contribution)']:
    ck('token:'+token,token in s)
# exact expected value for a player fixing one side
normal=Fraction(9873,20000)
ordinary=Fraction(1,160)
destiny=Fraction(1,10000)
loss=Fraction(1,2)
ev=normal*Fraction(19,20)+ordinary*Fraction(57,20)+destiny*Fraction(323,10)-loss
ck('expected-value',ev==Fraction(-999,100000),str(ev))
ck('win100-pool',100*500//10000==5)
ck('ordinary-profit600-pool',600*500//10000==30)
ck('destiny-profit6800-pool',6800*500//10000==340)
ck('loss100-pool',100*1000//10000==10)
ck('loss100-heaven',100-10==90)
failed=[x for x in checks if not x[1]]
print(json.dumps({'ok':not failed,'checks':len(checks),'expected_value':float(ev),'failed':[{'name':n,'detail':d} for n,_,d in failed]},ensure_ascii=False,indent=2))
raise SystemExit(1 if failed else 0)
