/* 九霄问道 · 灵兽正式版
 * V2.5.0 CACHE139 / SQL267
 * 捕捉、兽卵、养成、突破、三段进化、血脉、性格、技能、放归、传承、图鉴、排行、洞府兽苑。
 * 所有资源与数值结算由 SQL267 RPC 权威处理；客户端不保存战斗快照或奖励结果。
 */
(() => {
  'use strict';

  const BUILD = 'SPIRIT-BEAST-V267-CACHE139';
  const cfg = window.GAME_CONFIG || {};
  const BASE = String(cfg.supabaseUrl || '').replace(/\/+$/, '');
  const KEY = String(cfg.supabasePublishableKey || '');
  const PROJECT_REF = (() => { try { return new URL(BASE).hostname.split('.')[0]; } catch { return 'unknown'; } })();
  const SESSION_KEY = `nine_cloud_dao_session_${PROJECT_REF}_v1`;
  const DEVICE_KEY = `nine_cloud_dao_device_${PROJECT_REF}_v1`;

  const state = { bundle: null, ranking: null, loading: false, busy: false, view: 'stable', selectedId: '', lastLoad: 0 };
  const esc = value => String(value ?? '').replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;').replaceAll("'",'&#039;');
  const fmt = value => Number(value || 0).toLocaleString('zh-CN');
  const pct = value => `${(Number(value || 0) * 100).toFixed(1).replace(/\.0$/,'')}%`;
  const uuid = () => crypto?.randomUUID?.() || `${Date.now()}-${Math.random().toString(16).slice(2)}-${Math.random().toString(16).slice(2)}`;

  function session() { try { return JSON.parse(localStorage.getItem(SESSION_KEY) || 'null'); } catch { return null; } }
  function deviceId() { return localStorage.getItem(DEVICE_KEY) || ''; }

  async function rpc(name, body = {}) {
    const s = session();
    if (!s?.access_token) throw new Error('AUTH_REQUIRED');
    const res = await fetch(`${BASE}/rest/v1/rpc/${name}`, {
      method: 'POST', headers: { apikey: KEY, Authorization: `Bearer ${s.access_token}`, 'Content-Type': 'application/json', Accept: 'application/json', 'X-Game-Session-Id': deviceId() }, body: JSON.stringify(body)
    });
    const text = await res.text(); let data = null;
    try { data = text ? JSON.parse(text) : null; } catch { data = text; }
    if (!res.ok) { const err = new Error(data?.message || data?.error || data?.msg || `HTTP ${res.status}`); err.payload = data; throw err; }
    return Array.isArray(data) ? (data[0] ?? null) : data;
  }

  function humanError(error) {
    const raw = String(error?.message || error || '');
    const map = [
      ['AUTH_REQUIRED','登录状态已失效，请重新登录。'],['SPIRIT_BEAST_DISABLED','灵兽系统目前暂停。'],['SPIRIT_BEAST_CAPTURE_DISABLED','捕捉功能目前暂停。'],
      ['SPIRIT_BEAST_STABLE_FULL','灵兽苑已满，请先扩建或放归灵兽。'],['SPIRIT_BEAST_ENCOUNTER_NOT_ACTIVE','这次灵兽遭遇已经结束。'],['SPIRIT_BEAST_CAPTURE_ATTEMPTS_EXHAUSTED','这只灵兽已经警觉逃离。'],
      ['SPIRIT_BEAST_TALISMAN_INVALID','御兽符选择无效。'],['SPIRIT_BEAST_DAILY_SUPPLY_CLAIMED','今日灵兽供给已经领取。'],['SPIRIT_BEAST_NOT_FOUND','没有找到这只灵兽。'],
      ['SPIRIT_BEAST_NOT_OWNER','这只灵兽不属于当前角色。'],['SPIRIT_BEAST_LOCKED','灵兽已锁定，请先解锁。'],['SPIRIT_BEAST_ACTIVE_CANNOT_RELEASE','出战灵兽不能直接放归。'],
      ['SPIRIT_BEAST_OWNER_REALM_LIMIT','主人境界不足，灵兽暂时不能继续突破。'],['SPIRIT_BEAST_LEVEL_NOT_READY','灵兽等级尚未达到突破要求。'],['SPIRIT_BEAST_EVOLUTION_NOT_AVAILABLE','当前形态没有可用的进化路线。'],
      ['SPIRIT_BEAST_EVOLUTION_REQUIREMENT','进化条件尚未满足。'],['SPIRIT_BEAST_SAME_BEAST','不能选择同一只灵兽作为血脉材料。'],['SPIRIT_BEAST_LINEAGE_MISMATCH','血脉传承必须使用同族灵兽。'],
      ['SPIRIT_BEAST_AUX_SKILL_INVALID','该辅助技能无法学习。'],['SPIRIT_BEAST_SKILL_SLOT_INVALID','技能升级位置无效。'],['SPIRIT_BEAST_STABLE_MAX','灵兽苑已经扩建至最高等级。'],
      ['SPIRIT_BEAST_INTERACT_DAILY_DONE','今天已经和这只灵兽互动过了。'],['SPIRIT_BEAST_CODEX_MILESTONE_NOT_REACHED','图鉴数量还没有达到这个里程碑。'],['SPIRIT_BEAST_CODEX_REWARD_CLAIMED','这个图鉴里程碑奖励已经领取。'],['SPIRIT_BEAST_CODEX_MILESTONE_INVALID','图鉴里程碑无效。'],['SPIRIT_BEAST_NAME_INVALID','灵兽名字需为1—12个字符。'],['SPIRIT_BEAST_REQUEST_ID_REUSED','请求已处理，请刷新灵兽苑。'],
      ['INSUFFICIENT_ITEM','材料不足。'],['INSUFFICIENT_INVENTORY','材料不足。'],['ITEM_NOT_ENOUGH','材料不足。'],['Could not find the function','灵兽系统需要先执行 SQL267。']
    ];
    const hit = map.find(([key]) => raw.includes(key)); return hit?.[1] || raw || '灵兽推演失败，请稍后重试。';
  }

  function toast(message, error = false) {
    const el = document.getElementById('toast'); if (!el) return;
    el.textContent = message; el.className = `toast show ${error ? 'error' : ''}`; clearTimeout(toast.timer);
    toast.timer = setTimeout(() => { el.className = 'toast'; }, 4200);
  }

  function itemQty(code) { return Number((state.bundle?.inventory || []).find(x => x.code === code)?.quantity || 0); }
  function rarityLabel(r) { return ({common:'灵兽',rare:'珍兽',epic:'异兽',legendary:'神兽'})[r] || r || '灵兽'; }
  function elementLabel(v) { return ({fire:'火',thunder:'雷',wood:'木',water:'水',metal:'金',wind:'风',ice:'冰',earth:'土'})[v] || v || '灵'; }
  function beastGlyph(b) { return ({fire:'焰',thunder:'雷',wood:'木',water:'澜',metal:'锋',wind:'羽',ice:'霜',earth:'岳'})[b?.element] || '灵'; }
  function inventoryName(code) { return (state.bundle?.inventory || []).find(x=>x.code===code)?.name || code; }
  function selectedBeast() { return (state.bundle?.beasts || []).find(b => String(b.id) === String(state.selectedId)) || (state.bundle?.beasts || [])[0] || null; }

  async function load(force = false) {
    if (state.loading || (!force && Date.now() - state.lastLoad < 3000 && state.bundle)) { render(); return; }
    const root = document.getElementById('spiritBeastRootV267'); if (!root) return;
    state.loading = true; if (!state.bundle) root.innerHTML = '<div class="sbv267-loading"><i></i><span>正在唤醒灵兽苑……</span></div>';
    try {
      state.bundle = await rpc('get_spirit_beast_hub_v267'); state.lastLoad = Date.now();
      if (!state.selectedId && state.bundle?.beasts?.length) state.selectedId = state.bundle.beasts[0].id;
      render();
    } catch (e) { root.innerHTML = `<div class="sbv267-empty"><b>灵兽苑尚未开启</b><p>${esc(humanError(e))}</p></div>`; }
    finally { state.loading = false; }
  }

  async function loadRanking(force = false) {
    if (state.ranking && !force) return;
    try { state.ranking = await rpc('get_spirit_beast_ranking_v267', { p_limit: 100 }); } catch (e) { toast(humanError(e), true); }
  }

  async function act(name, body, success, refresh = true) {
    if (state.busy) return; state.busy = true; renderBusy(true);
    try {
      const out = await rpc(name, body); if (success) toast(typeof success === 'function' ? success(out) : success);
      if (refresh) { state.bundle = null; state.ranking = null; await load(true); }
      return out;
    } catch (e) { toast(humanError(e), true); }
    finally { state.busy = false; renderBusy(false); }
  }

  function renderBusy(on) { document.querySelectorAll('#spiritBeastRootV267 button,#spiritBeastRootV267 select,#spiritBeastRootV267 input').forEach(el => { if (on) el.setAttribute('disabled',''); else el.removeAttribute('disabled'); }); }

  function encounterHtml() {
    const e = state.bundle?.pending_encounter; if (!e) return '';
    const left = Math.max(0, Math.ceil((new Date(e.expires_at).getTime() - Date.now()) / 60000));
    return `<article class="sbv267-encounter rarity-${esc(e.rarity)}">
      <div class="sbv267-glyph">${esc(beastGlyph(e))}</div><div class="sbv267-enc-copy"><span>${esc(e.region_code || '九霄')} · 野外遭遇</span><h4>${esc(e.species_name)}</h4><p>${esc(e.description || '')}</p>
      <small>${esc(e.bloodline_hint || '')} · 已尝试 ${fmt(e.attempts)} 次 · ${left}分钟后离去</small></div>
      <div class="sbv267-capture"><button type="button" data-sb-capture="none">徒手安抚</button><button type="button" data-sb-capture="spirit_beast_talisman">御兽符 ×${fmt(itemQty('spirit_beast_talisman'))}</button><button class="primary" type="button" data-sb-capture="spirit_beast_talisman_high">高级御兽符 ×${fmt(itemQty('spirit_beast_talisman_high'))}</button></div>
    </article>`;
  }

  function beastCard(b) {
    return `<button class="sbv267-beast-card rarity-${esc(b.rarity)} ${b.is_active?'active':''} ${String(b.id)===String(state.selectedId)?'selected':''}" type="button" data-sb-select="${esc(b.id)}">
      <span class="sbv267-beast-glyph">${esc(beastGlyph(b))}</span><span class="sbv267-beast-main"><b>${esc(b.display_name)}</b><small>${esc(rarityLabel(b.rarity))} · ${esc(elementLabel(b.element))} · ${fmt(b.evolution_stage)}阶形态</small></span>
      <span class="sbv267-beast-meta"><i>Lv.${fmt(b.level)}</i><i>血脉 ${fmt(b.bloodline)}</i><i>${b.is_active?'出战中':`评分 ${fmt(b.score)}`}</i></span>
    </button>`;
  }

  function detailHtml(b) {
    if (!b) return `<div class="sbv267-empty"><b>灵兽苑尚为空寂</b><p>游历中可偶遇灵兽，秘境与世界BOSS也会掉落兽卵和培养材料。</p></div>`;
    const sameLine = (state.bundle?.beasts || []).filter(x => x.id !== b.id && x.lineage_code === b.lineage_code);
    const aux = state.bundle?.aux_skills || [];
    const expPct = Math.max(0, Math.min(100, Number(b.exp || 0) / Math.max(1, Number(b.next_level_exp || 1)) * 100));
    return `<article class="sbv267-detail rarity-${esc(b.rarity)}">
      <div class="sbv267-detail-head"><span class="sbv267-portrait">${esc(beastGlyph(b))}</span><div><span>${esc(rarityLabel(b.rarity))} · ${esc(elementLabel(b.element))}系 · ${fmt(b.evolution_stage)}阶</span><h3>${esc(b.display_name)}</h3><p>${esc(b.description || '')}</p></div><strong>${b.is_active?'出战':'休憩'}</strong></div>
      <div class="sbv267-stat-grid"><span><small>等级</small><b>${fmt(b.level)} / ${fmt(b.level_cap)}</b></span><span><small>灵兽境界</small><b>第 ${fmt(b.beast_realm_order)} 境</b></span><span><small>血脉</small><b>${fmt(b.bloodline)}</b></span><span><small>亲密</small><b>${fmt(b.intimacy)}</b></span><span><small>性格</small><b>${esc(b.personality_name)}</b></span><span><small>总评分</small><b>${fmt(b.score)}</b></span></div>
      <div class="sbv267-exp"><i style="width:${expPct}%"></i><span>成长 ${fmt(b.exp)} / ${fmt(b.next_level_exp)}</span></div>
      <div class="sbv267-skill-grid"><div><small>本命战技 Lv.${fmt(b.skill_level)}</small><b>${esc(b.innate_skill_name)}</b><p>${esc(b.innate_skill_description || '')}</p></div><div><small>辅助天赋 ${b.aux_skill_code?`Lv.${fmt(b.aux_skill_level)}`:''}</small><b>${esc(b.aux_skill_name || '尚未领悟')}</b><p>${b.aux_skill_code?'可消耗兽魂继续强化。':'可使用技能残卷学习一个辅助天赋。'}</p></div></div>
      <div class="sbv267-actions">
        <button data-sb-active="${esc(b.id)}" ${b.is_active?'disabled':''}>${b.is_active?'正在出战':'设为出战'}</button>
        <button data-sb-feed="${esc(b.id)}" data-count="1">喂养×1</button><button data-sb-feed="${esc(b.id)}" data-count="10">喂养×10</button><button data-sb-interact="${esc(b.id)}" ${b.last_interact_day===state.bundle?.server_day?'disabled':''}>${b.last_interact_day===state.bundle?.server_day?'今日已互动':'今日互动'}</button>
        <button data-sb-break="${esc(b.id)}">境界突破</button><button class="primary" data-sb-evolve="${esc(b.id)}" ${b.next_species_code?'':'disabled'}>${b.next_species_code?'血脉进化':'已至终形'}</button>
        <button data-sb-upgrade="${esc(b.id)}" data-slot="innate">强化战技</button><button data-sb-reroll="${esc(b.id)}">洗髓性格</button><button data-sb-rename="${esc(b.id)}">赐名</button><button data-sb-lock="${esc(b.id)}" data-value="${b.locked?'false':'true'}">${b.locked?'解除锁定':'锁定保护'}</button>
      </div>
      <div class="sbv267-secondary">
        <label>辅助天赋<select data-sb-aux-select="${esc(b.id)}"><option value="">选择天赋</option>${aux.map(x=>`<option value="${esc(x.skill_code)}" ${x.skill_code===b.aux_skill_code?'selected':''}>${esc(x.name)}</option>`).join('')}</select></label>
        <button data-sb-learn-aux="${esc(b.id)}">${b.aux_skill_code?'更换辅助天赋':'学习辅助天赋'}</button><button data-sb-upgrade="${esc(b.id)}" data-slot="aux" ${b.aux_skill_code?'':'disabled'}>强化辅助天赋</button>
        <label>血脉传承<select data-sb-donor-select="${esc(b.id)}"><option value="">同族灵兽</option>${sameLine.map(x=>`<option value="${esc(x.id)}">${esc(x.display_name)} · 血脉${fmt(x.bloodline)}</option>`).join('')}</select></label><button data-sb-inherit="${esc(b.id)}" ${sameLine.length?'':'disabled'}>传承血脉</button>
        <button class="danger" data-sb-release="${esc(b.id)}" ${b.locked||b.is_active?'disabled':''}>放归天地</button>
      </div>
    </article>`;
  }

  function eggsHtml() {
    const eggs = (state.bundle?.inventory || []).filter(x => x.code?.startsWith('spirit_beast_egg_') && Number(x.quantity)>0);
    if (!eggs.length) return `<div class="sbv267-empty compact"><b>暂无兽卵</b><p>秘境与世界BOSS有机会获得未认主兽卵，可在天墟交易。</p></div>`;
    return `<div class="sbv267-egg-grid">${eggs.map(x=>`<button type="button" data-sb-hatch="${esc(x.code)}"><span>卵</span><b>${esc(x.name)}</b><small>持有 ${fmt(x.quantity)} · 点击孵化</small></button>`).join('')}</div>`;
  }

  function codexHtml() {
    const rows = state.bundle?.codex || [];
    const unlocked = Number(state.bundle?.codex_unlocked || 0);
    const mask = Number(state.bundle?.state?.codex_claim_mask || 0);
    const milestones = [
      {n:10,bit:1,text:'兽粮×20 · 兽魂×20 · 御兽符×3'},
      {n:20,bit:2,text:'兽粮×30 · 兽魂×40 · 上品御兽符×2 · 洗髓露×1'},
      {n:30,bit:4,text:'兽魂×80 · 悟法卷×2 · 洗髓露×1'},
      {n:45,bit:8,text:'兽魂×150 · 上品御兽符×5 · 洗髓露×3 · 悟法卷×3'},
      {n:60,bit:16,text:'兽魂×300 · 上品御兽符×10 · 洗髓露×5 · 悟法卷×5'}
    ];
    const rewardHtml = milestones.map(m=>{const claimed=(mask&m.bit)!==0;const ready=unlocked>=m.n;return `<article class="sbv267-codex-reward ${claimed?'claimed':ready?'ready':''}"><span>${m.n}图鉴</span><b>${esc(m.text)}</b><button type="button" data-sb-codex-reward="${m.n}" ${claimed||!ready?'disabled':''}>${claimed?'已领取':ready?'领取奖励':`还差 ${m.n-unlocked}`}</button></article>`}).join('');
    return `<div class="sbv267-codex-head"><b>灵兽图鉴 ${fmt(unlocked)} / ${fmt(state.bundle?.codex_total)}</b><span>获得、进化与孵化均会永久点亮对应形态</span></div><div class="sbv267-codex-rewards">${rewardHtml}</div><div class="sbv267-codex">${rows.map(x=>`<article class="${x.unlocked?'unlocked':'locked'} rarity-${esc(x.rarity)}"><span>${x.unlocked?esc(beastGlyph(x)):'?'}</span><b>${x.unlocked?esc(x.name):'未识灵兽'}</b><small>${esc(elementLabel(x.element))} · ${fmt(x.evolution_stage)}阶</small>${x.unlocked?`<em>最高血脉 ${fmt(x.highest_bloodline)} · Lv.${fmt(x.highest_level)}</em>`:'<em>等待结缘</em>'}</article>`).join('')}</div>`;
  }

  function rankingHtml() {
    const rows = state.ranking?.rows || [];
    return `<div class="sbv267-ranking-head"><b>九霄灵兽榜</b><button type="button" data-sb-ranking-refresh>刷新</button></div>${rows.length?`<div class="sbv267-ranking">${rows.map((x,i)=>`<article class="${x.is_mine?'mine':''}"><strong>${fmt(x.rank||i+1)}</strong><span><b>${esc(x.display_name)}</b><small>${esc(x.character_name)} · ${esc(rarityLabel(x.rarity))}</small></span><em>血脉${fmt(x.bloodline)} · ${fmt(x.score)}</em></article>`).join('')}</div>`:'<div class="sbv267-empty compact">暂无排行数据</div>'}`;
  }

  function render() {
    const root = document.getElementById('spiritBeastRootV267'); if (!root) return;
    const b = state.bundle; if (!b) return;
    const s = b.state || {}; const beast = selectedBeast();
    root.innerHTML = `<div class="sbv267-shell" data-build="${BUILD}">
      <header class="sbv267-hero"><div><span>洞府 · 灵兽苑</span><h3>万灵归苑</h3><p>游历结缘，秘境育兽，血脉进化；已认主灵兽不可交易，兽卵与培养材料可流通天墟。</p></div><div class="sbv267-hero-stats"><b>${fmt(s.owned_count)} / ${fmt(s.capacity)}</b><small>兽苑 Lv.${fmt(s.stable_level)}</small></div></header>
      ${encounterHtml()}
      <nav class="sbv267-tabs"><button class="${state.view==='stable'?'active':''}" data-sb-view="stable">灵兽苑</button><button class="${state.view==='eggs'?'active':''}" data-sb-view="eggs">兽卵</button><button class="${state.view==='codex'?'active':''}" data-sb-view="codex">图鉴 ${fmt(b.codex_unlocked)}/${fmt(b.codex_total)}</button><button class="${state.view==='ranking'?'active':''}" data-sb-view="ranking">灵兽榜</button></nav>
      <div class="sbv267-toolbar"><button type="button" data-sb-supply>领取今日供给</button><button type="button" data-sb-upgrade-stable>扩建兽苑</button><span>兽粮 ${fmt(itemQty('spirit_beast_food'))}</span><span>兽魂 ${fmt(itemQty('spirit_beast_soul'))}</span><span>洗髓露 ${fmt(itemQty('spirit_beast_marrow_dew'))}</span><span>技能残卷 ${fmt(itemQty('spirit_beast_skill_scroll'))}</span></div>
      ${state.view==='stable'?`<div class="sbv267-stable-layout"><aside class="sbv267-beast-list">${(b.beasts||[]).length?(b.beasts||[]).map(beastCard).join(''):'<div class="sbv267-empty compact">尚未收服灵兽</div>'}</aside><main>${detailHtml(beast)}</main></div>`:''}
      ${state.view==='eggs'?eggsHtml():''}${state.view==='codex'?codexHtml():''}${state.view==='ranking'?rankingHtml():''}
      <footer class="sbv267-foot">数据库轻量模式：普通喂养与战斗不写永久大JSON；幂等请求、已结算遭遇会自动TTL清理。</footer>
    </div>`;
    bind(); if (state.busy) renderBusy(true);
  }

  function bind() {
    const root = document.getElementById('spiritBeastRootV267'); if (!root) return;
    root.querySelectorAll('[data-sb-view]').forEach(btn => btn.addEventListener('click', async () => { state.view=btn.dataset.sbView; if(state.view==='ranking') await loadRanking(); render(); }));
    root.querySelectorAll('[data-sb-select]').forEach(btn => btn.addEventListener('click',()=>{ state.selectedId=btn.dataset.sbSelect; render(); }));
    root.querySelector('[data-sb-supply]')?.addEventListener('click',()=>act('spirit_beast_claim_daily_supply_v267',{p_request_id:uuid()},'今日灵兽供给已收入洞府。'));
    root.querySelector('[data-sb-upgrade-stable]')?.addEventListener('click',()=>{ if(confirm('扩建灵兽苑会消耗兽魂与灵石，确认继续？')) act('spirit_beast_upgrade_stable_v267',{p_request_id:uuid()},o=>`兽苑已扩建至 Lv.${o?.stable_level||''}`); });
    root.querySelectorAll('[data-sb-capture]').forEach(btn=>btn.addEventListener('click',()=>{ const e=state.bundle?.pending_encounter;if(!e)return; act('spirit_beast_capture_v267',{p_encounter_id:e.id,p_talisman_code:btn.dataset.sbCapture,p_request_id:uuid()},o=>o?.status==='captured'?`收服成功：${o?.species_name||'灵兽'}！`:o?.status==='fled'?'捕捉失败，它已经警觉逃离。':'捕捉失败，它仍在警惕地观察你。'); }));
    root.querySelectorAll('[data-sb-hatch]').forEach(btn=>btn.addEventListener('click',()=>act('spirit_beast_hatch_egg_v267',{p_item_code:btn.dataset.sbHatch,p_request_id:uuid()},'兽卵孵化成功。')));
    root.querySelectorAll('[data-sb-active]').forEach(btn=>btn.addEventListener('click',()=>act('spirit_beast_set_active_v267',{p_beast_id:btn.dataset.sbActive,p_request_id:uuid()},'已设为本命出战灵兽。')));
    root.querySelectorAll('[data-sb-feed]').forEach(btn=>btn.addEventListener('click',()=>act('spirit_beast_feed_v267',{p_beast_id:btn.dataset.sbFeed,p_food_count:Number(btn.dataset.count||1),p_request_id:uuid()},'灵兽成长有所精进。')));
    root.querySelectorAll('[data-sb-interact]').forEach(btn=>btn.addEventListener('click',()=>act('spirit_beast_interact_v267',{p_beast_id:btn.dataset.sbInteract,p_request_id:uuid()},'亲密度提升。')));
    root.querySelectorAll('[data-sb-break]').forEach(btn=>btn.addEventListener('click',()=>{if(confirm('确认消耗兽魂与灵石为灵兽突破境界？'))act('spirit_beast_breakthrough_v267',{p_beast_id:btn.dataset.sbBreak,p_request_id:uuid()},'灵兽突破成功！');}));
    root.querySelectorAll('[data-sb-evolve]').forEach(btn=>btn.addEventListener('click',()=>{if(confirm('血脉进化会消耗兽魂、元素精魄与灵石，确认进化？'))act('spirit_beast_evolve_v267',{p_beast_id:btn.dataset.sbEvolve,p_request_id:uuid()},'血脉蜕变，灵兽完成进化！');}));
    root.querySelectorAll('[data-sb-reroll]').forEach(btn=>btn.addEventListener('click',()=>{if(confirm('消耗洗髓露重塑灵兽性格？'))act('spirit_beast_reroll_personality_v267',{p_beast_id:btn.dataset.sbReroll,p_request_id:uuid()},'洗髓完成，性格已重塑。');}));
    root.querySelectorAll('[data-sb-rename]').forEach(btn=>btn.addEventListener('click',()=>{const name=prompt('给灵兽赐名（1—12字符）','');if(name!=null)act('spirit_beast_rename_v267',{p_beast_id:btn.dataset.sbRename,p_name:name,p_request_id:uuid()},'灵兽新名已记入灵契。');}));
    root.querySelectorAll('[data-sb-lock]').forEach(btn=>btn.addEventListener('click',()=>act('spirit_beast_set_lock_v267',{p_beast_id:btn.dataset.sbLock,p_locked:btn.dataset.value==='true',p_request_id:uuid()},btn.dataset.value==='true'?'已锁定保护。':'已解除锁定。')));
    root.querySelectorAll('[data-sb-upgrade]').forEach(btn=>btn.addEventListener('click',()=>act('spirit_beast_upgrade_skill_v267',{p_beast_id:btn.dataset.sbUpgrade,p_slot:btn.dataset.slot,p_request_id:uuid()},'灵兽技能已强化。')));
    root.querySelectorAll('[data-sb-learn-aux]').forEach(btn=>btn.addEventListener('click',()=>{const sel=root.querySelector(`[data-sb-aux-select="${CSS.escape(btn.dataset.sbLearnAux)}"]`);const code=sel?.value;if(!code){toast('请先选择辅助天赋。',true);return;}act('spirit_beast_learn_aux_skill_v267',{p_beast_id:btn.dataset.sbLearnAux,p_skill_code:code,p_request_id:uuid()},'辅助天赋已铭刻。');}));
    root.querySelectorAll('[data-sb-inherit]').forEach(btn=>btn.addEventListener('click',()=>{const sel=root.querySelector(`[data-sb-donor-select="${CSS.escape(btn.dataset.sbInherit)}"]`);const donor=sel?.value;if(!donor){toast('请选择同族灵兽作为血脉材料。',true);return;}if(confirm('血脉传承会永久消耗材料灵兽，确认继续？'))act('spirit_beast_inherit_bloodline_v267',{p_target_beast_id:btn.dataset.sbInherit,p_donor_beast_id:donor,p_request_id:uuid()},'血脉传承完成。');}));
    root.querySelectorAll('[data-sb-release]').forEach(btn=>btn.addEventListener('click',()=>{const phrase=prompt('放归会永久失去这只灵兽并获得兽魂。请输入“放归”确认：','');if(phrase==='放归')act('spirit_beast_release_v267',{p_beast_id:btn.dataset.sbRelease,p_request_id:uuid()},'灵兽已放归天地，兽魂已回收。');}));
    root.querySelectorAll('[data-sb-codex-reward]').forEach(btn=>btn.addEventListener('click',()=>act('spirit_beast_claim_codex_reward_v267',{p_milestone:Number(btn.dataset.sbCodexReward),p_request_id:uuid()},`图鉴 ${btn.dataset.sbCodexReward} 里程碑奖励已领取。`)));
    root.querySelector('[data-sb-ranking-refresh]')?.addEventListener('click',async()=>{state.ranking=null;await loadRanking(true);render();});
  }

  window.addEventListener('jiuxiao:spirit-beast-rendered',()=>load(false));
  window.addEventListener('jiuxiao:exploration-changed',e=>{const sb=e?.detail?.spirit_beast_v267;if(sb?.status==='encounter') toast(`游历中感应到灵兽气息：${sb.species_name||'未知灵兽'}`); state.bundle=null; load(true);});
  window.addEventListener('jiuxiao:secret-realm-claimed',e=>{const sb=e?.detail?.spirit_beast_v267;if(sb?.egg_item_code) toast(`秘境所得：${inventoryName(sb.egg_item_code)}`);state.bundle=null;load(true);});
  window.addEventListener('jiuxiao:world-boss-finished',e=>{const sb=e?.detail?.spirit_beast_v267;if(sb) toast('灵兽已从世界BOSS战中获得成长与战利品。');state.bundle=null;load(true);});
})();
