(() => {
  'use strict';
  const MODULE = 'B-TECHNIQUE-V220-CACHE126-TIANXU';
  const config = window.GAME_CONFIG || {};
  const baseUrl = String(config.supabaseUrl || '').replace(/\/+$/, '');
  const apiKey = String(config.supabasePublishableKey || '');
  const projectRef = (() => { try { return new URL(baseUrl).hostname.split('.')[0]; } catch { return 'unknown'; } })();
  const sessionKey = `nine_cloud_dao_session_${projectRef}_v1`;
  const deviceKey = `nine_cloud_dao_device_${projectRef}_v1`;
  const state = { data: null, loading: false, bound: null, tab: 'cultivation', modalCode: '' };
  const gradeNames = { yellow: '黄品', mystic: '玄品', earth: '地品', heaven: '天品', immortal: '仙品' };
  const esc = v => String(v ?? '').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#039;');
  const num = v => Number.isFinite(Number(v)) ? Number(v) : 0;
  const pct = (v, d=2) => `${(num(v)*100).toLocaleString('zh-CN',{maximumFractionDigits:d})}%`;
  const fmt = v => Math.floor(num(v)).toLocaleString('zh-CN');
  const uuid = () => globalThis.crypto?.randomUUID?.() || 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g,c=>{const v=Math.random()*16|0;return(c==='x'?v:(v&3|8)).toString(16);});
  function session(){ try{return JSON.parse(localStorage.getItem(sessionKey)||'null');}catch{return null;} }
  function toast(message,type='success'){const el=document.getElementById('toast');if(!el)return;el.textContent=message;el.className=`toast show ${type}`;clearTimeout(toast.timer);toast.timer=setTimeout(()=>{el.className='toast';},3600);}
  async function rpc(name, body={}){
    const s=session(); if(!s?.access_token) throw new Error('请先登录。');
    const r=await fetch(`${baseUrl}/rest/v1/rpc/${name}`,{method:'POST',headers:{apikey:apiKey,Authorization:`Bearer ${s.access_token}`,'Content-Type':'application/json','X-Game-Session-Id':localStorage.getItem(deviceKey)||''},body:JSON.stringify(body)});
    const text=await r.text();let data=null;try{data=text?JSON.parse(text):null;}catch{data=text;}
    if(!r.ok) throw new Error(data?.message||data?.error||`HTTP ${r.status}`);return Array.isArray(data)?(data[0]||null):data;
  }
  function humanEffects(row, params=row.current_effects||{}){
    const p=params||{}, code=row.effect_code; const a=[];
    if(code==='ATK_FINAL_DAMAGE') a.push(`最终伤害 +${pct(p.damage_bonus)}`);
    if(code==='ATK_HIT') a.push(`命中 +${pct(p.hit_bonus)}`,`最终伤害 +${pct(p.damage_bonus)}`);
    if(code==='ATK_DEFENSE_PEN') a.push(`相对削弱目标道御减伤 ${pct(p.defense_penetration)}`);
    if(code==='ATK_OPENING_BURST') a.push(`前${fmt(p.opening_rounds)}回合伤害 +${pct(p.opening_damage_bonus)}`,`之后伤害 +${pct(p.later_damage_bonus)}`);
    if(code==='ATK_ANTI_EVASION') a.push(`命中 +${pct(p.hit_bonus)}`,`目标闪避≥${pct(p.high_evasion_threshold)}时伤害 +${pct(p.high_evasion_damage_bonus)}`);
    if(code==='ATK_ANTI_DEFENSE') a.push(`目标减伤≥${pct(p.high_defense_threshold)}时伤害 +${pct(p.high_defense_damage_bonus)}`,`否则伤害 +${pct(p.normal_damage_bonus)}`);
    if(code==='ATK_ELEMENT_ADVANTAGE') a.push(`五行攻势摆幅强化 ${pct(p.element_swing_amplify)}`);
    if(code==='ATK_EXECUTE') a.push(`目标生机≤${pct(p.hp_threshold)}时伤害 +${pct(p.damage_bonus)}`);
    if(code==='ATK_ROUND_STACK') a.push(`首回合0层；每完整回合每层伤害 +${pct(p.per_stack_damage_bonus)}`,`最多 ${fmt(p.max_stacks)} 层`);
    if(code==='DEF_REDUCTION') a.push(`护体减伤 ${pct(p.reduction)}`);
    if(code==='DEF_EVASION') a.push(`闪避 +${pct(p.evasion_bonus)}（最终命中仍受5%—98%边界）`);
    if(code==='DEF_ELEMENT_RESIST') a.push(`五行抗性 +${pct(p.element_resistance)}`);
    if(code==='DEF_STEADFAST') a.push(`常驻减伤 ${pct(p.reduction)}`,`生机≥${pct(p.high_hp_threshold)}时额外减伤 ${pct(p.high_hp_extra_reduction)}`);
    if(code==='DEF_LOW_HP_RECOVERY') a.push(`残血减伤 ${pct(p.low_hp_reduction)}`,`每场首次存活跌入≤${pct(p.hp_threshold)}时回元 ${pct(p.heal_ratio)}最大生机`);
    if(code==='DEF_OPENING_REDUCTION') a.push(`前${fmt(p.opening_rounds)}回合减伤 ${pct(p.opening_reduction)}`,`之后减伤 ${pct(p.later_reduction)}`);
    if(code==='DEF_ATTACK_TECH_SUPPRESS') a.push(`削弱敌方攻伐功法额外增伤 ${pct(p.attack_tech_suppression)}`,`自身减伤 ${pct(p.reduction)}`);
    if(code==='DEF_ALL_SUPPRESS') a.push(`削弱五行优势 ${pct(p.element_advantage_suppression)}`,`削弱敌方攻伐增伤 ${pct(p.attack_tech_suppression)}`,`自身减伤 ${pct(p.reduction)}`);
    if(code==='DEF_LETHAL_GUARD') a.push(`常驻减伤 ${pct(p.reduction)}`, row.is_mastered ? '圆满：每场首次致命伤保留1点生机' : '圆满后解锁：每场首次致命伤保留1点生机');
    return a.length?a:['服务端效果参数已读取'];
  }
  function poolShare(row){
    const d=state.data||{},s=d.settings||{}; if(row?.enabled===false)return 0;
    const aw=num(s.opportunity_attack_weight??50),dw=num(s.opportunity_defense_weight??50),total=Math.max(1,aw+dw);
    const familyWeight=row.family==='attack'?aw:dw;
    const same=(d.techniques||[]).filter(x=>x.enabled!==false&&x.grade_code===row.grade_code&&x.family===row.family&&num(x.pool_weight)>0);
    const familyPool=same.reduce((n,x)=>n+num(x.pool_weight),0);
    return familyPool>0?(familyWeight/total)*(num(row.pool_weight)/familyPool):0;
  }
  function opportunityPoolRate(row){const d=state.data||{},s=d.settings||{},direct=Number(d.opportunity_shard_rates?.[row.grade_code]);if(Number.isFinite(direct))return direct;if(row.grade_code==='yellow')return num(s.opportunity_yellow_shard_rate??.05);const base=Number(d.ordinary_drop_rates?.[row.grade_code]);return Number.isFinite(base)?base*num(s.opportunity_relative_rate??.2):0;}
  function rateFor(row){return opportunityPoolRate(row)*poolShare(row);}
  function secretRate(row){const s=state.data?.settings||{};return row.grade_code==='mystic'?num(s.secret_mystic_rate):row.grade_code==='earth'?num(s.secret_earth_rate):row.grade_code==='heaven'?num(s.secret_heaven_rate):row.grade_code==='immortal'?num(s.secret_immortal_rate):0;}
  function secretSpecifiedRate(row){return secretRate(row)*poolShare(row);}
  function bossSpecifiedRate(row,difficulty='normal'){
    const s=state.data?.settings||{};let pool=0;if(row.grade_code==='heaven')pool=difficulty==='hard'?num(s.boss_hard_heaven_rate):num(s.boss_normal_heaven_rate);else if(row.grade_code==='immortal'&&difficulty==='hard')pool=num(s.boss_hard_immortal_rate);return pool*poolShare(row);
  }
  function card(row){
    const ready=num(row.shards)>=num(state.data?.settings?.shard_combine_count||10); const progress=Math.min(100,num(row.shards)/Math.max(1,num(state.data?.settings?.shard_combine_count||10))*100);
    return `<button class="technique-dao-slot-v220 grade-${esc(row.grade_code)} ${row.learned?'learned':''} ${ready?'ready':''} ${row.enabled===false?'disabled':''}" type="button" data-v220-tech-code="${esc(row.code)}">
      <span class="technique-dao-grade-v220">${esc(gradeNames[row.grade_code]||row.grade_code)}</span><strong>${esc(row.name)}</strong><em>${esc(row.role_name)}</em>
      ${row.learned?`<small>${row.is_mastered?'圆满':`第 ${fmt(row.level)} / ${fmt(row.max_level)} 层`}</small>`:`<small>残卷 ${fmt(row.shards)} / ${fmt(state.data?.settings?.shard_combine_count||10)}</small>`}
      <i class="technique-dao-progress-v220"><b style="width:${progress.toFixed(1)}%"></b></i>
      ${row.enabled===false?'<span class="technique-dao-ready-v220">已停用</span>':row.equipped?'<span class="technique-dao-equipped-v220">运转中</span>':ready&&!row.learned?'<span class="technique-dao-ready-v220">可合卷</span>':''}
    </button>`;
  }
  function pane(family){
    const rows=(state.data?.techniques||[]).filter(x=>x.family===family); const eq=rows.find(x=>x.equipped); const learned=rows.filter(x=>x.learned).length;
    return `<div class="combat-technique-pane-v220">
      <section class="combat-technique-equipped-v220"><span>当前${family==='attack'?'攻伐':'护体'}</span>${eq?`<strong>${esc(eq.name)}</strong><small>${esc(gradeNames[eq.grade_code])} · ${eq.is_mastered?'圆满':`第${fmt(eq.level)}层`} · ${humanEffects(eq).map(esc).join(' · ')}</small><button type="button" data-v220-unequip="${family}">卸下</button>`:`<strong>尚未运转</strong><small>参悟后可从下方格子选择一门运转。</small>`}</section>
      <div class="combat-technique-heading-v220"><div><strong>${family==='attack'?'攻伐道藏':'护体道藏'}</strong><small>已参悟 ${learned} / 10 · 同名${fmt(state.data?.settings?.shard_combine_count||10)}残卷合一整卷</small></div><span>秘境风险残卷 ${fmt(state.data?.pending_secret_shards||0)}</span></div>
      <div class="technique-dao-grid-v220">${rows.map(card).join('')}</div>
    </div>`;
  }
  function render(){
    const root=document.getElementById('combatTechniqueRootV220'); if(!root)return;
    const combatTab=state.tab==='attack'||state.tab==='defense';
    root.hidden=!combatTab;
    root.style.display=combatTab?'':'none';
    if(!combatTab){root.innerHTML='';return;}
    root.innerHTML=state.loading?'<div class="empty-state">正在查阅攻防道藏……</div>':!state.data?'<div class="empty-state">SQL254尚未部署，攻伐/护体功法暂不可用。</div>':pane(state.tab);
    bindRoot(root);
  }
  function tabSwitch(tab){
    if(!['cultivation','attack','defense'].includes(tab))tab='cultivation';
    state.tab=tab;
    document.querySelectorAll('[data-v220-tech-tab]').forEach(b=>{const active=b.dataset.v220TechTab===tab;b.classList.toggle('active',active);b.setAttribute('aria-selected',active?'true':'false');});
    document.querySelectorAll('[data-v220-cultivation-pane]').forEach(el=>{const visible=tab==='cultivation';el.hidden=!visible;el.style.display=visible?'':'none';});
    render();
  }
  async function refresh(){if(state.loading)return;state.loading=true;render();try{const d=await rpc('get_combat_technique_system_v220');state.data=d?.status==='ok'?d:null;}catch(e){console.warn(MODULE,e);state.data=null;}finally{state.loading=false;render();}}
  function modalHtml(row){
    const s=state.data?.settings||{}, need=num(s.shard_combine_count||10), learned=row.learned;
    const sec=secretRate(row), secOwn=secretSpecifiedRate(row), sameGrade=(state.data?.techniques||[]).filter(x=>x.grade_code===row.grade_code&&x.code!==row.code).reduce((n,x)=>n+num(x.shards),0);
    const boss=row.grade_code==='heaven'?`普通BOSS池 ${pct(s.boss_normal_heaven_rate)}（指定本约 ${pct(bossSpecifiedRate(row,'normal'),4)}） / 困难池 ${pct(s.boss_hard_heaven_rate)}（指定本约 ${pct(bossSpecifiedRate(row,'hard'),4)}）`:row.grade_code==='immortal'?`困难BOSS池 ${pct(s.boss_hard_immortal_rate)}（指定本约 ${pct(bossSpecifiedRate(row,'hard'),4)}）`:'不掉落';
    return `<div class="modal-backdrop technique-modal-backdrop-v220"><section class="modal technique-modal-v220"><button class="modal-close-button" data-v220-close>×</button><span class="technique-modal-grade-v220">${esc(gradeNames[row.grade_code])} · ${row.family==='attack'?'攻伐功法':'护体功法'} · ${esc(row.role_name)}${row.enabled===false?' · GM已停用':''}</span><h3>《${esc(row.name)}》</h3><p>${esc(row.description)}</p>
      <div class="technique-modal-stats-v220"><div><span>参悟状态</span><strong>${learned?(row.is_mastered?'圆满':`第 ${fmt(row.level)} / ${fmt(row.max_level)} 层`):'尚未参悟'}</strong></div><div><span>残卷</span><strong>${fmt(row.shards)} / ${fmt(need)}</strong></div><div><span>完整道卷</span><strong>${fmt(row.books)}</strong></div><div><span>下一次精进</span><strong>${num(row.upgrade_cost)>0?`${fmt(row.upgrade_cost)} 灵石`:'—'}</strong></div></div>
      <section class="technique-modal-box-v220"><header>当前效果</header>${humanEffects(row).map(x=>`<p>· ${esc(x)}</p>`).join('')}</section>
      <section class="technique-modal-box-v220"><header>圆满效果预览</header>${humanEffects({...row,is_mastered:true},row.mastered_effects).map(x=>`<p>· ${esc(x)}</p>`).join('')}</section>
      <section class="technique-modal-box-v220"><header>残卷获取</header><p>机缘：在<strong>${esc(gradeNames[row.grade_code])}趋吉机缘</strong>内，任意攻防残卷池当前为 <strong>${pct(opportunityPoolRate(row),4)}</strong>，按当前家族/单本权重《${esc(row.name)}》约 <strong>${pct(rateFor(row),4)}</strong>。${row.grade_code==='yellow'?'黄品为独立5%默认配置，可由GM调整；旧普通功法没有黄品掉率行。':'玄/地/天/仙严格按当前普通功法条件概率×20%（五分之一）计算。'}</p><p>注意：这里是“已经抽到对应品级且为趋吉”后的条件概率，不是所有机缘的总概率。</p><p>秘境：${sec?`对应阶段妖兽残卷池 ${pct(sec)}，按当前家族/单本权重指定本约 <strong>${pct(secOwn,4)}/只</strong>。`:'黄品主要来自机缘。'}</p><p>世界BOSS：${esc(boss)}。天命榜只让功法生效，不产残卷。</p><p>秘境内残卷处于风险中：玩家战败按本轮全部残卷总数50%向下取整后原物转移，并有同对手反对刷。</p></section>
      <section class="technique-modal-actions-v220">
        ${row.enabled!==false&&num(row.shards)>=need?`<button class="primary-btn" data-v220-combine="${esc(row.code)}">合成完整道卷</button>`:''}
        ${row.enabled!==false&&!learned&&num(row.books)>0?`<button class="primary-btn" data-v220-learn="${esc(row.code)}">参悟功法</button>`:''}
        ${row.enabled!==false&&learned&&!row.equipped?`<button class="primary-btn" data-v220-equip="${esc(row.code)}" data-v220-family="${row.family}">运转此功法</button>`:''}
        ${row.enabled!==false&&learned&&!row.is_mastered?`<button class="secondary-btn" data-v220-upgrade="${esc(row.code)}">精进 · ${fmt(row.upgrade_cost)}灵石</button>`:''}
        ${row.enabled!==false&&s.shard_exchange_enabled!==false&&num(sameGrade)>=num(s.shard_exchange_cost||5)?`<button class="secondary-btn" data-v220-exchange="${esc(row.code)}">同品${fmt(s.shard_exchange_cost||5)}换${fmt(s.shard_exchange_gain||1)}指定残卷</button>`:''}
      </section><small>攻防功法无参悟境界门槛；战斗效果由服务端快照和 effect_code 权威结算。</small>
    </section></div>`;
  }
  function openModal(code){const row=(state.data?.techniques||[]).find(x=>x.code===code);if(!row)return;state.modalCode=code;const host=document.getElementById('modalRoot');if(!host)return;host.innerHTML=modalHtml(row);bindModal(host,row);}
  function bindModal(host,row){host.querySelectorAll('[data-v220-close]').forEach(b=>b.onclick=()=>{host.innerHTML='';state.modalCode='';});
    const act=async(name,body,msg)=>{try{host.querySelectorAll('button').forEach(b=>b.disabled=true);await rpc(name,body);toast(msg);await refresh();openModal(row.code);}catch(e){toast(String(e.message||e),'error');openModal(row.code);}};
    host.querySelector('[data-v220-combine]')?.addEventListener('click',()=>act('combine_combat_technique_shards_v220',{p_technique_code:row.code,p_request_id:uuid()},'残卷已合成完整道卷。'));
    host.querySelector('[data-v220-learn]')?.addEventListener('click',()=>act('learn_combat_technique_v220',{p_technique_code:row.code,p_request_id:uuid()},'功法参悟成功。'));
    host.querySelector('[data-v220-equip]')?.addEventListener('click',()=>act('set_combat_technique_equipped_v220',{p_family:row.family,p_technique_code:row.code},'功法已运转；下一场战斗/下一次入境或重新准备时锁定。'));
    host.querySelector('[data-v220-upgrade]')?.addEventListener('click',()=>act('upgrade_combat_technique_v220',{p_technique_code:row.code,p_request_id:uuid()},'功法精进成功。'));
    host.querySelector('[data-v220-exchange]')?.addEventListener('click',()=>{if(!confirm(`确认消耗同品级其它功法残卷，按 ${fmt(state.data?.settings?.shard_exchange_cost||5)} : ${fmt(state.data?.settings?.shard_exchange_gain||1)} 置换《${row.name}》残卷？`))return;act('exchange_combat_technique_shards_v220',{p_target_code:row.code,p_request_id:uuid()},'同品残卷置换成功。');});
  }
  function bindRoot(root){root.querySelectorAll('[data-v220-tech-code]').forEach(b=>b.onclick=()=>openModal(b.dataset.v220TechCode));root.querySelectorAll('[data-v220-unequip]').forEach(b=>b.onclick=async()=>{try{await rpc('set_combat_technique_equipped_v220',{p_family:b.dataset.v220Unequip,p_technique_code:null});toast('已卸下功法。');await refresh();}catch(e){toast(e.message,'error');}});}
  function openPathDetail(button){const card=button.closest('.path-card-v220');const source=card?.querySelector('.path-detail-source-v220');const host=document.getElementById('modalRoot');if(!host||!source)return;host.innerHTML=`<div class="modal-backdrop technique-modal-backdrop-v220"><section class="modal technique-modal-v220"><button class="modal-close-button" data-v220-close>×</button><span class="technique-modal-grade-v220">${esc(button.dataset.v220PathKind||'先天')}</span><h3>${esc(button.dataset.v220PathName||'详情')}</h3><div class="path-detail-copy-v220">${source.innerHTML}</div></section></div>`;host.querySelector('[data-v220-close]').onclick=()=>host.innerHTML='';}
  function bindShell(){
    const shell=document.getElementById('techniqueTabsV220'); if(!shell||state.bound===shell)return;state.bound=shell;
    shell.querySelectorAll('[data-v220-tech-tab]').forEach(b=>b.onclick=()=>tabSwitch(b.dataset.v220TechTab));document.querySelectorAll('[data-v220-path-open]').forEach(b=>b.onclick=()=>openPathDetail(b));tabSwitch(state.tab);refresh();
  }
  const observer=new MutationObserver(()=>bindShell());observer.observe(document.documentElement,{subtree:true,childList:true});
  window.addEventListener('jiuxiao:combat-technique-refresh',()=>refresh());
  window.addEventListener('jiuxiao:secret-realm-rendered',()=>{ if(state.data) refresh(); });
  bindShell();
  window.JIUXIAO_TECHNIQUE_V220={module:MODULE,refresh};
})();
