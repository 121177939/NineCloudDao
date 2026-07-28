'use strict';
const fs=require('fs'),path=require('path'),vm=require('vm');
const root=path.resolve(process.argv[2]||process.argv[1]||'.');
let source=fs.readFileSync(path.join(root,'app.js'),'utf8');
const css=fs.readFileSync(path.join(root,'styles.css'),'utf8');
const sql=fs.readFileSync(path.join(root,'database/V0.14.8/202607281630_v0148_fish_shrimp_mobile_casino.sql'),'utf8');
const checks=[
 ['B summary 2x2',css.includes('.casino-lobby-summary')&&css.includes('repeat(2, minmax(0, 1fr))')],
 ['B primary nav 1x4',source.includes('casinoPrimaryNavHtml')&&css.includes('repeat(4, minmax(0, 1fr))')],
 ['B lobby 2x2',source.includes('playerHouseLobbyCardsHtml')&&source.includes('data-casino-dealer-status')],
 ['formal naming',source.includes("casino: ['赌坊 · 万运博弈楼'")&&!source.includes('墨玉赌坊')],
 ['fish rpc',source.includes('rpcGetFishShrimpStateV0148')&&source.includes('rpcPlaceFishShrimpBetV0148')],
 ['fish selector',source.includes('data-house-select-game="fish_shrimp"')&&source.includes('鱼虾灵局')],
 ['compact order',source.indexOf('fish-bet-controls')<source.indexOf('fish-draw-block')&&source.indexOf('fish-draw-block')<source.indexOf('fish-target-grid')],
 ['six symbols', ['fish','shrimp','crab','coin','gourd','frog'].every(x=>source.includes(`['${x}'`))],
 ['three columns',css.includes('.fish-target-grid')&&css.includes('grid-template-columns: repeat(3')],
 ['hit glow',source.includes("hit ? 'win'")&&source.includes('myAmount > 0')&&css.includes('fishWinningGlow')],
 ['history 20',source.includes('最近20局结算历史')&&source.includes('get_fish_shrimp_state_v0148')],
 ['dealer label once grouping',source.includes('fishShrimpHistoryGroupHtmlV0148')&&source.includes('fish-history-group-summary')&&!source.includes('const dealerText = groups.length')],
 ['60 second SQL',sql.includes("interval '40 seconds'")&&sql.includes("interval '43 seconds'")&&sql.includes("interval '49 seconds'")&&sql.includes("interval '60 seconds'")],
 ['player house rules',sql.includes('CASINO_PLAYER_HOUSE_ONLY_SPIRIT_STONE')&&sql.includes('CASINO_PLAYER_HOUSE_SELF_BET_FORBIDDEN')&&sql.includes('v_system_cover:=greatest')],
 ['no demo placeholders',!source.includes('未来玩法一')&&!source.includes('未来玩法二')]
];
for(const [name,ok] of checks) console.log(ok?'PASS':'FAIL',name);
const failed=checks.filter(x=>!x[1]);
console.log(`TOTAL=${checks.length} PASS=${checks.length-failed.length} FAIL=${failed.length}`);
if(failed.length) process.exit(1);
