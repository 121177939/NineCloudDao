/* 九霄问道 · B模块：完整天道人物 / 仙缘 / 道侣
 * 正式合并基线：V2.2.0 CACHE133 / SQL261
 * 目标：让NPC拥有每日生活、主动联系、人生事件线、情境互动、承诺与真正可读的共同记忆。
 * Cloudflare Workers AI 只负责人格与语言提案；数值、经济、关系和事件推进继续由服务端审核。
 */
(() => {
  'use strict';

  const BUILD = 'B-TIANDAO-PERSON-V08-CACHE133-REAL-AI-TALK';
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
    actionBusy: false,
    actionMenu: ''
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
    if (raw.includes('TIANDAO_INTERACTION_COOLDOWN')) return '你们刚刚才有过互动，先让这段对话沉淀一下。';
    if (raw.includes('TIANDAO_FREE_TALK_INVALID')) return '这次想说的话没有成功送到TA那里。';
    if (raw.includes('TIANDAO_STORY_NOT_FOUND') || raw.includes('TIANDAO_STORY_EXPIRED')) return '这件事已经发生了变化，重新打开人物看看吧。';
    if (raw.includes('TIANDAO_STORY_CHOICE_INVALID')) return '这个选择已经不再适用于当前情境。';
    if (raw.includes('TIANDAO_INBOX_NOT_FOUND') || raw.includes('TIANDAO_INBOX_EXPIRED')) return '这条传音已经失效。';
    if (raw.includes('TIANDAO_ROMANCE_DISABLED')) return '仙缘功能目前暂停。';
    if (raw.includes('TIANDAO_COMPANION_DISABLED')) return '道侣互动目前暂停。';
    if (raw.includes('TIANDAO_CONFESSION_REQUIREMENTS')) return '你们之间的好感、信任、亲密、情缘还不足以表明心意。';
    if (raw.includes('TIANDAO_CONFESSION_COOLDOWN')) return '这份心意刚刚已经传达，请给彼此一些时间。';
    if (raw.includes('TIANDAO_COMPANION_ALREADY_EXISTS')) return '你当前已经有正式道侣。';
    if (raw.includes('TIANDAO_COMPANION_ACTION_COOLDOWN')) return '刚刚已经与道侣互动过，请稍后再来。';
    if (raw.includes('TIANXU_ITEM_INSUFFICIENT')) return '灵石不足，无法准备这份心意。';
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
    toast.timer = setTimeout(() => t.className = 'toast', 4200);
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

  function timeAgo(v) {
    if (!v) return '';
    const d = new Date(v);
    if (Number.isNaN(d.getTime())) return '';
    const sec = Math.max(0, Math.floor((Date.now() - d.getTime()) / 1000));
    if (sec < 60) return '刚刚';
    if (sec < 3600) return `${Math.floor(sec / 60)}分钟前`;
    if (sec < 86400) return `${Math.floor(sec / 3600)}小时前`;
    return `${Math.floor(sec / 86400)}天前`;
  }

  async function loadBundle(force = false) {
    if (state.loading) return;
    if (!force && state.bundle && Date.now() - state.lastLoad < 30000) return;
    state.loading = true;
    render();
    try {
      const b = await rpc('get_tiandao_people_hub_v1', {});
      state.bundle = b || { people:[], encounters:[], inbox:[], stories:[], romance:[], companion:null, counts:{} };
      state.lastLoad = Date.now();
    } catch (e) {
      state.bundle = {
        status:'unavailable',
        error:String(e?.message || e),
        people:[], encounters:[], inbox:[], stories:[], romance:[], companion:null, counts:{}
      };
    } finally {
      state.loading = false;
      render();
    }
  }

  function navTabs() {
    const unread = Number(state.bundle?.counts?.unread || 0);
    const tabs = [
      ['home','总览'],['inbox',unread ? `来信 ${unread}` : '来信'],['encounters','缘遇'],['people','人物志'],['romance','仙缘'],['companion','道侣']
    ];
    return `<div class="tp-tabs">${tabs.map(([v,l]) =>
      `<button class="${state.view===v?'active':''}" data-tp-view="${v}" type="button">${esc(l)}</button>`
    ).join('')}</div>`;
  }

  function personCard(p, compact=false) {
    const stage = attitudeText(p);
    const status = p.active_story_title
      ? `正在经历：${p.active_story_title}`
      : (p.current_activity || p.latest_rumor || p.current_status || publicMood(p));
    return `<article class="tp-person-card ${p.is_companion?'is-companion':''}" data-tp-person="${esc(p.npc_id || p.npc_code)}">
      <div class="tp-person-avatar">${esc((p.name || '人').slice(-1))}</div>
      <div class="tp-person-main">
        <div class="tp-person-head"><strong>${esc(p.name || '未知')}</strong><em>${esc(stage)}</em></div>
        <p>${esc([p.realm_label,p.identity].filter(Boolean).join(' · ') || '九霄修士')}</p>
        ${compact ? '' : `<small>${p.mood_label ? `<b>${esc(p.mood_label)}</b> · ` : ''}${esc(status)}</small>`}
      </div>
      ${Number(p.unread_count||0) ? `<span class="tp-unread-dot">${fmt(p.unread_count)}</span>` : ''}
      <span class="tp-chevron">›</span>
    </article>`;
  }

  function storyCard(s, compact=false) {
    return `<article class="tp-story-card">
      <div class="tp-story-mark">事</div>
      <div class="tp-story-main">
        <span>${esc(s.npc_name || '')} · 第${Math.min(4,Number(s.stage||1))}阶段</span>
        <strong>${esc(s.title || '一件正在发生的事')}</strong>
        <p>${esc(s.current_summary || s.premise || '')}</p>
      </div>
      ${compact ? '' : `<button data-tp-person="${esc(s.npc_id)}">去看看</button>`}
    </article>`;
  }

  function inboxCard(m, compact=false) {
    const actions = Array.isArray(m.actions) ? m.actions : [];
    return `<article class="tp-inbox-card ${m.status==='unread'?'is-unread':''}">
      <div class="tp-inbox-head"><div><span>${m.status==='unread'?'新传音':'人物来信'}</span><strong>${esc(m.title || m.npc_name || '有人联系了你')}</strong></div><small>${esc(timeAgo(m.created_at))}</small></div>
      <p>${esc(m.content || '')}</p>
      ${compact ? `<button data-tp-inbox-person="${esc(m.message_id)}" data-tp-inbox-npc="${esc(m.npc_id)}">打开</button>` : `<div class="tp-inbox-actions">
        ${actions.map(a=>`<button data-tp-inbox-action="${esc(a.code)}" data-tp-inbox-id="${esc(m.message_id)}" data-tp-inbox-npc="${esc(m.npc_id)}">${esc(a.label||'回应')}</button>`).join('')}
        <button class="ghost" data-tp-inbox-person="${esc(m.message_id)}" data-tp-inbox-npc="${esc(m.npc_id)}">人物</button>
      </div>`}
    </article>`;
  }

  function homeHtml(b) {
    const c = b.counts || {};
    const inbox = (b.inbox || []).slice(0,2);
    const stories = (b.stories || []).slice(0,2);
    const people = (b.people || []).filter(x=>x.known_level!=='heard').slice(0,4);
    return `
      <section class="tp-hero tp-living-hero">
        <div><span>九霄人物</span><h3>他们有自己的日子，也会主动想起你</h3><p>每日状态、人生事件、主动传音、承诺、仙缘与共同往事会一起推动关系。</p></div>
        <div class="tp-count-orb"><strong>${fmt(c.known ?? (b.people||[]).length)}</strong><small>已结识</small></div>
      </section>
      <div class="tp-metric-grid tp-metric-grid-5">
        <button data-tp-view="inbox"><span>来信</span><strong>${fmt(c.unread||0)}</strong><small>未读</small></button>
        <button data-tp-view="encounters"><span>缘遇</span><strong>${fmt(c.encounters||0)}</strong><small>待回应</small></button>
        <button data-tp-view="people"><span>人物</span><strong>${fmt(c.known||0)}</strong><small>已结识</small></button>
        <button data-tp-view="romance"><span>仙缘</span><strong>${fmt(c.romance||0)}</strong><small>有缘之人</small></button>
        <button data-tp-view="companion"><span>道侣</span><strong>${b.companion?'1':'—'}</strong><small>${b.companion?'已结缘':'大道未定'}</small></button>
      </div>
      <section class="tp-block tp-now-block">
        <div class="tp-block-head"><div><span>有人主动找你</span><strong>不是每个人都会一直站在原地等你点击</strong></div><button data-tp-view="inbox">全部</button></div>
        ${inbox.length ? inbox.map(x=>inboxCard(x,true)).join('') : '<div class="tp-empty">今天暂时没有新的传音。关系越深、共同事件越多，NPC越可能主动联系你。</div>'}
      </section>
      <section class="tp-block">
        <div class="tp-block-head"><div><span>正在发生</span><strong>人物自己的生活不会因为你下线就永远停住</strong></div></div>
        ${stories.length ? stories.map(x=>storyCard(x)).join('') : '<div class="tp-empty">当前没有你已经卷入的人生事件。多和熟识之人相处，新的故事会自然出现。</div>'}
      </section>
      <section class="tp-block">
        <div class="tp-block-head"><div><span>人物近况</span><strong>同一个人今天和明天可能完全不是一种状态</strong></div><button data-tp-view="people">人物志</button></div>
        ${people.length ? people.map(x=>personCard(x,false)).join('') : '<div class="tp-empty">先通过缘遇真正认识一些人。</div>'}
      </section>
      ${b.companion ? `<section class="tp-block tp-companion-mini"><div class="tp-block-head"><div><span>我的道侣</span><strong>${esc(b.companion.name)}</strong></div><button data-tp-view="companion">进入</button></div>${personCard(b.companion,false)}</section>` : ''}
      <section class="tp-world-link"><div><span>九霄界闻</span><strong>NPC重大突破、宗门变动、结缘等仍进入游戏原有九霄界闻</strong></div><button data-tp-open-world-news type="button">前往界闻</button></section>
    `;
  }

  function inboxHtml(b) {
    const rows = b.inbox || [];
    return `<section class="tp-page-head"><span>人物来信</span><h3>他们也会主动想起你</h3><p>有人心情不好会来找你，有人遇到事情会问你，也有人只是路过某处忽然想起你。</p></section>
      <div class="tp-list">${rows.length ? rows.map(x=>inboxCard(x,false)).join('') : '<div class="tp-empty big">没有等待你的传音。不是每天都必须有人来找你，这样每一次主动才有意义。</div>'}</div>`;
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
    return `<section class="tp-page-head"><span>缘遇</span><h3>真正的相识，从发生事情开始</h3><p>战斗、坊市、宗门、修炼、世界事件与NPC主动传音，都可以产生缘遇。</p></section>
      <div class="tp-list">${rows.length ? rows.map(encounterCard).join('') : '<div class="tp-empty big">当前没有待处理缘遇。继续正常修行，人物会在你的游戏过程中出现。</div>'}</div>`;
  }

  function peopleHtml(b) {
    const rows=b.people || [];
    const heard=rows.filter(x=>x.known_level==='heard').length;
    const filtered=rows.filter(p=>{
      const stage=attitudeText(p);
      if(state.peopleFilter==='friend') return ['相识','熟识'].includes(stage);
      if(state.peopleFilter==='confidant') return ['知己','心有情愫','倾心','道侣'].includes(stage);
      if(state.peopleFilter==='story') return Boolean(p.active_story_title || Number(p.unread_count||0));
      if(state.peopleFilter==='enemy') return stage==='敌视';
      return true;
    });
    const filters=[['all','全部'],['story','有事找你'],['friend','故交'],['confidant','知己'],['enemy','敌对']];
    return `<section class="tp-page-head"><span>人物志</span><h3>已结识 ${fmt((b.counts||{}).known ?? rows.length)} · 听闻 ${fmt((b.counts||{}).heard ?? heard)}</h3><p>人物志不只记关系等级，也显示TA今天在做什么、有没有事情发生、有没有主动联系你。</p></section>
      <div class="tp-filter-row">${filters.map(([code,label])=>`<button class="${state.peopleFilter===code?'active':''}" data-tp-filter="${code}" type="button">${label}</button>`).join('')}</div>
      <div class="tp-list">${filtered.length?filtered.map(p=>personCard(p)).join(''):'<div class="tp-empty big">当前筛选下没有人物。</div>'}</div>`;
  }

  function romanceHtml(b) {
    const rows=(b.romance || []).filter(x=>!x.is_companion);
    return `<section class="tp-page-head romance"><span>仙缘</span><h3>情不是刷满一条进度条</h3><p>表明心意会综合好感、信任、亲密、敬重、守诺、情缘、仇恨以及NPC自己的经历与人格。</p></section>
      <div class="tp-list">${rows.length?rows.map(p=>`
        <article class="tp-romance-card">
          ${personCard(p,true)}
          <div class="tp-romance-copy"><span>${esc(attitudeText(p))}</span><p>${esc(p.current_activity ? `${p.mood_label||'今日'} · ${p.current_activity}` : publicMood(p))}</p></div>
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
      <div><span>我的道侣</span><h3>${esc(p.name)}</h3><p>${esc([p.realm_label,p.identity].filter(Boolean).join(' · '))}</p><small>${esc([p.mood_label,p.current_activity].filter(Boolean).join(' · '))}</small></div>
    </section>
    <section class="tp-block tp-companion-life"><div class="tp-block-head"><div><span>TA今天</span><strong>${esc(p.mood_detail || p.current_status || '正在过自己的日子')}</strong></div></div><p class="tp-body-copy">${esc(p.current_place ? `大概在${p.current_place}。` : '')}</p></section>
    <div class="tp-companion-actions">
      <button data-tp-companion-menu="message">传音</button>
      <button data-tp-companion-menu="gift">赠礼</button>
      <button data-tp-companion-menu="meeting">相约</button>
      <button data-tp-companion-action="joint_cultivation">共同修炼</button>
      <button data-tp-companion-action="protect">互为护道</button>
      <button data-tp-person="${esc(p.npc_id || p.npc_code)}">人物详情</button>
    </div>`;
  }

  function closePersonModal() {
    detailRequestSeq += 1;
    state.actionMenu = '';
    const root = document.getElementById('modalRoot');
    if (root) root.innerHTML = '';
  }

  function personLoadingHtml(id) {
    return `<div class="modal-backdrop tp-modal-backdrop" data-tp-modal-backdrop data-tp-modal-id="${esc(id)}">
      <section class="modal tp-person-modal tp-person-modal-loading" role="dialog" aria-modal="true" aria-busy="true">
        <button class="modal-close-button" data-tp-close-modal type="button" aria-label="关闭">×</button>
        <div class="tp-ai-wait"><span class="tp-ai-spinner" aria-hidden="true"></span><strong>正在读取TA今天的状态……</strong><small>人物正在过自己的生活，不只是读取一张关系卡。</small></div>
      </section>
    </div>`;
  }

  function relationProfileHtml(detail) {
    const p = detail.relationship_profile || {};
    const rows = [
      ['在意',p.affection],['信任',p.trust],['熟悉',p.intimacy],['敬重',p.respect],['人情',p.gratitude],['芥蒂',p.tension]
    ].filter(x=>x[1]);
    if (!rows.length) return '';
    return `<div class="tp-relation-profile">${rows.map(([k,v])=>`<div><span>${esc(k)}</span><strong>${esc(v)}</strong></div>`).join('')}</div>`;
  }

  function storyDetailHtml(story) {
    if (!story) return '';
    const promise = story.promise;
    return `<section class="tp-detail-section tp-story-detail">
      <div class="tp-section-title"><small>TA正在经历</small><span>第${Math.min(4,Number(story.stage||1))}/4阶段</span></div>
      <h4>${esc(story.title || '')}</h4>
      <p>${esc(story.current_summary || story.premise || '')}</p>
      ${promise ? `<div class="tp-promise"><b>你答应过TA</b><span>${esc(promise.title||'')}</span></div>` : ''}
      <div class="tp-story-choices">${(story.choices||[]).map(a=>`<button data-tp-choice-action="${esc(a.code)}" data-tp-choice-ref="${esc(story.story_id)}">${esc(a.label||'回应')}</button>`).join('')}</div>
    </section>`;
  }

  function actionMenuHtml(detail, kind) {
    if (!kind) return '';
    const costs = detail.interaction_costs || {};
    if (kind==='freeTalk') {
      return `<div class="tp-action-menu tp-talk-composer"><div class="tp-action-menu-head"><strong>你想亲自对${esc(detail.name||'TA')}说什么？</strong><button data-tp-action-menu-close>收起</button></div>
        <label class="tp-talk-input-wrap"><span>你的原话会交给TA本人理解</span><textarea class="tp-free-talk-input" maxlength="300" rows="4" placeholder="直接说你真正想说的话。TA会按自己的性格、心情、关系和经历具体回应，不一定顺着你。"></textarea><small>最多300字 · Ctrl/⌘ + Enter 送出</small></label>
        <div class="tp-talk-send-row"><button class="primary" data-tp-free-send type="button">送出这句话</button></div>
        <p class="tp-action-hint">Cloudflare AI 会优先生成具体回应；如果本次失败，结果页会明确标记“本地人格兜底”，不会伪装成 AI 成功。</p></div>`;
    }
    if (kind==='talk') {
      const rows = [
        ['talk:ask_current','问问近况','看看TA今天究竟怎么了'],
        ['talk:listen','认真听TA说','少说一点，先听'],
        ['talk:share_story','说说自己的经历','让TA也更了解你'],
        ['talk:seek_advice','请教TA擅长的事','不是所有关系都只靠好感'],
        ['talk:tease','开个轻松的玩笑','有的人吃这一套，有的人不吃'],
        ['talk:free','我想自己说一句','直接输入你真正想对TA说的话']
      ];
      return `<div class="tp-action-menu"><div class="tp-action-menu-head"><strong>这次想怎么聊？</strong><button data-tp-action-menu-close>收起</button></div>${rows.map(([code,label,hint])=>`<button data-tp-choice-action="${code}"><b>${label}</b><small>${hint}</small></button>`).join('')}</div>`;
    }
    if (kind==='gift') {
      const rows = [
        ['gift:practical','实用之物',costs.gift_practical],
        ['gift:cultivation','修行之物',costs.gift_cultivation],
        ['gift:elegant','风雅之礼',costs.gift_elegant],
        ['gift:rare','难得奇物',costs.gift_rare]
      ];
      return `<div class="tp-action-menu"><div class="tp-action-menu-head"><strong>送什么样的东西？</strong><button data-tp-action-menu-close>收起</button></div><p class="tp-action-hint">${esc(detail.gift_hint||'你还不清楚TA真正喜欢什么。')}</p>${rows.map(([code,label,cost])=>`<button data-tp-choice-action="${code}"><b>${label}</b><small>${cost!==undefined?`约 ${fmt(cost)} 灵石`:'按人物规则结算'}</small></button>`).join('')}</div>`;
    }
    if (kind==='meeting') {
      const rows = [
        ['meeting:market','去坊市走走','热闹、消息多，也容易碰见意外'],
        ['meeting:teahouse','找个安静地方坐坐','适合慢慢说话'],
        ['meeting:mountain','去山间看景','离开人群，换个环境'],
        ['meeting:practice','一起练一阵','对重修行的人更自然'],
        ['meeting:travel','去远一点的地方','把相约真正变成一段共同经历']
      ];
      return `<div class="tp-action-menu"><div class="tp-action-menu-head"><strong>想约TA去哪里？</strong><button data-tp-action-menu-close>收起</button></div>${rows.map(([code,label,hint])=>`<button data-tp-choice-action="${code}"><b>${label}</b><small>${hint}</small></button>`).join('')}</div>`;
    }
    return '';
  }

  function personDetailHtml(detail, id) {
    const life = detail.life || {};
    const memories = Array.isArray(detail.public_memories) ? detail.public_memories : [];
    const moments = Array.isArray(detail.recent_moments) ? detail.recent_moments : [];
    return `<div class="modal-backdrop tp-modal-backdrop" data-tp-modal-backdrop data-tp-modal-id="${esc(id)}"><section class="modal tp-person-modal" role="dialog" aria-modal="true">
      <button class="modal-close-button" data-tp-close-modal type="button" aria-label="关闭">×</button>
      <div class="tp-person-detail-head"><div class="tp-person-avatar big">${esc((detail.name||'人').slice(-1))}</div><div><span>${esc(detail.identity||'九霄修士')}</span><h3>${esc(detail.name)}</h3><p>${esc(detail.realm_label||'')}</p></div><em>${esc(attitudeText(detail))}</em></div>
      <section class="tp-detail-section tp-today"><div class="tp-section-title"><small>TA今天</small><span>${esc(life.mood_label||'平常')}</span></div><p class="tp-today-main">${esc(life.mood_detail || detail.current_status || '正在过自己的日子。')}</p><div class="tp-today-meta"><span>${esc(life.current_activity||'')}</span>${life.current_place?`<span>${esc(life.current_place)}</span>`:''}${life.current_need?`<span>${esc(life.current_need)}</span>`:''}</div></section>
      <section class="tp-detail-section"><small>TA怎么看你</small><p>${esc(publicMood(detail))}</p>${relationProfileHtml(detail)}</section>
      ${storyDetailHtml(detail.active_story)}
      ${detail.known_secret ? `<section class="tp-detail-section tp-secret"><small>TA只对你透露的事</small><p>${esc(detail.known_secret)}</p></section>` : ''}
      <section class="tp-detail-section"><div class="tp-section-title"><small>真正值得记住的往事</small><span>${memories.length}件</span></div><div class="tp-memory-list">${memories.slice(0,8).map(m=>`<p>· ${esc(m.content||m)}</p>`).join('')||'<p>你们还没有经历足以写进人物志的大事。</p>'}</div></section>
      ${moments.length ? `<details class="tp-small-moments"><summary>最近一些小事</summary><div>${moments.slice(0,4).map(m=>`<p>· ${esc(m.content||m)}</p>`).join('')}</div></details>` : ''}
      <div class="tp-detail-actions">
        <button data-tp-action-menu="talk" data-tp-id="${esc(id)}">交谈</button>
        <button data-tp-action-menu="gift" data-tp-id="${esc(id)}">赠礼</button>
        <button data-tp-action-menu="meeting" data-tp-id="${esc(id)}">相约</button>
        ${detail.can_confess ? `<button class="primary" data-tp-confess="${esc(id)}">表明心意</button>`:''}
      </div>
      <div class="tp-action-host" data-tp-action-host>${actionMenuHtml(detail,state.actionMenu)}</div>
      <div class="tp-action-status" data-tp-action-status hidden></div>
    </section></div>`;
  }

  function resultHtml(result, npcId, kind='interaction', options={}) {
    const content = result?.content || '这段因缘有了新的变化。';
    const applied = result?.applied || {};
    const playerMessage = String(options?.playerMessage || '').trim();
    const engine = String(result?.engine || '');
    const aiStatus = String(result?.ai_status || '');
    const cloudflare = engine==='cloudflare_workers_ai' || aiStatus==='Cloudflare';
    const model = String(result?.model || '').trim();
    const latency = Number(result?.ai_latency_ms || 0);
    let extra='';
    if (applied.gift_accepted===false) extra='TA没有收下礼物。这并不等于关系被清零。';
    else if (applied.preference_match===true) extra='这次选择刚好合TA心意。';
    if (applied.story_resolved===true) extra='这件事已经走到了一个真正的结果。';
    const engineNote = cloudflare
      ? `本次由 Cloudflare AI 生成人物回应${latency>0?` · ${fmt(latency)}ms`:''}${model?` · ${esc(model)}`:''}`
      : `本次 Cloudflare 未生成有效回复，已自动使用本地人格兜底${model?` · 目标模型 ${esc(model)}`:''}`;
    return `<div class="modal-backdrop tp-modal-backdrop" data-tp-modal-backdrop><section class="modal tp-result-modal" role="dialog" aria-modal="true">
      <button class="modal-close-button" data-tp-close-modal type="button" aria-label="关闭">×</button>
      <div class="tp-result-mark">${kind==='story'?'事':kind==='gift'?'礼':kind==='meeting'?'游':'言'}</div>
      ${playerMessage?`<div class="tp-chat-player"><small>你说</small><p>${esc(playerMessage)}</p></div>`:''}
      <span class="tp-result-kicker">TA的回应</span>
      <p class="tp-result-dialogue">${esc(content)}</p>
      <div class="tp-ai-engine ${cloudflare?'is-cloudflare':'is-fallback'}"><strong>${cloudflare?'Cloudflare AI':'本地人格兜底'}</strong><span>${engineNote}</span></div>
      ${extra?`<small>${esc(extra)}</small>`:''}
      <div class="tp-result-actions"><button class="primary" data-tp-result-person="${esc(npcId)}">继续看看TA</button><button data-tp-close-modal>先到这里</button></div>
    </section></div>`;
  }

  async function openPerson(id, force=false) {
    if(!id || state.actionBusy) return;
    const root=document.getElementById('modalRoot');
    if(!root) return;
    const cached = detailCache.get(id);
    if (!force && cached && Date.now() - cached.at < 30000) {
      state.selected = cached.data;
      state.actionMenu='';
      root.innerHTML = personDetailHtml(cached.data, id);
      return;
    }
    const seq = ++detailRequestSeq;
    root.innerHTML = personLoadingHtml(id);
    const detail = await tryRpc('get_tiandao_person_detail_v1',{p_npc_id:id});
    if (seq !== detailRequestSeq) return;
    if(detail?.__error || !detail) {
      closePersonModal();
      return toast(detail?.__error ? humanError(detail.__error) : '人物资料读取失败。',true);
    }
    detailCache.set(id, { at: Date.now(), data: detail });
    state.selected=detail;
    state.actionMenu='';
    root.innerHTML=personDetailHtml(detail,id);
  }

  function refreshPersonModal() {
    const root=document.getElementById('modalRoot');
    const id=state.selected?.npc_id;
    if(root && state.selected && id) root.innerHTML=personDetailHtml(state.selected,id);
  }

  function setActionBusy(busy, label='') {
    state.actionBusy = busy;
    const modal = document.querySelector('.tp-person-modal, .tp-result-modal');
    if (modal) {
      modal.classList.toggle('is-busy', busy);
      modal.querySelectorAll('button').forEach(btn => {
        if (!btn.matches('[data-tp-close-modal]')) btn.disabled = busy;
      });
      const status = modal.querySelector('[data-tp-action-status]');
      if (status) {
        status.hidden = !busy;
        status.innerHTML = busy ? `<span class="tp-ai-spinner" aria-hidden="true"></span><div><strong>${esc(label || 'TA正在思量……')}</strong><small>AI只负责TA怎么想、怎么说；关系数值与资源仍由服务端规则决定。</small></div>` : '';
      }
    }
    document.querySelectorAll('#bTiandaoPersonRoot button').forEach(btn => { if (!btn.matches('[data-tp-view],[data-tp-filter]')) btn.disabled = busy; });
  }

  async function runAiAction(label, task, options={}) {
    if (state.actionBusy) {
      toast('上一段人物因果仍在推演，请稍候。');
      return null;
    }
    setActionBusy(true, label);
    if (!options.silentToast) toast(label || 'TA正在思量……');
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

  async function performInteraction(id, action, ref='') {
    if(!id || !action) return;
    let message = ref || '';
    if(action==='talk:free') {
      message=String(ref||'').trim();
      if(!message) return toast('你还没有说出想说的话。');
      if(message.length>300) return toast('这次最多说300字。',true);
    }
    const family=String(action).split(':')[0];
    const label = family==='gift'?'TA正在看你准备的东西……':family==='meeting'?'TA正在考虑这次相约……':family==='story'?'这件事正在继续发生……':family==='inbox'?'TA正在看你的回应……':'TA正在听你说话……';
    const r=await runAiAction(label,()=>tryEdgeAi({mode:'interaction',npc_id:id,action,message}),{silentToast:true});
    if(!r) return;
    detailCache.delete(id);
    state.selected=null;
    state.actionMenu='';
    await loadBundle(true);
    const root=document.getElementById('modalRoot');
    if(root) root.innerHTML=resultHtml(r,id,family,{playerMessage:action==='talk:free'?message:''});
  }

  async function sendFreeTalk() {
    if (state.actionBusy) return;
    const id=state.selected?.npc_id;
    const input=document.querySelector('.tp-free-talk-input');
    const message=String(input?.value||'').trim();
    if(!id) return toast('人物资料已经变化，请重新打开。',true);
    if(!message) { input?.focus(); return toast('你还没有说出想说的话。'); }
    if(message.length>300) return toast('这次最多说300字。',true);
    await performInteraction(id,'talk:free',message);
  }

  async function confess(id) {
    if (state.actionBusy) return;
    const line=prompt('你想对TA说什么？','愿往后大道漫漫，与你同行。');
    if(line===null) return;
    const r=await runAiAction('TA正在斟酌你的心意……',()=>tryEdgeAi({mode:'romance',npc_id:id,action:'confess',message:line}),{silentToast:true});
    if(!r) return;
    detailCache.delete(id);
    await loadBundle(true);
    const root=document.getElementById('modalRoot');
    if(root) root.innerHTML=resultHtml(r,id,'romance');
  }

  async function encounterAction(id, action) {
    if(!id) return;
    const r=await runAiAction('这段缘遇正在推演……',()=>tryEdgeAi({mode:'encounter',encounter_id:id,action}));
    if(!r) return;
    await loadBundle(true);
    toast(r?.content||'缘遇已有结果。');
  }

  function companionMenu(kind) {
    const p=state.bundle?.companion;
    if(!p?.npc_id) return;
    const id=p.npc_id;
    if(kind==='message') {
      const line=prompt(`想给${p.name}传什么话？`,'今日修行可还顺利？');
      if(line===null || !String(line).trim()) return;
      companionAction('message:free',String(line).trim());
      return;
    }
    if(kind==='gift') {
      const choice=prompt('准备哪一类礼物？\n1 实用之物\n2 修行之物\n3 风雅之礼\n4 难得奇物','2');
      if(choice===null) return;
      const map={'1':'gift:practical','2':'gift:cultivation','3':'gift:elegant','4':'gift:rare'};
      if(!map[String(choice).trim()]) return toast('请输入 1、2、3 或 4。');
      companionAction(map[String(choice).trim()]);
      return;
    }
    if(kind==='meeting') {
      const choice=prompt('想和TA去哪里？\n1 坊市\n2 清静处\n3 山间\n4 一起练一阵\n5 去远一点的地方','2');
      if(choice===null) return;
      const map={'1':'meeting:market','2':'meeting:teahouse','3':'meeting:mountain','4':'meeting:practice','5':'meeting:travel'};
      if(!map[String(choice).trim()]) return toast('请输入 1 到 5。');
      companionAction(map[String(choice).trim()]);
      return;
    }
    openPerson(id);
  }

  async function companionAction(action, message='') {
    const r=await runAiAction('道侣正在回应……',()=>tryEdgeAi({mode:'companion',action,message}));
    if(!r) return;
    await loadBundle(true);
    const id=state.bundle?.companion?.npc_id;
    const root=document.getElementById('modalRoot');
    if(root && id) root.innerHTML=resultHtml(r,id,String(action).split(':')[0]);
    else toast(r?.content||'你与道侣之间有了新的经历。');
  }

  async function openInboxPerson(messageId, npcId) {
    if(messageId) await tryRpc('tiandao_people_mark_read_v260',{p_message_id:messageId});
    await loadBundle(true);
    openPerson(npcId,true);
  }

  async function inboxAction(messageId, npcId, action) {
    return performInteraction(npcId,action,messageId);
  }

  function openExistingWorldNews() {
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
    const b=state.bundle||{people:[],encounters:[],inbox:[],stories:[],romance:[],companion:null,counts:{}};
    let body='';
    if(state.loading&&!state.bundle) body='<div class="tp-empty big">正在读取人物今日生活与因果……</div>';
    else if(b.status==='unavailable') body=`<div class="tp-empty big">人物系统暂未读取成功。<br><small>${esc(b.error||'')}</small><br><button data-tp-retry>重新读取</button></div>`;
    else if(state.view==='home') body=homeHtml(b);
    else if(state.view==='inbox') body=inboxHtml(b);
    else if(state.view==='encounters') body=encountersHtml(b);
    else if(state.view==='people') body=peopleHtml(b);
    else if(state.view==='romance') body=romanceHtml(b);
    else if(state.view==='companion') body=companionHtml(b);

    host.innerHTML=`<div class="panel-title tp-host-title"><h3>九霄人物</h3><span class="badge">活人 · 因果 · 仙缘 · 道侣</span></div>
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

  document.addEventListener('click',e=>{
    const close=e.target.closest?.('[data-tp-close-modal]');
    if(close){ e.preventDefault(); closePersonModal(); return; }

    const backdrop=e.target.closest?.('[data-tp-modal-backdrop]');
    if(backdrop && e.target===backdrop){ closePersonModal(); return; }

    const resultPerson=e.target.closest?.('[data-tp-result-person]');
    if(resultPerson){ e.preventDefault(); openPerson(resultPerson.dataset.tpResultPerson,true); return; }

    const menuBtn=e.target.closest?.('[data-tp-action-menu]');
    if(menuBtn){
      e.preventDefault();e.stopPropagation();
      state.actionMenu=state.actionMenu===menuBtn.dataset.tpActionMenu?'':menuBtn.dataset.tpActionMenu;
      refreshPersonModal();return;
    }

    const menuClose=e.target.closest?.('[data-tp-action-menu-close]');
    if(menuClose){ e.preventDefault();state.actionMenu='';refreshPersonModal();return; }

    const freeSend=e.target.closest?.('[data-tp-free-send]');
    if(freeSend){ e.preventDefault();e.stopPropagation();sendFreeTalk();return; }

    const choice=e.target.closest?.('[data-tp-choice-action]');
    if(choice){
      e.preventDefault();e.stopPropagation();
      const id=state.selected?.npc_id || choice.closest?.('[data-tp-modal-id]')?.dataset.tpModalId;
      if(choice.dataset.tpChoiceAction==='talk:free'){
        state.actionMenu='freeTalk';refreshPersonModal();
        setTimeout(()=>document.querySelector('.tp-free-talk-input')?.focus(),0);return;
      }
      performInteraction(id,choice.dataset.tpChoiceAction,choice.dataset.tpChoiceRef||'');return;
    }

    const confessBtn=e.target.closest?.('[data-tp-confess]');
    if(confessBtn){ e.preventDefault(); e.stopPropagation(); confess(confessBtn.dataset.tpConfess); return; }

    const encounterBtn=e.target.closest?.('[data-tp-encounter]');
    if(encounterBtn){ e.preventDefault(); encounterAction(encounterBtn.dataset.tpEncounter,encounterBtn.dataset.tpEncounterAction); return; }

    const inboxBtn=e.target.closest?.('[data-tp-inbox-action]');
    if(inboxBtn){ e.preventDefault(); inboxAction(inboxBtn.dataset.tpInboxId,inboxBtn.dataset.tpInboxNpc,inboxBtn.dataset.tpInboxAction); return; }

    const inboxPerson=e.target.closest?.('[data-tp-inbox-person]');
    if(inboxPerson){ e.preventDefault(); openInboxPerson(inboxPerson.dataset.tpInboxPerson,inboxPerson.dataset.tpInboxNpc); return; }

    const companionMenuBtn=e.target.closest?.('[data-tp-companion-menu]');
    if(companionMenuBtn){ e.preventDefault(); companionMenu(companionMenuBtn.dataset.tpCompanionMenu); return; }

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
    if((e.ctrlKey||e.metaKey) && e.key==='Enter' && e.target?.matches?.('.tp-free-talk-input')){
      e.preventDefault();sendFreeTalk();return;
    }
    if(e.key==='Escape' && document.querySelector('[data-tp-modal-backdrop]')) closePersonModal();
  });

  window.B_TIANDAO_PERSON_V08 = Object.freeze({
    build:BUILD,
    mount,
    refresh:()=>loadBundle(true),
    openPerson,
    setView:v=>{state.view=v;render();}
  });

  mount();
})();
