#!/usr/bin/env node
const fs = require('fs');
const path = require('path');
const root = path.resolve(process.argv[2] || path.join(__dirname, '..'));
const app = fs.readFileSync(path.join(root, 'app.js'),'utf8');
const start = app.indexOf('  function marketPoolCard');
const end = app.indexOf('  function bindMarketActions', start);
if (start < 0 || end < 0) throw new Error('market functions not found');
function escapeHtml(value){return String(value??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#039;');}
function formatNumber(v){return Number(v||0).toLocaleString('zh-CN');}
function formatDuration(v){return `${Math.max(0,Math.floor(Number(v||0)))}秒`;}
eval(app.slice(start,end));
const base = {
 status:'active',
 pools:{spirit_stone:{amount:1200,seconds_remaining:300,last_prize:500,last_winner_name:'青玄'},cultivation:{amount:50000,seconds_remaining:600}},
 tickets:{spirit_stone:2,cultivation:1},
 activity:{house_count:2,duel_count:1,cultivation_count:1,total_count:3},
 open_duels:[{id:'11111111-1111-1111-1111-111111111111',creator_name:'玄微',game_code:'spirit_fist',stake_type:'spirit_stone',stake_amount:1000,expires_in:900}],
 my_duels:[{id:'222',status:'sealed',status_name:'赌契封存中',outcome:'sealed',opponent_name:'云岚',stake_type:'spirit_stone',stake_amount:1000,my_choice:'磐石势',opponent_choice:null,seconds_remaining:240,result_text:null}],
 latest_draws:[{stake_type:'spirit_stone',winner_name:'青玄',prize_amount:500,result_text:'造化显灵。'}]
};
const normal = marketPanelHtml({...base,character:{spirit_stones:9000,cultivation_available:300000,cultivation_max_stake:60000,cultivation_eligible:true,cultivation_full:false,cultivation_cap:800000}});
const full = marketPanelHtml({...base,character:{spirit_stones:9000,cultivation_available:0,cultivation_max_stake:0,cultivation_eligible:false,cultivation_full:true,cultivation_cap:800000}});
for (const token of ['灵石造化池','修为造化池','封招应局','灵拳对弈','五行灵拳','五分钟','玄微','磐石势','未知']) {
  if (!normal.includes(token)) throw new Error(`missing ${token}`);
}
if (!full.includes('圆满后禁止')) throw new Error('cultivation-full casino label missing');
if (full.includes('<option value="cultivation" >')) throw new Error('full cultivation option not disabled');
if (normal.includes('云岚】') && normal.includes('对手：【云岚')) throw new Error('opponent move leak');
console.log(JSON.stringify({ok:true,normalLength:normal.length,fullLength:full.length,checks:12}));
