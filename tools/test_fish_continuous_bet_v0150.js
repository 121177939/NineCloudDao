#!/usr/bin/env node
'use strict';
const fs=require('fs'),path=require('path'),vm=require('vm');
const root=path.resolve(process.argv[2]||'.');
const source=fs.readFileSync(path.join(root,'app.js'),'utf8');
const css=fs.readFileSync(path.join(root,'styles.css'),'utf8');

const start=source.lastIndexOf("document.querySelectorAll('[data-fish-symbol]')");
const end=source.indexOf("document.querySelectorAll('[data-fish-refresh]')",start);
if(start<0||end<0) throw new Error('fish click handler missing');
const handler=source.slice(start,end);

const checks=[
 ['queue helper exists',source.includes('function enqueueFishShrimpBetV0150')&&source.includes('function processFishShrimpBetQueueV0150')],
 ['button never busy locked',!handler.includes('setBusy(')&&!handler.includes('落注中')],
 ['click enqueues immediately',handler.includes('enqueueFishShrimpBetV0150(')],
 ['queue batches clicks',source.includes('existing.amount = nextAmount')&&source.includes('existing.clickCount')],
 ['queue serial worker',source.includes('state.fishShrimpBetProcessing = true')&&source.includes('while (queue.length)')],
 ['queue delay window',source.includes('}, 120);')],
 ['pending amount shown',source.includes('data-fish-pending')&&source.includes('待提交 +')],
 ['queue feedback says continue',source.includes('可连续选择法印')],
 ['refresh guarded during queue',source.includes('state.fishShrimpBetProcessing || !state.character')],
 ['only phase disables cards',source.includes("button.disabled = phase !== 'betting'")],
 ['queued css exists',css.includes('.fish-target-card.queued')&&css.includes('.fish-target-pending')]
];

// Reference model: five rapid clicks on fish become one batch of 5x amount,
// while a shrimp click remains a separate queued batch.
const queue=[];
function enqueue(key,amount){
 const existing=queue.find(x=>x.key===key&&!x.processing);
 if(existing){existing.amount+=amount;existing.clickCount+=1;}
 else queue.push({key,amount,clickCount:1,processing:false});
}
for(let i=0;i<5;i++) enqueue('r1|system|spirit_stone|fish',10000);
enqueue('r1|system|spirit_stone|shrimp',10000);
checks.push(['five fish clicks merged',queue[0].amount===50000&&queue[0].clickCount===5]);
checks.push(['different symbol separate',queue.length===2&&queue[1].amount===10000]);

// Render regression: pending queue is visible on the matching card.
let runtime=source;
const marker='\n  bootstrap();\n})();';
if(!runtime.includes(marker)) throw new Error('bootstrap marker missing');
runtime=runtime.replace(marker,`\n  globalThis.__fishV0150={marketPanelHtml,state};\n})();`);
const el=()=>({textContent:'',innerHTML:'',value:'',disabled:false,style:{setProperty(){}},addEventListener(){},classList:{toggle(){},add(){},remove(){}},querySelector(){return null;}});
const context={console,URL,Intl,Date,Math,JSON,Number,String,Boolean,Array,Object,RegExp,Promise,setTimeout,clearTimeout,setInterval,clearInterval,requestAnimationFrame:cb=>{cb();return 1},cancelAnimationFrame(){},localStorage:{getItem(){return null},setItem(){},removeItem(){}},sessionStorage:{getItem(){return null},setItem(){},removeItem(){}},document:{hidden:false,documentElement:{clientWidth:390,style:{setProperty(){}}},getElementById:()=>el(),addEventListener(){},querySelectorAll:()=>[],querySelector:()=>null},window:{GAME_CONFIG:{supabaseUrl:'https://example.supabase.co',supabasePublishableKey:'test',version:'0.15.0'},innerWidth:390,addEventListener(){},matchMedia:()=>({matches:true,addEventListener(){}}),history:{replaceState(){},pushState(){},back(){},state:null},location:{hash:'',pathname:'/',search:'',replace(){}},scrollTo(){}},navigator:{},crypto:{randomUUID:()=> '11111111-1111-4111-8111-111111111111'},CSS:{escape:v=>String(v)}};
context.globalThis=context;vm.createContext(context);vm.runInContext(runtime,context,{filename:'app.js'});
const f=context.__fishV0150;
f.state.casinoDrafts.house.game='fish_shrimp';f.state.casinoView='house';f.state.casinoHouseMode='system';
f.state.fishShrimpDraft={stakeType:'spirit_stone',quantity:10000,multiplier:1};
f.state.fishShrimpState={server_now:'2026-07-28T08:00:10Z',round:{id:'r1',round_no:1,phase:'betting',seconds_remaining:30,elapsed_seconds:10,results:[],is_settled:false},character:{spirit_stones:5000000,cultivation_available:9000000},player_house:{mode:'system'},my_bets:[],round_totals:[],history:[]};
f.state.fishShrimpBetQueue=[{key:'r1|system|spirit_stone|fish',roundId:'r1',houseMode:'system',stakeType:'spirit_stone',symbolCode:'fish',amount:50000,clickCount:5,processing:false}];
const data={status:'active',settings:{},character:f.state.fishShrimpState.character,activity:{},pools:{},tickets:{},player_house:f.state.fishShrimpState.player_house,open_duels:[],my_duels:[],latest_draws:[]};
const html=f.marketPanelHtml(data,'house');
checks.push(['render shows pending fish',html.includes('data-fish-symbol="fish"')&&html.includes('待提交 +50,000')&&html.includes('fish-target-card queued')]);

for(const [name,ok] of checks) console.log(ok?'PASS':'FAIL',name);
const failed=checks.filter(([,ok])=>!ok);
console.log(`TOTAL=${checks.length} PASS=${checks.length-failed.length} FAIL=${failed.length}`);
if(failed.length) process.exit(1);
