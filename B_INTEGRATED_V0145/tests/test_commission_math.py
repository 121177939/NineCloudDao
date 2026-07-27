from math import floor
cases=[
 (100,1,5,95,195),
 (100,3,15,285,385),
 (100,34,170,3230,3330),
 (250,1,12,238,488),
 (10,1,0,10,20),
]
for stake,odds,fee,net,reward in cases:
    gross=stake*odds
    actual_fee=floor(gross*500/10000)
    actual_net=gross-actual_fee
    actual_reward=stake+actual_net
    assert (actual_fee,actual_net,actual_reward)==(fee,net,reward),(stake,odds,actual_fee,actual_net,actual_reward)
    print('PASS',stake,odds,'fee',fee,'net',net,'reward',reward)
print('TOTAL',len(cases),'PASS',len(cases),'FAIL',0)
