(() => {
  'use strict';

  const MODULE = 'B-SECRETREALM01-CACHE59-HISTORY5';
  const config = window.GAME_CONFIG || {};
  const baseUrl = String(config.supabaseUrl || '').replace(/\/+$/, '');
  const apiKey = String(config.supabasePublishableKey || '');
  const projectRef = (() => { try { return new URL(baseUrl).hostname.split('.')[0]; } catch { return 'unknown'; } })();
  const sessionKey = `nine_cloud_dao_session_${projectRef}_v1`;
  const deviceKey = `nine_cloud_dao_device_${projectRef}_v1`;

  const state = {
    data: null,
    loading: false,
    actionBusy: false,
    lastFetchAt: 0,
    serverOffsetMs: 0,
    localTicker: null,
    boundaryTimer: null,
    lastAutoSettleSlot: '',
    boundRoot: null,
    view: 'current',
    history: [],
    historyLoading: false,
    historyError: '',
    historyLoadedAt: 0
  };

  const esc = value => String(value ?? '')
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#039;');

  const uuid = () => globalThis.crypto?.randomUUID?.() || 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, char => {
    const value = Math.random() * 16 | 0;
    return (char === 'x' ? value : (value & 3 | 8)).toString(16);
  });

  function session() {
    try { return JSON.parse(localStorage.getItem(sessionKey) || 'null'); }
    catch { return null; }
  }

  function deviceId() { return localStorage.getItem(deviceKey) || ''; }

  function toast(message, type = 'success') {
    const element = document.getElementById('toast');
    if (!element) return;
    element.textContent = message;
    element.className = `toast show ${type}`;
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => { element.className = 'toast'; }, 3800);
  }

  function errorText(error) {
    const raw = String(error?.message || error || '秘境操作失败');
    const map = [
      ['SECRET_REALM_DATABASE_NOT_READY', '秘境数据库候选尚未接入。'],
      ['SECRET_REALM_ADAPTER_NOT_CONNECTED', '秘境尚未接通天命榜战斗与装备结算适配层。'],
      ['SECRET_REALM_DISABLED', '秘境当前处于维护状态。'],
      ['SECRET_REALM_DAILY_LIMIT_REACHED', '今日10次秘境次数已经用尽。'],
      ['SECRET_REALM_ALREADY_RUNNING', '你已经身处本轮秘境。'],
      ['SECRET_REALM_PREVIOUS_SETTLING', '上一轮秘境正在结算，请稍后再进入。'],
      ['SECRET_REALM_REWARDS_UNCLAIMED', '请先领取上一轮秘境的全部奖励，再进入下一次秘境。'],
      ['SECRET_REALM_CLAIM_IN_PROGRESS', '秘境奖励正在领取，请稍后刷新。'],
      ['SECRET_REALM_SESSION_CLOSED', '本轮秘境已经关闭，请进入下一轮。'],
      ['SECRET_REALM_REALM_MISMATCH', '只能进入与自身当前大境界相同的秘境。'],
      ['SECRET_REALM_CHARACTER_NOT_FOUND', '未找到当前角色。'],
      ['SECRET_REALM_REQUEST_ID_REQUIRED', '秘境唯一请求凭证缺失，请刷新后重试。'],
      ['SECRET_REALM_REQUEST_PARAMETER_MISMATCH', '秘境请求凭证与本次操作不一致。'],
      ['SECRET_REALM_SETTLEMENT_IN_PROGRESS', '当前分钟正在结算，请稍后刷新。'],
      ['GAME_SESSION_REPLACED', '当前账号已在另一设备接管。'],
      ['AUTH_REQUIRED', '请先登录后进入秘境。'],
      ['PGRST202', '秘境RPC尚未部署。'],
      ['Could not find the function', '秘境RPC尚未部署。']
    ];
    return (map.find(([code]) => raw.includes(code)) || [])[1] || raw;
  }

  async function rpc(name, body = {}) {
    const activeSession = session();
    if (!activeSession?.access_token) throw new Error('AUTH_REQUIRED');
    const response = await fetch(`${baseUrl}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: {
        apikey: apiKey,
        Authorization: `Bearer ${activeSession.access_token}`,
        'Content-Type': 'application/json',
        'X-Game-Session-Id': deviceId()
      },
      body: JSON.stringify(body)
    });
    const text = await response.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch { data = text; }
    if (!response.ok) throw new Error(data?.message || data?.msg || data?.error || `HTTP ${response.status}`);
    return Array.isArray(data) ? data[0] || null : data;
  }

  function number(value, fallback = 0) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  }

  function formatNumber(value, maximumFractionDigits = 0) {
    return number(value).toLocaleString('zh-CN', { maximumFractionDigits });
  }

  function formatDuration(totalSeconds) {
    const seconds = Math.max(0, Math.floor(number(totalSeconds)));
    const hours = Math.floor(seconds / 3600);
    const minutes = Math.floor((seconds % 3600) / 60);
    const rest = seconds % 60;
    if (hours > 0) return `${hours}时${String(minutes).padStart(2, '0')}分${String(rest).padStart(2, '0')}秒`;
    return `${String(minutes).padStart(2, '0')}:${String(rest).padStart(2, '0')}`;
  }

  function formatClock(value) {
    const date = value ? new Date(value) : null;
    if (!date || Number.isNaN(date.getTime())) return '—';
    return date.toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit', hour12: false });
  }

  function formatDateTime(value) {
    const date = value ? new Date(value) : null;
    if (!date || Number.isNaN(date.getTime())) return '—';
    return date.toLocaleString('zh-CN', {
      month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hour12: false
    }).replace('/', '月').replace(',', '日');
  }

  function updateServerOffset(payload) {
    const serverNow = new Date(payload?.server_now || 0).getTime();
    if (Number.isFinite(serverNow) && serverNow > 0) state.serverOffsetMs = serverNow - Date.now();
  }

  function serverNowMs() { return Date.now() + state.serverOffsetMs; }

  function phaseMeta(sessionData = {}) {
    const minute = Math.max(1, Math.min(30, number(sessionData.global_minute || sessionData.minute_index || 1)));
    if (minute <= 10) return { code: 'outer', name: '秘境外围', danger: '常规', className: 'outer' };
    if (minute <= 20) return { code: 'inner', name: '秘境内层', danger: '提升', className: 'inner' };
    return { code: 'deep', name: '秘境深处', danger: '较高', className: 'deep' };
  }

  function sessionSecondsRemaining(sessionData = {}) {
    const end = new Date(sessionData.end_at || 0).getTime();
    if (!Number.isFinite(end) || end <= 0) return number(sessionData.seconds_remaining);
    return Math.max(0, Math.ceil((end - serverNowMs()) / 1000));
  }

  function resetSecondsRemaining(data = {}) {
    const reset = new Date(data.reset_at || 0).getTime();
    if (!Number.isFinite(reset) || reset <= 0) return 0;
    return Math.max(0, Math.ceil((reset - serverNowMs()) / 1000));
  }

  function statusLabel(run = {}) {
    const map = {
      running: '探索中',
      settling: '结算中',
      completed: '成功离境',
      monster_defeated: '被妖兽击败',
      pvp_defeated: '被修士击败',
      settled: '已结算'
    };
    return map[run.status] || run.status_name || '未进入';
  }

  function percentText(value, digits = 1) {
    const pct = Math.max(0, number(value)) * 100;
    return `${pct.toLocaleString('zh-CN', { maximumFractionDigits: digits })}%`;
  }

  function stageProbabilityText(phase = 'outer', data = state.data || {}) {
    const row = data?.live_config?.depths?.[phase];
    if (!row) {
      if (phase === 'inner') return '初期50% · 中期30% · 后期15% · 圆满5%';
      if (phase === 'deep') return '初期35% · 中期35% · 后期22% · 圆满8%';
      return '初期65% · 中期25% · 后期8% · 圆满2%';
    }
    return `初期${percentText(row.early)} · 中期${percentText(row.middle)} · 后期${percentText(row.late)} · 圆满${percentText(row.complete)}`;
  }

  function equipmentRateText(data = state.data || {}) {
    const stages = data?.live_config?.stages || {};
    const rates = ['early', 'middle', 'late', 'complete']
      .map(code => number(stages?.[code]?.equipment_rate, NaN))
      .filter(Number.isFinite);
    if (!rates.length) return '读取实时配置';
    const unique = [...new Set(rates.map(value => Math.round(value * 1000000) / 1000000))];
    return unique.length === 1 ? `单只实时掉率${percentText(unique[0], 3)}` : `各阶段实时掉率：${rates.map(value => percentText(value, 3)).join(' / ')}`;
  }

  function rewardValue(rewards, key) {
    if (!rewards || typeof rewards !== 'object') return 0;
    const value = rewards[key];
    if (value && typeof value === 'object') {
      return number(value.granted_amount ?? value.requested_amount ?? value.amount ?? value.total ?? 0);
    }
    return number(value);
  }

  function materialsArray(rewards = {}) {
    if (Array.isArray(rewards.materials)) return rewards.materials;
    if (rewards.materials && typeof rewards.materials === 'object') {
      return Object.entries(rewards.materials).map(([code, quantity]) => ({ code, name: materialName(code), quantity }));
    }
    return [];
  }

  function equipmentArray(rewards = {}) {
    return Array.isArray(rewards.equipment) ? rewards.equipment : Array.isArray(rewards.equipments) ? rewards.equipments : [];
  }

  function materialName(code) {
    return {
      hundred_refine_crystal: '百炼玄晶',
      weapon_soul_jade: '兵魄道玉',
      guardian_spirit_jade: '护道灵玉',
      beast_essence_blood: '灵兽精血',
      mystic_bone_essence: '玄骨精粹',
      spirit_scale_fragment: '灵鳞残片',
      spirit_nurturing_herb: '蕴灵草',
      earth_vein_spirit_sand: '地脉灵砂',
      beast_soul_fragment: '兽魂残魄'
    }[code] || code || '未知材料';
  }

  function equipmentGradeClass(code) {
    return ['yellow', 'mystic', 'earth', 'heaven', 'immortal'].includes(code) ? code : 'mystic';
  }

  function materialCardsHtml(rewards = {}) {
    const rows = materialsArray(rewards).filter(row => number(row.quantity) > 0);
    if (!rows.length) return '<div class="secret-realm-empty-bsecretrealm01">尚未获得材料</div>';
    return rows.map(row => `
      <div class="secret-realm-material-bsecretrealm01">
        <span>${esc(String(row.name || materialName(row.code)).slice(0, 1))}</span>
        <div><strong>${esc(row.name || materialName(row.code))}</strong><small>秘境材料 · 数量随机缘境界基数成长</small></div>
        <b>×${formatNumber(row.quantity)}</b>
      </div>
    `).join('');
  }

  function equipmentCardsHtml(rewards = {}) {
    const rows = equipmentArray(rewards);
    if (!rows.length) return '<div class="secret-realm-empty-bsecretrealm01">尚未获得秘境装备</div>';
    return rows.map(item => `
      <article class="secret-realm-equipment-bsecretrealm01 grade-${equipmentGradeClass(item.grade_code)}">
        <span>${esc(item.icon_glyph || '器')}</span>
        <div><strong>${esc(item.full_name || item.name || '秘境装备')}</strong><small>${esc(item.realm_name || '')} · ${esc(item.grade_name || '')}${item.stolen ? ' · 夺宝所得' : ''}</small></div>
        <em>${item.claim_pending ? '待领取' : item.at_risk === false ? '已结算' : '风险中'}</em>
      </article>
    `).join('');
  }

  function eventSeal(type = '') {
    const raw = String(type);
    if (raw.includes('pvp')) return '斗';
    if (raw.includes('monster')) return '妖';
    if (raw.includes('completed')) return '归';
    if (raw.includes('equipment')) return '器';
    return '境';
  }

  function opponentFactsHtml(event = {}) {
    const opponent = event.opponent || event.monster || null;
    if (!opponent || !['monster', 'pvp'].includes(event.event_type)) return '';
    const isMonster = event.event_type === 'monster';
    const facts = [
      opponent.realm || opponent.stage_realm || '',
      opponent.element_name ? `${opponent.element_name}属性` : '',
      isMonster ? (opponent.archetype_name || '') : '秘境修士',
      opponent.power ? `战力 ${formatNumber(opponent.power)}` : ''
    ].filter(Boolean);
    const stats = [
      ['道攻', opponent.attack], ['道御', opponent.defense], ['生机', opponent.vitality], ['身法', opponent.agility]
    ].filter(([, value]) => number(value) > 0);
    return `<div class="secret-realm-monster-facts-bsecretrealm01 ${isMonster ? 'is-monster' : 'is-player'}">
      <div class="secret-realm-monster-facts-title-bsecretrealm01"><b>${esc(opponent.name || (isMonster ? '秘境妖兽' : '无名修士'))}</b><span>${facts.map(esc).join(' · ')}</span></div>
      ${stats.length ? `<div class="secret-realm-monster-stat-grid-bsecretrealm01">${stats.map(([label,value]) => `<span>${label}<b>${formatNumber(value)}</b></span>`).join('')}</div>` : ''}
    </div>`;
  }

  function eventRowsHtml(events = [], direction = 'desc') {
    if (!events.length) return '<div class="secret-realm-empty-bsecretrealm01">本轮没有可显示的分钟记录。</div>';
    const rows = [...events].sort((left, right) => direction === 'asc'
      ? number(left.minute_index) - number(right.minute_index)
      : number(right.minute_index) - number(left.minute_index));
    return rows.map(event => `
      <article class="secret-realm-log-row-bsecretrealm01 outcome-${esc(event.outcome || 'neutral')}">
        <span class="secret-realm-log-seal-bsecretrealm01">${eventSeal(event.event_type)}</span>
        <div>
          <header><strong>第${formatNumber(event.minute_index || 1)}分钟 · ${esc(event.title || '秘境异动')}</strong><time>${esc(event.stage_name || '')}</time></header>
          <p>${esc(event.content || event.summary || '')}</p>
          ${opponentFactsHtml(event)}
          ${event.reward_text ? `<small>${esc(event.reward_text)}</small>` : ''}
        </div>
      </article>
    `).join('');
  }

  function monsterRowsHtml(monsters = []) {
    if (!monsters.length) return '<div class="secret-realm-empty-bsecretrealm01">怪物图鉴将在数据库接入后显示。</div>';
    const grouped = ['early', 'middle', 'late', 'complete'].map(stage => ({ stage, rows: monsters.filter(row => row.minor_stage === stage) }));
    const meta = {
      early: ['初期', '玄品'], middle: ['中期', '地品'], late: ['后期', '天品'], complete: ['圆满', '仙品']
    };
    return grouped.map(group => `
      <section class="secret-realm-monster-stage-bsecretrealm01 stage-${group.stage}">
        <header><strong>${meta[group.stage][0]}怪物</strong><span>概率掉落当前境界${meta[group.stage][1]}装备</span></header>
        <div>${group.rows.map(row => `<span title="${esc(row.archetype_name || '')}">${esc(row.name || '未知妖物')}<small>${esc(row.archetype_name || '')}</small></span>`).join('')}</div>
      </section>
    `).join('');
  }

  function unavailableHtml(data = {}) {
    return `
      <div class="secret-realm-unavailable-bsecretrealm01">
        <span>秘</span>
        <h4>秘境正式版等待生产接口校准</h4>
        <p>${esc(data.error || '请先执行117A只读取证；最终适配层会按生产函数和表结构生成，不使用猜测接口。')}</p>
        <button class="ghost-btn" type="button" data-secret-realm-refresh>重新感应</button>
      </div>
    `;
  }

  function reportHtml(report = {}) {
    if (!report || !report.status) return '';
    const lost = report.lost_rewards || {};
    const finalRewards = report.claim_result || report.final_rewards || {};
    const claimStatus = report.claim_status || (report.claimed_at ? 'claimed' : '');
    return `
      <section class="secret-realm-report-bsecretrealm01 outcome-${esc(report.status)}">
        <div class="secret-realm-report-seal-bsecretrealm01">${report.status === 'completed' ? '归' : report.status === 'pvp_defeated' ? '败' : '退'}</div>
        <div class="secret-realm-report-copy-bsecretrealm01">
          <span>上一轮战报${claimStatus === 'claimed' ? ' · 奖励已领取' : ''}</span>
          <h4>${esc(report.title || statusLabel(report))}</h4>
          <p>${esc(report.summary || '')}</p>
        </div>
        <div class="secret-realm-report-grid-bsecretrealm01">
          <div><span>实际探索</span><strong>${formatNumber(report.duration_minutes)}分钟</strong></div>
          <div><span>击败妖兽</span><strong>${formatNumber(report.monsters_defeated)}</strong></div>
          <div><span>玩家交锋</span><strong>${formatNumber(report.pvp_count)}</strong></div>
          <div><span>所得修为</span><strong>${formatNumber(rewardValue(finalRewards, 'cultivation'))}</strong></div>
          <div><span>所得灵石</span><strong>${formatNumber(rewardValue(finalRewards, 'spirit_stones'))}</strong></div>
          <div><span>被夺灵石</span><strong>${formatNumber(rewardValue(lost, 'spirit_stones'))}</strong></div>
        </div>
      </section>
    `;
  }

  function historyClaimLabel(run = {}) {
    if (run.claim_status === 'pending') return '待领取';
    if (run.claim_status === 'claiming') return '领取中';
    return '已领取';
  }

  function historyOutcomeSeal(run = {}) {
    if (run.status === 'completed') return '归';
    if (run.status === 'pvp_defeated') return '败';
    if (run.status === 'monster_defeated') return '妖';
    return '境';
  }

  function historyCardHtml(run = {}, index = 0) {
    const rewards = run.final_rewards || {};
    const claimResult = run.claim_result || {};
    const lost = run.lost_rewards || {};
    const equipment = equipmentArray(rewards);
    const entry = run.entry_snapshot || {};
    const events = Array.isArray(run.events) ? run.events : [];
    const receivedCultivation = rewardValue(claimResult, 'cultivation') || rewardValue(rewards, 'cultivation');
    const receivedSpirit = rewardValue(claimResult, 'spirit_stones') || rewardValue(rewards, 'spirit_stones');
    return `
      <details class="secret-realm-history-card-bsecretrealm01 outcome-${esc(run.status || '')}" ${index === 0 ? 'open' : ''}>
        <summary>
          <span class="secret-realm-history-seal-bsecretrealm01">${historyOutcomeSeal(run)}</span>
          <div class="secret-realm-history-summary-copy-bsecretrealm01">
            <small>${esc(formatDateTime(run.ended_at || run.claimed_at))} · ${esc(run.secret_name || run.realm_name || '秘境')}</small>
            <strong>${esc(run.title || statusLabel(run))}</strong>
            <em>${esc(historyClaimLabel(run))}</em>
          </div>
          <b>${formatNumber(run.duration_minutes)}分钟</b>
        </summary>
        <div class="secret-realm-history-body-bsecretrealm01">
          <p class="secret-realm-history-summary-text-bsecretrealm01">${esc(run.summary || run.end_reason || '本轮秘境已经结束。')}</p>
          <div class="secret-realm-history-entry-bsecretrealm01">
            <span>入场境界<b>${esc(entry.realm || '—')}</b></span>
            <span>入场战力<b>${formatNumber(entry.power)}</b></span>
            <span>灵根命格<b>${esc([entry.spirit_root_name, entry.fate_name].filter(Boolean).join(' · ') || '—')}</b></span>
          </div>
          <div class="secret-realm-report-grid-bsecretrealm01 secret-realm-history-grid-bsecretrealm01">
            <div><span>探索事件</span><strong>${formatNumber(run.events_processed)}</strong></div>
            <div><span>击败妖兽</span><strong>${formatNumber(run.monsters_defeated)}</strong></div>
            <div><span>玩家交锋</span><strong>${formatNumber(run.pvp_count)}</strong></div>
            <div><span>最终修为</span><strong>${formatNumber(receivedCultivation)}</strong></div>
            <div><span>最终灵石</span><strong>${formatNumber(receivedSpirit)}</strong></div>
            <div><span>装备所得</span><strong>${formatNumber(equipment.length)}件</strong></div>
          </div>
          ${rewardValue(lost, 'cultivation') || rewardValue(lost, 'spirit_stones') ? `<div class="secret-realm-history-loss-bsecretrealm01">风险损失：修为 ${formatNumber(rewardValue(lost, 'cultivation'))} · 灵石 ${formatNumber(rewardValue(lost, 'spirit_stones'))}</div>` : ''}
          <section class="secret-realm-history-events-bsecretrealm01">
            <header><strong>本轮完整经历</strong><span>按分钟顺序 · 共${formatNumber(events.length)}条</span></header>
            <div class="secret-realm-log-list-bsecretrealm01">${eventRowsHtml(events, 'asc')}</div>
          </section>
        </div>
      </details>
    `;
  }

  function historyHtml() {
    if (state.historyLoading) return '<div class="secret-realm-loading-bsecretrealm01"><i></i><span>正在读取最近5轮秘境……</span></div>';
    if (state.historyError) return `<div class="secret-realm-unavailable-bsecretrealm01"><span>史</span><h4>秘境历史读取失败</h4><p>${esc(state.historyError)}</p><button class="ghost-btn" type="button" data-secret-realm-history-refresh>重新读取</button></div>`;
    if (!state.history.length) return '<div class="secret-realm-history-empty-bsecretrealm01"><span>卷</span><strong>尚无秘境历史</strong><p>完成第一轮秘境后，这里会保存最近5轮的过程、结果与领取情况。</p></div>';
    return `
      <section class="secret-realm-history-bsecretrealm01">
        <header class="secret-realm-history-heading-bsecretrealm01"><div><span>秘境履历</span><strong>最近5轮</strong><small>只读取当前角色最近结束的5轮，不加载更早记录。</small></div><button class="ghost-btn" type="button" data-secret-realm-history-refresh>刷新历史</button></header>
        <div class="secret-realm-history-list-bsecretrealm01">${state.history.slice(0, 5).map(historyCardHtml).join('')}</div>
      </section>
    `;
  }

  function surfaceTabsHtml() {
    return `<nav class="secret-realm-surface-tabs-bsecretrealm01" aria-label="秘境页面">
      <button type="button" class="${state.view === 'current' ? 'active' : ''}" data-secret-realm-view="current">当前秘境</button>
      <button type="button" class="${state.view === 'history' ? 'active' : ''}" data-secret-realm-view="history">秘境历史 <small>最近5轮</small></button>
    </nav>`;
  }

  function pendingClaimHtml(data, claim) {
    const rewards = claim.final_rewards || claim.rewards || {};
    const equipment = equipmentArray(rewards);
    const outcomeTitle = claim.title || statusLabel(claim);
    return `
      <section class="secret-realm-claim-bsecretrealm01 outcome-${esc(claim.status || '')}">
        <div class="secret-realm-claim-scene-bsecretrealm01">
          <img src="assets/secret-realm-portal.webp" alt="秘境界门与悬山" loading="eager">
          <div class="secret-realm-claim-scene-shade-bsecretrealm01"></div>
          <div class="secret-realm-claim-heading-bsecretrealm01"><span>本轮探索已结束</span><strong>${esc(outcomeTitle)}</strong><small>${esc(claim.summary || claim.end_reason || '请清点战利品并领取。')}</small></div>
        </div>
        <div class="secret-realm-claim-lock-bsecretrealm01"><b>奖励尚未入账</b><span>修为、灵石、材料与装备会在点击领取后统一写入账号；领取完成前不能进入下一次秘境。</span></div>
        <div class="secret-realm-reward-summary-bsecretrealm01 secret-realm-claim-summary-bsecretrealm01">
          <div><span>待领修为</span><strong>${formatNumber(rewardValue(rewards, 'cultivation'))}</strong></div>
          <div><span>待领灵石</span><strong>${formatNumber(rewardValue(rewards, 'spirit_stones'))}</strong></div>
          <div><span>待领装备</span><strong>${formatNumber(equipment.length)}件</strong></div>
        </div>
        <div class="secret-realm-two-column-bsecretrealm01">
          <section class="secret-realm-box-bsecretrealm01"><header><strong>待领材料</strong><span>领取后进入洞府储物</span></header>${materialCardsHtml(rewards)}</section>
          <section class="secret-realm-box-bsecretrealm01"><header><strong>待领装备</strong><span>背包满时进入待领取区</span></header>${equipmentCardsHtml({ ...rewards, equipment: equipment.map(item => ({ ...item, claim_pending: true })) })}</section>
        </div>
        <div class="secret-realm-claim-actions-bsecretrealm01">
          <button class="ghost-btn" type="button" data-secret-realm-refresh>刷新结算</button>
          <button class="primary-btn" type="button" data-secret-realm-claim>领取全部奖励</button>
        </div>
      </section>
      <section class="secret-realm-box-bsecretrealm01"><header><strong>本轮秘境日志</strong><span>领取前可再次核对</span></header><div class="secret-realm-log-list-bsecretrealm01">${eventRowsHtml(claim.events || [])}</div></section>
    `;
  }

  function runningHtml(data, run) {
    const rewards = run.temporary_rewards || run.rewards || {};
    const seconds = sessionSecondsRemaining(data.session);
    const phase = phaseMeta(data.session || {});
    const latestEvent = Array.isArray(run.events) && run.events.length ? [...run.events].sort((a,b)=>number(b.minute_index)-number(a.minute_index))[0] : null;
    return `
      <section class="secret-realm-running-bsecretrealm01">
        <div class="secret-realm-live-scene-bsecretrealm01 phase-${phase.className}">
          <img src="assets/secret-realm-portal.webp" alt="秘境界门与悬山" loading="eager">
          <i class="secret-realm-fog-one-bsecretrealm01"></i><i class="secret-realm-fog-two-bsecretrealm01"></i>
          <div class="secret-realm-live-scene-copy-bsecretrealm01">
            <span>${esc(run.realm_name || data.realm?.secret_name || data.realm?.name || '本轮秘境')}</span>
            <strong>${esc(statusLabel(run))}</strong>
            <small>${phase.name} · 属性已按进入时权威快照锁定${latestEvent?.opponent?.name ? ` · 最近遭遇 ${esc(latestEvent.opponent.name)}` : ''}</small>
          </div>
          <div class="secret-realm-countdown-bsecretrealm01"><span>距离场次关闭</span><b data-secret-realm-session-countdown>${formatDuration(seconds)}</b></div>
        </div>
        <div class="secret-realm-run-stats-bsecretrealm01">
          <div><span>进入时间</span><strong>${formatClock(run.entered_at)}</strong></div>
          <div><span>已结算事件</span><strong>${formatNumber(run.events_processed)} / ${formatNumber(run.max_events || data.session?.remaining_event_slots || 30)}</strong></div>
          <div><span>击败妖兽</span><strong>${formatNumber(run.monsters_defeated)}</strong></div>
          <div><span>玩家交锋</span><strong>${formatNumber(run.pvp_count)}</strong></div>
        </div>
        <div class="secret-realm-risk-note-bsecretrealm01"><strong>当前所得仍处于风险中</strong><span>被玩家击败后，堆叠资源转移50%，每件装备独立判定50%易主；被妖兽击败则保留全部当前所得。离境结算后仍需手动领取。</span></div>
        <div class="secret-realm-reward-summary-bsecretrealm01">
          <div><span>临时修为</span><strong>${formatNumber(rewardValue(rewards, 'cultivation'))}</strong></div>
          <div><span>临时灵石</span><strong>${formatNumber(rewardValue(rewards, 'spirit_stones'))}</strong></div>
          <div><span>临时装备</span><strong>${formatNumber(equipmentArray(rewards).length)}件</strong></div>
        </div>
        <div class="secret-realm-running-actions-bsecretrealm01">
          <button class="ghost-btn" type="button" data-secret-realm-refresh>刷新状态</button>
          <button class="primary-btn" type="button" data-secret-realm-settle>结算已到分钟</button>
        </div>
      </section>
      <div class="secret-realm-two-column-bsecretrealm01">
        <section class="secret-realm-box-bsecretrealm01"><header><strong>临时材料</strong><span>触发概率沿用原配置，数量按当前境界机缘基数成长</span></header>${materialCardsHtml(rewards)}</section>
        <section class="secret-realm-box-bsecretrealm01"><header><strong>临时装备</strong><span>天品、仙品同样处于夺宝风险</span></header>${equipmentCardsHtml(rewards)}</section>
      </div>
      <section class="secret-realm-box-bsecretrealm01"><header><strong>本轮秘境日志</strong><span>妖兽修为、五行、类型与四维均由服务端显示</span></header><div class="secret-realm-log-list-bsecretrealm01">${eventRowsHtml(run.events || [])}</div></section>
    `;
  }

  function entranceHtml(data) {
    const sessionData = data.session || {};
    const realm = data.realm || {};
    const phase = phaseMeta(sessionData);
    const seconds = sessionSecondsRemaining(sessionData);
    const eventSlots = Math.max(0, number(sessionData.remaining_event_slots || Math.ceil(seconds / 60)));
    const remaining = Math.max(0, number(data.entries_remaining));
    const canEnter = data.can_enter !== false && remaining > 0 && seconds > 0 && !state.actionBusy;
    return `
      ${reportHtml(data.latest_report)}
      <section class="secret-realm-gate-bsecretrealm01 phase-${phase.className}">
        <div class="secret-realm-gate-art-bsecretrealm01"><span>秘</span><i></i></div>
        <div class="secret-realm-gate-copy-bsecretrealm01">
          <span>${esc(realm.name || '当前境界秘境')}</span>
          <h4>${esc(realm.secret_name || '秘境')}</h4>
          <p>${esc(realm.description || '半小时公共秘境，全服同境界修士可能在其中相遇。')}</p>
          <div class="secret-realm-tags-bsecretrealm01"><span>奖励 ${formatNumber(number(data.rules?.reward_global_multiplier || 1) * 100, 2)}%</span><span>怪物强度 ${formatNumber(number(data.rules?.monster_strength_multiplier || 1) * 100, 2)}%</span><span>只可进入当前大境界</span></div>
        </div>
        <div class="secret-realm-session-card-bsecretrealm01">
          <span>当前公共场次</span>
          <strong>${formatClock(sessionData.start_at)}—${formatClock(sessionData.end_at)}</strong>
          <b data-secret-realm-session-countdown>${formatDuration(seconds)}</b>
          <small>${phase.name} · 怪物危险${phase.danger}</small>
        </div>
      </section>
      <section class="secret-realm-entry-grid-bsecretrealm01">
        <div><span>今日剩余次数</span><strong>${formatNumber(remaining)} / ${formatNumber(data.daily_limit || 10)}</strong><small>服务器每日00:00重置 · 不累计</small></div>
        <div><span>本次最多事件</span><strong>${formatNumber(eventSlots)}次</strong><small>中途进入仍完整消耗1次</small></div>
        <div><span>当前怪物分布</span><strong>${phase.name}</strong><small>${stageProbabilityText(phase.code, data)}</small></div>
        <div><span>玩家碰撞</span><strong>${formatNumber(number(data.rules?.pvp_probability_per_minute || 0.02) * 100, 2)}% / 分钟</strong><small>同境界、同场次、真实天命榜战斗</small></div>
      </section>
      <div class="secret-realm-entry-warning-bsecretrealm01">
        <strong>${seconds <= 120 ? '本轮秘境即将关闭' : '进入后无法主动退出'}</strong>
        <p>你只会参与进入后的剩余分钟。迟入者没有保护，也可遇到已探索更久的玩家。秘境成功、被妖兽击败或被玩家击败均同步九霄界闻。</p>
      </div>
      <div class="secret-realm-entry-actions-bsecretrealm01">
        <button class="ghost-btn" type="button" data-secret-realm-refresh>刷新场次</button>
        <button class="primary-btn" type="button" data-secret-realm-enter ${canEnter ? '' : 'disabled'}>${remaining <= 0 ? '今日次数已用尽' : seconds <= 0 ? '等待下一场' : data.can_enter === false ? esc(data.blocked_reason || '当前不可进入') : `进入${esc(realm.secret_name || '秘境')}（消耗1次）`}</button>
      </div>
      <section class="secret-realm-box-bsecretrealm01 secret-realm-rules-bsecretrealm01">
        <header><strong>秘境核心规则</strong><span>服务端权威结算 · 配置纪元 ${formatNumber(data?.live_config?.config_epoch || 0)}</span></header>
        <div class="secret-realm-rule-grid-bsecretrealm01">
          <p><b>公共场次</b>全天开放，每个整点与半点开启新场，场次结束时所有存活玩家成功离境。</p>
          <p><b>妖兽战败</b>立即结束本轮，但保留当前秘境全部所得。</p>
          <p><b>玩家战败</b>失去本轮堆叠所得50%，每件临时装备独立50%概率易主。</p>
          <p><b>真实战斗</b>玩家碰撞完全复用天命榜战斗核心，使用进入时锁定的真实属性快照。</p>
          <p><b>机缘折算</b>初期、中期、后期、圆满妖兽分别对应玄品、地品、天品、仙品趋吉机缘；每只妖兽发放对应完整机缘结果的五分之一，再乘后台秘境奖励整体倍率。</p><p><b>装备品级</b>${equipmentRateText(data)}；初期玄品、中期地品、后期天品、圆满仙品，装备掉落规则本次不变。</p>
          <p><b>统一领取</b>离境、战败或夺宝结束后，所有修为、灵石、材料与装备必须手动领取；领取前不能进入下一次秘境。</p><p><b>材料成长</b>材料触发概率与种类沿用现有配置；触发数量以炼气10—15为基础，按每次大境界突破时的机缘基数增长比例累计提升，并受秘境奖励整体倍率影响。</p>
        </div>
      </section>
      <section class="secret-realm-box-bsecretrealm01"><header><strong>${esc(realm.secret_name || '秘境')}怪物图鉴</strong><span>同阶段不同名字只改变属性倾向，不改变掉率</span></header>${monsterRowsHtml(data.monsters || [])}</section>
    `;
  }

  function currentSurfaceHtml(data = {}) {
    if (data.status === 'unavailable' || data.status === 'adapter_pending') return unavailableHtml(data);
    if (data.status === 'loading') return '<div class="secret-realm-loading-bsecretrealm01"><i></i><span>正在感应本轮秘境……</span></div>';
    if (data.status === 'disabled') return unavailableHtml({ error: data.error || '秘境当前处于维护状态。' });
    if (data.pending_claim) return pendingClaimHtml(data, data.pending_claim);
    const run = data.current_run;
    return run && ['running', 'settling'].includes(run.status) ? runningHtml(data, run) : entranceHtml(data);
  }

  function rootHtml(data = {}) {
    return `${surfaceTabsHtml()}${state.view === 'history' ? historyHtml() : currentSurfaceHtml(data)}`;
  }

  function render() {
    const root = document.getElementById('secretRealmRootBSecretRealm01');
    if (!root) return;
    state.boundRoot = root;
    root.innerHTML = rootHtml(state.data || { status: state.loading ? 'loading' : 'unavailable', error: '秘境状态尚未读取。' });
    bindActions(root);
    updateCountdownDom();
    scheduleBoundary();
  }

  async function refresh(force = false) {
    if (state.loading || !session()?.access_token) return state.data;
    if (!force && Date.now() - state.lastFetchAt < 4000) return state.data;
    state.loading = true;
    if (!state.data) render();
    try {
      const data = await rpc('get_secret_realm_state_bsecretrealm01', {});
      state.data = data || { status: 'unavailable', error: '秘境RPC未返回数据。' };
      updateServerOffset(state.data);
      state.lastFetchAt = Date.now();
      render();
      return state.data;
    } catch (error) {
      state.data = { status: 'unavailable', error: errorText(error) };
      render();
      return state.data;
    } finally {
      state.loading = false;
    }
  }

  async function loadHistory(force = false) {
    if (state.historyLoading || !session()?.access_token) return state.history;
    if (!force && state.historyLoadedAt && Date.now() - state.historyLoadedAt < 30000) return state.history;
    state.historyLoading = true;
    state.historyError = '';
    render();
    try {
      const result = await rpc('get_secret_realm_history_bsecretrealm01', {});
      state.history = Array.isArray(result?.history) ? result.history.slice(0, 5) : [];
      state.historyLoadedAt = Date.now();
      return state.history;
    } catch (error) {
      state.historyError = errorText(error);
      return [];
    } finally {
      state.historyLoading = false;
      render();
    }
  }

  async function enterRealm(button) {
    if (state.actionBusy) return;
    const data = state.data || {};
    const seconds = sessionSecondsRemaining(data.session || {});
    const events = Math.max(0, number(data.session?.remaining_event_slots || Math.ceil(seconds / 60)));
    const warning = seconds <= 120
      ? `本轮只剩${events}次事件，仍会消耗1次。确认进入？`
      : `进入后无法主动退出，本轮最多参与${events}次事件。确认进入？`;
    if (!window.confirm(warning)) return;
    state.actionBusy = true;
    if (button) { button.disabled = true; button.textContent = '踏入秘境中……'; }
    try {
      const result = await rpc('enter_secret_realm_bsecretrealm01', { p_request_id: uuid() });
      if (result?.state) {
        state.data = result.state;
        updateServerOffset(state.data);
      } else {
        await refresh(true);
      }
      toast(result?.message || '你已经进入本轮秘境。');
      render();
    } catch (error) {
      toast(errorText(error), 'error');
      await refresh(true);
    } finally {
      state.actionBusy = false;
      render();
    }
  }

  async function settleDue(button = null, silent = false) {
    if (state.actionBusy || !state.data?.current_run || !['running', 'settling'].includes(state.data.current_run.status)) return;
    state.actionBusy = true;
    if (button) { button.disabled = true; button.textContent = '结算中……'; }
    try {
      const result = await rpc('settle_secret_realm_progress_bsecretrealm01', { p_request_id: uuid() });
      if (result?.state) {
        state.data = result.state;
        updateServerOffset(state.data);
      } else {
        await refresh(true);
      }
      if (!silent && result?.message) toast(result.message);
      state.historyLoadedAt = 0;
      window.dispatchEvent(new CustomEvent('jiuxiao:secret-realm-settled', { detail: result || state.data }));
      render();
    } catch (error) {
      if (!silent) toast(errorText(error), 'error');
      await refresh(true);
    } finally {
      state.actionBusy = false;
      render();
    }
  }

  async function claimRewards(button = null) {
    if (state.actionBusy || !state.data?.pending_claim) return;
    state.actionBusy = true;
    if (button) { button.disabled = true; button.textContent = '奖励入账中……'; }
    try {
      const result = await rpc('claim_secret_realm_rewards_bsecretrealm01', { p_request_id: uuid() });
      if (result?.state) {
        state.data = result.state;
        updateServerOffset(state.data);
      } else {
        await refresh(true);
      }
      toast(result?.message || '秘境奖励已全部领取。');
      state.historyLoadedAt = 0;
      window.dispatchEvent(new CustomEvent('jiuxiao:secret-realm-claimed', { detail: result || state.data }));
      render();
    } catch (error) {
      toast(errorText(error), 'error');
      await refresh(true);
    } finally {
      state.actionBusy = false;
      render();
    }
  }

  function bindActions(root) {
    root.querySelectorAll('[data-secret-realm-refresh]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        button.disabled = true;
        await refresh(true);
      });
    });
    root.querySelectorAll('[data-secret-realm-view]').forEach(button => {
      button.addEventListener('click', async () => {
        const view = button.dataset.secretRealmView === 'history' ? 'history' : 'current';
        state.view = view;
        render();
        if (view === 'history') await loadHistory(false);
      });
    });
    root.querySelectorAll('[data-secret-realm-history-refresh]').forEach(button => {
      button.addEventListener('click', async () => {
        button.disabled = true;
        await loadHistory(true);
      });
    });
    root.querySelector('[data-secret-realm-enter]')?.addEventListener('click', event => enterRealm(event.currentTarget));
    root.querySelector('[data-secret-realm-settle]')?.addEventListener('click', event => settleDue(event.currentTarget, false));
    root.querySelector('[data-secret-realm-claim]')?.addEventListener('click', event => claimRewards(event.currentTarget));
  }

  function updateCountdownDom() {
    const sessionData = state.data?.session || {};
    const sessionSeconds = sessionSecondsRemaining(sessionData);
    document.querySelectorAll('[data-secret-realm-session-countdown]').forEach(element => {
      element.textContent = formatDuration(sessionSeconds);
    });
    const reset = document.querySelector('[data-secret-realm-reset-countdown]');
    if (reset) reset.textContent = formatDuration(resetSecondsRemaining(state.data || {}));
  }

  function startLocalTicker() {
    if (state.localTicker) clearInterval(state.localTicker);
    state.localTicker = setInterval(() => {
      if (!document.getElementById('secretRealmRootBSecretRealm01')) return;
      updateCountdownDom();
    }, 500);
  }

  function scheduleBoundary() {
    if (state.boundaryTimer) clearTimeout(state.boundaryTimer);
    state.boundaryTimer = null;
    const data = state.data;
    const run = data?.current_run;
    if (!run || !['running', 'settling'].includes(run.status) || document.hidden) return;
    const now = serverNowMs();
    const sessionEnd = new Date(data.session?.end_at || 0).getTime();
    const nextMinute = Math.ceil(now / 60000) * 60000 + 900;
    const target = Number.isFinite(sessionEnd) && sessionEnd > 0 ? Math.min(nextMinute, sessionEnd + 900) : nextMinute;
    const delay = Math.max(1000, Math.min(61000, target - now));
    state.boundaryTimer = setTimeout(async () => {
      const slot = new Date(target).toISOString().slice(0, 16);
      if (slot !== state.lastAutoSettleSlot) {
        state.lastAutoSettleSlot = slot;
        await settleDue(null, true);
      }
      scheduleBoundary();
    }, delay);
  }

  function bindSurface() {
    const root = document.getElementById('secretRealmRootBSecretRealm01');
    if (!root) return;
    render();
    const navButton = document.querySelector('[data-mobile-tab="secret_realm"]');
    if (navButton && navButton.dataset.secretRealmBound !== '1') {
      navButton.dataset.secretRealmBound = '1';
      navButton.addEventListener('click', () => refresh(Date.now() - state.lastFetchAt > 10000));
    }
    refresh(!state.data);
  }

  window.addEventListener('jiuxiao:secret-realm-rendered', bindSurface);
  window.addEventListener('focus', () => {
    if (document.getElementById('secretRealmRootBSecretRealm01')) {
      const active = state.data?.current_run && ['running', 'settling'].includes(state.data.current_run.status);
      if (active) settleDue(null, true); else refresh(Date.now() - state.lastFetchAt > 15000);
    }
  });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) {
      if (state.boundaryTimer) clearTimeout(state.boundaryTimer);
      state.boundaryTimer = null;
      return;
    }
    if (state.data?.current_run && ['running', 'settling'].includes(state.data.current_run.status)) settleDue(null, true);
    else refresh(Date.now() - state.lastFetchAt > 15000);
  });
  window.addEventListener('pageshow', event => { if (event.persisted) bindSurface(); });
  document.addEventListener('DOMContentLoaded', () => { startLocalTicker(); bindSurface(); });

  window.B_SECRETREALM01 = Object.freeze({
    module: MODULE,
    version: '1.7.9-history5',
    refresh,
    history: loadHistory,
    settle: settleDue,
    render
  });
})();
