#!/usr/bin/env node
const fs=require('fs'),path=require('path'),vm=require('vm');
const root=path.resolve(process.argv[2]||path.join(__dirname,'..'));
let source=fs.readFileSync(path.join(root,'app.js'),'utf8');
const marker='\n  bootstrap();\n})();';
if(!source.includes(marker)) throw new Error('bootstrap marker missing');
source=source.replace(marker,`\n  globalThis.__ncdTestExports={rankingCenterPanelHtml,rankingBoardTabsHtml};\n})();`);
const el=()=>({textContent:'',innerHTML:'',style:{setProperty(){}},addEventListener(){},classList:{toggle(){},add(){},remove(){}}});
const context={console,URL,Intl,Date,Math,JSON,Number,String,Boolean,Array,Object,RegExp,Promise,setTimeout,clearTimeout,setInterval,clearInterval,requestAnimationFrame:cb=>{cb();return 1},cancelAnimationFrame(){},localStorage:{getItem(){return null},setItem(){},removeItem(){}},document:{hidden:false,documentElement:{clientWidth:390,style:{setProperty(){}}},getElementById:()=>el(),addEventListener(){},querySelectorAll:()=>[]},window:{GAME_CONFIG:{supabaseUrl:'https://example.supabase.co',supabasePublishableKey:'test',version:'0.14.3'},innerWidth:390,addEventListener(){},matchMedia:()=>({matches:true,addEventListener(){}}),history:{pushState(){},back(){},state:null},location:{hash:'',pathname:'/',search:''},scrollTo(){}},history:{replaceState(){}},location:{hash:'',pathname:'/',search:''},navigator:{},crypto:{randomUUID:()=> '11111111-1111-4111-8111-111111111111'},CSS:{escape:v=>String(v)}};
context.globalThis=context;vm.createContext(context);vm.runInContext(source,context,{filename:'app.js'});
const f=context.__ncdTestExports;
const cultivation={status:'ok',total_count:1,has_more:false,ranking_rule:'修为规则',entries:[{rank:1,name:'周立',realm:'炼虚期 · 圆满',fate:'机缘深厚',generation:1,cultivation:67000000,is_self:false}]};
const wealth={status:'ok',total_count:1,has_more:false,ranking_rule:'财富规则',entries:[{rank:1,name:'唐枫',realm:'化神期 · 后期',fate:'功法领悟',generation:1,cultivation:9097090,wealth:1234567,is_self:true}]};
const c=f.rankingCenterPanelHtml('cultivation',cultivation,wealth);
for(const token of ['修为榜','财富榜','战力榜','67000000 修为','修为榜首']) if(!c.includes(token.replace('67000000','67,000,000'))) throw new Error('cultivation missing '+token);
if(c.includes('刷新天命')||c.includes('data-ranking-refresh')) throw new Error('manual refresh remains');
const w=f.rankingCenterPanelHtml('wealth',cultivation,wealth);
for(const token of ['财富榜首','唐枫','1,234,567 灵石','本尊']) if(!w.includes(token)) throw new Error('wealth missing '+token);
const hasBCombat01=source.includes('rpcGetBattlePowerRankingBCombat01');
if(hasBCombat01){
  const battle={status:'ok',total_count:1,has_more:false,ranking_rule:'四项战力',entries:[{rank:1,character_id:'22222222-2222-4222-8222-222222222222',name:'顾长歌',realm:'金丹 · 后期',fate:'天生剑心',generation:1,element:'fire',element_name:'火',power:9760,dao_attack:360,dao_defense:220,vitality:2200,agility:220,is_self:false,can_challenge:true}]};
  const b=f.rankingCenterPanelHtml('battle',cultivation,wealth,battle);
  for(const token of ['战力榜首','顾长歌','9,760 战力','火','道攻 360','data-battle-challenge-target']) if(!b.includes(token)) throw new Error('battle module missing '+token);
  if(!source.includes("battle: ['battleRankingSyncing', 'battleRanking', rpcGetBattlePowerRankingBCombat01]")) throw new Error('battle refresh mapping missing');
}else{
  const b=f.rankingCenterPanelHtml('battle',cultivation,wealth);
  for(const token of ['战力榜暂未开放','战斗体系与统一战力算法仍在推演中']) if(!b.includes(token)) throw new Error('battle placeholder missing '+token);
  if(!source.includes("if (safeBoard !== 'battle') refreshRankingBoard(safeBoard, false, true);")) throw new Error('switch refresh missing');
}
if(!source.includes("if (safeView === 'ranking' && previousView !== 'ranking')")) throw new Error('entry auto refresh trigger missing');
if(!source.includes("refreshRankingBoard('cultivation', false, true)")) throw new Error('entry cultivation refresh missing');
if(source.includes('state.destinyRankingSyncTimer = setInterval')) throw new Error('ranking periodic refresh remains');
const css=fs.readFileSync(path.join(root,'styles.css'),'utf8');
for(const token of ['.ranking-board-tabs','.ranking-board-tab.active','.ranking-unopened']) if(!css.includes(token)) throw new Error('css missing '+token);
console.log(JSON.stringify({ok:true,checks:hasBCombat01?21:16,module:hasBCombat01?'B-COMBAT01':'baseline'}));
