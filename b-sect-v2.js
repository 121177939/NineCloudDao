(() => {
  'use strict';

  const MODULE = 'B-SECT02-WORLDNET1';
  const config = window.GAME_CONFIG || {};
  const baseUrl = String(config.supabaseUrl || '').replace(/\/+$/, '');
  const apiKey = String(config.supabasePublishableKey || '');
  const projectRef = (() => { try { return new URL(baseUrl).hostname.split('.')[0]; } catch { return 'unknown'; } })();
  const sessionKey = `nine_cloud_dao_session_${projectRef}_v1`;
  const deviceKey = `nine_cloud_dao_device_${projectRef}_v1`;
  const state = { data: null, loading: false, busy: false, lastFetchAt: 0, activeTab: 'overview', phase2Available: true };

  const esc = value => String(value ?? '')
    .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;').replaceAll("'", '&#039;');
  const uuid = () => globalThis.crypto?.randomUUID?.() || 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const v = Math.random() * 16 | 0; return (c === 'x' ? v : (v & 3 | 8)).toString(16);
  });
  const session = () => { try { return JSON.parse(localStorage.getItem(sessionKey) || 'null'); } catch { return null; } };
  const num = (value, fallback = 0) => Number.isFinite(Number(value)) ? Number(value) : fallback;
  const fmt = value => num(value).toLocaleString('zh-CN', { maximumFractionDigits: 2 });
  const pct = value => `${(num(value) * 100).toLocaleString('zh-CN', { maximumFractionDigits: 2 })}%`;
  const time = value => {
    const d = value ? new Date(value) : null;
    return d && !Number.isNaN(d.getTime()) ? d.toLocaleString('zh-CN', { month:'2-digit',day:'2-digit',hour:'2-digit',minute:'2-digit',hour12:false }) : '—';
  };

  function toast(message, type = 'success') {
    const element = document.getElementById('toast');
    if (!element) return;
    element.textContent = message;
    element.className = `toast show ${type}`;
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => { element.className = 'toast'; }, 4200);
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
      ['BSECT01_DISABLED', '宗门经营当前处于维护状态。'],
      ['BSECT02_NPC_ACTION_COOLDOWN', '世界宗门往来尚在冷却中。'],
      ['BSECT02_RELATION_TOO_LOW', '双方关系尚不足以开展这项合作。'],
      ['BSECT02_CERTIFICATION_RELATION_REQUIRED', '至少达到友好关系后才能申请晋升认证。'],
      ['BSECT02_TREASURY_STONES_INSUFFICIENT', '宗门库藏灵石不足。'],
      ['BSECT02_TREASURY_SUPPLIES_INSUFFICIENT', '宗门物资不足。'],
      ['BSECT02_MARKET_DAILY_SOFT_CAP_REACHED', '本宗门今日市场成交额已达到软上限。'],
      ['BSECT02_MARKET_SOFT_CAP_EXCEEDED', '这张订单超过单笔市场上限。'],
      ['BSECT02_MARKET_ORDER_NOT_AVAILABLE', '这张订单已经成交、取消或过期。'],
      ['BSECT02_SELF_TRADE_FORBIDDEN', '不能与自己的宗门订单成交。'],
      ['BSECT02_DISCIPLE_ALREADY_ON_ADVENTURE', '选中的弟子已有正在进行的历练。'],
      ['BSECT02_DISCIPLE_NOT_IDLE_OR_NOT_OWNED', '只能选择本宗门当前空闲的弟子。'],
      ['BSECT02_NPC_SECT_REQUIRED', '共同历练必须选择一个世界宗门。'],
      ['BSECT02_STAGE_REQUIREMENTS_NOT_MET', '当前弟子、评分、资源或认证尚未达到晋升要求。'],
      ['BSECT02_PROMOTION_TRIAL_REQUIRED', '晋升圣地道门或万古仙宗必须进行多阶段试炼。'],
      ['BSECT02_TRIAL_COOLDOWN', '晋升试炼失败冷却尚未结束。'],
      ['BSECT02_TRIAL_NOT_ACTIVE', '该晋升试炼已经结束。'],
      ['BSECT02_OPENING_DISCIPLE_CANNOT_EXPEL', '开山大弟子不能被逐出宗门。'],
      ['BSECT02_DISABLED', '宗门第二阶段当前处于维护状态。'],
      ['BSECT02_MARKET_DISABLED', '跨宗门市场当前处于维护状态。'],
      ['BSECT02_NPC_DIPLOMACY_DISABLED', '世界宗门外交当前处于维护状态。'],
      ['BSECT02_ADVANCED_ADVENTURE_DISABLED', '高级历练当前处于维护状态。'],
      ['BSECT02_PROMOTION_DISABLED', '宗门晋升与试炼当前处于维护状态。'],
      ['BSECT02_AUTO_MANAGEMENT_DISABLED', '自动管理当前处于维护状态。'],
      ['AUTH_REQUIRED', '请先登录游戏。'],
      ['PGRST202', '宗门数据库RPC尚未安装或尚未刷新API缓存。'],
      ['Could not find the function', '宗门数据库RPC尚未安装或尚未刷新API缓存。']
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
  const stageName = code => ({ founding:'开山立派',lineage:'初具道统',rising:'声名鹊起',renowned:'名震一方',sacred:'圣地道门',immortal:'万古仙宗' }[code] || '开山立派');
  const specialtyName = code => ({combat:'战力与认证',alchemy:'丹道与疗伤',exploration:'探索与护送',trade:'商路与功法'}[code] || code || '世界宗门');
  const orderName = code => code === 'buy_supplies' ? '求购物资' : '出售物资';
  const adventureName = code => ({npc_joint_expedition:'世界宗门共同历练',trade_route:'护送宗门商路',ancient_ruins:'探索上古遗迹'}[code] || code);
  const riskName = code => ({normal:'普通风险',high:'较高风险',critical:'极高风险'}[code] || code);
  const trialChoiceName = code => ({steady:'稳守道心',bold:'破境争先',diplomatic:'借势诸宗'}[code] || code);

  function root() { return document.getElementById('sectV2RootBSect01'); }
  function setRoot(html) { const el = root(); if (el) el.innerHTML = html; }
  function cultivationProgress(d) { const cap = Math.max(0, num(d.cultivation_cap)); return cap > 0 ? Math.min(100, num(d.cultivation) / cap * 100) : 0; }
  function phase2(data = state.data) { return data?.phase2 || {}; }
  function advanced(data = state.data) { return phase2(data)?.advanced || {}; }
  function disciples(data = state.data) { return Array.isArray(data?.disciples) ? data.disciples : []; }
  function runningDiscipleIds(data = state.data) {
    const ids = new Set();
    (phase2(data).adventures || []).filter(a => a.status === 'running').forEach(a => (a.disciple_ids || []).forEach(id => ids.add(id)));
    return ids;
  }

  function loadingHtml() { return '<div class="sect-v2-loading-bsect01">正在结算宗门事务与世界往来……</div>'; }
  function unavailableHtml(message) {
    return `<div class="sect-v2-empty-bsect01"><h4>宗门经营尚未接通</h4><p>${esc(message)}</p><button class="secondary-btn" type="button" data-bsect-refresh>重新读取</button></div>`;
  }
  function lockedHtml(data) {
    return `<div class="sect-v2-callout-bsect01"><strong>开山之机尚未成熟</strong><p>当前境界：${esc(data.current_realm_name || '未知')}。达到大乘初期后，可直接建立个人宗门，无需建宗令、灵石或材料。</p></div>`;
  }
  function createHtml() {
    return `<form class="sect-v2-create-bsect01" id="createSectV2FormBsect01"><div><strong>开山立派</strong><p>只填写宗门名称。创建后会生成三名方向不同、整体质量接近的开山弟子候选。</p></div><label><span>宗门名称</span><input name="sectName" minlength="2" maxlength="16" autocomplete="off" placeholder="如：九霄剑宗" required></label><button class="primary-btn" type="submit">创建宗门</button></form>`;
  }

  function candidateCard(c, opening) {
    return `<article class="sect-v2-card-bsect01 ${opening ? 'is-opening' : ''}"><div><small>${esc(directionName(c.direction_code))}</small><h4>${esc(c.name)}</h4></div><div class="sect-v2-tags-bsect01"><span>${esc(genderName(c.gender))} · ${fmt(c.age_years)}岁</span><span>${esc(c.spirit_root_name)}</span><span>${esc(c.element_name)}属性</span>${c.realm_name ? `<span>${esc(c.realm_name)}</span>` : ''}</div><p>收入宗门后才显示主性格、详细经历与隐藏特质。</p><div class="sect-v2-actions-bsect01">${opening ? `<button class="primary-btn" type="button" data-bsect-opening="${esc(c.id)}">选为开山大弟子</button>` : `<button class="primary-btn" type="button" data-bsect-recruit="${esc(c.id)}">收入宗门</button><button class="secondary-btn" type="button" data-bsect-lock="${esc(c.id)}" ${c.status === 'locked' ? 'disabled' : ''}>${c.status === 'locked' ? '已锁定24小时' : '锁定候选'}</button>`}</div></article>`;
  }

  function discipleCard(d, options = {}) {
    const progress = cultivationProgress(d); const capped = num(d.cultivation_cap) > 0 && num(d.cultivation) >= num(d.cultivation_cap);
    const away = runningDiscipleIds().has(d.id);
    return `<article class="sect-v2-card-bsect01"><div class="sect-v2-card-head-bsect02"><div><small>${esc(identityName(d.identity_code))}</small><h4>${esc(d.dao_name || d.name)}</h4>${d.dao_name ? `<small>本名：${esc(d.name)}</small>` : ''}</div><span class="sect-v2-status-bsect02 ${away ? 'away' : ''}">${away ? '历练中' : (capped ? '修为圆满' : assignmentName(d.assignment_type))}</span></div><div class="sect-v2-tags-bsect01"><span>${esc(d.spirit_root_name)}</span><span>${esc(d.element_name)}属性</span><span>${esc(d.realm_name)}</span><span>${esc(d.personality)}</span></div><div class="sect-v2-statline-bsect01"><span>修为 ${fmt(d.cultivation)} / ${fmt(d.cultivation_cap)}</span><span>忠诚 ${fmt(d.loyalty)} · 心境 ${fmt(d.mood)}</span></div><div class="sect-v2-progress-bsect01"><i style="width:${progress.toFixed(2)}%"></i></div><small>当前速率约 ${fmt(d.rate_per_second)}/秒 · 伤势：${esc(d.injury_status || 'healthy')}</small><div class="sect-v2-actions-bsect01"><button class="secondary-btn" type="button" data-bsect-detail="${esc(d.id)}">详情</button>${!away && (d.assignment_type === 'cultivation' ? `<button class="secondary-btn" type="button" data-bsect-assignment="${esc(d.id)}" data-assignment="idle">停止修炼</button>` : `<button class="primary-btn" type="button" data-bsect-assignment="${esc(d.id)}" data-assignment="cultivation" ${capped ? 'disabled' : ''}>开始修炼</button>`)}${options.allowExpel && d.identity_code !== 'opening_first' ? `<button class="danger-btn" type="button" data-bsect-expel="${esc(d.id)}" data-name="${esc(d.dao_name || d.name)}">逐出</button>` : ''}</div></article>`;
  }

  function tabNav() {
    const tabs = [
      ['overview','宗门总览'],['disciples','弟子与山门'],['world','世界宗门'],['market','宗门市集'],
      ['adventures','高级历练'],['promotion','晋升与托管'],['honors','排行与荣誉']
    ];
    return `<nav class="sect-v2-tabs-bsect02" aria-label="宗门页面">${tabs.map(([code,label]) => `<button type="button" data-bsect-tab="${code}" class="${state.activeTab === code ? 'active' : ''}">${label}</button>`).join('')}</nav>`;
  }

  function metric(label, value, note = '') { return `<article class="sect-v2-metric-bsect02"><span>${esc(label)}</span><strong>${esc(value)}</strong>${note ? `<small>${esc(note)}</small>` : ''}</article>`; }
  function sectionTitle(title, note = '') { return `<div class="sect-v2-section-title-bsect01"><h4>${esc(title)}</h4><span>${esc(note)}</span></div>`; }

  function overviewHtml(data) {
    const p2 = phase2(data); const treasury = p2.treasury || {}; const adv = advanced(data); const readiness = adv.readiness || {};
    const events = Array.isArray(data.recent_events) ? data.recent_events : [];
    const candidates = Array.isArray(data.candidates) ? data.candidates : [];
    const openingNeeded = !disciples(data).some(d => d.identity_code === 'opening_first');
    const opening = candidates.filter(c => c.kind === 'opening');
    return `<div class="sect-v2-view-bsect02">${openingNeeded ? `<div class="sect-v2-callout-bsect01"><strong>选择开山大弟子</strong><p>三名候选整体质量接近，分别偏修炼、偏实战与均衡。选择后不可撤销，称号永久保留但不提供额外数值。</p></div><div class="sect-v2-grid-bsect01">${opening.map(c => candidateCard(c,true)).join('')}</div>` : ''}<div class="sect-v2-metrics-bsect02">${metric('宗门综合评分',fmt(p2.score || 0),`阶段：${stageName(data.sect?.stage_code)}`)}${metric('宗门灵石',fmt(treasury.spirit_stones || 0),`下次维护：${time(treasury.next_maintenance_at)}`)}${metric('宗门物资',fmt(treasury.supplies || 0),`维护欠费：${fmt(treasury.maintenance_debt || 0)}`)}${metric('世界声望',fmt(treasury.reputation || 0),readiness.completed ? '已达万古仙宗' : `下一阶段：${readiness.display_name || '待计算'}`)}</div>${readiness && !readiness.completed ? `<section class="sect-v2-panel-bsect02"><header><div><strong>下一阶段准备度</strong><small>${esc(readiness.display_name || '')}</small></div><span class="sect-v2-ready-bsect02 ${readiness.ok ? 'ok' : ''}">${readiness.ok ? '条件已满足' : '继续经营'}</span></header><div class="sect-v2-readiness-bsect02"><span>弟子 ${fmt(readiness.alive)}/${fmt(readiness.minimum_disciples)}</span><span>达标境界弟子 ${fmt(readiness.realm_ready_count)}/${fmt(readiness.minimum_realm_disciple_count)}</span><span>评分 ${fmt(readiness.score)}/${fmt(readiness.minimum_score)}</span><span>灵石 ${fmt(readiness.spirit_stones)}/${fmt(readiness.spirit_stone_cost)}</span>${readiness.requires_trial ? `<span>友好认证宗门 ${fmt(readiness.certifying_npc_count)}/2</span>` : ''}</div></section>` : ''}${sectionTitle('世界宗门排行','前50名')}<div class="sect-v2-ranking-bsect02">${(p2.ranking || []).slice(0,8).map(r => `<article class="${r.is_mine ? 'mine' : ''}"><b>${fmt(r.rank)}</b><div><strong>${esc(r.name)}</strong><small>${stageName(r.stage_code)} · ${fmt(r.disciple_count)}名弟子</small></div><span>${fmt(r.score)}</span></article>`).join('') || '<div class="sect-v2-empty-bsect01">暂无排行数据。</div>'}</div>${sectionTitle('宗门史','最近20条')}<div class="sect-v2-log-bsect01">${events.map(e => `<article><strong>${esc(e.title)}</strong><p>${esc(e.content)}</p><small>${time(e.created_at)}</small></article>`).join('') || '<div class="sect-v2-empty-bsect01">宗门史尚无记载。</div>'}</div></div>`;
  }

  function disciplesHtml(data) {
    const list = disciples(data); const candidates = Array.isArray(data.candidates) ? data.candidates : [];
    const normal = candidates.filter(c => c.kind !== 'opening');
    return `<div class="sect-v2-view-bsect02">${sectionTitle('宗门弟子',`${list.length}/${num(data.settings?.max_disciple_count,20)} · ${list.filter(d=>d.assignment_type==='cultivation').length}人修炼中`)}<div class="sect-v2-grid-bsect01">${list.map(d => discipleCard(d,{allowExpel:true})).join('') || '<div class="sect-v2-empty-bsect01">宗门目前没有存活弟子。</div>'}</div>${sectionTitle('山门候选',data.sect?.next_candidate_refresh_at ? `下次刷新 ${time(data.sect.next_candidate_refresh_at)}` : '等待刷新')}<div class="sect-v2-grid-bsect01">${normal.map(c => candidateCard(c,false)).join('') || '<div class="sect-v2-empty-bsect01">当前没有新的拜师候选。</div>'}</div><div class="sect-v2-warning-bsect02"><strong>逐出属于危险操作</strong><p>被逐出的弟子会根据忠诚与性格成为散修、加入世界宗门或成为敌对角色；其经历永久保留。</p></div></div>`;
  }

  function worldHtml(data) {
    const p2 = phase2(data); const npcs = p2.npc_sects || [];
    if (!state.phase2Available) return unavailableHtml('第二阶段数据库尚未安装，第一阶段弟子经营仍可使用。');
    return `<div class="sect-v2-view-bsect02"><div class="sect-v2-callout-bsect01"><strong>世界宗门网络</strong><p>关系分为仇敌、敌对、冷淡、中立、友好与盟友。访问、赠礼、共同修炼和晋升认证均由服务端结算，并受冷却与库藏约束。</p></div><div class="sect-v2-grid-bsect01">${npcs.map(n => `<article class="sect-v2-card-bsect01 sect-v2-npc-bsect02"><div class="sect-v2-card-head-bsect02"><div><small>${esc(specialtyName(n.specialty_code))}</small><h4>${esc(n.name)}</h4></div><span class="sect-v2-relation-bsect02">${esc(n.relation_level)} ${fmt(n.relation_score)}</span></div><p>${esc(n.doctrine)}</p><div class="sect-v2-statline-bsect01"><span>晋升认证 ${fmt(n.certification_progress)}%</span><span>上次往来 ${time(n.last_action_at)}</span></div><div class="sect-v2-progress-bsect01"><i style="width:${Math.min(100,num(n.certification_progress))}%"></i></div><div class="sect-v2-actions-bsect01"><button class="secondary-btn" type="button" data-bsect-npc="${esc(n.code)}" data-action="visit">登门拜访</button><button class="secondary-btn" type="button" data-bsect-npc="${esc(n.code)}" data-action="gift">赠礼·500灵石</button><button class="primary-btn" type="button" data-bsect-npc="${esc(n.code)}" data-action="joint_training">共同修炼</button><button class="secondary-btn" type="button" data-bsect-npc="${esc(n.code)}" data-action="request_certification">申请认证</button></div></article>`).join('') || '<div class="sect-v2-empty-bsect01">尚未建立世界宗门档案。</div>'}</div></div>`;
  }

  function marketHtml(data) {
    const p2 = phase2(data); const treasury = p2.treasury || {}; const orders = p2.market_orders || []; const mine = p2.my_orders || [];
    if (!state.phase2Available) return unavailableHtml('第二阶段宗门市集尚未安装。');
    return `<div class="sect-v2-view-bsect02"><section class="sect-v2-panel-bsect02"><header><div><strong>发布宗门订单</strong><small>物资与灵石会在服务端托管，取消或过期后退回未成交部分</small></div><span>灵石 ${fmt(treasury.spirit_stones)} · 物资 ${fmt(treasury.supplies)}</span></header><form id="sectMarketFormBsect02" class="sect-v2-form-bsect02"><label>订单方向<select name="orderType"><option value="buy_supplies">求购物资</option><option value="sell_supplies">出售物资</option></select></label><label>数量<input name="quantity" type="number" min="1" step="1" value="10" required></label><label>单价<input name="unitPrice" type="number" min="1" step="1" value="100" required></label><label>有效小时<input name="duration" type="number" min="1" max="168" step="1" value="24" required></label><button class="primary-btn" type="submit">托管并发布</button></form></section>${sectionTitle('公开订单',`${orders.length}张可成交`)}<div class="sect-v2-market-list-bsect02">${orders.map(o => `<article><div><strong>${esc(o.sect_name)}</strong><small>${esc(orderName(o.order_type))} · 到期 ${time(o.expires_at)}</small></div><span>${fmt(o.remaining_quantity)}份 × ${fmt(o.unit_price)}灵石</span><button class="primary-btn" type="button" data-bsect-accept-order="${esc(o.id)}" data-max="${fmt(o.remaining_quantity)}">成交</button></article>`).join('') || '<div class="sect-v2-empty-bsect01">当前没有其他宗门的公开订单。</div>'}</div>${sectionTitle('我的订单',`${mine.filter(o=>o.status==='open').length}张进行中`)}<div class="sect-v2-market-list-bsect02">${mine.map(o => `<article><div><strong>${esc(orderName(o.order_type))}</strong><small>${esc(o.status)} · 到期 ${time(o.expires_at)}</small></div><span>${fmt(o.remaining_quantity)}/${fmt(o.quantity)}份 × ${fmt(o.unit_price)}</span>${o.status === 'open' ? `<button class="secondary-btn" type="button" data-bsect-cancel-order="${esc(o.id)}">取消</button>` : '<i>已结算</i>'}</article>`).join('') || '<div class="sect-v2-empty-bsect01">尚未发布订单。</div>'}</div></div>`;
  }

  function adventuresHtml(data) {
    const p2 = phase2(data); const list = p2.adventures || []; const idle = disciples(data).filter(d => d.assignment_type === 'idle' && !runningDiscipleIds(data).has(d.id)); const npcs = p2.npc_sects || [];
    if (!state.phase2Available) return unavailableHtml('第二阶段高级历练尚未安装。');
    return `<div class="sect-v2-view-bsect02"><section class="sect-v2-panel-bsect02"><header><div><strong>安排高级历练</strong><small>每队1—3名空闲弟子；到期后再次进入宗门由服务端结算</small></div></header><form id="sectAdventureFormBsect02" class="sect-v2-adventure-form-bsect02"><label>历练类型<select name="template"><option value="npc_joint_expedition">世界宗门共同历练 · 2小时 · 1500灵石</option><option value="trade_route">护送宗门商路 · 4小时 · 2500灵石</option><option value="ancient_ruins">探索上古遗迹 · 8小时 · 4000灵石</option></select></label><label>合作宗门<select name="npcCode"><option value="">不指定</option>${npcs.map(n=>`<option value="${esc(n.code)}">${esc(n.name)}</option>`).join('')}</select></label><fieldset><legend>出行弟子（最多3名）</legend><div class="sect-v2-check-grid-bsect02">${idle.map(d => `<label><input type="checkbox" name="disciple" value="${esc(d.id)}"><span>${esc(d.dao_name || d.name)} · ${esc(d.realm_name)}</span></label>`).join('') || '<span>没有可安排的空闲弟子。</span>'}</div></fieldset><button class="primary-btn" type="submit" ${idle.length ? '' : 'disabled'}>确认出发</button></form></section>${sectionTitle('历练记录',`${list.filter(a=>a.status==='running').length}队进行中`)}<div class="sect-v2-grid-bsect01">${list.map(a => `<article class="sect-v2-card-bsect01"><div class="sect-v2-card-head-bsect02"><div><small>${esc(riskName(a.risk_level))}</small><h4>${esc(adventureName(a.template_code))}</h4></div><span class="sect-v2-status-bsect02 ${a.status === 'running' ? 'away' : ''}">${esc(a.status)}</span></div><p>${a.npc_name ? `合作宗门：${esc(a.npc_name)}` : '独立宗门行动'} · ${fmt((a.disciple_ids || []).length)}名弟子</p><div class="sect-v2-statline-bsect01"><span>出发 ${time(a.started_at)}</span><span>结算 ${time(a.resolves_at)}</span></div>${a.result ? `<pre class="sect-v2-result-bsect02">${esc(JSON.stringify(a.result,null,2))}</pre>` : ''}</article>`).join('') || '<div class="sect-v2-empty-bsect01">尚无高级历练记录。</div>'}</div></div>`;
  }

  function promotionHtml(data) {
    const p2 = phase2(data); const adv = advanced(data); const readiness = adv.readiness || {}; const policy = adv.auto_policy || {}; const trials = adv.trials || [];
    const activeTrial = trials.find(t => t.status === 'active'); const npcs = p2.npc_sects || [];
    if (!state.phase2Available) return unavailableHtml('第二阶段晋升与自动管理尚未安装。');
    return `<div class="sect-v2-view-bsect02"><section class="sect-v2-panel-bsect02"><header><div><strong>宗门阶段</strong><small>阶段只解锁经营内容，不直接增加弟子属性</small></div><span>${esc(adv.stage_name || stageName(data.sect?.stage_code))}</span></header>${readiness.completed ? '<div class="sect-v2-callout-bsect01"><strong>万古仙宗</strong><p>宗门已达到当前最高阶段。</p></div>' : `<div class="sect-v2-readiness-bsect02"><span>目标：${esc(readiness.display_name || '待计算')}</span><span>弟子 ${fmt(readiness.alive)}/${fmt(readiness.minimum_disciples)}</span><span>境界达标 ${fmt(readiness.realm_ready_count)}/${fmt(readiness.minimum_realm_disciple_count)}</span><span>评分 ${fmt(readiness.score)}/${fmt(readiness.minimum_score)}</span><span>灵石 ${fmt(readiness.spirit_stones)}/${fmt(readiness.spirit_stone_cost)}</span>${readiness.requires_trial ? `<span>友好认证 ${fmt(readiness.certifying_npc_count)}/2</span>` : ''}</div><div class="sect-v2-actions-bsect01">${readiness.requires_trial ? `<button class="primary-btn" type="button" data-bsect-start-trial ${activeTrial || !readiness.ok ? 'disabled' : ''}>开启多阶段晋升试炼</button>` : `<button class="primary-btn" type="button" data-bsect-advance-stage ${!readiness.ok ? 'disabled' : ''}>确认晋升</button>`}</div>`}</section>${activeTrial ? `<section class="sect-v2-panel-bsect02 sect-v2-trial-bsect02"><header><div><strong>${esc(activeTrial.target_stage_name)}试炼</strong><small>第 ${fmt(activeTrial.current_phase + 1)} / ${fmt(activeTrial.phase_count)} 阶段</small></div><span>${fmt(activeTrial.total_score)} / ${fmt(activeTrial.required_score)}</span></header><p>每阶段选择一种策略，由服务端随机结算。试炼失败只损失配置比例的晋升资源并进入冷却。</p><div class="sect-v2-actions-bsect01"><button class="secondary-btn" type="button" data-bsect-trial="${esc(activeTrial.id)}" data-choice="steady">${trialChoiceName('steady')}</button><button class="primary-btn" type="button" data-bsect-trial="${esc(activeTrial.id)}" data-choice="bold">${trialChoiceName('bold')}</button><button class="secondary-btn" type="button" data-bsect-trial="${esc(activeTrial.id)}" data-choice="diplomatic">${trialChoiceName('diplomatic')}</button></div></section>` : ''}<section class="sect-v2-panel-bsect02"><header><div><strong>峰主 / 大长老自动管理策略</strong><small>按需同步时执行，无Cron、无后台高频任务</small></div></header><form id="sectAutoPolicyFormBsect02" class="sect-v2-form-bsect02"><label class="sect-v2-switch-bsect02"><input type="checkbox" name="enabled" ${policy.enabled ? 'checked' : ''}><span>启用自动管理</span></label><label class="sect-v2-switch-bsect02"><input type="checkbox" name="autoCultivate" ${policy.auto_cultivate_idle !== false ? 'checked' : ''}><span>自动安排空闲弟子修炼</span></label><label>忠诚保护线<input type="number" name="loyalty" min="0" max="100" value="${num(policy.protect_loyalty_below,35)}"></label><label>宗门灵石保留线<input type="number" name="reserve" min="0" step="1" value="${num(policy.reserve_spirit_stones,5000)}"></label><label>优先往来宗门<select name="npc"><option value="">不指定</option>${npcs.map(n=>`<option value="${esc(n.code)}" ${policy.npc_preferred_code===n.code?'selected':''}>${esc(n.name)}</option>`).join('')}</select></label><button class="primary-btn" type="submit">保存策略</button></form></section>${sectionTitle('晋升试炼历史',`${trials.length}条`)}<div class="sect-v2-log-bsect01">${trials.map(t=>`<article><strong>${esc(t.target_stage_name)} · ${esc(t.status)}</strong><p>阶段 ${fmt(t.current_phase)}/${fmt(t.phase_count)} · 得分 ${fmt(t.total_score)}/${fmt(t.required_score)} · 托管 ${fmt(t.escrow_spirit_stones)}灵石</p><small>${time(t.started_at)}${t.cooldown_until ? ` · 冷却至 ${time(t.cooldown_until)}` : ''}</small></article>`).join('') || '<div class="sect-v2-empty-bsect01">尚无晋升试炼。</div>'}</div></div>`;
  }

  function honorsHtml(data) {
    const p2 = phase2(data); const adv = advanced(data); const honors = adv.honors || []; const wars = adv.war_observations || [];
    if (!state.phase2Available) return unavailableHtml('第二阶段排行与荣誉尚未安装。');
    return `<div class="sect-v2-view-bsect02">${sectionTitle('世界宗门排行','服务端综合评分')}<div class="sect-v2-ranking-bsect02">${(p2.ranking || []).map(r => `<article class="${r.is_mine ? 'mine' : ''}"><b>${fmt(r.rank)}</b><div><strong>${esc(r.name)}</strong><small>${stageName(r.stage_code)} · 声望 ${fmt(r.reputation)}</small></div><span>${fmt(r.score)}</span></article>`).join('') || '<div class="sect-v2-empty-bsect01">暂无排行。</div>'}</div>${sectionTitle('历史荣誉',`${honors.length}项`)}<div class="sect-v2-grid-bsect01">${honors.map(h=>`<article class="sect-v2-card-bsect01"><small>${time(h.awarded_at)}</small><h4>${esc(h.title)}</h4><p>${esc(h.description)}</p><strong>荣誉点 ${fmt(h.points)}</strong></article>`).join('') || '<div class="sect-v2-empty-bsect01">尚未获得第二阶段荣誉。</div>'}</div>${sectionTitle('正式宗门战争观战','封闭测试 · 默认关闭')}<div class="sect-v2-callout-bsect01"><strong>${adv.war_spectator_enabled ? '只读观战已开放' : '只读观战未开放'}</strong><p>第二阶段不产生真实伤势、资源损失或建筑损坏。只有ADMIN9明确开启并发布观战数据后才会显示。</p></div>${wars.length ? `<div class="sect-v2-log-bsect01">${wars.map(w=>`<article><strong>${esc(w.title)}</strong><p>${esc(w.attacker_name)} 对 ${esc(w.defender_name)} · ${esc(w.status)}<br>${esc(w.summary || '')}</p><small>${time(w.starts_at)}</small></article>`).join('')}</div>` : ''}</div>`;
  }

  function dashboardHtml(data) {
    const sect = data.sect || {}; const p2 = phase2(data); const treasury = p2.treasury || {};
    const views = {overview:overviewHtml,disciples:disciplesHtml,world:worldHtml,market:marketHtml,adventures:adventuresHtml,promotion:promotionHtml,honors:honorsHtml};
    const view = views[state.activeTab] || overviewHtml;
    return `<div class="sect-v2-shell-bsect01"><header class="sect-v2-head-bsect01"><div><span>B-SECT02 · 世界宗门与经济网络</span><strong>${esc(sect.name)}</strong><small>${stageName(sect.stage_code)} · 弟子 ${disciples(data).length}/${num(data.settings?.max_disciple_count,20)} · 综合评分 ${fmt(p2.score || 0)}</small></div><div class="sect-v2-resource-chips-bsect02"><span>灵石 <b>${fmt(treasury.spirit_stones || 0)}</b></span><span>物资 <b>${fmt(treasury.supplies || 0)}</b></span><span>声望 <b>${fmt(treasury.reputation || 0)}</b></span><button class="secondary-btn" type="button" data-bsect-refresh>结算并刷新</button></div></header>${tabNav()}${view(data)}</div>`;
  }

  function render() {
    const el = root(); if (!el) return;
    if (state.loading && !state.data) { setRoot(loadingHtml()); return; }
    const data = state.data;
    if (!data) setRoot(unavailableHtml('等待宗门数据。'));
    else if (data.status === 'unavailable') setRoot(unavailableHtml(data.error || '数据库尚未安装。'));
    else if (data.status === 'no_character') setRoot(unavailableHtml('未找到当前角色。'));
    else if (data.status === 'no_sect') setRoot(data.unlocked ? createHtml() : lockedHtml(data));
    else setRoot(dashboardHtml(data));
    bind();
  }

  async function fetchDashboard(sync = true) {
    if (state.phase2Available) {
      try {
        return sync ? await rpc('sync_sect_v2_phase2_dashboard_bsect02', { p_request_id: uuid() }) : await rpc('get_sect_v2_phase2_dashboard_bsect02');
      } catch (error) {
        const raw = String(error?.message || error || '');
        if (!raw.includes('PGRST202') && !raw.includes('Could not find the function') && !raw.includes('BSECT02_SQL')) throw error;
        state.phase2Available = false;
      }
    }
    const base = sync ? await rpc('sync_sect_v2_dashboard_bsect01', { p_request_id: uuid() }) : await rpc('get_sect_v2_dashboard_bsect01');
    return base && typeof base === 'object' ? { ...base, phase2:{ installed:false, enabled:false } } : base;
  }

  async function refresh({ sync = true, silent = true } = {}) {
    if (state.loading) return state.data;
    state.loading = true; if (!state.data) render();
    try {
      state.data = await fetchDashboard(sync);
      state.lastFetchAt = Date.now(); render(); if (!silent) toast('宗门事务、维护、订单和历练已结算。'); return state.data;
    } catch (error) {
      state.data = { status:'unavailable', error:errorText(error) }; render(); if (!silent) toast(errorText(error),'error'); return state.data;
    } finally { state.loading = false; }
  }

  async function action(name, body, success, options = {}) {
    if (state.busy) return;
    state.busy = true;
    try {
      await rpc(name, options.noRequestId ? body : { ...body, p_request_id: uuid() });
      await refresh({ sync:false, silent:true });
      toast(success);
    } catch (error) { toast(errorText(error),'error'); }
    finally { state.busy = false; }
  }

  async function showDetail(id) {
    try {
      const d = await rpc('get_sect_disciple_detail_bsect01', { p_disciple_id:id });
      const modal = document.createElement('div'); modal.className='sect-v2-modal-bsect01';
      modal.innerHTML=`<article class="sect-v2-modal-card-bsect01"><header><div><small>${esc(identityName(d.identity_code))}</small><h3>${esc(d.dao_name || d.name)}</h3></div><button class="secondary-btn" type="button" data-close>关闭</button></header><dl><div><dt>本名</dt><dd>${esc(d.name)}</dd></div><div><dt>年龄</dt><dd>${fmt(d.age_years)}岁</dd></div><div><dt>灵根</dt><dd>${esc(d.spirit_root_name)} ×${fmt(d.spirit_root_multiplier)}</dd></div><div><dt>五行</dt><dd>${esc(d.element_name)}属性</dd></div><div><dt>境界</dt><dd>${esc(d.realm_name)}</dd></div><div><dt>修为</dt><dd>${fmt(d.cultivation)} / ${fmt(d.cultivation_cap)}</dd></div><div><dt>性格</dt><dd>${esc(d.personality)}</dd></div><div><dt>特质</dt><dd>${esc((d.visible_traits || []).join('、') || '尚未显现')}</dd></div><div><dt>忠诚</dt><dd>${fmt(d.loyalty)}</dd></div><div><dt>心境</dt><dd>${fmt(d.mood)}</dd></div><div><dt>伤势</dt><dd>${esc(d.injury_status)}</dd></div><div><dt>安排</dt><dd>${esc(assignmentName(d.assignment_type))}</dd></div></dl><p class="sect-v2-meta-bsect01">所有修炼、资产、离宗和晋升结果均由服务端权威结算；客户端不上传属性或结果。</p></article>`;
      document.body.appendChild(modal); const close=()=>modal.remove(); modal.addEventListener('click',e=>{if(e.target===modal||e.target.closest('[data-close]'))close();});
    } catch (error) { toast(errorText(error),'error'); }
  }

  function bind() {
    const el = root(); if (!el) return;
    el.querySelectorAll('[data-bsect-tab]').forEach(b => b.addEventListener('click', () => { state.activeTab=b.dataset.bsectTab; render(); window.scrollTo({top:0,behavior:'smooth'}); }));
    el.querySelectorAll('[data-bsect-refresh]').forEach(b=>b.addEventListener('click',()=>refresh({sync:true,silent:false})));
    el.querySelector('#createSectV2FormBsect01')?.addEventListener('submit', e => { e.preventDefault(); const name = new FormData(e.currentTarget).get('sectName'); action('create_sect_v2_bsect01',{p_name:String(name||'').trim()},'宗门已创建，请选择开山大弟子。'); });
    el.querySelectorAll('[data-bsect-opening]').forEach(b=>b.addEventListener('click',()=>{ if(confirm('开山大弟子一经选择不可撤销，确认选择？')) action('choose_opening_disciple_bsect01',{p_candidate_id:b.dataset.bsectOpening},'开山大弟子已经入门。'); }));
    el.querySelectorAll('[data-bsect-recruit]').forEach(b=>b.addEventListener('click',()=>action('recruit_sect_candidate_bsect01',{p_candidate_id:b.dataset.bsectRecruit},'新弟子已经入门。')));
    el.querySelectorAll('[data-bsect-lock]').forEach(b=>b.addEventListener('click',()=>action('lock_sect_candidate_bsect01',{p_candidate_id:b.dataset.bsectLock},'候选弟子已锁定24小时。')));
    el.querySelectorAll('[data-bsect-assignment]').forEach(b=>b.addEventListener('click',()=>action('set_sect_disciple_assignment_bsect01',{p_disciple_id:b.dataset.bsectAssignment,p_assignment_type:b.dataset.assignment},b.dataset.assignment==='cultivation'?'弟子已开始持续修炼。':'弟子已停止修炼。')));
    el.querySelectorAll('[data-bsect-detail]').forEach(b=>b.addEventListener('click',()=>showDetail(b.dataset.bsectDetail)));
    el.querySelectorAll('[data-bsect-expel]').forEach(b=>b.addEventListener('click',()=>{ if(confirm(`确认将“${b.dataset.name}”逐出宗门？其世界去向将永久记录。`)) action('expel_sect_disciple_bsect02',{p_disciple_id:b.dataset.bsectExpel},'弟子已离宗，世界去向已经记录。'); }));
    el.querySelectorAll('[data-bsect-npc]').forEach(b=>b.addEventListener('click',()=>action('interact_npc_sect_bsect02',{p_npc_code:b.dataset.bsectNpc,p_action_code:b.dataset.action},'世界宗门往来已完成。')));
    el.querySelector('#sectMarketFormBsect02')?.addEventListener('submit', e => { e.preventDefault(); const f=new FormData(e.currentTarget); action('create_sect_market_order_bsect02',{p_order_type:f.get('orderType'),p_quantity:Number(f.get('quantity')),p_unit_price:Number(f.get('unitPrice')),p_duration_hours:Number(f.get('duration'))},'宗门订单已发布并完成托管。'); });
    el.querySelectorAll('[data-bsect-accept-order]').forEach(b=>b.addEventListener('click',()=>{ const q=Number(prompt(`输入成交数量（最多${b.dataset.max}）`,String(Math.min(10,Number(b.dataset.max)||1)))); if(Number.isFinite(q)&&q>0) action('accept_sect_market_order_bsect02',{p_order_id:b.dataset.bsectAcceptOrder,p_quantity:Math.floor(q)},'订单已成交，资产已原子结算。'); }));
    el.querySelectorAll('[data-bsect-cancel-order]').forEach(b=>b.addEventListener('click',()=>{if(confirm('取消后未成交的托管资产会退回宗门库藏，确认取消？')) action('cancel_sect_market_order_bsect02',{p_order_id:b.dataset.bsectCancelOrder},'订单已取消，剩余托管资产已退回。');}));
    el.querySelector('#sectAdventureFormBsect02')?.addEventListener('submit', e => { e.preventDefault(); const f=new FormData(e.currentTarget); const ids=f.getAll('disciple').slice(0,3); if(!ids.length){toast('至少选择一名空闲弟子。','error');return;} if(f.getAll('disciple').length>3){toast('每次历练最多选择三名弟子。','error');return;} action('start_sect_adventure_bsect02',{p_template_code:f.get('template'),p_npc_code:f.get('npcCode')||null,p_disciple_ids:ids},'弟子队伍已出发，返回宗门时按需结算。'); });
    el.querySelector('[data-bsect-advance-stage]')?.addEventListener('click',()=>{if(confirm('确认消耗宗门资源并晋升？已晋升阶段不会因评分下降而降级。')) action('advance_sect_stage_bsect02',{},'宗门阶段晋升完成。');});
    el.querySelector('[data-bsect-start-trial]')?.addEventListener('click',()=>{if(confirm('确认托管晋升资源并开启多阶段试炼？失败会损失规定比例并进入冷却。')) action('start_sect_promotion_trial_bsect02',{},'晋升试炼已经开启。');});
    el.querySelectorAll('[data-bsect-trial]').forEach(b=>b.addEventListener('click',()=>action('advance_sect_promotion_trial_bsect02',{p_trial_id:b.dataset.bsectTrial,p_choice_code:b.dataset.choice},`已选择“${trialChoiceName(b.dataset.choice)}”，本阶段由服务端结算。`)));
    el.querySelector('#sectAutoPolicyFormBsect02')?.addEventListener('submit', e => { e.preventDefault(); const f=new FormData(e.currentTarget); action('set_sect_auto_policy_bsect02',{p_enabled:f.get('enabled')==='on',p_auto_cultivate_idle:f.get('autoCultivate')==='on',p_protect_loyalty_below:Number(f.get('loyalty')),p_reserve_spirit_stones:Number(f.get('reserve')),p_npc_preferred_code:f.get('npc')||null},'自动管理策略已保存。'); });
  }

  function onRendered() {
    if (!root()) return;
    render();
    if (!state.data || Date.now() - state.lastFetchAt > 60_000) refresh({ sync:true, silent:true });
  }

  window.addEventListener('jiuxiao:sect-v2-rendered', onRendered);
  window.addEventListener('jiuxiao:sect-v2-refresh', () => refresh({sync:true,silent:true}));
  window.addEventListener('focus', () => { if (root() && Date.now()-state.lastFetchAt>60_000) refresh({sync:true,silent:true}); }, { passive:true });
  const api = { module:MODULE, refresh, render, state:() => state.data, setTab:tab=>{state.activeTab=tab;render();} };
  window.B_SECTV2_B02 = api;
  window.B_SECTV2_B01 = api;
})();
