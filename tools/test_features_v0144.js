const fs=require('fs'),path=require('path');
const root=path.resolve(process.argv[2]||process.argv[1]||'.');
const app=fs.readFileSync(path.join(root,'app.js'),'utf8');
const css=fs.readFileSync(path.join(root,'styles.css'),'utf8');
const checks=[]; const ck=(n,o)=>checks.push([n,!!o]);
[
 ['player-house-rpc','rpcGetCasinoPlayerHouseStatusV1'],['player-house-toggle','data-player-house-toggle'],['player-house-copy','余额达到500万即可自愿上庄，无需财富榜第一'],
 ['system-dealer-name','荷老'],['no-wrong-dealer-name',!app.includes('何老')],['cultivation-all-in','data-cultivation-all-in'],
 ['minor-stage-copy','输光后境界不变'],['no-twenty-percent',!app.includes('最高20%')&&!app.includes('可动用修为的20%')],
 ['duel-immediate','确认落注并立即开局'],['join-immediate','应局并立即开契'],['no-five-minute',!app.includes('五分钟后')&&!app.includes('等待5分钟')],
 ['insight-speed','总修炼速度'],['insight-ten','insights * 10'],['notice-rpc','rpcClaimNextDivineNoticeV1'],
 ['notice-modal','showDivineNoticeModal'],['notice-ack','我已知晓'],['notice-poll','setInterval(() => checkDivineNotice(true), 10000)'],
 ['notice-css',css.includes('.divine-notice-modal')],['all-in-css',css.includes('.casino-all-in-btn')]
].forEach(([n,t])=>ck(n,typeof t==='string'?app.includes(t):t));
const failed=checks.filter(x=>!x[1]); checks.forEach(x=>console.log(x[1]?'PASS':'FAIL',x[0]));
console.log(`TOTAL=${checks.length} PASS=${checks.length-failed.length} FAIL=${failed.length}`); process.exit(failed.length?1:0);
