const fs=require('fs');
const path=require('path');
const root=path.resolve(__dirname,'..');
const app=fs.readFileSync(path.join(root,'CLIENT_CANDIDATE','app.js'),'utf8');
const html=fs.readFileSync(path.join(root,'CLIENT_CANDIDATE','b-paigow01.html'),'utf8');
const assertions=[
 ['entry replacement',app.includes('data-paigow-open')&&app.includes('九霄灵牌')&&!app.includes('气运龟卜')],
 ['room flow',html.includes('创建牌局')&&html.includes('选择桌位')&&html.includes('随机抢庄')],
 ['small and big',html.includes('小牌九')&&html.includes('大牌九')],
 ['weak head rule',html.includes('头牌不能大于尾牌')&&html.includes('头牌不大于尾牌')],
 ['timers',html.includes('30秒')&&html.includes('10秒')&&html.includes('6秒')],
 ['baseline bankroll',html.includes('get_market_v1')&&html.includes('casinoFunds')],
];
for(const [name,ok] of assertions){console.log(`${name}: ${ok?'PASS':'FAIL'}`);if(!ok)process.exitCode=1;}
