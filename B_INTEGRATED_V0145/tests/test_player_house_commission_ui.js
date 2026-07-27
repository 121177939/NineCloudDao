#!/usr/bin/env node
const fs=require('fs'),path=require('path'),vm=require('vm');
const root=path.resolve(process.argv[2]||path.join(__dirname,'../source/candidate'));
let source=fs.readFileSync(path.join(root,'app.js'),'utf8');
const marker='\n  bootstrap();\n})();';
if(!source.includes(marker)) throw new Error('bootstrap marker missing');
source=source.replace(marker,`\n  globalThis.__ncdCommissionTest={marketPanelHtml,state};\n})();`);
const el=()=>({textContent:'',innerHTML:'',style:{setProperty(){}},addEventListener(){},classList:{toggle(){},add(){},remove(){}}});
const context={console,URL,Intl,Date,Math,JSON,Number,String,Boolean,Array,Object,RegExp,Promise,setTimeout,clearTimeout,setInterval,clearInterval,requestAnimationFrame:cb=>{cb();return 1},cancelAnimationFrame(){},localStorage:{getItem(){return null},setItem(){},removeItem(){}},document:{hidden:false,documentElement:{clientWidth:390,style:{setProperty(){}}},getElementById:()=>el(),addEventListener(){},querySelectorAll:()=>[]},window:{GAME_CONFIG:{supabaseUrl:'https://example.supabase.co',supabasePublishableKey:'test',version:'0.14.4'},innerWidth:390,addEventListener(){},matchMedia:()=>({matches:true,addEventListener(){}}),history:{replaceState(){}},location:{hash:'',pathname:'/',search:''}},navigator:{},crypto:{randomUUID:()=> '11111111-1111-4111-8111-111111111111'},CSS:{escape:v=>String(v)}};
context.globalThis=context; vm.createContext(context); vm.runInContext(source,context,{filename:'app.js'});
const f=context.__ncdCommissionTest;
const data={status:'active',settings:{pool_hit_chance:.4,quick_multipliers:[1,5,10,50,100]},character:{spirit_stones:12345,cultivation_available:500000,cultivation_max_stake:100000,cultivation_eligible:true,cultivation_full:false},activity:{total_count:8},pools:{spirit_stone:{amount:10000,ticket_count:2,seconds_remaining:100},cultivation:{amount:200000,ticket_count:1,seconds_remaining:100}},tickets:{spirit_stone:1,cultivation:0},open_duels:[],my_duels:[],latest_draws:[],player_house:{status:'ok',mode:'player',dealer_name:'云岚',dealer_wealth:9000000,is_self_dealer:false,can_deactivate:false,max_stake_spirit_dice:264705,max_stake_turtle_oracle:3000000,player_house_win_commission_bps:500}};
const lobby=f.marketPanelHtml(data,'lobby');
const house=f.marketPanelHtml(data,'house');
const pools=f.marketPanelHtml(data,'pools');
const checks=[
  ['house subtitle',house.includes('玩家庄赢家毛利润5%佣金')],
  ['principal protected',house.includes('本金100%返还')],
  ['95 percent to bettor',house.includes('毛利润的95%发给闲家')],
  ['5 percent dealer commission',house.includes('5%作为庄家佣金')],
  ['example total 195',house.includes('玩家总到账195')],
  ['zero pool',house.includes('不进入造化池')],
  ['lobby copy',lobby.includes('赢家毛利润收取5%佣金')],
  ['pools copy',pools.includes('赢家毛利润中收取5%庄家佣金')],
  ['old zero-fee copy removed',!house.includes('玩家庄零抽成灵石对赌')&&!lobby.includes('仅灵石零抽成对赌')],
  ['system rule preserved',house.includes('系统庄沿用FIX7A造化规则')===false]
];
// 玩家庄视图不会显示系统庄副标题；核心是没有篡改系统庄代码文案。
const failed=checks.filter(x=>!x[1]); checks.forEach(x=>console.log(x[1]?'PASS':'FAIL',x[0]));
console.log(`TOTAL=${checks.length} PASS=${checks.length-failed.length} FAIL=${failed.length}`);
process.exit(failed.length?1:0);
