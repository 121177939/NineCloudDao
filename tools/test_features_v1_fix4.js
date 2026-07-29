#!/usr/bin/env node
const fs=require('fs'),path=require('path');
const root=path.resolve(process.argv[2]||path.join(__dirname,'..'));
const app=fs.readFileSync(path.join(root,'app.js'),'utf8');
const sql=fs.readFileSync(path.join(root,'SQL/45_V1.0_FIX4_赌坊安全结算.sql'),'utf8');
const checks={
 'new house rpc':app.includes("rpc/play_house_game_v1_fix4")&&sql.includes('play_house_game_v1_fix4'),
 'new fish rpc':app.includes("rpc/place_fish_shrimp_bet_v1_fix4")&&sql.includes('place_fish_shrimp_bet_v1_fix4'),
 'request id':app.includes('casinoRequestIdFix4')&&app.includes('p_request_id')&&sql.includes('casino_bet_requests_v1'),
 'ten percent ui':app.includes('10%')&&app.includes('CASINO_STAKE_EXCEEDS_TEN_PERCENT'),
 'ten percent sql':sql.includes('house_stake_limit_bps')&&sql.includes('casino_house_stake_limit_v1'),
 'no system cover':sql.includes("'player_house_system_cover',false")&&sql.includes('system_cover_amount=0'),
 'max liability':sql.includes('v_max_liability')&&sql.includes('dealer_reserved_amount'),
 'five percent pool':app.includes('5%')&&sql.includes('casino_pools')&&sql.includes('v_fee_bps'),
 'old rpc closed':sql.includes('revoke all on function public.play_house_game_v0147')&&sql.includes('revoke all on function public.place_fish_shrimp_bet_v0148'),
 'parameter mismatch':sql.includes('CASINO_REQUEST_PARAMETER_MISMATCH')&&app.includes('CASINO_REQUEST_PARAMETER_MISMATCH'),
 'unsafe copy removed':!app.includes('玩家庄局不限下注金额')&&!app.includes('不足由荷老补足')
};
for(const [k,v] of Object.entries(checks)) console.log((v?'PASS ':'FAIL ')+k);
const failed=Object.entries(checks).filter(([,v])=>!v).map(([k])=>k);
if(failed.length) throw new Error('failed: '+failed.join(', '));
console.log(JSON.stringify({ok:true,checks:Object.keys(checks).length}));
