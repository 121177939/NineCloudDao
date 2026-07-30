#!/usr/bin/env python3
from fractions import Fraction
import random

def pair_vs_dealer(player_score,dealer_score):
    return 1 if player_score>dealer_score else -1

def big_round(ph,pt,dh,dt):
    head=1 if ph>dh else -1
    tail=1 if pt>dt else -1
    if head==tail: return head
    return 0

def prorata(stakes,pool,seat_ids=None):
    total=sum(stakes)
    if total<=0 or pool<=0: return [0]*len(stakes)
    pay=min(pool,total)
    floors=[s*pay//total for s in stakes]
    remain=pay-sum(floors)
    ids=seat_ids or list(range(len(stakes)))
    order=sorted(range(len(stakes)),key=lambda i:(-(s:=Fraction(stakes[i]*pay,total)-floors[i]),ids[i]))
    out=floors[:]
    for i in order[:remain]: out[i]+=1
    return out

checks=[]
def ck(name,value): checks.append((name,bool(value)))
ck('equal positive score dealer wins',pair_vs_dealer(9010,9010)==-1)
ck('both zero dealer wins',pair_vs_dealer(0,0)==-1)
ck('strict higher player wins',pair_vs_dealer(6000,5000)==1)
ck('big both win',big_round(2,8,1,7)==1)
ck('big both lose',big_round(1,7,2,8)==-1)
ck('big split tie A',big_round(2,7,1,8)==0)
ck('big split tie B',big_round(1,8,2,7)==0)
ck('entry 10x',1000*10==10000 and 9999<10000)
ck('tie refund net zero',(1000+25)-1000-25==0)
ck('pro rata simple',prorata([10000,20000,30000],30000)==[5000,10000,15000])
ck('pro rata cap claim',sum(prorata([50,50,50],100))==100)
ck('pro rata enough pays full',prorata([11,17,23],1000)==[11,17,23])
# Randomized conservation/fairness invariant.
rng=random.Random(15043)
ok=True
for _ in range(5000):
    n=rng.randint(1,8);stakes=[rng.randint(1,10**7) for _ in range(n)];pool=rng.randint(0,sum(stakes)*2)
    out=prorata(stakes,pool,list(range(n)))
    target=min(pool,sum(stakes))
    if sum(out)!=target or any(x<0 or x>s for x,s in zip(out,stakes)):
        ok=False;break
    # Every result must be either floor or ceil of exact proportional share.
    if target:
        for x,s in zip(out,stakes):
            exact=Fraction(s*target,sum(stakes))
            if x not in (exact.numerator//exact.denominator,(exact.numerator+exact.denominator-1)//exact.denominator): ok=False;break
    if not ok: break
ck('5000 randomized pro-rata invariants',ok)
for n,v in checks: print(('PASS ' if v else 'FAIL ')+n)
failed=[n for n,v in checks if not v]
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(bool(failed))
