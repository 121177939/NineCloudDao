#!/usr/bin/env node
const fs=require('fs'),path=require('path'),vm=require('vm');
const root=path.resolve(process.argv[2]||path.join(__dirname,'..')); let source=fs.readFileSync(path.join(root,'app.js'),'utf8');
const marker='\n  bootstrap();\n})();'; if(!source.includes(marker)) throw new Error('bootstrap marker missing');
source=source.replace(marker,`\n  globalThis.__ncdTestExports={bazaarPanelHtml,marketPanelHtml,mergeCanonicalSpiritStoneInventory,casinoStakeBase,mobileBottomNavHtml,getCasinoDraft,state};\n})();`);
const el=()=>({textContent:'',innerHTML:'',style:{setProperty(){}},addEventListener(){},classList:{toggle(){},add(){},remove(){}}});
const context={console,URL,Intl,Date,Math,JSON,Number,String,Boolean,Array,Object,RegExp,Promise,setTimeout,clearTimeout,setInterval,clearInterval,requestAnimationFrame:cb=>{cb();return 1},cancelAnimationFrame(){},localStorage:{getItem(){return null},setItem(){},removeItem(){}},document:{hidden:false,documentElement:{clientWidth:390,style:{setProperty(){}}},getElementById:()=>el(),addEventListener(){},querySelectorAll:()=>[]},window:{GAME_CONFIG:{supabaseUrl:'https://example.supabase.co',supabasePublishableKey:'test',version:'0.14.1'},innerWidth:390,addEventListener(){},matchMedia:()=>({matches:true,addEventListener(){}}),history:{pushState(){},back(){},state:null},location:{hash:'',pathname:'/',search:''},scrollTo(){}},history:{replaceState(){}},location:{hash:'',pathname:'/',search:''},navigator:{},crypto:{randomUUID:()=> '11111111-1111-4111-8111-111111111111'},CSS:{escape:v=>String(v)}}; context.globalThis=context; vm.createContext(context); vm.runInContext(source,context,{filename:'app.js'});
const f=context.__ncdTestExports; const data={status:'active',settings:{pool_hit_chance:.4,quick_multipliers:[1,5,10,50,100]},character:{spirit_stones:12345,cultivation_available:500000,cultivation_max_stake:100000,cultivation_eligible:true,cultivation_full:false},activity:{total_count:88},pools:{spirit_stone:{amount:10000,ticket_count:2,seconds_remaining:100},cultivation:{amount:200000,ticket_count:1,seconds_remaining:100}},tickets:{spirit_stone:1,cultivation:0},open_duels:[],my_duels:[],latest_draws:[{stake_type:'spirit_stone',pool_amount:10000,prize_amount:0,did_hit:false,candidate_name:'甲',ticket_count:2,result_text:'未中滚存'}]};
const lobby=f.marketPanelHtml(data,'lobby'),house=f.marketPanelHtml(data,'house'),duel=f.marketPanelHtml(data,'duel'),pools=f.marketPanelHtml(data,'pools');
for(const [name,html,tokens] of [['lobby',lobby,['大堂','贵宾雅间','全服造化池','已取消每日次数限制','统一灵石']],['house',house,['灵骰问道','气运龟卜','赌注资源','快捷倍数','自定义赌注数量','确认落注并立即开局','押100、1倍胜出共到账195','败局余下95%']],['duel',duel,['贵宾雅间','灵拳对弈','五行灵拳','确认赌注并封招开桌','双方各押100','胜者共到账195','奖池增加5']],['pools',pools,['40%','60%','大堂每一局赌注的5%进入奖池','败者赌注的5%进入奖池、95%转给胜者','不会叠加个人中奖权重','未中滚存']]]) for(const t of tokens) if(!html.includes(t)) throw new Error(`${name} missing ${t}`);

f.state.marketSystem=data;
f.state.casinoDrafts.house={stakeType:'cultivation',amount:250000,multiplier:5,game:'turtle_oracle',choice:'ominous'};
f.state.casinoDrafts.duel={stakeType:'cultivation',amount:100000,multiplier:null,game:'five_elements',choice:'fire'};
const preservedHouse=f.marketPanelHtml(data,'house');
for(const token of ['value="cultivation" selected','value="250000"','data-stake-multiplier="5"','class="active" type="button" data-house-select-game="turtle_oracle"','value="ominous" selected']) if(!preservedHouse.includes(token)) throw new Error(`house draft persistence missing ${token}`);
const preservedDuel=f.marketPanelHtml(data,'duel');
for(const token of ['value="cultivation" selected','value="100000"','value="five_elements" selected']) if(!preservedDuel.includes(token)) throw new Error(`duel draft persistence missing ${token}`);
if(f.getCasinoDraft('duel',data).choice!=='fire') throw new Error('duel choice draft persistence failed');

const merged=f.mergeCanonicalSpiritStoneInventory([{id:'a',quantity:10,is_bound:true,definition:{code:'spirit_stone',name:'灵石'}},{id:'b',quantity:20,is_bound:false,definition:{code:'spirit_stone',name:'灵石'}},{id:'c',quantity:1,definition:{code:'pill',name:'丹'}}]); if(merged.filter(x=>x.definition.code==='spirit_stone').length!==1||merged[0].quantity!==30||merged[0].is_bound!==false) throw new Error('currency merge failed');
if(f.casinoStakeBase('spirit_stone')!==100||f.casinoStakeBase('cultivation')!==50000) throw new Error('stake bases failed');
const nav=f.mobileBottomNavHtml('market'); if(!nav.includes('市坊')||nav.includes('data-mobile-tab="ranking"')) throw new Error('navigation failed');
const css=fs.readFileSync(path.join(root,'styles.css'),'utf8'); for(const t of ['.casino-mode-grid','.casino-stake-controls','.casino-multiplier-grid','.casino-record-row']) if(!css.includes(t)) throw new Error(`css missing ${t}`);
console.log(JSON.stringify({ok:true,checks:46,lobby:lobby.length,house:house.length,duel:duel.length,pools:pools.length}));
