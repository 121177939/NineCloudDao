/** B online indicator: solely the authenticated Supabase heartbeat.
 * Realtime Presence may disconnect in the background while B continues working.
 * This is UI presentation only: server-side queue and STOP safety checks retain
 * their independent, stricter conditions.
 */
export const HEARTBEAT_DISPLAY_GRACE_MS=30_000;
export function presenceState(p){
  const row=p?.row;
  if(!row)return {text:'B 离线 · 尚未收到执行端心跳',color:'#b54444',ready:false};
  const seen=Date.parse(row.seen_at||'');
  const now=p.serverTime||Date.now();
  const age=now-seen;
  if(!Number.isFinite(age)||age< -2000)
    return {text:'B 状态暂时无法核实 · 心跳时间无效',color:'#b36a00',ready:false};
  const ageText=`${Math.max(0,Math.floor(age/1000))} 秒前`;
  // Never use a disconnected socket as evidence of device offline.
  if(age>HEARTBEAT_DISPLAY_GRACE_MS)
    return {text:`B 离线 · 最近心跳 ${ageText}`,color:'#b54444',ready:false};
  const known=['idle','busy','attention','paused'].includes(row.state);
  if(!known)return {text:'B 状态暂时无法核实 · 上报状态不明',color:'#b36a00',ready:false};
  const map={idle:'B 在线 · 空闲待命',busy:'B 在线 · 正在执行',attention:'B 在线 · 待核实',paused:'B 在线 · 暂停接单'};
  const temporaryControlCheck=row.state==='attention' && /^(全局控制状态暂不可核实|全局 STOP 状态暂不可核实|全局控制正在重连核验|全局控制状态未及时确认)/.test(String(row.stage||''));
  let text=temporaryControlCheck?'B 在线 · 控制连接核验中（暂缓接单）':map[row.state];
  if(Number(row.total_items)>0)text+=` · ${Number(row.completed_items)||0}/${Number(row.total_items)}组`;
  text+=` · ${ageText}更新`;
  if(row.stage&&row.state!=='idle')text+='\n'+String(row.stage).slice(0,100);
  return {text,color:row.state==='busy'?'#1870b8':'#188c3c',ready:true};
}
