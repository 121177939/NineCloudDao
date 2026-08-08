(() => {
  'use strict';
  const MODULE='B-EQUIPMENT-V210';
  const config=window.GAME_CONFIG||{};
  const baseUrl=String(config.supabaseUrl||'').replace(/\/+$/,'');
  const apiKey=String(config.supabasePublishableKey||'');
  const projectRef=(()=>{try{return new URL(baseUrl).hostname.split('.')[0]}catch{return'unknown'}})();
  const sessionKey=`nine_cloud_dao_session_${projectRef}_v1`,deviceKey=`nine_cloud_dao_device_${projectRef}_v1`;
  const state={overview:null,item:null,busy:false,dirty:false,status:'',serverItem:null};
  const esc=v=>String(v??'').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#039;');
  const fmt=v=>Number(v||0).toLocaleString('zh-CN',{maximumFractionDigits:2});
  const pct=v=>`${fmt(Number(v||0)*100)}%`;
  const uuid=()=>crypto?.randomUUID?.()||'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g,c=>{const v=Math.random()*16|0;return(c==='x'?v:(v&3|8)).toString(16)});
  const session=()=>{try{return JSON.parse(localStorage.getItem(sessionKey)||'null')}catch{return null}};
  function toast(msg,type='success'){const e=document.getElementById('toast');if(!e)return;e.textContent=msg;e.className=`toast show ${type}`;clearTimeout(toast.t);toast.t=setTimeout(()=>e.className='toast',3200)}
  function setStatus(msg='',type=''){state.status=String(msg||'');const e=host().querySelector?.('[data-forge-status]');if(!e)return;e.textContent=state.status;e.className=`forge-status-v210${type?` ${type}`:''}`;e.hidden=!state.status}
  function errorText(error){const raw=String(error?.message||error||'装备淬炼失败');const map=[
    ['EQUIPMENT_V210_LOCK_LIMIT_EXCEEDED','最多锁定3个孔位。'],['EQUIPMENT_V210_NO_UNLOCKED_FILLED_SOCKET','没有可进行百炼的未锁孔位。'],['EQUIPMENT_V210_EMPTY_SOCKET_CANNOT_LOCK','空孔不能锁定。'],['EQUIPMENT_V210_ALL_SOCKETS_LOCKED','没有可刷新的未锁孔位。'],['EQUIPMENT_V210_SPIRIT_STONE_INSUFFICIENT','灵石不足，无法进行本次孔位操作。'],['EQUIPMENT_V210_ITEM_INSUFFICIENT','对应材料不足。'],['EQUIPMENT_V210_REROLL_NO_EFFECT_ROLLBACK','当前配置无法产生新的孔位结果，本次未扣除任何材料或灵石。'],['EQUIPMENT_V210_LEVEL_REROLL_NO_CHANGE_ROLLBACK','当前等级池无法产生新等级，本次百炼未扣除任何材料或灵石。'],['EQUIPMENT_V210_LEVEL_REROLL_DISABLED','百炼玄铁等级刷新当前已关闭。'],['EQUIPMENT_V210_BACKPACK_ONLY','只有背包中的装备可以进行该操作。'],['EQUIPMENT_V210_LOCKED','锁定装备不能淬炼，请先解锁。'],['EQUIPMENT_V210_GRADE_MAX','该装备已是仙品。'],['EQUIPMENT_V210_REALM_EXCEEDS_CHARACTER','装备境界不能超过角色当前大境界。'],['EQUIPMENT_V210_NEXT_REALM_TEMPLATE_MISSING','没有找到下一大境界对应装备模板。'],['EQUIPMENT_V210_SOUL_INCOMPATIBLE','器魂只能承接到同大境界、同品级、同部位装备。'],['EQUIPMENT_V210_SOUL_TARGET_SOCKETS_INSUFFICIENT','目标装备当前开放孔位不足，无法承接该器魂。'],['EQUIPMENT_V210_SOUL_NOT_FOUND','器魂不存在或已被使用。'],['EQUIPMENT_ESSENCE_INSUFFICIENT','器源不足。'],['EQUIPMENT_ITEM_NOT_FOUND','装备不存在或已被销毁。'],['PGRST202','V2.1.1装备RPC尚未部署。'],['Could not find the function','V2.1.1装备RPC尚未部署。']
  ];return(map.find(([k])=>raw.includes(k))||[])[1]||raw}
  async function rpc(name,body={}){const s=session();if(!s?.access_token)throw new Error('AUTH_REQUIRED');const res=await fetch(`${baseUrl}/rest/v1/rpc/${name}`,{method:'POST',headers:{apikey:apiKey,Authorization:`Bearer ${s.access_token}`,'Content-Type':'application/json','X-Game-Session-Id':localStorage.getItem(deviceKey)||''},body:JSON.stringify(body)});const text=await res.text();let data=null;try{data=text?JSON.parse(text):null}catch{data=text}if(!res.ok)throw new Error(data?.message||data?.error||`HTTP ${res.status}`);return Array.isArray(data)?data[0]||null:data}
  function host(){return document.getElementById('modalRoot')||document.body}
  function close(){host().innerHTML='';document.body.classList.remove('modal-open');if(state.dirty){state.dirty=false;Promise.resolve(window.B_EQUIPMENT01?.refresh?.(true)).catch(()=>{})}}
  async function overview(){const [data,stones]=await Promise.all([rpc('get_equipment_forge_overview_v210',{}),rpc('get_spirit_stone_balance_v0141',{}).catch(()=>null)]);state.overview=data||{};const raw=Array.isArray(stones)?stones[0]:stones;if(raw!==null&&raw!==undefined&&Number.isFinite(Number(raw)))state.overview.spirit_stones=Math.max(0,Number(raw));return state.overview}
  async function serverItemState(id){const row=await rpc('get_equipment_forge_item_state_v247',{p_item_id:id});state.serverItem=row||null;return row||null}
  async function freshItem(item){
    const id=item?.id;if(!id)throw new Error('EQUIPMENT_ITEM_NOT_FOUND');
    await window.B_EQUIPMENT01?.refresh?.(true);
    const fresh=window.B_EQUIPMENT01?.getItem?.(id)||item;
    const server=await serverItemState(id);
    return {...fresh,...(server||{})};
  }
  async function requireBackpackCurrent(item){
    const current=await freshItem(item);state.item=current;
    if(current.location!=='backpack')throw new Error('EQUIPMENT_V210_BACKPACK_ONLY');
    if(current.is_locked)throw new Error('EQUIPMENT_V210_LOCKED');
    return current;
  }
  function material(code){return Number(state.overview?.materials?.[code]||0)}
  function stoneBalance(){return Math.max(0,Number(state.overview?.spirit_stones||0))}
  function stoneCost(item,level=false){const sc=state.overview?.socket_settings||{};if(level)return Math.max(0,Number(sc.level_reroll_spirit_stone_cost??200000));return Math.max(0,Number((item?.slot_code==='weapon'?sc.weapon_reroll_spirit_stone_cost:sc.armor_reroll_spirit_stone_cost)??200000))}
  function forgeItem(id){return (state.overview?.items||[]).find(x=>String(x.id)===String(id))||{id,sockets:[],socket_content_count:0}}
  function levelRow(level){return (state.overview?.level_config||[]).find(x=>Number(x.level)===Number(level))||{}}
  const circledSocketNumbers=['①','②','③','④','⑤','⑥','⑦','⑧'];
  function detailSocketText(item,s){
    const r=levelRow(s.level),label=String(s.label||s.attribute_code||'属性').replace('+数值','').replace('+%','');
    if(['attack_flat','defense_flat','vitality_flat','agility_flat'].includes(s.attribute_code)){
      const value=Math.round(Number(item?.base_main_stat_value||0)*Number(r.fixed_main_ratio||s.value||0));
      return `${label} +${value.toLocaleString('zh-CN')}`;
    }
    const value=Number(s.value_percent??(Number(s.value||0)*100)??0);
    return `${label} +${fmt(value)}%`;
  }
  async function detailRows(item){
    if(!state.overview)await overview();
    const fi=forgeItem(item.id);
    const open=Math.min(8,Math.max(0,Number(item.opened_sockets??item.total_socket_capacity??item.socket_capacity??0)));
    const map=new Map((fi.sockets||[]).map(s=>[Number(s.socket_index),s]));
    return Array.from({length:open},(_,i)=>{const index=i+1,s=map.get(index);return s?{index,symbol:circledSocketNumbers[i]||String(index),empty:false,level:Number(s.level||1),text:detailSocketText(item,s)}:{index,symbol:circledSocketNumbers[i]||String(index),empty:true,level:null,text:'空'};});
  }
  function gradeNext(code){return({yellow:'玄品',mystic:'地品',earth:'天品',heaven:'仙品'}[code]||'已满品')}
  function rerollMeta(item){
    const sc=state.overview?.socket_settings||{};
    const weapon=item.slot_code==='weapon';
    return {
      code:weapon?'weapon_soul_jade':'guardian_spirit_jade',
      short:weapon?'兵魄':'护道',
      full:weapon?'兵魄道玉':'护道灵玉',
      rerollCost:Number(sc.reroll_item_cost||1),
      levelCost:Number(sc.level_item_cost||1),
      lockCost:Number(sc.lock_item_cost_per_socket||1),
      levelEnabled:sc.level_reroll_enabled!==false
    };
  }
  function materialRows(item){const m=rerollMeta(item);return `<span><em>${m.short}</em><b>${fmt(material(m.code))}</b></span><i>·</i><span><em>百炼</em><b>${fmt(material('hundred_refine_crystal'))}</b></span><i>·</i><span><em>锁玉</em><b>${fmt(material('equipment_socket_lock_jade_v210'))}</b></span><i>·</i><span><em>灵石</em><b>${fmt(stoneBalance())}</b></span><i>·</i><span><em>升品</em><b>${fmt(material('equipment_grade_ascension_jade_v210'))}</b></span><i>·</i><span><em>破境</em><b>${fmt(material('equipment_realm_breakthrough_stone_v210'))}</b></span>`}
  function socketRows(item,fi){
    const open=Math.min(8,Math.max(0,Number(item.opened_sockets??item.total_socket_capacity??item.socket_capacity??0)));
    const map=new Map((fi.sockets||[]).map(s=>[Number(s.socket_index),s]));
    return Array.from({length:open},(_,i)=>{
      const n=i+1,s=map.get(n),symbol=circledSocketNumbers[i]||String(n);
      if(!s)return `<label class="forge-socket-line-v210 empty"><input type="checkbox" disabled aria-label="${symbol} 空孔不可锁定"><span class="forge-socket-symbol-v210">${symbol}</span><strong>空</strong></label>`;
      const level=Number(s.level||1),max=level===10?' max':'';
      return `<label class="forge-socket-line-v210${max}"><input type="checkbox" data-forge-lock="${n}" aria-label="锁定${symbol}"><span class="forge-socket-symbol-v210">${symbol}</span><strong>${esc(detailSocketText(item,s))} <small>（LV.${level}）</small></strong></label>`;
    }).join('');
  }
  function soulRows(item){const souls=(state.overview?.souls||[]).filter(s=>Number(s.source_major_order)===Number(item.major_order)&&s.source_grade_code===item.grade_code&&s.source_slot_code===item.slot_code);if(!souls.length)return '<div class="forge-empty-v210">当前没有可用于这件装备的器魂。</div>';return souls.map(s=>{const cost=(state.overview?.soul_costs||[]).find(x=>Number(x.socket_count)===Number(s.socket_count))?.essence_cost??0;return `<article class="forge-soul-v210"><div><strong>${Number(s.socket_count)}孔器魂</strong><small>同境界 · 同品级 · 同部位 · ${new Date(s.created_at).toLocaleString('zh-CN')}</small></div><button type="button" data-forge-soul="${esc(s.id)}">器源×${fmt(cost)} 承接</button></article>`}).join('')}
  function selectedLocks(root=host()){return Array.from(root.querySelectorAll('[data-forge-lock]:checked')).map(x=>Number(x.dataset.forgeLock)).filter((v,i,a)=>v>=1&&v<=8&&a.indexOf(v)===i)}
  function validateLocks(item,level=false){if(item.location!=='backpack'){const msg='穿戴中的装备不能洗炼，请先卸下放回背包。';setStatus(msg,'error');toast(msg,'error');return null}const locks=selectedLocks(),m=rerollMeta(item);if(locks.length>3){setStatus('最多锁定3个孔位。','error');toast('最多锁定3个孔位。','error');return null}const need=locks.length*m.lockCost;if(need>material('equipment_socket_lock_jade_v210')){const msg=`定灵锁玉不足：需要${need}枚。`;setStatus(msg,'error');toast(msg,'error');return null}const itemNeed=level?m.levelCost:m.rerollCost,itemCode=level?'hundred_refine_crystal':m.code,itemName=level?'百炼玄铁':m.full;if(itemNeed>material(itemCode)){const msg=`${itemName}不足：需要${itemNeed}个。`;setStatus(msg,'error');toast(msg,'error');return null}const stones=stoneCost(item,level);if(stones>stoneBalance()){const msg=`灵石不足：本次需要${fmt(stones)}灵石，当前${fmt(stoneBalance())}。`;setStatus(msg,'error');toast(msg,'error');return null}return locks}
  function setSocketButtons(item){const root=host(),m=rerollMeta(item),locked=Boolean(item.is_locked),inBag=item.location==='backpack';const attr=root.querySelector('[data-forge-reroll]'),level=root.querySelector('[data-forge-level-all]');if(attr){attr.textContent=`使用${m.short}×${m.rerollCost} + 灵石${fmt(stoneCost(item,false))}`;attr.disabled=state.busy||!inBag||locked;attr.title=!inBag?'穿戴中的装备不能洗炼，请先卸下放回背包。':''}if(level){level.textContent=`使用百炼×${m.levelCost} + 灵石${fmt(stoneCost(item,true))}`;level.disabled=state.busy||!inBag||locked||!m.levelEnabled;level.title=!inBag?'穿戴中的装备不能洗炼，请先卸下放回背包。':(m.levelEnabled?'':'百炼玄铁等级刷新当前已关闭')}}
  function updateDynamic(item,keepLocks=[]){const root=host(),fi=forgeItem(item.id);const materials=root.querySelector('[data-forge-materials]'),sockets=root.querySelector('[data-forge-sockets]');if(materials)materials.innerHTML=materialRows(item);if(sockets)sockets.innerHTML=socketRows(item,fi);for(const n of keepLocks){const input=root.querySelector(`[data-forge-lock="${n}"]`);if(input)input.checked=true}setSocketButtons(item)}
  function rulesPanel(){return `<div class="forge-rules-backdrop-v210" data-forge-rules-panel hidden><section class="forge-rules-card-v210" role="dialog" aria-modal="true" aria-label="孔位属性规则"><button type="button" class="forge-rules-close-v210" data-forge-rules-close>×</button><h4>孔位属性规则</h4><p>最多锁定3个已有属性孔位。锁定后，该孔的属性类型与LV都保持不变。</p><p>每次使用兵魄/护道或百炼时，锁1/2/3孔分别额外消耗对应数量的定灵锁玉。</p><p>兵魄/护道：所有未锁孔同时重新随机属性类型与LV；锁定孔的属性与LV都保持不变。</p><p>百炼：属性类型不变，一次随机重炼全部未锁且已有属性孔的LV；有其它等级可选时不会原样洗回当前LV，空孔不参与。</p><p>兵魄道玉、护道灵玉、百炼玄铁每次还会按GM配置额外消耗灵石；默认均为20万。若整次无法产生实际变化，服务端会回滚且不扣任何消耗。</p><p>穿戴中的装备禁止洗炼；请先卸下放回背包后再使用兵魄、护道或百炼。</p></section></div>`}
  async function render(item){
    state.item=item;await overview();
    const fi=forgeItem(item.id),up=state.overview?.upgrade_settings||{},m=rerollMeta(item),locked=Boolean(item.is_locked),inBag=item.location==='backpack';
    host().innerHTML=`<div class="forge-backdrop-v210"><section class="forge-modal-v210" role="dialog" aria-modal="true"><button class="forge-close-v210" type="button" data-forge-close>×</button><header><small>V2.1.1 CACHE118 · 装备孔位/升品/破境</small><h3>${esc(item.full_name||item.short_name||'装备')} ${Number(item.enhancement_level||0)>0?`+${Number(item.enhancement_level)}`:''}</h3><p>${esc(item.realm_name||'')} · ${esc(item.grade_name||item.grade_code||'')} · 当前开放${Math.min(8,Number(item.opened_sockets??item.total_socket_capacity??0))}孔</p></header><div class="forge-materials-v210" data-forge-materials>${materialRows(item)}</div><div class="forge-status-v210" data-forge-status hidden aria-live="polite"></div>${(!inBag||locked)?`<div class="forge-warning-v210">${locked?'装备已锁定，请先解锁。':'穿戴中的装备不能洗炼；请先卸下放回背包后再进行孔位洗炼、百炼、升品、破境或器魂承接。'}</div>`:''}<section class="forge-section-v210 forge-socket-section-v210"><header><button class="forge-section-title-v210" type="button" data-forge-rules-open>孔位属性 <span>?</span></button></header><div class="forge-sockets-v210" data-forge-sockets>${socketRows(item,fi)}</div><div class="forge-actions-v210"><button class="forge-primary-v210" type="button" data-forge-reroll ${!inBag||locked?'disabled':''}>使用${m.short}×${m.rerollCost} + 灵石${fmt(stoneCost(item,false))}</button><button class="forge-primary-v210 forge-secondary-v210" type="button" data-forge-level-all ${!inBag||locked||!m.levelEnabled?'disabled':''}>使用百炼×${m.levelCost} + 灵石${fmt(stoneCost(item,true))}</button></div></section><section class="forge-section-v210"><header><strong>装备跃迁</strong><small>每次固定消耗1个；失败仅消耗材料，装备不变。</small></header><div class="forge-upgrade-grid-v210"><button type="button" data-forge-grade ${!inBag||locked||item.grade_code==='immortal'?'disabled':''}><b>升品</b><span>${esc(item.grade_name||item.grade_code)} → ${gradeNext(item.grade_code)}</span><small>造化升品玉×${Number(up.grade_item_cost||1)} · ${pct(up.grade_success_rate??.3)}</small></button><button type="button" data-forge-realm ${!inBag||locked?'disabled':''}><b>破境</b><span>${esc(item.realm_name||'当前境界')} → 下一大境界</span><small>乾坤破境石×${Number(up.realm_item_cost||1)} · ${pct(up.realm_success_rate??.3)}</small></button></div></section><section class="forge-section-v210"><header><strong>器魂承接</strong><small>强化失败时孔位灵性凝成器魂；只能同大境界、同品级、同部位整套覆盖承接。</small></header><div class="forge-souls-v210">${soulRows(item)}</div></section>${rulesPanel()}</section></div>`;
    document.body.classList.add('modal-open');bind(item);setSocketButtons(item)
  }
  function openRules(){const p=host().querySelector('[data-forge-rules-panel]');if(p)p.hidden=false}
  function closeRules(){const p=host().querySelector('[data-forge-rules-panel]');if(p)p.hidden=true}
  function bind(item){
    const root=host();
    root.querySelector('[data-forge-close]')?.addEventListener('click',close);
    root.querySelector('.forge-backdrop-v210')?.addEventListener('click',e=>{if(e.target===e.currentTarget)close()});
    root.addEventListener('change',e=>{const t=e.target;if(!t?.matches?.('[data-forge-lock]'))return;if(t.checked&&selectedLocks(root).length>3){t.checked=false;toast('最多锁定3个孔位。','error')}});
    root.addEventListener('click',e=>{
      const t=e.target.closest?.('button');if(!t)return;
      if(t.matches('[data-forge-rules-open]')){openRules();return}
      if(t.matches('[data-forge-rules-close]')){closeRules();return}
      if(t.matches('[data-forge-reroll]')){const locks=validateLocks(item,false);if(!locks)return;runSocket('reroll_equipment_socket_attributes_v210',{p_item_id:item.id,p_locked_positions:locks,p_request_id:uuid()},`孔位属性与等级已刷新${locks.length?`，已保护${locks.length}孔。`:''}`,locks);return}
      if(t.matches('[data-forge-level-all]')){const locks=validateLocks(item,true);if(!locks)return;runSocket('reroll_equipment_socket_levels_v210',{p_item_id:item.id,p_locked_positions:locks,p_request_id:uuid()},`孔位等级已重炼${locks.length?`，已保护${locks.length}孔。`:''}`,locks);return}
      if(t.matches('[data-forge-grade]')){const up=state.overview?.upgrade_settings||{};if(confirm(`消耗造化升品玉×${Number(up.grade_item_cost||1)}尝试升品？当前成功率${pct(up.grade_success_rate??.3)}，失败只消耗道具，装备不变。`))run('upgrade_equipment_grade_v210',{p_item_id:item.id,p_request_id:uuid()},null,true);return}
      if(t.matches('[data-forge-realm]')){const up=state.overview?.upgrade_settings||{};if(confirm(`消耗乾坤破境石×${Number(up.realm_item_cost||1)}尝试提升装备大境界？当前成功率${pct(up.realm_success_rate??.3)}，失败只消耗道具，装备不变。`))run('upgrade_equipment_realm_v210',{p_item_id:item.id,p_request_id:uuid()},null,true);return}
      if(t.matches('[data-forge-soul]')){if(confirm('器魂承接会清空目标装备现有孔位属性并整套覆盖，确认继续？'))run('inherit_equipment_socket_soul_v210',{p_soul_id:t.dataset.forgeSoul,p_target_item_id:item.id,p_request_id:uuid()},'器魂已完成承接。');return}
    });
    root.querySelector('[data-forge-rules-panel]')?.addEventListener('click',e=>{if(e.target===e.currentTarget)closeRules()});
  }
  async function runSocket(name,body,message,keepLocks){
    if(state.busy)return;state.busy=true;setSocketButtons(state.item);setStatus('正在提交孔位操作，请勿重复点击…','working');
    try{
      await requireBackpackCurrent(state.item);
      const result=await rpc(name,body);
      state.dirty=true;
      await overview();
      const fresh=await freshItem(state.item);
      state.item=fresh;
      updateDynamic(fresh,keepLocks);
      const suffix=Number(result?.spirit_stone_cost||0)>0?` · 已消耗${fmt(result.spirit_stone_cost)}灵石`:'';
      const ok=(message||'操作完成。')+suffix;setStatus(ok,'ok');toast(ok);
      window.dispatchEvent(new CustomEvent('jiuxiao:equipment-forge-updated',{detail:result||{}}));
    }catch(e){const msg=errorText(e);setStatus(msg,'error');toast(msg,'error');try{state.item=await freshItem(state.item)}catch{}}
    finally{state.busy=false;setSocketButtons(state.item)}
  }
  async function run(name,body,message,upgrade=false){if(state.busy)return;state.busy=true;try{await requireBackpackCurrent(state.item);const result=await rpc(name,body);state.dirty=true;if(upgrade){toast(result?.upgrade_success?'天命应允，装备跃迁成功！':'天命未应，道具已消耗，装备保持不变。',result?.upgrade_success?'success':'error')}else toast(message||'操作完成。');const fresh=await freshItem(state.item);await render(fresh)}catch(e){toast(errorText(e),'error');try{state.item=await freshItem(state.item)}catch{}}finally{state.busy=false}}
  async function open(item){try{const fresh=await freshItem(item);await render(fresh)}catch(e){toast(errorText(e),'error')}}
  window.B_EQUIPMENT_V210=Object.freeze({module:MODULE,version:'2.1.1-cache118',open,refresh:overview,detailRows});
})();
