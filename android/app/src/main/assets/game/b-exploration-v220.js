/* 九霄问道 · B模块：九霄游历 V1
 * V2.2.0 CACHE134 / SQL262
 * 300条正式故事：240境界专属 + 60跨境界长线。
 * 状态、奖励、战斗结算、人物关系与故事推进全部由服务端 RPC 权威处理。
 */
(() => {
  'use strict';

  const BUILD = 'B-EXPLORATION-V01-CACHE134-SQL262-300-STORIES';
  const cfg = window.GAME_CONFIG || {};
  const BASE = String(cfg.supabaseUrl || '').replace(/\/+$/, '');
  const KEY = String(cfg.supabasePublishableKey || '');
  const PROJECT_REF = (() => { try { return new URL(BASE).hostname.split('.')[0]; } catch { return 'unknown'; } })();
  const SESSION_KEY = `nine_cloud_dao_session_${PROJECT_REF}_v1`;
  const DEVICE_KEY = `nine_cloud_dao_device_${PROJECT_REF}_v1`;

  const state = {
    bundle: null,
    loading: false,
    busy: false,
    view: 'world',
    lastOutcome: null,
    lastLoad: 0
  };

  const esc = value => String(value ?? '')
    .replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;')
    .replaceAll('"','&quot;').replaceAll("'",'&#039;');
  const fmt = value => Number(value || 0).toLocaleString('zh-CN');

  function session() {
    try { return JSON.parse(localStorage.getItem(SESSION_KEY) || 'null'); } catch { return null; }
  }
  function deviceId() { return localStorage.getItem(DEVICE_KEY) || ''; }

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
      const err = new Error(data?.message || data?.error || data?.msg || `HTTP ${res.status}`);
      err.status = res.status; err.payload = data; throw err;
    }
    return Array.isArray(data) ? (data[0] ?? null) : data;
  }

  function humanError(error) {
    const raw = String(error?.message || error || '');
    if (raw.includes('AUTH_REQUIRED')) return '登录状态已失效，请重新登录。';
    if (raw.includes('EXPLORATION_MAJOR_INJURY_REST_REQUIRED')) return '你现在伤势太重，先休养一阵再出去。';
    if (raw.includes('EXPLORATION_DAILY_LIMIT')) return '今日游历次数已经用完。';
    if (raw.includes('EXPLORATION_REGION_REALM_LOCKED')) return '以你当前境界，还不足以长期踏足这里。';
    if (raw.includes('EXPLORATION_STORY_REALM_GATE')) return '这条旧缘已经走到当前境界能理解的尽头，突破后再回来。';
    if (raw.includes('EXPLORATION_REGION_STORIES_EXHAUSTED')) return '这个境界在此地暂时没有新的故事可遇。';
    if (raw.includes('EXPLORATION_RUN_NOT_ACTIVE')) return '这次游历已经结束，重新看看当前游历状态。';
    if (raw.includes('EXPLORATION_CHOICE_INVALID')) return '眼前的局面已经变化，这个选择不再成立。';
    if (raw.includes('EXPLORATION_DISABLED')) return '九霄游历目前暂停。';
    if (raw.includes('Could not find the function') || raw.includes('get_exploration_hub_v262')) return '九霄游历需要先执行 SQL262。';
    return raw || '游历推演失败，请稍后重试。';
  }

  function toast(message, error = false) {
    const el = document.getElementById('toast');
    if (!el) return;
    el.textContent = message;
    el.className = `toast show ${error ? 'error' : ''}`;
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => { el.className = 'toast'; }, 4200);
  }

  function modeLabel(mode) {
    return ({ wander:'游历', investigate:'调查', track:'追踪', revisit:'回访' })[mode] || '游历';
  }
  function rarityLabel(rarity) {
    return ({ common:'寻常', uncommon:'少见', rare:'稀有', epic:'传说' })[rarity] || '未知';
  }
  function dangerHtml(level) {
    const n = Math.max(0, Math.min(5, Number(level || 0)));
    return `<span class="jxexp-danger" aria-label="危险等级${n}">${Array.from({length:5},(_,i)=>`<i class="${i<n?'on':''}"></i>`).join('')}</span>`;
  }
  function remainingTime(iso) {
    const end = new Date(iso || 0).getTime();
    const ms = end - Date.now();
    if (!Number.isFinite(ms) || ms <= 0) return '即将恢复';
    const m = Math.ceil(ms / 60000);
    if (m < 60) return `${m}分钟`;
    const h = Math.floor(m / 60), mm = m % 60;
    return `${h}小时${mm ? mm+'分' : ''}`;
  }

  function outcomeHtml() {
    const o = state.lastOutcome;
    if (!o) return '';
    const battle = o.battle && Object.keys(o.battle).length ? o.battle : null;
    const won = battle?.won === true;
    const battleText = battle ? `
      <div class="jxexp-outcome-battle ${won ? 'win' : 'lose'}">
        <b>${won ? '交锋胜利' : '交锋败退'}</b>
        <span>${esc(battle.enemy_name || '游历中的敌手')}</span>
        <small>胜算 ${Math.round(Number(battle.win_probability || 0) * 100)}% · 敌手威胁 ${esc(battle.danger_level || 0)}</small>
      </div>` : '';
    const settlement = Number(o.settled_spirit_stones || 0);
    return `
      <div class="jxexp-outcome">
        <div class="jxexp-outcome-head"><b>刚刚发生</b><button type="button" data-jxexp-dismiss>×</button></div>
        <p>${esc(o.summary || (o.status === 'continued' ? '你继续向前。' : '这一步有了结果。'))}</p>
        ${battleText}
        ${settlement ? `<div class="jxexp-settlement">安全带回 <b>${fmt(settlement)}</b> 灵石</div>` : ''}
        ${o.injury ? `<div class="jxexp-injury-mini">${o.injury.severity === 'major' ? '重伤' : '负伤'} · 约需休养 ${fmt(o.injury.minutes)} 分钟</div>` : ''}
        ${o.new_discovery ? `<div class="jxexp-discovery-mini">你记录下了一项新的发现。</div>` : ''}
      </div>`;
  }

  function activeRunHtml(run) {
    if (!run?.run_id || !run?.node) return '';
    const n = run.node;
    const choices = Array.isArray(n.choices) ? n.choices : [];
    return `
      <section class="jxexp-run-card">
        <div class="jxexp-run-kicker">
          <span>${esc(n.region_name || run.region_code || '')} · ${esc(modeLabel(run.mode))}</span>
          <span>${n.is_cross_realm ? '跨境界旧缘' : `${esc(rarityLabel(n.rarity))}故事`}</span>
        </div>
        <h4>${esc(n.title || '无名游历')}</h4>
        <div class="jxexp-stage-row">
          <span>第 ${fmt(n.stage)} / ${fmt(n.stage_count)} 阶段</span>
          ${dangerHtml(n.danger_level)}
        </div>
        <p class="jxexp-story-text">${esc(n.description || '')}</p>
        <div class="jxexp-bag-row">
          <span>旅囊：<b>${fmt(run.pending_spirit_stones)}</b> 灵石 <em>（尚未安全结算）</em></span>
          <span>本次见闻：<b>${fmt(run.insight_gained)}</b></span>
        </div>
        <div class="jxexp-choice-grid">
          ${choices.map(c => `<button type="button" class="jxexp-choice ${c.code === 'fight' || c.code === 'force' || c.code === 'harvest_greedy' ? 'danger' : ''}" data-jxexp-choice="${esc(c.code)}" data-run-id="${esc(run.run_id)}" ${state.busy?'disabled':''}>
            <b>${esc(c.label || c.code)}</b><small>${esc(c.hint || '')}</small>
          </button>`).join('')}
        </div>
        <div class="jxexp-retreat-note">你可以随时见好就收。选择“安全退出”会把旅囊结算回去；被击败则只保住一部分。</div>
      </section>`;
  }

  function injuryHtml(injury) {
    if (!injury) return '';
    return `<div class="jxexp-injury ${injury.severity === 'major' ? 'major' : ''}">
      <b>${esc(injury.label || '游历负伤')}</b>
      <span>${esc(injury.detail || '')}</span>
      <small>预计 ${esc(remainingTime(injury.expires_at))} 后恢复${injury.severity === 'major' ? ' · 重伤期间不能开始新游历' : ''}</small>
    </div>`;
  }

  function regionsHtml(bundle) {
    const regions = Array.isArray(bundle?.regions) ? bundle.regions : [];
    const disabled = state.busy || Number(bundle?.daily_remaining || 0) <= 0 || bundle?.injury?.severity === 'major';
    return `<div class="jxexp-region-list">
      ${regions.map(r => `
        <article class="jxexp-region ${r.unlocked ? '' : 'locked'}">
          <div class="jxexp-region-head">
            <div><h4>${esc(r.name)}</h4><small>${r.unlocked ? `熟悉度 ${fmt(r.familiarity)} · 当前可遇 ${fmt(r.unseen)} 条` : `需大境界第 ${fmt(r.min_major_order)} 阶`}</small></div>
            <span>${r.unlocked ? '可前往' : '未解锁'}</span>
          </div>
          <p>${esc(r.description)}</p>
          ${r.unlocked ? `<div class="jxexp-mode-grid">
            <button type="button" data-jxexp-start="wander" data-region="${esc(r.region_code)}" ${disabled?'disabled':''}><b>游历</b><small>不知道会遇到什么</small></button>
            <button type="button" data-jxexp-start="investigate" data-region="${esc(r.region_code)}" ${disabled?'disabled':''}><b>调查</b><small>寻找遗迹、异象与秘密</small></button>
            <button type="button" data-jxexp-start="track" data-region="${esc(r.region_code)}" ${disabled?'disabled':''}><b>追踪</b><small>主动寻找妖兽与痕迹</small></button>
            <button type="button" data-jxexp-start="revisit" data-region="${esc(r.region_code)}" ${disabled?'disabled':''}><b>回访</b><small>重回曾经留下痕迹的地方</small></button>
          </div>` : ''}
        </article>`).join('')}
    </div>`;
  }

  function worldHtml(bundle) {
    const c = bundle?.character || {};
    const p = bundle?.profile || {};
    const run = bundle?.active_run;
    return `
      ${outcomeHtml()}
      <div class="jxexp-hero">
        <div>
          <span class="jxexp-eyebrow">九霄游历 · ${esc(c.realm_name || '凡尘')}</span>
          <h3>今天出去看看，会遇见什么？</h3>
          <p>${esc(bundle?.realm_theme || '')}</p>
        </div>
        <div class="jxexp-daily"><b>${fmt(bundle?.daily_remaining)}</b><small>/ ${fmt(bundle?.daily_limit)} 次今日剩余</small></div>
      </div>
      <div class="jxexp-stats">
        <div><b>${fmt(bundle?.story_total)}</b><span>正式故事</span></div>
        <div><b>${fmt(bundle?.cross_realm_total)}</b><span>跨境界长线</span></div>
        <div><b>${fmt(p.insight)}</b><span>见闻</span></div>
        <div><b>${fmt(p.discoveries)}</b><span>发现</span></div>
      </div>
      ${injuryHtml(bundle?.injury)}
      ${run ? activeRunHtml(run) : `
        <div class="jxexp-no-run">
          <b>当前没有进行中的游历</b>
          <span>每次会进入一条多阶段故事。战利品先放进旅囊，安全返回才真正结算。</span>
        </div>
        ${regionsHtml(bundle)}`}
    `;
  }

  function journalHtml(bundle) {
    const discoveries = Array.isArray(bundle?.discoveries) ? bundle.discoveries : [];
    const journal = Array.isArray(bundle?.journal) ? bundle.journal : [];
    return `
      <div class="jxexp-journal-intro">
        <b>游历志</b><span>只记真正发生过的发现、败退、旧缘与故事结果，不把每次点击堆成流水账。</span>
      </div>
      <h4 class="jxexp-subtitle">已发现地点与秘密</h4>
      <div class="jxexp-discovery-list">
        ${discoveries.length ? discoveries.map(d => `<article><b>${esc(d.title)}</b><small>${esc(d.region_name || '')}${Number(d.times_seen||1)>1 ? ` · 回访${fmt(d.times_seen)}次` : ''}</small><p>${esc(d.detail || '')}</p></article>`).join('') : '<div class="jxexp-empty">你还没有留下值得回访的发现。</div>'}
      </div>
      <h4 class="jxexp-subtitle">最近经历</h4>
      <div class="jxexp-log-list">
        ${journal.length ? journal.map(j => `<article class="imp-${Math.min(5,Number(j.importance||1))}"><b>${esc(j.title)}</b><p>${esc(j.content)}</p><small>${new Date(j.created_at).toLocaleString('zh-CN')}</small></article>`).join('') : '<div class="jxexp-empty">你的游历志还是空的。</div>'}
      </div>`;
  }

  function render() {
    const root = document.getElementById('bExplorationRoot');
    if (!root) return;
    if (state.loading && !state.bundle) {
      root.innerHTML = '<div class="empty-state">正在展开九霄山河……</div>';
      return;
    }
    if (!state.bundle) {
      root.innerHTML = '<div class="empty-state">九霄游历尚未就绪。先执行 SQL262，再重新进入此页。</div>';
      return;
    }
    root.innerHTML = `
      <div class="jxexp-root" data-build="${BUILD}">
        <div class="jxexp-tabs">
          <button type="button" class="${state.view==='world'?'active':''}" data-jxexp-view="world">山河</button>
          <button type="button" class="${state.view==='journal'?'active':''}" data-jxexp-view="journal">游历志</button>
          <button type="button" data-jxexp-refresh ${state.loading?'disabled':''}>刷新</button>
        </div>
        ${state.view === 'journal' ? journalHtml(state.bundle) : worldHtml(state.bundle)}
      </div>`;
  }

  async function load(force = false) {
    const root = document.getElementById('bExplorationRoot');
    if (!root) return null;
    if (state.loading) return state.bundle;
    if (!force && state.bundle && Date.now() - state.lastLoad < 15000) { render(); return state.bundle; }
    state.loading = true; render();
    try {
      state.bundle = await rpc('get_exploration_hub_v262');
      state.lastLoad = Date.now();
      return state.bundle;
    } catch (error) {
      state.bundle = null;
      root.innerHTML = `<div class="empty-state">${esc(humanError(error))}</div>`;
      return null;
    } finally {
      state.loading = false; render();
    }
  }

  async function start(regionCode, mode) {
    if (state.busy) return;
    state.busy = true; render();
    try {
      const result = await rpc('exploration_start_v262', { p_region_code: regionCode, p_mode: mode });
      state.lastOutcome = { status:'started', summary:`你进入${modeLabel(mode)}状态，新的游历已经开始。` };
      await load(true);
      toast('游历开始。先看清局面，再决定要不要把风险压上去。');
      return result;
    } catch (error) {
      toast(humanError(error), true);
    } finally {
      state.busy = false; render();
    }
  }

  async function choose(runId, code) {
    if (state.busy) return;
    state.busy = true; render();
    try {
      const result = await rpc('exploration_choose_v262', { p_run_id: runId, p_choice_code: code });
      state.lastOutcome = result;
      await load(true);
      const msg = ({completed:'这段经历已经成为你的游历记录。',paused:'这条旧缘要等你突破后再继续。',defeated:'你败下阵来，先活着回来更重要。',retreated:'你见好就收，安全返回。',failed:'这次冒进付出了代价。',continued:'你继续向故事深处走去。'})[result?.status] || '这一步有了结果。';
      toast(msg, result?.status === 'defeated' || result?.status === 'failed');
      window.dispatchEvent(new CustomEvent('jiuxiao:exploration-changed', { detail: result || {} }));
    } catch (error) {
      toast(humanError(error), true);
    } finally {
      state.busy = false; render();
    }
  }

  document.addEventListener('click', event => {
    const view = event.target.closest('[data-jxexp-view]');
    if (view) { state.view = view.dataset.jxexpView || 'world'; render(); return; }
    if (event.target.closest('[data-jxexp-refresh]')) { load(true); return; }
    if (event.target.closest('[data-jxexp-dismiss]')) { state.lastOutcome = null; render(); return; }
    const startBtn = event.target.closest('[data-jxexp-start]');
    if (startBtn) { start(startBtn.dataset.region || '', startBtn.dataset.jxexpStart || 'wander'); return; }
    const choice = event.target.closest('[data-jxexp-choice]');
    if (choice) { choose(choice.dataset.runId || '', choice.dataset.jxexpChoice || ''); }
  });

  window.addEventListener('jiuxiao:exploration-rendered', () => { load(false); });
  window.addEventListener('jiuxiao:exploration-refresh', () => { load(true); });

  window.B_EXPLORATION_V262 = { build: BUILD, refresh: () => load(true), mount: () => load(false) };
  if (document.getElementById('bExplorationRoot')) load(false);
})();
