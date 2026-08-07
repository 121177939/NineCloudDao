(() => {
  'use strict';

  const MODULE = 'B-SECT06-AUTONOMY2000';
  const config = window.GAME_CONFIG || {};
  const baseUrl = String(config.supabaseUrl || '').replace(/\/+$/, '');
  const apiKey = String(config.supabasePublishableKey || '');
  const projectRef = (() => { try { return new URL(baseUrl).hostname.split('.')[0]; } catch { return 'unknown'; } })();
  const sessionKey = `nine_cloud_dao_session_${projectRef}_v1`;
  const deviceKey = `nine_cloud_dao_device_${projectRef}_v1`;
  const state = { data: null, loading: false, busy: false, lastFetchAt: 0, lastAutoSyncAt: 0, activeTab: 'overview', phase2Available: true, growthAvailable: true, eventSyncAvailable: true, socialAvailable: true, partnerAvailable: true, autonomyAvailable: true, contributionCatalog: null, timer: null, serverOffsetMs: 0, autonomousBreakthroughPolicyRepairing: false, autonomousBreakthroughPolicyRepaired: false };

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
      ['BSECT03_CULTIVATION_NOT_FULL', '弟子修为尚未圆满，不能突破。'],
      ['BSECT03_MANUAL_REQUIRED', '该突破由弟子自主决定，宗主不能手动发起。'],
      ['BSECT03_DISCIPLE_INJURED', '重伤或濒死弟子不能修炼、闭关或突破。'],
      ['BSECT03_DISCIPLE_AWAY', '外出历练中的弟子不能更改事务或突破。'],
      ['BSECT03_BREAKTHROUGH_PILLS_INSUFFICIENT', '宗门库藏中的渡境清元丹不足。'],
      ['BSECT03_MAXIMUM_REALM', '该弟子已经达到当前最高境界。'],
      ['BSECT03_BREAKTHROUGH_TOO_FREQUENT', '突破请求过于频繁，请稍后再试。'],
      ['BSECT03_AUTO_RETRY_COOLDOWN', '自动突破重试尚在冷却中。'],
      ['BSECT03_INVALID_ASSIGNMENT', '弟子事务类型无效。'],
      ['BSECT03_RETREAT_DISABLED', '随机闭关当前处于维护状态。'],
      ['BSECT03_HEALING_NOT_REQUIRED', '该弟子当前无需疗伤。'],
      ['BSECT03_BREAKTHROUGH_DISABLED', '弟子突破当前处于维护状态。'],
      ['BSECT03_DISABLED', '宗门弟子成长系统当前处于维护状态。'],
      ['BSECT04_LINEUP_REQUIRES_THREE', '普通切磋阵容必须选择三名弟子。'],
      ['BSECT04_LINEUP_DUPLICATE_DISCIPLE', '切磋阵容不能重复选择同一名弟子。'],
      ['BSECT04_LINEUP_DISCIPLE_NOT_OWNED', '阵容中存在不属于本宗门的弟子。'],
      ['BSECT04_LINEUP_DISCIPLE_UNAVAILABLE', '阵容弟子当前无法生成切磋快照。'],
      ['BSECT04_LINEUP_REQUIRED', '请先设置三人切磋阵容。'],
      ['BSECT04_DAILY_SPARRING_LIMIT', '今日主动切磋次数已达上限。'],
      ['BSECT04_NO_MATCHED_OPPONENT', '当前没有强度接近且可挑战的宗门。'],
      ['BSECT04_SPARRING_DISABLED', '宗门普通切磋当前处于维护状态。'],
      ['BSECT04_POSITIONS_DISABLED', '弟子身份与职务管理当前处于维护状态。'],
      ['BSECT04_MASTER_APPRENTICE_DISABLED', '师徒系统当前处于维护状态。'],
      ['BSECT04_IMPORTANT_EVENTS_DISABLED', '宗主决断当前处于维护状态。'],
      ['BSECT04_DIRECT_LIMIT_REACHED', '亲传弟子最多三名。'],
      ['BSECT04_CHIEF_LIMIT_REACHED', '首席弟子只能有一名。'],
      ['BSECT04_GRAND_ELDER_LIMIT_REACHED', '大长老只能有一名。'],
      ['BSECT04_PEAK_MASTER_LIMIT_REACHED', '峰主名额已达到上限。'],
      ['BSECT04_MASTER_OFFICE_REQUIRED', '只有长老、峰主或大长老可以正式收徒。'],
      ['BSECT04_MASTER_APPRENTICE_LIMIT_REACHED', '该师父的收徒名额已满。'],
      ['BSECT04_EVENT_ALREADY_RESOLVED', '这个人物事件已经处理。'],
      ['BSECT04_INVALID_EVENT_CHOICE', '人物事件选项无效。'],
      ['BSECT04_TREASURY_STONES_INSUFFICIENT', '宗门库藏灵石不足以执行这个选择。'],
      ['BSECT04_DISABLED', '宗门人物与切磋系统当前处于维护状态。'],
      ['BSECT05_PARTNER_DISABLED', '宗门道侣系统当前处于维护状态。'],
      ['BSECT05_PARTNER_REQUIREMENTS_NOT_MET', '双方好感、心境或忠诚尚未达到结为道侣的条件。'],
      ['BSECT05_DISCIPLE_ALREADY_PARTNERED', '其中一名弟子已经拥有道侣。'],
      ['BSECT05_PROPOSAL_NOT_FOUND', '道侣提案不存在。'],
      ['BSECT05_PROPOSAL_ALREADY_RESOLVED', '这个道侣提案已经处理。'],
      ['BSECT05_PROPOSAL_EXPIRED', '这个道侣提案已经过期。'],
      ['BSECT05_BOND_NOT_ACTIVE', '这段道侣关系已经解除。'],
      ['BSECT05_MANAGER_OFFICE_REQUIRED', '自动托管负责人必须是峰主或大长老。'],
      ['BSECT05_DAILY_WINS_NOT_ENOUGH', '今日切磋胜场尚未达到领取条件。'],
      ['BSECT05_DAILY_REWARD_ALREADY_CLAIMED', '今日切磋奖励已经领取。'],
      ['BSECT05_SEASON_DISABLED', '普通切磋赛季当前处于维护状态。'],
      ['BSECT05_DISABLED', '宗门道侣、托管与赛季系统当前处于维护状态。'],
      ['BSECT06_DISABLED', '宗门自主生态当前处于维护状态。'],
      ['BSECT06_SECT_NOT_FOUND', '没有找到当前角色的宗门。'],
      ['BSECT06_CHARACTER_OR_SECT_NOT_FOUND', '没有找到当前角色或宗门。'],
      ['BSECT06_ASSET_NOT_FOUND', '宗门库藏中没有找到这项资产。'],
      ['BSECT06_ASSET_QUANTITY_INSUFFICIENT', '宗门库藏资产数量不足。'],
      ['BSECT06_INVENTORY_ITEM_NOT_FOUND', '个人背包中没有找到这项物品。'],
      ['BSECT06_EQUIPMENT_NOT_FOUND', '个人背包中没有找到这件装备。'],
      ['BSECT06_SPIRIT_STONES_INSUFFICIENT', '个人灵石不足。'],
      ['BSECT06_DISCIPLE_NOT_FOUND', '没有找到这名宗门弟子。'],
      ['BSECT06_REQUEST_ID_REQUIRED', '请求编号缺失，请刷新后重试。'],
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

  const identityName = code => ({ opening_first:'开山大弟子',registered:'记名弟子',outer:'外门弟子',inner:'内门弟子',direct:'亲传弟子',steward:'执事',elder:'长老',peak_master:'峰主',grand_elder:'大长老',chief:'首席弟子' }[code] || '弟子');
  const directionName = code => ({ cultivation:'修炼倾向',combat:'实战倾向',balanced:'均衡倾向' }[code] || '均衡倾向');
  const assignmentName = code => ({ cultivation:'持续修炼中', retreat:'随机闭关中', healing:'疗伤休养中', idle:'等待安排' }[code] || '等待安排');
  const genderName = code => code === 'female' ? '女' : '男';
  const stageName = code => ({ founding:'开山立派',lineage:'初具道统',rising:'声名鹊起',renowned:'名震一方',sacred:'圣地道门',immortal:'万古仙宗' }[code] || '开山立派');
  const specialtyName = code => ({combat:'战力与认证',alchemy:'丹道与疗伤',exploration:'探索与护送',trade:'商路与功法'}[code] || '世界宗门');
  const orderName = code => code === 'buy_supplies' ? '求购物资' : '出售物资';
  const adventureName = code => ({npc_joint_expedition:'世界宗门共同历练',trade_route:'护送宗门商路',ancient_ruins:'探索上古遗迹'}[code] || '宗门历练');
  const riskName = code => ({normal:'普通风险',high:'较高风险',critical:'极高风险'}[code] || '宗门历练');
  const trialChoiceName = code => ({steady:'稳守道心',bold:'破境争先',diplomatic:'借势诸宗'}[code] || '宗门历练');
  const identityRankName = code => ({registered:'记名弟子',outer:'外门弟子',inner:'内门弟子',direct:'亲传弟子',chief:'首席弟子'}[code] || '记名弟子');
  const officeName = code => ({none:'无职务',steward:'执事',elder:'长老',peak_master:'峰主',grand_elder:'大长老'}[code] || '无职务');
  const relationName = code => ({acquaintance:'同门',friend:'好友',close_friend:'挚友',rival:'竞争',dislike:'厌恶',hatred:'仇恨',admiration:'爱慕',romance:'相恋',dao_partner:'道侣'}[code] || '同门');

  const eventCategoryName = code => ({cultivation:'修炼',breakthrough:'突破',personality:'性格心境',master:'师徒',relationship:'同门关系',partner:'道侣',governance:'宗门治理',resource:'资源',treasure:'机缘宝物',adventure:'历练',injury:'伤势',infrastructure:'山峰建筑',diplomacy:'外交',honor:'荣誉切磋'}[String(code||'').toLowerCase()] || '其他动态');
  const activityName = value => {
    const raw=String(value||'').trim();
    if(!raw) return '自主生活';
    if(/[\u3400-\u9fff]/.test(raw)) return raw;
    const key=raw.toLowerCase();
    return ({cultivation:'自主修炼',retreat:'自主闭关',healing:'疗伤休养',idle:'休整观察',breakthrough:'准备突破',breakthrough_ready:'准备突破',prepare_breakthrough:'准备突破',waiting_breakthrough:'等待突破',adventure:'外出历练',training:'修炼',rest:'休整'}[key] || '自主行动');
  };
  const statusName = value => {
    const raw=String(value||'').trim(); if(!raw) return '—'; if(/[\u3400-\u9fff]/.test(raw)) return raw;
    return ({healthy:'健康',light:'轻伤',heavy:'重伤',dying:'濒死',active:'进行中',completed:'已完成',resolved:'已结算',failed:'失败',success:'成功',open:'进行中',closed:'已结束',pending:'待处理',ordinary:'普通',important:'重要',critical:'重大'}[raw.toLowerCase()] || '其他状态');
  };
  const storyStatusName = value => ({active:'进行中',completed:'已完成',resolved:'已结算',failed:'已中断',paused:'暂缓'}[String(value||'').toLowerCase()] || '故事进行中');
  const importanceName = value => ({ordinary:'普通经历',important:'重要经历',critical:'重大经历',permanent:'永久记忆'}[String(value||'').toLowerCase()] || '人物经历');
  function autonomyReasonText(value, activity = '') {
    const raw = String(value || '').trim();
    const names = {
      AUTONOMOUS_CHOICE: `弟子依据性格、心境、关系与宗门方略，自主选择了${activity || '当前行动'}。`,
      AUTONOMOUS_DECISION: `弟子完成了一次自主评估，并选择继续${activity || '当前行动'}。`,
      AUTO_CHOICE: `弟子自主选择了${activity || '当前行动'}。`
    };
    if (names[raw]) return names[raw];
    if (/^[A-Z][A-Z0-9_]{2,}$/.test(raw)) return `弟子完成自主判断，当前选择：${activity || '按自身状态行动'}。`;
    return raw || `弟子正在观察自身状态与宗门环境，准备下一次自主选择。`;
  }
  function parseMaybeJson(value) {
    if (value == null) return null;
    if (typeof value === 'object') return value;
    if (typeof value !== 'string') return null;
    const text = value.trim(); if (!text || !/^[\[{]/.test(text)) return null;
    try { return JSON.parse(text); } catch { return null; }
  }
  function signedValue(value) {
    const n = Number(value); if (!Number.isFinite(n) || n === 0) return '';
    return `${n > 0 ? '+' : ''}${fmt(n)}`;
  }
  function eventOutcomeParts(event) {
    const summary = String(event?.summary || event?.content || '');
    const embedded = summary.match(/【结算[：:]([^】]+)】/);
    if (embedded) return embedded[1].split(/[；;]/).map(x=>x.trim()).filter(Boolean);
    const roots = [event,event?.effects_json,event?.effect_json,event?.result_json,event?.outcome_json,event?.reward_json,event?.payload_json,event?.metadata,event?.effects,event?.effect,event?.result,event?.outcome,event?.reward,event?.payload]
      .map(parseMaybeJson).filter(Boolean);
    const parts = []; const seen = new Set();
    const push = text => { const t=String(text||'').trim(); if(t && !seen.has(t)){seen.add(t);parts.push(t);} };
    const keyMap = new Map([
      ['cultivation_delta','修为'],['cultivation_gain','修为'],['exp_delta','修为'],['exp_gain','修为'],
      ['spirit_stones_delta','宗门灵石'],['spirit_stones_gain','宗门灵石'],['spirit_stone_delta','宗门灵石'],['stones_delta','宗门灵石'],
      ['supplies_delta','宗门物资'],['supplies_gain','宗门物资'],['reputation_delta','宗门声望'],['reputation_gain','宗门声望'],
      ['loyalty_delta','忠诚'],['mood_delta','心境'],['contribution_delta','贡献'],['contribution_gain','贡献'],
      ['breakthrough_pills_delta','渡境丹'],['pill_delta','丹药']
    ]);
    const typeMap = {cultivation:'修为',exp:'修为',spirit_stones:'宗门灵石',spirit_stone:'宗门灵石',stones:'宗门灵石',supplies:'宗门物资',reputation:'宗门声望',loyalty:'忠诚',mood:'心境',contribution:'贡献',breakthrough_pill:'渡境丹',pill:'丹药'};
    const walk = (node, depth=0) => {
      if (depth>7 || node==null) return;
      if (Array.isArray(node)) { node.forEach(x=>walk(x,depth+1)); return; }
      if (typeof node !== 'object') return;
      const type = String(node.type ?? node.kind ?? node.effect_type ?? node.asset_type ?? '').toLowerCase();
      const amount = node.amount ?? node.delta ?? node.change ?? node.gain;
      if (typeMap[type] && Number.isFinite(Number(amount)) && Number(amount)!==0) push(`${typeMap[type]} ${signedValue(amount)}`);
      for (const [k,v] of Object.entries(node)) {
        const lk=String(k).toLowerCase();
        if (keyMap.has(lk) && Number.isFinite(Number(v)) && Number(v)!==0) push(`${keyMap.get(lk)} ${signedValue(v)}`);
        if (['technique_name','manual_name','skill_name','cultivation_method_name','item_name','item_display_name','asset_name','reward_name'].includes(lk) && typeof v==='string' && v.trim()) {
          const q=Number(node.quantity ?? node.qty ?? node.count ?? 1); push(`获得 ${v.trim()}${Number.isFinite(q)&&q>1?` ×${fmt(q)}`:''}`);
        }
        if (['injury_status','status_change','new_status'].includes(lk) && typeof v==='string' && v.trim()) push(`状态：${statusName(v.trim())}`);
        if (typeof v==='object' && v!==null) walk(v,depth+1);
      }
    };
    roots.forEach(x=>walk(x));
    return parts.slice(0,8);
  }
  function inferredEventOutcomeParts(event) {
    const title=String(event?.title||'');
    const summary=humanizeEventText(String(event?.summary||event?.content||'').replace(/【结算[：:][^】]+】/g,'').trim());
    const parts=[]; const push=text=>{const t=String(text||'').trim();if(t&&!parts.includes(t))parts.push(t);};
    const successTarget=summary.match(/成功突破至([^。；;，,]+)/);
    if(/突破成功/.test(title)||successTarget){
      push('突破成功');
      if(successTarget?.[1]) push(`境界提升至${successTarget[1].trim()}`);
    }
    if(/突破失败/.test(title)||/突破失败/.test(summary)){
      push('突破失败');
      if(/境界与修为没有损失|境界没有损失/.test(summary)) push('境界无损失');
      if(/境界与修为没有损失|修为没有损失/.test(summary)) push('修为无损失');
    }
    if(/疗伤/.test(title)||/疗伤/.test(summary)){
      if(/完成/.test(title)||/完成/.test(summary)) push('疗伤阶段完成');
      if(/健康/.test(summary)) push('当前状态：健康');
      else if(/轻伤/.test(summary)) push('当前状态：轻伤');
      else if(/重伤/.test(summary)) push('当前状态：重伤');
      else if(/濒死/.test(summary)) push('当前状态：濒死');
    }
    return parts.slice(0,6);
  }
  function eventOutcomeHtml(event) {
    const actual=eventOutcomeParts(event);
    if(actual.length) return `<div class="sect-v2-event-outcome-bsect07"><b>实际变化</b><span>${actual.map(esc).join(' · ')}</span></div>`;
    const inferred=inferredEventOutcomeParts(event);
    if(inferred.length) return `<div class="sect-v2-event-outcome-bsect07 is-summary-only-bsect09"><b>事件结果</b><span>${inferred.map(esc).join(' · ')}</span></div>`;
    return '';
  }

  function humanizeEventText(value) {
    let text=String(value||'');
    const replacements=[
      [/AUTONOMOUS_CHOICE/g,'自主选择当前行动'],[/AUTONOMOUS_DECISION/g,'自主完成行动评估'],[/AUTO_CHOICE/g,'自主选择当前行动'],
      [/\bhealthy\b/gi,'健康'],[/\bheavy\b/gi,'重伤'],[/\bdying\b/gi,'濒死'],[/\blight\b/gi,'轻伤'],
      [/\bcultivation\b/gi,'修炼'],[/\bbreakthrough\b/gi,'突破'],[/\bretreat\b/gi,'闭关'],[/\bhealing\b/gi,'疗伤'],[/\bidle\b/gi,'休整'],
      [/\btreasure\b/gi,'机缘宝物'],[/\bhonor\b/gi,'荣誉切磋'],[/\bpersonality\b/gi,'性格心境'],[/\bresource\b/gi,'资源'],[/\badventure\b/gi,'历练'],[/\binjury\b/gi,'伤势'],[/\bgovernance\b/gi,'宗门治理'],[/\brelationship\b/gi,'同门关系']
    ];
    replacements.forEach(([pattern,label])=>{text=text.replace(pattern,label);});
    return text.replace(/\b[A-Z][A-Z0-9_]{2,}\b/g,'系统行动').trim();
  }

  function root() { return document.getElementById('sectV2RootBSect01'); }
  function setRoot(html) { const el = root(); if (el) el.innerHTML = html; }
  function cultivationProgress(d) { const cap = Math.max(0, num(d.cultivation_cap)); return cap > 0 ? Math.min(100, num(d.cultivation) / cap * 100) : 0; }
  function phase2(data = state.data) { return data?.phase2 || {}; }
  function advanced(data = state.data) { return phase2(data)?.advanced || {}; }
  function growth(data = state.data) { return data?.growth || {}; }
  function social(data = state.data) { return data?.social || {}; }
  function partnerPhase(data = state.data) { return data?.partner_phase || {}; }
  function autonomy(data = state.data) { return data?.autonomy_phase || {}; }
  function mapBy(items, key = 'disciple_id') { return new Map((Array.isArray(items) ? items : []).map(item => [String(item?.[key] || ''), item])); }
  function disciples(data = state.data) {
    const base = Array.isArray(data?.disciples) ? data.disciples : [];
    const aMap = mapBy(growth(data).assignments); const bMap = mapBy(growth(data).breakthrough_states);
    const sMap = mapBy(social(data).disciple_states);
    return base.map(item => {
      const assignment = aMap.get(String(item.id)) || null; const breakthrough = bMap.get(String(item.id)) || null;
      const person = sMap.get(String(item.id)) || null;
      const assignmentCode = assignment?.assignment_code || item.assignment_type || 'idle';
      return { ...item, growth_assignment: assignment, breakthrough_state: breakthrough, social_state: person,
        identity_rank_code: person?.identity_rank_code || item.identity_rank_code || (item.identity_code === 'opening_first' ? 'direct' : 'registered'),
        office_code: person?.office_code || item.office_code || 'none',
        next_social_event_at: person?.next_event_at || null,
        assignment_code: assignmentCode, assignment_type: assignmentCode === 'idle' ? 'idle' : 'cultivation' };
    });
  }
  function runningDiscipleIds(data = state.data) {
    const ids = new Set();
    (phase2(data).adventures || []).filter(a => a.status === 'running').forEach(a => (a.disciple_ids || []).forEach(id => ids.add(id)));
    return ids;
  }
  function nowMs() { return Date.now() + state.serverOffsetMs; }
  function durationText(ms) {
    if (!Number.isFinite(ms)) return '—'; if (ms <= 0) return '已到期';
    const total = Math.ceil(ms / 1000); const days = Math.floor(total / 86400); const hours = Math.floor(total % 86400 / 3600);
    const minutes = Math.floor(total % 3600 / 60); const seconds = total % 60;
    if (days) return `${days}天${hours}小时`; if (hours) return `${hours}小时${minutes}分`; if (minutes) return `${minutes}分${seconds}秒`; return `${seconds}秒`;
  }
  function countdown(value) { const t = value ? new Date(value).getTime() : NaN; return Number.isFinite(t) ? durationText(t - nowMs()) : '—'; }
  function countdownSpan(value, label = '') { return value ? `<span class="sect-v2-countdown-bsect03" data-bsect-countdown="${esc(value)}" data-label="${esc(label)}">${esc(label)}${esc(countdown(value))}</span>` : ''; }
  function updateCountdowns(scope = document) {
    scope.querySelectorAll?.('[data-bsect-countdown]').forEach(el => {
      const label = el.dataset.label || ''; el.textContent = `${label}${countdown(el.dataset.bsectCountdown)}`;
    });
  }
  function syncServerClock(data) {
    const raw = growth(data).server_now || data?.server_now; const server = raw ? new Date(raw).getTime() : NaN;
    state.serverOffsetMs = Number.isFinite(server) ? server - Date.now() : 0;
  }
  function growthEvents(data = state.data) {
    const autonomyEvents = Array.isArray(autonomy(data).recent_events) ? autonomy(data).recent_events : [];
    if (autonomyEvents.length) return autonomyEvents;
    const direct = Array.isArray(growth(data).recent_events) ? growth(data).recent_events : [];
    if (direct.length) return direct;
    return (Array.isArray(data?.recent_events) ? data.recent_events : []).filter(e => e?.event_type === 'growth_random_event');
  }
  function eventKey(e) { return String(e?.id || `${e?.disciple_id || ''}:${e?.event_code || e?.event_type || ''}:${e?.resolved_at || e?.created_at || ''}`); }
  function dueGrowthBoundary(data = state.data) {
    const current = nowMs();
    const growthDue = (growth(data).assignments || []).some(a => {
      const eventAt = a?.next_event_at ? new Date(a.next_event_at).getTime() : NaN;
      const endsAt = a?.ends_at ? new Date(a.ends_at).getTime() : NaN;
      return (Number.isFinite(eventAt) && eventAt <= current) || (Number.isFinite(endsAt) && endsAt <= current);
    });
    const socialDue = (social(data).disciple_states || []).some(x => {
      const at = x?.next_event_at ? new Date(x.next_event_at).getTime() : NaN;
      return Number.isFinite(at) && at <= current;
    });
    const autonomyDue = (autonomy(data).states || []).some(x => {
      const eventAt = x?.next_event_at ? new Date(x.next_event_at).getTime() : NaN;
      const decisionAt = x?.next_decision_at ? new Date(x.next_decision_at).getTime() : NaN;
      return (Number.isFinite(eventAt) && eventAt <= current) || (Number.isFinite(decisionAt) && decisionAt <= current);
    });
    return growthDue || socialDue || autonomyDue;
  }
  async function autoSettleDue() {
    if (document.hidden || !root() || state.loading || state.busy || !state.data || !dueGrowthBoundary()) return;
    if (Date.now() - state.lastAutoSyncAt < 30000) return;
    state.lastAutoSyncAt = Date.now();
    await refresh({ sync:true, silent:true });
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
    const a = autonomy().states?.find(x => String(x.disciple_id) === String(d.id)) || {};
    const progress = cultivationProgress(d);
    const capped = num(d.cultivation_cap) > 0 && num(d.cultivation) >= num(d.cultivation_cap);
    const activity = activityName(a.activity_name || a.activity_code || 'cultivation');
    const displayActivity = capped ? '等待自主破境判断' : activity;
    const next = a.next_event_at ? countdownSpan(a.next_event_at, '下次弟子动态约 ') : '';
    const decision = a.next_decision_at ? countdownSpan(a.next_decision_at, '下次行动评估约 ') : '';
    const breakthroughHint = capped ? `<div class="sect-v2-breakthrough-hint-bsect08"><b>修为已经圆满 · 突破由弟子自主决定</b><span>宗主不能手动点击突破。弟子会在后续行动评估中结合性格、心境、伤势、资源与宗门“突破态度”，自行决定继续准备还是尝试破境；高境界真实失败风险仍由服务端结算。</span></div>` : '';
    return `<article class="sect-v2-card-bsect01 ${capped ? 'is-breakthrough-ready-bsect03' : ''}"><div class="sect-v2-card-head-bsect02"><div><small>${esc(identityRankName(d.identity_rank_code))}${d.office_code && d.office_code !== 'none' ? ` · ${esc(officeName(d.office_code))}` : ''}</small><h4>${esc(d.dao_name || d.name)}</h4>${d.dao_name ? `<small>本名：${esc(d.name)}</small>` : ''}</div><span class="sect-v2-status-bsect02 ${capped ? 'ready-bsect03' : ''}">${esc(displayActivity)}</span></div><div class="sect-v2-tags-bsect01"><span>${esc(d.spirit_root_name)}</span><span>${esc(d.element_name)}属性</span><span>${esc(d.realm_name)}</span><span>${esc(d.personality)}</span></div><div class="sect-v2-statline-bsect01"><span>修为 ${fmt(d.cultivation)} / ${fmt(d.cultivation_cap)}</span><span>忠诚 ${fmt(d.loyalty)} · 心境 ${fmt(d.mood)}</span></div><div class="sect-v2-progress-bsect01"><i style="width:${progress.toFixed(2)}%"></i></div><small>弟子将依据性格、关系、宗门方略和自身状态自主修炼、历练、疗伤与突破。</small>${breakthroughHint}${next || decision ? `<div class="sect-v2-timing-bsect03">${next}${next && decision ? '<br>' : ''}${decision}</div>` : ''}${a.last_reason ? `<p class="sect-v2-autonomy-reason-bsect06"><b>最近自主决定：</b>${esc(autonomyReasonText(a.last_reason, displayActivity))}</p>` : ''}<div class="sect-v2-actions-bsect01"><button class="secondary-btn" type="button" data-bsect-detail="${esc(d.id)}">人物经历</button>${options.allowExpel && d.identity_code !== 'opening_first' ? `<button class="danger-btn" type="button" data-bsect-expel="${esc(d.id)}" data-name="${esc(d.dao_name || d.name)}">逐出</button>` : ''}</div></article>`;
  }

  function tabNav() {
    const a = autonomy();
    const eventCount = (a.recent_events || []).length;
    const pendingCount = (social().pending_events || []).length;
    const tabs = [
      ['overview','宗门总览'],['autonomy','自主生态'],['disciples','弟子与山门'],['events',`宗门动态${eventCount ? `（${eventCount}）` : ''}`],
      ['chronicle','人物经历'],['resources','贡献与奖励'],['people','人物与师徒'],['decisions',`宗主案牍${pendingCount ? `（${pendingCount}）` : ''}`],
      ['partners','道侣与托管'],['sparring','切磋赛季'],['world','世界宗门'],['market','宗门市集'],['adventures','高级历练'],['promotion','晋升与治理'],['honors','排行与荣誉']
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
    return `<div class="sect-v2-view-bsect02">${openingNeeded ? `<div class="sect-v2-callout-bsect01"><strong>选择开山大弟子</strong><p>三名候选整体质量接近，分别偏修炼、偏实战与均衡。选择后不可撤销，称号永久保留但不提供额外数值。</p></div><div class="sect-v2-grid-bsect01">${opening.map(c => candidateCard(c,true)).join('')}</div>` : ''}<div class="sect-v2-metrics-bsect02">${metric('宗门综合评分',fmt(p2.score || 0),`阶段：${stageName(data.sect?.stage_code)}`)}${metric('宗门灵石',fmt(treasury.spirit_stones || 0),`下次维护：${time(treasury.next_maintenance_at)}`)}${metric('宗门物资',fmt(treasury.supplies || 0),`维护欠费：${fmt(treasury.maintenance_debt || 0)}`)}${metric('世界声望',fmt(treasury.reputation || 0),readiness.completed ? '已达万古仙宗' : `下一阶段：${readiness.display_name || '待计算'}`)}</div>${readiness && !readiness.completed ? `<section class="sect-v2-panel-bsect02"><header><div><strong>下一阶段准备度</strong><small>${esc(readiness.display_name || '')}</small></div><span class="sect-v2-ready-bsect02 ${readiness.ok ? 'ok' : ''}">${readiness.ok ? '条件已满足' : '继续经营'}</span></header><div class="sect-v2-readiness-bsect02"><span>弟子 ${fmt(readiness.alive)}/${fmt(readiness.minimum_disciples)}</span><span>达标境界弟子 ${fmt(readiness.realm_ready_count)}/${fmt(readiness.minimum_realm_disciple_count)}</span><span>评分 ${fmt(readiness.score)}/${fmt(readiness.minimum_score)}</span><span>灵石 ${fmt(readiness.spirit_stones)}/${fmt(readiness.spirit_stone_cost)}</span>${readiness.requires_trial ? `<span>友好认证宗门 ${fmt(readiness.certifying_npc_count)}/2</span>` : ''}</div></section>` : ''}${sectionTitle('世界宗门排行','前50名')}<div class="sect-v2-ranking-bsect02">${(p2.ranking || []).slice(0,8).map(r => `<article class="${r.is_mine ? 'mine' : ''}"><b>${fmt(r.rank)}</b><div><strong>${esc(r.name)}</strong><small>${stageName(r.stage_code)} · ${fmt(r.disciple_count)}名弟子</small></div><span>${fmt(r.score)}</span></article>`).join('') || '<div class="sect-v2-empty-bsect01">暂无排行数据。</div>'}</div>${sectionTitle('宗门史','最近20条 · 有实际变化时显示明细')}<div class="sect-v2-log-bsect01">${events.map(e => `<article><strong>${esc(e.title)}</strong><p>${esc(humanizeEventText(String(e.content||e.summary||'').replace(/【结算[：:][^】]+】/g,'').trim()))}</p>${eventOutcomeHtml(e)}<small>${time(e.created_at||e.occurred_at)}</small></article>`).join('') || '<div class="sect-v2-empty-bsect01">宗门史尚无记载。</div>'}</div></div>`;
  }

  function disciplesHtml(data) {
    const list = disciples(data); const candidates = Array.isArray(data.candidates) ? data.candidates : [];
    const normal = candidates.filter(c => c.kind !== 'opening'); const a=autonomy(data);
    return `<div class="sect-v2-view-bsect02"><div class="sect-v2-callout-bsect01"><strong>弟子是自主生活与修炼的人物</strong><p>宗主不再逐个安排普通修炼、闭关时长或突破。所有境界的弟子都会依据灵根、性格、心境、关系、伤势、资源和宗门方略自行选择道路；修为圆满后是否立即破境，也由弟子自己决定。</p></div>${sectionTitle('宗门弟子',`${list.length}/${num(data.settings?.max_disciple_count,20)} · 自主事件模板 ${fmt(a.template_count || 0)} 条`)}<div class="sect-v2-grid-bsect01">${list.map(d => discipleCard(d,{allowExpel:true})).join('') || '<div class="sect-v2-empty-bsect01">宗门目前没有存活弟子。</div>'}</div>${sectionTitle('山门候选',data.sect?.next_candidate_refresh_at ? `下次刷新 ${time(data.sect.next_candidate_refresh_at)}` : '等待刷新')}<div class="sect-v2-grid-bsect01">${normal.map(c => candidateCard(c,false)).join('') || '<div class="sect-v2-empty-bsect01">当前没有新的拜师候选。</div>'}</div><div class="sect-v2-warning-bsect02"><strong>宗主只决定方向</strong><p>弟子可能自主申请资源、请求拜师、产生道侣提案、选择历练、继续准备或尝试突破。宗主不能直接替弟子点击突破；涉及珍贵资产和宗门走向的其他重大事项仍会进入宗主案牍。</p></div></div>`;
  }

  function eventsHtml(data) {
    const a=autonomy(data); const items=a.recent_events || []; const settings=a.settings || {}; const states=a.states || [];
    return `<div class="sect-v2-view-bsect02"><div class="sect-v2-callout-bsect01"><strong>分类事件池与人物状态共同驱动宗门</strong><p>系统先按弟子当前行为、性格、心境、关系、职位和宗门政策选择事件家族，再抽取具体模板。当前已安装 ${fmt(a.template_count||0)} 个独立模板、${fmt(a.family_count||0)} 个事件家族；普通事件自动处理，重要事件进入宗主案牍。</p></div>${sectionTitle('自主排期',`${states.length}名弟子`)}<div class="sect-v2-log-bsect01">${states.map(x=>`<article><strong>${esc(x.disciple_name)} · ${esc(activityName(x.activity_name))}</strong><p>${x.next_event_at?countdownSpan(x.next_event_at,'弟子动态 '):'等待排期'} · ${x.next_decision_at?countdownSpan(x.next_decision_at,'行动评估 '):'等待决定'}</p><small>已经历 ${fmt(x.event_count)} 次事件 · ${fmt(x.important_event_count)} 次重要事件</small></article>`).join('')||'<div class="sect-v2-empty-bsect01">暂无自主排期。</div>'}</div>${sectionTitle('最近宗门动态',`${items.length}条 · 有变化时显示明细`)}<div class="sect-v2-log-bsect01">${items.map(e=>`<article class="importance-${esc(e.importance_code||'ordinary')}"><strong>${esc(e.title||'宗门动态')}</strong><p>${esc(humanizeEventText(String(e.summary||'').replace(/【结算[：:][^】]+】/g,'').trim()))}</p>${eventOutcomeHtml(e)}<small>${esc(eventCategoryName(e.category_code))} · ${time(e.occurred_at)}</small></article>`).join('')||'<div class="sect-v2-empty-bsect01">尚无新动态。点击结算并刷新会按服务器时间推进宗门。</div>'}</div><div class="sect-v2-warning-bsect02"><strong>容量保护已启用</strong><p>普通明细保留 ${fmt(settings.ordinary_retention_days||90)} 天，并受每宗门 ${fmt(settings.ordinary_hard_cap_per_sect||3000)} 条硬上限约束；重大经历永久保留，旧日常事件按月汇总。</p></div></div>`;
  }

  function peopleHtml(data) {
    if (!state.socialAvailable || social(data).installed === false) return unavailableHtml('人物关系数据库尚未安装。');
    const list = disciples(data); const soc = social(data); const links = soc.master_apprentice || []; const relations = soc.relationships || [];
    const names = new Map(list.map(d => [String(d.id), d.dao_name || d.name]));
    const masterByApprentice = new Map(links.filter(x => x.status === 'active').map(x => [String(x.apprentice_disciple_id), String(x.master_disciple_id)]));
    const eligibleMasters = list.filter(d => ['elder','peak_master','grand_elder'].includes(d.office_code));
    const identityOptions = d => ['registered','outer','inner','direct','chief'].map(code => `<option value="${code}" ${d.identity_rank_code===code?'selected':''}>${identityRankName(code)}</option>`).join('');
    const officeOptions = d => ['none','steward','elder','peak_master','grand_elder'].map(code => `<option value="${code}" ${d.office_code===code?'selected':''}>${officeName(code)}</option>`).join('');
    return `<div class="sect-v2-view-bsect02"><div class="sect-v2-callout-bsect01"><strong>身份与管理职务采用双轴结构</strong><p>弟子可以同时拥有门内身份和管理职务，例如“亲传弟子·峰主”。亲传最多3名、首席1名、大长老1名；长老、峰主和大长老可以按名额正式收徒。</p></div>${sectionTitle('身份、职务与师徒',`${list.length}名存活弟子`)}<div class="sect-v2-people-grid-bsect04">${list.map(d => { const currentMaster=masterByApprentice.get(String(d.id))||''; return `<article class="sect-v2-person-card-bsect04"><header><div><small>${esc(d.realm_name)} · ${esc(d.element_name)}属性</small><strong>${esc(d.dao_name||d.name)}</strong></div><span>忠诚 ${fmt(d.loyalty)} · 心境 ${fmt(d.mood)}</span></header><form data-bsect-position-form="${esc(d.id)}"><label>门内身份<select name="identity">${identityOptions(d)}</select></label><label>管理职务<select name="office">${officeOptions(d)}</select></label><button class="secondary-btn" type="submit">保存身份职务</button></form><form data-bsect-master-form="${esc(d.id)}"><label>正式师父<select name="master"><option value="">无正式师父</option>${eligibleMasters.filter(m=>m.id!==d.id).map(m=>`<option value="${esc(m.id)}" ${currentMaster===String(m.id)?'selected':''}>${esc(m.dao_name||m.name)} · ${officeName(m.office_code)}</option>`).join('')}</select></label><button class="secondary-btn" type="submit">保存师承</button></form>${d.next_social_event_at?`<small>${countdownSpan(d.next_social_event_at,'下次人物事件约 ')}</small>`:''}</article>`; }).join('') || '<div class="sect-v2-empty-bsect01">尚无弟子。</div>'}</div>${sectionTitle('同门关系',`${relations.length}组已形成关系`)}<div class="sect-v2-relation-list-bsect04">${relations.map(r=>`<article><div><strong>${esc(names.get(String(r.disciple_a_id))||'弟子')} ↔ ${esc(names.get(String(r.disciple_b_id))||'弟子')}</strong><small>${esc(relationName(r.relation_code))}</small></div><span>好感 ${fmt(r.affinity)}</span></article>`).join('') || '<div class="sect-v2-empty-bsect01">关系会通过修炼、师徒和人物事件逐步形成。</div>'}</div></div>`;
  }

  function decisionsHtml(data) {
    if (!state.socialAvailable) return unavailableHtml('人物事件数据库尚未安装。');
    const list=disciples(data);const names=new Map(list.map(d=>[String(d.id),d.dao_name||d.name]));const pending=social(data).pending_events||[];
    return `<div class="sect-v2-view-bsect02"><div class="sect-v2-callout-bsect01"><strong>重要人物事件需要宗主裁决</strong><p>普通事件会按弟子性格、忠诚、心境和关系自动处理；资源申请、同门冲突、晋升诉求、拜师请求和心魔征兆等重要事件进入待处理队列。</p></div>${sectionTitle('待处理事件',`${pending.length}件`)}<div class="sect-v2-decision-list-bsect04">${pending.map(e=>`<article><header><div><small>${esc(names.get(String(e.disciple_id))||'宗门弟子')}${e.target_disciple_id?` · 涉及 ${esc(names.get(String(e.target_disciple_id))||'同门')}`:''}</small><strong>${esc(e.title)}</strong></div><span>${countdownSpan(e.expires_at,'剩余 ')}</span></header><p>${esc(e.content)}</p><div class="sect-v2-actions-bsect01">${(e.choices||[]).map(c=>`<button type="button" class="${c.code==='approve'||c.code==='counsel'||c.code==='mediate'?'primary-btn':'secondary-btn'}" data-bsect-event-choice="${esc(e.id)}" data-choice="${esc(c.code)}" data-label="${esc(c.label)}">${esc(c.label)}</button>`).join('')}</div></article>`).join('') || '<div class="sect-v2-empty-bsect01">当前没有需要宗主处理的重要人物事件。</div>'}</div></div>`;
  }

  function partnersHtml(data) {
    const phase = partnerPhase(data);
    if (!state.partnerAvailable || phase.installed === false) return unavailableHtml('道侣、深度托管与切磋赛季数据库尚未安装。');
    const list = disciples(data); const names = new Map(list.map(d => [String(d.id), d.dao_name || d.name]));
    const proposals = phase.proposals || []; const bonds = phase.bonds || []; const eligible = phase.eligible_pairs || [];
    const rules = phase.auto_rules || {}; const settings = phase.settings || {};
    const managers = list.filter(d => ['peak_master','grand_elder'].includes(d.office_code));
    return `<div class="sect-v2-view-bsect02"><div class="sect-v2-callout-bsect01"><strong>道侣关系属于长期人物资产</strong><p>只有本宗弟子、双方好感达到${fmt(settings.minimum_affinity || 60)}，且心境与忠诚达到配置门槛时才能发起提案。宗主批准后，双方同时修炼或闭关会由服务器按时间结算约${pct(settings.cultivation_bonus_rate || 0.05)}协同修为；本阶段仍不开放生育与后代。</p></div>${sectionTitle('待确认道侣提案',`${proposals.length}件`)}<div class="sect-v2-decision-list-bsect04">${proposals.map(p=>`<article><header><div><small>好感 ${fmt(p.affinity_snapshot)}</small><strong>${esc(names.get(String(p.disciple_a_id))||'弟子')} 与 ${esc(names.get(String(p.disciple_b_id))||'弟子')}</strong></div><span>${countdownSpan(p.expires_at,'剩余 ')}</span></header><p>双方关系已达到结为道侣的条件。批准后形成唯一道侣关系并开始同修协同。</p><div class="sect-v2-actions-bsect01"><button class="primary-btn" type="button" data-bsect-partner-resolve="${esc(p.id)}" data-approve="true">宗门见证·批准</button><button class="secondary-btn" type="button" data-bsect-partner-resolve="${esc(p.id)}" data-approve="false">暂不批准</button></div></article>`).join('') || '<div class="sect-v2-empty-bsect01">当前没有待确认提案。</div>'}</div>${sectionTitle('可发起关系',`${eligible.length}组`)}<div class="sect-v2-relation-list-bsect04">${eligible.map(r=>`<article><div><strong>${esc(names.get(String(r.disciple_a_id))||'弟子')} ↔ ${esc(names.get(String(r.disciple_b_id))||'弟子')}</strong><small>${esc(relationName(r.relation_code))}</small></div><span>好感 ${fmt(r.affinity)}</span><button class="secondary-btn" type="button" data-bsect-partner-propose-a="${esc(r.disciple_a_id)}" data-b="${esc(r.disciple_b_id)}">发起道侣提案</button></article>`).join('') || '<div class="sect-v2-empty-bsect01">暂无满足门槛且双方均无道侣的关系组合。</div>'}</div>${sectionTitle('现有道侣',`${bonds.filter(b=>b.status==='active').length}对`)}<div class="sect-v2-grid-bsect01">${bonds.map(b=>`<article class="sect-v2-card-bsect01 ${b.status==='active'?'is-partner-active-bsect05':''}"><small>${b.status==='active'?'道侣关系生效中':`状态：${esc(statusName(b.status))}`}</small><h4>${esc(names.get(String(b.disciple_a_id))||'弟子')} · ${esc(names.get(String(b.disciple_b_id))||'弟子')}</h4><p>协同等级 ${fmt(b.synergy_level)} · 累计协同修为 ${fmt(b.total_cultivation_bonus)}<br>累计同修 ${durationText(num(b.total_synergy_seconds)*1000)}</p><small>上次结算：${time(b.last_synergy_at)}</small>${b.status==='active'?`<div class="sect-v2-actions-bsect01"><button class="danger-btn" type="button" data-bsect-partner-end="${esc(b.id)}">解除道侣关系</button></div>`:''}</article>`).join('') || '<div class="sect-v2-empty-bsect01">宗门尚无正式道侣。</div>'}</div><section class="sect-v2-panel-bsect02"><header><div><strong>峰主 / 大长老深度托管</strong><small>服务端按需执行，不创建高频Cron</small></div><span>${rules.enabled?'已启用':'未启用'}</span></header><form id="sectAutoRulesFormBsect05" class="sect-v2-form-bsect02"><label class="sect-v2-switch-bsect02"><input type="checkbox" name="enabled" ${rules.enabled?'checked':''}><span>启用深度托管</span></label><label class="sect-v2-switch-bsect02"><input type="checkbox" name="autoCultivate" ${rules.auto_cultivate_idle!==false?'checked':''}><span>自动安排空闲弟子修炼</span></label><label class="sect-v2-switch-bsect02"><input type="checkbox" name="autoHeal" ${rules.auto_heal_injured!==false?'checked':''}><span>自动安排受伤弟子疗伤</span></label><label class="sect-v2-switch-bsect02"><input type="checkbox" name="autoResource" ${rules.auto_resolve_resource_requests?'checked':''}><span>限额自动审批修炼资源</span></label><label>单次资源审批上限<input type="number" name="resourceLimit" min="0" step="1" value="${num(rules.resource_approval_limit,300)}"></label><label>心境保护线<input type="number" name="moodFloor" min="0" max="100" value="${num(rules.protect_mood_below,30)}"></label><label>宗门灵石保留线<input type="number" name="reserve" min="0" step="1" value="${num(rules.reserve_spirit_stones,5000)}"></label><label>托管负责人<select name="manager"><option value="">宗主直接管理</option>${managers.map(d=>`<option value="${esc(d.id)}" ${String(rules.manager_disciple_id||'')===String(d.id)?'selected':''}>${esc(d.dao_name||d.name)} · ${officeName(d.office_code)}</option>`).join('')}</select></label><button class="primary-btn" type="submit">保存深度托管策略</button></form></section></div>`;
  }

  function sparringHtml(data) {
    if (!state.socialAvailable || social(data).installed === false) return unavailableHtml('普通切磋数据库尚未安装。');
    const soc=social(data);const phase=partnerPhase(data);const list=disciples(data);const current=new Set((soc.sparring_lineup?.disciple_ids||[]).map(String));const matches=soc.recent_matches||[];const settings=soc.settings||{};
    const season=phase.season||{};const rating=phase.rating||{};const board=phase.leaderboard||[];const phaseSettings=phase.settings||{};
    const todayWins=matches.filter(m=>String(m.winner_sect_id)===String(data.sect?.id)&&new Date(m.created_at).toDateString()===new Date().toDateString()).length;
    const canClaim=todayWins>=num(phaseSettings.daily_reward_wins,3)&&!phase.daily_reward_claimed;
    return `<div class="sect-v2-view-bsect02"><div class="sect-v2-callout-bsect01"><strong>三人异步普通切磋 · 月赛季</strong><p>选择三名弟子保存防守快照，再由服务端匹配强度接近的宗门。切磋复用现有境界与五行克制，不造成真实伤势、死亡、装备损失或建筑损坏。</p></div><div class="sect-v2-metrics-bsect02">${metric('当前赛季',season.name||'等待开启',season.ends_at?`结束 ${time(season.ends_at)}`:'')}${metric('赛季积分',fmt(rating.rating||phaseSettings.season_start_rating||1000),`胜 ${fmt(rating.wins||0)} · 负 ${fmt(rating.losses||0)}`)}${metric('今日胜场',fmt(todayWins),`奖励门槛 ${fmt(phaseSettings.daily_reward_wins||3)}`)}${metric('最高积分',fmt(rating.best_rating||rating.rating||0),`当前连胜 ${fmt(rating.current_streak||0)}`)}</div><section class="sect-v2-panel-bsect02"><header><div><strong>出战阵容</strong><small>必须恰好选择3名不同的存活弟子</small></div><span>今日主动切磋 ${fmt(soc.today_sparring_count||0)}/${fmt(settings.daily_sparring_limit||10)}</span></header><form id="sectSparringLineupFormBsect04"><div class="sect-v2-lineup-grid-bsect04">${list.map(d=>`<label class="${['heavy','dying'].includes(d.injury_status)?'disabled':''}"><input type="checkbox" name="disciple" value="${esc(d.id)}" ${current.has(String(d.id))?'checked':''} ${['heavy','dying'].includes(d.injury_status)?'disabled':''}><span><strong>${esc(d.dao_name||d.name)}</strong><small>${esc(d.realm_name)} · ${esc(d.element_name)} · ${identityRankName(d.identity_rank_code)}</small></span></label>`).join('')}</div><div class="sect-v2-actions-bsect01"><button class="secondary-btn" type="submit">保存三人阵容</button><button class="primary-btn" type="button" data-bsect-start-sparring ${current.size===3?'':'disabled'}>匹配并切磋</button><button class="primary-btn" type="button" data-bsect-claim-season-reward ${canClaim?'':'disabled'}>${phase.daily_reward_claimed?'今日奖励已领取':`领取${fmt(phaseSettings.daily_reward_spirit_stones||1200)}灵石`}</button></div></form></section>${sectionTitle('赛季排行榜','前30名')}<div class="sect-v2-ranking-bsect02">${board.map(r=>`<article class="${r.is_mine?'mine':''}"><b>${fmt(r.rank)}</b><div><strong>${esc(r.sect_name)}</strong><small>胜 ${fmt(r.wins)} · 负 ${fmt(r.losses)}</small></div><span>${fmt(r.rating)}</span></article>`).join('')||'<div class="sect-v2-empty-bsect01">本赛季暂无积分数据。</div>'}</div>${sectionTitle('最近战报',`${matches.length}场`)}<div class="sect-v2-match-list-bsect04">${matches.map(m=>{const mine=String(m.winner_sect_id)===String(data.sect?.id);const attackerMine=String(m.attacker_sect_id)===String(data.sect?.id);return `<article class="${mine?'win':'lose'}"><header><div><small>${time(m.created_at)}</small><strong>${esc(m.attacker_name)} ${fmt(m.attacker_score)} : ${fmt(m.defender_score)} ${esc(m.defender_name)}</strong></div><span>${mine?'胜':'负'}${attackerMine?' · 主动':' · 防守'}</span></header><div class="sect-v2-rounds-bsect04">${(m.rounds||[]).map(r=>`<span>第${fmt(r.round)}阵 · ${r.winner==='attacker'?'攻方胜':'守方胜'}</span>`).join('')}</div></article>`;}).join('') || '<div class="sect-v2-empty-bsect01">尚无普通切磋战报。其他宗门也需要先设置三人阵容。</div>'}</div></div>`;
  }

  function worldHtml(data) {
    const p2 = phase2(data); const npcs = p2.npc_sects || [];
    if (!state.phase2Available) return unavailableHtml('第二阶段数据库尚未安装，第一阶段弟子经营仍可使用。');
    return `<div class="sect-v2-view-bsect02"><div class="sect-v2-callout-bsect01"><strong>世界宗门网络</strong><p>关系分为仇敌、敌对、冷淡、中立、友好与盟友。访问、赠礼、共同修炼和晋升认证均由服务端结算，并受冷却与库藏约束。</p></div><div class="sect-v2-grid-bsect01">${npcs.map(n => `<article class="sect-v2-card-bsect01 sect-v2-npc-bsect02"><div class="sect-v2-card-head-bsect02"><div><small>${esc(specialtyName(n.specialty_code))}</small><h4>${esc(n.name)}</h4></div><span class="sect-v2-relation-bsect02">${esc(n.relation_level)} ${fmt(n.relation_score)}</span></div><p>${esc(n.doctrine)}</p><div class="sect-v2-statline-bsect01"><span>晋升认证 ${fmt(n.certification_progress)}%</span><span>上次往来 ${time(n.last_action_at)}</span></div><div class="sect-v2-progress-bsect01"><i style="width:${Math.min(100,num(n.certification_progress))}%"></i></div><div class="sect-v2-actions-bsect01"><button class="secondary-btn" type="button" data-bsect-npc="${esc(n.code)}" data-action="visit">登门拜访</button><button class="secondary-btn" type="button" data-bsect-npc="${esc(n.code)}" data-action="gift">赠礼·500灵石</button><button class="primary-btn" type="button" data-bsect-npc="${esc(n.code)}" data-action="joint_training">共同修炼</button><button class="secondary-btn" type="button" data-bsect-npc="${esc(n.code)}" data-action="request_certification">申请认证</button></div></article>`).join('') || '<div class="sect-v2-empty-bsect01">尚未建立世界宗门档案。</div>'}</div></div>`;
  }

  function marketHtml(data) {
    const p2 = phase2(data); const treasury = p2.treasury || {}; const orders = p2.market_orders || []; const mine = p2.my_orders || [];
    if (!state.phase2Available) return unavailableHtml('第二阶段宗门市集尚未安装。');
    return `<div class="sect-v2-view-bsect02"><section class="sect-v2-panel-bsect02"><header><div><strong>发布宗门订单</strong><small>物资与灵石会在服务端托管，取消或过期后退回未成交部分</small></div><span>灵石 ${fmt(treasury.spirit_stones)} · 物资 ${fmt(treasury.supplies)}</span></header><form id="sectMarketFormBsect02" class="sect-v2-form-bsect02"><label>订单方向<select name="orderType"><option value="buy_supplies">求购物资</option><option value="sell_supplies">出售物资</option></select></label><label>数量<input name="quantity" type="number" min="1" step="1" value="10" required></label><label>单价<input name="unitPrice" type="number" min="1" step="1" value="100" required></label><label>有效小时<input name="duration" type="number" min="1" max="168" step="1" value="24" required></label><button class="primary-btn" type="submit">托管并发布</button></form></section>${sectionTitle('公开订单',`${orders.length}张可成交`)}<div class="sect-v2-market-list-bsect02">${orders.map(o => `<article><div><strong>${esc(o.sect_name)}</strong><small>${esc(orderName(o.order_type))} · 到期 ${time(o.expires_at)}</small></div><span>${fmt(o.remaining_quantity)}份 × ${fmt(o.unit_price)}灵石</span><button class="primary-btn" type="button" data-bsect-accept-order="${esc(o.id)}" data-max="${fmt(o.remaining_quantity)}">成交</button></article>`).join('') || '<div class="sect-v2-empty-bsect01">当前没有其他宗门的公开订单。</div>'}</div>${sectionTitle('我的订单',`${mine.filter(o=>o.status==='open').length}张进行中`)}<div class="sect-v2-market-list-bsect02">${mine.map(o => `<article><div><strong>${esc(orderName(o.order_type))}</strong><small>${esc(statusName(o.status))} · 到期 ${time(o.expires_at)}</small></div><span>${fmt(o.remaining_quantity)}/${fmt(o.quantity)}份 × ${fmt(o.unit_price)}</span>${o.status === 'open' ? `<button class="secondary-btn" type="button" data-bsect-cancel-order="${esc(o.id)}">取消</button>` : '<i>已结算</i>'}</article>`).join('') || '<div class="sect-v2-empty-bsect01">尚未发布订单。</div>'}</div></div>`;
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
    return `<div class="sect-v2-view-bsect02">${sectionTitle('世界宗门排行','服务端综合评分')}<div class="sect-v2-ranking-bsect02">${(p2.ranking || []).map(r => `<article class="${r.is_mine ? 'mine' : ''}"><b>${fmt(r.rank)}</b><div><strong>${esc(r.name)}</strong><small>${stageName(r.stage_code)} · 声望 ${fmt(r.reputation)}</small></div><span>${fmt(r.score)}</span></article>`).join('') || '<div class="sect-v2-empty-bsect01">暂无排行。</div>'}</div>${sectionTitle('历史荣誉',`${honors.length}项`)}<div class="sect-v2-grid-bsect01">${honors.map(h=>`<article class="sect-v2-card-bsect01"><small>${time(h.awarded_at)}</small><h4>${esc(h.title)}</h4><p>${esc(h.description)}</p><strong>荣誉点 ${fmt(h.points)}</strong></article>`).join('') || '<div class="sect-v2-empty-bsect01">尚未获得第二阶段荣誉。</div>'}</div>${sectionTitle('正式宗门战争观战','封闭测试 · 默认关闭')}<div class="sect-v2-callout-bsect01"><strong>${adv.war_spectator_enabled ? '只读观战已开放' : '只读观战未开放'}</strong><p>第二阶段不产生真实伤势、资源损失或建筑损坏。只有ADMIN9明确开启并发布观战数据后才会显示。</p></div>${wars.length ? `<div class="sect-v2-log-bsect01">${wars.map(w=>`<article><strong>${esc(w.title)}</strong><p>${esc(w.attacker_name)} 对 ${esc(w.defender_name)} · ${esc(statusName(w.status))}<br>${esc(w.summary || '')}</p><small>${time(w.starts_at)}</small></article>`).join('')}</div>` : ''}</div>`;
  }


  function autonomyDirectionName(code){return ({balanced:'均衡发展',cultivation:'修行为先',exploration:'历练探索',combat:'实战争锋',alchemy:'丹道兴宗',craft:'器道兴宗',scholar:'传承学宫'})[code]||'均衡发展';}
  function policyName(code){return ({cautious:'稳健',balanced:'均衡',bold:'激进',conservative:'节制',generous:'慷慨',closed:'闭关自守',open:'广结善缘'})[code]||'均衡';}
  function autonomyHtml(data){
    const a=autonomy(data); if(!state.autonomyAvailable||a.installed===false)return unavailableHtml('自主宗门生态数据库尚未安装。');
    const p=a.policy||{};const states=a.states||[];
    const counts={};states.forEach(x=>counts[x.activity_code]=(counts[x.activity_code]||0)+1);
    return `<div class="sect-v2-view-bsect02"><div class="sect-v2-metrics-bsect02">${metric('自主弟子',fmt(states.length),'全部按服务端时间生活')}${metric('事件模板',fmt(a.template_count||0),`${fmt(a.family_count||0)}个事件家族`)}${metric('当前方略',autonomyDirectionName(p.direction_code),`突破：${policyName(p.breakthrough_policy)}`)}${metric('待处理案牍',fmt((social(data).pending_events||[]).length),'重大事项由宗主决定')}</div><section class="sect-v2-panel-bsect02"><header><div><strong>宗门方略</strong><small>只改变弟子的选择权重，不强制所有弟子执行同一事务</small></div></header><form id="sectAutonomyPolicyFormBsect06" class="sect-v2-form-bsect02"><label>发展方向<select name="direction"><option value="balanced" ${p.direction_code==='balanced'?'selected':''}>均衡发展</option><option value="cultivation" ${p.direction_code==='cultivation'?'selected':''}>修行为先</option><option value="exploration" ${p.direction_code==='exploration'?'selected':''}>历练探索</option><option value="combat" ${p.direction_code==='combat'?'selected':''}>实战争锋</option><option value="alchemy" ${p.direction_code==='alchemy'?'selected':''}>丹道兴宗</option><option value="craft" ${p.direction_code==='craft'?'selected':''}>器道兴宗</option><option value="scholar" ${p.direction_code==='scholar'?'selected':''}>传承学宫</option></select></label><label>突破态度<select name="breakthrough"><option value="cautious" ${p.breakthrough_policy==='cautious'?'selected':''}>稳健准备</option><option value="balanced" ${p.breakthrough_policy==='balanced'?'selected':''}>审时度势</option><option value="bold" ${p.breakthrough_policy==='bold'?'selected':''}>勇于破境</option></select></label><label>资源政策<select name="resource"><option value="conservative" ${p.resource_policy==='conservative'?'selected':''}>节制使用</option><option value="balanced" ${p.resource_policy==='balanced'?'selected':''}>按需发放</option><option value="generous" ${p.resource_policy==='generous'?'selected':''}>慷慨培养</option></select></label><label>对外政策<select name="external"><option value="closed" ${p.external_policy==='closed'?'selected':''}>闭关自守</option><option value="balanced" ${p.external_policy==='balanced'?'selected':''}>谨慎往来</option><option value="open" ${p.external_policy==='open'?'selected':''}>广结善缘</option></select></label><label>普通资源自动批准上限<input type="number" name="commonLimit" min="0" value="${num(p.auto_approve_common_limit,300)}"></label><label>宗门灵石保留线<input type="number" name="reserveStones" min="0" value="${num(p.reserve_spirit_stones,5000)}"></label><label>宗门物资保留线<input type="number" name="reserveSupplies" min="0" value="${num(p.reserve_supplies,20)}"></label><label class="sect-v2-switch-bsect02"><input type="checkbox" name="rareApproval" ${p.rare_asset_requires_approval!==false?'checked':''}><span>稀有资产必须宗主批准</span></label><div class="sect-v2-breakthrough-hint-bsect08"><b>突破决定权：弟子自主</b><span>所有境界都由弟子在行动评估时自行决定是否破境。这里的“突破态度”只影响弟子的选择倾向，宗主没有立即突破按钮。</span></div><button class="primary-btn" type="submit">颁布宗门方略</button></form></section>${sectionTitle('宗门生态分布','弟子会不断重新评估自己的选择')}<div class="sect-v2-metrics-bsect02">${Object.entries(counts).map(([k,v])=>metric(assignmentName(k),fmt(v),'当前自主行为')).join('')||metric('暂无状态','0','等待首次结算')}</div></div>`;
  }
  function resourcesHtml(data){
    const a=autonomy(data);const catalog=state.contributionCatalog||{};const assets=a.assets||[];const list=disciples(data);
    return `<div class="sect-v2-view-bsect02"><div class="sect-v2-callout-bsect01"><strong>宗主提供环境与资源，不直接替弟子修炼</strong><p>你可以把个人灵石、丹药、材料、功法和装备贡献给宗门；弟子会依据事件、需求、贡献和政策申请获得。你也可以直接赏赐某名弟子。</p></div><section class="sect-v2-panel-bsect02"><header><div><strong>贡献个人资产</strong><small>所有转移均由服务端结算并写入资产账本</small></div><button class="secondary-btn" type="button" data-bsect-load-catalog>读取个人资产</button></header><form id="sectContributeStonesFormBsect06" class="sect-v2-form-bsect02"><label>贡献灵石<input type="number" name="quantity" min="1" step="1" placeholder="输入数量"></label><button class="primary-btn" type="submit">贡献灵石</button></form>${catalog.items?.length?`<div class="sect-v2-asset-list-bsect06">${catalog.items.map(x=>`<article><div><strong>${esc(x.name)}</strong><small>${esc(x.category||'物品')} · 个人持有 ${fmt(x.quantity)}</small></div><button class="secondary-btn" type="button" data-bsect-contribute-item="${esc(x.inventory_id||x.id)}" data-max="${num(x.quantity)}">贡献</button></article>`).join('')}</div>`:''}${catalog.equipment?.length?`<div class="sect-v2-asset-list-bsect06">${catalog.equipment.map(x=>`<article><div><strong>${esc(x.name||x.display_name||'装备')}</strong><small>${esc(x.rarity||'')} · 未装备实例</small></div><button class="secondary-btn" type="button" data-bsect-contribute-equipment="${esc(x.id)}">贡献装备</button></article>`).join('')}</div>`:''}</section>${sectionTitle('宗门库藏',`${assets.length}种可分配资产`)}<div class="sect-v2-asset-list-bsect06">${assets.map(x=>`<article><div><strong>${esc(x.display_name)}</strong><small>${esc(x.asset_type)} · ${esc(x.rarity_code||'普通')} · 来源 ${esc(x.source_code)}</small></div><b>×${fmt(x.quantity)}</b></article>`).join('')||'<div class="sect-v2-empty-bsect01">宗门尚无可分配资产。</div>'}</div><section class="sect-v2-panel-bsect02"><header><div><strong>宗主赏赐</strong><small>奖赏会影响弟子的忠诚、心境和后续事件</small></div></header><form id="sectRewardFormBsect06" class="sect-v2-form-bsect02"><label>弟子<select name="disciple">${list.map(d=>`<option value="${esc(d.id)}">${esc(d.dao_name||d.name)}</option>`).join('')}</select></label><label>宗门资产<select name="asset">${assets.filter(x=>num(x.quantity)>0).map(x=>`<option value="${esc(x.id)}">${esc(x.display_name)} ×${fmt(x.quantity)}</option>`).join('')}</select></label><label>数量<input type="number" name="quantity" min="1" value="1"></label><label>奖赏缘由<input name="reason" minlength="2" maxlength="300" value="嘉奖近日表现"></label><button class="primary-btn" type="submit" ${assets.length&&list.length?'':'disabled'}>赏赐弟子</button></form></section></div>`;
  }
  function chronicleHtml(data){
    const a=autonomy(data);const memories=a.memories||[];const stories=a.stories||[];const sums=a.monthly_summaries||[];
    return `<div class="sect-v2-view-bsect02"><div class="sect-v2-callout-bsect01"><strong>人物记忆与连锁故事</strong><p>重大经历会永久进入弟子记忆；部分事件会形成2—6段故事链。普通日常明细到期后会压缩成月度宗门编年史。</p></div>${sectionTitle('进行中的故事',`${stories.filter(x=>x.status==='active').length}条`)}<div class="sect-v2-log-bsect01">${stories.map(x=>`<article><strong>人物故事 · 第${fmt(x.current_step)}章</strong><p>状态：${esc(storyStatusName(x.status))}${x.next_eligible_at?` · 后续时间 ${time(x.next_eligible_at)}`:''}</p><small>${time(x.updated_at)}</small></article>`).join('')||'<div class="sect-v2-empty-bsect01">暂无进行中的连锁故事。</div>'}</div>${sectionTitle('弟子重要记忆',`${memories.length}条`)}<div class="sect-v2-log-bsect01">${memories.map(x=>`<article><strong>${esc(x.summary)}</strong><p>${(x.memory_tags||[]).map(t=>`#${esc(t)}`).join(' ')}</p><small>${esc(importanceName(x.importance_code))} · ${time(x.occurred_at)}</small></article>`).join('')||'<div class="sect-v2-empty-bsect01">尚无重要记忆。</div>'}</div>${sectionTitle('月度编年史',`${sums.length}项汇总`)}<div class="sect-v2-log-bsect01">${sums.map(x=>`<article><strong>${time(x.month_key)} · ${esc(x.category_code)}</strong><p>已归档 ${fmt(x.event_count)} 条日常事件</p><small>${time(x.generated_at)}</small></article>`).join('')||'<div class="sect-v2-empty-bsect01">普通事件尚未达到归档周期。</div>'}</div></div>`;
  }

  function dashboardHtml(data) {
    const sect = data.sect || {}; const p2 = phase2(data); const treasury = p2.treasury || {};
    const views = {overview:overviewHtml,autonomy:autonomyHtml,disciples:disciplesHtml,events:eventsHtml,chronicle:chronicleHtml,resources:resourcesHtml,people:peopleHtml,decisions:decisionsHtml,partners:partnersHtml,sparring:sparringHtml,world:worldHtml,market:marketHtml,adventures:adventuresHtml,promotion:promotionHtml,honors:honorsHtml};
    const view = views[state.activeTab] || overviewHtml;
    return `<div class="sect-v2-shell-bsect01"><header class="sect-v2-head-bsect01"><div><span>B-SECT06 · 自主弟子生态与2000事件宗门叙事</span><strong>${esc(sect.name)}</strong><small>${stageName(sect.stage_code)} · 弟子 ${disciples(data).length}/${num(data.settings?.max_disciple_count,20)} · 综合评分 ${fmt(p2.score || 0)}</small></div><div class="sect-v2-resource-chips-bsect02"><span>灵石 <b>${fmt(treasury.spirit_stones || 0)}</b></span><span>物资 <b>${fmt(treasury.supplies || 0)}</b></span><span>声望 <b>${fmt(treasury.reputation || 0)}</b></span><span>渡境丹 <b>${fmt(growth(data).breakthrough_pills || 0)}</b></span><button class="secondary-btn" type="button" data-bsect-refresh>结算并刷新</button></div></header>${tabNav()}${view(data)}</div>`;
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
    bind(); updateCountdowns(el);
  }

  async function fetchDashboard(sync = true) {
    if (state.autonomyAvailable) {
      try { return sync ? await rpc('sync_sect_v2_dashboard_bsect06',{p_request_id:uuid()}) : await rpc('get_sect_v2_dashboard_bsect06'); }
      catch(error){ const raw=String(error?.message||error||''); if(!raw.includes('PGRST202')&&!raw.includes('Could not find the function')&&!raw.includes('BSECT06')) throw error; state.autonomyAvailable=false; }
    }
    if (state.partnerAvailable) {
      try { return sync ? await rpc('sync_sect_v2_dashboard_bsect05', { p_request_id: uuid() }) : await rpc('get_sect_v2_dashboard_bsect05'); }
      catch (error) { const raw = String(error?.message || error || ''); if (!raw.includes('PGRST202') && !raw.includes('Could not find the function')) throw error; state.partnerAvailable=false; }
    }
    if (state.socialAvailable) { try{return sync?await rpc('sync_sect_v2_dashboard_bsect04',{p_request_id:uuid()}):await rpc('get_sect_v2_dashboard_bsect04');}catch(error){const raw=String(error?.message||error||'');if(!raw.includes('PGRST202')&&!raw.includes('Could not find the function'))throw error;state.socialAvailable=false;} }
    if (state.eventSyncAvailable) { try{return sync?await rpc('sync_sect_v2_dashboard_bsect03',{p_request_id:uuid()}):await rpc('get_sect_v2_dashboard_bsect03');}catch(error){const raw=String(error?.message||error||'');if(!raw.includes('PGRST202')&&!raw.includes('Could not find the function'))throw error;state.eventSyncAvailable=false;} }
    if (state.phase2Available) { try{return sync?await rpc('sync_sect_v2_dashboard_bsect02',{p_request_id:uuid()}):await rpc('get_sect_v2_dashboard_bsect02');}catch(error){const raw=String(error?.message||error||'');if(!raw.includes('PGRST202')&&!raw.includes('Could not find the function'))throw error;state.phase2Available=false;} }
    return sync ? await rpc('sync_sect_v2_dashboard_bsect01',{p_request_id:uuid()}) : await rpc('get_sect_v2_dashboard_bsect01');
  }

  async function ensureAutonomousBreakthroughPolicy(data) {
    const a=autonomy(data); const p=a.policy||{};
    if(!state.autonomyAvailable || a.installed===false || state.autonomousBreakthroughPolicyRepairing || state.autonomousBreakthroughPolicyRepaired) return data;
    if(p.allow_private_high_realm_breakthrough===true){state.autonomousBreakthroughPolicyRepaired=true;return data;}
    state.autonomousBreakthroughPolicyRepairing=true;
    try {
      await rpc('set_sect_autonomy_policy_bsect06',{
        p_direction_code:p.direction_code||'balanced',
        p_breakthrough_policy:p.breakthrough_policy||'balanced',
        p_resource_policy:p.resource_policy||'balanced',
        p_external_policy:p.external_policy||'balanced',
        p_rare_asset_requires_approval:p.rare_asset_requires_approval!==false,
        p_auto_approve_common_limit:num(p.auto_approve_common_limit,300),
        p_reserve_spirit_stones:num(p.reserve_spirit_stones,5000),
        p_reserve_supplies:num(p.reserve_supplies,20),
        p_allow_private_high_realm_breakthrough:true,
        p_request_id:uuid()
      });
      state.autonomousBreakthroughPolicyRepaired=true;
      return await fetchDashboard(false);
    } catch(error) {
      console.warn('[九霄问道] 自动修复弟子自主突破策略失败：', error?.message||error);
      return data;
    } finally {
      state.autonomousBreakthroughPolicyRepairing=false;
    }
  }

  async function refresh({ sync = true, silent = true } = {}) {
    if (state.loading) return state.data;
    const hadData = Boolean(state.data);
    const beforeEvents = new Set(growthEvents(state.data).map(eventKey));
    state.loading = true; if (!state.data) render();
    try {
      state.data = await fetchDashboard(sync);
      state.data = await ensureAutonomousBreakthroughPolicy(state.data);
      syncServerClock(state.data); state.lastFetchAt = Date.now(); render();
      const freshEvents = hadData ? growthEvents(state.data).filter(e => !beforeEvents.has(eventKey(e))) : [];
      if (freshEvents.length) toast(`宗门来报：${freshEvents[0].title || '弟子有新动静'}${freshEvents.length > 1 ? `（另有${freshEvents.length - 1}条）` : ''}`);
      else if (!silent) toast('宗门事务、随机事件、维护、订单和历练已结算。');
      return state.data;
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

  async function showDetail(id, focus = '') {
    try {
      const d=disciples().find(x=>String(x.id)===String(id));if(!d)throw new Error('BSECT06_DISCIPLE_NOT_FOUND');
      const a=autonomy().states?.find(x=>String(x.disciple_id)===String(id))||{};
      const memories=(autonomy().memories||[]).filter(x=>String(x.disciple_id)===String(id)).slice(0,12);
      const stories=(autonomy().stories||[]).filter(x=>String(x.disciple_id)===String(id)).slice(0,8);
      const recent=(autonomy().recent_events||[]).filter(x=>String(x.disciple_id||'')===String(id)).slice(0,20);
      const html=`<div class="sect-v2-modal-bsect03"><div class="sect-v2-modal-card-bsect03"><header><div><small>自主弟子人物档案</small><h3>${esc(d.dao_name||d.name)}</h3><p>${esc(d.realm_name)} · ${esc(d.spirit_root_name)} · ${esc(d.personality)}</p></div><button type="button" data-modal-close aria-label="关闭">×</button></header><div class="sect-v2-detail-grid-bsect03"><span>当前行为<b>${esc(activityName(a.activity_name||'自主生活'))}</b></span><span>忠诚<b>${fmt(d.loyalty)}</b></span><span>心境<b>${fmt(d.mood)}</b></span><span>事件经历<b>${fmt(a.event_count||0)}</b></span></div><div class="sect-v2-callout-bsect01"><strong>最近自主决定</strong><p>${esc(autonomyReasonText(a.last_reason,activityName(a.activity_name||'自主生活')))}</p></div>${sectionTitle('最近人物经历',`${recent.length}条`)}<div class="sect-v2-log-bsect01">${recent.map(e=>`<article><strong>${esc(e.title||'人物经历')}</strong><p>${esc(humanizeEventText(String(e.summary||e.content||'').replace(/【结算[：:][^】]+】/g,'').trim()))}</p>${eventOutcomeHtml(e)}<small>${esc(eventCategoryName(e.category_code))} · ${time(e.occurred_at||e.created_at)}</small></article>`).join('')||'<div class="sect-v2-empty-bsect01">暂无近期人物事件。</div>'}</div>${sectionTitle('重要记忆',`${memories.length}条`)}<div class="sect-v2-log-bsect01">${memories.map(x=>`<article><strong>${esc(humanizeEventText(x.summary))}</strong><small>${esc(importanceName(x.importance_code))} · ${time(x.occurred_at)}</small></article>`).join('')||'<div class="sect-v2-empty-bsect01">暂无重要记忆。</div>'}</div>${sectionTitle('故事线',`${stories.length}条`)}<div class="sect-v2-log-bsect01">${stories.map(x=>`<article><strong>人物故事 · 第${fmt(x.current_step)}章</strong><small>${esc(storyStatusName(x.status))}</small></article>`).join('')||'<div class="sect-v2-empty-bsect01">暂无故事线。</div>'}</div></div></div>`;
      document.body.insertAdjacentHTML('beforeend',html);const modal=document.body.lastElementChild;modal.querySelector('[data-modal-close]')?.addEventListener('click',()=>modal.remove());modal.addEventListener('click',e=>{if(e.target===modal)modal.remove();});
    } catch(error){toast(errorText(error),'error');}
  }

  function bind() {
    const el = root(); if (!el) return;
    el.querySelectorAll('[data-bsect-tab]').forEach(b => b.addEventListener('click', () => { state.activeTab=b.dataset.bsectTab; render(); window.scrollTo({top:0,behavior:'smooth'}); }));
    el.querySelectorAll('[data-bsect-refresh]').forEach(b=>b.addEventListener('click',()=>refresh({sync:true,silent:false})));
    el.querySelector('#sectAutonomyPolicyFormBsect06')?.addEventListener('submit',e=>{e.preventDefault();const f=new FormData(e.currentTarget);action('set_sect_autonomy_policy_bsect06',{p_direction_code:f.get('direction'),p_breakthrough_policy:f.get('breakthrough'),p_resource_policy:f.get('resource'),p_external_policy:f.get('external'),p_rare_asset_requires_approval:f.get('rareApproval')==='on',p_auto_approve_common_limit:Number(f.get('commonLimit')),p_reserve_spirit_stones:Number(f.get('reserveStones')),p_reserve_supplies:Number(f.get('reserveSupplies')),p_allow_private_high_realm_breakthrough:true},'宗门方略已颁布，弟子会在后续自主决策中逐步响应。');});
    el.querySelector('[data-bsect-load-catalog]')?.addEventListener('click',async()=>{try{state.contributionCatalog=await rpc('get_sect_contribution_catalog_bsect06');render();}catch(error){toast(errorText(error),'error');}});
    el.querySelector('#sectContributeStonesFormBsect06')?.addEventListener('submit',e=>{e.preventDefault();const q=Number(new FormData(e.currentTarget).get('quantity'));if(!Number.isFinite(q)||q<1){toast('请输入正确的灵石数量。','error');return;}action('contribute_sect_spirit_stones_bsect06',{p_quantity:Math.floor(q)},'灵石已经转入宗门库藏。');});
    el.querySelectorAll('[data-bsect-contribute-item]').forEach(b=>b.addEventListener('click',()=>{const max=Number(b.dataset.max||1);const q=Number(prompt(`输入贡献数量（最多${max}）`,String(Math.min(max,1))));if(Number.isFinite(q)&&q>0)action('contribute_sect_inventory_item_bsect06',{p_inventory_id:b.dataset.bsectContributeItem,p_quantity:Math.min(max,Math.floor(q))},'物品已经转入宗门库藏。');}));
    el.querySelectorAll('[data-bsect-contribute-equipment]').forEach(b=>b.addEventListener('click',()=>{if(confirm('确认将这件装备永久转入宗门库藏？'))action('contribute_sect_equipment_bsect06',{p_equipment_id:b.dataset.bsectContributeEquipment},'装备已经转入宗门库藏。');}));
    el.querySelector('#sectRewardFormBsect06')?.addEventListener('submit',e=>{e.preventDefault();const f=new FormData(e.currentTarget);action('reward_sect_disciple_asset_bsect06',{p_disciple_id:f.get('disciple'),p_asset_id:f.get('asset'),p_quantity:Number(f.get('quantity')),p_reason:String(f.get('reason')||'').trim()},'宗主赏赐已经发放。');});
    el.querySelector('#createSectV2FormBsect01')?.addEventListener('submit', e => { e.preventDefault(); const name = new FormData(e.currentTarget).get('sectName'); action('create_sect_v2_bsect01',{p_name:String(name||'').trim()},'宗门已创建，请选择开山大弟子。'); });
    el.querySelectorAll('[data-bsect-opening]').forEach(b=>b.addEventListener('click',()=>{ if(confirm('开山大弟子一经选择不可撤销，确认选择？')) action('choose_opening_disciple_bsect01',{p_candidate_id:b.dataset.bsectOpening},'开山大弟子已经入门。'); }));
    el.querySelectorAll('[data-bsect-recruit]').forEach(b=>b.addEventListener('click',()=>action('recruit_sect_candidate_bsect01',{p_candidate_id:b.dataset.bsectRecruit},'新弟子已经入门。')));
    el.querySelectorAll('[data-bsect-lock]').forEach(b=>b.addEventListener('click',()=>action('lock_sect_candidate_bsect01',{p_candidate_id:b.dataset.bsectLock},'候选弟子已锁定24小时。')));
    el.querySelectorAll('[data-bsect-assignment-obsolete]').forEach(b=>b.addEventListener('click',()=>{
      const disciple=disciples().find(d=>String(d.id)===String(b.dataset.bsectAssignment));
      const policy=disciple?.breakthrough_state||{};
      return action('set_sect_disciple_growth_assignment_bsect03',{
        p_disciple_id:b.dataset.bsectAssignment,p_assignment_code:b.dataset.assignment,p_duration_code:null,
        p_auto_breakthrough:Boolean(policy.auto_mode),p_pill_policy:num(policy.pill_policy,0)
      },b.dataset.assignment==='cultivation'?'弟子已开始持续修炼。':'弟子已停止当前事务。');
    }));
    el.querySelectorAll('[data-bsect-detail]').forEach(b=>b.addEventListener('click',()=>showDetail(b.dataset.bsectDetail)));
    el.querySelectorAll('[data-bsect-retreat-obsolete]').forEach(b=>b.addEventListener('click',()=>showDetail(b.dataset.bsectRetreat,'retreat')));
    el.querySelectorAll('[data-bsect-healing-obsolete]').forEach(b=>b.addEventListener('click',()=>showDetail(b.dataset.bsectHealing,'healing')));
    el.querySelectorAll('[data-bsect-breakthrough-obsolete]').forEach(b=>b.addEventListener('click',()=>showDetail(b.dataset.bsectBreakthrough,'breakthrough')));
    el.querySelectorAll('[data-bsect-expel]').forEach(b=>b.addEventListener('click',()=>{ if(confirm(`确认将“${b.dataset.name}”逐出宗门？其世界去向将永久记录。`)) action('expel_sect_disciple_bsect02',{p_disciple_id:b.dataset.bsectExpel},'弟子已离宗，世界去向已经记录。'); }));
    el.querySelectorAll('[data-bsect-npc]').forEach(b=>b.addEventListener('click',()=>action('interact_npc_sect_bsect02',{p_npc_code:b.dataset.bsectNpc,p_action_code:b.dataset.action},'世界宗门往来已完成。')));
    el.querySelector('#sectMarketFormBsect02')?.addEventListener('submit', e => { e.preventDefault(); const f=new FormData(e.currentTarget); action('create_sect_market_order_bsect02',{p_order_type:f.get('orderType'),p_quantity:Number(f.get('quantity')),p_unit_price:Number(f.get('unitPrice')),p_duration_hours:Number(f.get('duration'))},'宗门订单已发布并完成托管。'); });
    el.querySelectorAll('[data-bsect-accept-order]').forEach(b=>b.addEventListener('click',()=>{ const q=Number(prompt(`输入成交数量（最多${b.dataset.max}）`,String(Math.min(10,Number(b.dataset.max)||1)))); if(Number.isFinite(q)&&q>0) action('accept_sect_market_order_bsect02',{p_order_id:b.dataset.bsectAcceptOrder,p_quantity:Math.floor(q)},'订单已成交，资产已原子结算。'); }));
    el.querySelectorAll('[data-bsect-cancel-order]').forEach(b=>b.addEventListener('click',()=>{if(confirm('取消后未成交的托管资产会退回宗门库藏，确认取消？')) action('cancel_sect_market_order_bsect02',{p_order_id:b.dataset.bsectCancelOrder},'订单已取消，剩余托管资产已退回。');}));
    el.querySelector('#sectAdventureFormBsect02')?.addEventListener('submit', e => { e.preventDefault(); const f=new FormData(e.currentTarget); const ids=f.getAll('disciple').slice(0,3); if(!ids.length){toast('至少选择一名空闲弟子。','error');return;} if(f.getAll('disciple').length>3){toast('每次历练最多选择三名弟子。','error');return;} action('start_sect_adventure_bsect02',{p_template_code:f.get('template'),p_npc_code:f.get('npcCode')||null,p_disciple_ids:ids},'弟子队伍已出发，返回宗门时按需结算。'); });
    el.querySelector('[data-bsect-advance-stage]')?.addEventListener('click',()=>{if(confirm('确认消耗宗门资源并晋升？已晋升阶段不会因评分下降而降级。')) action('advance_sect_stage_bsect02',{},'宗门阶段晋升完成。');});
    el.querySelector('[data-bsect-start-trial]')?.addEventListener('click',()=>{if(confirm('确认托管晋升资源并开启多阶段试炼？失败会损失规定比例并进入冷却。')) action('start_sect_promotion_trial_bsect02',{},'晋升试炼已经开启。');});
    el.querySelectorAll('[data-bsect-trial]').forEach(b=>b.addEventListener('click',()=>action('advance_sect_promotion_trial_bsect02',{p_trial_id:b.dataset.bsectTrial,p_choice_code:b.dataset.choice},`已选择“${trialChoiceName(b.dataset.choice)}”，本阶段由服务端结算。`)));
    el.querySelectorAll('[data-bsect-position-form]').forEach(form=>form.addEventListener('submit',e=>{e.preventDefault();const f=new FormData(e.currentTarget);action('set_sect_disciple_position_bsect04',{p_disciple_id:e.currentTarget.dataset.bsectPositionForm,p_identity_rank_code:f.get('identity'),p_office_code:f.get('office')},'弟子身份与职务已调整。');}));
    el.querySelectorAll('[data-bsect-master-form]').forEach(form=>form.addEventListener('submit',e=>{e.preventDefault();const f=new FormData(e.currentTarget);action('set_sect_master_apprentice_bsect04',{p_apprentice_disciple_id:e.currentTarget.dataset.bsectMasterForm,p_master_disciple_id:f.get('master')||null},'弟子师承已更新。');}));
    el.querySelectorAll('[data-bsect-event-choice]').forEach(b=>b.addEventListener('click',()=>{if(confirm(`确认选择“${b.dataset.label}”？人物关系与资源结果由服务端结算。`))action('resolve_sect_pending_event_bsect04',{p_event_id:b.dataset.bsectEventChoice,p_choice_code:b.dataset.choice},'宗主决断已记录。');}));
    el.querySelectorAll('[data-bsect-partner-propose-a]').forEach(b=>b.addEventListener('click',()=>{if(confirm('确认向宗门提交这两名弟子的道侣提案？提案仍需宗主再次批准。'))action('propose_sect_dao_partner_bsect05',{p_disciple_a_id:b.dataset.bsectPartnerProposeA,p_disciple_b_id:b.dataset.b},'道侣提案已经生成。');}));
    el.querySelectorAll('[data-bsect-partner-resolve]').forEach(b=>b.addEventListener('click',()=>{const approve=b.dataset.approve==='true';if(confirm(approve?'确认由宗门见证双方结为道侣？':'确认暂不批准这份道侣提案？'))action('resolve_sect_dao_partner_bsect05',{p_proposal_id:b.dataset.bsectPartnerResolve,p_approve:approve},approve?'双方已经结为道侣。':'提案已被暂缓。');}));
    el.querySelectorAll('[data-bsect-partner-end]').forEach(b=>b.addEventListener('click',()=>{if(confirm('解除后双方好感会明显下降，确认解除这段道侣关系？'))action('end_sect_dao_partner_bsect05',{p_bond_id:b.dataset.bsectPartnerEnd},'道侣关系已经解除。');}));
    el.querySelector('#sectAutoRulesFormBsect05')?.addEventListener('submit',e=>{e.preventDefault();const f=new FormData(e.currentTarget);action('set_sect_auto_rules_bsect05',{p_enabled:f.get('enabled')==='on',p_auto_cultivate_idle:f.get('autoCultivate')==='on',p_auto_heal_injured:f.get('autoHeal')==='on',p_auto_resolve_resource_requests:f.get('autoResource')==='on',p_resource_approval_limit:Number(f.get('resourceLimit')),p_protect_mood_below:Number(f.get('moodFloor')),p_reserve_spirit_stones:Number(f.get('reserve')),p_manager_disciple_id:f.get('manager')||null},'深度托管策略已保存。');});
    el.querySelector('[data-bsect-claim-season-reward]')?.addEventListener('click',()=>action('claim_sect_sparring_daily_reward_bsect05',{},'今日切磋胜场奖励已领取。'));
    el.querySelector('#sectSparringLineupFormBsect04')?.addEventListener('submit',e=>{e.preventDefault();const ids=new FormData(e.currentTarget).getAll('disciple');if(ids.length!==3){toast('必须恰好选择三名弟子。','error');return;}action('set_sect_sparring_lineup_bsect04',{p_disciple_ids:ids},'三人切磋阵容已保存。');});
    el.querySelector('[data-bsect-start-sparring]')?.addEventListener('click',async()=>{if(!confirm('确认匹配其他玩家宗门进行普通切磋？本次不会造成真实伤势或资产损失。'))return;if(state.busy)return;state.busy=true;try{const result=await rpc('start_sect_sparring_bsect04',{p_request_id:uuid()});await refresh({sync:false,silent:true});alert(`${result?.attacker_name||'本宗门'} ${result?.attacker_score??0} : ${result?.defender_score??0} ${result?.defender_name||'对手'}\n${String(result?.winner_sect_id)===String(state.data?.sect?.id)?'切磋获胜':'切磋落败'}\n声望 +${result?.reputation_delta??0}，灵石 +${result?.spirit_stones_delta??0}`);}catch(error){toast(errorText(error),'error');}finally{state.busy=false;}});
    el.querySelector('#sectAutoPolicyFormBsect02')?.addEventListener('submit', e => { e.preventDefault(); const f=new FormData(e.currentTarget); action('set_sect_auto_policy_bsect02',{p_enabled:f.get('enabled')==='on',p_auto_cultivate_idle:f.get('autoCultivate')==='on',p_protect_loyalty_below:Number(f.get('loyalty')),p_reserve_spirit_stones:Number(f.get('reserve')),p_npc_preferred_code:f.get('npc')||null},'自动管理策略已保存。'); });
  }

  function onRendered() {
    if (!root()) return;
    render();
    if (!state.data || Date.now() - state.lastFetchAt > 60_000) refresh({ sync:true, silent:true });
  }

  if (!state.timer) state.timer=window.setInterval(()=>{ updateCountdowns(document); if (Date.now() % 15000 < 1100) autoSettleDue(); },1000);
  window.addEventListener('jiuxiao:sect-v2-rendered', onRendered);
  window.addEventListener('jiuxiao:sect-v2-refresh', () => refresh({sync:true,silent:true}));
  window.addEventListener('focus', () => { if (root() && Date.now()-state.lastFetchAt>60_000) refresh({sync:true,silent:true}); }, { passive:true });
  const api = { module:MODULE, refresh, render, state:() => state.data, setTab:tab=>{state.activeTab=tab;render();} };
  window.B_SECTV2_B06 = api;
  window.B_SECTV2_B05 = api;
  window.B_SECTV2_B04 = api;
  window.B_SECTV2_B03 = api;
  window.B_SECTV2_B02 = api;
  window.B_SECTV2_B01 = api;
})();
