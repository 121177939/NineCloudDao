import {WebAClient, CloudError} from './supabase.js?v=web-a-stage7';
import {WebTransactions} from './transactions.js?v=web-a-stage7';
import {requireBReady} from './safety.js?v=web-a-stage7';
import {createPreviewModel, moneyJiao} from './preview-model.js?v=web-a-stage7';
import {expandLinkedReviewRows, describeSplitExecutions} from './preview-coverage.js?v=web-a-stage7';
import {planHistoryArtifacts, historyCardPresentation, historyDetailStatus} from './history-detail.js?v=web-a-stage7';

// Web A v2.0.51 — GitHub Pages integration candidate. Local mutation state machine is
// implemented and unit-tested, but production write actions stay fail-closed until
// user-approved real Supabase/B acceptance and browser suspend/recovery tests.
const $=id=>document.getElementById(id);
const escapeHTML=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const webParser=globalThis.parser?.com?.example?.remotea?.WebParser;
if(!webParser)throw Error('Kotlin/JS 识别引擎未加载，拒绝提供预览或发送');
const api=new WebAClient();
const state={tx:null,page:'entry',filter:'全部',parsed:null,parsedText:'',lastFocus:null,auth:false,
    busy:false,historyOffset:0,historyRows:[],tasks:[],presence:null,stopRows:[],activeObjectUrls:[],lastRoleCheck:0,previewModel:null,expandedSuites:new Set(),modalRevision:0,currentHistoryArtifacts:[]};
