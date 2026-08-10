/* 九霄问道 · B模块：天道人物 / 仙缘 / 道侣
 * 正式合并基线：V2.2.0 CACHE130
 * 目标：替换现有 data-mobile-screen="social" 的“红尘录”表现层。
 * 正式生产接入由 SQL259 提供；旧红尘系统彻底废弃，新版只依赖天道人物 RPC。
 */
(() => {
  'use strict';

  const BUILD = 'B-TIANDAO-PERSON-V06-CACHE130-INTERACTION-UX';
  const cfg = window.GAME_CONFIG || {};
  const BASE = String(cfg.supabaseUrl || '').replace(/\/+$/, '');
  const KEY = String(cfg.supabasePublishableKey || '');
  const PROJECT_REF = (() => { try { return new URL(BASE).hostname.split('.')[0]; } catch { return 'unknown'; } })();
  const SESSION_KEY = `nine_cloud_dao_session_${PROJECT_REF}_v1`;
  const DEVICE_KEY = `nine_cloud_dao_device_${PROJECT_REF}_v1`;

  const state = {
    view: 'home',
    bundle: null,
    selected: null,
    loading: false,
    mounted: false,
    lastLoad: 0,
    peopleFilter: 'all',
    actionBusy: false
  };

  const detailCache = new Map();
  let detailRequestSeq = 0;
  let mountQueued = false;

  const esc = v => String(v ?? '')
    .replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;')
    .replaceAll('"','&quot;').replaceAll("'",'&#039;');

  const fmt = n => Number(n || 0).toLocaleString('zh-CN');

  function humanError(error) {
    const raw = String(error?.message || error || '');
    if (raw.includes('AUTH_REQUIRED')) return '登录状态已失效，请重新登录。';
    if (raw.includes('TIANDAO_PERSON_NOT_KNOWN')) return '你与此人尚未真正产生可继续的因果。';
    if (raw.includes('TIANDAO_INTERACTIONS_DISABLED')) return '人物交游目前暂停。';
    if (raw.includes('TIANDAO_INTERACTION_COOLDOWN')) return '刚刚已经互动过，请稍后再来。';
    if (raw.includes('TIANDAO_ROMANCE_DISABLED')) return '仙缘功能目前暂停。';
    if (raw.includes('TIANDAO_COMPANION_DISABLED')) return '道侣互动目前暂停。';
    if (raw.includes('TIANDAO_CONFESSION_REQUIREMENTS')) return '你们之间的好感、信任、亲密与情缘还不足以表明心意。';
    if (raw.includes('TIANDAO_CONFESSION_COOLDOWN')) return '这份心意刚刚已经传达，请给彼此一些时间。';
    if (raw.includes('TIANDAO_COMPANION_ALREADY_EXISTS')) return '你当前已经有正式道侣。';
    if (raw.includes('TIANDAO_COMPANION_ACTION_COOLDOWN')) return '刚刚已经与道侣互动过，请稍后再来。';
    if (raw.includes('TIANXU_ITEM_INSUFFICIENT')) return '灵石不足，无法准备这份赠礼。';
    if (raw.includes('TIANDAO_ENCOUNTER_EXPIRED')) return '这段缘遇已经错过。';
    if (raw.includes('TIANDAO_AI_REQUEST_EXPIRED')) return '这次人物决策已超时，请重新操作。';
    if (raw.includes('tiandao-ai') || raw.includes('FunctionsHttpError')) return '天道人物服务暂时不可用，请稍后重试。';
    return raw || '天机暂时无法推演，请稍后重试。';
  }

  function session() {
    try { return JSON.parse(localStorage.getItem(SESSION_KEY) || 'null'); } catch { return null; }
  }

  function deviceId() {
    return localStorage.getItem(DEVICE_KEY) || '';
  }

  async function rpc(name, body = {}) {
    const s = session();
    if (!s?.access_token) throw new Error('AUTH_REQUIRED');
    const res = await fetch(`${BASE}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: {
        apikey: KEY,
        Authorization: `Bearer ${s.access_token}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'X-Game-Session-Id': deviceId()
      },
      body: JSON.stringify(body)
    });
    const text = await res.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch { data = text; }
    if (!res.ok) {
      const e = new Error(data?.message || data?.error || data?.msg || `HTTP ${res.status}`);
      e.status = res.status; e.payload = data; throw e;
    }
    return Array.isArray(data) ? (data[0] ?? null) : data;
  }

  async function tryRpc(name, body = {}) {
    try { return await rpc(name, body); } catch (e) { return { __error: e }; }
  }

  async function edgeAi(body = {}) {
    const s = session();
    if (!s?.access_token) throw new Error('AUTH_REQUIRED');
    const res = await fetch(`${BASE}/functions/v1/tiandao-ai`, {
      method: 'POST',
      headers: {
        apikey: KEY,
        Authorization: `Bearer ${s.access_token}`,
        'Content-Type': 'application/json',
        Accept: 'application/json',
        'X-Game-Session-Id': deviceId()
      },
      body: JSON.stringify(body)
    });
    const text = await res.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch { data = text; }
    if (!res.ok) {
      const e = new Error(data?.error || data?.message || data?.msg || `HTTP ${res.status}`);
      e.status = res.status; e.payload = data; throw e;
    }
    return data;
  }

  async function tryEdgeAi(body = {}) {
    try { return await edgeAi(body); } catch (e) { return { __error: e }; }
  }

  function toast(msg, error = false) {
    const t = document.getElementById('toast');
    if (!t) return;
    t.textContent = msg;
    t.className = `toast show ${error ? 'error' : ''}`;
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => t.className = 'toast', 3600);
  }

  function attitudeText(p) {
    const r = String(p?.relation_stage || p?.relationship_name || '').trim();
    if (r) return r;
    const a = Number(p?.affinity || 0), trust = Number(p?.trust || 0), romance = Number(p?.romance || 0);
    if (romance >= 70) return '倾心';
    if (romance >= 45) return '心有情愫';
    if (trust >= 60 && a >= 60) return '知己';
    if (a >= 35) return '熟识';
    if (a >= 10) return '相识';
    if (a <= -40) return '敌视';
    return '陌生';
  }

  function publicMood(p) {
    const stage = attitudeText(p);
    const map = {
      '倾心':'与你相处时，目光中已很难掩饰情意。',
      '心有情愫':'似乎越来越在意你的言行。',
      '知己':'对你已少有戒备，愿意谈及心中之事。',
      '熟识':'与你相处得还算自在。',
      '相识':'已经记住了你，但彼此仍需更多了解。',
      '敌视':'对你的敌意并未消退。',
      '陌生':'你们尚未真正熟悉。'
    };
    return p?.attitude_text || map[stage] || map['陌生'];
  }

  async function loadBundle(force = false) {
    if (state.loading) return;
    if (!force && state.bundle && Date.now() - state.lastLoad < 30000) return;
    state.loading = true;
    render();
    try {
      const b = await rpc('get_tiandao_people_hub_v1', {});
      state.bundle = b || { people:[], encounters:[], romance:[], companion:null, counts:{} };
      state.lastLoad = Date.now();
    } catch (e) {
      state.bundle = {
        status:'unavailable',
        error:String(e?.message || e),
        people:[], encounters:[], romance:[], companion:null, counts:{}
      };
    } finally {
      state.loading = false;
      render();
    }
  }

  function navTabs() {
    const tabs = [
      ['home','总览'],['encounters','缘遇'],['people','人物志'],['romance','仙缘'],['companion','道侣']
    ];
    return `<div class="tp-tabs">${tabs.map(([v,l]) =>
      `<button class="${state.view===v?'active':''}" data-tp-view="${v}" type="button">${l}</button>`
    ).join('')}</div>`;
  }

  function personCard(p, compact=false) {
    const stage = attitudeText(p);
    return `<article class="tp-person-card ${p.is_companion?'is-companion':''}" data-tp-person="${esc(p.npc_id || p.npc_code)}">
      <div class="tp-person-avatar">${esc((p.name || '人').slice(-1))}</div>
      <div class="tp-person-main">
        <div class="tp-person-head"><strong>${esc(p.name || '未知')}</strong><em>${esc(stage)}</em></div>
        <p>${esc([p.realm_label,p.identity].filter(Boolean).join(' · ') || '九霄修士')}</p>
        ${compact ? '' : `<small>${esc(p.latest_rumor || p.current_status || publicMood(p))}</small>`}
      </div>
      <span class="tp-chevron">›</span>
    </article>`;
  }

  function homeHtml(b) {
    const c = b.counts || {};
    const enc = (b.encounters || []).slice(0,3);
    const romance = (b.romance || []).filter(x=>!x.is_companion).slice(0,3);
    return `
      <section class="tp-hero">
        <div><span>九霄人物</span><h3>人间万象，皆有因果</h3><p>结识、恩怨、仙缘与道侣，都由你与他们真实发生的经历推动。</p></div>
        <div class="tp-count-orb"><strong>${fmt(c.known ?? (b.people||[]).length)}</strong><small>已结识</small></div>
      </section>
      <div class="tp-metric-grid">
        <button data-tp-view="encounters"><span>缘遇</span><strong>${fmt(enc.length || c.encounters || 0)}</strong><small>待回应</small></button>
        <button data-tp-view="people"><span>人物志</span><strong>${fmt(c.known ?? 0)}</strong><small>结识之人</small></button>
        <button data-tp-view="romance"><span>仙缘</span><strong>${fmt(c.romance ?? romance.length)}</strong><small>有缘之人</small></button>
        <button data-tp-view="companion"><span>道侣</span><strong>${b.companion ? '1' : '—'}</strong><small>${b.companion?'已结缘':'大道未定'}</small></button>
      </div>
      <section class="tp-block">
        <div class="tp-block-head"><div><span>当前缘遇</span><strong>有人正在你的因果线上出现</strong></div><button data-tp-view="encounters">全部</button></div>
        ${enc.length ? enc.map(e=>encounterCard(e)).join('') : '<div class="tp-empty">暂时没有新的缘遇。继续正常修行，缘分自会出现。</div>'}
      </section>
      <section class="tp-block">
        <div class="tp-block-head"><div><span>仙缘近况</span><strong>关系不是数值冲满，而是共同经历</strong></div><button data-tp-view="romance">查看</button></div>
        ${romance.length ? romance.map(x=>personCard(x,true)).join('') : '<div class="tp-empty">尚无人与你情意渐深。</div>'}
      </section>
      ${b.companion ? `<section class="tp-block tp-companion-mini"><div class="tp-block-head"><div><span>我的道侣</span><strong>${esc(b.companion.name)}</strong></div><button data-tp-view="companion">进入</button></div>${personCard(b.companion,false)}</section>` : ''}
      <section class="tp-world-link"><div><span>九霄界闻</span><strong>NPC重大突破、宗门变动、结缘等仍进入游戏原有九霄界闻</strong></div><button data-tp-open-world-news type="button">前往界闻</button></section>
    `;
  }

  function encounterCard(e) {
    const actions=Array.isArray(e.actions)&&e.actions.length ? e.actions : (e.action_label ? [{code:e.action_code||'approach',label:e.action_label}] : []);
    return `<article class="tp-encounter">
      <div class="tp-encounter-mark">缘</div>
      <div><strong>${esc(e.title || e.npc_name || '一段缘遇')}</strong><p>${esc(e.summary || e.content || '天机未明。')}</p><small>${esc(e.location_name || e.source_label || '')}</small></div>
      <div class="tp-encounter-actions">
        ${actions.map(a=>`<button data-tp-encounter="${esc(e.encounter_id || '')}" data-tp-encounter-action="${esc(a.code||'approach')}">${esc(a.label||'回应')}</button>`).join('')}
        ${e.npc_id ? `<button class="ghost" data-tp-person="${esc(e.npc_id)}">人物</button>` : ''}
      </div>
    </article>`;
  }

  function encountersHtml(b) {
    const rows = b.encounters || [];
    return `<section class="tp-page-head"><span>缘遇</span><h3>你不需要去“探索页”找人</h3><p>战斗、坊市、宗门、修炼、世界事件与NPC主动传音，都可以产生缘遇。</p></section>
      <div class="tp-list">${rows.length ? rows.map(encounterCard).join('') : '<div class="tp-empty big">当前没有待处理缘遇。NPC会在你正常游玩过程中出现。</div>'}</div>`;
  }

  function peopleHtml(b) {
    const rows=b.people || [];
    const heard=rows.filter(x=>x.known_level==='heard').length;
    const filtered=rows.filter(p=>{
      const stage=attitudeText(p);
      if(state.peopleFilter==='friend') return ['相识','熟识'].includes(stage);
      if(state.peopleFilter==='confidant') return ['知己','心有情愫','倾心','道侣'].includes(stage);
      if(state.peopleFilter==='enemy') return stage==='敌视';
      return true;
    });
    const filters=[['all','全部'],['friend','故交'],['confidant','知己'],['enemy','敌对']];
    return `<section class="tp-page-head"><span>人物志</span><h3>已结识 ${fmt((b.counts||{}).known ?? rows.length)} · 听闻 ${fmt((b.counts||{}).heard ?? heard)}</h3><p>玩家只看得到自己知道的信息；NPC真实目标、仇恨数值和内部决策仅GM可见。</p></section>
      <div class="tp-filter-row">${filters.map(([code,label])=>`<button class="${state.peopleFilter===code?'active':''}" data-tp-filter="${code}" type="button">${label}</button>`).join('')}</div>
      <div class="tp-list">${filtered.length?filtered.map(p=>personCard(p)).join(''):'<div class="tp-empty big">当前筛选下没有人物。</div>'}</div>`;
  }

  function romanceHtml(b) {
    const rows=(b.romance || []).filter(x=>!x.is_companion);
    return `<section class="tp-page-head romance"><span>仙缘</span><h3>大道漫漫，情由事生</h3><p>表明心意前会综合好感、信任、亲密、情缘、仇恨以及NPC自己的记忆与人格。</p></section>
      <div class="tp-list">${rows.length?rows.map(p=>`
        <article class="tp-romance-card">
          ${personCard(p,true)}
          <div class="tp-romance-copy"><span>${esc(attitudeText(p))}</span><p>${esc(publicMood(p))}</p></div>
          <div class="tp-romance-actions">
            <button data-tp-person="${esc(p.npc_id || p.npc_code)}">查看</button>
            ${p.can_confess ? `<button class="primary" data-tp-confess="${esc(p.npc_id || p.npc_code)}">表明心意</button>` : ''}
          </div>
        </article>`).join(''):'<div class="tp-empty big">目前尚无已经发展到仙缘阶段的人物。</div>'}</div>`;
  }

  function companionHtml(b) {
    const p=b.companion;
    if(!p) return `<section class="tp-page-head romance"><span>道侣</span><h3>大道未定，仙缘未至</h3><p>与NPC真正相识、共同经历并取得对方自主同意后，才能正式结缘。</p></section>
      <div class="tp-empty big">当前没有正式道侣。去人物志与仙缘看看你已经认识的人。</div>`;
    return `<section class="tp-companion-hero">
      <div class="tp-companion-seal">侣</div>
      <div><span>我的道侣</span><h3>${esc(p.name)}</h3><p>${esc([p.realm_label,p.identity].filter(Boolean).join(' · '))}</p></div>
    </section>
    <div class="tp-companion-actions">
      <button data-tp-companion-action="message">传音</button>
      <button data-tp-companion-action="gift">赠礼</button>
      <button data-tp-companion-action="meeting">相约</button>
      <button data-tp-companion-action="joint_cultivation">共同修炼</button>
      <button data-tp-companion-action="protect">请求护道</button>
      <button data-tp-person="${esc(p.npc_id || p.npc_code)}">查看往事</button>
    </div>
    <section class="tp-block"><div class="tp-block-head"><div><span>当前状态</span><strong>${esc(p.current_status || '正在自己的修行道路上')}</strong></div></div><p class="tp-body-copy">${esc(p.latest_rumor || publicMood(p))}</p></section>`;
  }

  function closePersonModal() {
    detailRequestSeq += 1;
    const root = document.getElementById('modalRoot');
    if (root) root.innerHTML = '';
  }

  function personLoadingHtml(id) {
    return `<div class="modal-backdrop tp-modal-backdrop" data-tp-modal-backdrop data-tp-modal-id="${esc(id)}">
      <section class="modal tp-person-modal tp-person-modal-loading" role="dialog" aria-modal="true" aria-busy="true">
        <button class="modal-close-button" data-tp-close-modal type="button" aria-label="关闭">×</button>
        <div class="tp-ai-wait"><span class="tp-ai-spinner" aria-hidden="true"></span><strong>正在读取人物因果……</strong><small>你可以随时关闭，不会卡住页面。</small></div>
      </section>
    </div>`;
  }

  function personDetailHtml(detail, id) {
    return `<div class="modal-backdrop tp-modal-backdrop" data-tp-modal-backdrop data-tp-modal-id="${esc(id)}"><section class="modal tp-person-modal" role="dialog" aria-modal="true">
      <button class="modal-close-button" data-tp-close-modal type="button" aria-label="关闭">×</button>
      <div class="tp-person-detail-head"><div class="tp-person-avatar big">${esc((detail.name||'人').slice(-1))}</div><div><span>${esc(detail.identity||'九霄修士')}</span><h3>${esc(detail.name)}</h3><p>${esc(detail.realm_label||'')}</p></div><em>${esc(attitudeText(detail))}</em></div>
      <section><small>TA对你的态度</small><p>${esc(publicMood(detail))}</p></section>
      <section><small>最近消息</small><p>${esc(detail.latest_rumor||detail.current_status||'暂无线索。')}</p></section>
      <section><small>与你的往事</small><div class="tp-memory-list">${(detail.public_memories||[]).slice(0,8).map(m=>`<p>· ${esc(m.content||m)}</p>`).join('')||'<p>尚无足以载入人物志的大事。</p>'}</div></section>
      <div class="tp-detail-actions">
        <button data-tp-interact="talk" data-tp-id="${esc(id)}">交谈</button>
        <button data-tp-interact="gift" data-tp-id="${esc(id)}">赠礼</button>
        <button data-tp-interact="meeting" data-tp-id="${esc(id)}">相约</button>
        ${detail.can_confess ? `<button class="primary" data-tp-confess="${esc(id)}">表明心意</button>`:''}
      </div>
      <div class="tp-action-status" data-tp-action-status hidden></div>
    </section></div>`;
  }

  async function openPerson(id) {
    if(!id || state.actionBusy) return;
    const root=document.getElementById('modalRoot');
    if(!root) return;
    const cached = detailCache.get(id);
    if (cached && Date.now() - cached.at < 45000) {
      state.selected = cached.data;
      root.innerHTML = personDetailHtml(cached.data, id);
      return;
    }
    const seq = ++detailRequestSeq;
    root.innerHTML = personLoadingHtml(id);
    const detail = await tryRpc('get_tiandao_person_detail_v1',{p_npc_id:id});
    if (seq !== detailRequestSeq) return;
    if(detail?.__error || !detail) {
      closePersonModal();
      return toast('人物资料读取失败。',true);
    }
    detailCache.set(id, { at: Date.now(), data: detail });
    state.selected=detail;
    root.innerHTML=personDetailHtml(detail,id);
  }

  function setActionBusy(busy, label='') {
    state.actionBusy = busy;
    const modal = document.querySelector('.tp-person-modal');
    if (modal) {
      modal.classList.toggle('is-busy', busy);
      modal.querySelectorAll('button').forEach(btn => {
        if (!btn.matches('[data-tp-close-modal]')) btn.disabled = busy;
      });
      const status = modal.querySelector('[data-tp-action-status]');
      if (status) {
        status.hidden = !busy;
        status.innerHTML = busy ? `<span class="tp-ai-spinner" aria-hidden="true"></span><div><strong>${esc(label || 'NPC正在思量……')}</strong><small>Cloudflare 响应较慢时会自动切换本地人格，不会丢失本次操作。</small></div>` : '';
      }
    }
    document.querySelectorAll('#bTiandaoPersonRoot [data-tp-encounter], #bTiandaoPersonRoot [data-tp-companion-action], #bTiandaoPersonRoot [data-tp-confess]').forEach(btn => { btn.disabled = busy; });
  }

  async function runAiAction(label, task, options={}) {
    if (state.actionBusy) {
      toast('上一段人物因果仍在推演，请稍候。');
      return null;
    }
    setActionBusy(true, label);
    if (!options.silentToast) toast(label || 'NPC正在思量……');
    try {
      const r = await task();
      if(r?.__error) {
        toast(humanError(r.__error),true);
        return null;
      }
      return r;
    } finally {
      setActionBusy(false);
    }
  }

  async function interact(id, action) {
    const labels={talk:'正在与TA交谈……',gift:'TA正在回应你的赠礼……',meeting:'TA正在考虑这次相约……'};
    const r=await runAiAction(labels[action]||'NPC正在思量……',()=>tryEdgeAi({mode:'interaction',npc_id:id,action}),{silentToast:true});
    if(!r) return;
    toast(r?.content||'这段因缘有了新的变化。');
    detailCache.delete(id);
    closePersonModal();
    await loadBundle(true);
  }

  async function confess(id) {
    if (state.actionBusy) return;
    const line=prompt('你想对TA说什么？','愿往后大道漫漫，与你同行。');
    if(line===null) return;
    const r=await runAiAction('TA正在斟酌你的心意……',()=>tryEdgeAi({mode:'romance',npc_id:id,action:'confess',message:line}),{silentToast:true});
    if(!r) return;
    const content=r?.content||r?.reason||'心意已经传达。';
    toast(content, r?.decision==='reject');
    detailCache.delete(id);
    closePersonModal();
    await loadBundle(true);
  }

  async function encounterAction(id, action) {
    if(!id) return;
    const r=await runAiAction('这段缘遇正在推演……',()=>tryEdgeAi({mode:'encounter',encounter_id:id,action}));
    if(!r) return;
    toast(r?.content||'缘遇已有结果。');
    await loadBundle(true);
  }

  async function companionAction(action) {
    const r=await runAiAction('道侣正在回应……',()=>tryEdgeAi({mode:'companion',action}));
    if(!r) return;
    toast(r?.content||'你与道侣之间有了新的经历。');
    await loadBundle(true);
  }

  function openExistingWorldNews() {
    // 绝不新造“九霄界闻”。直接切到当前游戏现有“市坊”首页，界闻就在该页。
    const market=document.querySelector('[data-mobile-tab="market"]');
    if(market) market.click();
    setTimeout(()=>{
      const heading=document.getElementById('worldEventsHeading');
      if(heading) heading.scrollIntoView({behavior:'smooth',block:'start'});
    },180);
  }

  function render() {
    const host=document.getElementById('npcSocialSection');
    if(!host) return;
    host.dataset.bTiandaoPerson=BUILD;
    const b=state.bundle||{people:[],encounters:[],romance:[],companion:null,counts:{}};
    let body='';
    if(state.loading&&!state.bundle) body='<div class="tp-empty big">正在推演九霄人物因果……</div>';
    else if(b.status==='unavailable') body=`<div class="tp-empty big">人物系统暂未读取成功。<br><small>${esc(b.error||'')}</small><br><button data-tp-retry>重新读取</button></div>`;
    else if(state.view==='home') body=homeHtml(b);
    else if(state.view==='encounters') body=encountersHtml(b);
    else if(state.view==='people') body=peopleHtml(b);
    else if(state.view==='romance') body=romanceHtml(b);
    else if(state.view==='companion') body=companionHtml(b);

    host.innerHTML=`<div class="panel-title tp-host-title"><h3>九霄人物</h3><span class="badge">缘遇 · 人物志 · 仙缘 · 道侣</span></div>
      <div id="bTiandaoPersonRoot" class="tp-root">${navTabs()}<div class="tp-content">${body}</div></div>`;
    const nav=document.querySelector('[data-mobile-tab="social"] span');
    if(nav) nav.textContent='人物';
    state.mounted=true;
  }

  function mount() {
    const host=document.getElementById('npcSocialSection');
    if(!host) return false;
    if(host.dataset.bTiandaoPerson!==BUILD) render();
    if(!state.bundle && !state.loading) loadBundle(false);
    return true;
  }

  function scheduleMount() {
    if (mountQueued) return;
    mountQueued = true;
    const run = () => {
      mountQueued = false;
      const host = document.getElementById('npcSocialSection');
      if (host && host.dataset.bTiandaoPerson !== BUILD) mount();
    };
    if (typeof requestAnimationFrame === 'function') requestAnimationFrame(run);
    else setTimeout(run, 0);
  }

  // 只在主程序真正替换/新建 social 容器时重新挂载；不再监听自己产生的每一次子节点变化。
  const appHost=document.getElementById('app');
  if(appHost) {
    const obs=new MutationObserver(records=>{
      for (const record of records) {
        for (const node of record.addedNodes) {
          if (node?.nodeType === 1 && (node.id === 'npcSocialSection' || node.querySelector?.('#npcSocialSection'))) {
            scheduleMount();
            return;
          }
        }
      }
    });
    obs.observe(appHost,{childList:true,subtree:true});
  }

  // 动态人物详情也统一走事件委托，避免“弹窗插入后按钮没有绑定”的问题。
  document.addEventListener('click',e=>{
    const close=e.target.closest?.('[data-tp-close-modal]');
    if(close){ e.preventDefault(); closePersonModal(); return; }

    const backdrop=e.target.closest?.('[data-tp-modal-backdrop]');
    if(backdrop && e.target===backdrop){ closePersonModal(); return; }

    const interactBtn=e.target.closest?.('[data-tp-interact]');
    if(interactBtn){ e.preventDefault(); e.stopPropagation(); interact(interactBtn.dataset.tpId,interactBtn.dataset.tpInteract); return; }

    const confessBtn=e.target.closest?.('[data-tp-confess]');
    if(confessBtn){ e.preventDefault(); e.stopPropagation(); confess(confessBtn.dataset.tpConfess); return; }

    const encounterBtn=e.target.closest?.('[data-tp-encounter]');
    if(encounterBtn){ e.preventDefault(); encounterAction(encounterBtn.dataset.tpEncounter,encounterBtn.dataset.tpEncounterAction); return; }

    const companionBtn=e.target.closest?.('[data-tp-companion-action]');
    if(companionBtn){ e.preventDefault(); companionAction(companionBtn.dataset.tpCompanionAction); return; }

    const filterBtn=e.target.closest?.('[data-tp-filter]');
    if(filterBtn){ state.peopleFilter=filterBtn.dataset.tpFilter||'all'; render(); return; }

    const viewBtn=e.target.closest?.('[data-tp-view]');
    if(viewBtn){ state.view=viewBtn.dataset.tpView; render(); return; }

    const personBtn=e.target.closest?.('[data-tp-person]');
    if(personBtn){ e.preventDefault(); e.stopPropagation(); openPerson(personBtn.dataset.tpPerson); return; }

    const worldBtn=e.target.closest?.('[data-tp-open-world-news]');
    if(worldBtn){ openExistingWorldNews(); return; }

    const retryBtn=e.target.closest?.('[data-tp-retry]');
    if(retryBtn){ loadBundle(true); return; }

    const mobileBtn=e.target.closest?.('[data-mobile-tab="social"]');
    if(mobileBtn) setTimeout(()=>{mount();loadBundle(false);},0);
  });

  document.addEventListener('keydown',e=>{
    if(e.key==='Escape' && document.querySelector('[data-tp-modal-backdrop]')) closePersonModal();
  });

  window.B_TIANDAO_PERSON_V06 = Object.freeze({
    build:BUILD,
    mount,
    refresh:()=>loadBundle(true),
    openPerson,
    setView:v=>{state.view=v;render();}
  });

  mount();
})();