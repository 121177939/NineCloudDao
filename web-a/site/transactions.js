import {isWireCommand} from './send-plan.js';
import {confirmedSuccessfulCompletion} from './auto-finalize.js';
import {SafetyJournal,SafetyLockError,requireBReady,shouldPermitNewTask,oneTapStopNext,withExclusiveLock,FINAL_STATES} from './safety.js';

/** Fail-closed Web transactional migration candidate. Not activated for production until DB acceptance.
 * Stores UUIDs only, NEVER JWT/passwords, passwords or command text. All cloud requests remain the
 * existing v2.0.51 Supabase table/RPC protocol and are guarded by roles and RLS.
 */
export class WebTransactions {
  constructor(api,storage,navigatorRef=globalThis.navigator){
    if(!api.uid)throw new SafetyLockError('请先登录再初始化任务安全门禁');
    this.api=api;this.nav=navigatorRef;
    this.tasks=new SafetyJournal(storage,api.uid,'task');
    this.stop=new SafetyJournal(storage,api.uid,'stop');
    this.inFlight=false;
  }
  pending(){return {task:this.tasks.load(),stop:this.stop.load()};}
  async preflight(){
    const [roleCurrent,presence,activeTask,globalControl,unresolvedStops]=await Promise.all([
      this.api.isRoleCurrent(),this.api.presence(),this.api.firstActiveTask(),this.api.globalControl(),this.api.unresolvedStops()
    ]);
    return {roleCurrent,presence,activeTask,globalControl,unresolvedStops,
      journal:this.tasks.load()||this.stop.load(),uploadInFlight:this.inFlight};
  }
  async sendFrozenCommand(command,selection){
    if(!['arrange','seven','both'].includes(selection)||!isWireCommand(command))
      throw new SafetyLockError('请选择有效账号并使用 Kotlin 识别器确认的 B 兼容指令');
    return withExclusiveLock('cloud-writes',async()=>{
      if(this.inFlight)throw new SafetyLockError('已有提交正在进行');
      if(this.tasks.load()||this.stop.load())throw new SafetyLockError('旧任务或 STOP 未决，请先核对');
      const firstId=crypto.randomUUID(),secondId=selection==='both'?crypto.randomUUID():null;
      // IDs MUST be committed before the first POST, including all cloud preflight RPCs.
      this.tasks.beginTask(firstId,secondId);
      let posted=false;this.inFlight=true;
      try{
        const inputs=await this.preflight();
        // The journal we just wrote is excluded from preflight's own lock check.
        shouldPermitNewTask({...inputs,journal:null,uploadInFlight:false});
        if(selection==='both'){
          const caps=await this.api.dualCapabilities();
          if(caps?.ready!==true)throw new SafetyLockError('双账号原子建单服务端未确认就绪');
        }
        // Last authoritative role check just before creating a task.
        if(await this.api.isRoleCurrent()!==true)throw new SafetyLockError('A 角色租约已失效');
        // A STOP may be registered concurrently (the native APP gives STOP priority).
        // The DB trigger serializes the final race; this local recheck avoids needless POSTs.
        if(this.stop.load())throw new SafetyLockError('一键终止已登记，拒绝创建新任务');
        this.tasks.advance('posting');posted=true;
        if(selection==='both')await this.api.createDualChain(command,firstId,secondId);
        else{
          const result=await this.api.createTask(command,firstId,selection);
          if(!Array.isArray(result)||result.length!==1||result[0].id!==firstId)
            throw new SafetyLockError('创建请求返回任务编号不一致，状态未知，保持锁定');
        }
        this.tasks.advance('created');
        return this.tasks.load();
      }catch(e){
        if(!posted){this.tasks.close(true);} // confirmed NO create POST was dispatched.
        else this.tasks.advance('unknown'); // even HTTP errors may be ambiguous; never auto-repeat.
        throw e;
      }finally{this.inFlight=false;}
    },this.nav);
  }
  async reconcileTask(){
    const row=this.tasks.load();if(!row)return {state:'none'};
    const first=await this.api.task(row.requestId);
    if(!first)return {state:'unknown',row}; // REST zero rows is NOT proof that no create happened.
    if(row.secondId){
      const plan=await this.api.dualPlanSnapshot(row.requestId,row.secondId);
      if(!plan?.plan_exists)return {state:'unknown-plan',row,first};
      const second=await this.api.task(row.secondId);
      if(!second)return {state:'unknown-second',row,first,plan};
      return {state:'plan',row,first,second,plan};
    }
    return {state:FINAL_STATES.includes(first.status)?'terminal':'active',row,first};
  }
  /** Mirrors APP normal successful completion: release ONLY the browser's opaque UUID lock
   * after finished + private receipt + B idle + role/STOP/active-task checks.
   * This NEVER changes cloud tasks, retries wagers, or clears STOP audit.
   */
  async autoReleaseSuccessfulTask(){
    if(this.inFlight || this.stop.load() || !this.tasks.load())return {action:'none'};
    return withExclusiveLock('cloud-writes',async()=>{
      const row=this.tasks.load();
      if(!row || this.inFlight || this.stop.load())return {action:'none'};
      const snapshot=await this.reconcileTask();
      if(snapshot.state!=='terminal' && snapshot.state!=='plan')return {action:'waiting'};
      // Unlike normal preflight, our OWN journal is expected here.
      const gate=await this.preflight();
      const recent=await this.reconcileTask();
      if(this.inFlight || this.stop.load() || this.tasks.load()?.requestId!==row.requestId ||
        this.tasks.load()?.secondId!==row.secondId)return {action:'waiting'};
      const verified=confirmedSuccessfulCompletion(recent,gate,this.api.uid,row.requestId,row.secondId||null);
      if(!verified.safe)return {action:'waiting',reason:verified.reason};
      this.tasks.close(true);
      return {action:'released',requestId:row.requestId,reason:verified.reason};
    },this.nav);
  }
  /** Deliberately no auto-clear: first show all receipts and require external manual verification. */
  async acknowledgeTerminalTask(externalReviewed){
    if(externalReviewed!==true)throw new SafetyLockError('请先人工核对真实小票与结果');
    const result=await this.reconcileTask();
    if(result.state==='terminal' && !this.stop.load())this.tasks.close(true);
    else if(result.state==='plan' && result.plan?.unfinished_count===0 && result.plan?.queued_count===0 &&
      result.plan.first_exists===true && result.plan.second_exists===true &&
      FINAL_STATES.includes(result.first?.status) && FINAL_STATES.includes(result.second?.status) && !this.stop.load()){
      // A verified terminal plan can be acknowledged, but database plan closure remains
      // a separate explicit RPC after review.
      this.tasks.close(true);
    }else throw new SafetyLockError('旧任务、双账号计划或 STOP 仍未权威结案，不能解除');
  }
  async requestOneTapStop(){
    return withExclusiveLock('stop-control',async()=>{
      if(this.stop.load())return this.stop.load(); // same idempotency request id; never new one.
      if(!await this.api.isRoleCurrent())throw new SafetyLockError('A 角色租约失效，禁止登记 STOP');
      // STOP has higher priority than an uncertain task submission; different journal.
      return this.stop.beginStop(crypto.randomUUID());
    },this.nav);
  }
  async advanceStop(){
    return withExclusiveLock('stop-control',async()=>{
      const row=this.stop.load();if(!row)return {action:'none'};
      if(!await this.api.isRoleCurrent())throw new SafetyLockError('A 角色租约失效，STOP 仍保留');
      const inflight=this.inFlight;
      const control=row.revision?await this.api.globalControl():null;
      const next=oneTapStopNext(row,control,inflight);
      if(next.action==='issue'){
        const r=await this.api.issueStopAll(row.requestId);
        if(!(Number(r?.revision)>0))throw new SafetyLockError('云端未返回 STOP 版本号');
        this.stop.advance('waiting_b_halt',{revision:Number(r.revision)});
      }else if(next.action==='superseded'){
        this.stop.advance('waiting_b_halt',{revision:next.revision});
      }else if(next.action==='release'){
        // The SQL RPC is idempotent by the exact p_stop_revision. If its response was lost,
        // retrying this SAME revision is the native APP behavior; never mint another STOP/release revision.
        if(row.phase!=='release_unknown')this.stop.advance('release_unknown');
        const r=await this.api.releaseStop(next.revision);
        if(!(Number(r?.revision)>next.revision))throw new SafetyLockError('云端未确认自动恢复版本');
        this.stop.advance('waiting_b_resume',{resumeRevision:Number(r.revision)});
      }else if(next.action==='complete'){
        // Mirror Android A finalization: only the exact auto-release link plus B's resumed ACK
        // can release local task/STOP placeholders. Cloud tasks were terminalized by the RPC;
        // history, screenshots and audit rows are not deleted or rewritten.
        if(this.inFlight)throw new SafetyLockError('A 端网络请求仍在收口，暂不释放本地占位');
        if(this.tasks.load())this.tasks.close(true);
        this.stop.close(true);
        return {...next,message:'一键终止完成：A/B 本地接单占位已释放，云端未结束任务已终止。旧任务、截图和停止审计全部保留；结果不明的旧任务不会重发。'};
      }
      return next;
    },this.nav);
  }
}
