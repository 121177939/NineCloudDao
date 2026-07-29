#!/usr/bin/env node
const fs=require('fs'),path=require('path');
const root=path.resolve(process.argv[2]||path.join(__dirname,'..'));
const app=fs.readFileSync(path.join(root,'app.js'),'utf8');
const css=fs.readFileSync(path.join(root,'styles.css'),'utf8');
const sql=fs.readFileSync(path.join(root,'SQL/40_V1.0_FIX3_挑战界闻趣味文案.sql'),'utf8');
const playbackStart=app.indexOf('function showBattlePlaybackBCombat01');
const playbackEnd=app.indexOf('function bindDestinyRankingActions',playbackStart);
const playback=app.slice(playbackStart,playbackEnd);
const duelStart=app.indexOf('function battleDuelCombatantHtmlFix3');
const duelEnd=app.indexOf('function closeBattleChallengeModalBCombat01',duelStart);
const duel=app.slice(duelStart,duelEnd);
const checks={
  'duel summary helper':duel.includes('battle-duel-combatant-fix3')&&duel.includes('我方')===false&&duel.includes('<b>战力</b>')&&duel.includes('<b>五行</b>'),
  'duel excludes level':!duel.includes('<b>等级</b>')&&!duel.includes('row?.realm'),
  'my side and opponent':playback.includes("'我方'")&&playback.includes("'对方'"),
  'log precedes controls':playback.indexOf('battle-log-bcombat01 battle-log-fix3')<playback.indexOf('battle-playback-controls-bcombat01 battle-controls-fix3'),
  'speed controls kept':playback.includes('data-battle-speed="1"')&&playback.includes('data-battle-speed="2"')&&playback.includes('data-battle-skip'),
  'modal grid layout':css.includes('grid-template-rows: auto auto minmax(0,1fr) auto'),
  'expanded log':css.includes('.battle-log-bcombat01.battle-log-fix3')&&css.includes('max-height: none'),
  'compact controls':css.includes('.battle-playback-controls-bcombat01.battle-controls-fix3')&&css.includes('min-height: 31px'),
  'story names challenge relation':sql.includes('向%s发起挑战')&&sql.includes('挑战失败'),
  'story weapons and cultivation':sql.includes('weapon_name')&&sql.includes('被夺走%s点修为'),
  'story variants': ['摧枯拉朽','险胜半招','五行相制','越阶破敌','守榜退敌','轻敌折戟','道途受挫'].every(x=>sql.includes(x)),
  'story failure isolation':sql.includes('九霄界闻文案失败不得影响挑战结算')&&sql.includes('exception when others'),
  'no extra feed subline':!sql.includes('挑战者 →')&&!sql.includes('修为转移')
};
for(const [k,v] of Object.entries(checks)) console.log((v?'PASS ':'FAIL ')+k);
const failed=Object.entries(checks).filter(([,v])=>!v).map(([k])=>k);
if(failed.length) throw new Error('failed: '+failed.join(', '));
console.log(JSON.stringify({ok:true,checks:Object.keys(checks).length}));
