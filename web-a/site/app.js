import {WebAClient, CloudError} from './supabase.js';
import {WebTransactions} from './transactions.js';
import {requireBReady} from './safety.js';

// Web A v2.0.51 — GitHub Pages integration candidate. Local mutation state machine is
// implemented and unit-tested, but production write actions stay fail-closed until
// user-approved real Supabase/B acceptance and browser suspend/recovery tests.
const $=id=>document.getElementById(id);
const escapeHTML=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const webParser=globalThis.parser?.com?.example?.remotea?.WebParser;
if(!webParser)throw Error('Kotlin/JS 识别引擎未加载，拒绝提供预览或发送');
const api=new WebAClient();
const state={tx:null,page:'entry',filter:'全部',parsed:null,parsedText:'',lastFocus:null,auth:false,
    busy:false,historyOffset:0,historyRows:[],tasks:[],presence:null,stopRows:[],activeObjectUrls:[],lastRoleCheck:0};
const FAIL_CLOSED='Web 安全一致性验证尚未完成，当前版本禁止真实建单和修改云端任务。请使用已验收的 Android A 端执行该操作。';
function setStatus(text){$('input-status').textContent=text;}
function modal(title,message,actions=[{label:'知道了'}]){
  $('modal-heading').textContent=title;$('modal-body').textContent=message;
  $('modal-options').replaceChildren();$('modal-actions').replaceChildren();
  for(const a of actions){const b=document.createElement('button');b.className='button'+(a.primary?' primary':' ghost');b.textContent=a.label;
    b.addEventListener('click',async()=>{closeModal();try{await a.onClick?.();}catch(e){modal('操作失败',e.message);}});$('modal-actions').appendChild(b);}
  state.lastFocus=document.activeElement;$('overlay').hidden=false;$('modal-actions').querySelector('button')?.focus();
}
function closeModal(){$('overlay').hidden=true;state.lastFocus?.focus?.();}
$('overlay').addEventListener('click',e=>{if(e.target===$('overlay'))closeModal();});
document.addEventListener('keydown',e=>{if(e.key==='Escape'){if(!$('overlay').hidden)closeModal();else if(!$('preview').hidden)closePreview();}});
function showLogin(message=''){
  state.auth=false;state.tx=null;state.parsed=null;state.parsedText='';
  $('login-screen').hidden=false;
  if(message)$('login-status').textContent=message;
  $('b-status').textContent='未登录 · 暂停更新';
  $('home-task-list').innerHTML='<div class="card">登录后读取任务状态</div>';
  $('task-list').innerHTML='<div class="card">登录后读取任务</div>';
  $('history-list').innerHTML='<div class="card">登录后读取历史记录</div>';
}
function showDashboard(){state.auth=true;$('login-screen').hidden=true;selectPage('entry');}
async function login(){
  if(state.busy)return;
  const email=$('login-email').value.trim(),password=$('login-password').value;
  if(!email.includes('@')||!password){$('login-status').textContent='请输入邮箱与密码';return;}
  modal('确认 Web A 登录','与 Android A 相同，新登录会取得 A 角色租约，可能使原手机 A 退出。旧任务不会因此被取消或重新执行。请确认当前没有在另一台 A 端进行未决操作。',[
    {label:'返回'},
    {label:'确认登录',primary:true,onClick:async()=>{
      state.busy=true;$('login-submit').disabled=true;
      $('login-status').textContent='正在向 Supabase 登录并登记 A 端会话…';
      try{await api.login(email,password);state.tx=new WebTransactions(api,localStorage);$('login-password').value='';showDashboard();await refreshAll();await showPendingSafetyInfo();}
      catch(e){api.clear();showLogin('登录失败：'+e.message);}
      finally{state.busy=false;$('login-submit').disabled=false;}
    }}
  ]);
}
$('login-submit').addEventListener('click',login);
$('login-password').addEventListener('keydown',e=>{if(e.key==='Enter')login();});
async function showPendingSafetyInfo(){
  if(!state.tx)return;
  try{
    const pending=state.tx.pending();
    if(pending.stop){
      modal('STOP 未决记录仍在',`上次浏览器留下全局 STOP 请求 ${pending.stop.requestId}，阶段：${pending.stop.phase}。不可假定 B 已恢复。当前网页未启用生产写操作，请使用已验收的 Android A / 服务端审计核实。`);
    }else if(pending.task){
      const result=await state.tx.reconcileTask();
      const txt=result.state==='unknown'?'云端查询暂未返回原任务，不能认定创建失败':
        result.state==='plan'?'双账号计划已查询，请核实两份任务状态与真实回图':
        result.state==='terminal'?'云端显示终态，但仍需核对小票':'当前任务尚未完全结束';
      modal('存在未决任务，禁止重发',`原请求 ID：${pending.task.requestId}\n${txt}。请到任务中心和目标软件核对；不能仅靠刷新页面解除锁。`);
    }
  }catch(e){modal('本地安全记录核查失败','操作状态无法完整核查：'+e.message+'\n当前保持只读。');}
}
function selectPage(page){
  if(!['entry','tasks','history'].includes(page))return;
  state.page=page;
  for(const key of ['entry','tasks','history'])$('page-'+key).hidden=key!==page;
  document.querySelectorAll('.tab').forEach(b=>{b.classList.toggle('active',b.dataset.page===page);b.setAttribute('aria-current',b.dataset.page===page?'page':'false');});
  $('navbar').hidden=false;$('preview').hidden=true;
  if(state.auth&&page==='history'&&!state.historyRows.length)loadHistory(true).catch(e=>modal('历史读取失败',e.message));
}
document.querySelectorAll('.tab').forEach(b=>b.addEventListener('click',()=>selectPage(b.dataset.page)));
$('view-all-tasks').addEventListener('click',()=>selectPage('tasks'));
const validDate=t=>{const d=new Date(t);return Number.isFinite(+d)?d.toLocaleString('zh-CN',{hour12:false}):'时间未知';};
const statusText=state=>({pending:'等待执行',queued:'等待上一账号',preparing:'准备中',awaiting_confirm:'等待确认',confirmed:'已确认',executing:'执行中',finished:'已完成',failed:'失败',cancelled:'已取消',needs_review:'待人工核实',partial:'部分完成'})[state]||state||'未知';
function presenceState(p){
  const row=p?.row;if(!row)return {text:'B 尚未上报状态 · 禁止发送',color:'#b36a00',ready:false};
  const age=(p.serverTime||Date.now())-Date.parse(row.seen_at||'');
  const fresh=Number.isFinite(age)&&age>=-2000&&age<=12000;
  const ready=fresh&&row.state==='idle';
  const ageText=Number.isFinite(age)?`${Math.max(0,Math.floor(age/1000))} 秒前`:'未知';
  const map={idle:'在线 · 空闲待命',busy:'在线 · 正在执行',attention:'在线 · 异常待人工核对',paused:'在线 · 暂停接单'};
  let text=fresh?(map[row.state]||'在线 · 状态未知'):'状态未确认 · 心跳已过期（可能断线或上报失败）';
  if(fresh&&Number(row.total_items)>0)text+=` · ${Number(row.completed_items)||0}/${Number(row.total_items)}组`;
  text+=' · '+ageText+'更新';
  if(fresh&&row.stage&&row.state!=='idle')text+='\n'+String(row.stage).slice(0,100);
  return {text,color:ready?'#188c3c':(row.state==='busy'&&fresh?'#1870b8':'#b36a00'),ready};
}
async function refreshPresence(){
  if(!api.loggedIn)return;
  $('b-status').textContent='正在刷新执行端状态…';$('b-status').style.color='var(--muted)';
  try{state.presence=await api.presence();const display=presenceState(state.presence);
    $('b-status').textContent=display.text;$('b-status').style.color=display.color;
  }catch(e){state.presence=null;$('b-status').textContent='无法确认 B 状态 · 禁止发送：'+e.message;$('b-status').style.color='#b36a00';}
}
function taskCard(row){
  const card=document.createElement('button');
  card.className='card history-card';card.type='button';card.style.cssText='width:100%;text-align:left;color:var(--ink);font:inherit;';
  const acct=row.target_account==='seven'?'七星彩':row.target_account==='arrange'?'排列五':'双账号';
  card.innerHTML=`<div class="row-info"><strong>${escapeHTML(acct)} · ${escapeHTML(statusText(row.status))}</strong><span class="state-chip">›</span></div>
    <div class="sub">${escapeHTML((row.id||'').slice(0,8))} · ${escapeHTML(validDate(row.created_at))}</div>
    <div class="sub">${escapeHTML(String(row.message||'').slice(0,180)||'查看详情、核验记录及原始回图')}</div>`;
  card.addEventListener('click',()=>showTaskDetail(row.id));return card;
}
async function refreshTasks(){
  const placeholder='<div class="card"><span class="status-note">正在读取云端任务…</span></div>';
  $('home-task-list').innerHTML=placeholder;$('task-list').innerHTML=placeholder;
  try{
    const [tasks,stops]=await Promise.all([api.tasks(0,30),api.stops().catch(()=>[])]);
    state.tasks=tasks;state.stopRows=stops;
    const active=tasks.filter(t=>!['finished','cancelled','failed'].includes(t.status));
    $('home-task-list').replaceChildren();$('task-list').replaceChildren();
    if(!active.length){$('home-task-list').innerHTML='<div class="card"><h3 class="no-task-title">✓ 当前没有进行中的任务</h3><p class="no-task-subtitle">可以输入号码，识别预览后发送。</p></div>';
      $('task-list').innerHTML='<div class="card">暂无执行中或排队任务</div>';
    }else{
      active.slice(0,2).forEach(t=>$('home-task-list').appendChild(taskCard(t)));
      active.slice(0,12).forEach(t=>$('task-list').appendChild(taskCard(t)));
      if(active.length>2){const small=document.createElement('p');small.className='light-note';small.textContent=`还有 ${active.length-2} 份待处理任务，点击“查看全部”。`;$('home-task-list').appendChild(small);}
    }
  }catch(e){const msg=`读取失败，不能推断云端无任务：${e.message}`;
    $('home-task-list').innerHTML='<div class="card"></div>';$('home-task-list').firstChild.textContent=msg;
    $('task-list').innerHTML='<div class="card"></div>';$('task-list').firstChild.textContent=msg;
    throw e;
  }
}
async function refreshAll(){
  if(!state.auth)return;
  const results=await Promise.allSettled([refreshPresence(),refreshTasks()]);
  const errors=results.filter(r=>r.status==='rejected');
  if(errors.length)setStatus('刷新有失败项：'+errors.map(x=>x.reason.message).join('；'));
}
$('presence-refresh').addEventListener('click',()=>refreshAll());
$('tasks-refresh').addEventListener('click',()=>refreshAll());
$('tasks-stop').addEventListener('click',()=>modal('终止所有任务',FAIL_CLOSED+'\n原 Android 一键 STOP 还包含 B ACK、自动释放版本和浏览器重载后的幂等恢复；当前页面没有完整通过这些验证。'));
async function loadHistory(reset=false){
  if(!api.loggedIn)return;
  if(reset){state.historyOffset=0;state.historyRows=[];$('history-list').textContent='正在加载…';}
  $('history-more').disabled=true;
  try{
    const next=await api.tasks(state.historyOffset,30);
    state.historyRows.push(...next);
    state.historyOffset+=next.length;
    $('history-list').replaceChildren();
    if(!state.historyRows.length){$('history-list').innerHTML='<div class="card">暂无云端历史记录</div>';}else{
      state.historyRows.forEach(t=>$('history-list').appendChild(taskCard(t)));
    }
    $('history-more').hidden=next.length<30;
  }catch(e){$('history-list').textContent='读取失败，不代表历史为空：'+e.message;throw e;}
  finally{$('history-more').disabled=false;}
}
$('history-all').addEventListener('click',()=>loadHistory(true).catch(e=>modal('历史失败',e.message)));
$('history-more').addEventListener('click',()=>loadHistory(false).catch(e=>modal('历史失败',e.message)));
function clearObjects(){for(const url of state.activeObjectUrls)URL.revokeObjectURL(url);state.activeObjectUrls=[];}
async function showTaskDetail(id){
  modal('任务详情','正在读取云端记录…');
  try{
    const [record,states,stops]=await Promise.all([api.task(id),api.suiteStates(id).catch(()=>[]),api.stopsFor([id]).catch(()=>[])]);
    if(!record)throw new CloudError('云端未返回该任务记录；不能视为已删除或可重新执行');
    $('modal-heading').textContent='任务 '+id.slice(0,8);
    $('modal-body').textContent=`账号：${record.target_account==='seven'?'七星彩':'排列五'}\n状态：${statusText(record.status)}\n时间：${validDate(record.created_at)}\n任务 ID：${id}\n${record.message||''}\n套码核验：${states.length} 条\n${states.slice(0,35).map(s=>'第'+s.ordinal+'组 '+s.state+' · '+(s.reason||'')).join('\n')}`;
    $('modal-options').replaceChildren();$('modal-actions').replaceChildren();
    const paths=[['统一回图',record.result_path],['散码小票',record.scatter_path],['套码日志',record.suite_path],
      ...stops.map(s=>['STOP 核实图',s.screenshot_path])];
    for(const [title,path] of paths){if(!path)continue;
      const btn=document.createElement('button');btn.className='menu-option';btn.textContent=title+' · 查看或分享';
      btn.addEventListener('click',()=>openScreenshot(title,path,id));$('modal-options').appendChild(btn);
    }
    const done=document.createElement('button');done.className='button primary';done.textContent='关闭';done.style.width='100%';done.onclick=closeModal;$('modal-actions').appendChild(done);
  }catch(e){modal('详情读取失败',e.message);}
}
async function openScreenshot(title,path,id){
  try{
    const blob=await api.screenshot(path);
    if(!blob.type.startsWith('image/'))throw new CloudError('服务器返回的不是图像数据');
    clearObjects();const url=URL.createObjectURL(blob);state.activeObjectUrls.push(url);
    $('modal-heading').textContent=title;$('modal-body').textContent='真实云端私有截图（未做合成或修改）';
    $('modal-options').replaceChildren();
    const img=document.createElement('img');img.className='ticket-image';img.src=url;img.alt=title;$('modal-options').appendChild(img);
    $('modal-actions').replaceChildren();
    const back=document.createElement('button');back.className='button ghost';back.textContent='关闭';back.onclick=()=>{clearObjects();closeModal();};
    const share=document.createElement('button');share.className='button primary';share.textContent='分享/保存';
    share.onclick=async()=>{const file=new File([blob],`${id.slice(0,8)}-${title}.png`,{type:blob.type});
      if(navigator.canShare?.({files:[file]})){try{await navigator.share({files:[file],title});}catch(e){if(e.name!=='AbortError')modal('分享失败',e.message);}}
      else{const link=document.createElement('a');link.href=url;link.download=file.name;link.click();}
    };
    $('modal-actions').append(back,share);
  }catch(e){modal('回图获取失败',e.message);}
}
$('clear-input').addEventListener('click',()=>{if(!$('command').value)return;
  modal('清空输入？','只清空本机输入，不会删除云端任务。',[
    {label:'返回'},{label:'确认清空',primary:true,onClick:()=>{$('command').value='';state.parsed=null;state.parsedText='';setStatus('输入已清空；云端任务不受影响。');}}
  ]);
});
$('input-status').addEventListener('click',()=>modal('任务提示',$('input-status').textContent));
function useParser(input){
  try{const raw=webParser.inspect(input);return JSON.parse(raw);}
  catch(e){return {valid:false,command:null,scatter:[],suites:[],totalJiao:0,issues:[{start:0,end:input.length,severity:'ERROR',message:e.message}]};}
}
function money(jiao){return `${(jiao/10).toFixed(1).replace(/\.0$/,'')}元`;}
function openPreview(){
  const input=$('command').value;
  if(!input.trim()){modal('请输入号码','请先输入或粘贴号码，再打开识别预览。');return;}
  state.parsed=useParser(input);state.parsedText=input;state.filter='全部';
  $('review-only').checked=false;$('suite-screenshot').checked=false;$('convert-odds').checked=false;
  $('original-title').textContent=`原始内容（共 ${input.length} 字）`;
  $('original-text').textContent=input;
  renderPreview();$('preview').hidden=false;$('navbar').hidden=true;
  $('preview').querySelector('.preview-scroll').scrollTop=0;
  if(state.parsed.valid){setStatus(`识别成功：${state.parsed.totalLines}条，预计金额 ${money(Number(state.parsed.totalJiao))}。`);}else{
    setStatus('识别失败：'+state.parsed.issues.filter(x=>x.severity==='ERROR').map(x=>x.message).slice(0,3).join('；'));
  }
}
function renderPreview(){
  const p=state.parsed||{scatter:[],suites:[],issues:[]};
  const scat=p.scatter||[],suite=p.suites||[],issues=p.issues||[];
  const errors=issues.filter(x=>x.severity==='ERROR'),warnings=issues.filter(x=>x.severity==='WARNING');
  $('result-count').textContent=`识别结果（散码 ${Math.max(0,scat.length-(p.turnCount||0))} 组 · 全转 ${p.turnCount||0} 组 · 套码 ${suite.length} 条）`;
  const counts={'全部':scat.length+suite.length+issues.length,'正常':scat.length+suite.length,'需确认':warnings.length,'失败':errors.length};
  document.querySelectorAll('#preview-filters .chip').forEach(b=>{
    const k=b.dataset.filter;b.textContent=`${k}(${counts[k]||0})`;b.classList.toggle('selected',k===state.filter);
  });
  const container=$('preview-rows');container.replaceChildren();
  const rows=[];
  if(state.filter==='全部'||state.filter==='正常'){
    for(const [i,s] of scat.entries())rows.push({name:`${s.number} · 各 ${money(s.amountJiao)}`,sub:`散码第${i+1}条`,kind:'正常'});
    for(const [i,s] of suite.entries())rows.push({name:`${s.canonical} · ${s.expectedCount}笔`,sub:`套码第${i+1}条 · ${money(s.amountJiao)}每笔`,kind:'正常'});
  }
  if(state.filter==='全部'||state.filter==='失败')errors.forEach(x=>rows.push({name:x.message,sub:`输入位置 ${x.start+1}–${x.end}`,kind:'失败',range:x}));
  if(state.filter==='全部'||state.filter==='需确认')warnings.forEach(x=>rows.push({name:x.message,sub:`位置 ${x.start+1}–${x.end}`,kind:'需确认',range:x}));
  if(!rows.length){container.innerHTML='<div class="preview-card result-caption">当前分类下没有项目</div>';}
  rows.forEach((r,i)=>{
    const c=document.createElement('div');c.className='preview-card';c.tabIndex=0;
    const badge=r.kind==='失败'?'<span class="txt-red">● 失败</span>':r.kind==='需确认'?'<span style="color:#b36a00">● 需确认</span>':'<span class="txt-green">● 正常</span>';
    c.innerHTML=`<div class="preview-row"><span class="round-index">${i+1}</span><div class="preview-row-content"><div class="result-top"><strong>${escapeHTML(r.name)}</strong>${badge}</div><div class="result-caption">${escapeHTML(r.sub)}</div></div></div>`;
    if(r.range){const highlight=()=>{
      const from=Math.max(0,Math.min(r.range.start,state.parsedText.length)),to=Math.max(from,Math.min(r.range.end,state.parsedText.length));
      $('original-text').innerHTML=escapeHTML(state.parsedText.slice(0,from))+'<mark>'+escapeHTML(state.parsedText.slice(from,to))+'</mark>'+escapeHTML(state.parsedText.slice(to));
    };c.onclick=highlight;c.onkeydown=e=>{if(e.key==='Enter')highlight();};}
    container.appendChild(c);
  });
  // Disabled in this migration build: native role/STOP/dual-plan transactions not yet accepted.
  $('preview-send').disabled=true;
  $('preview-send').title=FAIL_CLOSED;
}
$('preview-input').addEventListener('click',openPreview);
$('preview-filters').addEventListener('click',e=>{const b=e.target.closest('[data-filter]');if(b){state.filter=b.dataset.filter;renderPreview();}});
$('review-only').addEventListener('change',e=>{state.filter=e.target.checked?'需确认':'全部';renderPreview();});
function closePreview(){$('preview').hidden=true;$('navbar').hidden=false;}
$('preview-back').onclick=closePreview;$('preview-edit').onclick=closePreview;
$('reuse-original').onclick=()=>{$('command').value=state.parsedText;closePreview();};
$('preview-help').onclick=()=>modal('识别预览说明','预览调用 v2.0.51 Kotlin 同源识别规则，并输出原 B 端 M1 指令；浏览器兼容改动已单独存档。\n真实发送需通过完整云端双账号与 STOP 安全状态机验收，不能仅凭解析成功解锁。');
$('preview-copy').onclick=async()=>{try{await navigator.clipboard.writeText(state.parsedText);modal('复制成功','原文已复制');}
  catch(e){modal('复制受限','请长按原始内容复制，或用 HTTPS 打开网页版。');}};
