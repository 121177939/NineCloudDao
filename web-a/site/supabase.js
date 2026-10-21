import {isWireCommand} from './send-plan.js';
/** Supabase read/auth client based on v2.0.51 PhoneA SupabaseApi.kt.
 * Refresh token is saved in per-tab sessionStorage to survive reload only; never localStorage. No service-role key is used.
 */
export const PROJECT_URL = 'https://wqhirteaemujeytsdpit.supabase.co';
export const PUBLISHABLE_KEY = 'sb_publishable_SWsPO_l7Jbo1SHWSEczPSg_iJhC8_3o';

export class CloudError extends Error {
  constructor(message, status = 0, code = '') { super(message); this.name='CloudError';this.status=status;this.code=code; }
}
export class WebAClient {
  constructor() { this.url=PROJECT_URL;this.key=PUBLISHABLE_KEY;this.access='';this.refresh='';this.expiry=0;this.uid='';this.roleClaimed=false;this.refreshing=null;this.sessionStore=globalThis.sessionStorage||null; }
  get loggedIn() { return !!(this.access && this.refresh && this.uid && this.roleClaimed); }
  clear() { this.access='';this.refresh='';this.expiry=0;this.uid='';this.roleClaimed=false;try{this.sessionStore?.removeItem('web-a-refresh-v12');}catch{} }
  async wire(method,path,body=undefined,auth=true,raw=false,representation=false) {
    if (auth) await this.ensureSession();
    const headers={ 'apikey':this.key,'Cache-Control':'no-store' };
    if(auth) headers.Authorization='Bearer '+this.access;
    if (body !== undefined) headers['Content-Type']='application/json';
    if(representation) headers.Prefer='return=representation';
    let response;
    try {
      response=await fetch(this.url+path, {method,headers,body:body===undefined?undefined:JSON.stringify(body),cache:'no-store',credentials:'omit',referrerPolicy:'no-referrer',signal:AbortSignal.timeout(24000)});
    } catch(e) { throw new CloudError('网络连接失败或请求超时，不能据此认定任务不存在：'+e.message); }
    if(!response.ok){
      const value=await response.text().catch(()=> '');let code='';
      try{code=JSON.parse(value).code||'';}catch{}
      throw new CloudError(`云端 HTTP ${response.status}${code?' / '+code:''}：${value.slice(0,240)}`,response.status,code);
    }
    const receivedDate=response.headers.get('Date');
    const serverTime=receivedDate?Date.parse(receivedDate):null;
    if(raw) return {data:await response.blob(),serverTime};
    const t=await response.text();
    let data;
    try{data=JSON.parse(t);}catch{ data=t; }
    return {data,serverTime};
  }
  async login(email,password){
    this.clear();
    const result=(await this.wire('POST','/auth/v1/token?grant_type=password',{email,password},false)).data;
    if(!result.access_token || !result.refresh_token || !result.user?.id) throw new CloudError('Supabase 登录回复缺少必要信息');
    this.acceptSession(result);
    try {
      const claim=(await this.wire('POST','/rest/v1/rpc/remote_claim_role',{p_role:'A'})).data;
      if(claim!==true) throw new CloudError('A 端设备占用登记失败，拒绝登录');
      this.roleClaimed=true;this.saveRefresh();
      const current=await this.isRoleCurrent();
      if(!current)throw new CloudError('新会话未通过服务端角色核验');
    }catch(e){ this.clear();throw e; }
  }
  saveRefresh(){try{if(this.refresh)this.sessionStore?.setItem('web-a-refresh-v12',this.refresh);}catch{}}
  async restoreSession(){
    let token='';try{token=this.sessionStore?.getItem('web-a-refresh-v12')||'';}catch{}
    if(!token)return false;
    try{
      const response=(await this.wire('POST','/auth/v1/token?grant_type=refresh_token',{refresh_token:token},false)).data;
      if(!response?.user?.id||!response?.access_token||!response?.refresh_token)throw new CloudError('刷新会话缺少身份');
      this.acceptSession(response);this.roleClaimed=true;
      if(await this.isRoleCurrent()!==true)throw new CloudError('原 A 角色租约已失效');
      this.saveRefresh();return true;
    }catch(e){this.clear();throw e;}
  }
  acceptSession(data){this.access=data.access_token;this.refresh=data.refresh_token;this.uid=data.user?.id||this.uid;this.expiry=Date.now()+1000*Number(data.expires_in||3600);}
  async ensureSession(){
    if(!this.access || !this.refresh)throw new CloudError('请重新登录');
    if(Date.now()+60000<this.expiry)return;
    if(!this.refreshing)this.refreshing=(async()=>{
      const token=this.refresh;
      const r=(await this.wire('POST','/auth/v1/token?grant_type=refresh_token',{refresh_token:token},false)).data;
      this.acceptSession(r);this.saveRefresh();
    })().finally(()=>{this.refreshing=null;});
    await this.refreshing;
  }
  async isRoleCurrent(){if(!this.roleClaimed)return false;return (await this.wire('POST','/rest/v1/rpc/remote_role_current',{p_role:'A'})).data===true;}
  async presence(){ const r=await this.wire('GET','/rest/v1/remote_device_presence?select=state,task_id,completed_items,total_items,stage,seen_at&limit=1');return {row:r.data?.[0]||null,serverTime:r.serverTime};}
  async tasks(offset=0,limit=30){ const p=`/rest/v1/remote_tasks?select=id,command,target_account,status,message,result_path,scatter_path,suite_path,created_at,updated_at&order=created_at.desc&limit=${limit}&offset=${offset}`; return (await this.wire('GET',p)).data; }
  async task(id){if(!/^[0-9a-f-]{36}$/i.test(id))throw new CloudError('任务编号不合法');return (await this.wire('GET',`/rest/v1/remote_tasks?id=eq.${encodeURIComponent(id)}&select=*`)).data?.[0]||null;}
  async firstActiveTask(){return (await this.wire('GET','/rest/v1/remote_tasks?select=*&status=in.(queued,pending,preparing,awaiting_confirm,confirmed,executing)&order=created_at.desc&limit=1')).data?.[0]||null;}
  async stops(){return (await this.wire('GET','/rest/v1/remote_stop_requests?select=task_id,batch_id,phase,screenshot_state,screenshot_path,exit_state,note,requested_at,reviewed_at,review_note,auto_release_at,auto_release_revision,auto_release_note&order=requested_at.desc&limit=60')).data||[];}
  async stopsFor(ids){const filtered=ids.filter(id=>/^[0-9a-f-]{36}$/i.test(id)).slice(0,50);if(!filtered.length)return[];return (await this.wire('GET',`/rest/v1/remote_stop_requests?select=task_id,phase,screenshot_path,screenshot_state,exit_state,note,reviewed_at,review_note,auto_release_at,auto_release_revision,auto_release_note&task_id=in.(${filtered.join(',')})&limit=50`)).data||[];}
  async suiteStates(id){if(!/^[0-9a-f-]{36}$/i.test(id))throw new CloudError('任务编号不合法');return (await this.wire('GET',`/rest/v1/remote_task_suite_items?task_id=eq.${id}&select=ordinal,canonical_text,expected_count,amount_jiao,state,reason,updated_at&order=ordinal.asc`)).data||[];}
  // v2.0.51 RPC correspondence. Not exposed to the UI until online acceptance.
  async rpc(name,body={}){
    if(!/^remote_[a-z0-9_]+$/.test(name))throw new CloudError('RPC 名称无效');
    return (await this.wire('POST','/rest/v1/rpc/'+name,body)).data;
  }
  async createTask(command,id,targetAccount){
    if(!/^[0-9a-f-]{36}$/i.test(id)||!['seven','arrange'].includes(targetAccount)||!isWireCommand(command))
      throw new CloudError('新建任务参数不合法');
    // send only a frozen, parser-validated command; server's presence gate must also pass.
    return (await this.wire('POST','/rest/v1/remote_tasks?select=*',{
      command,id,target_account:targetAccount,requires_account_preflight:true},true,false,true)).data;
  }
  async dualCapabilities(){return this.rpc('remote_v110_capabilities');}
  async createDualChain(command,firstId,secondId){
    if(!/^[0-9a-f-]{36}$/i.test(firstId)||!/^[0-9a-f-]{36}$/i.test(secondId)||firstId===secondId||!isWireCommand(command))
      throw new CloudError('双账号建单参数不合法');
    const r=await this.rpc('remote_v110_create_plan',{p_command:command,p_first_id:firstId,p_second_id:secondId});
    if(r?.plan_id!==firstId || r?.first_task_id!==firstId || r?.second_task_id!==secondId)
      throw new CloudError('云端返回的双账号计划 UUID 不一致，保持锁定');
    return r;
  }
  async dualPlanSnapshot(firstId,secondId){
    if(!/^[0-9a-f-]{36}$/i.test(firstId)||!/^[0-9a-f-]{36}$/i.test(secondId)||firstId===secondId)
      throw new CloudError('双账号计划 ID 无效');
    const p=await this.rpc('remote_v111_plan_snapshot',{p_plan_id:firstId});
    if(p?.plan_exists){
      if(p.first_task_id!==firstId || p.second_task_id!==secondId)throw new CloudError('计划关联不一致，保持锁定');
      for(const k of ['first_exists','first_status','second_exists','second_status','unfinished_count','queued_count','second_account']){
        if(p[k]===undefined||p[k]===null)throw new CloudError('计划状态缺失 '+k);
      }
    }
    return p;
  }
  async globalControl(){return this.rpc('remote_v229_control_status');}
  async issueStopAll(id){
    if(!/^[0-9a-f-]{36}$/i.test(id))throw new CloudError('STOP 请求 ID 无效');
    return this.rpc('remote_v235_issue_stop_all',{p_request_id:id});
  }
  async releaseStop(revision){
    if(!Number.isSafeInteger(revision)||revision<=0)throw new CloudError('STOP 版本无效');
    return this.rpc('remote_v235_issue_stop_release',{p_stop_revision:revision});
  }
  async unresolvedStops(){
    // Android A excludes one-tap auto-released STOP evidence from the open review queue.
    // The evidence row remains in cloud history; only auto_release_at IS NULL blocks new tasks.
    return (await this.wire('GET','/rest/v1/remote_stop_requests?select=task_id,phase,screenshot_path,exit_state,requested_at,auto_release_at&phase=in.(requested,stopped,review)&auto_release_at=is.null&order=requested_at.asc&limit=200')).data||[];
  }
  async cancelPendingTask(id,expectedStatus){
    if(!/^[0-9a-f-]{36}$/i.test(id)||!['pending','awaiting_confirm'].includes(expectedStatus))
      throw new CloudError('禁止对已执行或不明确任务执行取消');
    const q='/rest/v1/remote_tasks?id=eq.'+encodeURIComponent(id)+'&status=eq.'+expectedStatus+'&select=id';
    const rows=(await this.wire('PATCH',q,{status:'cancelled',message:'由 Web A 人工确认未执行后取消旧任务'},true,false,true)).data;
    if(!Array.isArray(rows)||rows.length!==1)throw new CloudError('任务状态已变化，取消未生效；保持人工核对');
    return rows[0];
  }
  async reviewClosedStop(id,note){
    if(!/^[0-9a-f-]{36}$/i.test(id)||typeof note!=='string'||note.trim().length<6)
      throw new CloudError('人工核查须有合法任务 ID 和至少六字备注');
    return this.rpc('remote_v204_review_close_stop',{
      p_task_id:id,p_external_checked:true,p_safe_to_resume:true,p_review_note:note.trim().slice(0,500)});
  }
  async reviewedResume(note){
    if(typeof note!=='string'||note.trim().length<6)throw new CloudError('恢复接单须至少六字人工核查说明');
    return this.rpc('remote_v229_issue_resume',{
      p_review_note:note.trim().slice(0,500),p_external_checked:true,p_odds_checked:true});
  }
  async screenshot(path){
    if(!path || !path.startsWith(this.uid+'/') || path.includes('..')||path.length>600) throw new CloudError('截图不属于本账号或路径无效');
    // Storage v1 download requires bearer token & publishable key; no public screenshot URLs.
    const response=await this.wire('GET','/storage/v1/object/authenticated/task-shots/'+path.split('/').map(encodeURIComponent).join('/'),undefined,true,true);
    if(response.data.size>5_000_000)throw new CloudError('图片超过 5 MB 上限');
    return response.data;
  }
}
