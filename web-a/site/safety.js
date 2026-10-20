/** Web A transactional guard, v2.0.51-derived. No JWT/password ever persisted.
 * The browser can be suspended or killed at any point. All unknown outcomes remain locked.
 */
export const TASK_STATES_ACTIVE = Object.freeze(['queued','pending','preparing','awaiting_confirm','confirmed','executing']);
export const FINAL_STATES = Object.freeze(['finished','failed','cancelled']);
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
export const isUUID = s => typeof s === 'string' && UUID.test(s);
export class SafetyLockError extends Error { constructor(message){super(message);this.name='SafetyLockError';} }
export function requireDurableStorage(store) {
  const key='tpr-web-write-probe';
  const value='1';
  try { store.setItem(key,value);if(store.getItem(key)!==value)throw Error('write mismatch');store.removeItem(key);}
  catch {throw new SafetyLockError('浏览器无法持久保存操作编号：禁止发出任务/STOP 请求');}
}
function copy(x){return x===null?null:JSON.parse(JSON.stringify(x));}
/** Single user per browser profile. Only opaque request ids and statuses are stored. */
export class SafetyJournal {
  constructor(storage, owner, scope='task') {
    if(!isUUID(owner)) throw new SafetyLockError('登录用户标识无效');
    if(!['task','stop'].includes(scope))throw new SafetyLockError('操作类型无效');
    this.storage=storage;this.owner=owner;this.scope=scope;this.key=`tpr-web-a-v251:${owner}:${scope}:journal`;
    requireDurableStorage(storage);
  }
  load() {
    const raw=this.storage.getItem(this.key);if(!raw)return null;
    let row;try{row=JSON.parse(raw);}catch{throw new SafetyLockError('本地操作记录损坏：禁止提交');}
    if(!row || row.owner!==this.owner || row.kind!==this.scope || !isUUID(row.requestId))
      throw new SafetyLockError('本地操作记录缺失必要字段：禁止提交');
    if(row.secondId!==undefined && !isUUID(row.secondId)) throw new SafetyLockError('第二任务编号损坏');
    return copy(row);
  }
  save(row) {
    if(!row || !isUUID(row.requestId)||row.kind!==this.scope)throw new SafetyLockError('操作请求标识错误');
    if(row.secondId && !isUUID(row.secondId))throw new SafetyLockError('双账号第二任务编号错误');
    const withOwner={...row,owner:this.owner};
    this.storage.setItem(this.key,JSON.stringify(withOwner));
    if(this.storage.getItem(this.key)!==JSON.stringify(withOwner))throw new SafetyLockError('操作标识写入后回读不一致');
    return withOwner;
  }
  beginTask(firstId,secondId=null){
    if(this.load())throw new SafetyLockError('仍有同类型未决请求：禁止新建');
    return this.save({kind:'task',requestId:firstId,...(secondId?{secondId}:{}),phase:'preflight',createdAt:Date.now()});
  }
  beginStop(requestId){
    if(this.load())throw new SafetyLockError('仍有同类型未决请求：先处理原记录');
    return this.save({kind:'stop',requestId,phase:'requesting',revision:0,createdAt:Date.now()});
  }
  advance(phase, extras={}) {
    const entry=this.load();if(!entry)throw new SafetyLockError('没有已持久化的操作编号');
    return this.save({...entry, ...extras, phase});
  }
  /** Clear ONLY after verified authoritatively and explicitly acknowledged. */
  close(authorized){
    if(authorized!==true)throw new SafetyLockError('需要云端权威结案证据，禁止删除未决记录');
    this.storage.removeItem(this.key);
    if(this.storage.getItem(this.key)!==null)throw new SafetyLockError('未决记录清理失败，保持锁定');
  }
}
export function requireBReady(snapshot, now=Date.now()) {
  if(!snapshot || !snapshot.row)throw new SafetyLockError('B 未上报状态');
  // B v2.0.42 presence gate is server-clock dependent: local clock is not authority.
  if(!Number.isFinite(snapshot.serverTime))throw new SafetyLockError('无法读取云端响应时间，禁止发送');
  const ms=Date.parse(snapshot.row.seen_at||'');const age=snapshot.serverTime-ms;
  if(!Number.isFinite(age) || age<-2000 || age>12000)throw new SafetyLockError('B 心跳过期或时钟异常，禁止发送');
  if(snapshot.row.state!=='idle')throw new SafetyLockError('B 不处于空闲状态，禁止发送');
  return true;
}
export function shouldPermitNewTask({roleCurrent,presence,activeTask,globalControl,unresolvedStops,journal, uploadInFlight}){
  if(!roleCurrent)throw new SafetyLockError('A 端会话不再有效');
  if(journal)throw new SafetyLockError('仍有持久化未决任务/STOP，禁止新建');
  if(uploadInFlight)throw new SafetyLockError('当前网络提交未收口');
  if(activeTask)throw new SafetyLockError('云端存在未完成任务 '+String(activeTask.id||'').slice(0,8));
  if(unresolvedStops?.length)throw new SafetyLockError('云端存在未结案 STOP 请求');
  if(globalControl?.action!=='resume' || Number(globalControl?.revision||0)<=0 ||
      Number(globalControl?.ack_revision||-1)!==Number(globalControl?.revision||0) || globalControl?.ack_state!=='resumed')
    throw new SafetyLockError('全局 STOP 未经 B 确认恢复，禁止发送');
  requireBReady(presence);
  return true;
}
export function oneTapStopNext(entry,control,uploadInFlight=false){
  if(!entry||entry.kind!=='stop')throw new SafetyLockError('没有同一请求 ID 的 STOP 记录');
  if(!Number.isInteger(entry.revision)||entry.revision<0)throw new SafetyLockError('STOP 版本错误');
  if(!entry.revision)return {action:'issue',requestId:entry.requestId};
  const rev=Number(control?.revision||0), ack=Number(control?.ack_revision||0);
  if(control?.action==='resume' && control?.release_mode==='one_tap_stop_release' &&
     Number(control?.release_from_revision)===entry.revision && rev>entry.revision && ack===rev && control?.ack_state==='resumed' && !uploadInFlight)
       return {action:'complete',revision:rev};
  if(control?.action==='stop' && rev===entry.revision && ack===rev && control?.ack_state==='halted' && !uploadInFlight)
       return {action:'release',revision:rev};
  if(control?.action==='stop' && rev>entry.revision)return {action:'superseded',revision:rev};
  return {action:'wait'};
}
/** Require Web Locks: localStorage checks by themselves aren't atomic across tabs. */
export async function withExclusiveLock(name,fn,nav=globalThis.navigator) {
  if(!nav?.locks?.request) throw new SafetyLockError('浏览器不支持跨标签页原子写锁；禁止真实写入');
  return nav.locks.request('tpr-web-a-'+name,{mode:'exclusive',ifAvailable:true},async lock=>{
    if(!lock)throw new SafetyLockError('另一网页标签正在执行操作，请切回原标签');
    return fn();
  });
}
