const fs=require('fs');const p=require('path');
const app=fs.readFileSync(p.join(__dirname,'../source/candidate/app.js'),'utf8');
const css=fs.readFileSync(p.join(__dirname,'../source/candidate/styles.css'),'utf8');
const checks={
  summary:app.includes('离线修行结算')&&app.includes('功法所得')&&app.includes('传承点 +'),
  mobile:css.includes('@media(max-width:520px)')&&css.includes('align-items:flex-end'),
  commission:app.includes('毛利润的95%发给闲家')&&app.includes('赢家毛利润5%佣金'),
  noTimeline:!app.includes('具体触发时间')
};
for(const [k,v] of Object.entries(checks))console.log(v?'PASS':'FAIL',k);
process.exit(Object.values(checks).every(Boolean)?0:1);