$('preview-send').onclick=()=>modal('不能发送',FAIL_CLOSED);
$('suite-screenshot').addEventListener('change',()=>{if(state.parsed?.valid){const p=JSON.parse(webParser.plan(state.parsedText,$('suite-screenshot').checked,$('convert-odds').checked));
  if(!p.valid)modal('截图模式校验失败',p.error);}});
$('convert-odds').addEventListener('change',()=>{if(state.parsed?.valid){const p=JSON.parse(webParser.plan(state.parsedText,$('suite-screenshot').checked,$('convert-odds').checked));
  if(!p.valid)modal('转换赔率校验失败',p.error);}});
function menu(){
  $('modal-heading').textContent='设置与故障处理';$('modal-body').textContent='';$('modal-options').replaceChildren();$('modal-actions').replaceChildren();
  const choices=[
    ['同步与恢复任务状态',()=>refreshAll()],
    ['网络超时：核对原任务',()=>showPendingSafetyInfo()],
    ['Web 安全状态检查',async()=>{
      if(!state.tx){modal('安全状态','未登录，无法核实角色与云端状态');return;}
      const pending=state.tx.pending();
      const [role,presence,globalControl,unresolved]=await Promise.all([api.isRoleCurrent(),api.presence(),api.globalControl(),api.unresolvedStops()]);
      let ready='不满足';try{requireBReady(presence);ready='空闲且心跳新鲜';}catch{}
      modal('安全状态核查',`当前 A 角色：${role?'有效':'失效'}\nB 状态：${ready}\n全局控制：${globalControl?.action||'未知'} / ${globalControl?.revision||0}\n未决 STOP：${unresolved?.length??'未知'}\n本地未决任务：${pending.task?.requestId||'无'}\n本地未决 STOP：${pending.stop?.requestId||'无'}\n安全写入：生产验收前关闭。`);
    }],
    ['人工核对并结束旧计划',()=>modal('人工结案',FAIL_CLOSED)],
    ['查看本机截图',()=>modal('本机截图','浏览器无法读取 Android A 专用内部文件。可在历史记录打开云端私有截图。')],
    ['退出登录',()=>{api.clear();clearObjects();showLogin('已退出 Web A 会话。本次浏览器会话密钥已清除。');}]
  ];
  choices.forEach(([name,fn])=>{const b=document.createElement('button');b.className='menu-option';b.innerHTML=escapeHTML(name)+'<span>›</span>';b.onclick=()=>{closeModal();Promise.resolve(fn()).catch(e=>modal('操作失败',e.message));};$('modal-options').appendChild(b);});
  const done=document.createElement('button');done.className='button ghost';done.textContent='关闭';done.style.width='100%';done.onclick=closeModal;$('modal-actions').appendChild(done);
  $('overlay').hidden=false;
}
$('open-settings').onclick=menu;
async function tick(){
  if(!api.loggedIn || !state.auth ||document.hidden)return;
  try{
    if(Date.now()-state.lastRoleCheck>15000){state.lastRoleCheck=Date.now();
      const current=await api.isRoleCurrent();if(!current){api.clear();showLogin('同账号已在另一台 A 端登录，当前 Web A 已退出；请到新设备核查任务。');return;}
    }
    await refreshPresence();
    if(state.page==='tasks'||state.page==='entry')await refreshTasks();
  }catch(e){setStatus('后台刷新失败（不代表任务已结束）：'+e.message);}
}
setInterval(tick,10000);
document.addEventListener('visibilitychange',()=>{if(!document.hidden)tick();});
selectPage('entry');showLogin();
