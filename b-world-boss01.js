(() => {
  'use strict';

  const MODULE = 'B-WBOSS01-TEAM-PVE-R1-A-V210';
  const config = window.GAME_CONFIG || {};
  const baseUrl = String(config.supabaseUrl || '').replace(/\/+$/, '');
  const apiKey = String(config.supabasePublishableKey || '');
  const projectRef = (() => { try { return new URL(baseUrl).hostname.split('.')[0]; } catch { return 'unknown'; } })();
  const sessionKey = `nine_cloud_dao_session_${projectRef}_v1`;
  const deviceKey = `nine_cloud_dao_device_${projectRef}_v1`;

  const state = {
    data: null,
    loading: false,
    busy: false,
    mounted: false,
    lastFetchAt: 0,
    playbackTimer: null,
    playbackIndex: 0,
    playbackSpeed: 1
  };

  const esc = value => String(value ?? '')
    .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;').replaceAll("'", '&#039;');
  const uuid = () => globalThis.crypto?.randomUUID?.() || 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const v = Math.random() * 16 | 0; return (c === 'x' ? v : (v & 3 | 8)).toString(16);
  });
  const num = (value, fallback = 0) => Number.isFinite(Number(value)) ? Number(value) : fallback;
  const fmt = value => num(value).toLocaleString('zh-CN', { maximumFractionDigits: 2 });
  const pct = value => `${Math.max(0, num(value) * 100).toLocaleString('zh-CN', { maximumFractionDigits: 1 })}%`;
  const session = () => { try { return JSON.parse(localStorage.getItem(sessionKey) || 'null'); } catch { return null; } };

  function toast(message, type = 'success') {
    const element = document.getElementById('toast');
    if (!element) return;
    element.textContent = message;
    element.className = `toast show ${type}`;
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => { element.className = 'toast'; }, 4200);
  }

  function errorText(error) {
    const raw = String(error?.message || error || '世界BOSS操作失败');
    const map = [
      ['BWBOSS01_DISABLED', '世界BOSS当前处于维护状态。'],
      ['BWBOSS01_EVENT_CLOSED', '当前不在世界BOSS开放时段。'],
      ['BWBOSS01_YUANYING_REQUIRED', '达到元婴境后才能参与世界BOSS。'],
      ['BWBOSS01_PARTY_NOT_FOUND', '没有找到当前队伍。'],
      ['BWBOSS01_PARTY_FULL', '队伍已满三人。'],
      ['BWBOSS01_REALM_MISMATCH', '正式队伍成员必须属于同一大境界。'],
      ['BWBOSS01_ALREADY_IN_PARTY', '你已经加入一个世界BOSS队伍。'],
      ['BWBOSS01_NOT_LEADER', '只有队长可以开始挑战。'],
      ['BWBOSS01_MEMBERS_NOT_READY', '队伍中仍有成员未准备。'],
      ['BWBOSS01_INVALID_JOIN_CODE', '队伍口令不存在或已经失效。'],
      ['BWBOSS01_PARTY_LOCKED', '当前队伍已经进入挑战，不能再修改成员。'],
      ['BWBOSS01_SNAPSHOT_UNAVAILABLE', '当前角色战斗快照不可用，请先刷新元神战斗属性。'],
      ['BWBOSS01_REQUEST_ID_REQUIRED', '请求编号缺失，请刷新后重试。'],
      ['BWBOSS01_DATABASE_NOT_READY', '世界BOSS数据库模块尚未安装。'],
      ['AUTH_REQUIRED', '请先登录游戏。'],
      ['PGRST202', '世界BOSS RPC尚未部署或API缓存尚未刷新。'],
      ['Could not find the function', '世界BOSS RPC尚未部署或API缓存尚未刷新。']
    ];
    return (map.find(([code]) => raw.includes(code)) || [])[1] || raw;
  }

  async function rpc(name, body = {}) {
    const active = session();
    if (!active?.access_token) throw new Error('AUTH_REQUIRED');
    const response = await fetch(`${baseUrl}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: {
        apikey: apiKey,
        Authorization: `Bearer ${active.access_token}`,
        'Content-Type': 'application/json',
        'X-Game-Session-Id': localStorage.getItem(deviceKey) || ''
      },
      body: JSON.stringify(body)
    });
    const text = await response.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch { data = text; }
    if (!response.ok) throw new Error(data?.message || data?.error || `HTTP ${response.status}`);
    return Array.isArray(data) ? data[0] || null : data;
  }

  function root() { return document.getElementById('worldBossRootBWorldBoss01'); }
  function difficultyName(code) { return code === 'hard' ? '困难' : '普通'; }
  function strategyName(code) {
    return ({ assault:'强攻', balanced:'均衡', guard:'守御', mechanic:'机制优先' }[code] || '均衡');
  }
  function elementName(code) {
    return ({ metal:'金', wood:'木', water:'水', fire:'火', earth:'土' }[code] || code || '未定');
  }
  function time(value) {
    const d = value ? new Date(value) : null;
    return d && !Number.isNaN(d.getTime()) ? d.toLocaleString('zh-CN', { month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hour12:false }) : '—';
  }

  function ensureSurface() {
    const dashboard = document.querySelector('.dashboard-reforge');
    const secret = document.getElementById('secretRealmSection');
    if (!dashboard || !secret) return false;

    let section = document.getElementById('worldBossSection');
    if (!section) {
      section = document.createElement('section');
      section.id = 'worldBossSection';
      section.className = 'panel world-boss-panel-bwboss01';
      section.dataset.mobileScreen = 'world_boss';
      section.innerHTML = `
        <div class="panel-title"><h3>世界BOSS</h3><span class="badge">元婴开放 · 1—3人 · 自动团队战</span></div>
        <div id="worldBossRootBWorldBoss01"><div class="empty-state">正在感应九幽魔息……</div></div>`;
      secret.insertAdjacentElement('afterend', section);
    }

    // V2.1.1由主程序正式提供“世 / 世界”底部导航，不再动态注入重复按钮。
    const tabbedMode = window.matchMedia('(max-width: 760px), (min-width: 1024px)').matches;
    const active = document.querySelector('.mobile-tab-button.active')?.dataset.mobileTab;
    if (tabbedMode && active !== 'world_boss') section.classList.add('mobile-screen-hidden');
    state.mounted = true;
    return true;
  }

  function openWorldBossTab(shouldScroll = false) {
    ensureSurface();
    const tabbedMode = window.matchMedia('(max-width: 760px), (min-width: 1024px)').matches;
    document.body.classList.remove('sect-focus-mode');
    document.querySelector('.dashboard-reforge')?.classList.remove('sect-focus-mode');
    document.querySelectorAll('[data-mobile-screen]').forEach(screen => {
      screen.classList.toggle('mobile-screen-hidden', tabbedMode && screen.dataset.mobileScreen !== 'world_boss');
    });
    document.querySelectorAll('.mobile-tab-button').forEach(button => button.classList.toggle('active', button.dataset.mobileTab === 'world_boss'));
    const button = document.querySelector('[data-mobile-tab="world_boss"]');
    const page = button?.closest('.mobile-bottom-nav-page');
    const viewport = document.querySelector('.mobile-bottom-nav-viewport');
    const pages = Array.from(document.querySelectorAll('.mobile-bottom-nav-page'));
    if (tabbedMode && page && viewport) {
      const index = Math.max(0, pages.indexOf(page));
      requestAnimationFrame(() => viewport.scrollTo({ left: index * viewport.clientWidth, behavior: shouldScroll ? 'smooth' : 'auto' }));
      document.querySelectorAll('.mobile-bottom-nav-pager i').forEach((dot, i) => dot.classList.toggle('active', i === index));
    }
    if (shouldScroll) window.scrollTo({ top: 0, behavior: 'smooth' });
    refresh(Date.now() - state.lastFetchAt > 5000);
  }

  function eventHeader(data) {
    const event = data?.event || {};
    const progress = Math.max(0, Math.min(100, num(event.progress_percent)));
    const status = event.status === 'echo' ? '残影挑战' : event.status === 'open' ? '镇压进行中' : '未开放';
    return `
      <section class="world-boss-hero-bwboss01">
        <div class="world-boss-crest-bwboss01"><span>土</span></div>
        <div class="world-boss-hero-copy-bwboss01">
          <small>B-WBOSS01 · 每日世界劫难</small>
          <h4>${esc(event.boss_name || '九幽吞天兽')}</h4>
          <p>${esc(event.form_name || '九幽吞天兽·境界投影')} · ${status}</p>
          <div class="world-boss-progress-bwboss01"><i style="width:${progress}%"></i></div>
          <div class="world-boss-progress-copy-bwboss01"><span>全服镇压 ${fmt(progress)}%</span><span>${time(event.ends_at)} 结束</span></div>
        </div>
        <button class="secondary-btn" type="button" data-wboss-refresh>刷新</button>
      </section>`;
  }

  function unavailableHtml(data) {
    return `<div class="world-boss-unavailable-bwboss01"><span>魔</span><h4>${esc(data?.title || '世界BOSS尚未开启')}</h4><p>${esc(data?.error || data?.blocked_reason || '请等待下一次世界劫难。')}</p><button class="secondary-btn" type="button" data-wboss-refresh>重新感应</button></div>`;
  }

  function noPartyHtml(data) {
    return `
      <div class="world-boss-callout-bwboss01"><strong>1—3人均可挑战</strong><p>同一队伍必须属于同一大境界。单人、双人、三人会使用不同BOSS缩放；不会按照装备战力实时追平。</p></div>
      <div class="world-boss-create-grid-bwboss01">
        <article><span>普通</span><strong>8分钟目标战</strong><p>完整机制的标准容错版，适合作为每日主要挑战。</p><button class="primary-btn" type="button" data-wboss-create="normal">创建普通队伍</button></article>
        <article><span>困难</span><strong>10分钟目标战</strong><p>BOSS生机、道攻、道御与机制压力提高，镇魔令奖励更多。</p><button class="primary-btn" type="button" data-wboss-create="hard">创建困难队伍</button></article>
      </div>
      <form id="worldBossJoinFormBWorldBoss01" class="world-boss-join-bwboss01">
        <label>加入好友队伍<input name="joinCode" maxlength="6" autocomplete="off" placeholder="输入6位队伍口令" required></label>
        <button class="secondary-btn" type="submit">加入队伍</button>
      </form>
      <div class="world-boss-rule-grid-bwboss01">
        <span><b>开放</b>元婴及以上</span><span><b>人数</b>1—3人</span><span><b>基础奖励</b>不限正式次数</span><span><b>珍稀奖励</b>每日前3次胜利判定</span><span><b>战斗</b>服务端自动结算</span>
      </div>`;
  }

  function memberCard(member, mineId) {
    const isMine = String(member.character_id || '') === String(mineId || '');
    return `<article class="world-boss-member-bwboss01 ${member.ready ? 'ready' : ''} ${isMine ? 'mine' : ''}">
      <div><small>${member.position === 1 ? '前位' : member.position === 2 ? '中位' : '后位'}${member.is_leader ? ' · 队长' : ''}</small><strong>${esc(member.name || '无名修士')}</strong><p>${esc(member.realm_name || '')} · ${esc(member.element_name || elementName(member.element))}行 · ${strategyName(member.strategy)}</p></div>
      <span>${member.ready ? '已准备' : '未准备'}</span>
    </article>`;
  }

  function partyHtml(data) {
    const party = data.party || {};
    const members = Array.isArray(party.members) ? party.members : [];
    const me = members.find(row => row.is_self) || {};
    const allReady = members.length > 0 && members.every(row => row.ready);
    return `
      <section class="world-boss-party-head-bwboss01">
        <div><small>${difficultyName(party.difficulty)} · ${esc(party.realm_name || '当前大境界')}</small><strong>队伍口令 ${esc(party.join_code || '—')}</strong><p>成员 ${members.length}/3 · 人数不足三人也可以开始，BOSS会按人数缩放。</p></div>
        <div><button class="secondary-btn" type="button" data-wboss-copy-code="${esc(party.join_code || '')}">复制口令</button><button class="danger-btn" type="button" data-wboss-leave>离队</button></div>
      </section>
      <div class="world-boss-members-bwboss01">${members.map(row => memberCard(row, me.character_id)).join('')}</div>
      <section class="world-boss-ready-bwboss01">
        <label>我的自动战斗策略<select id="worldBossStrategyBWorldBoss01">
          <option value="assault" ${me.strategy === 'assault' ? 'selected' : ''}>强攻 · 优先输出</option>
          <option value="balanced" ${!me.strategy || me.strategy === 'balanced' ? 'selected' : ''}>均衡 · 低生机转守</option>
          <option value="guard" ${me.strategy === 'guard' ? 'selected' : ''}>守御 · 更容易承压</option>
          <option value="mechanic" ${me.strategy === 'mechanic' ? 'selected' : ''}>机制优先 · 破甲/核心/破势优先</option>
        </select></label>
        <button class="${me.ready ? 'secondary-btn' : 'primary-btn'}" type="button" data-wboss-ready="${me.ready ? 'false' : 'true'}">${me.ready ? '取消准备' : '锁定快照并准备'}</button>
        ${party.is_leader ? `<button class="primary-btn" type="button" data-wboss-start ${allReady ? '' : 'disabled'}>${allReady ? `开始${members.length}人挑战` : '等待全员准备'}</button>` : '<span class="world-boss-wait-bwboss01">等待队长开始挑战</span>'}
      </section>
      <div class="world-boss-callout-bwboss01"><strong>当前基线没有已确认的战斗回血丹契约</strong><p>本候选不伪造丹药消耗。A确认生产真实丹药RPC后，可在此处接入每场最多2次的自动/手动治疗丹。</p></div>`;
  }

  function rareRewardHtml(run) {
    const reward = run?.my_reward?.rare_reward || run?.my_reward?.rareReward || null;
    const eligible = run?.my_reward?.rare_eligible === true;
    const index = Number(run?.my_reward?.rare_win_index || 0);
    if (reward?.reward_name) return `<div class="world-boss-rare-bwboss01 win"><b>珍稀战利品</b><span>${esc(reward.reward_name)} ×${fmt(reward.quantity || 1)}</span><small>今日第${fmt(index)}次珍稀判定</small></div>`;
    if (eligible) return `<div class="world-boss-rare-bwboss01"><b>珍稀判定</b><span>本次未命中珍稀战利品</span><small>今日第${fmt(index)}次判定</small></div>`;
    return '';
  }

  function runSummaryHtml(run) {
    if (!run?.id) return '';
    const result = run.result || {};
    const won = Boolean(result.victory);
    return `<section class="world-boss-run-summary-bwboss01 ${won ? 'win' : 'lose'}">
      <div><small>${time(run.ended_at || run.created_at)} · ${difficultyName(run.difficulty)}</small><strong>${won ? '镇压成功' : '挑战失败'}</strong><p>${esc(result.summary || (won ? '九幽吞天兽的投影已经被击退。' : '本次队伍未能在狂暴前完成镇压。'))}</p></div>
      <div><span>回合 ${fmt(result.rounds || 0)}</span><span>镇魔令 +${fmt(result.token_reward || 0)}</span><button class="primary-btn" type="button" data-wboss-playback="${esc(run.id)}">查看战报</button></div>${rareRewardHtml(run)}
    </section>`;
  }

  function rankingsHtml(data) {
    const rows = Array.isArray(data?.rankings) ? data.rankings.slice(0, 10) : [];
    if (!rows.length) return '<div class="world-boss-empty-bwboss01">当前境界尚无有效通关记录。</div>';
    return `<div class="world-boss-ranking-bwboss01">${rows.map((row, index) => `<article><b>${index + 1}</b><div><strong>${esc(row.party_label || row.player_name || '无名队伍')}</strong><small>${difficultyName(row.difficulty)} · ${fmt(row.party_size)}人 · ${fmt(row.rounds)}回合</small></div><span>${fmt(row.contribution || 0)}</span></article>`).join('')}</div>`;
  }

  function render() {
    const el = root(); if (!el) return;
    if (state.loading && !state.data) {
      el.innerHTML = '<div class="world-boss-loading-bwboss01"><i></i><span>正在读取世界劫难与队伍状态……</span></div>';
      return;
    }
    const data = state.data || {};
    if (['unavailable','disabled','closed','ineligible'].includes(data.status)) {
      el.innerHTML = unavailableHtml(data);
      bindActions(el);
      return;
    }
    el.innerHTML = `${eventHeader(data)}${data.party ? partyHtml(data) : noPartyHtml(data)}${runSummaryHtml(data.latest_run)}
      <section class="world-boss-section-bwboss01"><header><strong>本境界近期贡献</strong><span>排行榜不跨大境界比较伤害</span></header>${rankingsHtml(data)}</section>
      <section class="world-boss-section-bwboss01"><header><strong>首版机制</strong><span>无主动技能版</span></header><div class="world-boss-mechanics-bwboss01"><span>玄甲护体</span><span>五行核心</span><span>蓄力破势</span><span>九幽暴走</span><span>一次救援</span></div></section>`;
    bindActions(el);
  }

  async function refresh(force = false) {
    if (state.loading || (!force && state.data && Date.now() - state.lastFetchAt < 4000)) return state.data;
    state.loading = true; render();
    try {
      state.data = await rpc('get_world_boss_state_bwboss01', {});
      state.lastFetchAt = Date.now();
      render();
      return state.data;
    } catch (error) {
      state.data = { status:'unavailable', error:errorText(error) };
      render(); return state.data;
    } finally { state.loading = false; }
  }

  async function action(name, body, success) {
    if (state.busy) return null;
    state.busy = true;
    try {
      const result = await rpc(name, { ...(body || {}), p_request_id: uuid() });
      await refresh(true);
      if (success) toast(success);
      return result;
    } catch (error) {
      toast(errorText(error), 'error');
      return null;
    } finally { state.busy = false; }
  }

  function bindActions(el) {
    el.querySelectorAll('[data-wboss-refresh]').forEach(button => button.addEventListener('click', () => refresh(true)));
    el.querySelectorAll('[data-wboss-create]').forEach(button => button.addEventListener('click', () => action('create_world_boss_party_bwboss01', { p_difficulty:button.dataset.wbossCreate }, '世界BOSS队伍已创建。')));
    el.querySelector('#worldBossJoinFormBWorldBoss01')?.addEventListener('submit', event => {
      event.preventDefault(); const code = String(new FormData(event.currentTarget).get('joinCode') || '').trim().toUpperCase();
      action('join_world_boss_party_bwboss01', { p_join_code:code }, '已加入世界BOSS队伍。');
    });
    el.querySelector('[data-wboss-leave]')?.addEventListener('click', () => { if (confirm('确认离开当前世界BOSS队伍？')) action('leave_world_boss_party_bwboss01', {}, '已离开队伍。'); });
    el.querySelector('[data-wboss-ready]')?.addEventListener('click', button => {
      const ready = button.dataset.wbossReady === 'true';
      const strategy = document.getElementById('worldBossStrategyBWorldBoss01')?.value || 'balanced';
      action('set_world_boss_member_ready_bwboss01', { p_ready:ready, p_strategy:strategy }, ready ? '战斗快照已锁定，等待开战。' : '已取消准备。');
    });
    el.querySelector('[data-wboss-start]')?.addEventListener('click', async () => {
      if (!confirm('确认开始世界BOSS挑战？开战后本场角色快照锁定，服务端会一次完成权威结算。')) return;
      const result = await action('start_world_boss_run_bwboss01', {}, '世界BOSS战已经结算。');
      const run = result?.run || result;
      if (run?.id) showPlayback(run);
    });
    el.querySelectorAll('[data-wboss-playback]').forEach(button => button.addEventListener('click', async () => {
      try {
        const run = await rpc('get_world_boss_run_bwboss01', { p_run_id:button.dataset.wbossPlayback });
        showPlayback(run);
      } catch (error) { toast(errorText(error), 'error'); }
    }));
    el.querySelector('[data-wboss-copy-code]')?.addEventListener('click', async button => {
      const code = button.dataset.wbossCopyCode || '';
      try { await navigator.clipboard.writeText(code); toast(`队伍口令 ${code} 已复制。`); }
      catch { prompt('复制队伍口令', code); }
    });
  }

  function actionText(action) {
    const type = action.type || 'attack';
    if (type === 'phase') return `${action.title || '战局变化'}：${action.text || ''}`;
    if (type === 'rescue') return `${action.actor_name || '队友'}放弃一次攻势，救起${action.target_name || '倒地修士'}，恢复${fmt(action.hp_after || 0)}生机。`;
    if (type === 'miss') return `${action.actor_name || '修士'}攻向${action.target_name || '九幽吞天兽'}，但被闪避。`;
    if (type === 'boss_miss') return `${action.actor_name || '九幽吞天兽'}攻向${action.target_name || '修士'}，但被闪避。`;
    if (type === 'boss_attack') return `${action.actor_name || '九幽吞天兽'}攻向${action.target_name || '修士'}，造成${fmt(action.damage || 0)}伤害。`;
    return `${action.actor_name || '修士'}攻向${action.target_name || '九幽吞天兽'}，造成${fmt(action.damage || 0)}伤害${num(action.element_multiplier,1)>1 ? '，五行克制生效' : ''}。`;
  }

  function showPlayback(run) {
    if (!run) return;
    if (state.playbackTimer) clearTimeout(state.playbackTimer);
    const actions = Array.isArray(run.actions) ? run.actions : Array.isArray(run.result?.actions) ? run.result.actions : [];
    state.playbackIndex = 0; state.playbackSpeed = 1;
    const result = run.result || {};
    const wrapper = document.createElement('div');
    wrapper.className = 'world-boss-modal-bwboss01';
    wrapper.innerHTML = `<section class="world-boss-playback-bwboss01" role="dialog" aria-modal="true">
      <button type="button" class="world-boss-close-bwboss01" data-wboss-close>×</button>
      <header><small>${difficultyName(run.difficulty)} · ${fmt(run.party_size || result.party_size || 1)}人挑战</small><h3>${esc(run.boss_name || result.boss_name || '九幽吞天兽')}</h3><p>服务端权威战报 · 所有队员读取同一run_id</p></header>
      <div class="world-boss-battle-stage-bwboss01"><div class="world-boss-boss-card-bwboss01"><span>土</span><strong>九幽吞天兽</strong><div><i data-wboss-boss-hp style="width:100%"></i></div></div><div class="world-boss-action-log-bwboss01" data-wboss-log></div></div>
      <div class="world-boss-playback-controls-bwboss01"><button class="secondary-btn active" data-wboss-speed="1">1倍</button><button class="secondary-btn" data-wboss-speed="2">2倍</button><button class="primary-btn" data-wboss-skip>直接看结果</button></div>
      <div class="world-boss-result-bwboss01" data-wboss-result hidden></div>
    </section>`;
    document.body.appendChild(wrapper);
    const close = () => { if (state.playbackTimer) clearTimeout(state.playbackTimer); wrapper.remove(); };
    wrapper.querySelector('[data-wboss-close]')?.addEventListener('click', close);
    wrapper.addEventListener('click', event => { if (event.target === wrapper) close(); });
    wrapper.querySelectorAll('[data-wboss-speed]').forEach(button => button.addEventListener('click', () => {
      state.playbackSpeed = num(button.dataset.wbossSpeed,1); wrapper.querySelectorAll('[data-wboss-speed]').forEach(x=>x.classList.toggle('active',x===button));
    }));
    const log = wrapper.querySelector('[data-wboss-log]');
    const resultBox = wrapper.querySelector('[data-wboss-result]');
    const finish = () => {
      if (state.playbackTimer) clearTimeout(state.playbackTimer); state.playbackTimer = null;
      while (state.playbackIndex < actions.length) {
        const a = actions[state.playbackIndex++]; log.insertAdjacentHTML('beforeend', `<article class="${a.type === 'phase' ? 'phase' : ''}"><small>第${fmt(a.round || 0)}回合</small><p>${esc(actionText(a))}</p></article>`);
      }
      resultBox.hidden = false;
      resultBox.innerHTML = `<strong>${result.victory ? '镇压成功' : '挑战失败'}</strong><p>${esc(result.summary || '')}</p><div><span>战斗回合 ${fmt(result.rounds || 0)}</span><span>镇魔令 +${fmt(result.token_reward || 0)}</span><span>世界贡献 +${fmt(result.world_contribution || 0)}</span></div>${rareRewardHtml(run)}`;
      wrapper.querySelector('.world-boss-playback-controls-bwboss01').hidden = true;
    };
    const step = () => {
      if (!document.body.contains(wrapper)) return;
      if (state.playbackIndex >= actions.length) { finish(); return; }
      const a = actions[state.playbackIndex++];
      log.insertAdjacentHTML('beforeend', `<article class="${a.type === 'phase' ? 'phase' : ''}"><small>第${fmt(a.round || 0)}回合</small><p>${esc(actionText(a))}</p></article>`);
      log.scrollTop = log.scrollHeight;
      const bossPct = num(a.boss_hp_percent, NaN);
      if (Number.isFinite(bossPct)) wrapper.querySelector('[data-wboss-boss-hp]').style.width = `${Math.max(0, Math.min(100,bossPct))}%`;
      state.playbackTimer = setTimeout(step, Math.max(180, 760 / state.playbackSpeed));
    };
    wrapper.querySelector('[data-wboss-skip]')?.addEventListener('click', finish);
    step();
  }

  function mountAndRefresh() {
    if (!ensureSurface()) return;
    render();
    if (!state.data) refresh(true);
  }

  window.addEventListener('jiuxiao:sect-v2-rendered', mountAndRefresh);
  window.addEventListener('jiuxiao:secret-realm-rendered', () => ensureSurface());
  document.addEventListener('DOMContentLoaded', () => setTimeout(mountAndRefresh, 0));
  window.addEventListener('focus', () => { if (root() && Date.now() - state.lastFetchAt > 30000) refresh(true); }, { passive:true });

  window.B_WORLD_BOSS01 = Object.freeze({ module:MODULE, version:'R1', refresh, render, open:openWorldBossTab });
})();
