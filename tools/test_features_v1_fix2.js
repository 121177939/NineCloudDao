#!/usr/bin/env node
const fs=require('fs'),path=require('path');
const root=path.resolve(process.argv[2]||path.join(__dirname,'..'));
const app=fs.readFileSync(path.join(root,'app.js'),'utf8');
const css=fs.readFileSync(path.join(root,'styles.css'),'utf8');
const checks={
  'no champion copy':!app.includes('修为榜首')&&!app.includes('财富榜首')&&!app.includes('战力榜首'),
  'no champion render':!app.includes('class="destiny-champion ${champion'),
  'battle rank private stats removed':!app.includes('<span>道攻 ${formatNumber(row.dao_attack'),
  'compact public card':app.includes('battle-combatant-card-compact-fix2')&&app.includes('<b>等级</b>')&&app.includes('<b>战力</b>')&&app.includes('<b>五行</b>'),
  'separate resolving popup':app.includes('showBattleResolvingModalBCombat01')&&app.includes('战局推演中'),
  'separate report popup':app.includes('battle-report-backdrop-fix2')&&app.includes('挑战战报'),
  'generic battle copy':app.includes('凝聚灵力，正面攻向')&&!app.includes('${attacker}赤手空拳，运转'),
  'css compact':css.includes('.battle-combatant-public-fix2'),
  'css report':css.includes('.battle-report-modal-fix2')
};
for(const [k,v] of Object.entries(checks)) console.log((v?'PASS ':'FAIL ')+k);
const failed=Object.entries(checks).filter(([,v])=>!v).map(([k])=>k);
if(failed.length) throw new Error('failed: '+failed.join(', '));
console.log(JSON.stringify({ok:true,checks:Object.keys(checks).length}));