const FAIL_CLOSED='Web 安全一致性验证尚未完成，当前版本禁止真实建单和修改云端任务。请使用已验收的 Android A 端执行该操作。';
function setStatus(text){$('input-status').textContent=text;}
function modal(title,message,actions=[{label:'知道了'}]){
  state.modalRevision+=1;clearObjects();state.currentHistoryArtifacts=[];
  $('modal-actions').classList.remove('history-detail-actions');
  $('modal-heading').textContent=title;$('modal-body').textContent=message;
  $('modal-options').replaceChildren();$('modal-actions').replaceChildren();
  for(const a of actions){const b=document.createElement('button');b.className='button'+(a.primary?' primary':' ghost');b.textContent=a.label;
    b.addEventListener('click',async()=>{closeModal();try{await a.onClick?.();}catch(e){modal('操作失败',e.message);}});$('modal-actions').appendChild(b);}
  state.lastFocus=document.activeElement;$('overlay').hidden=false;$('modal-actions').querySelector('button')?.focus();
}
function closeModal(){state.modalRevision+=1;clearObjects();state.currentHistoryArtifacts=[];$('modal-actions').classList.remove('history-detail-actions');$('overlay').hidden=true;state.lastFocus?.focus?.();}
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
  card.className='card task-card';card.type='button';card.style.cssText='width:100%;text-align:left;color:var(--ink);font:inherit;';
  const acct=row.target_account==='seven'?'七星彩':row.target_account==='arrange'?'排列五':'双账号';
  card.innerHTML=`<div class="row-info"><strong>${escapeHTML(acct)} · ${escapeHTML(statusText(row.status))}</strong><span class="state-chip">›</span></div>
    <div class="sub">${escapeHTML((row.id||'').slice(0,8))} · ${escapeHTML(validDate(row.created_at))}</div>
    <div class="sub">${escapeHTML(String(row.message||'').slice(0,180)||'查看详情、核验记录及原始回图')}</div>`;
  card.addEventListener('click',()=>showTaskDetail(row.id));return card;
}
function historyCard(row){
  const card=document.createElement('button');card.className='card history-card';card.type='button';
  const acct=row.target_account==='seven'?'七星彩':row.target_account==='both'?'双账号检查':'排列五';
  const presentation=historyCardPresentation(row.status,row.message);
  card.innerHTML=`<div class="row-info"><strong>${escapeHTML(acct)}</strong><span class="history-status tone-${escapeHTML(presentation.tone)}"><span class="history-status-dot" aria-hidden="true"></span>${escapeHTML(presentation.label)}</span></div>
    <div class="sub">${escapeHTML(presentation.summary)}</div>`;
  card.setAttribute('aria-label',`${acct}，${presentation.label}，点击查看任务详情与小票`);
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
  if(reset){state.historyRows=[];$('history-list').textContent='正在加载…';}
  try{
    const rows=await api.tasks(0,30);
    state.historyRows=rows;
    const completed=rows.filter(t=>['finished','cancelled','failed'].includes(t.status)).slice(0,8);
    $('history-list').replaceChildren();
    if(!completed.length){$('history-list').innerHTML='<div class="card">暂时没有历史任务</div>';}
    else completed.forEach(t=>$('history-list').appendChild(historyCard(t)));
  }catch(e){$('history-list').textContent='读取失败，不代表历史为空：'+e.message;throw e;}
}
async function showAllHistory(offset=0){
  modal('历史任务','正在读取全部历史…',[{label:'关闭'}]);
  const revision=state.modalRevision;
  try{
    const rows=await api.tasks(offset,30);
    const ids=rows.map(row=>row.id).filter(Boolean);
    const stops=await api.stopsFor(ids).catch(()=>[]);
    if(revision!==state.modalRevision||$('overlay').hidden)return;
    const stopsByTask=new Map();
    for(const stop of stops){if(!stopsByTask.has(stop.task_id))stopsByTask.set(stop.task_id,[]);stopsByTask.get(stop.task_id).push(stop);}
    $('modal-heading').textContent='全部历史 · 最新优先';
    $('modal-body').textContent=`历史任务 · 第${Math.floor(offset/30)+1}页 · 本页${rows.length}条`;
    $('modal-options').replaceChildren();
    const controls=document.createElement('div');controls.className='history-all-controls';
    const control=(label,disabled,action)=>{const button=document.createElement('button');button.className='button ghost';button.textContent=label;button.disabled=disabled;button.addEventListener('click',action);controls.appendChild(button);return button;};
    control('上一页',offset===0,()=>showAllHistory(Math.max(0,offset-30)));
    control('下一页',rows.length<30,()=>showAllHistory(offset+30));
    control('刷新',false,()=>showAllHistory(offset));
    $('modal-options').appendChild(controls);
    const selected=new Set();let shareButton=null;
    const updateShare=()=>{if(shareButton){shareButton.disabled=selected.size===0;shareButton.textContent=`转发勾选小票到微信（${selected.size}个任务，最多6张）`;}};
    if(!rows.length){const empty=document.createElement('p');empty.className='history-artifact-note';empty.textContent='这一页没有历史任务。';$('modal-options').appendChild(empty);}
    for(const row of rows){
      const stopRows=stopsByTask.get(row.id)||[];
      const shareable=[row.result_path,row.scatter_path,row.suite_path].some(path=>typeof path==='string'&&path.trim()!=='');
      const wrap=document.createElement('div');wrap.className='history-all-row';
      const checkbox=document.createElement('input');checkbox.type='checkbox';checkbox.disabled=!shareable;checkbox.setAttribute('aria-label',`选择任务 ${String(row.id||'').slice(0,8)} 的小票`);
      checkbox.addEventListener('change',()=>{if(checkbox.checked)selected.add(row.id);else selected.delete(row.id);updateShare();});
      const entry=document.createElement('button');entry.type='button';entry.className='history-all-entry';
      const presentation=historyCardPresentation(row.status,row.message);
      const account=row.target_account==='seven'?'七星彩':row.target_account==='both'?'双账号检查':'排列五';
      const stopEvidence=stopRows.some(stop=>Boolean(stop.screenshot_path));
      entry.innerHTML=`<div class="row-info"><strong>${escapeHTML(validDate(row.created_at))} · ${escapeHTML(account)}</strong><span class="history-status tone-${escapeHTML(presentation.tone)}">${escapeHTML(presentation.label)} ›</span></div><div class="sub">${escapeHTML(stopEvidence?'终止核实截图可查看':presentation.summary)}</div>`;
      entry.addEventListener('click',()=>showTaskDetail(row.id,offset));
      wrap.append(checkbox,entry);$('modal-options').appendChild(wrap);
    }
    $('modal-actions').replaceChildren();$('modal-actions').classList.remove('history-detail-actions');
    shareButton=document.createElement('button');shareButton.className='button primary';shareButton.disabled=true;shareButton.textContent='转发勾选小票到微信（0个任务，最多6张）';
    shareButton.addEventListener('click',async()=>{
      const chosen=rows.filter(row=>selected.has(row.id));if(!chosen.length)return;
      shareButton.disabled=true;shareButton.textContent='正在准备图片…';
      try{
        const images=[];
        for(const row of chosen){
          const paths=[row.scatter_path,row.suite_path,row.result_path].filter((path,index,all)=>typeof path==='string'&&path.trim()!==''&&all.indexOf(path)===index);
          for(const path of paths){
            try{const blob=await api.screenshot(path);if(blob.type?.startsWith('image/'))images.push({title:'小票',path,kind:'bulk',blob,taskId:row.id});}
            catch{/* A failed image is omitted from the share set; it remains visible in the task detail. */}
            if(images.length>=6)break;
          }
          if(images.length>=6)break;
        }
        if(revision!==state.modalRevision||$('overlay').hidden)return;
        if(!images.length){appendHistoryNotice('勾选的历史任务没有可读取的小票图片；历史记录仍保留。');}
        else await shareHistoryImages(images,chosen[0].id);
      }catch(e){appendHistoryNotice('准备分享失败：'+e.message);}
      finally{if(revision===state.modalRevision&&!$('overlay').hidden)updateShare();}
    });
    $('modal-actions').appendChild(shareButton);
    const close=document.createElement('button');close.className='button ghost';close.textContent='关闭';close.addEventListener('click',closeModal);$('modal-actions').appendChild(close);
  }catch(e){if(revision===state.modalRevision&&!$('overlay').hidden)modal('全部历史读取失败',e.message);}
}
$('history-all').addEventListener('click',()=>showAllHistory(0));
function clearObjects(){for(const url of state.activeObjectUrls)URL.revokeObjectURL(url);state.activeObjectUrls=[];}
function historyAccountLabel(account){return account==='seven'?'七星彩':account==='both'?'两账号启停检查':'排列';}
function suiteStateLabel(value){return ({verified_success:'成功',unsubmitted_failed:'未下注失败',submitted_unknown:'待人工核对',preparing:'准备中'})[value]||'未执行';}
function imageExtension(blob){const type=String(blob?.type||'').toLowerCase();return type.includes('jpeg')||type.includes('jpg')?'jpg':type.includes('webp')?'webp':type.includes('gif')?'gif':'png';}
function safeFilePart(value){return String(value||'小票').replace(/[\\/:*?"<>|\u0000-\u001f]/g,'_').slice(0,48)||'小票';}
function appendHistoryNotice(message){$('modal-body').textContent=($('modal-body').textContent+'\n'+message).trim();}
async function shareHistoryImages(artifacts,id){
  const files=artifacts.map((artifact,index)=>new File([artifact.blob],`${String(artifact.taskId||id).slice(0,8)}-${safeFilePart(artifact.title)}-${index+1}.${imageExtension(artifact.blob)}`,{type:artifact.blob.type||'image/png'}));
  let canShareFiles=false;
  try{canShareFiles=typeof navigator.share==='function'&&typeof navigator.canShare==='function'&&navigator.canShare({files});}catch{}
  if(canShareFiles){
    try{await navigator.share({files,title:`任务 ${id.slice(0,8)} 小票`});}
    catch(e){if(e.name!=='AbortError')appendHistoryNotice('系统分享失败：'+e.message);}
    return;
  }
  for(const file of files){const url=URL.createObjectURL(file);state.activeObjectUrls.push(url);const link=document.createElement('a');link.href=url;link.download=file.name;link.style.display='none';document.body.appendChild(link);link.click();link.remove();}
  appendHistoryNotice(files.length>1?'当前浏览器不支持一次分享多张图片，已分别下载原图。':'当前浏览器不支持系统分享，已下载原图。可在微信中手动选择。');
}
async function showTaskDetail(id,returnToAllHistoryOffset=null){
  modal('任务 '+String(id||'').slice(0,8),'正在读取云端记录…',[{label:returnToAllHistoryOffset===null?'关闭':'返回全部历史',onClick:()=>returnToAllHistoryOffset===null?undefined:showAllHistory(returnToAllHistoryOffset)}]);
  const revision=state.modalRevision;
  try{
    const [record,states,stops]=await Promise.all([api.task(id),api.suiteStates(id).catch(()=>[]),api.stopsFor([id]).catch(()=>[])]);
    if(revision!==state.modalRevision||$('overlay').hidden)return;
    if(!record)throw new CloudError('云端未返回该任务记录；不能视为已删除或可重新执行');
    const planned=planHistoryArtifacts(record,stops);
    const artifacts=await Promise.all(planned.map(async artifact=>{
      try{
        const blob=await api.screenshot(artifact.path);
        if(!blob.type?.startsWith('image/'))throw new CloudError('服务器返回的不是图像数据');
        return {...artifact,blob,error:''};
      }catch(e){return {...artifact,blob:null,error:e.message||'读取失败'};}
    }));
    if(revision!==state.modalRevision||$('overlay').hidden)return;
    state.currentHistoryArtifacts=artifacts.filter(a=>a.blob);
    $('modal-heading').textContent='任务 '+String(id).slice(0,8);
    const lines=[
      `时间：${validDate(record.created_at)}`,
      `任务状态：${historyDetailStatus(record.status)}`,
      `执行账号：${historyAccountLabel(record.target_account)}`,
      `说明：${String(record.message||'无').slice(0,500)}`
    ];
    if(states.length){
      lines.push(`套码核验：${states.length} 条`);
      lines.push(...states.slice(0,35).map(s=>`第${s.ordinal}组 ${suiteStateLabel(s.state)}${s.reason?' · '+s.reason:''}`));
      if(states.length>35)lines.push(`另有 ${states.length-35} 条核验记录未展开`);
    }
    if(stops.length)lines.push(`终止/人工核实记录：${stops.length} 条`);
    $('modal-body').textContent=lines.join('\n');
    $('modal-options').replaceChildren();
    if(!artifacts.length){
      const empty=document.createElement('p');empty.className='history-artifact-note';
      empty.textContent='目前没有可查看的回图。结果不确定时不能重新提交，请人工核实。';$('modal-options').appendChild(empty);
    }
    for(const artifact of artifacts){
      const section=document.createElement('section');section.className='history-artifact';
      const heading=document.createElement('h3');heading.className='history-artifact-title';heading.textContent=artifact.title;section.appendChild(heading);
      if(artifact.blob){
        const image=document.createElement('img');image.className='ticket-image';image.alt=artifact.title;image.loading='lazy';
        const url=URL.createObjectURL(artifact.blob);state.activeObjectUrls.push(url);image.src=url;section.appendChild(image);
        const note=document.createElement('p');note.className='history-artifact-note';note.textContent='真实云端私有截图，未合成或修改';section.appendChild(note);
      }else{
        const error=document.createElement('p');error.className='history-artifact-error';error.textContent='图片读取失败（历史任务仍保留）：'+artifact.error;section.appendChild(error);
      }
      $('modal-options').appendChild(section);
    }
    $('modal-actions').replaceChildren();$('modal-actions').classList.add('history-detail-actions');
    const addAction=(label,{primary=false,disabled=false,title='',onClick=()=>{}}={})=>{
      const button=document.createElement('button');button.className='button'+(primary?' primary':' ghost');button.textContent=label;button.disabled=disabled;if(title)button.title=title;
      button.addEventListener('click',()=>{try{Promise.resolve(onClick()).catch(e=>appendHistoryNotice('操作失败：'+e.message));}catch(e){appendHistoryNotice('操作失败：'+e.message);}});
      $('modal-actions').appendChild(button);return button;
    };
    const scatter=state.currentHistoryArtifacts.find(a=>a.kind==='scatter');
    const suite=state.currentHistoryArtifacts.find(a=>a.kind==='suite');
    const stop=state.currentHistoryArtifacts.find(a=>a.kind==='stop');
    const single=scatter||suite||stop;
    const singleLabel=!single?'转发小票到微信':single.kind==='stop'?'转发人工核实截图':single.kind==='suite'?(single.title==='套码下注页截图'?'转发套码下注页截图':'转发日志截图'):'转发小票到微信';
    addAction(singleLabel,{primary:true,disabled:!single,onClick:()=>single&&shareHistoryImages([single],id)});
    addAction('两张图片一起发微信',{disabled:!(scatter&&suite),title:scatter&&suite?'':'需要同时存在可读取的散码小票和套码图片',onClick:()=>scatter&&suite&&shareHistoryImages([scatter,suite],id)});
    addAction('A 端人工核实 · 结案并通知 B 自动恢复接单',{disabled:true,title:FAIL_CLOSED});
    const safetyNote=document.createElement('p');safetyNote.className='history-safety-note';safetyNote.textContent='分享由系统确认；若浏览器不支持则保存原图。网页端结案和恢复接单仍关闭。';$('modal-actions').appendChild(safetyNote);
    if(returnToAllHistoryOffset===null)addAction('关闭',{onClick:()=>closeModal()});
    else addAction('返回全部历史',{onClick:()=>showAllHistory(returnToAllHistoryOffset)});
  }catch(e){if(revision===state.modalRevision&&!$('overlay').hidden)modal('详情读取失败',e.message);}
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
  state.previewModel=createPreviewModel(input,state.parsed);state.expandedSuites.clear();
  $('review-only').checked=false;$('suite-screenshot').checked=false;$('convert-odds').checked=false;
  $('original-title').textContent=`原始内容（共 ${input.length} 字）`;
  $('original-text').textContent=input;
  renderPreview();$('preview').hidden=false;$('navbar').hidden=true;
  $('preview').querySelector('.preview-scroll').scrollTop=0;
  if(state.parsed.valid){setStatus(`识别成功：${state.parsed.totalLines}条，预计金额 ${money(Number(state.parsed.totalJiao))}。`);}else{
    setStatus('识别失败：'+state.parsed.issues.filter(x=>x.severity==='ERROR').map(x=>x.message).slice(0,3).join('；'));
  }
}
function setPreviewHighlights(spans=[]){
  const source=state.parsedText, model=state.previewModel;
  const marks=[];
  for(const i of model.ignored)marks.push({...i,priority:1,cls:'ignored-mark'});
  for(const i of spans)if(i?.matched && i.start<i.end)marks.push({...i,priority:2,cls:'selected-mark'});
  // Draw from source offsets without altering source text, checksum, or recognition result.
  const tags=Array.from({length:source.length},()=>null);
  for(const span of marks){
    for(let pos=Math.max(0,span.start);pos<Math.min(source.length,span.end);pos++){
      if(!tags[pos]||tags[pos].priority<=span.priority)tags[pos]=span;
    }
  }
  let result='',pos=0;
  while(pos<source.length){
    const tag=tags[pos];let end=pos+1;
    while(end<source.length && tags[end]?.cls===tag?.cls)end++;
    const part=escapeHTML(source.slice(pos,end));
    result+=tag?`<mark class="${tag.cls}">${part}</mark>`:part;
    pos=end;
  }
  $('original-text').innerHTML=result;
}
function makePreviewCard(index,title,status='正常'){
  const card=document.createElement('div');card.className='preview-card';
  const heading=document.createElement('div');heading.className='preview-row';
  const badge=document.createElement('span');badge.className='round-index';badge.textContent=index;
  const content=document.createElement('div');content.className='preview-row-content';
  const head=document.createElement('div');head.className='result-top';
  const titleNode=document.createElement('strong');titleNode.textContent=title;
  const statusNode=document.createElement('span');statusNode.className=`row-status ${status==='正常'?'txt-green':'txt-amber'}`;
  statusNode.textContent=status==='正常'?'✓ 正常':`● ${status}`;
  head.append(titleNode,statusNode);content.append(head);heading.append(badge,content);card.append(heading);
  return {card,content};
}
function previewDetail(node,text,style=''){
  const el=document.createElement('div');el.className='preview-detail '+style;el.textContent=text;node.appendChild(el);return el;
}
function renderPreview(){
  const model=state.previewModel;
  if(!model)return;
  $('result-count').textContent=`识别结果（散码 ${model.scatterCount} 组 · 全转 ${model.turnCount} 组 · 套码 ${model.suiteCount} 条）`;
  const counts={'全部':model.totalCount,'正常':model.normalCount,'需确认':model.reviewCount,'失败':model.failCount};
  document.querySelectorAll('#preview-filters .chip').forEach(button=>{
    const key=button.dataset.filter;button.textContent=`${key}(${counts[key]||0})`;
    button.classList.toggle('selected',key===state.filter);
  });
  setPreviewHighlights([]);
  const note=$('preview-ignored');note.replaceChildren();
  if(model.ignored.length){
    note.hidden=false;note.textContent='已自动忽略：'+model.ignored.map(x=>x.source).join('、');
    note.onclick=()=>setPreviewHighlights(model.ignored);
  }else note.hidden=true;
  const onlyReview=$('review-only').checked;
  const isVisible=row=>{
    if(onlyReview)return row.status!=='正常';
    if(state.filter==='全部')return true;
    return row.status===state.filter;
  };
  const host=$('preview-rows');host.replaceChildren();
  // Keep all linked execution slices visible together: '0336各88组' is
  // split by the Android parser into 50+38; review-only must not show 38 alone.
  const scatter=expandLinkedReviewRows(model.scatter,isVisible);
  const scatterStatus=scatter.some(x=>x.status==='需确认')?'需确认':'正常';
  const group=makePreviewCard(1,'散码区',scatterStatus);
  if(!scatter.length){
    previewDetail(group.content,onlyReview||state.filter!=='全部'?'当前筛选下没有散码':'本次没有单组散码','result-caption');
  }else{
    const rawEvidence=scatter.filter(x=>x.matched).map(x=>x.source);
    const unlocated=scatter.filter(x=>!x.matched).length;
    previewDetail(group.content,'原文：'+(rawEvidence.join('，')||'未定位')+(unlocated?`（另有 ${unlocated} 条解析执行项不能独立定位）`:''),'preview-raw');
    const grouped=new Map();
    for(const item of scatter){
      if(!grouped.has(item.amountText))grouped.set(item.amountText,[]);
      grouped.get(item.amountText).push(item.number);
    }
    previewDetail(group.content,'识别：'+[...grouped].map(([amount,codes])=>`${codes.join('、')}各${amount}`).join('；'),'preview-recognized');
    for(const summary of describeSplitExecutions(scatter)){
      previewDetail(group.content,summary,'txt-amber');
    }
    const problems=[...new Set(scatter.map(x=>x.detail).filter(Boolean))];
    if(problems.length)previewDetail(group.content,'提示：'+problems.join('；'),'txt-amber');
    group.card.setAttribute('role','button');group.card.tabIndex=0;
    const highlight=()=>setPreviewHighlights(scatter);
    group.card.addEventListener('click',highlight);
    group.card.addEventListener('keydown',e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();highlight();}});
  }
  host.appendChild(group.card);
  if(model.turnCount){
    const turn=document.createElement('div');turn.className='preview-card';
    const label=document.createElement('strong');label.textContent=`全转区（${model.turnCount}条独立执行项）`;
    turn.appendChild(label);
    const visibleTurn=expandLinkedReviewRows(model.turns,isVisible);
    if(!visibleTurn.length)previewDetail(turn,'当前筛选下无全转','result-caption');
    for(const item of visibleTurn)previewDetail(turn,`第${item.executionIndex}组 · ${item.number} · 全转 · 各${item.amountText}${!item.matched?' · 来源未单独定位':''}`,'preview-recognized');
    turn.onclick=()=>setPreviewHighlights(visibleTurn);host.appendChild(turn);
  }
  const visibleSuites=model.suites.filter(isVisible);
  for(const [visualIndex,row] of visibleSuites.entries()){
    const detail=makePreviewCard(visualIndex+2,'原文：'+row.source,row.status);
    const main=document.createElement('div');main.className='preview-suite-line';
    const recognize=document.createElement('span');recognize.className='preview-recognized';
    recognize.textContent=`识别：${row.recognition}各${row.amountText}`;
    const expanded=state.expandedSuites.has(row.index);
    const expand=document.createElement('span');expand.className='result-caption';
    expand.textContent=expanded?'收起 ⌄':`展开 ${row.expectedCount} 组 ›`;
    main.append(recognize,expand);detail.content.append(main);
    if(row.detail)previewDetail(detail.content,'提示：'+row.detail,'txt-amber');
    if(expanded){
      const pane=document.createElement('div');pane.className='preview-suite-examples';
      previewDetail(pane,`展开号码（共 ${row.expectedCount} 组）`,'txt-blue');
      const examples=row.examples||[];
      previewDetail(pane,examples.reduce((acc,x,i)=>acc+x+((i+1)%5===0?'\n':'   '),'').trim()+(row.expectedCount>examples.length?'\n……':''));
      detail.content.append(pane);
    }
    detail.card.tabIndex=0;detail.card.setAttribute('role','button');
    const toggle=()=>{setPreviewHighlights(row.matched?[row]:[]);
      if(state.expandedSuites.has(row.index))state.expandedSuites.delete(row.index);
      else state.expandedSuites.add(row.index);
      renderPreview();setPreviewHighlights(row.matched?[row]:[]);};
    detail.card.onclick=toggle;detail.card.onkeydown=e=>{if(e.key==='Enter'||e.key===' '){e.preventDefault();toggle();}};
    host.appendChild(detail.card);
  }
  if(!model.suiteCount&&state.filter==='全部'&&!onlyReview){
    const empty=document.createElement('div');empty.className='preview-card preview-empty-suite';
    empty.textContent='本次没有需要展开的套码';host.appendChild(empty);
  }
  if(model.errors.length&&(state.filter==='全部'||state.filter==='失败'||onlyReview)){
    model.errors.forEach(issue=>{
      const card=document.createElement('div');card.className='preview-card';card.style.color='var(--red)';
      card.textContent=`失败：${issue.message}（位置 ${issue.start+1}–${issue.end}）`;
      card.onclick=()=>setPreviewHighlights([{start:issue.start,end:issue.end,matched:true}]);host.appendChild(card);
    });
  }
  $('preview-send').disabled=true;
  $('preview-send').title=FAIL_CLOSED;
}
$('preview-input').addEventListener('click',openPreview);
$('preview-filters').addEventListener('click',e=>{const b=e.target.closest('[data-filter]');if(b){state.filter=b.dataset.filter;renderPreview();}});
$('review-only').addEventListener('change',e=>{state.filter=e.target.checked?'需确认':'全部';renderPreview();});
function closePreview(){$('preview').hidden=true;$('navbar').hidden=false;}
$('preview-back').onclick=closePreview;$('preview-edit').onclick=closePreview;
$('reuse-original').onclick=()=>{$('command').value=state.parsedText;closePreview();};
$('preview-help').onclick=()=>modal('识别预览使用说明','原始内容完整展开。最终只生成1组号码的内容统一汇总到编号1“散码区”；散码区同时显示所有散码原文与按金额归组后的识别结果。点击散码区可以高亮相关原文；生成2组及以上的套码逐条展示并可展开。自动忽略的标题文字用黄色标记，不占编号。\n真实发送仍需通过安全验收。');
$('preview-copy').onclick=async()=>{
  const model=state.previewModel;
  const text=['散码区',model?.scatterCount?'原文：'+model.scatterOriginal:'无',
    ...(model?.scatterCount?['识别：'+model.scatterRecognition]:[]),
    ...(model?.turnCount?['全转区',...model.turns.map(r=>`第${r.executionIndex}组 ${r.number} 全转 各${r.amountText}`)]:[]),
    ...(model?.suiteCount?['套码',...model.suites.map(r=>`原文：${r.source} -> ${r.recognition}各${r.amountText}`)]:[]),
    ...(model?.ignored?.length?['已忽略：'+model.ignored.map(x=>x.source).join('、')]:[])].join('\n');
  try{await navigator.clipboard.writeText(text);modal('复制成功','识别结果已复制');}
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
