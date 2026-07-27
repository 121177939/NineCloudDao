#!/usr/bin/env node
const fs=require('fs'),path=require('path'),vm=require('vm');
const root=path.resolve(process.argv[2]||path.join(__dirname,'..'));
let source=fs.readFileSync(path.join(root,'app.js'),'utf8');
const marker='\n  bootstrap();\n})();';
if(!source.includes(marker)) throw new Error('bootstrap marker missing');
source=source.replace(marker,`\n  globalThis.__ncdTestExports={sortWorldEventEntriesNewestFirst,worldEventsPanelHtml};\n})();`);
const el=()=>({textContent:'',innerHTML:'',style:{setProperty(){}},addEventListener(){},classList:{toggle(){},add(){},remove(){}}});
const context={console,URL,Intl,Date,Math,JSON,Number,String,Boolean,Array,Object,RegExp,Promise,setTimeout,clearTimeout,setInterval,clearInterval,requestAnimationFrame:cb=>{cb();return 1},cancelAnimationFrame(){},localStorage:{getItem(){return null},setItem(){},removeItem(){}},document:{hidden:false,documentElement:{clientWidth:390,style:{setProperty(){}}},getElementById:()=>el(),addEventListener(){},querySelectorAll:()=>[]},window:{GAME_CONFIG:{supabaseUrl:'https://example.supabase.co',supabasePublishableKey:'test',version:'0.14.2'},innerWidth:390,addEventListener(){},matchMedia:()=>({matches:true,addEventListener(){}}),history:{pushState(){},back(){},state:null},location:{hash:'',pathname:'/',search:''},scrollTo(){}},history:{replaceState(){}},location:{hash:'',pathname:'/',search:''},navigator:{},crypto:{randomUUID:()=> '11111111-1111-4111-8111-111111111111'},CSS:{escape:v=>String(v)}};
context.globalThis=context; vm.createContext(context); vm.runInContext(source,context,{filename:'app.js'});
const f=context.__ncdTestExports;
const entries=[
 {id:'old-pinned',feed_sequence:10,is_pinned:true,event_type:'system',event_level:4,title:'旧置顶消息',content:'旧',created_at:'2026-07-27T00:00:00Z'},
 {id:'breakthrough',feed_sequence:12,is_pinned:false,event_type:'breakthrough_success',event_level:2,title:'新突破',content:'突破',created_at:'2026-07-27T00:00:02Z'},
 {id:'casino',feed_sequence:11,is_pinned:false,event_type:'casino_house_win',event_level:1,title:'新赌坊',content:'赌博',created_at:'2026-07-27T00:00:01Z'}
];
const sorted=f.sortWorldEventEntriesNewestFirst(entries);
if(sorted.map(x=>x.id).join(',')!=='breakthrough,casino,old-pinned') throw new Error('feed_sequence ordering failed');
const html=f.worldEventsPanelHtml({status:'active',entries});
const p1=html.indexOf('新突破'),p2=html.indexOf('新赌坊'),p3=html.indexOf('旧置顶消息');
if(!(p1>=0&&p1<p2&&p2<p3)) throw new Error('render ordering failed');
if(!html.includes('严格按最新消息排序，新消息永远置顶')) throw new Error('footer rule missing');
const fallback=f.sortWorldEventEntriesNewestFirst([
 {id:'a',created_at:'2026-07-27T00:00:00Z'},
 {id:'b',created_at:'2026-07-27T00:00:02Z'}
]);
if(fallback[0].id!=='b') throw new Error('created_at fallback failed');
console.log(JSON.stringify({ok:true,checks:4,order:sorted.map(x=>x.id)}));
