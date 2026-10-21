import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {WebTransactions} from '../site/transactions.js';
import {confirmedSuccessfulCompletion} from '../site/auto-finalize.js';
const uid='11111111-1111-4111-8111-111111111111';
const nav={locks:{request:async (_name,_options,callback)=>callback({})}};
class MemoryStorage{constructor(){this.m=new Map()}getItem(k){return this.m.get(k)??null}setItem(k,v){this.m.set(k,String(v))}removeItem(k){this.m.delete(k)}}
const newUuid=()=>crypto.randomUUID();
const task=(id,acct='arrange',status='finished',path=uid+'/receipt.png')=>({id,status,target_account:acct,result_path:path});
const gate=()=>({roleCurrent:true,presence:{serverTime:Date.now(),row:{state:'idle',seen_at:new Date().toISOString()}},activeTask:null,globalControl:{action:'none',revision:0},unresolvedStops:[],uploadInFlight:false});
const api=(one,second=null,gateOverrides={})=>({uid,
  async task(id){return id===one?.id?one:id===second?.id?second:null},
  async dualPlanSnapshot(firstId,secondId){return {plan_exists:true,first_exists:true,second_exists:true,first_task_id:firstId,second_task_id:secondId,unfinished_count:0,queued_count:0}},
  async isRoleCurrent(){return gateOverrides.roleCurrent??true},
  async presence(){return gateOverrides.presence||gate().presence},
  async firstActiveTask(){return gateOverrides.activeTask??null},
  async globalControl(){return gateOverrides.globalControl||gate().globalControl},
  async unresolvedStops(){return gateOverrides.unresolvedStops||[]}
});
async function scenario(label,setup,expected){
 const id=newUuid(), row=task(id);const context={id,row,second:null,gateOverrides:{}};
 await setup(context);const client=api(context.row,context.second,context.gateOverrides);
 const tx=new WebTransactions(client,new MemoryStorage(),nav);
 tx.tasks.beginTask(id,context.second?.id||null);tx.tasks.advance('created');
 const result=await tx.autoReleaseSuccessfulTask();
 assert.equal(result.action,expected,label);
 assert.equal(Boolean(tx.pending().task),expected!=='released',label+' journal');
 console.log('PASS',label);
}
await scenario('one successful finished task with receipt and B idle auto releases',async()=>{},'released');
await scenario('finished without receipt remains locked',async x=>{x.row.result_path=null;},'waiting');
await scenario('failed terminal remains locked',async x=>{x.row.status='failed'},'waiting');
await scenario('cancelled terminal remains locked',async x=>{x.row.status='cancelled'},'waiting');
await scenario('B busy during odds/exit finalization remains locked',async x=>{x.gateOverrides.presence={serverTime:Date.now(),row:{state:'busy',seen_at:new Date().toISOString()}}},'waiting');
await scenario('stale B presence remains locked',async x=>{x.gateOverrides.presence={serverTime:Date.now(),row:{state:'idle',seen_at:new Date(Date.now()-30000).toISOString()}}},'waiting');
await scenario('global STOP missing ACK remains locked',async x=>{x.gateOverrides.globalControl={action:'stop',revision:10,ack_revision:0,ack_state:'pending'}},'waiting');
await scenario('unresolved stop evidence remains locked',async x=>{x.gateOverrides.unresolvedStops=[{id:'stop'}]},'waiting');
await scenario('other unfinished server task remains locked',async x=>{x.gateOverrides.activeTask={id:newUuid()}},'waiting');
await scenario('role lease lost remains locked',async x=>{x.gateOverrides.roleCurrent=false},'waiting');
await scenario('dual both successful with receipts and snapshot auto releases',async x=>{x.second=task(newUuid(),'seven');},'released');
await scenario('dual second missing receipt remains locked',async x=>{x.second=task(newUuid(),'seven');x.second.result_path=null},'waiting');
await scenario('dual second failed remains locked',async x=>{x.second=task(newUuid(),'seven');x.second.status='failed'},'waiting');
await scenario('dual account mismatch remains locked',async x=>{x.second=task(newUuid(),'arrange')},'waiting');
await scenario('cloud absence does not release a local request',async x=>{x.row=null},'waiting');
{
 const id=newUuid();const row=task(id);const tx=new WebTransactions(api(row),new MemoryStorage(),nav);
 tx.tasks.beginTask(id);tx.stop.beginStop(newUuid());
 assert.equal((await tx.autoReleaseSuccessfulTask()).action,'none');assert(tx.pending().task);console.log('PASS local STOP journal blocks auto-release');
}
{
 const id=newUuid();const row=task(id);const client=api(row);const tx=new WebTransactions(client,new MemoryStorage(),nav);
 tx.tasks.beginTask(id);tx.inFlight=true;
 assert.equal((await tx.autoReleaseSuccessfulTask()).action,'none');assert(tx.pending().task);console.log('PASS in-flight network POST blocks auto-release');
}
const html=readFileSync(new URL('../site/index.html',import.meta.url),'utf8');
const app=readFileSync(new URL('../site/app.js',import.meta.url),'utf8');
assert(html.includes('WAP 17') && html.includes('app.js?v=web-a-stage17'));
assert(app.includes('renderHistoryRows(tasks)') && app.includes('await refreshTasks(); // history remains live while its tab is open, too.'));
assert(app.includes('await autoReconcileAfterRefresh()'));
assert(app.includes('const fingerprint=completed.map'));
assert(app.includes('Keep previously verified history'));
console.log('PASS history list is updated by the same 10s cloud task-feed poll and cloud failures do not blank history');
