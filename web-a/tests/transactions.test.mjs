import assert from 'node:assert/strict';
import {WebTransactions} from '../site/transactions.js';
import {SafetyLockError} from '../site/safety.js';
class St{constructor(){this.m=new Map()}getItem(k){return this.m.has(k)?this.m.get(k):null}setItem(k,v){this.m.set(k,String(v))}removeItem(k){this.m.delete(k)}}
const uid='11111111-1111-4111-8111-111111111111',now=Date.now();
const nav={locks:{request:async (_,{ifAvailable},fn)=>fn({name:'granted'})}};
function mock(){const calls=[];const a={uid,calls,
  async isRoleCurrent(){calls.push('role');return true},
  async presence(){calls.push('presence');return {serverTime:Date.now(),row:{state:'idle',seen_at:new Date(Date.now()-200).toISOString()}}},
  async firstActiveTask(){calls.push('active');return null},
  async globalControl(){calls.push('control');return {action:'resume',revision:44,ack_revision:44,ack_state:'resumed'}},
  async unresolvedStops(){calls.push('stops');return []},
  async dualCapabilities(){calls.push('capability');return {ready:true}},
  async createTask(cmd,id,sel){calls.push('POST task');return [{id}]},
  async createDualChain(cmd,a,b){calls.push('POST dual');return {plan_id:a,first_task_id:a,second_task_id:b}},
  async task(id){calls.push('read task');return {id,status:'finished'}},
  async dualPlanSnapshot(first,second){calls.push('plan');return {plan_exists:true,unfinished_count:0,queued_count:0,first_task_id:first,second_task_id:second}},
  async issueStopAll(id){calls.push('POST stop');return {revision:55}},
  async releaseStop(rev){calls.push('POST resume');return {revision:rev+1}}};return a;}
let pass=0;async function t(name,fn){await fn();pass++;console.log('PASS',name)}
await t('regular send uses fixed persisted request UUID',async()=>{const a=mock(),st=new St(),tx=new WebTransactions(a,st,nav);const row=await tx.sendFrozenCommand('M1|S=1234:1|T=','arrange');assert.equal(row.phase,'created');assert(a.calls.includes('POST task'));assert.equal(tx.pending().task.requestId,row.requestId);});
await t('dual use one atomic RPC not two POSTs',async()=>{const a=mock(),tx=new WebTransactions(a,new St(),nav);const r=await tx.sendFrozenCommand('M1|S=1234:1|T=','both');assert(r.secondId);assert.equal(a.calls.filter(c=>c.startsWith('POST')).join(','),'POST dual');});
await t('old task blocks another send',async()=>{const a=mock(),tx=new WebTransactions(a,new St(),nav);await tx.sendFrozenCommand('M1|S=1234:1|T=','arrange');await assert.rejects(tx.sendFrozenCommand('M1|S=1234:1|T=','arrange'),SafetyLockError);assert.equal(a.calls.filter(x=>x==='POST task').length,1);});
await t('no POST on B not ready; preflight journal safely cleared',async()=>{const a=mock();a.presence=async()=>({serverTime:Date.now(),row:{state:'busy',seen_at:new Date().toISOString()}});const tx=new WebTransactions(a,new St(),nav);await assert.rejects(tx.sendFrozenCommand('M1|S=1234:1|T=','arrange'),/空闲/);assert(!tx.pending().task);assert(!a.calls.includes('POST task'));});
await t('unknown POST result locks new task after reload',async()=>{const a=mock(),st=new St();a.createTask=async()=>{a.calls.push('POST task');throw Error('timeout')};const tx=new WebTransactions(a,st,nav);await assert.rejects(tx.sendFrozenCommand('M1|S=1234:1|T=','arrange'),/timeout/);assert.equal(tx.pending().task.phase,'unknown');const reloaded=new WebTransactions(a,st,nav);await assert.rejects(reloaded.sendFrozenCommand('M1|S=1234:1|T=','arrange'),/未决/);assert.equal(a.calls.filter(x=>x==='POST task').length,1);});
await t('known terminal manually acknowledged removes task lock',async()=>{const a=mock(),tx=new WebTransactions(a,new St(),nav);await tx.sendFrozenCommand('M1|S=1234:1|T=','seven');await assert.rejects(tx.acknowledgeTerminalTask(false),/人工/);await tx.acknowledgeTerminalTask(true);assert.equal(tx.pending().task,null);});
await t('unknown REST absence does not unlock',async()=>{const a=mock(),tx=new WebTransactions(a,new St(),nav);await tx.sendFrozenCommand('M1|S=1234:1|T=','seven');a.task=async()=>null;await assert.rejects(tx.acknowledgeTerminalTask(true),/未权威/);assert(tx.pending().task);});
await t('STOP UUID persists and is idempotent',async()=>{const a=mock(),st=new St(),tx=new WebTransactions(a,st,nav);const r=await tx.requestOneTapStop();assert.equal(r.requestId,(await tx.requestOneTapStop()).requestId);const next=await tx.advanceStop();assert.equal(next.action,'issue');assert.equal(tx.pending().stop.revision,55);assert.equal(a.calls.filter(c=>c==='POST stop').length,1);});
await t('STOP never releases until ACK',async()=>{const a=mock(),tx=new WebTransactions(a,new St(),nav);await tx.requestOneTapStop();await tx.advanceStop();const r=await tx.advanceStop();assert.equal(r.action,'wait');assert(!a.calls.includes('POST resume'));});
await t('STOP releases only after exact halted ACK and later resumed ACK',async()=>{const a=mock(),tx=new WebTransactions(a,new St(),nav);await tx.requestOneTapStop();await tx.advanceStop();a.globalControl=async()=>({action:'stop',revision:55,ack_revision:55,ack_state:'halted'});assert.equal((await tx.advanceStop()).action,'release');assert.equal(tx.pending().stop.resumeRevision,56);a.globalControl=async()=>({action:'resume',release_mode:'one_tap_stop_release',release_from_revision:55,revision:56,ack_revision:56,ack_state:'resumed'});assert.equal((await tx.advanceStop()).action,'complete');assert.equal(tx.pending().stop,null);});
await t('STOP may be registered even when task result is unknown',async()=>{const a=mock(),tx=new WebTransactions(a,new St(),nav);tx.tasks.beginTask(crypto.randomUUID());tx.tasks.advance('unknown');const r=await tx.requestOneTapStop();assert(r.requestId);assert(tx.pending().task);});
await t('STOP no releases with ambiguous task',async()=>{const a=mock(),tx=new WebTransactions(a,new St(),nav);tx.tasks.beginTask(crypto.randomUUID());tx.tasks.advance('unknown');await tx.requestOneTapStop();await tx.advanceStop();a.globalControl=async()=>({action:'stop',revision:55,ack_revision:55,ack_state:'halted'});assert.equal((await tx.advanceStop()).action,'wait');});
console.log('PASS total',pass,'transaction safety simulation scenarios');
