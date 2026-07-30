#!/usr/bin/env node
const fs=require('fs'),path=require('path');
const root=path.resolve(process.argv[2]||path.join(__dirname,'..'));
const app=fs.readFileSync(path.join(root,'app.js'),'utf8');
const sql=fs.readFileSync(path.join(root,'SQL/50_V1.1_双向战力挑战与界闻修复.sql'),'utf8');
const checks={
 'ranking bidirectional':app.includes('高低战力均可互相挑战')&&sql.includes("'can_challenge',id<>v_self_id"),
 'daily 20':app.includes('今日的20次主动挑战')&&sql.includes('active_challenge_daily_limit=20'),
 'cooldown 20':app.includes('等待20分钟')&&sql.includes('challenge_cooldown_minutes=20'),
 'same opponent allowed':app.includes('可以重复挑战同一对手')&&!sql.includes('PAIR_CHALLENGE_DAILY_LIMIT'),
 'stage progress rates':app.includes('当前阶段进度')&&sql.includes('higher_power_win_rate=0.005')&&sql.includes('lower_power_win_rate=0.01'),
 'no stage drop':sql.includes('greatest(v_loser_stage_floor,cultivation-v_transfer)'),
 'equal transfer':sql.includes('v_escrow:=v_transfer-v_granted'),
 'world event correct table':sql.includes('update public.jiuxiao_world_events')&&!sql.includes('update public.world_events'),
 'history backfill':sql.includes('set world_event_id=world_event_id'),
 'old higher-only error removed':!app.includes('只能挑战战力高于自己的角色')&&!sql.includes('TARGET_POWER_NOT_HIGHER')
};
for(const [k,v] of Object.entries(checks))console.log((v?'PASS ':'FAIL ')+k);
const failed=Object.entries(checks).filter(([,v])=>!v).map(([k])=>k);
if(failed.length)throw new Error('failed: '+failed.join(', '));
console.log(JSON.stringify({ok:true,checks:Object.keys(checks).length}));
