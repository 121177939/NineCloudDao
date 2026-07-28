#!/usr/bin/env node
'use strict';
const fs=require('fs'),path=require('path'),vm=require('vm');
const root=path.resolve(process.argv[2]||process.argv[1]||'.');
let source=fs.readFileSync(path.join(root,'app.js'),'utf8');
const sql=fs.readFileSync(path.join(root,'database/V0.15.1/202607282010_v0151_casino_world_feed_dealer_and_fish_40s.sql'),'utf8');
const marker='\n  bootstrap();\n})();';
if(!source.includes(marker)) throw new Error('bootstrap marker missing');
source=source.replace(marker,`\n  globalThis.__fish151={marketPanelHtml,state};\n})();`);
const el=()=>({textContent:'',innerHTML:'',value:'',disabled:false,style:{setProperty(){}},addEventListener(){},classList:{toggle(){},add(){},remove(){}},querySelector(){return null;}});
const context={console,URL,Intl,Date,Math,JSON,Number,String,Boolean,Array,Object,RegExp,Promise,setTimeout,clearTimeout,setInterval,clearInterval,requestAnimationFrame:cb=>{cb();return 1},cancelAnimationFrame(){},localStorage:{getItem(){return null},setItem(){},removeItem(){}},sessionStorage:{getItem(){return null},setItem(){},removeItem(){}},document:{hidden:false,documentElement:{clientWidth:390,style:{setProperty(){}}},getElementById:()=>el(),addEventListener(){},querySelectorAll:()=>[],querySelector:()=>null},window:{GAME_CONFIG:{supabaseUrl:'https://example.supabase.co',supabasePublishableKey:'test',version:'0.15.1'},innerWidth:390,addEventListener(){},matchMedia:()=>({matches:true,addEventListener(){}}),history:{replaceState(){},pushState(){},back(){},state:null},location:{hash:'',pathname:'/',search:'',replace(){}},scrollTo(){}},navigator:{},crypto:{randomUUID:()=> '11111111-1111-4111-8111-111111111111'},CSS:{escape:v=>String(v)}};
context.globalThis=context;vm.createContext(context);vm.runInContext(source,context,{filename:'app.js'});
const f=context.__fish151;
f.state.casinoDrafts.house.game='fish_shrimp';f.state.casinoView='house';f.state.casinoHouseMode='player';
f.state.fishShrimpDraft={stakeType:'spirit_stone',quantity:10000,multiplier:10};
f.state.fishShrimpState={server_now:'2026-07-28T08:00:38Z',round:{id:'r40',round_no:456,starts_at:'2026-07-28T08:00:00Z',betting_closes_at:'2026-07-28T08:00:30Z',reveal_at:'2026-07-28T08:00:32Z',settles_at:'2026-07-28T08:00:37Z',ends_at:'2026-07-28T08:00:40Z',phase:'settled',seconds_remaining:2,elapsed_seconds:38,results:['fish','shrimp','coin'],is_settled:true},character:{spirit_stones:5000000,cultivation_available:9000000},player_house:{mode:'player',dealer_name:'青玄真人',dealer_wealth:9000000},my_bets:[],round_totals:[],history:[]};
const data={status:'active',settings:{},character:f.state.fishShrimpState.character,activity:{},pools:{},tickets:{},player_house:f.state.fishShrimpState.player_house,open_duels:[],my_duels:[],latest_draws:[]};
const html=f.marketPanelHtml(data,'house');
const checks=[
 ['40 second subtitle',html.includes('40秒公共开盘')&&html.includes('公共40秒轮次')],
 ['40 second rules',html.includes('每局40秒')&&html.includes('前30秒下注')&&html.includes('5秒依次开骰')],
 ['progress denominator',source.includes('elapsed/40*100')&&!source.includes('elapsed/60*100')],
 ['client fallback times',source.includes('start + 30000')&&source.includes('start + 32000')&&source.includes('start + 37000')&&source.includes('start + 40000')],
 ['30 second SQL timing',sql.includes("interval '30 seconds'")&&sql.includes("interval '32 seconds'")&&sql.includes("interval '37 seconds'")&&sql.includes("interval '40 seconds'")],
 ['dice stop times',source.includes('33 + index * 2')],
 ['continuous bet preserved',source.includes('enqueueFishShrimpBetV0150')&&source.includes('processFishShrimpBetQueueV0150')],
 ['fish feed helper',sql.includes('world_event_publish_fish_round_v0151')&&sql.includes("'casino_fish_rounds_v0148'")],
 ['system dealer wording',sql.includes("else '荷老' end")&&sql.includes('与%s对局')],
 ['player dealer wording',sql.includes("format('玩家庄【%s】'")&&sql.includes('dealer_name_snapshot')],
 ['net win and loss wording',sql.includes('本局净赢')&&sql.includes('本局净输')],
 ['fish aggregation',sql.includes('sum(b.net_profit)::bigint as net_change')&&sql.includes('group by b.character_id,b.house_mode,b.dealer_character_id,b.stake_type')],
 ['settlement publish isolated',sql.includes('广播失败不得阻断赌局结算')&&sql.includes('perform public.world_event_publish_fish_round_v0151(p_round_id)')],
 ['40 second database clock',sql.includes('clock_timestamp())/40')&&sql.includes("interval '30 seconds'")&&sql.includes("interval '32 seconds'")&&sql.includes("interval '37 seconds'")&&sql.includes("interval '40 seconds'")]
];
for(const [name,ok] of checks) console.log(ok?'PASS':'FAIL',name);
const failed=checks.filter(([,ok])=>!ok);console.log(`TOTAL=${checks.length} PASS=${checks.length-failed.length} FAIL=${failed.length}`);if(failed.length)process.exit(1);
