(() => {
  'use strict';
  const MODULE='B-EQUIPMENT01';
  const config=window.GAME_CONFIG||{};
  const baseUrl=String(config.supabaseUrl||'').replace(/\/+$/,'');
  const apiKey=String(config.supabasePublishableKey||'');
  const projectRef=(()=>{try{return new URL(baseUrl).hostname.split('.')[0]}catch{return'unknown'}})();
  const sessionKey=`nine_cloud_dao_session_${projectRef}_v1`;
  const deviceKey=`nine_cloud_dao_device_${projectRef}_v1`;
  const gradeColors={yellow:'#C99A32',mystic:'#4F86D9',earth:'#925FD1',heaven:'#E05252',immortal:'#F2D06B'};
  const slotMeta={weapon:['攻','武器'],clothing:['御','衣服'],pants:['生','裤子'],shoes:['身','鞋子'],ring:['元','戒指']};
  const weaponKindLabels={sword:'剑',blade:'刀',spear:'枪',staff:'棍',fan:'扇',wand:'杖',qin:'琴',ring_blade:'环'};
  const state={data:null,loading:false,view:'backpack',filter:'all',sort:'grade',lastFetch:0,available:false,disabled:false,lastOpportunityId:null};
  const esc=v=>String(v??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#039;');
  const uuid=()=>globalThis.crypto?.randomUUID?.()||'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g,c=>{const v=Math.random()*16|0;return(c==='x'?v:(v&3|8)).toString(16)});
  const session=()=>{try{return JSON.parse(localStorage.getItem(sessionKey)||'null')}catch{return null}};
  const device=()=>localStorage.getItem(deviceKey)||'';
  const toast=(message,type='success')=>{const el=document.getElementById('toast');if(!el)return;el.textContent=message;el.className=`toast show ${type}`;clearTimeout(toast.t);toast.t=setTimeout(()=>el.className='toast',3800)};
  const errorText=e=>{const raw=String(e?.message||e||'装备操作失败');const map=[['EQUIPMENT_BACKPACK_FULL','背包空间不足。'],['EQUIPMENT_REALM_TOO_HIGH','当前境界不足，不能穿戴这件装备。'],['EQUIPMENT_ITEM_NOT_FOUND','装备不存在或已被处理。'],['EQUIPMENT_ITEM_NOT_IN_BACKPACK','只有背包中的装备可以穿戴。'],['EQUIPMENT_DECOMPOSE_PROTECTED_OR_MISSING','所选装备包含锁定、非背包或已不存在的装备。'],['EQUIPMENT_ESSENCE_INSUFFICIENT','器源精粹数量不足。'],['EQUIPMENT_SLOT_EMPTY','该装备槽当前为空。'],['EQUIPMENT_SYSTEM_DISABLED','装备系统当前已停用。'],['EQUIPMENT_DECOMPOSE_BATCH_TOO_LARGE','单次最多分解100件装备。'],['AUTH_REQUIRED','请先登录后使用装备系统。'],['PGRST202','装备数据库尚未完成升级。'],['Could not find the function','装备数据库尚未完成升级。']];return(map.find(([k])=>raw.includes(k))||[])[1]||raw};
  async function rpc(name,body={}){
    const s=session();if(!s?.access_token)throw new Error('AUTH_REQUIRED');
    const res=await fetch(`${baseUrl}/rest/v1/rpc/${name}`,{method:'POST',headers:{apikey:apiKey,Authorization:`Bearer ${s.access_token}`,'Content-Type':'application/json','X-Game-Session-Id':device()},body:JSON.stringify(body)});
    const text=await res.text();let data=null;try{data=text?JSON.parse(text):null}catch{data=text}
    if(!res.ok)throw new Error(data?.message||data?.msg||data?.error||`HTTP ${res.status}`);
    return Array.isArray(data)?data[0]||null:data;
  }
  function itemList(location){return Array.isArray(state.data?.[location])?state.data[location]:[]}
  function allItems(){return [...itemList('backpack'),...itemList('cave'),...itemList('pending'),...Object.values(state.data?.equipped||{}).filter(Boolean)]}
  async function refresh(force=false){
    if(state.loading||!session()?.access_token)return state.data;
    if(!force&&Date.now()-state.lastFetch<5000)return state.data;
    state.loading=true;
    try{state.data=await rpc('get_equipment_system_bequipment01');state.available=true;state.disabled=state.data?.status==='disabled';state.lastFetch=Date.now();renderAll();return state.data}
    catch(e){state.available=false;renderAll();return null}
    finally{state.loading=false}
  }
  async function action(name,body,success){
    if(state.disabled){toast('装备系统当前已停用。','error');return}
    try{await rpc(name,{...body,p_request_id:uuid()});await refresh(true);if(success)toast(success)}catch(e){toast(errorText(e),'error');await refresh(true)}
  }
  function color(item){return item?.grade_color||gradeColors[item?.grade_code]||'#8f8068'}
  function itemIcon(item){return `<span class="equipment-icon-bequipment01" style="--grade:${esc(color(item))}">${esc(item?.icon_glyph||slotMeta[item?.slot_code]?.[0]||'器')}</span>`}
  function slotCardContent(item,slot){
    const [emptyGlyph,label]=slotMeta[slot];
    if(!item)return `<span class="yuanshen-sigil-v0155 equipment-empty-icon-bequipment01" aria-hidden="true">${emptyGlyph}</span><span class="yuanshen-stat-copy-v0155"><strong>${label}：未装备</strong><i></i><small>空槽 · 点击查看背包</small></span>`;
    return `${itemIcon(item)}<span class="yuanshen-stat-copy-v0155 equipment-copy-bequipment01"><strong>${esc(item.short_name)}：<em style="color:${esc(color(item))}">${esc(item.grade_name)}</em></strong><i></i><small>${esc(item.realm_name)}</small><small>${esc(item.main_stat_display)}</small><small>${esc(item.socket_display)}</small></span>`;
  }
  function renderSpiritSlots(){
    const root=document.getElementById('primordialSpiritRootV1');if(!root||!state.available||!state.data)return;
    const map={weapon:'.left-1',clothing:'.left-2',pants:'.right-1',shoes:'.right-2',ring:'.right-3'};
    Object.entries(map).forEach(([slot,sel])=>{
      const btn=root.querySelector(`.yuanshen-stat-card-v0155${sel}`);if(!btn)return;
      const item=state.data?.equipped?.[slot]||null;
      btn.classList.add('equipment-slot-card-bequipment01');btn.style.setProperty('--grade',color(item));btn.dataset.equipmentSlot=slot;
      btn.dataset.yuanshenStat=slotMeta[slot][1];btn.dataset.yuanshenDetail=item?`${item.full_name} · ${item.grade_name} · ${item.realm_name} · ${item.main_stat_display} · ${item.socket_display}`:`${slotMeta[slot][1]}槽尚未装备。`;
      btn.innerHTML=slotCardContent(item,slot);
      if(btn.dataset.equipmentBound!=='1'){btn.dataset.equipmentBound='1';btn.addEventListener('click',ev=>{ev.stopPropagation();const current=state.data?.equipped?.[btn.dataset.equipmentSlot];if(current)openDetail(current);else focusBackpack()})}
    })
  }
  function sortItems(rows){return [...rows].sort((a,b)=>state.sort==='time'?String(b.acquired_at).localeCompare(String(a.acquired_at)):(Number(b.grade_order)-Number(a.grade_order)||Number(b.major_order)-Number(a.major_order)||String(a.full_name).localeCompare(String(b.full_name),'zh-CN')))}
  function filtered(rows){return sortItems(rows.filter(x=>state.filter==='all'||x.slot_code===state.filter))}
  function gridItem(item){return `<button type="button" class="equipment-grid-item-bequipment01" style="--grade:${esc(color(item))}" data-equipment-item="${esc(item.id)}" aria-label="${esc(item.full_name)}，${esc(item.grade_name)}"><span class="equipment-grid-lock-bequipment01">${item.is_locked?'锁':''}</span>${itemIcon(item)}<strong>${esc(item.short_name)}</strong><span class="equipment-grade-bequipment01">${esc(item.grade_name)}</span><small>${esc(item.realm_name)} · ${esc(item.main_stat_display)}</small><em>${esc(item.socket_display)}</em></button>`}
  function materialItem(q,loc){if(Number(q)<=0)return'';return `<button type="button" class="equipment-grid-item-bequipment01 material" data-equipment-material="${loc}"><span class="equipment-icon-bequipment01">粹</span><strong>器源精粹</strong><small>开孔预留材料</small><em>×${Number(q).toLocaleString()}</em></button>`}
  function storagePanel(location='backpack'){
    const cap=Math.max(36,Number(state.data?.rules?.backpack_capacity||36));const allRows=itemList('backpack');const rows=filtered(allRows);const material=Number(state.data?.materials?.essence_backpack||0);
    const used=allRows.length+(material>0?1:0);const showMaterial=state.filter==='all';const visibleUsed=rows.length+(showMaterial&&material>0?1:0);const empty=Math.max(0,cap-visibleUsed);
    return `<section class="equipment-storage-panel-bequipment01" data-equipment-panel="backpack"><div class="equipment-storage-head-bequipment01"><strong>随身背包</strong><span>${used}/${cap} · 固定6×6 · 装备一件一格</span></div><div class="equipment-filter-bequipment01"><button data-eq-filter="all">全部</button>${Object.entries(slotMeta).map(([k,v])=>`<button data-eq-filter="${k}">${v[1]}</button>`).join('')}<button data-eq-sort>${state.sort==='grade'?'恢复所得顺序':'一键整理'}</button><button class="batch-decompose-bequipment01" data-batch-decompose>批量分解</button></div><div class="equipment-grid-bequipment01">${rows.map(gridItem).join('')}${showMaterial?materialItem(material,'backpack'):''}${Array.from({length:empty},()=>'<div class="equipment-grid-empty-bequipment01">道</div>').join('')}</div></section>`
  }
  function caveEquipmentSlot(item){
    const rarity={yellow:'uncommon',mystic:'rare',earth:'epic',heaven:'legendary',immortal:'legendary'}[item?.grade_code]||'uncommon';
    return `<button type="button" class="cave-item-slot-b01 rarity-${rarity} equipment-cave-slot-bequipment01" data-equipment-cave-item="${esc(item.id)}" aria-label="洞府装备，${esc(item.full_name)}，${esc(item.grade_name)}"><span class="cave-item-aura-b01" aria-hidden="true"></span>${itemIcon(item)}<span class="cave-item-name-b01">${esc(item.short_name)}</span><span class="cave-item-type-b01">${esc(item.grade_name)} · ${esc(slotMeta[item.slot_code]?.[1]||'装备')}</span><strong class="cave-item-quantity-b01">器</strong></button>`
  }
  function openCaveEquipmentBox(items=itemList('cave')){
    const rows=sortItems(items);const cap=Math.max(36,Math.ceil(Math.max(1,rows.length)/36)*36);const empty=Math.max(0,cap-rows.length);
    modalHost().innerHTML=`<div class="modal-backdrop equipment-modal-backdrop-bequipment01"><section class="modal equipment-modal-bequipment01 equipment-cave-box-modal-bequipment01" role="dialog" aria-modal="true"><button class="modal-close-button" data-eq-close>×</button><header><span class="equipment-icon-bequipment01">藏</span><div><span>洞府储物中的装备</span><h3>装备匣 · ${rows.length}件</h3></div></header><div class="equipment-grid-bequipment01 equipment-cave-box-grid-bequipment01">${rows.map(gridItem).join('')}${Array.from({length:empty},()=>'<div class="equipment-grid-empty-bequipment01">道</div>').join('')}</div></section></div>`;
    const root=modalHost();root.querySelector('[data-eq-close]').onclick=closeModal;root.querySelector('.equipment-modal-backdrop-bequipment01').onclick=e=>{if(e.target===e.currentTarget)closeModal()};root.querySelectorAll('[data-equipment-item]').forEach(b=>b.onclick=()=>{const item=allItems().find(x=>String(x.id)===b.dataset.equipmentItem);if(item){closeModal();openDetail(item)}})
  }
  function renderCaveEquipmentIntoNative(){
    const cave=document.getElementById('caveStorageB01');const grid=cave?.querySelector('.cave-storage-grid-b01');if(!cave||!grid||!state.available)return;
    grid.querySelectorAll('[data-equipment-cave-item]').forEach(node=>node.remove());cave.querySelector('[data-equipment-cave-overflow]')?.remove();
    const rows=sortItems(itemList('cave'));const empties=[...grid.querySelectorAll('.cave-item-slot-b01.empty')];const visible=rows.slice(0,empties.length);
    visible.forEach((item,index)=>{empties[index].outerHTML=caveEquipmentSlot(item)});
    grid.querySelectorAll('[data-equipment-cave-item]').forEach(b=>b.onclick=()=>{const item=allItems().find(x=>String(x.id)===b.dataset.equipmentCaveItem);if(item)openDetail(item)});
    const head=cave.querySelector('.cave-storage-head-b01 span');if(head){const base=head.dataset.equipmentBaseText||head.textContent.replace(/ · 洞府装备 \d+$/,'');head.dataset.equipmentBaseText=base;head.textContent=`${base} · 洞府装备 ${rows.length}`}
    if(rows.length>visible.length){const overflow=document.createElement('button');overflow.type='button';overflow.className='equipment-cave-overflow-bequipment01';overflow.dataset.equipmentCaveOverflow='1';overflow.textContent=`另有 ${rows.length-visible.length} 件洞府装备，打开装备匣`;overflow.onclick=()=>openCaveEquipmentBox(rows);grid.insertAdjacentElement('afterend',overflow)}
  }
  function bindBackpackPanel(root){
    if(!root)return;
    root.querySelectorAll('[data-eq-filter]').forEach(b=>{b.classList.toggle('active',b.dataset.eqFilter===state.filter);b.onclick=()=>{state.filter=b.dataset.eqFilter;renderBackpackInline()}});
    root.querySelector('[data-eq-sort]')?.addEventListener('click',()=>{state.sort=state.sort==='grade'?'time':'grade';renderBackpackInline()});
    root.querySelector('[data-batch-decompose]')?.addEventListener('click',openBatchDecompose);
    root.querySelectorAll('[data-equipment-item]').forEach(b=>b.onclick=()=>{const item=allItems().find(x=>String(x.id)===b.dataset.equipmentItem);if(item)openDetail(item)});
    root.querySelector('[data-claim-pending]')?.addEventListener('click',()=>action('claim_pending_equipment_bequipment01',{},'待领取装备已按空位收入背包。'));
    root.querySelector('[data-equipment-material]')?.addEventListener('click',e=>openMaterial(e.currentTarget.dataset.equipmentMaterial));
  }
  function renderBackpackInline(){
    const root=document.getElementById('primordialSpiritRootV1');if(!root)return;
    root.querySelector('#equipmentBackpackLauncherBEquipment01')?.remove();
    let host=root.querySelector('#equipmentBackpackInlineBEquipment01');
    if(!host){host=document.createElement('section');host.id='equipmentBackpackInlineBEquipment01';host.className='equipment-backpack-inline-bequipment01';root.appendChild(host)}
    const pending=itemList('pending').length;
    host.innerHTML=`${state.disabled?'<div class="equipment-disabled-bequipment01">装备系统当前已停用：装备数据只读，写操作已关闭。</div>':''}${pending?`<div class="equipment-pending-bequipment01"><span>待领取装备 ${pending} 件</span><button type="button" data-claim-pending>领取到背包</button></div>`:''}${state.available?storagePanel('backpack'):'<div class="equipment-unavailable-bequipment01">装备数据库尚未完成升级。</div>'}`;
    bindBackpackPanel(host)
  }
  function focusBackpack(){
    renderBackpackInline();
    document.getElementById('equipmentBackpackInlineBEquipment01')?.scrollIntoView({behavior:'smooth',block:'start'})
  }
  function openBackpack(){focusBackpack()}
  function compare(item){const current=state.data?.equipped?.[item.slot_code];if(!current)return`当前${slotMeta[item.slot_code][1]}槽为空，穿戴后增加 ${item.main_stat_display}。`;const diff=Number(item.main_stat_value)-Number(current.main_stat_value);return`当前：${current.main_stat_display}；新装备：${item.main_stat_display}；变化：${diff>=0?'+':''}${item.slot_code==='ring'?diff.toFixed(1)+'%':Math.round(diff)}。`}
  function modalHost(){let root=document.getElementById('equipmentModalRootBEquipment01');if(!root){root=document.createElement('div');root.id='equipmentModalRootBEquipment01';document.body.appendChild(root)}return root}
  function closeModal(){modalHost().innerHTML=''}
  function openDetail(item){
    const equipped=item.location==='equipped';const inBag=item.location==='backpack';const inCave=item.location==='cave';
    const actions=[];
    if(inBag)actions.push(`<button class="primary-btn" data-eq-action="equip">${state.data?.equipped?.[item.slot_code]?'更换':'穿戴'}</button>`);
    if(equipped)actions.push('<button class="ghost-btn" data-eq-action="unequip">卸下</button>');
    if(inBag)actions.push('<button class="ghost-btn" data-eq-action="cave">放入洞府</button>');
    if(inCave)actions.push('<button class="ghost-btn" data-eq-action="backpack">取回背包</button>');
    if(inBag||inCave)actions.push(`<button class="ghost-btn" data-eq-action="lock">${item.is_locked?'解锁':'锁定'}</button>`);
    if(inBag)actions.push(`<button class="danger-btn" data-eq-action="decompose" ${item.is_locked?'disabled':''}>分解得器源精粹×${Number(item.decompose_essence)}</button>`);
    modalHost().innerHTML=`<div class="modal-backdrop equipment-modal-backdrop-bequipment01"><section class="modal equipment-modal-bequipment01" role="dialog" aria-modal="true"><button class="modal-close-button" data-eq-close>×</button><header style="--grade:${esc(color(item))}">${itemIcon(item)}<div><span>${esc(item.realm_name)} · ${esc(slotMeta[item.slot_code][1])}${item.weapon_kind?' · '+esc(item.weapon_kind_label||weaponKindLabels[item.weapon_kind]||item.weapon_kind):''}</span><h3>${esc(item.short_name)}：<em>${esc(item.grade_name)}</em></h3></div></header><div class="equipment-detail-main-bequipment01"><strong>${esc(item.main_stat_display)}</strong><span>${esc(item.socket_display)}</span></div><p>${esc(compare(item))}</p><dl><div><dt>完整名称</dt><dd>${esc(item.full_name)}</dd></div><div><dt>存放位置</dt><dd>${equipped?'已穿戴':inBag?'背包':inCave?'洞府':'待领取'}</dd></div><div><dt>保护状态</dt><dd>${item.is_locked?'已锁定':'未锁定'}</dd></div></dl><div class="equipment-modal-actions-bequipment01">${actions.join('')}</div></section></div>`;
    const root=modalHost();root.querySelector('[data-eq-close]').onclick=closeModal;root.querySelector('.equipment-modal-backdrop-bequipment01').onclick=e=>{if(e.target===e.currentTarget)closeModal()};
    root.querySelector('[data-eq-action="equip"]')?.addEventListener('click',()=>{closeModal();action('equip_item_bequipment01',{p_item_id:item.id},'装备已穿戴。')});
    root.querySelector('[data-eq-action="unequip"]')?.addEventListener('click',()=>{closeModal();action('unequip_item_bequipment01',{p_slot_code:item.slot_code},'装备已卸下。')});
    root.querySelector('[data-eq-action="cave"]')?.addEventListener('click',()=>{closeModal();action('move_equipment_item_bequipment01',{p_item_id:item.id,p_target_location:'cave'},'装备已放入洞府。')});
    root.querySelector('[data-eq-action="backpack"]')?.addEventListener('click',()=>{closeModal();action('move_equipment_item_bequipment01',{p_item_id:item.id,p_target_location:'backpack'},'装备已取回背包。')});
    root.querySelector('[data-eq-action="lock"]')?.addEventListener('click',()=>{closeModal();action('set_equipment_lock_bequipment01',{p_item_id:item.id,p_locked:!item.is_locked},item.is_locked?'装备已解锁。':'装备已锁定。')});
    root.querySelector('[data-eq-action="decompose"]')?.addEventListener('click',()=>{if(!confirm(`确认分解【${item.full_name}：${item.grade_name}】？将获得器源精粹×${item.decompose_essence}，操作不可撤销。`))return;closeModal();action('decompose_equipment_bequipment01',{p_item_ids:[item.id]},`分解完成，获得器源精粹×${item.decompose_essence}。`)})
  }
  function openBatchDecompose(){
    const candidates=itemList('backpack').filter(item=>!item.is_locked);
    if(!candidates.length){toast('背包中没有可分解的未锁定装备。','error');return}
    const defaultSelected=new Set(candidates.filter(item=>['yellow','mystic'].includes(item.grade_code)).map(item=>String(item.id)));
    const rows=candidates.map(item=>`<label class="equipment-batch-row-bequipment01" style="--grade:${esc(color(item))}"><input type="checkbox" data-batch-id="${esc(item.id)}" ${defaultSelected.has(String(item.id))?'checked':''}><span>${itemIcon(item)}</span><span><strong>${esc(item.short_name)}：<em>${esc(item.grade_name)}</em></strong><small>${esc(item.realm_name)} · ${esc(item.main_stat_display)} · ${esc(item.socket_display)}</small></span><b>精粹×${Number(item.decompose_essence)}</b></label>`).join('');
    modalHost().innerHTML=`<div class="modal-backdrop equipment-modal-backdrop-bequipment01"><section class="modal equipment-modal-bequipment01 equipment-batch-modal-bequipment01" role="dialog" aria-modal="true"><button class="modal-close-button" data-eq-close>×</button><header><span class="equipment-icon-bequipment01">解</span><div><span>批量分解 · 默认勾选黄品与玄品</span><h3>装备化源</h3></div></header><div class="equipment-batch-tools-bequipment01"><button type="button" data-batch-low>勾选黄玄</button><button type="button" data-batch-clear>清空</button><strong data-batch-summary></strong></div><div class="equipment-batch-list-bequipment01">${rows}</div><p>地品及以上不会自动勾选；分解不可撤销，锁定、穿戴、洞府与待领取装备已自动排除。</p><div class="equipment-modal-actions-bequipment01"><button class="danger-btn" data-batch-confirm>确认分解</button></div></section></div>`;
    const root=modalHost();
    const boxes=()=>[...root.querySelectorAll('[data-batch-id]')];
    const update=()=>{const selected=boxes().filter(x=>x.checked).map(x=>candidates.find(item=>String(item.id)===x.dataset.batchId)).filter(Boolean);const gain=selected.reduce((sum,item)=>sum+Number(item.decompose_essence||0),0);root.querySelector('[data-batch-summary]').textContent=`已选 ${selected.length} 件 · 器源精粹×${gain}`;return{selected,gain}};
    root.querySelector('[data-eq-close]').onclick=closeModal;
    root.querySelector('.equipment-modal-backdrop-bequipment01').onclick=e=>{if(e.target===e.currentTarget)closeModal()};
    boxes().forEach(box=>box.addEventListener('change',update));
    root.querySelector('[data-batch-low]').onclick=()=>{boxes().forEach(box=>{const item=candidates.find(x=>String(x.id)===box.dataset.batchId);box.checked=['yellow','mystic'].includes(item?.grade_code)});update()};
    root.querySelector('[data-batch-clear]').onclick=()=>{boxes().forEach(box=>box.checked=false);update()};
    root.querySelector('[data-batch-confirm]').onclick=()=>{const{selected,gain}=update();if(!selected.length){toast('请至少选择一件装备。','error');return}const hasHigh=selected.some(item=>['earth','heaven','immortal'].includes(item.grade_code));const warning=hasHigh?'所选装备包含地品或更高品级。':'';if(!confirm(`${warning}确认分解 ${selected.length} 件装备，获得器源精粹×${gain}？操作不可撤销。`))return;closeModal();action('decompose_equipment_bequipment01',{p_item_ids:selected.map(item=>item.id)},`分解完成，获得器源精粹×${gain}。`)};
    update();
  }
  function openMaterial(loc){const qty=Number(state.data?.materials?.[loc==='backpack'?'essence_backpack':'essence_cave']||0);modalHost().innerHTML=`<div class="modal-backdrop equipment-modal-backdrop-bequipment01"><section class="modal equipment-modal-bequipment01"><button class="modal-close-button" data-eq-close>×</button><header><span class="equipment-icon-bequipment01">粹</span><div><span>装备分解材料</span><h3>器源精粹 ×${qty.toLocaleString()}</h3></div></header><p>从废弃法器与防具中提炼出的器物本源，预留用于后续装备开孔。</p><div class="equipment-modal-actions-bequipment01"><button class="primary-btn" data-move-material>${loc==='backpack'?'存入洞府':'取回背包'}</button></div></section></div>`;const root=modalHost();root.querySelector('[data-eq-close]').onclick=closeModal;root.querySelector('[data-move-material]').onclick=()=>{const raw=prompt(`输入转移数量（1—${qty}）`,String(qty));const n=Math.floor(Number(raw));if(!Number.isFinite(n)||n<1||n>qty)return;closeModal();action('move_equipment_essence_bequipment01',{p_target_location:loc==='backpack'?'cave':'backpack',p_quantity:n},'器源精粹已转移。')}}
  function renderAll(){document.getElementById('equipmentStorageShellBEquipment01')?.remove();document.getElementById('equipmentBackpackLauncherBEquipment01')?.remove();renderSpiritSlots();renderBackpackInline();renderCaveEquipmentIntoNative()}
  function hasEquipmentSurface(){return Boolean(document.getElementById('caveStorageB01')||document.getElementById('primordialSpiritRootV1'))}
  function refreshOrRender({force=false}={}){
    if(state.data){renderAll();if(force||Date.now()-state.lastFetch>60000)refresh(force);return}
    if(hasEquipmentSurface())refresh(force)
  }
  function opportunityEquipment(payload){
    const direct=payload?.opportunity?.last_result?.equipment;
    if(direct?.awarded)return direct;
    const rows=payload?.offline_summary?.net_result?.equipment;
    if(Array.isArray(rows))return rows.find(x=>x?.awarded)||null;
    return rows?.awarded?rows:null
  }
  window.addEventListener('jiuxiao:cave-rendered',()=>refreshOrRender());
  window.addEventListener('jiuxiao:primordial-rendered',()=>refreshOrRender());
  window.addEventListener('jiuxiao:opportunity-settled',event=>{
    const payload=event?.detail||null;const equipment=opportunityEquipment(payload);
    const itemId=equipment?.item?.id||equipment?.item_id||null;
    if(equipment?.awarded&&itemId!==state.lastOpportunityId){state.lastOpportunityId=itemId;toast(`机缘得宝：${equipment.item?.short_name||'装备'}·${equipment.item?.grade_name||''}`)}
    if(Number(payload?.events_resolved||0)>0||equipment?.awarded)refresh(true)
  });
  document.addEventListener('DOMContentLoaded',()=>refreshOrRender({force:true}));
  window.addEventListener('focus',()=>{if(hasEquipmentSurface()&&Date.now()-state.lastFetch>60000)refresh(true)});
  window.addEventListener('pageshow',event=>{if(event.persisted)refreshOrRender({force:true})});
  window.B_EQUIPMENT01={refresh,render:renderAll,openBackpack,version:'1.7.5'};
})();
