#!/usr/bin/env node
'use strict';
const fs=require('fs'),path=require('path'),vm=require('vm');
const root=path.resolve(process.argv[2]||process.argv[1]||'.');
let source=fs.readFileSync(path.join(root,'app.js'),'utf8');
const marker='\n  bootstrap();\n})();';
if(!source.includes(marker)) throw new Error('bootstrap marker missing');
source=source.replace(marker,`\n  globalThis.__fishTest={marketPanelHtml,state};\n})();`);
const el=()=>({textContent:'',innerHTML:'',value:'',disabled:false,style:{setProperty(){}},addEventListener(){},classList:{toggle(){},add(){},remove(){}}});
const context={console,URL,Intl,Date,Math,JSON,Number,String,Boolean,Array,Object,RegExp,Promise,setTimeout,clearTimeout,setInterval,clearInterval,requestAnimationFrame:cb=>{cb();return 1},cancelAnimationFrame(){},localStorage:{getItem(){return null},setItem(){},removeItem(){}},sessionStorage:{getItem(){return null},setItem(){},removeItem(){}},document:{hidden:false,documentElement:{clientWidth:390,style:{setProperty(){}}},getElementById:()=>el(),addEventListener(){},querySelectorAll:()=>[]},window:{GAME_CONFIG:{supabaseUrl:'https://example.supabase.co',supabasePublishableKey:'test',version:'0.14.9'},innerWidth:390,addEventListener(){},matchMedia:()=>({matches:true,addEventListener(){}}),history:{replaceState(){},pushState(){},back(){},state:null},location:{hash:'',pathname:'/',search:'',replace(){}},scrollTo(){}},navigator:{},crypto:{randomUUID:()=> '11111111-1111-4111-8111-111111111111'},CSS:{escape:v=>String(v)}};
context.globalThis=context; vm.createContext(context); vm.runInContext(source,context,{filename:'app.js'});
const f=context.__fishTest;
f.state.casinoDrafts.house.game='fish_shrimp';
f.state.casinoView='house';
f.state.casinoHouseMode='system';
f.state.fishShrimpDraft={stakeType:'spirit_stone',quantity:100,multiplier:10};
f.state.fishShrimpState={
 server_now:'2026-07-28T08:00:45Z',
 round:{id:'r1',round_no:123,starts_at:'2026-07-28T08:00:00Z',betting_closes_at:'2026-07-28T08:00:40Z',reveal_at:'2026-07-28T08:00:43Z',settles_at:'2026-07-28T08:00:49Z',ends_at:'2026-07-28T08:01:00Z',phase:'settled',seconds_remaining:5,elapsed_seconds:52,results:['fish','coin','fish'],is_settled:true},
 character:{spirit_stones:5000000,cultivation_available:9000000},
 player_house:{mode:'player',dealer_name:'测试庄家',dealer_wealth:3000000},
 my_bets:[
  {house_mode:'system',stake_type:'spirit_stone',symbol_code:'fish',stake_amount:1000,net_profit:1900,result_count:2,is_settled:true},
  {house_mode:'system',stake_type:'spirit_stone',symbol_code:'shrimp',stake_amount:1000,net_profit:-1000,result_count:0,is_settled:true}
 ],
 round_totals:[
  {house_mode:'system',stake_type:'spirit_stone',symbol_code:'fish',stake_amount:5000},
  {house_mode:'system',stake_type:'spirit_stone',symbol_code:'shrimp',stake_amount:3000}
 ],
 history:[{round_no:123,results:['fish','coin','fish'],has_bets:true,groups:[{house_mode:'system',dealer_label:'荷老局',items:[{stake_type:'spirit_stone',symbol_code:'fish',symbol_name:'鱼',stake_amount:1000,net_profit:1900,result_count:2},{stake_type:'spirit_stone',symbol_code:'shrimp',symbol_name:'虾',stake_amount:1000,net_profit:-1000,result_count:0}]}]}]
};
const data={status:'active',settings:{quick_multipliers:[1,10,100]},character:f.state.fishShrimpState.character,activity:{total_count:0},pools:{spirit_stone:{amount:1,ticket_count:0,seconds_remaining:1},cultivation:{amount:1,ticket_count:0,seconds_remaining:1}},tickets:{},player_house:f.state.fishShrimpState.player_house,open_duels:[],my_duels:[],latest_draws:[]};
const html=f.marketPanelHtml(data,'house');
const pos=[html.indexOf('押注设置'),html.indexOf('开盘灵骰'),html.indexOf('选择压什么'),html.indexOf('最近20局结算历史'),html.indexOf('结算明细')];
const fishCard=(html.match(/class="fish-target-card win"[^>]*data-fish-symbol="fish"/)||[]).length;
const shrimpCard=(html.match(/class="fish-target-card win"[^>]*data-fish-symbol="shrimp"/)||[]).length;
const historyDealerCount=(html.match(/class="fish-history-group-summary"><strong>荷老局<\/strong>/g)||[]).length;
const css=fs.readFileSync(path.join(root,'styles.css'),'utf8');
const checks=[
 ['page renders',html.includes('fish-game-shell')&&html.includes('鱼虾灵局')],
 ['six inline svg seals',['fish','shrimp','crab','coin','gourd','frog'].every(code=>html.includes(`fish-seal-${code}`))&&(html.match(/<svg viewBox=\"0 0 100 100\"/g)||[]).length>=6],
 ['desktop responsive layout',css.includes('.fish-game-shell {')&&css.includes('width: 100%;')&&css.includes('max-width: none;')&&!css.includes('width: min(100%, 460px)')],
 ['strict order',pos.every(x=>x>=0)&&pos.every((x,i)=>i===0||pos[i-1]<x)],
 ['compact balances',html.includes('可用灵石')&&html.includes('可用修为')],
 ['quantity multiplier',html.includes('100 × 10')&&html.includes('1,000 灵石')],
 ['three results',html.includes('鱼')&&html.includes('铜钱')],
 ['hit only actual winning bet',fishCard===1&&shrimpCard===0],
 ['dealer once in detail',html.includes('<strong>荷老局</strong>')],
 ['history dealer label once',historyDealerCount===1&&!html.includes('荷老局：')],
 ['player switch exists',html.includes('测试庄家')]
];
for(const [name,ok] of checks) console.log(ok?'PASS':'FAIL',name);
const failed=checks.filter(x=>!x[1]); console.log(`TOTAL=${checks.length} PASS=${checks.length-failed.length} FAIL=${failed.length}`); if(failed.length) process.exit(1);
