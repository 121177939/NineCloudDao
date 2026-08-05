(() => {
  'use strict';

  const MODULE = 'B-SECT01-FOUNDATION1';
  const config = window.GAME_CONFIG || {};
  const baseUrl = String(config.supabaseUrl || '').replace(/\/+$/, '');
  const apiKey = String(config.supabasePublishableKey || '');
  const projectRef = (() => { try { return new URL(baseUrl).hostname.split('.')[0]; } catch { return 'unknown'; } })();
  const sessionKey = `nine_cloud_dao_session_${projectRef}_v1`;
  const deviceKey = `nine_cloud_dao_device_${projectRef}_v1`;
  const state = { data: null, loading: false, busy: false, lastFetchAt: 0, boundRoot: null };

  const esc = value => String(value ?? '')
    .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;').replaceAll("'", '&#039;');
  const uuid = () => globalThis.crypto?.randomUUID?.() || 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const v = Math.random() * 16 | 0; return (c === 'x' ? v : (v & 3 | 8)).toString(16);
  });
  const session = () => { try { return JSON.parse(localStorage.getItem(sessionKey) || 'null'); } catch { return null; } };
  const number = (value, fallback = 0) => Number.isFinite(Number(value)) ? Number(value) : fallback;
  const fmt = value => number(value).toLocaleString('zh-CN', { maximumFractionDigits: 2 });
  const time = value => { const d = value ? new Date(value) : null; return d && !Number.isNaN(d.getTime()) ? d.toLocaleString('zh-CN', { month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hour12:false }) : '—'; };

  function toast(message, type = 'success') {
    const element = document.getElementById('toast');
    if (!element) return;
    element.textContent = message;
    element.className = `toast show ${type}`;
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => { element.className = 'toast'; }, 3800);
  }

  function errorText(error) {
    const raw = String(error?.message || error || '宗门操作失败');
    const map = [
      ['BSECT01_DACHENG_EARLY_REQUIRED', '达到大乘初期后才能开山立派。'],
      ['BSECT01_SECT_ALREADY_EXISTS', '当前角色传承已经拥有宗门。'],
      ['BSECT01_SECT_NAME_TAKEN', '这个宗门名称已经被占用。'],
      ['BSECT01_INVALID_SECT_NAME', '宗门名称需要2—16个字符。'],
      ['BSECT01_OPENING_ALREADY_CHOSEN', '开山大弟子已经确定。'],
      ['BSECT01_DISCIPLE_LIMIT_REACHED', '宗门弟子已达到20人上限。'],
      ['BSECT01_CANDIDATE_NOT_AVAILABLE', '这名候选人已经离开或被招收。'],
      ['BSECT01_DISABLED', '宗门经营V2当前处于维护状态。'],
      ['AUTH_REQUIRED', '请先登录游戏。'],
      ['PGRST202', 'B-SECT01数据库RPC尚未安装。'],
      ['Could not find the function', 'B-SECT01数据库RPC尚未安装。']
    ];
    return (map.find(([code]) => raw.includes(code)) || [])[1] || raw;
  }

  async function rpc(name, body = {}) {
    const active = session();
    if (!active?.access_token) throw new Error('AUTH_REQUIRED');
    const response = await fetch(`${baseUrl}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: { apikey: apiKey, Authorization: `Bearer ${active.access_token}`, 'Content-Type': 'application/json', 'X-Game-Session-Id': localStorage.getItem(deviceKey) || '' },
      body: JSON.stringify(body)
    });
    const text = await response.text(); let data = null;
    try { data = text ? JSON.parse(text) : null; } catch { data = text; }
    if (!response.ok) throw new Error(data?.message || data?.error || `HTTP ${response.status}`);
    return Array.isArray(data) ? data[0] || null : data;
  }

  const identityName = code => ({ opening_first:'开山大弟子',registered:'记名弟子',outer:'外门弟子',inner:'内门弟子',direct:'亲传弟子',steward:'执事',elder:'长老',peak_master:'峰主',grand_elder:'大长老',chief:'首席弟子' }[code] || code || '弟子');
  const directionName = code => ({ cultivation:'修炼倾向',combat:'实战倾向',balanced:'均衡倾向' }[code] || '均衡倾向');
  const assignmentName = code => code === 'cultivation' ? '持续修炼中' : '等待安排';
  const genderName = code => code === 'female' ? '女' : '男';

  function root() { return document.getElementById('sectV2RootBSect01'); }
  function setRoot(html) { const el = root(); if (el) el.innerHTML = html; }
  function progress(d) { const cap = Math.max(0, number(d.cultivation_cap)); return cap > 0 ? Math.min(100, number(d.cultivation) / cap * 100) : 0; }

  function loadingHtml() { return '<div class="sect-v2-loading-bsect01">正在查阅宗门名册……</div>'; }
  function unavailableHtml(message) {
    return `<div class="sect-v2-empty-bsect01"><h4>宗门经营V2尚未接通</h4><p>${esc(message)}</p><button class="secondary-btn" type="button" data-bsect-refresh>重新读取</button></div>`;
  }
  function lockedHtml(data) {
    return `<div class="sect-v2-callout-bsect01"><strong>开山之机尚未成熟</strong><p>当前境界：${esc(data.current_realm_name || '未知')}。角色达到大乘初期后，即可直接创建一个个人宗门，无需建宗令或灵石。</p></div>`;
  }
  function createHtml() {
    return `<form class="sect-v2-create-bsect01" id="createSectV2FormBsect01"><div><strong>开山立派</strong><p>宗主只需为宗门定名。创建后将出现三名方向不同的开山弟子候选。</p></div><label><span>宗门名称</span><input name="sectName" minlength="2" maxlength="16" autocomplete="off" placeholder="如：九霄剑宗" required></label><button class="primary-btn" type="submit">创建宗门</button></form>`;
  }
  function candidateCard(c, opening) {
    return `<article class="sect-v2-card-bsect01 ${opening ? 'is-opening' : ''}"><div><small>${esc(directionName(c.direction_code))}</small><h4>${esc(c.name)}</h4></div><div class="sect-v2-tags-bsect01"><span>${esc(genderName(c.gender))} · ${fmt(c.age_years)}岁</span><span>${esc(c.spirit_root_name)}</span><span>${esc(c.element_name)}属性</span>${c.realm_name ? `<span>${esc(c.realm_name)}</span>` : ''}</div><p>详细性格、战斗差异和隐藏特质将在正式收入宗门后显现。</p><div class="sect-v2-actions-bsect01">${opening ? `<button class="primary-btn" type="button" data-bsect-opening="${esc(c.id)}">选为开山大弟子</button>` : `<button class="primary-btn" type="button" data-bsect-recruit="${esc(c.id)}">收入宗门</button><button class="secondary-btn" type="button" data-bsect-lock="${esc(c.id)}" ${c.status === 'locked' ? 'disabled' : ''}>${c.status === 'locked' ? '已锁定24小时' : '锁定候选'}</button>`}</div></article>`;
  }
  function discipleCard(d) {
    const pct = progress(d); const capped = number(d.cultivation_cap) > 0 && number(d.cultivation) >= number(d.cultivation_cap);
    return `<article class="sect-v2-card-bsect01"><div><small>${esc(identityName(d.identity_code))}</small><h4>${esc(d.dao_name || d.name)}</h4>${d.dao_name ? `<small>本名：${esc(d.name)}</small>` : ''}</div><div class="sect-v2-tags-bsect01"><span>${esc(d.spirit_root_name)}</span><span>${esc(d.element_name)}属性</span><span>${esc(d.realm_name)}</span><span>${esc(d.personality)}</span></div><div class="sect-v2-statline-bsect01"><span>修为 ${fmt(d.cultivation)} / ${fmt(d.cultivation_cap)}</span><span>${capped ? '修为圆满' : assignmentName(d.assignment_type)}</span></div><div class="sect-v2-progress-bsect01"><i style="width:${pct.toFixed(2)}%"></i></div><small>当前速率约 ${fmt(d.rate_per_second)}/秒 · 灵根只影响修炼速度</small><div class="sect-v2-actions-bsect01"><button class="secondary-btn" type="button" data-bsect-detail="${esc(d.id)}">查看详情</button>${d.assignment_type === 'cultivation' ? `<button class="secondary-btn" type="button" data-bsect-assignment="${esc(d.id)}" data-assignment="idle">停止修炼</button>` : `<button class="primary-btn" type="button" data-bsect-assignment="${esc(d.id)}" data-assignment="cultivation" ${capped ? 'disabled' : ''}>开始修炼</button>`}</div></article>`;
  }
  function dashboardHtml(data) {
    const sect = data.sect || {}; const disciples = Array.isArray(data.disciples) ? data.disciples : []; const candidates = Array.isArray(data.candidates) ? data.candidates : [];
    const openingNeeded = !disciples.some(d => d.identity_code === 'opening_first');
    const opening = candidates.filter(c => c.kind === 'opening'); const normal = candidates.filter(c => c.kind !== 'opening');
    const events = Array.isArray(data.recent_events) ? data.recent_events : [];
    return `<div class="sect-v2-shell-bsect01"><div class="sect-v2-head-bsect01"><div><span>${openingNeeded ? '开山立派 · 待定首徒' : '宗主经营 · 弟子养成'}</span><strong>${esc(sect.name)}</strong><small>阶段：开山立派 · 弟子 ${disciples.length}/${number(data.settings?.max_disciple_count,20)}</small></div><div class="sect-v2-actions-bsect01"><button class="secondary-btn" type="button" data-bsect-refresh>结算并刷新</button></div></div>${openingNeeded ? `<div class="sect-v2-callout-bsect01"><strong>选择开山大弟子</strong><p>三名候选整体质量接近，分别偏向修炼、实战和均衡。选择后不可撤销，身份永久保留且不提供额外数值加成。</p></div><div class="sect-v2-grid-bsect01">${opening.map(c => candidateCard(c,true)).join('')}</div>` : `<div class="sect-v2-section-title-bsect01"><h4>宗门弟子</h4><span>${disciples.filter(d=>d.assignment_type==='cultivation').length}人正在修炼</span></div><div class="sect-v2-grid-bsect01">${disciples.map(discipleCard).join('') || '<div class="sect-v2-empty-bsect01">宗门目前没有存活弟子。</div>'}</div><div class="sect-v2-section-title-bsect01"><h4>山门候选</h4><span>${sect.next_candidate_refresh_at ? `下次刷新 ${time(sect.next_candidate_refresh_at)}` : '等待刷新'}</span></div><div class="sect-v2-grid-bsect01">${normal.map(c=>candidateCard(c,false)).join('') || '<div class="sect-v2-empty-bsect01">当前没有新的拜师候选，刷新时间到达后再来查看。</div>'}</div>`}<div class="sect-v2-section-title-bsect01"><h4>宗门史</h4><span>最近20条</span></div><div class="sect-v2-log-bsect01">${events.map(e=>`<article><strong>${esc(e.title)}</strong><p>${esc(e.content)}</p><small>${time(e.created_at)}</small></article>`).join('') || '<div class="sect-v2-empty-bsect01">宗门史尚无记载。</div>'}</div></div>`;
  }

  function render() {
    const el = root(); if (!el) return;
    if (state.loading && !state.data) { setRoot(loadingHtml()); return; }
    const data = state.data;
    if (!data) setRoot(unavailableHtml('等待B-SECT01数据。'));
    else if (data.status === 'unavailable') setRoot(unavailableHtml(data.error || '数据库尚未安装。'));
    else if (data.status === 'no_character') setRoot(unavailableHtml('未找到当前角色。'));
    else if (data.status === 'no_sect') setRoot(data.unlocked ? createHtml() : lockedHtml(data));
    else setRoot(dashboardHtml(data));
    bind();
  }

  async function refresh({ sync = true, silent = true } = {}) {
    if (state.loading) return state.data;
    state.loading = true; if (!state.data) render();
    try {
      state.data = sync
        ? await rpc('sync_sect_v2_dashboard_bsect01', { p_request_id: uuid() })
        : await rpc('get_sect_v2_dashboard_bsect01');
      state.lastFetchAt = Date.now(); render(); if (!silent) toast('宗门事务已结算。'); return state.data;
    } catch (error) {
      state.data = { status:'unavailable', error:errorText(error) }; render(); if (!silent) toast(errorText(error),'error'); return state.data;
    } finally { state.loading = false; }
  }

  async function action(name, body, success) {
    if (state.busy) return;
    state.busy = true;
    try { state.data = await rpc(name, { ...body, p_request_id: uuid() }); render(); toast(success); }
    catch (error) { toast(errorText(error),'error'); }
    finally { state.busy = false; }
  }

  async function showDetail(id) {
    try {
      const d = await rpc('get_sect_disciple_detail_bsect01', { p_disciple_id:id });
      const modal = document.createElement('div'); modal.className='sect-v2-modal-bsect01';
      modal.innerHTML=`<article class="sect-v2-modal-card-bsect01"><header><div><small>${esc(identityName(d.identity_code))}</small><h3>${esc(d.dao_name || d.name)}</h3></div><button class="secondary-btn" type="button" data-close>关闭</button></header><dl><div><dt>本名</dt><dd>${esc(d.name)}</dd></div><div><dt>年龄</dt><dd>${fmt(d.age_years)}岁</dd></div><div><dt>灵根</dt><dd>${esc(d.spirit_root_name)} ×${fmt(d.spirit_root_multiplier)}</dd></div><div><dt>五行</dt><dd>${esc(d.element_name)}属性</dd></div><div><dt>境界</dt><dd>${esc(d.realm_name)}</dd></div><div><dt>修为</dt><dd>${fmt(d.cultivation)} / ${fmt(d.cultivation_cap)}</dd></div><div><dt>性格</dt><dd>${esc(d.personality)}</dd></div><div><dt>特质</dt><dd>${esc((d.visible_traits || []).join('、') || '尚未显现')}</dd></div><div><dt>忠诚</dt><dd>${fmt(d.loyalty)}</dd></div><div><dt>心境</dt><dd>${fmt(d.mood)}</dd></div><div><dt>伤势</dt><dd>${esc(d.injury_status)}</dd></div><div><dt>安排</dt><dd>${esc(assignmentName(d.assignment_type))}</dd></div></dl><p class="sect-v2-meta-bsect01">灵根只影响修炼速度；五行只在后续弟子战斗中参与克制。突破模块将在B-SECT02接入现有突破规则。</p></article>`;
      document.body.appendChild(modal); const close=()=>modal.remove(); modal.addEventListener('click',e=>{if(e.target===modal||e.target.closest('[data-close]'))close();});
    } catch (error) { toast(errorText(error),'error'); }
  }

  function bind() {
    const el = root(); if (!el) return;
    el.querySelectorAll('[data-bsect-refresh]').forEach(b=>b.addEventListener('click',()=>refresh({sync:true,silent:false})));
    el.querySelector('#createSectV2FormBsect01')?.addEventListener('submit', e => { e.preventDefault(); const name = new FormData(e.currentTarget).get('sectName'); action('create_sect_v2_bsect01',{p_name:String(name||'').trim()},'宗门已创建，请选择开山大弟子。'); });
    el.querySelectorAll('[data-bsect-opening]').forEach(b=>b.addEventListener('click',()=>{ if(confirm('开山大弟子一经选择不可撤销，确认选择？')) action('choose_opening_disciple_bsect01',{p_candidate_id:b.dataset.bsectOpening},'开山大弟子已经入门。'); }));
    el.querySelectorAll('[data-bsect-recruit]').forEach(b=>b.addEventListener('click',()=>action('recruit_sect_candidate_bsect01',{p_candidate_id:b.dataset.bsectRecruit},'新弟子已经入门。')));
    el.querySelectorAll('[data-bsect-lock]').forEach(b=>b.addEventListener('click',()=>action('lock_sect_candidate_bsect01',{p_candidate_id:b.dataset.bsectLock},'候选弟子已锁定24小时。')));
    el.querySelectorAll('[data-bsect-assignment]').forEach(b=>b.addEventListener('click',()=>action('set_sect_disciple_assignment_bsect01',{p_disciple_id:b.dataset.bsectAssignment,p_assignment_type:b.dataset.assignment},b.dataset.assignment==='cultivation'?'弟子已开始持续修炼。':'弟子已停止修炼。')));
    el.querySelectorAll('[data-bsect-detail]').forEach(b=>b.addEventListener('click',()=>showDetail(b.dataset.bsectDetail)));
  }

  function onRendered() {
    const el = root(); if (!el) return;
    state.boundRoot = el; render();
    if (!state.data || Date.now() - state.lastFetchAt > 60_000) refresh({ sync:true, silent:true });
  }

  window.addEventListener('jiuxiao:sect-v2-rendered', onRendered);
  window.addEventListener('focus', () => { if (root() && Date.now()-state.lastFetchAt>60_000) refresh({sync:true,silent:true}); }, { passive:true });
  window.B_SECTV2_B01 = { module:MODULE, refresh, render, state:() => state.data };
})();
