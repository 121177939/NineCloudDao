(() => {
  'use strict';

  const MODULE = 'B-EQUIPMENT01';
  const VERSION = '2.1.1-cache115-equipped-detail';
  const config = window.GAME_CONFIG || {};
  const baseUrl = String(config.supabaseUrl || '').replace(/\/+$/, '');
  const apiKey = String(config.supabasePublishableKey || '');
  const projectRef = (() => {
    try { return new URL(baseUrl).hostname.split('.')[0]; } catch { return 'unknown'; }
  })();
  const sessionKey = `nine_cloud_dao_session_${projectRef}_v1`;
  const deviceKey = `nine_cloud_dao_device_${projectRef}_v1`;

  const gradeColors = {
    yellow: '#C99A32', mystic: '#4F86D9', earth: '#925FD1', heaven: '#E05252', immortal: '#F2D06B'
  };
  const gradeDecomposeEssence = { yellow: 10, mystic: 20, earth: 40, heaven: 80, immortal: 160 };
  const gradeEnhancementEssence = { yellow: 1, mystic: 2, earth: 4, heaven: 8, immortal: 16 };
  const gradeBaseSockets = { yellow: 1, mystic: 2, earth: 3, heaven: 4, immortal: 5 };
  const slotMeta = {
    weapon: ['攻', '武器', '道攻'],
    clothing: ['御', '衣服', '道御'],
    pants: ['生', '裤子', '生机'],
    shoes: ['身', '鞋子', '身法'],
    ring: ['元', '戒指', '五行最终伤害']
  };
  const weaponKindLabels = { sword: '剑', blade: '刀', spear: '枪', staff: '棍', fan: '扇', wand: '杖', qin: '琴', ring_blade: '环' };
  const locationLabels = { backpack: '背包', cave: '洞府', pending: '待领取', equipped: '已穿戴' };

  const state = {
    data: null,
    enhancement: null,
    loading: false,
    view: 'backpack',
    filter: 'all',
    sort: 'grade',
    lastFetch: 0,
    available: false,
    disabled: false,
    lastOpportunityId: null
  };

  const esc = value => String(value ?? '')
    .replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;').replaceAll("'", '&#039;');
  const uuid = () => globalThis.crypto?.randomUUID?.() || 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const value = Math.random() * 16 | 0;
    return (c === 'x' ? value : (value & 3 | 8)).toString(16);
  });
  const session = () => {
    try { return JSON.parse(localStorage.getItem(sessionKey) || 'null'); } catch { return null; }
  };
  const device = () => localStorage.getItem(deviceKey) || '';
  const nfmt = value => Number(value || 0).toLocaleString('zh-CN');

  function configuredGradeDecomposeEssence(gradeCode) {
    const rule = state.enhancement?.grade_rules?.[gradeCode] || {};
    const configured = Number(rule.decompose_essence ?? rule.essence);
    if (Number.isFinite(configured) && configured > 0) return configured;
    const fallback = Number(gradeDecomposeEssence[gradeCode]);
    return Number.isFinite(fallback) && fallback > 0 ? fallback : 0;
  }

  function configuredGradeEnhancementEssence(gradeCode) {
    const configured = Number(state.enhancement?.grade_rules?.[gradeCode]?.enhancement_essence_cost);
    if (Number.isFinite(configured) && configured > 0) return configured;
    const fallback = Number(gradeEnhancementEssence[gradeCode]);
    return Number.isFinite(fallback) && fallback > 0 ? fallback : 0;
  }

  function gradeDecomposeSummary() {
    return ['yellow', 'mystic', 'earth', 'heaven', 'immortal']
      .map(code => nfmt(configuredGradeDecomposeEssence(code)))
      .join('、');
  }

  function gradeEnhancementSummary() {
    return ['yellow', 'mystic', 'earth', 'heaven', 'immortal']
      .map(code => nfmt(configuredGradeEnhancementEssence(code)))
      .join('、');
  }

  function toast(message, type = 'success') {
    const element = document.getElementById('toast');
    if (!element) return;
    element.textContent = message;
    element.className = `toast show ${type}`;
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => { element.className = 'toast'; }, 4200);
  }

  function errorText(error) {
    const raw = String(error?.message || error || '装备操作失败');
    const map = [
      ['EQUIPMENT_BACKPACK_FULL', '背包空间不足。'],
      ['EQUIPMENT_REALM_TOO_HIGH', '当前境界不足，不能穿戴这件装备。'],
      ['EQUIPMENT_ITEM_NOT_FOUND', '装备不存在、已分解或已在强化失败时销毁。'],
      ['EQUIPMENT_ITEM_NOT_IN_BACKPACK', '只有背包中的装备可以穿戴。'],
      ['EQUIPMENT_DECOMPOSE_PROTECTED_OR_MISSING', '所选装备包含锁定、非背包或已不存在的装备。'],
      ['EQUIPMENT_DECOMPOSE_DUPLICATE_IDS', '分解清单中存在重复装备。'],
      ['EQUIPMENT_DECOMPOSE_EMPTY', '请至少选择一件装备。'],
      ['EQUIPMENT_ESSENCE_INSUFFICIENT', '器源数量不足。'],
      ['INSUFFICIENT_SPIRIT_STONES', '灵石数量不足。'],
      ['EQUIPMENT_ENHANCE_BACKPACK_ONLY', '只有背包中的装备可以强化，请先卸下或取回。'],
      ['EQUIPMENT_ENHANCE_LOCKED', '锁定装备不能强化，请先解锁。'],
      ['EQUIPMENT_ENHANCE_MAX_LEVEL', '该装备已经强化至最高等级 +10。'],
      ['EQUIPMENT_ENHANCE_LEVEL_DISABLED', '该强化等级当前已被后台停用。'],
      ['EQUIPMENT_SLOT_EMPTY', '该装备槽当前为空。'],
      ['EQUIPMENT_SYSTEM_DISABLED', '装备系统当前已停用。'],
      ['EQUIPMENT_DECOMPOSE_BATCH_TOO_LARGE', '单次最多分解100件装备。'],
      ['REQUEST_ID_REQUIRED', '操作请求编号缺失，请刷新页面后重试。'],
      ['AUTH_REQUIRED', '请先登录后使用装备系统。'],
      ['NO_ACTIVE_CHARACTER', '未找到当前角色。'],
      ['PGRST202', '装备数据库尚未完成V1.8.0升级。'],
      ['Could not find the function', '装备数据库尚未完成V1.8.0升级。']
    ];
    return (map.find(([key]) => raw.includes(key)) || [])[1] || raw;
  }

  async function rpc(name, body = {}) {
    const currentSession = session();
    if (!currentSession?.access_token) throw new Error('AUTH_REQUIRED');
    const response = await fetch(`${baseUrl}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: {
        apikey: apiKey,
        Authorization: `Bearer ${currentSession.access_token}`,
        'Content-Type': 'application/json',
        'X-Game-Session-Id': device()
      },
      body: JSON.stringify(body)
    });
    const text = await response.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; } catch { data = text; }
    if (!response.ok) throw new Error(data?.message || data?.msg || data?.error || `HTTP ${response.status}`);
    return Array.isArray(data) ? data[0] || null : data;
  }

  function enhancementLevelConfig(targetLevel) {
    return (state.enhancement?.levels || []).find(row => Number(row.target_level) === Number(targetLevel)) || null;
  }

  function extraSocketsAt(level) {
    return (state.enhancement?.levels || [])
      .filter(row => Number(row.target_level) <= Number(level))
      .reduce((sum, row) => sum + Number(row.extra_socket_grant || 0), 0);
  }

  function formatMainStat(item, value = item?.main_stat_value) {
    const numeric = Number(value || 0);
    const label = item?.main_stat_label || slotMeta[item?.slot_code]?.[2] || '主属性';
    if (item?.slot_code === 'ring') {
      return `${label} +${numeric.toLocaleString('zh-CN', { maximumFractionDigits: 4 })}%`;
    }
    return `${label} +${Math.round(numeric).toLocaleString('zh-CN')}`;
  }

  function itemEnhancementName(item) {
    const level = Number(item?.enhancement_level || 0);
    return `${item?.short_name || item?.full_name || '装备'}${level > 0 ? ` +${level}` : ''}`;
  }

  function normalizeItem(item, enhancementById) {
    if (!item) return item;
    const extra = enhancementById.get(String(item.id)) || {};
    const merged = { ...item, ...extra };
    merged.enhancement_level = Number(merged.enhancement_level || 0);
    merged.base_main_stat_value = Number(merged.base_main_stat_value ?? merged.main_stat_value ?? 0);
    merged.main_stat_value = Number(merged.main_stat_value ?? merged.base_main_stat_value ?? 0);
    merged.base_socket_capacity = Number(merged.base_socket_capacity ?? gradeBaseSockets[merged.grade_code] ?? 0);
    merged.total_socket_capacity = Number(merged.total_socket_capacity ?? merged.socket_capacity ?? merged.base_socket_capacity + extraSocketsAt(merged.enhancement_level));
    merged.socket_capacity = merged.total_socket_capacity;
    merged.opened_sockets = Number(merged.opened_sockets ?? merged.total_socket_capacity);
    merged.socket_content_count = Number(merged.socket_content_count || 0);
    merged.decompose_essence = Number(configuredGradeDecomposeEssence(merged.grade_code) || merged.decompose_essence || 0);
    merged.main_stat_display = formatMainStat(merged, merged.main_stat_value);
    merged.socket_display = `孔位 ${merged.total_socket_capacity}${merged.socket_content_count > 0 ? ` · 已用 ${merged.socket_content_count}` : ''}`;
    return merged;
  }

  function mergeEnhancementData(baseData, enhancementData) {
    const byId = new Map((enhancementData?.items || []).map(row => [String(row.id), row]));
    const result = { ...(baseData || {}) };
    ['backpack', 'cave', 'pending'].forEach(location => {
      result[location] = Array.isArray(baseData?.[location]) ? baseData[location].map(item => normalizeItem(item, byId)) : [];
    });
    result.equipped = Object.fromEntries(Object.entries(baseData?.equipped || {}).map(([slot, item]) => [slot, normalizeItem(item, byId)]));
    result.enhancement = enhancementData;
    result.materials = {
      ...(baseData?.materials || {}),
      essence: Number(enhancementData?.essence || 0),
      spirit_stones: Number(enhancementData?.spirit_stones || 0)
    };
    return result;
  }

  function itemList(location) {
    return Array.isArray(state.data?.[location]) ? state.data[location] : [];
  }

  function allItems() {
    return [
      ...itemList('backpack'),
      ...itemList('cave'),
      ...itemList('pending'),
      ...Object.values(state.data?.equipped || {}).filter(Boolean)
    ];
  }

  async function refresh(force = false) {
    if (state.loading || !session()?.access_token) return state.data;
    if (!force && Date.now() - state.lastFetch < 5000) return state.data;
    state.loading = true;
    try {
      const [baseData, enhancementData] = await Promise.all([
        rpc('get_equipment_system_bequipment01'),
        rpc('get_equipment_enhancement_state_v180')
      ]);
      state.enhancement = enhancementData;
      state.data = mergeEnhancementData(baseData, enhancementData);
      state.available = true;
      state.disabled = state.data?.status === 'disabled';
      state.lastFetch = Date.now();
      renderAll();
      return state.data;
    } catch (error) {
      console.warn(`[${MODULE}] refresh failed`, error);
      state.available = false;
      renderAll();
      return null;
    } finally {
      state.loading = false;
    }
  }

  async function refreshBattleSnapshotAfterLoadout(actionName) {
    if (!['equip_item_bequipment01', 'unequip_item_bequipment01'].includes(actionName)) return null;
    try {
      if (typeof window.JIUXIAO_REFRESH_BATTLE_SNAPSHOT_V1 === 'function') {
        return await window.JIUXIAO_REFRESH_BATTLE_SNAPSHOT_V1({ reason: 'equipment', action: actionName });
      }
      window.dispatchEvent(new CustomEvent('jiuxiao:equipment-loadout-changed', { detail: { action: actionName } }));
      return null;
    } catch (error) {
      console.warn(`[${MODULE}] 战斗属性即时刷新失败，将在下次页面同步时重试：`, error?.message || error);
      window.dispatchEvent(new CustomEvent('jiuxiao:equipment-loadout-changed', { detail: { action: actionName, retry: true } }));
      return null;
    }
  }

  async function action(name, body, successText) {
    if (state.disabled) {
      toast('装备系统当前已停用。', 'error');
      return null;
    }
    try {
      const result = await rpc(name, { ...body, p_request_id: uuid() });
      await refresh(true);
      const snapshot = await refreshBattleSnapshotAfterLoadout(name);
      if (successText) {
        const powerText = ['equip_item_bequipment01', 'unequip_item_bequipment01'].includes(name) && Number.isFinite(Number(snapshot?.power))
          ? ` 当前战力 ${Number(snapshot.power).toLocaleString('zh-CN')}。`
          : '';
        toast(`${successText}${['equip_item_bequipment01', 'unequip_item_bequipment01'].includes(name) ? ' 战斗属性已实时更新。' : ''}${powerText}`);
      }
      return result;
    } catch (error) {
      toast(errorText(error), 'error');
      await refresh(true);
      return null;
    }
  }

  function color(item) {
    return item?.grade_color || gradeColors[item?.grade_code] || '#8f8068';
  }

  function equipmentEffectTier(item) {
    const level = Number(item?.enhancement_level || 0);
    if (level >= 10) return 'equipment-effect-bequipment01 equipment-effect-tier10-bequipment01';
    if (level >= 8) return 'equipment-effect-bequipment01 equipment-effect-tier8-bequipment01';
    if (level >= 6) return 'equipment-effect-bequipment01 equipment-effect-tier6-bequipment01';
    return '';
  }

  function itemIcon(item) {
    return `<span class="equipment-icon-bequipment01 ${equipmentEffectTier(item)}" style="--grade:${esc(color(item))}">${esc(item?.icon_glyph || slotMeta[item?.slot_code]?.[0] || '器')}</span>`;
  }

  function enhancementBadge(item) {
    const level = Number(item?.enhancement_level || 0);
    return level > 0 ? `<b class="equipment-enhancement-badge-bequipment01">+${level}</b>` : '';
  }

  function slotCardContent(item, slot) {
    const [emptyGlyph, label] = slotMeta[slot];
    if (!item) {
      return `<span class="yuanshen-sigil-v0155 equipment-empty-icon-bequipment01" aria-hidden="true">${emptyGlyph}</span><span class="yuanshen-stat-copy-v0155"><strong>${label}：未装备</strong><i></i><small>空槽 · 点击查看背包</small></span>`;
    }
    return `${itemIcon(item)}<span class="yuanshen-stat-copy-v0155 equipment-copy-bequipment01"><strong>${esc(itemEnhancementName(item))}：<em style="color:${esc(color(item))}">${esc(item.grade_name)}</em></strong><i></i><small>${esc(item.main_stat_display)}</small><small>${esc(item.socket_display)}</small></span>`;
  }

  function renderSpiritSlots() {
    const root = document.getElementById('primordialSpiritRootV1');
    if (!root || !state.available || !state.data) return;
    const map = { weapon: '.left-1', clothing: '.left-2', pants: '.right-1', shoes: '.right-2', ring: '.right-3' };
    Object.entries(map).forEach(([slot, selector]) => {
      const button = root.querySelector(`.yuanshen-stat-card-v0155${selector}`);
      if (!button) return;
      const item = state.data?.equipped?.[slot] || null;
      button.classList.add('equipment-slot-card-bequipment01');
      button.style.setProperty('--grade', color(item));
      button.dataset.equipmentSlot = slot;
      button.dataset.yuanshenStat = slotMeta[slot][1];
      button.dataset.yuanshenDetail = item
        ? `${item.full_name} +${item.enhancement_level || 0} · ${item.grade_name} · ${item.realm_name} · ${item.main_stat_display} · ${item.socket_display}`
        : `${slotMeta[slot][1]}槽尚未装备。`;
      button.innerHTML = slotCardContent(item, slot);
      if (button.dataset.equipmentBound !== '1') {
        button.dataset.equipmentBound = '1';
        button.addEventListener('click', event => {
          event.stopPropagation();
          const current = state.data?.equipped?.[button.dataset.equipmentSlot];
          if (current) openDetail(current); else focusBackpack();
        });
      }
    });
  }

  function sortItems(rows) {
    return [...rows].sort((a, b) => state.sort === 'time'
      ? String(b.acquired_at).localeCompare(String(a.acquired_at))
      : (Number(b.grade_order) - Number(a.grade_order)
        || Number(b.enhancement_level || 0) - Number(a.enhancement_level || 0)
        || Number(b.major_order) - Number(a.major_order)
        || String(a.full_name).localeCompare(String(b.full_name), 'zh-CN')));
  }

  function filtered(rows) {
    return sortItems(rows.filter(item => state.filter === 'all' || item.slot_code === state.filter));
  }

  function gridSocketDisplay(item) {
    return `孔位 ${Number(item?.socket_content_count || 0)}/${Number(item?.total_socket_capacity || 0)}`;
  }

  function gridGradeCornerLabel(item) {
    const name = String(item?.grade_name || '').trim();
    if (!name) return '';
    return name.endsWith('品') ? name.slice(0, -1) : name.slice(0, 1);
  }

  function gridItem(item) {
    return `<button type="button" class="equipment-grid-item-bequipment01" style="--grade:${esc(color(item))}" data-equipment-item="${esc(item.id)}" aria-label="${esc(item.full_name)}，${esc(item.grade_name)}，强化+${Number(item.enhancement_level || 0)}"><span class="equipment-grade-corner-bequipment01" aria-hidden="true">${esc(gridGradeCornerLabel(item))}</span><span class="equipment-grid-lock-bequipment01">${item.is_locked ? '锁' : ''}</span>${enhancementBadge(item)}${itemIcon(item)}<strong>${esc(item.short_name)}</strong><em>${esc(gridSocketDisplay(item))}</em></button>`;
  }

  function resourceStrip() {
    const essence = Number(state.data?.materials?.essence || 0);
    const stones = Number(state.data?.materials?.spirit_stones || 0);
    return `<button type="button" class="equipment-resource-strip-bequipment01" data-equipment-material="universal"><span><i>源</i><b>器源</b><strong>×${nfmt(essence)}</strong></span><span><i>灵</i><b>灵石</b><strong>×${nfmt(stones)}</strong></span><small>器源全境界、全部位通用；分解产出由GM配置，强化消耗保持原品级基数。</small></button>`;
  }

  function storagePanel() {
    const capacity = Math.max(36, Number(state.data?.rules?.backpack_capacity || 36));
    const allRows = itemList('backpack');
    const rows = filtered(allRows);
    const empty = Math.max(0, capacity - rows.length);
    return `<section class="equipment-storage-panel-bequipment01" data-equipment-panel="backpack"><div class="equipment-storage-head-bequipment01"><strong>随身背包</strong><span>${allRows.length}/${capacity} · 固定6×6 · 装备一件一格</span></div>${resourceStrip()}<div class="equipment-filter-bequipment01"><button data-eq-filter="all">全部</button>${Object.entries(slotMeta).map(([key, value]) => `<button data-eq-filter="${key}">${value[1]}</button>`).join('')}<button data-eq-sort>${state.sort === 'grade' ? '恢复所得顺序' : '一键整理'}</button><button class="batch-decompose-bequipment01" data-batch-decompose>批量分解</button></div><div class="equipment-grid-bequipment01">${rows.map(gridItem).join('')}${Array.from({ length: empty }, () => '<div class="equipment-grid-empty-bequipment01">道</div>').join('')}</div></section>`;
  }

  function caveEquipmentSlot(item) {
    const rarity = { yellow: 'uncommon', mystic: 'rare', earth: 'epic', heaven: 'legendary', immortal: 'legendary' }[item?.grade_code] || 'uncommon';
    return `<button type="button" class="cave-item-slot-b01 rarity-${rarity} equipment-cave-slot-bequipment01" data-equipment-cave-item="${esc(item.id)}" aria-label="洞府装备，${esc(item.full_name)}，${esc(item.grade_name)}，强化+${Number(item.enhancement_level || 0)}"><span class="cave-item-aura-b01" aria-hidden="true"></span>${enhancementBadge(item)}${itemIcon(item)}<span class="cave-item-name-b01">${esc(itemEnhancementName(item))}</span><span class="cave-item-type-b01">${esc(item.grade_name)} · ${esc(slotMeta[item.slot_code]?.[1] || '装备')}</span><strong class="cave-item-quantity-b01">器</strong></button>`;
  }

  function modalHost() {
    let root = document.getElementById('equipmentModalRootBEquipment01');
    if (!root) {
      root = document.createElement('div');
      root.id = 'equipmentModalRootBEquipment01';
      document.body.appendChild(root);
    }
    return root;
  }

  function closeModal() {
    modalHost().innerHTML = '';
  }

  function bindBackdrop(root) {
    root.querySelector('[data-eq-close]')?.addEventListener('click', closeModal);
    root.querySelector('.equipment-modal-backdrop-bequipment01')?.addEventListener('click', event => {
      if (event.target === event.currentTarget) closeModal();
    });
  }

  function openCaveEquipmentBox(items = itemList('cave')) {
    const rows = sortItems(items);
    const capacity = Math.max(36, Math.ceil(Math.max(1, rows.length) / 36) * 36);
    const empty = Math.max(0, capacity - rows.length);
    modalHost().innerHTML = `<div class="modal-backdrop equipment-modal-backdrop-bequipment01"><section class="modal equipment-modal-bequipment01 equipment-cave-box-modal-bequipment01" role="dialog" aria-modal="true"><button class="modal-close-button" data-eq-close>×</button><header><span class="equipment-icon-bequipment01">藏</span><div><span>洞府储物中的装备</span><h3>装备匣 · ${rows.length}件</h3></div></header><div class="equipment-grid-bequipment01 equipment-cave-box-grid-bequipment01">${rows.map(gridItem).join('')}${Array.from({ length: empty }, () => '<div class="equipment-grid-empty-bequipment01">道</div>').join('')}</div></section></div>`;
    const root = modalHost();
    bindBackdrop(root);
    root.querySelectorAll('[data-equipment-item]').forEach(button => {
      button.addEventListener('click', () => {
        const item = allItems().find(row => String(row.id) === button.dataset.equipmentItem);
        if (item) { closeModal(); openDetail(item); }
      });
    });
  }

  function renderCaveEquipmentIntoNative() {
    const cave = document.getElementById('caveStorageB01');
    const grid = cave?.querySelector('.cave-storage-grid-b01');
    if (!cave || !grid || !state.available) return;
    grid.querySelectorAll('[data-equipment-cave-item]').forEach(node => node.remove());
    cave.querySelector('[data-equipment-cave-overflow]')?.remove();
    const rows = sortItems(itemList('cave'));
    const empties = [...grid.querySelectorAll('.cave-item-slot-b01.empty')];
    const visible = rows.slice(0, empties.length);
    visible.forEach((item, index) => { empties[index].outerHTML = caveEquipmentSlot(item); });
    grid.querySelectorAll('[data-equipment-cave-item]').forEach(button => {
      button.addEventListener('click', () => {
        const item = allItems().find(row => String(row.id) === button.dataset.equipmentCaveItem);
        if (item) openDetail(item);
      });
    });
    const head = cave.querySelector('.cave-storage-head-b01 span');
    if (head) {
      const base = head.dataset.equipmentBaseText || head.textContent.replace(/ · 洞府装备 \d+$/, '');
      head.dataset.equipmentBaseText = base;
      head.textContent = `${base} · 洞府装备 ${rows.length}`;
    }
    if (rows.length > visible.length) {
      const overflow = document.createElement('button');
      overflow.type = 'button';
      overflow.className = 'equipment-cave-overflow-bequipment01';
      overflow.dataset.equipmentCaveOverflow = '1';
      overflow.textContent = `另有 ${rows.length - visible.length} 件洞府装备，打开装备匣`;
      overflow.addEventListener('click', () => openCaveEquipmentBox(rows));
      grid.insertAdjacentElement('afterend', overflow);
    }
  }

  function bindBackpackPanel(root) {
    if (!root) return;
    root.querySelectorAll('[data-eq-filter]').forEach(button => {
      button.classList.toggle('active', button.dataset.eqFilter === state.filter);
      button.addEventListener('click', () => { state.filter = button.dataset.eqFilter; renderBackpackInline(); });
    });
    root.querySelector('[data-eq-sort]')?.addEventListener('click', () => {
      state.sort = state.sort === 'grade' ? 'time' : 'grade';
      renderBackpackInline();
    });
    root.querySelector('[data-batch-decompose]')?.addEventListener('click', openBatchDecompose);
    root.querySelectorAll('[data-equipment-item]').forEach(button => {
      button.addEventListener('click', () => {
        const item = allItems().find(row => String(row.id) === button.dataset.equipmentItem);
        if (item) openDetail(item);
      });
    });
    root.querySelector('[data-claim-pending]')?.addEventListener('click', () => action('claim_pending_equipment_bequipment01', {}, '待领取装备已按空位收入背包。'));
    root.querySelector('[data-equipment-material]')?.addEventListener('click', openMaterial);
  }

  function renderBackpackInline() {
    const root = document.getElementById('primordialSpiritRootV1');
    if (!root) return;
    root.querySelector('#equipmentBackpackLauncherBEquipment01')?.remove();
    let host = root.querySelector('#equipmentBackpackInlineBEquipment01');
    if (!host) {
      host = document.createElement('section');
      host.id = 'equipmentBackpackInlineBEquipment01';
      host.className = 'equipment-backpack-inline-bequipment01';
      root.appendChild(host);
    }
    const pending = itemList('pending').length;
    host.innerHTML = `${state.disabled ? '<div class="equipment-disabled-bequipment01">装备系统当前已停用：装备数据只读，写操作已关闭。</div>' : ''}${pending ? `<div class="equipment-pending-bequipment01"><span>待领取装备 ${pending} 件</span><button type="button" data-claim-pending>领取到背包</button></div>` : ''}${state.available ? storagePanel() : '<div class="equipment-unavailable-bequipment01">装备数据库尚未完成V1.8.0升级，或强化状态读取失败。</div>'}`;
    bindBackpackPanel(host);
  }

  function focusBackpack() {
    renderBackpackInline();
    document.getElementById('equipmentBackpackInlineBEquipment01')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  function openBackpack() { focusBackpack(); }

  function compare(item) {
    const current = state.data?.equipped?.[item.slot_code];
    if (!current) return `当前${slotMeta[item.slot_code][1]}槽为空，穿戴后获得 ${item.main_stat_display}。`;
    const diff = Number(item.main_stat_value) - Number(current.main_stat_value);
    const diffText = item.slot_code === 'ring'
      ? `${diff >= 0 ? '+' : ''}${diff.toLocaleString('zh-CN', { maximumFractionDigits: 4 })}%`
      : `${diff >= 0 ? '+' : ''}${Math.round(diff).toLocaleString('zh-CN')}`;
    return `当前：${current.main_stat_display}；新装备：${item.main_stat_display}；变化：${diffText}。`;
  }

  async function openDetail(item) {
    const equipped = item.location === 'equipped';
    const inBag = item.location === 'backpack';
    const inCave = item.location === 'cave';
    const actions = [];
    if (inBag) actions.push(`<button class="primary-btn" data-eq-action="equip">${state.data?.equipped?.[item.slot_code] ? '更换' : '穿戴'}</button>`);
    if (equipped) actions.push('<button class="ghost-btn" data-eq-action="unequip">卸下</button>');
    if (inBag) actions.push(`<button class="enhance-btn-bequipment01" data-eq-action="enhance" ${item.is_locked || Number(item.enhancement_level) >= 10 ? 'disabled' : ''}>强化${Number(item.enhancement_level) >= 10 ? '已满' : `至 +${Number(item.enhancement_level || 0) + 1}`}</button>`);
    if (inBag) actions.push('<button class="ghost-btn" data-eq-action="cave">放入洞府</button>');
    if (inCave) actions.push('<button class="ghost-btn" data-eq-action="backpack">取回背包</button>');
    if (inBag || inCave) actions.push(`<button class="ghost-btn" data-eq-action="lock">${item.is_locked ? '解锁' : '锁定'}</button>`);
    if (inBag) actions.push('<button class="primary-btn" data-eq-action="forge">孔位 / 升品 / 破境</button>');
    if (inBag) actions.push(`<button class="danger-btn" data-eq-action="decompose" ${item.is_locked ? 'disabled' : ''}>分解得器源×${Number(item.decompose_essence)}</button>`);

    let socketRows = Array.from({ length: Math.min(8, Math.max(0, Number(item.opened_sockets ?? item.total_socket_capacity ?? item.socket_capacity ?? 0))) }, (_, i) => ({ index: i + 1, symbol: ['①','②','③','④','⑤','⑥','⑦','⑧'][i] || String(i + 1), empty: true, level: null, text: '空' }));
    try {
      const rows = await window.B_EQUIPMENT_V210?.detailRows?.(item);
      if (Array.isArray(rows)) socketRows = rows;
    } catch (error) {
      console.warn('[B-EQUIPMENT01] 装备详情孔位读取失败，使用空孔占位。', error);
    }
    const socketDetailHtml = socketRows.length
      ? socketRows.map(row => `<div class="equipment-detail-socket-row-bequipment01 ${row.empty ? 'is-empty' : ''} ${Number(row.level) === 10 ? 'is-max' : ''}"><b>${esc(row.symbol)}</b><span>${esc(row.text)}${row.empty ? '' : ` <em>（LV.${Number(row.level || 1)}）</em>`}</span></div>`).join('')
      : '<div class="equipment-detail-socket-row-bequipment01 is-empty"><b>①</b><span>空</span></div>';

    modalHost().innerHTML = `<div class="modal-backdrop equipment-modal-backdrop-bequipment01"><section class="modal equipment-modal-bequipment01" role="dialog" aria-modal="true"><button class="modal-close-button" data-eq-close>×</button><header style="--grade:${esc(color(item))}">${itemIcon(item)}<div><span>${esc(item.realm_name)} · ${esc(slotMeta[item.slot_code][1])}${item.weapon_kind ? ` · ${esc(item.weapon_kind_label || weaponKindLabels[item.weapon_kind] || item.weapon_kind)}` : ''}</span><h3>${esc(itemEnhancementName(item))}：<em>${esc(item.grade_name)}</em></h3></div></header><div class="equipment-detail-main-bequipment01"><strong>${esc(item.main_stat_display)}</strong><span>${esc(item.socket_display)}</span></div><section class="equipment-detail-sockets-bequipment01" aria-label="装备孔位属性">${socketDetailHtml}</section><div class="equipment-modal-actions-bequipment01">${actions.join('')}</div></section></div>`;

    const root = modalHost();
    bindBackdrop(root);
    root.querySelector('[data-eq-action="equip"]')?.addEventListener('click', () => { closeModal(); action('equip_item_bequipment01', { p_item_id: item.id }, '装备已穿戴。'); });
    root.querySelector('[data-eq-action="unequip"]')?.addEventListener('click', () => { closeModal(); action('unequip_item_bequipment01', { p_slot_code: item.slot_code }, '装备已卸下。'); });
    root.querySelector('[data-eq-action="enhance"]')?.addEventListener('click', () => { closeModal(); openEnhancement(item); });
    root.querySelector('[data-eq-action="forge"]')?.addEventListener('click', () => { closeModal(); window.B_EQUIPMENT_V210?.open?.(item); });
    root.querySelector('[data-eq-action="cave"]')?.addEventListener('click', () => { closeModal(); action('move_equipment_item_bequipment01', { p_item_id: item.id, p_target_location: 'cave' }, '装备已放入洞府。'); });
    root.querySelector('[data-eq-action="backpack"]')?.addEventListener('click', () => { closeModal(); action('move_equipment_item_bequipment01', { p_item_id: item.id, p_target_location: 'backpack' }, '装备已取回背包。'); });
    root.querySelector('[data-eq-action="lock"]')?.addEventListener('click', () => { closeModal(); action('set_equipment_lock_bequipment01', { p_item_id: item.id, p_locked: !item.is_locked }, item.is_locked ? '装备已解锁。' : '装备已锁定。'); });
    root.querySelector('[data-eq-action="decompose"]')?.addEventListener('click', () => confirmSingleDecompose(item));
  }

  function confirmSingleDecompose(item) {
    const warnings = [];
    if (Number(item.enhancement_level || 0) > 0) warnings.push(`该装备已强化至 +${item.enhancement_level}`);
    if (Number(item.socket_content_count || 0) > 0) warnings.push(`孔位中已有 ${item.socket_content_count} 项内容`);
    const warningText = warnings.length ? `\n警告：${warnings.join('，')}，分解后全部永久消失。` : '';
    if (!confirm(`确认分解【${item.full_name}${Number(item.enhancement_level || 0) ? ` +${item.enhancement_level}` : ''} · ${item.grade_name}】？\n将获得器源×${item.decompose_essence}。${warningText}\n操作不可撤销。`)) return;
    closeModal();
    decomposeItems([item], Number(item.decompose_essence));
  }

  async function decomposeItems(items, expectedGain) {
    if (state.disabled) { toast('装备系统当前已停用。', 'error'); return; }
    try {
      const result = await rpc('decompose_equipment_v180', { p_item_ids: items.map(item => item.id), p_request_id: uuid() });
      await refresh(true);
      toast(`分解完成：${Number(result?.decomposed_count || items.length)}件装备，获得器源×${nfmt(result?.essence_gain ?? expectedGain)}。`);
    } catch (error) {
      toast(errorText(error), 'error');
      await refresh(true);
    }
  }

  function openBatchDecompose() {
    const candidates = itemList('backpack').filter(item => !item.is_locked);
    if (!candidates.length) { toast('背包中没有可分解的未锁定装备。', 'error'); return; }
    const defaultSelected = new Set(candidates
      .filter(item => ['yellow', 'mystic'].includes(item.grade_code) && Number(item.enhancement_level || 0) === 0 && Number(item.socket_content_count || 0) === 0)
      .map(item => String(item.id)));
    const rows = candidates.map(item => `<label class="equipment-batch-row-bequipment01" style="--grade:${esc(color(item))}"><input type="checkbox" data-batch-id="${esc(item.id)}" ${defaultSelected.has(String(item.id)) ? 'checked' : ''}><span>${itemIcon(item)}</span><span><strong>${esc(itemEnhancementName(item))}：<em>${esc(item.grade_name)}</em></strong><small>${esc(item.realm_name)} · ${esc(item.main_stat_display)} · ${esc(item.socket_display)}</small></span><b>器源×${Number(item.decompose_essence)}</b></label>`).join('');
    modalHost().innerHTML = `<div class="modal-backdrop equipment-modal-backdrop-bequipment01"><section class="modal equipment-modal-bequipment01 equipment-batch-modal-bequipment01" role="dialog" aria-modal="true"><button class="modal-close-button" data-eq-close>×</button><header><span class="equipment-icon-bequipment01">解</span><div><span>批量分解 · 默认只勾选未强化、无孔位内容的黄品与玄品</span><h3>装备化源</h3></div></header><div class="equipment-batch-tools-bequipment01"><button type="button" data-batch-low>勾选安全黄玄</button><button type="button" data-batch-clear>清空</button><strong data-batch-summary></strong></div><div class="equipment-batch-list-bequipment01">${rows}</div><p>地品及以上、已强化装备及已有孔位内容的装备不会自动勾选。分解后装备、强化价值和全部孔位内容永久消失。</p><div class="equipment-modal-actions-bequipment01"><button class="danger-btn" data-batch-confirm>确认分解</button></div></section></div>`;
    const root = modalHost();
    const boxes = () => [...root.querySelectorAll('[data-batch-id]')];
    const selectedItems = () => boxes().filter(box => box.checked).map(box => candidates.find(item => String(item.id) === box.dataset.batchId)).filter(Boolean);
    const update = () => {
      const selected = selectedItems();
      const gain = selected.reduce((sum, item) => sum + Number(item.decompose_essence || 0), 0);
      root.querySelector('[data-batch-summary]').textContent = `已选 ${selected.length} 件 · 器源×${gain}`;
      return { selected, gain };
    };
    bindBackdrop(root);
    boxes().forEach(box => box.addEventListener('change', update));
    root.querySelector('[data-batch-low]').addEventListener('click', () => {
      boxes().forEach(box => {
        const item = candidates.find(row => String(row.id) === box.dataset.batchId);
        box.checked = ['yellow', 'mystic'].includes(item?.grade_code) && Number(item?.enhancement_level || 0) === 0 && Number(item?.socket_content_count || 0) === 0;
      });
      update();
    });
    root.querySelector('[data-batch-clear]').addEventListener('click', () => { boxes().forEach(box => { box.checked = false; }); update(); });
    root.querySelector('[data-batch-confirm]').addEventListener('click', () => {
      const { selected, gain } = update();
      if (!selected.length) { toast('请至少选择一件装备。', 'error'); return; }
      const high = selected.some(item => ['earth', 'heaven', 'immortal'].includes(item.grade_code));
      const enhanced = selected.some(item => Number(item.enhancement_level || 0) > 0);
      const occupied = selected.some(item => Number(item.socket_content_count || 0) > 0);
      const warnings = [high ? '包含地品或更高品级' : '', enhanced ? '包含已强化装备' : '', occupied ? '包含已有孔位内容的装备' : ''].filter(Boolean);
      const warning = warnings.length ? `警告：${warnings.join('、')}，相关内容将永久消失。\n` : '';
      if (!confirm(`${warning}确认分解 ${selected.length} 件装备，获得器源×${gain}？操作不可撤销。`)) return;
      closeModal();
      decomposeItems(selected, gain);
    });
    update();
  }

  function openMaterial() {
    const essence = Number(state.data?.materials?.essence || 0);
    const stones = Number(state.data?.materials?.spirit_stones || 0);
    modalHost().innerHTML = `<div class="modal-backdrop equipment-modal-backdrop-bequipment01"><section class="modal equipment-modal-bequipment01"><button class="modal-close-button" data-eq-close>×</button><header><span class="equipment-icon-bequipment01">源</span><div><span>装备分解与强化材料</span><h3>器源 ×${nfmt(essence)}</h3></div></header><p>器源由所有境界、所有部位的装备分解获得，全游戏通用。当前黄、玄、地、天、仙品分解分别获得${gradeDecomposeSummary()}器源，强化一次分别消耗${gradeEnhancementSummary()}器源。默认一件装备约可提供10次同品级强化尝试；分解产出可由GM即时调整。</p><dl><div><dt>当前器源</dt><dd>${nfmt(essence)}</dd></div><div><dt>当前灵石</dt><dd>${nfmt(stones)}</dd></div><div><dt>旧材料处理</dt><dd>旧“器源精粹”数量已原样继承为器源</dd></div></dl></section></div>`;
    bindBackdrop(modalHost());
  }

  function calculateNextValue(item, targetLevel, configRow) {
    const percent = item.slot_code === 'ring'
      ? Number(configRow?.ring_cumulative_percent || 0)
      : Number(configRow?.normal_cumulative_percent || 0);
    const raw = Number(item.base_main_stat_value || 0) * (1 + percent / 100);
    return item.slot_code === 'ring' ? Math.round(raw * 10000) / 10000 : Math.round(raw);
  }

  function enhancementSuccessNotice(item, feedback = null) {
    if (!feedback) return '';
    const gainedSocket = Boolean(feedback.gainedSocket);
    return `<div class="equipment-enhance-success-bequipment01" role="status"><strong>强化成功 · 已提升至 +${Number(item.enhancement_level || feedback.level || 0)}</strong><p>${esc(item.short_name || item.full_name)}已承受天命${gainedSocket ? '，并新增一个孔位' : ''}。当前数据与下一次强化预览已刷新，可继续强化。</p></div>`;
  }

  function openMaxEnhancement(item, feedback = null) {
    const currentSockets = Number(item.total_socket_capacity || item.socket_capacity || 0);
    modalHost().innerHTML = `<div class="modal-backdrop equipment-modal-backdrop-bequipment01"><section class="modal equipment-modal-bequipment01 equipment-enhance-modal-bequipment01" role="dialog" aria-modal="true"><button class="modal-close-button" data-eq-close>×</button><header style="--grade:${esc(color(item))}">${itemIcon(item)}<div><span>${esc(item.realm_name)} · ${esc(item.grade_name)} · ${esc(slotMeta[item.slot_code][1])}</span><h3>${esc(itemEnhancementName(item))} · 已满级</h3></div></header>${enhancementSuccessNotice(item, feedback)}<div class="equipment-enhance-levels-bequipment01"><div><small>当前等级</small><strong>+${Number(item.enhancement_level || 10)}</strong><span>${esc(formatMainStat(item, item.main_stat_value))}</span><em>${currentSockets}个孔位</em></div><i>✓</i><div class="next"><small>强化状态</small><strong>已满级</strong><span>该装备已达到最高强化等级</span><em>无需继续消耗器源或灵石</em></div></div><div class="equipment-modal-actions-bequipment01 equipment-enhance-actions-bequipment01"><button class="primary-btn" type="button" disabled>已强化至最高等级 +10</button><button class="ghost-btn" data-eq-close-alt>返回背包</button></div></section></div>`;
    const root = modalHost();
    bindBackdrop(root);
    root.querySelector('[data-eq-close-alt]')?.addEventListener('click', closeModal);
  }

  function openEnhancement(item, feedback = null) {
    const currentLevel = Number(item.enhancement_level || 0);
    if (currentLevel >= 10) { openMaxEnhancement(item, feedback); return; }
    const targetLevel = currentLevel + 1;
    const level = enhancementLevelConfig(targetLevel);
    if (!level || targetLevel > 10) { toast('该装备已经强化至最高等级 +10。', 'error'); return; }
    const essenceCost = Number(configuredGradeEnhancementEssence(item.grade_code) || 0);
    const essenceOwned = Number(state.data?.materials?.essence || 0);
    const stoneCost = Number(level.spirit_stone_cost || 0);
    const stonesOwned = Number(state.data?.materials?.spirit_stones || 0);
    const nextValue = calculateNextValue(item, targetLevel, level);
    const currentSockets = Number(item.total_socket_capacity || item.socket_capacity || 0);
    const nextSockets = Number(item.base_socket_capacity || gradeBaseSockets[item.grade_code] || 0) + extraSocketsAt(targetLevel);
    const percent = item.slot_code === 'ring' ? Number(level.ring_cumulative_percent || 0) : Number(level.normal_cumulative_percent || 0);
    const insufficient = essenceOwned < essenceCost || stonesOwned < stoneCost || level.enabled === false;
    const sourceText = level.probability_source === 'timed_override' ? '限时活动概率' : '基础概率';

    modalHost().innerHTML = `<div class="modal-backdrop equipment-modal-backdrop-bequipment01"><section class="modal equipment-modal-bequipment01 equipment-enhance-modal-bequipment01" role="dialog" aria-modal="true"><button class="modal-close-button" data-eq-close>×</button><header style="--grade:${esc(color(item))}">${itemIcon(item)}<div><span>${esc(item.realm_name)} · ${esc(item.grade_name)} · ${esc(slotMeta[item.slot_code][1])}</span><h3>${esc(itemEnhancementName(item))} → +${targetLevel}</h3></div></header>${enhancementSuccessNotice(item, feedback)}<div class="equipment-enhance-levels-bequipment01"><div><small>当前等级</small><strong>+${currentLevel}</strong><span>${esc(formatMainStat(item, item.main_stat_value))}</span><em>${currentSockets}个孔位</em></div><i>→</i><div class="next"><small>成功后</small><strong>+${targetLevel}</strong><span>${esc(formatMainStat(item, nextValue))}</span><em>${nextSockets}个孔位${nextSockets > currentSockets ? ` · 新增${nextSockets - currentSockets}孔` : ''}</em></div></div><dl class="equipment-enhance-costs-bequipment01"><div><dt>本级属性增加</dt><dd>基础主属性 +${item.slot_code === 'ring' ? Number(level.ring_cumulative_percent || 0) - Number((enhancementLevelConfig(targetLevel - 1) || {}).ring_cumulative_percent || 0) : Number(level.normal_increment_percent || 0)}%</dd></div><div><dt>累计强化加成</dt><dd>+${percent}%${item.slot_code === 'ring' ? '（戒指采用普通倍率的50%）' : ''}</dd></div><div><dt>本次成功率</dt><dd class="risk">${Number(level.success_percent ?? Number(level.success_rate || 0) * 100).toLocaleString('zh-CN', { maximumFractionDigits: 4 })}% · ${sourceText}</dd></div><div><dt>器源</dt><dd class="${essenceOwned < essenceCost ? 'insufficient' : ''}">${nfmt(essenceOwned)} / 消耗 ${nfmt(essenceCost)}</dd></div><div><dt>灵石</dt><dd class="${stonesOwned < stoneCost ? 'insufficient' : ''}">${nfmt(stonesOwned)} / 消耗 ${nfmt(stoneCost)}</dd></div></dl><div class="equipment-destroy-warning-bequipment01"><strong>天命有险</strong><p>强化失败后，该装备与已有强化等级将永久消失；已有的 ${Number(item.socket_content_count || 0)} 条V2.1孔位属性与等级会凝成器魂保存，供同大境界、同品级、同部位装备承接。本次器源与灵石不返还。</p></div><div class="equipment-modal-actions-bequipment01 equipment-enhance-actions-bequipment01"><button class="danger-btn fate" data-enhance-confirm ${insufficient ? 'disabled' : ''}>我命由我不由天</button><button class="ghost-btn" data-eq-close-alt>我再回去考虑考虑</button></div>${insufficient ? `<p class="equipment-insufficient-note-bequipment01">${level.enabled === false ? '该强化等级当前已停用。' : '器源或灵石不足，暂时无法强化。'}</p>` : ''}</section></div>`;
    const root = modalHost();
    bindBackdrop(root);
    root.querySelector('[data-eq-close-alt]')?.addEventListener('click', closeModal);
    root.querySelector('[data-enhance-confirm]')?.addEventListener('click', event => executeEnhancement(item, targetLevel, event.currentTarget));
  }

  async function executeEnhancement(item, targetLevel, button) {
    if (state.disabled) { toast('装备系统当前已停用。', 'error'); return; }
    button.disabled = true;
    button.textContent = '天命判定中…';
    try {
      const result = await rpc('enhance_equipment_v180', { p_item_id: item.id, p_request_id: uuid() });
      await refresh(true);
      if (Number(result?.target_level || targetLevel) >= 6) {
        window.dispatchEvent(new CustomEvent('jiuxiao:world-events-dirty', { detail: {
          source: 'equipment_enhancement',
          result: result?.enhancement_success ? 'success' : 'failure',
          targetLevel: Number(result?.target_level || targetLevel),
          worldEventId: result?.world_event_id || null
        }}));
      }
      if (result?.enhancement_success) {
        const fresh = allItems().find(row => String(row.id) === String(item.id));
        if (!fresh) { closeModal(); toast('强化已成功，但装备刷新失败，请重新打开背包确认。', 'error'); return; }
        const gainedSocket = Number(fresh.total_socket_capacity || 0) > Number(item.total_socket_capacity || 0);
        openEnhancement(fresh, { level: targetLevel, gainedSocket });
        toast(`强化成功！${item.short_name}已提升至 +${targetLevel}${gainedSocket ? '，并新增一个孔位' : ''}。`);
      } else {
        showEnhancementFailure(item, targetLevel, result);
      }
    } catch (error) {
      toast(errorText(error), 'error');
      await refresh(true);
      const current = allItems().find(row => String(row.id) === String(item.id));
      if (current) openEnhancement(current); else closeModal();
    }
  }

  function showEnhancementFailure(item, targetLevel, result) {
    modalHost().innerHTML = `<div class="modal-backdrop equipment-modal-backdrop-bequipment01"><section class="modal equipment-modal-bequipment01 equipment-result-modal-bequipment01 destroyed" role="dialog" aria-modal="true"><header><span class="equipment-result-sigil-bequipment01">劫</span><div><span>道器归墟</span><h3>强化失败 · 装备已永久消失</h3></div></header><p>【${esc(item.full_name)} +${Number(item.enhancement_level || 0)}】未能承受强化，装备已化为飞灰。${result?.socket_soul_created ? `已有 ${Number(result.socket_soul_count || 0)} 条孔位灵性凝成器魂，可由同大境界、同品级、同部位装备承接。` : '该装备没有可保存的孔位灵性。'}</p><dl><div><dt>冲击等级</dt><dd>+${targetLevel}</dd></div><div><dt>本次成功率</dt><dd>${Number(result?.success_percent || 0)}%</dd></div><div><dt>消耗器源</dt><dd>${nfmt(result?.essence_cost)}</dd></div><div><dt>消耗灵石</dt><dd>${nfmt(result?.spirit_stone_cost)}</dd></div></dl><div class="equipment-modal-actions-bequipment01"><button class="ghost-btn" data-eq-close-alt>知命而行</button></div></section></div>`;
    toast(result?.socket_soul_created ? '强化失败，装备已消失；孔位已凝成器魂保存。' : '强化失败，装备已永久消失。', 'error');
    const root = modalHost();
    root.querySelector('[data-eq-close-alt]')?.addEventListener('click', closeModal);
    root.querySelector('.equipment-modal-backdrop-bequipment01')?.addEventListener('click', event => { if (event.target === event.currentTarget) closeModal(); });
  }

  function renderAll() {
    document.getElementById('equipmentStorageShellBEquipment01')?.remove();
    document.getElementById('equipmentBackpackLauncherBEquipment01')?.remove();
    renderSpiritSlots();
    renderBackpackInline();
    renderCaveEquipmentIntoNative();
  }

  function hasEquipmentSurface() {
    return Boolean(document.getElementById('caveStorageB01') || document.getElementById('primordialSpiritRootV1'));
  }

  function refreshOrRender({ force = false } = {}) {
    if (state.data) {
      renderAll();
      if (force || Date.now() - state.lastFetch > 60000) refresh(force);
      return;
    }
    if (hasEquipmentSurface()) refresh(force);
  }

  function opportunityEquipment(payload) {
    const direct = payload?.opportunity?.last_result?.equipment;
    if (direct?.awarded) return direct;
    const rows = payload?.offline_summary?.net_result?.equipment;
    if (Array.isArray(rows)) return rows.find(row => row?.awarded) || null;
    return rows?.awarded ? rows : null;
  }

  window.addEventListener('jiuxiao:cave-rendered', () => refreshOrRender());
  window.addEventListener('jiuxiao:primordial-rendered', () => refreshOrRender());
  window.addEventListener('jiuxiao:secret-realm-claimed', () => refreshOrRender({ force: true }));
  window.addEventListener('jiuxiao:opportunity-settled', event => {
    const payload = event?.detail || null;
    const equipment = opportunityEquipment(payload);
    const itemId = equipment?.item?.id || equipment?.item_id || null;
    if (equipment?.awarded && itemId !== state.lastOpportunityId) {
      state.lastOpportunityId = itemId;
      toast(`机缘得宝：${equipment.item?.short_name || '装备'}·${equipment.item?.grade_name || ''}`);
    }
    if (Number(payload?.events_resolved || 0) > 0 || equipment?.awarded) refresh(true);
  });
  document.addEventListener('DOMContentLoaded', () => refreshOrRender({ force: true }));
  window.addEventListener('focus', () => { if (hasEquipmentSurface() && Date.now() - state.lastFetch > 60000) refresh(true); });
  window.addEventListener('pageshow', event => { if (event.persisted) refreshOrRender({ force: true }); });

  window.B_EQUIPMENT01 = { refresh, render: renderAll, openBackpack, getItem: id => allItems().find(row => String(row.id) === String(id)) || null, version: VERSION };
})();
