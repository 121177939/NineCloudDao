rates={"玄品":(25/100,2/72,1/72),"地品":(8/100,3/45,1.5/45),"天品":(1.5/100,4/24,2/24),"仙品":(.5/100,3/9,1.5/9)}
ausp=.5
for g,(grade,main,support) in rates.items():
 print(g,"main",grade*ausp*main,"support",grade*ausp*support)
assert rates["天品"][0]*rates["天品"][1] > rates["仙品"][0]*rates["仙品"][1]
assert rates["天品"][0]*rates["天品"][2] > rates["仙品"][0]*rates["仙品"][2]
print("PASS overall heaven technique rates exceed immortal")
