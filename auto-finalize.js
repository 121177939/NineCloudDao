import {requireBReady} from './safety.js';

// Browser-local release is NOT settlement, a refund, a verified wager, or cloud review.
// Uncertain / partial / failed tasks and STOP remain locked for human intervention.
const receipt = (task,uid) => task && [task.result_path,task.scatter_path,task.suite_path]
  .some(path => typeof path === 'string' && path.startsWith(uid+'/') &&
    path.length < 600 && !path.includes('..') && path.length > uid.length+1);

export function confirmedSuccessfulCompletion(snapshot, preflight, uid, requestId, secondId=null) {
  if(!snapshot || !preflight || !uid || !requestId)return {safe:false,reason:'核查数据缺失'};
  if(preflight.roleCurrent!==true || preflight.uploadInFlight || preflight.activeTask ||
    !Array.isArray(preflight.unresolvedStops) || preflight.unresolvedStops.length)
    return {safe:false,reason:'角色/未完任务/STOP 状态尚未确认'};
  const control=preflight.globalControl;
  const none=control?.action==='none' && Number(control?.revision)===0;
  const resumed=control?.action==='resume' && Number(control?.revision)>0 &&
    Number(control?.ack_revision)===Number(control?.revision) && control?.ack_state==='resumed';
  if(!none&&!resumed)return {safe:false,reason:'全局 STOP 恢复 ACK 尚未确认'};
  try{requireBReady(preflight.presence);}catch(e){return {safe:false,reason:'B 仍在收尾或心跳不可核验：'+e.message};}
  const first=snapshot.first;
  if(!first || first.id!==requestId || first.status!=='finished' || !receipt(first,uid))
    return {safe:false,reason:'首份任务未成功终结或无私有回图证据'};
  if(!secondId) {
    return snapshot.state==='terminal' && ['arrange','seven'].includes(first.target_account)
      ? {safe:true,reason:'单任务完成、回图存在、B 已安全待命'}
      : {safe:false,reason:'原请求或账号状态未确认'};
  }
  const plan=snapshot.plan,second=snapshot.second;
  if(snapshot.state!=='plan' || !plan || !plan.plan_exists ||
    plan.first_task_id!==requestId || plan.second_task_id!==secondId ||
    plan.first_exists!==true || plan.second_exists!==true ||
    plan.unfinished_count!==0 || plan.queued_count!==0 ||
    first.target_account!=='arrange' || !second || second.id!==secondId ||
    second.target_account!=='seven' || second.status!=='finished' || !receipt(second,uid))
    return {safe:false,reason:'双账号权威计划未全部成功且留存回图'};
  return {safe:true,reason:'两份任务均成功、回图齐全、B 已安全待命'};
}
