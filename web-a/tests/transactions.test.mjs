import assert from 'node:assert/strict';
import {WebTransactions} from '../site/transactions.js';
import {SafetyLockError} from '../site/safety.js';
class St{constructor(){this.m=new Map()}getItem(k){return this.m.get(k)??null}setItem(k,v){this.m.set(k,String(v))}removeItem(k){this.m.delete(k)}}
const uid='11111111-1111-4111-8111-111111111111';
const nav={locks:{request:async (_,{ifAvailable},fn)=>fn({name:'granted'})}};
const cmd='M1|S=1234-1|T=';
function mock(){const calls=[],orders=new Map();let status='idle';
  const a={uid,calls,orders,setStatus(v){status=v},
    async isRoleCurrent(){calls.push('role');return true},
    async presence(){calls.push('presence');return {serverTime:Date.now(),row:{state:status,seen_at:new Date().toISOString()}}},
    async firstActiveTask(){calls.push('active');return {id:'old-active-id'}},
    async globalControl(){return {action:'none',revision:0,ack_revision:0,ack_state:''}},
    async unresolvedStops(){return []},
    async queueState(){return {held:false}},
    async enqueueOrder(command,id,selection,second){calls.push('POST enqueue');const prev=orders.get(id);if(prev)return prev;
      const r={id,order_number:orders.size+1,state:'queued',command,selection,second};orders.set(id,r);return r;},
    async order(id){calls.push('read order');return orders.get(id)||null},
    async task(id){return {id,status:'finished',result_path:uid+'/receipt.png'}},
    async dualPlanSnapshot(first,second){return {plan_exists:true,unfinished_count:0,queued_count:0,first_task_id:first,second_task_id:second,first_exists:true,second_exists:true}},
    async issueStopAll(id){calls.push('POST stop');return {revision:55}},
    async releaseStop(rev){calls.push('POST resume');return {revision:rev+1}}};return a;
}
let pass=0;async function t(name,fn){await fn();pass++;console.log('PASS',name)}
await t('one tap creates ONE parent order and releases upload lock',async()=>{
 const a=mock(),tx=new WebTransactions(a,new St(),nav);
 const row=await tx.sendFrozenCommand(cmd,'arrange');
 assert.equal(row.phase,'created');assert.equal(row.orderNumber,1);assert.equal(tx.pending().task,null);
 assert.equal(a.orders.size,1);assert.equal(a.calls.filter(x=>x==='POST enqueue').length,1);
});
await t('dual selection creates ONE parent with TWO linked steps',async()=>{
 const a=mock(),tx=new WebTransactions(a,new St(),nav);const row=await tx.sendFrozenCommand(cmd,'both');
 assert(row.secondId);assert.equal(a.orders.size,1);assert.equal(a.orders.get(row.requestId).second,row.secondId);
 assert.equal(a.calls.filter(x=>x==='POST enqueue').length,1);
});
await t('B busy plus legacy active task still allow NEXT order',async()=>{
 const a=mock(),tx=new WebTransactions(a,new St(),nav);a.setStatus('busy');
 await tx.sendFrozenCommand(cmd,'arrange');await tx.sendFrozenCommand(cmd,'seven');
 assert.equal(a.orders.size,2);assert.equal(tx.pending().task,null);
});
await t('B definitely offline blocks queue admission without uncertain journal',async()=>{
 const a=mock(),tx=new WebTransactions(a,new St(),nav);a.setStatus('offline');
 await assert.rejects(tx.sendFrozenCommand(cmd,'arrange'),/心跳|在线|状态异常/);
 assert.equal(tx.pending().task,null);assert.equal(a.orders.size,0);
});
await t('cloud queue hold blocks new order',async()=>{
 const a=mock();a.queueState=async()=>({held:true});const tx=new WebTransactions(a,new St(),nav);
 await assert.rejects(tx.sendFrozenCommand(cmd,'arrange'),/暂停/);assert.equal(a.orders.size,0);
});
await t('STOP blocks new order when unacknowledged',async()=>{
 const a=mock();a.globalControl=async()=>({action:'stop',revision:44,ack_revision:0});const tx=new WebTransactions(a,new St(),nav);
 await assert.rejects(tx.sendFrozenCommand(cmd,'arrange'),/STOP/);assert.equal(a.orders.size,0);
});
await t('after ambiguous POST timeout original UUID survives reload, no new POST',async()=>{
 const a=mock(),st=new St();a.enqueueOrder=async()=>{a.calls.push('POST enqueue');throw Error('timeout')};
 const tx=new WebTransactions(a,st,nav);
 await assert.rejects(tx.sendFrozenCommand(cmd,'arrange'),/timeout/);
 const id=tx.pending().task.requestId;assert.equal(tx.pending().task.phase,'unknown');
 const other=new WebTransactions(a,st,nav);
 await assert.rejects(other.sendFrozenCommand(cmd,'seven'),SafetyLockError);
 assert.equal(other.pending().task.requestId,id);
 assert.equal(a.calls.filter(x=>x==='POST enqueue').length,1);
});
await t('ambiguous success can resolve ORIGINAL order and clear lock without replay',async()=>{
 const a=mock(),st=new St();a.enqueueOrder=async(command,id,sel,second)=>{a.calls.push('POST enqueue');a.orders.set(id,{id,selection:sel,second,state:'queued'});throw Error('timeout')};
 const tx=new WebTransactions(a,st,nav);await assert.rejects(tx.sendFrozenCommand(cmd,'arrange'),/timeout/);
 const check=await tx.autoReleaseSuccessfulTask();assert.equal(check.action,'released');assert.equal(tx.pending().task,null);
 assert.equal(a.calls.filter(x=>x==='POST enqueue').length,1);
});
await t('REST empty result does not prove order was not created',async()=>{
 const a=mock(),tx=new WebTransactions(a,new St(),nav);
 tx.tasks.beginTask(crypto.randomUUID());tx.tasks.advance('unknown');
 const result=await tx.autoReleaseSuccessfulTask();assert.equal(result.action,'waiting');assert(tx.pending().task);
});
await t('STOP UUID remains stable/idempotent',async()=>{
 const a=mock(),tx=new WebTransactions(a,new St(),nav);
 const row=await tx.requestOneTapStop();assert.equal(row.requestId,(await tx.requestOneTapStop()).requestId);
 assert.equal((await tx.advanceStop()).action,'issue');assert.equal(a.calls.filter(x=>x==='POST stop').length,1);
});
await t('STOP waits for B ACK before releasing',async()=>{
 const a=mock(),tx=new WebTransactions(a,new St(),nav);
 await tx.requestOneTapStop();await tx.advanceStop();assert.equal((await tx.advanceStop()).action,'wait');assert(!a.calls.includes('POST resume'));
});
await t('STOP auto release uses exact previous revision, does not retry order',async()=>{
 const a=mock(),tx=new WebTransactions(a,new St(),nav);
 await tx.sendFrozenCommand(cmd,'arrange');await tx.requestOneTapStop();await tx.advanceStop();
 a.globalControl=async()=>({action:'stop',revision:55,ack_revision:55,ack_state:'halted'});
 assert.equal((await tx.advanceStop()).action,'release');
 a.globalControl=async()=>({action:'resume',release_mode:'one_tap_stop_release',release_from_revision:55,revision:56,ack_revision:56,ack_state:'resumed'});
 assert.equal((await tx.advanceStop()).action,'complete');assert.equal(tx.pending().stop,null);
 assert.equal(a.calls.filter(x=>x==='POST enqueue').length,1);
});
await t('STOP registered during an unconfirmed upload prevents release until upload settles',async()=>{
 const a=mock(),tx=new WebTransactions(a,new St(),nav);
 let began,unblock;const sent=new Promise(r=>began=r),pending=new Promise(r=>unblock=r);
 a.enqueueOrder=async(_c,id)=>{a.calls.push('POST enqueue');began();await pending;return {id,order_number:1}};
 const uploading=tx.sendFrozenCommand(cmd,'arrange');await sent;
 await tx.requestOneTapStop();await tx.advanceStop();
 a.globalControl=async()=>({action:'stop',revision:55,ack_revision:55,ack_state:'halted'});
 assert.equal((await tx.advanceStop()).action,'wait');unblock();await uploading;
 assert.equal((await tx.advanceStop()).action,'release');
});
console.log('PASS total',pass,'v2.0.60 transaction/STOP/order queue simulation scenarios');
