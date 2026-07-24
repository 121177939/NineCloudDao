(() => {
  'use strict';

  const config = window.GAME_CONFIG || {};
  const SUPABASE_URL = String(config.supabaseUrl || '').replace(/\/+$/, '');
  const API_KEY = String(config.supabasePublishableKey || '');
  const PROJECT_REF = (() => { try { return new URL(SUPABASE_URL).hostname.split('.')[0]; } catch { return 'unknown'; } })();
  const SESSION_KEY = `nine_cloud_dao_session_${PROJECT_REF}_v1`;
  const DEVICE_KEY = `nine_cloud_dao_device_${PROJECT_REF}_v1`;

  function createUuid() {
    if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, char => {
      const value = Math.random() * 16 | 0;
      const result = char === 'x' ? value : (value & 0x3 | 0x8);
      return result.toString(16);
    });
  }

  function getOrCreateDeviceSessionId() {
    const existing = localStorage.getItem(DEVICE_KEY);
    if (existing && /^[0-9a-f-]{36}$/i.test(existing)) return existing;
    const created = createUuid();
    localStorage.setItem(DEVICE_KEY, created);
    return created;
  }

  const GAME_SESSION_ID = getOrCreateDeviceSessionId();

  const app = document.getElementById('app');
  const accountArea = document.getElementById('accountArea');
  const toast = document.getElementById('toast');
  const modalRoot = document.getElementById('modalRoot');
  const versionText = document.getElementById('versionText');
  versionText.textContent = config.version || 'unknown';
  const projectRefText = document.getElementById('projectRefText');
  if (projectRefText) projectRefText.textContent = PROJECT_REF;

  let desktopScaleFrame = 0;
  function updateDesktopUiScale() {
    const viewportWidth = Math.max(document.documentElement.clientWidth || 0, window.innerWidth || 0);
    const baseWidth = 760;
    let scale = 1;
    if (viewportWidth >= 1024) {
      scale = Math.min(1.5, Math.max(1, 1 + ((viewportWidth - 1024) / 896) * 0.5));
    }
    document.documentElement.style.setProperty('--desktop-ui-scale', scale.toFixed(4));
    document.documentElement.style.setProperty('--desktop-stage-width', `${Math.round(baseWidth * scale)}px`);
  }
  function scheduleDesktopUiScale() {
    cancelAnimationFrame(desktopScaleFrame);
    desktopScaleFrame = requestAnimationFrame(updateDesktopUiScale);
  }
  updateDesktopUiScale();
  window.addEventListener('resize', scheduleDesktopUiScale, { passive: true });

  const state = {
    authMode: 'login',
    session: null,
    user: null,
    profile: null,
    character: null,
    details: null,
    history: [],
    cultivationStatus: null,
    cultivationTicker: null,
    cultivationSyncTimer: null,
    cultivationSyncing: false,
    liveCultivationBase: 0,
    liveCultivationStartedAt: 0,
    breakthroughStatus: null,
    opportunityStatus: null,
    opportunityPollTimer: null,
    opportunityCountdownTimer: null,
    opportunitySyncing: false,
    supplyStatus: null,
    supplyCountdownTimer: null,
    techniqueSystem: null,
    techniqueSyncTimer: null,
    techniqueSyncing: false,
    timeStatus: null,
    timeStatusStartedAt: 0,
    timeSyncing: false,
    deathHandled: false,
    gameSessionActive: false,
    gameSessionHeartbeatTimer: null,
    sessionReplacementHandled: false,
    activeMobileTab: 'cultivation'
  };

  function escapeHtml(value) {
    return String(value ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#039;');
  }

  function showToast(message, type = 'success') {
    toast.textContent = message;
    toast.className = `toast show ${type}`;
    clearTimeout(showToast.timer);
    showToast.timer = setTimeout(() => {
      toast.className = 'toast';
    }, 3800);
  }

  function setBusy(button, busy, text = '处理中……') {
    if (!button) return;
    if (busy) {
      button.dataset.oldText = button.textContent;
      button.textContent = text;
      button.disabled = true;
    } else {
      button.textContent = button.dataset.oldText || button.textContent;
      delete button.dataset.oldText;
      button.disabled = false;
    }
  }

  function translateError(error) {
    const raw = `${error?.message || error?.error_description || error?.msg || error || '未知错误'}`;
    const lower = raw.toLowerCase();
    if (lower.includes('invalid login credentials')) return '邮箱或密码错误。';
    if (lower.includes('email not confirmed')) return '邮箱尚未验证，请先打开验证邮件。';
    if (lower.includes('user already registered')) return '该邮箱已经注册，请直接登录。';
    if (lower.includes('password should be at least')) return '密码长度不足，请至少输入 6 位。';
    if (lower.includes('email rate limit exceeded')) return '注册邮件发送过于频繁，请稍后再试。';
    if (lower.includes('signups not allowed')) return `当前云端项目（${PROJECT_REF}）禁止注册。请确认游戏连接的是你刚开启注册的 Supabase 项目。`;
    if (raw.includes('ACTIVE_CHARACTER_ALREADY_EXISTS')) return '这个账号已经拥有一位在世角色。';
    if (raw.includes('DUPLICATE_CHARACTER_NAME')) return '这个角色姓名已经被其他修士使用，请换一个名字。';
    if (raw.includes('EXISTING_DUPLICATE_CHARACTER_NAMES')) return '数据库中已经存在重名角色，请先处理旧数据再启用唯一姓名。';
    if (raw.includes('INVALID_CHARACTER_NAME')) return '角色姓名需要 2—12 个字符。';
    if (raw.includes('GAME_SESSION_REPLACED')) return '该账号已在另一台设备登录，本设备已退出。';
    if (raw.includes('GAME_SESSION_REQUIRED')) return '游戏会话尚未建立，请重新登录。';
    if (raw.includes('INVALID_GENDER')) return '性别参数无效。';
    if (raw.includes('AUTH_REQUIRED')) return '登录状态已失效，请重新登录。';
    if (raw.includes('SEED_DATA_INCOMPLETE')) return '数据库初始数据不完整，请检查阶段1部署。';
    if (raw.includes('INSUFFICIENT_CULTIVATION')) return '当前修为尚未达到突破门槛。';
    if (raw.includes('MAXIMUM_REALM_REACHED')) return '你已经抵达当前版本可用的最高境界。';
    if (raw.includes('OPPORTUNITY_EXPIRED')) return '这次机缘已经消散，天道会重新推演。';
    if (raw.includes('OPPORTUNITY_ALREADY_RESOLVED')) return '这次机缘已经选择过了。';
    if (raw.includes('INVALID_OPPORTUNITY_CHOICE')) return '机缘选择无效，请重新读取。';
    if (raw.includes('OPPORTUNITY_CONTENT_MISSING')) return '机缘内容尚未部署，请执行 V0.4 数据库升级。';
    if (raw.includes('SUPPLY_NOT_READY')) return '洞府补给尚未成熟，请等待倒计时结束。';
    if (raw.includes('INVALID_LEGACY_CHOICE')) return '道统继承选择无效，请重新选择。';
    if (raw.includes('NO_DEAD_CHARACTER_FOR_REINCARNATION')) return '没有可转世的陨落角色。';
    if (raw.includes('CHARACTER_ALREADY_REINCARNATED')) return '这位角色的道统已经续接，不能重复转世。';
    if (raw.includes('REINCARNATION_CHARACTER_CREATION_FAILED')) return '转世角色创建失败，请不要重复提交并联系维护。';
    if (raw.includes('WORLD_TIME_NOT_INITIALIZED')) return '仙历时间尚未初始化，请先执行 V0.7.0 数据库升级。';
    if (raw.includes('WORLD_NOT_FOUND')) return '九霄界配置缺失，请检查数据库世界数据。';
    if (raw.includes('INVENTORY_ITEM_NOT_FOUND')) return '储物不存在或不属于当前角色。';
    if (raw.includes('ITEM_QUANTITY_EMPTY')) return '该物品数量不足。';
    if (raw.includes('ITEM_NOT_USABLE')) return '该物品当前不能直接使用。';
    if (raw.includes('ITEM_EFFECT_INVALID')) return '物品效果配置不完整，请检查 V0.6 数据库升级。';
    if (raw.includes('TECHNIQUE_NOT_FOUND')) return '没有找到这门功法。';
    if (raw.includes('SUPPORT_SLOTS_FULL')) return '辅修槽已满，最多同时运转两门辅修功法。';
    if (raw.includes('MAIN_TECHNIQUE_REQUIRED')) return '主修功法不能卸下，请直接切换另一门主修功法。';
    if (raw.includes('TECHNIQUE_MAX_LEVEL')) return '这门功法已经修至当前品质允许的最高层。';
    if (raw.includes('TECHNIQUE_PROFICIENCY_REQUIRED')) return '功法熟练与传承点合计不足100，继续运转或重复获得后再精进。';
    if (raw.includes('INVALID_TECHNIQUE_SLOT')) return '功法槽位无效，请重新选择。';
    if (raw.includes('MAIN_TECHNIQUE_SLOT_ONLY')) return '主修功法只能放入主修槽。';
    if (raw.includes('SUPPORT_TECHNIQUE_SLOT_ONLY')) return '这门功法只能放入辅修槽。';
    if (raw.includes('INSUFFICIENT_SPIRIT_STONES')) return '灵石不足，无法提升功法。';
    if (lower.includes('could not find the function') || raw.includes('PGRST202')) return '数据库功能尚未升级到当前版本，请执行游戏包内最新 SQL。';
    if (raw.includes('Failed to fetch')) return '无法连接云端数据库，请检查网络或 Supabase 项目状态。';
    return raw;
  }

  async function parseResponse(response) {
    const text = await response.text();
    let data = null;
    if (text) {
      try { data = JSON.parse(text); } catch { data = text; }
    }
    if (!response.ok) {
      const message = data?.msg || data?.message || data?.error_description || data?.error || `HTTP ${response.status}`;
      const error = new Error(message);
      error.status = response.status;
      error.payload = data;
      throw error;
    }
    return data;
  }

  async function authFetch(path, options = {}) {
    const headers = {
      apikey: API_KEY,
      'Content-Type': 'application/json',
      ...(options.headers || {})
    };
    if (options.accessToken) headers.Authorization = `Bearer ${options.accessToken}`;
    const response = await fetch(`${SUPABASE_URL}/auth/v1${path}`, {
      method: options.method || 'GET',
      headers,
      body: options.body ? JSON.stringify(options.body) : undefined
    });
    return parseResponse(response);
  }

  function saveSession(session) {
    if (!session?.access_token) return;
    const expiresAt = session.expires_at || Math.floor(Date.now() / 1000) + Number(session.expires_in || 3600);
    state.session = { ...session, expires_at: expiresAt };
    localStorage.setItem(SESSION_KEY, JSON.stringify(state.session));
  }

  function stopCultivationLoop() {
    if (state.cultivationTicker) clearInterval(state.cultivationTicker);
    if (state.cultivationSyncTimer) clearInterval(state.cultivationSyncTimer);
    if (state.opportunityPollTimer) clearInterval(state.opportunityPollTimer);
    if (state.opportunityCountdownTimer) clearInterval(state.opportunityCountdownTimer);
    if (state.supplyCountdownTimer) clearInterval(state.supplyCountdownTimer);
    if (state.techniqueSyncTimer) clearInterval(state.techniqueSyncTimer);
    if (state.gameSessionHeartbeatTimer) clearInterval(state.gameSessionHeartbeatTimer);
    state.cultivationTicker = null;
    state.cultivationSyncTimer = null;
    state.opportunityPollTimer = null;
    state.opportunityCountdownTimer = null;
    state.supplyCountdownTimer = null;
    state.techniqueSyncTimer = null;
    state.gameSessionHeartbeatTimer = null;
    state.cultivationSyncing = false;
    state.opportunitySyncing = false;
    state.techniqueSyncing = false;
  }

  function clearSession() {
    stopCultivationLoop();
    state.session = null;
    state.user = null;
    state.profile = null;
    state.character = null;
    state.details = null;
    state.history = [];
    state.cultivationStatus = null;
    state.liveCultivationBase = 0;
    state.liveCultivationStartedAt = 0;
    state.breakthroughStatus = null;
    state.opportunityStatus = null;
    state.opportunitySyncing = false;
    state.supplyStatus = null;
    state.techniqueSystem = null;
    state.timeStatus = null;
    state.timeStatusStartedAt = 0;
    state.timeSyncing = false;
    state.deathHandled = false;
    state.gameSessionActive = false;
    state.activeMobileTab = 'cultivation';
    localStorage.removeItem(SESSION_KEY);
  }

  function loadStoredSession() {
    try {
      const raw = localStorage.getItem(SESSION_KEY);
      if (raw) state.session = JSON.parse(raw);
    } catch {
      clearSession();
    }
  }

  function importSessionFromHash() {
    const hash = window.location.hash.startsWith('#') ? window.location.hash.slice(1) : '';
    if (!hash) return false;
    const params = new URLSearchParams(hash);
    const accessToken = params.get('access_token');
    if (!accessToken) return false;
    saveSession({
      access_token: accessToken,
      refresh_token: params.get('refresh_token'),
      expires_in: Number(params.get('expires_in') || 3600),
      token_type: params.get('token_type') || 'bearer'
    });
    history.replaceState(null, document.title, window.location.pathname + window.location.search);
    return true;
  }

  async function ensureSession() {
    if (!state.session?.access_token) return null;
    const expiresAt = Number(state.session.expires_at || 0);
    if (expiresAt > Math.floor(Date.now() / 1000) + 60) return state.session;
    if (!state.session.refresh_token) {
      clearSession();
      return null;
    }
    try {
      const refreshed = await authFetch('/token?grant_type=refresh_token', {
        method: 'POST',
        body: { refresh_token: state.session.refresh_token }
      });
      saveSession(refreshed);
      return state.session;
    } catch {
      clearSession();
      return null;
    }
  }

  async function getCurrentUser() {
    const session = await ensureSession();
    if (!session) return null;
    return authFetch('/user', { accessToken: session.access_token });
  }

  async function restFetch(tableOrPath, options = {}) {
    const session = await ensureSession();
    if (!session) throw new Error('AUTH_REQUIRED');
    const url = new URL(`${SUPABASE_URL}/rest/v1/${tableOrPath}`);
    Object.entries(options.query || {}).forEach(([key, value]) => {
      if (value !== undefined && value !== null) url.searchParams.set(key, value);
    });
    const headers = {
      apikey: API_KEY,
      Authorization: `Bearer ${session.access_token}`,
      Accept: 'application/json',
      'X-Game-Session-Id': GAME_SESSION_ID,
      ...(options.headers || {})
    };
    if (options.body !== undefined) headers['Content-Type'] = 'application/json';
    const response = await fetch(url.toString(), {
      method: options.method || 'GET',
      headers,
      body: options.body !== undefined ? JSON.stringify(options.body) : undefined
    });
    if (response.status === 401 && state.session?.refresh_token && !options._retried) {
      state.session.expires_at = 0;
      await ensureSession();
      return restFetch(tableOrPath, { ...options, _retried: true });
    }
    try {
      return await parseResponse(response);
    } catch (error) {
      const raw = String(error?.message || '');
      if (raw.includes('GAME_SESSION_REPLACED') || raw.includes('GAME_SESSION_REQUIRED')) {
        setTimeout(() => handleGameSessionReplaced(), 0);
      }
      throw error;
    }
  }

  async function signUp(email, password, displayName) {
    return authFetch('/signup', {
      method: 'POST',
      body: {
        email,
        password,
        data: { display_name: displayName }
      }
    });
  }

  async function signIn(email, password) {
    return authFetch('/token?grant_type=password', {
      method: 'POST',
      body: { email, password }
    });
  }

  async function signOut() {
    try {
      if (state.session?.access_token && state.gameSessionActive) {
        await rpcReleaseGameSession();
      }
    } catch {
      // 会话释放失败不阻止本地退出。
    }
    try {
      if (state.session?.access_token) {
        await authFetch('/logout', { method: 'POST', accessToken: state.session.access_token });
      }
    } catch {
      // 即使远程退出失败，也清理本地会话。
    }
    clearSession();
    state.sessionReplacementHandled = false;
    renderAuth();
  }

  function deviceLabel() {
    const platform = navigator.userAgentData?.platform || navigator.platform || '未知设备';
    const viewport = `${Math.max(0, window.screen?.width || 0)}×${Math.max(0, window.screen?.height || 0)}`;
    return `${platform} · ${viewport}`.slice(0, 120);
  }

  async function rpcClaimGameSession() {
    const result = await restFetch('rpc/claim_game_session_v1', {
      method: 'POST',
      body: { p_session_id: GAME_SESSION_ID, p_device_label: deviceLabel() }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcHeartbeatGameSession() {
    const result = await restFetch('rpc/heartbeat_game_session_v1', {
      method: 'POST',
      body: { p_session_id: GAME_SESSION_ID }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcReleaseGameSession() {
    const result = await restFetch('rpc/release_game_session_v1', {
      method: 'POST',
      body: { p_session_id: GAME_SESSION_ID }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  function handleGameSessionReplaced() {
    if (state.sessionReplacementHandled) return;
    state.sessionReplacementHandled = true;
    clearSession();
    accountArea.innerHTML = '<span>会话已退出</span>';
    app.innerHTML = `
      <section class="notice-card">
        <div class="notice-icon">!</div>
        <h2>账号已在其他设备登录</h2>
        <p>为了保护云端角色，同一个账号只允许一台设备在线。若要在本设备继续，请重新登录；重新登录后会自动退出另一台设备。</p>
        <button id="sessionReloginBtn" class="primary-btn" type="button">重新登录</button>
      </section>
    `;
    document.getElementById('sessionReloginBtn')?.addEventListener('click', () => {
      state.sessionReplacementHandled = false;
      state.authMode = 'login';
      renderAuth();
    });
  }

  async function activateGameSession(takeover = false) {
    if (state.gameSessionActive) return true;
    let status = null;
    if (takeover) {
      status = await rpcClaimGameSession();
    } else {
      status = await rpcHeartbeatGameSession();
      if (status?.status === 'missing') status = await rpcClaimGameSession();
    }
    if (status?.status === 'replaced') {
      handleGameSessionReplaced();
      throw new Error('GAME_SESSION_REPLACED');
    }
    state.gameSessionActive = true;
    state.sessionReplacementHandled = false;
    startGameSessionHeartbeat();
    return true;
  }

  function startGameSessionHeartbeat() {
    if (state.gameSessionHeartbeatTimer) clearInterval(state.gameSessionHeartbeatTimer);
    state.gameSessionHeartbeatTimer = setInterval(async () => {
      if (!state.session?.access_token || !state.gameSessionActive) return;
      try {
        const status = await rpcHeartbeatGameSession();
        if (status?.status !== 'active') handleGameSessionReplaced();
      } catch (error) {
        const raw = String(error?.message || '');
        if (raw.includes('GAME_SESSION_REPLACED') || raw.includes('GAME_SESSION_REQUIRED')) {
          handleGameSessionReplaced();
        }
      }
    }, 5000);
  }

  async function rpcCreateCharacter(name, gender) {
    return restFetch('rpc/create_character_v1', {
      method: 'POST',
      body: { p_name: name, p_gender: gender }
    });
  }

  async function rpcClaimCultivation() {
    const result = await restFetch('rpc/claim_cultivation_v1', {
      method: 'POST',
      body: {}
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcGetGameTime() {
    const result = await restFetch('rpc/get_game_time_v1', {
      method: 'POST',
      body: {}
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcSettleCharacterTime() {
    const result = await restFetch('rpc/settle_character_time_v1', {
      method: 'POST',
      body: {}
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcReincarnateCharacter(name, gender, legacyChoice) {
    const result = await restFetch('rpc/reincarnate_character_v1', {
      method: 'POST',
      body: {
        p_name: name,
        p_gender: gender,
        p_legacy_choice: legacyChoice
      }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcGetOpportunity() {
    const result = await restFetch('rpc/get_opportunity_v1', {
      method: 'POST',
      body: {}
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcResolveOpportunity(opportunityId, choiceKey) {
    const result = await restFetch('rpc/resolve_opportunity_v1', {
      method: 'POST',
      body: { p_opportunity_id: opportunityId, p_choice_key: choiceKey }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcGetBreakthroughStatus() {
    const result = await restFetch('rpc/get_breakthrough_status_v1', {
      method: 'POST',
      body: {}
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcAttemptBreakthrough() {
    const result = await restFetch('rpc/attempt_breakthrough_v1', {
      method: 'POST',
      body: {}
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcGetDailySupplyStatus() {
    const result = await restFetch('rpc/get_daily_supply_status_v1', {
      method: 'POST',
      body: {}
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcClaimDailySupply() {
    const result = await restFetch('rpc/claim_daily_supply_v1', {
      method: 'POST',
      body: {}
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcUseInventoryItem(inventoryId) {
    const result = await restFetch('rpc/use_inventory_item_v1', {
      method: 'POST',
      body: { p_inventory_id: inventoryId }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcSetTechniqueEquipped(characterTechniqueId, equipped) {
    const result = await restFetch('rpc/set_technique_equipped_v1', {
      method: 'POST',
      body: {
        p_character_technique_id: characterTechniqueId,
        p_equipped: Boolean(equipped)
      }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcUpgradeTechnique(characterTechniqueId) {
    const result = await restFetch('rpc/upgrade_technique_v1', {
      method: 'POST',
      body: { p_character_technique_id: characterTechniqueId }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcGetTechniqueSystemV2() {
    const result = await restFetch('rpc/get_technique_system_v2', {
      method: 'POST',
      body: {}
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcSetTechniqueSlotV2(characterTechniqueId, targetSlot) {
    const result = await restFetch('rpc/set_technique_slot_v2', {
      method: 'POST',
      body: {
        p_character_technique_id: characterTechniqueId,
        p_target_slot: targetSlot
      }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcUpgradeTechniqueV2(characterTechniqueId) {
    const result = await restFetch('rpc/upgrade_technique_v2', {
      method: 'POST',
      body: { p_character_technique_id: characterTechniqueId }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function getOne(table, query) {
    const rows = await restFetch(table, { query: { ...query, limit: '1' } });
    return Array.isArray(rows) ? rows[0] || null : null;
  }

  async function loadProfile() {
    return getOne('profiles', {
      select: 'id,display_name,account_status,preferred_language,created_at',
      id: `eq.${state.user.id}`
    });
  }

  async function loadCharacterBundle() {
    const character = await getOne('player_characters', {
      select: 'id,user_id,world_id,lineage_id,generation_number,name,gender,birth_year,age,realm_stage_id,cultivation,lifespan_total,lifespan_used,comprehension,luck,mindset,karma,adversity,health_status,status,created_at',
      status: 'in.(active,secluded,missing,dead)',
      order: 'created_at.desc'
    });
    if (!character) return null;

    const [world, stage, rootLink, fateLink, historyRows] = await Promise.all([
      getOne('game_worlds', {
        select: 'id,code,name,current_year,era_name,spiritual_qi_level,heaven_state',
        id: `eq.${character.world_id}`
      }),
      getOne('realm_stages', {
        select: 'id,realm_id,minor_level,stage_name,cultivation_required,breakthrough_base_rate,lifespan_bonus',
        id: `eq.${character.realm_stage_id}`
      }),
      getOne('character_spirit_roots', {
        select: 'character_id,spirit_root_id,is_primary,awakened_year',
        character_id: `eq.${character.id}`,
        is_primary: 'eq.true'
      }),
      getOne('character_fates', {
        select: 'character_id,fate_id,acquired_year,source,is_active',
        character_id: `eq.${character.id}`,
        is_active: 'eq.true',
        order: 'created_at.asc'
      }),
      restFetch('history_logs', {
        query: {
          select: 'id,world_year,event_type,title,content,importance,created_at',
          scope_type: 'eq.character',
          scope_id: `eq.${character.id}`,
          order: 'world_year.desc,created_at.desc',
          limit: '100'
        }
      })
    ]);

    const [realm, spiritRoot, fate, cultivationState, techniqueLinks, cultivationEffects, inventoryLinks] = await Promise.all([
      stage ? getOne('realms', {
        select: 'id,code,name,major_order,max_minor_level,base_lifespan,description',
        id: `eq.${stage.realm_id}`
      }) : null,
      rootLink ? getOne('spirit_roots', {
        select: 'id,code,name,rarity,cultivation_multiplier,event_luck_bonus,description',
        id: `eq.${rootLink.spirit_root_id}`
      }) : null,
      fateLink ? getOne('fates', {
        select: 'id,code,name,rarity,description,modifiers',
        id: `eq.${fateLink.fate_id}`
      }) : null,
      getOne('character_cultivation_state', {
        select: 'character_id,base_rate_per_second,last_claim_at,fractional_remainder,total_cultivation_seconds,updated_at',
        character_id: `eq.${character.id}`
      }),
      restFetch('character_techniques', {
        query: {
          select: 'id,character_id,technique_id,level,proficiency,is_equipped,slot_type,learned_year,acquisition_count,mastery_points,equipped_slot,last_practiced_at',
          character_id: `eq.${character.id}`,
          order: 'is_equipped.desc,created_at.asc'
        }
      }),
      restFetch('character_cultivation_effects', {
        query: {
          select: 'id,display_name,source_type,source_key,flat_rate_per_second,multiplier_bonus,starts_at,expires_at,is_active,metadata',
          character_id: `eq.${character.id}`,
          is_active: 'eq.true',
          order: 'created_at.asc'
        }
      }),
      restFetch('character_inventory', {
        query: {
          select: 'id,character_id,item_definition_id,quantity,is_bound,item_instance,acquired_year',
          character_id: `eq.${character.id}`,
          quantity: 'gt.0',
          order: 'created_at.asc'
        }
      })
    ]);

    const techniqueIds = (Array.isArray(techniqueLinks) ? techniqueLinks : []).map(row => row.technique_id);
    let techniqueDefinitions = [];
    if (techniqueIds.length) {
      techniqueDefinitions = await restFetch('techniques', {
        query: {
          select: 'id,code,name,category,grade,element,fixed_effects,description',
          id: `in.(${techniqueIds.join(',')})`
        }
      });
    }
    const techniqueMap = new Map((Array.isArray(techniqueDefinitions) ? techniqueDefinitions : []).map(row => [row.id, row]));
    const techniques = (Array.isArray(techniqueLinks) ? techniqueLinks : []).map(link => ({
      ...link,
      definition: techniqueMap.get(link.technique_id) || null
    }));

    const itemIds = (Array.isArray(inventoryLinks) ? inventoryLinks : []).map(row => row.item_definition_id);
    let itemDefinitions = [];
    if (itemIds.length) {
      itemDefinitions = await restFetch('item_definitions', {
        query: {
          select: 'id,code,name,category,rarity,stack_limit,effects,description',
          id: `in.(${itemIds.join(',')})`
        }
      });
    }
    const itemMap = new Map((Array.isArray(itemDefinitions) ? itemDefinitions : []).map(row => [row.id, row]));
    const inventory = (Array.isArray(inventoryLinks) ? inventoryLinks : []).map(link => ({
      ...link,
      definition: itemMap.get(link.item_definition_id) || null
    })).filter(row => row.definition && Number(row.quantity || 0) > 0);

    return {
      character,
      world,
      stage,
      realm,
      spiritRoot,
      fate,
      cultivationState,
      techniques,
      inventory,
      cultivationEffects: Array.isArray(cultivationEffects) ? cultivationEffects : [],
      history: Array.isArray(historyRows) ? historyRows : []
    };
  }

  function renderAccount() {
    if (!state.user) {
      accountArea.innerHTML = '<span>仙门未启</span>';
      return;
    }
    const label = state.profile?.display_name || state.user.email || '修士';
    accountArea.innerHTML = `
      <span>${escapeHtml(label)}</span>
      <button id="logoutBtn" class="ghost-btn" type="button">退出</button>
    `;
    document.getElementById('logoutBtn')?.addEventListener('click', signOut);
  }

  function renderAuth() {
    state.user = null;
    renderAccount();
    const isLogin = state.authMode === 'login';
    app.innerHTML = `
      <section class="hero-grid">
        <article class="hero-copy">
          <span class="eyebrow">东方文字修仙人生模拟</span>
          <h1>凡人问道<br>百年一梦</h1>
          <p>从一介凡人开始，在灵根、命格、机缘与因果中走出自己的仙途。你的每一次选择，都会被九霄界记入史书。</p>
          <div class="world-note">
            <div><span>世界</span><strong>九霄界</strong></div>
            <div><span>时序</span><strong>现实1日 · 仙历12年</strong></div>
            <div><span>存档</span><strong>云端账号</strong></div>
          </div>
        </article>

        <section class="auth-panel" aria-label="账号入口">
          <div class="tabs">
            <button class="tab ${isLogin ? 'active' : ''}" id="loginTab" type="button">登录仙籍</button>
            <button class="tab ${!isLogin ? 'active' : ''}" id="registerTab" type="button">注册仙籍</button>
          </div>
          ${isLogin ? loginFormHtml() : registerFormHtml()}
        </section>
      </section>
    `;
    document.getElementById('loginTab').addEventListener('click', () => { state.authMode = 'login'; renderAuth(); });
    document.getElementById('registerTab').addEventListener('click', () => { state.authMode = 'register'; renderAuth(); });
    if (isLogin) bindLoginForm(); else bindRegisterForm();
  }

  function loginFormHtml() {
    return `
      <form id="loginForm" class="form-stack">
        <div class="field">
          <label for="loginEmail">邮箱</label>
          <input id="loginEmail" type="email" autocomplete="email" required placeholder="name@example.com">
        </div>
        <div class="field">
          <label for="loginPassword">密码</label>
          <input id="loginPassword" type="password" autocomplete="current-password" required minlength="6" placeholder="至少 6 位">
        </div>
        <div id="authError" class="form-error"></div>
        <button id="loginSubmit" class="primary-btn full" type="submit">踏入仙门</button>
        <p class="field-hint">账号与角色均保存到你的 Supabase 云端数据库。</p>
      </form>
    `;
  }

  function registerFormHtml() {
    return `
      <form id="registerForm" class="form-stack">
        <div class="field">
          <label for="registerName">称呼</label>
          <input id="registerName" type="text" autocomplete="nickname" maxlength="24" required placeholder="例如：青玄">
        </div>
        <div class="field">
          <label for="registerEmail">邮箱</label>
          <input id="registerEmail" type="email" autocomplete="email" required placeholder="用于登录与找回账号">
        </div>
        <div class="field">
          <label for="registerPassword">密码</label>
          <input id="registerPassword" type="password" autocomplete="new-password" required minlength="6" placeholder="至少 6 位">
        </div>
        <div class="field">
          <label for="registerPassword2">确认密码</label>
          <input id="registerPassword2" type="password" autocomplete="new-password" required minlength="6" placeholder="再次输入密码">
        </div>
        <div id="authError" class="form-error"></div>
        <button id="registerSubmit" class="primary-btn full" type="submit">登记仙籍</button>
        <p class="field-hint">注册即创建云端玩家档案。若项目启用了邮箱确认，需要先打开验证邮件。</p>
      </form>
    `;
  }

  function showFormError(message) {
    const box = document.getElementById('authError') || document.getElementById('createError');
    if (!box) return;
    box.textContent = message;
    box.classList.add('show');
  }

  function bindLoginForm() {
    document.getElementById('loginForm').addEventListener('submit', async (event) => {
      event.preventDefault();
      const button = document.getElementById('loginSubmit');
      setBusy(button, true, '正在开启仙门……');
      try {
        const result = await signIn(
          document.getElementById('loginEmail').value.trim(),
          document.getElementById('loginPassword').value
        );
        saveSession(result);
        await activateGameSession(true);
        showToast('登录成功，正在读取云端命书。');
        await enterGame();
      } catch (error) {
        showFormError(translateError(error));
      } finally {
        setBusy(button, false);
      }
    });
  }

  function bindRegisterForm() {
    document.getElementById('registerForm').addEventListener('submit', async (event) => {
      event.preventDefault();
      const button = document.getElementById('registerSubmit');
      const password = document.getElementById('registerPassword').value;
      const password2 = document.getElementById('registerPassword2').value;
      if (password !== password2) {
        showFormError('两次输入的密码不一致。');
        return;
      }
      setBusy(button, true, '正在登记仙籍……');
      try {
        const email = document.getElementById('registerEmail').value.trim();
        const result = await signUp(email, password, document.getElementById('registerName').value.trim());
        if (result?.access_token) {
          saveSession(result);
          await activateGameSession(true);
          showToast('注册成功，仙籍已经建立。');
          await enterGame();
        } else {
          renderEmailConfirmation(email);
        }
      } catch (error) {
        showFormError(translateError(error));
      } finally {
        setBusy(button, false);
      }
    });
  }

  function renderEmailConfirmation(email) {
    accountArea.innerHTML = '<span>等待验证</span>';
    app.innerHTML = `
      <section class="notice-card">
        <div class="notice-icon">✉</div>
        <h2>验证仙籍邮箱</h2>
        <p>验证邮件已发送到 <strong>${escapeHtml(email)}</strong>。打开邮件完成验证后，回到这里登录，即可创建角色。</p>
        <button id="backLogin" class="primary-btn" type="button">返回登录</button>
      </section>
    `;
    document.getElementById('backLogin').addEventListener('click', () => {
      state.authMode = 'login';
      renderAuth();
    });
  }

  function renderCreateCharacter() {
    renderAccount();
    const currentWorldYear = Number(state.timeStatus?.current_world_year || 1024);
    app.innerHTML = `
      <section class="create-layout">
        <article class="lore-panel">
          <span class="eyebrow">仙历 ${escapeHtml(currentWorldYear)} 年 · 现实1日=仙历12年</span>
          <h2>凡尘初生</h2>
          <p>九霄界灵潮渐起，山野之间异象频现。你生于凡尘，尚不知自己的灵根与命格。今日，仙门测灵石第一次为你亮起。</p>
          <div class="lore-list">
            <div class="lore-item"><b>一</b><span>每个账号在同一世界只能拥有一位在世角色。</span></div>
            <div class="lore-item"><b>二</b><span>灵根与命格由天道在服务器端随机判定，无法篡改。</span></div>
            <div class="lore-item"><b>三</b><span>角色一生会被写入命书，未来可留下道统与轮回传承。</span></div>
          </div>
        </article>

        <section class="create-panel">
          <span class="eyebrow">创建角色</span>
          <h2>请留下你的凡尘姓名</h2>
          <form id="createForm" class="form-stack">
            <div class="field">
              <label for="characterName">角色姓名</label>
              <input id="characterName" type="text" minlength="2" maxlength="12" required placeholder="2—12 个字符">
            </div>
            <div class="field">
              <label>性别</label>
              <div class="gender-grid">
                <div class="gender-option"><input id="genderMale" name="gender" type="radio" value="male"><label for="genderMale">男</label></div>
                <div class="gender-option"><input id="genderFemale" name="gender" type="radio" value="female"><label for="genderFemale">女</label></div>
                <div class="gender-option"><input id="genderUnknown" name="gender" type="radio" value="unspecified" checked><label for="genderUnknown">不详</label></div>
              </div>
            </div>
            <div id="createError" class="form-error"></div>
            <button id="createSubmit" class="primary-btn full" type="submit">叩问天机 · 踏入此生</button>
          </form>
        </section>
      </section>
    `;

    document.getElementById('createForm').addEventListener('submit', async (event) => {
      event.preventDefault();
      const button = document.getElementById('createSubmit');
      setBusy(button, true, '天道正在推演……');
      try {
        const name = document.getElementById('characterName').value.trim();
        const gender = document.querySelector('input[name="gender"]:checked')?.value || 'unspecified';
        const result = await rpcCreateCharacter(name, gender);
        const birth = Array.isArray(result) ? result[0] : result;
        showBirthModal(name, birth?.spirit_root_name || '未知灵根', birth?.fate_name || '未知命格');
      } catch (error) {
        const box = document.getElementById('createError');
        box.textContent = translateError(error);
        box.classList.add('show');
      } finally {
        setBusy(button, false);
      }
    });
  }

  function showBirthModal(name, spiritRoot, fate) {
    modalRoot.innerHTML = `
      <div class="modal-backdrop">
        <section class="modal" role="dialog" aria-modal="true" aria-labelledby="birthTitle">
          <div class="modal-seal">命</div>
          <h2 id="birthTitle">${escapeHtml(name)}，此生已定</h2>
          <p>测灵石光华流转，天道在九霄界留下了你的第一笔命书。</p>
          <div class="birth-result">
            <div><span>先天灵根</span><strong>${escapeHtml(spiritRoot)}</strong></div>
            <div><span>降生命格</span><strong>${escapeHtml(fate)}</strong></div>
          </div>
          <button id="enterWorldBtn" class="primary-btn full" type="button">进入九霄界</button>
        </section>
      </div>
    `;
    document.getElementById('enterWorldBtn').addEventListener('click', async () => {
      modalRoot.innerHTML = '';
      await enterGame();
    });
  }

  function renderDeathScreen(bundle, timeStatus) {
    stopCultivationLoop();
    state.deathHandled = true;
    renderAccount();
    const c = bundle?.character || {};
    const world = bundle?.world || {};
    const realm = bundle?.realm || {};
    const stage = bundle?.stage || {};
    const deathYear = timeStatus?.death_world_year || timeStatus?.current_world_year || world.current_year || '—';
    const generation = Number(c.generation_number || timeStatus?.generation_number || 1);
    const realmLabel = realm.code === 'mortal'
      ? (stage.stage_name || realm.name || '凡人')
      : `${realm.name || ''}${stage.stage_name ? ` · ${stage.stage_name}` : ''}`;

    app.innerHTML = `
      <section class="death-layout">
        <article class="death-scroll panel">
          <div class="death-seal">终</div>
          <span class="eyebrow">仙历 ${escapeHtml(deathYear)} 年 · 道统第 ${escapeHtml(generation)} 世</span>
          <h1>${escapeHtml(c.name || '此世修士')}，此生已尽</h1>
          <p>${escapeHtml(c.name || '此世修士')}寿元耗尽，于${escapeHtml(realmLabel)}之境归于天地。旧角色已停止修炼、机缘与突破，但命书和道统仍被保留。</p>
          <div class="death-stats">
            <div><span>享年</span><strong>${escapeHtml(c.age || timeStatus?.character_age || '—')} 岁</strong></div>
            <div><span>最终境界</span><strong>${escapeHtml(realmLabel)}</strong></div>
            <div><span>陨落仙历</span><strong>${escapeHtml(deathYear)} 年</strong></div>
            <div><span>下一世</span><strong>第 ${escapeHtml(generation + 1)} 世</strong></div>
          </div>
          <div class="time-law-note">
            <strong>九霄时序</strong>
            <span>现实 1 天推进仙历 12 年；现实 2 小时推进 1 个游戏年。</span>
          </div>
        </article>

        <section class="reincarnation-panel panel">
          <div class="panel-title"><h3>续接道统</h3><span class="badge">三择其一</span></div>
          <p class="reincarnation-intro">转世会生成新的灵根与命格，并继承同一道统和世代编号。请选择一项前世遗泽。</p>
          <form id="reincarnationForm" class="form-stack">
            <div class="legacy-choice-grid">
              <label class="legacy-choice">
                <input type="radio" name="legacyChoice" value="wisdom" checked>
                <span><b>前尘悟道</b><small>下一世悟性 +2</small></span>
              </label>
              <label class="legacy-choice">
                <input type="radio" name="legacyChoice" value="fortune">
                <span><b>气运相随</b><small>下一世气运 +2</small></span>
              </label>
              <label class="legacy-choice">
                <input type="radio" name="legacyChoice" value="steadfast">
                <span><b>道心不灭</b><small>下一世心境 +2</small></span>
              </label>
            </div>
            <div class="field">
              <label for="reincarnationName">下一世姓名</label>
              <input id="reincarnationName" type="text" minlength="2" maxlength="12" required placeholder="2—12 个字符">
            </div>
            <div class="field">
              <label>下一世性别</label>
              <div class="gender-grid">
                <div class="gender-option"><input id="reincarnationMale" name="reincarnationGender" type="radio" value="male"><label for="reincarnationMale">男</label></div>
                <div class="gender-option"><input id="reincarnationFemale" name="reincarnationGender" type="radio" value="female"><label for="reincarnationFemale">女</label></div>
                <div class="gender-option"><input id="reincarnationUnknown" name="reincarnationGender" type="radio" value="unspecified" checked><label for="reincarnationUnknown">不详</label></div>
              </div>
            </div>
            <div id="reincarnationError" class="form-error"></div>
            <button id="reincarnationSubmit" class="primary-btn full" type="submit">转世重修 · 续接第 ${escapeHtml(generation + 1)} 世</button>
          </form>
        </section>
      </section>
    `;

    document.getElementById('reincarnationForm')?.addEventListener('submit', async event => {
      event.preventDefault();
      const button = document.getElementById('reincarnationSubmit');
      const errorBox = document.getElementById('reincarnationError');
      setBusy(button, true, '轮回盘正在转动……');
      try {
        const name = document.getElementById('reincarnationName').value.trim();
        const gender = document.querySelector('input[name="reincarnationGender"]:checked')?.value || 'unspecified';
        const legacyChoice = document.querySelector('input[name="legacyChoice"]:checked')?.value || 'wisdom';
        const result = await rpcReincarnateCharacter(name, gender, legacyChoice);
        const choiceName = {
          wisdom: '前尘悟道 · 悟性 +2',
          fortune: '气运相随 · 气运 +2',
          steadfast: '道心不灭 · 心境 +2'
        }[legacyChoice] || '前世遗泽';
        modalRoot.innerHTML = `
          <div class="modal-backdrop">
            <section class="modal" role="dialog" aria-modal="true">
              <div class="modal-seal">轮</div>
              <h2>${escapeHtml(name)}，第 ${escapeHtml(result?.generation_number || generation + 1)} 世已开</h2>
              <p>前世命书归卷，新生灵光落入九霄。道统保留，灵根与命格将由天道重新判定。</p>
              <div class="birth-result">
                <div><span>道统世代</span><strong>第 ${escapeHtml(result?.generation_number || generation + 1)} 世</strong></div>
                <div><span>继承遗泽</span><strong>${escapeHtml(choiceName)}</strong></div>
              </div>
              <button id="enterReincarnationBtn" class="primary-btn full" type="button">进入新一世</button>
            </section>
          </div>
        `;
        document.getElementById('enterReincarnationBtn')?.addEventListener('click', async () => {
          modalRoot.innerHTML = '';
          state.deathHandled = false;
          await enterGame();
        });
      } catch (error) {
        errorBox.textContent = translateError(error);
        errorBox.classList.add('show');
      } finally {
        setBusy(button, false);
      }
    });
  }

  function genderName(value) {
    return value === 'male' ? '男' : value === 'female' ? '女' : '不详';
  }

  function statusName(value) {
    const map = { active: '在世', secluded: '闭关', missing: '失踪', dead: '陨落', ascended: '飞升' };
    return map[value] || value;
  }

  function healthName(value) {
    const map = { healthy: '安康', injured: '负伤', wounded: '重伤', critical: '垂危' };
    return map[value] || value || '安康';
  }

  function formatNumber(value, maximumFractionDigits = 0) {
    const number = Number(value || 0);
    return new Intl.NumberFormat('zh-CN', { maximumFractionDigits }).format(number);
  }

  function formatRate(value) {
    const number = Number(value || 0);
    const digits = number >= 100 ? 1 : number >= 10 ? 2 : 3;
    return `+${formatNumber(number, digits)} / 秒`;
  }

  function formatDuration(seconds) {
    const total = Math.max(0, Math.floor(Number(seconds || 0)));
    if (total < 60) return `${total} 秒`;
    if (total < 3600) return `${Math.floor(total / 60)} 分 ${total % 60} 秒`;
    if (total < 86400) return `${Math.floor(total / 3600)} 小时 ${Math.floor((total % 3600) / 60)} 分`;
    return `${Math.floor(total / 86400)} 天 ${Math.floor((total % 86400) / 3600)} 小时`;
  }

  function formatClock(seconds) {
    const total = Math.max(0, Math.floor(Number(seconds || 0)));
    const hours = Math.floor(total / 3600);
    const minutes = Math.floor((total % 3600) / 60);
    const secs = total % 60;
    return [hours, minutes, secs].map(value => String(value).padStart(2, '0')).join(':');
  }

  function applyTimeStatus(status) {
    if (!status) return;
    state.timeStatus = status;
    state.timeStatusStartedAt = Date.now();
    if (state.character && status.character_id === state.character.id) {
      if (status.character_age !== undefined) state.character.age = status.character_age;
      if (status.lifespan_total !== undefined) state.character.lifespan_total = status.lifespan_total;
      if (status.lifespan_used !== undefined) state.character.lifespan_used = status.lifespan_used;
      if (status.character_status) state.character.status = status.character_status;
    }
    if (state.details?.world && status.current_world_year !== undefined) {
      state.details.world.current_year = status.current_world_year;
    }
  }

  function currentTimeSnapshot() {
    const status = state.timeStatus || {};
    const ratio = Number(status.game_years_per_real_day || 12);
    const elapsedRealSeconds = Math.max(0, (Date.now() - Number(state.timeStatusStartedAt || Date.now())) / 1000);
    const elapsedGameYears = elapsedRealSeconds / 86400 * ratio;
    const exactYear = Number(status.current_world_year_exact ?? status.current_world_year ?? 0) + elapsedGameYears;
    const baseFraction = Number(status.fractional_years || 0);
    const characterProgress = baseFraction + elapsedGameYears;
    const gainedWholeYears = Math.floor(characterProgress);
    const characterAge = Number(status.character_age ?? state.character?.age ?? 0) + gainedWholeYears;
    const lifespanUsed = Number(status.lifespan_used ?? state.character?.lifespan_used ?? 0) + gainedWholeYears;
    const lifespanTotal = Number(status.lifespan_total ?? state.character?.lifespan_total ?? 0);
    const secondsPerYear = Number(status.seconds_per_game_year || (86400 / Math.max(ratio, 0.0001)));
    const yearFraction = exactYear - Math.floor(exactYear);
    const secondsUntilNextYear = status.is_enabled === false ? null : Math.max(0, (1 - yearFraction) * secondsPerYear);
    return {
      exactYear,
      currentWorldYear: Math.floor(exactYear),
      characterAge,
      lifespanUsed,
      lifespanTotal,
      lifespanRemaining: Math.max(0, lifespanTotal - lifespanUsed),
      secondsUntilNextYear,
      ratio
    };
  }

  function updateGameTimeDisplay() {
    if (!state.timeStatus) return;
    const snapshot = currentTimeSnapshot();
    const worldYear = document.getElementById('worldYearValue');
    const ageValue = document.getElementById('characterAgeValue');
    const lifespanValue = document.getElementById('lifespanRemainingValue');
    const timeCountdown = document.getElementById('timeCountdownText');
    if (worldYear) worldYear.textContent = snapshot.currentWorldYear;
    if (ageValue) ageValue.textContent = snapshot.characterAge;
    if (lifespanValue) lifespanValue.textContent = `${snapshot.lifespanRemaining} 年`;
    if (timeCountdown) {
      timeCountdown.textContent = state.timeStatus.is_enabled === false
        ? '仙历已暂停'
        : `距下一岁 ${formatClock(snapshot.secondsUntilNextYear)} · 现实1日=仙历${formatNumber(snapshot.ratio)}年`;
    }
    if (snapshot.lifespanRemaining <= 0 && !state.timeSyncing && state.character?.status !== 'dead') {
      state.timeSyncing = true;
      setTimeout(async () => {
        try {
          await syncCultivation(true);
        } finally {
          state.timeSyncing = false;
        }
      }, 0);
    }
  }

  function effectRemainingText(effect) {
    if (!effect?.expires_at) return '永久生效';
    const seconds = Math.max(0, (new Date(effect.expires_at).getTime() - Date.now()) / 1000);
    return seconds > 0 ? `剩余 ${formatDuration(seconds)}` : '已结束';
  }

  function rarityName(value) {
    const map = { common: '寻常', uncommon: '少见', rare: '稀有', epic: '史诗', legendary: '传说' };
    return map[value] || value || '未知';
  }

  function currentDisplayedCultivation() {
    if (!state.cultivationStatus) return Number(state.character?.cultivation || 0);
    const rate = Number(state.cultivationStatus.current_rate_per_second || 0);
    const elapsed = Math.max(0, (Date.now() - state.liveCultivationStartedAt) / 1000);
    return Math.floor(state.liveCultivationBase + rate * elapsed);
  }

  function breakthroughPanelHtml(status, cultivationValue) {
    if (!status || status.status === 'loading') {
      return '<div class="empty-state">天道正在推演下一重道关……</div>';
    }
    if (status.status === 'maximum') {
      return `
        <div class="panel-title"><h3>境界突破</h3><span class="badge">道途已尽</span></div>
        <div class="breakthrough-card"><strong>${escapeHtml(status.current_stage_name || '未知境界')}</strong><p>当前版本尚未开放更高境界。</p></div>
      `;
    }
    const required = Number(status.cultivation_required || 0);
    const current = Number(cultivationValue ?? status.cultivation_total ?? 0);
    const percent = required > 0 ? Math.max(0, Math.min(100, current / required * 100)) : 100;
    const canBreakthrough = current >= required;
    return `
      <div class="panel-title"><h3>境界突破</h3><span class="badge">目标 · ${escapeHtml(status.next_stage_name || '未知')}</span></div>
      <div class="breakthrough-card">
        <div class="breakthrough-heading">
          <div><span>下一道关</span><strong>${escapeHtml(status.next_stage_name || '未知境界')}</strong></div>
          <div class="chance-orb"><small>成功率</small><b>${formatNumber(Number(status.success_rate || 0) * 100, 1)}%</b></div>
        </div>
        <div class="progress-label"><span>累计修为</span><strong id="breakthroughProgressText">${formatNumber(current)} / ${formatNumber(required)}</strong></div>
        <div class="progress-track"><div id="breakthroughProgressFill" class="progress-fill" style="width:${percent}%"></div></div>
        <div class="breakthrough-meta">
          <span>突破成功：寿元 +${escapeHtml(status.lifespan_bonus || 0)} 年</span>
          <span>逆境 ${escapeHtml(status.adversity || 0)}：失败会提高下次成功率</span>
        </div>
        <button id="attemptBreakthroughBtn" class="primary-btn full" type="button" ${canBreakthrough ? '' : 'disabled'}>
          ${canBreakthrough ? `冲击${escapeHtml(status.next_stage_name || '境界')}` : `尚缺 ${formatNumber(Math.max(0, required - current))} 修为`}
        </button>
      </div>
    `;
  }

  function opportunityPanelHtml(opportunity) {
    if (!opportunity || opportunity.status === 'loading') {
      return '<div class="empty-state">天机未显，正在观测灵气变化……</div>';
    }
    if (opportunity.status === 'pending') {
      const choices = Array.isArray(opportunity.choices) ? opportunity.choices : [];
      return `
        <div class="panel-title"><h3>天降机缘</h3><span class="badge rarity-${escapeHtml(opportunity.rarity || 'common')}">${escapeHtml(rarityName(opportunity.rarity))}</span></div>
        <article class="opportunity-scene">
          <span class="eyebrow">机缘已至</span>
          <h4>${escapeHtml(opportunity.title || '无名机缘')}</h4>
          <p>${escapeHtml(opportunity.content || '')}</p>
          <div class="opportunity-choices">
            ${choices.map(choice => `
              <button class="opportunity-choice" type="button" data-opportunity-id="${escapeHtml(opportunity.opportunity_id)}" data-choice-key="${escapeHtml(choice.choice_key)}">
                <strong>${escapeHtml(choice.choice_text)}</strong>
                <small>${escapeHtml(choice.reward_text || '所得由天道决定')}</small>
              </button>
            `).join('')}
          </div>
          <small class="opportunity-expire">此机缘将在 ${escapeHtml(new Date(opportunity.expires_at).toLocaleTimeString('zh-CN', { hour: '2-digit', minute: '2-digit' }))} 前消散。</small>
        </article>
      `;
    }
    const nextAt = opportunity.next_available_at ? new Date(opportunity.next_available_at) : null;
    const seconds = nextAt ? Math.max(0, Math.ceil((nextAt.getTime() - Date.now()) / 1000)) : Number(opportunity.seconds_until_next || 0);
    return `
      <div class="panel-title"><h3>天降机缘</h3><span class="badge">天机流转</span></div>
      <div class="opportunity-waiting">
        <div class="dao-orbit" aria-hidden="true"><i></i><i></i><i></i></div>
        <strong>下一次机缘推演中</strong>
        <p>气运越高，越容易在稀有机缘中获得上乘功法与修炼加成。</p>
        <span id="opportunityCountdown">${formatDuration(seconds)}</span>
      </div>
    `;
  }

  function showResultModal({ seal = '缘', title, message, detail = '', success = true }) {
    modalRoot.innerHTML = `
      <div class="modal-backdrop">
        <section class="modal" role="dialog" aria-modal="true">
          <div class="modal-seal ${success ? '' : 'failure-seal'}">${escapeHtml(seal)}</div>
          <h2>${escapeHtml(title)}</h2>
          <p>${escapeHtml(message)}</p>
          ${detail ? `<div class="result-detail">${escapeHtml(detail)}</div>` : ''}
          <button id="resultContinueBtn" class="primary-btn full" type="button">继续修行</button>
        </section>
      </div>
    `;
    document.getElementById('resultContinueBtn').addEventListener('click', async () => {
      modalRoot.innerHTML = '';
      await enterGame();
    });
  }

  function bindProgressionActions() {
    const breakthroughButton = document.getElementById('attemptBreakthroughBtn');
    if (breakthroughButton && breakthroughButton.dataset.bound !== '1') {
      breakthroughButton.dataset.bound = '1';
      breakthroughButton.addEventListener('click', async () => {
        setBusy(breakthroughButton, true, '正在冲关……');
        try {
          const result = await rpcAttemptBreakthrough();
          showResultModal({
            seal: result?.success ? '破' : '劫',
            title: result?.success ? `突破成功 · ${result.target_stage_name}` : '冲关未成',
            message: result?.message || (result?.success ? '道关已开。' : '灵机散乱。'),
            detail: result?.success
              ? `寿元增加 ${formatNumber(result.lifespan_bonus)} 年。`
              : `逆境累积至 ${formatNumber(result.adversity_after)}，下一次成功率将有所提高。`,
            success: Boolean(result?.success)
          });
        } catch (error) {
          showToast(translateError(error), 'error');
          setBusy(breakthroughButton, false);
        }
      });
    }

    document.querySelectorAll('.opportunity-choice').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        document.querySelectorAll('.opportunity-choice').forEach(item => { item.disabled = true; });
        setBusy(button, true, '天道结算中……');
        try {
          const result = await rpcResolveOpportunity(button.dataset.opportunityId, button.dataset.choiceKey);
          showResultModal({
            seal: '缘',
            title: result?.title || '机缘已定',
            message: result?.reward_text || '你从机缘中有所收获。',
            detail: result?.technique_name ? `新功法：${result.technique_name}` : (Number(result?.flat_rate_per_second || 0) ? `自动修炼永久增加 ${formatRate(result.flat_rate_per_second)}` : ''),
            success: true
          });
        } catch (error) {
          showToast(translateError(error), 'error');
          document.querySelectorAll('.opportunity-choice').forEach(item => { item.disabled = false; });
          setBusy(button, false);
          await refreshOpportunity();
        }
      });
    });
  }

  function updateProgressionDisplay() {
    const status = state.breakthroughStatus;
    if (!status || status.status !== 'available') return;
    const current = currentDisplayedCultivation();
    const required = Number(status.cultivation_required || 0);
    const percent = required > 0 ? Math.max(0, Math.min(100, current / required * 100)) : 100;
    const text = document.getElementById('breakthroughProgressText');
    const fill = document.getElementById('breakthroughProgressFill');
    const button = document.getElementById('attemptBreakthroughBtn');
    if (text) text.textContent = `${formatNumber(current)} / ${formatNumber(required)}`;
    if (fill) fill.style.width = `${percent}%`;
    if (button && !button.dataset.oldText) {
      const ready = current >= required;
      button.disabled = !ready;
      button.textContent = ready ? `冲击${status.next_stage_name || '下一境界'}` : `尚缺 ${formatNumber(Math.max(0, required - current))} 修为`;
    }
  }

  async function refreshOpportunity() {
    if (state.opportunitySyncing || !state.character) return;
    state.opportunitySyncing = true;
    try {
      state.opportunityStatus = await rpcGetOpportunity();
      const panel = document.getElementById('opportunityPanel');
      if (panel) {
        panel.innerHTML = opportunityPanelHtml(state.opportunityStatus);
        bindProgressionActions();
      }
    } catch (error) {
      console.error(error);
    } finally {
      state.opportunitySyncing = false;
    }
  }

  async function refreshBreakthroughStatus() {
    if (!state.character) return;
    try {
      state.breakthroughStatus = await rpcGetBreakthroughStatus();
      const panel = document.getElementById('breakthroughPanel');
      if (panel) {
        panel.innerHTML = breakthroughPanelHtml(state.breakthroughStatus, currentDisplayedCultivation());
        bindProgressionActions();
      }
    } catch (error) {
      console.error(error);
    }
  }

  async function refreshTechniqueSystem(rebind = false) {
    if (!state.character || state.techniqueSyncing) return state.techniqueSystem;
    state.techniqueSyncing = true;
    try {
      const system = await rpcGetTechniqueSystemV2();
      if (!system || system.status !== 'ok') return system;
      state.techniqueSystem = system;
      if (state.details) state.details.techniqueSystem = system;
      const root = document.getElementById('techniqueV2Root');
      if (root && state.details) {
        root.outerHTML = techniquePanelHtml(system, state.details.inventory || []);
        if (rebind) bindInventoryTechniqueActions();
        else bindInventoryTechniqueActions();
      }
      return system;
    } catch (error) {
      console.error(error);
      return null;
    } finally {
      state.techniqueSyncing = false;
    }
  }

  async function refreshSupplyStatus() {
    if (!state.character) return;
    try {
      state.supplyStatus = await rpcGetDailySupplyStatus();
      const screen = document.querySelector('[data-mobile-screen="inventory"]');
      if (screen && state.details) {
        const card = screen.querySelector('.supply-card');
        if (card) card.outerHTML = supplyPanelHtml(state.supplyStatus);
        bindInventoryTechniqueActions();
      }
    } catch (error) {
      console.error(error);
    }
  }

  function updateOpportunityCountdown() {
    const opportunity = state.opportunityStatus;
    if (!opportunity || opportunity.status !== 'waiting') return;
    const target = opportunity.next_available_at ? new Date(opportunity.next_available_at).getTime() : 0;
    const seconds = target ? Math.max(0, Math.ceil((target - Date.now()) / 1000)) : Math.max(0, Number(opportunity.seconds_until_next || 0));
    const label = document.getElementById('opportunityCountdown');
    if (label) label.textContent = seconds > 0 ? formatDuration(seconds) : '天机将显';
    if (seconds <= 0) refreshOpportunity();
  }


  function techniqueCategoryName(value) {
    const map = {
      main: '主修功法',
      support: '辅修功法',
      divine_ability: '神通',
      body: '炼体功法',
      movement: '身法'
    };
    return map[value] || value || '功法';
  }

  function techniqueEffectText(row) {
    const definition = row?.definition || {};
    const level = Number(row?.level || 1);
    const fixed = definition.fixed_effects || {};
    const flat = Number(fixed.cultivation_per_second || 0) * level;
    const multiplier = Math.max(0, Number(fixed.cultivation_multiplier || 1) - 1);
    const parts = [];
    if (flat) parts.push(`每秒修为 +${formatNumber(flat, 3)}`);
    if (multiplier) parts.push(`修炼倍率 +${formatNumber(multiplier * 100, 2)}%`);
    if (Number(fixed.lifespan_bonus || 0)) parts.push(`寿元潜力 +${formatNumber(Number(fixed.lifespan_bonus) * 100, 1)}%`);
    if (Number(fixed.recovery || 0)) parts.push(`恢复效率 +${formatNumber(Number(fixed.recovery) * 100, 1)}%`);
    return parts.join(' · ') || '当前没有直接修炼数值加成';
  }

  function itemEffectText(item) {
    const definition = item?.definition || {};
    const effects = definition.effects || {};
    const useType = effects.use_type || '';
    if (definition.code === 'spirit_stone') return '修仙界通用货币，用于精进功法。';
    if (useType === 'instant_cultivation') return `使用后立即修为 +${formatNumber(effects.instant_cultivation || 0)}。`;
    if (useType === 'timed_rate') return '使用后获得限时自动修炼速度加成。';
    if (useType === 'comprehension') return `使用后永久悟性 +${formatNumber(effects.comprehension || 0)}。`;
    return definition.description || '暂未开放直接使用。';
  }

  function normalizeStackLabel(value) {
    return String(value || '')
      .normalize('NFKC')
      .replace(/\s+/g, '')
      .toLocaleLowerCase('zh-CN');
  }

  function stackCultivationEffects(effects) {
    const groups = new Map();
    (effects || []).forEach(effect => {
      const displayName = String(effect?.display_name || effect?.source_key || '未知加成').trim();
      const durationType = effect?.expires_at ? 'timed' : 'permanent';
      const key = `${normalizeStackLabel(displayName)}::${durationType}`;
      const current = groups.get(key) || [];
      current.push(effect);
      groups.set(key, current);
    });

    return Array.from(groups.values()).map(group => {
      const first = group[0] || {};
      const timedExpirations = group
        .map(row => row?.expires_at ? new Date(row.expires_at).getTime() : null)
        .filter(value => Number.isFinite(value));
      const expiresAt = timedExpirations.length
        ? new Date(Math.min(...timedExpirations)).toISOString()
        : null;
      return {
        ...first,
        expires_at: expiresAt,
        effect_count: group.length,
        flat_rate_per_second: group.reduce((sum, row) => sum + Number(row?.flat_rate_per_second || 0), 0),
        multiplier_bonus: group.reduce((sum, row) => sum + Number(row?.multiplier_bonus || 0), 0),
        stacked_effect_ids: group.map(row => row?.id).filter(Boolean)
      };
    }).sort((a, b) => {
      const permanentOrder = Number(Boolean(a.expires_at)) - Number(Boolean(b.expires_at));
      if (permanentOrder) return permanentOrder;
      return String(a.display_name || '').localeCompare(String(b.display_name || ''), 'zh-CN');
    });
  }

  function stackTechniqueAcquisitions(techniques) {
    const groups = new Map();
    (techniques || []).forEach(row => {
      const key = row?.technique_id || row?.definition?.code || row?.definition?.name || row?.id;
      if (!key) return;
      const current = groups.get(key) || [];
      current.push(row);
      groups.set(key, current);
    });

    return Array.from(groups.values()).map(group => {
      const ranked = [...group].sort((a, b) => {
        const equippedScore = Number(Boolean(b?.is_equipped)) - Number(Boolean(a?.is_equipped));
        if (equippedScore) return equippedScore;
        const levelScore = Number(b?.level || 1) - Number(a?.level || 1);
        if (levelScore) return levelScore;
        return Number(b?.proficiency || 0) - Number(a?.proficiency || 0);
      });
      const acquisitionCount = group.reduce((total, row) => {
        const repeatedRewards = Math.floor(Math.max(0, Number(row?.proficiency || 0)) / 100);
        return total + 1 + repeatedRewards;
      }, 0);
      return {
        ...ranked[0],
        acquisition_count: acquisitionCount,
        acquisition_ids: group.map(row => row.id).filter(Boolean)
      };
    });
  }

  function techniqueSlotName(value) {
    const map = {
      main: '主修槽',
      support_1: '辅修一',
      support_2: '辅修二'
    };
    return map[value] || '未运转';
  }

  function techniqueGradeClass(value) {
    return `grade-${String(value || 'mortal').replace(/[^a-z0-9_-]/gi, '')}`;
  }

  function techniqueV2EffectText(row) {
    const fixed = row?.fixed_effects || row?.definition?.fixed_effects || {};
    const level = Number(row?.level || 1);
    const flat = Number(fixed.cultivation_per_second || 0) * level;
    const multiplier = Math.max(0, Number(fixed.cultivation_multiplier || 1) - 1);
    const parts = [];
    if (flat) parts.push(`每秒修为 +${formatNumber(flat, 3)}`);
    if (multiplier) parts.push(`修炼倍率 +${formatNumber(multiplier * 100, 2)}%`);
    if (Number(fixed.lifespan_bonus || 0)) parts.push(`寿元潜力 +${formatNumber(Number(fixed.lifespan_bonus) * 100, 1)}%`);
    if (Number(fixed.recovery || 0)) parts.push(`恢复效率 +${formatNumber(Number(fixed.recovery) * 100, 1)}%`);
    return parts.join(' · ') || '当前没有直接修炼数值加成';
  }

  function combinationEffectText(row) {
    const effects = row?.effects || {};
    const parts = [];
    if (Number(effects.flat_rate_per_second || 0)) parts.push(`每秒修为 +${formatNumber(effects.flat_rate_per_second, 3)}`);
    if (Number(effects.multiplier_bonus || 0)) parts.push(`修炼倍率 +${formatNumber(Number(effects.multiplier_bonus) * 100, 2)}%`);
    return parts.join(' · ') || '组合效果待配置';
  }

  function techniquePanelHtml(system, inventory) {
    const rows = Array.isArray(system?.techniques) ? system.techniques : [];
    const combinations = Array.isArray(system?.combinations) ? system.combinations : [];
    const stone = (inventory || []).find(row => row.definition?.code === 'spirit_stone');
    const stones = Number(stone?.quantity || 0);
    const slots = system?.slots || {};
    if (!rows.length) return '<div id="techniqueV2Root"><div class="empty-state">尚未习得功法。</div></div>';

    return `
      <div id="techniqueV2Root" class="technique-v2-root">
        <div class="resource-inline"><span>可用灵石</span><strong>${formatNumber(stones)}</strong></div>
        <div class="technique-slot-grid">
          ${['main', 'support_1', 'support_2'].map(slot => {
            const equipped = rows.find(row => row.character_technique_id === slots?.[slot] || row.equipped_slot === slot);
            return `<article class="technique-slot ${equipped ? 'filled' : ''}">
              <span>${escapeHtml(techniqueSlotName(slot))}</span>
              <strong>${escapeHtml(equipped?.name || '空置')}</strong>
              <small>${equipped ? `${escapeHtml(equipped.grade_name || '凡品')} · 第 ${formatNumber(equipped.level)} 层` : '选择功法开始运转'}</small>
            </article>`;
          }).join('')}
        </div>
        <div class="technique-rule-note">
          <strong>功法 V2</strong>
          <span>主修熟练速度100%，辅修50%；每层需要100点熟练/传承进度。重复获得只转化为传承点，不再叠加永久修炼效果。</span>
        </div>
        <div class="technique-manage-list">
          ${rows.map(row => {
            const category = row.category || 'main';
            const isMain = category === 'main';
            const equipped = Boolean(row.equipped_slot);
            const level = Number(row.level || 1);
            const maxLevel = Number(row.max_level || 20);
            const proficiency = Math.max(0, Math.min(100, Number(row.proficiency || 0)));
            const mastery = Math.max(0, Number(row.mastery_points || 0));
            const combinedProgress = Math.min(100, proficiency + mastery);
            const maxed = level >= maxLevel;
            const canUpgrade = Boolean(row.can_upgrade) && !maxed;
            const slotTarget = equipped ? 'none' : (isMain ? 'main' : 'auto_support');
            const slotLabel = equipped ? (isMain ? '主修运转中' : '停止辅修') : (isMain ? '设为主修' : '设为辅修');
            return `
              <article class="manage-card technique-v2-card ${equipped ? 'equipped' : ''}">
                <div class="manage-card-head">
                  <div>
                    <span class="technique-grade ${escapeHtml(techniqueGradeClass(row.grade_code))}">${escapeHtml(row.grade_name || row.raw_grade || '凡品')}</span>
                    <strong>${escapeHtml(row.name || '未知功法')} <small>第 ${level}/${maxLevel} 层</small></strong>
                  </div>
                  <span class="badge">${escapeHtml(equipped ? techniqueSlotName(row.equipped_slot) : techniqueCategoryName(category))}</span>
                </div>
                <p>${escapeHtml(techniqueV2EffectText(row))}</p>
                <small class="manage-description">${escapeHtml(row.description || '')}</small>
                <div class="technique-progress-copy">
                  <span>熟练 ${formatNumber(proficiency)}/100</span>
                  <span>传承点 ${formatNumber(mastery)}</span>
                  <span>获得 ${formatNumber(row.acquisition_count || 1)} 次</span>
                </div>
                <div class="progress-track technique-progress"><div class="progress-fill" style="width:${combinedProgress}%"></div></div>
                <small class="technique-progress-hint">${maxed ? '已达到当前品质层数上限' : (canUpgrade ? '已经满足精进条件' : `还需 ${formatNumber(row.progress_needed || Math.max(0, 100 - proficiency - mastery))} 点熟练或传承进度`)}</small>
                <div class="manage-actions">
                  <button
                    class="ghost-btn"
                    type="button"
                    data-technique-slot="${escapeHtml(row.character_technique_id)}"
                    data-target-slot="${escapeHtml(slotTarget)}"
                    ${equipped && isMain ? 'disabled' : ''}
                  >${escapeHtml(slotLabel)}</button>
                  <button
                    class="primary-btn"
                    type="button"
                    data-upgrade-technique-v2="${escapeHtml(row.character_technique_id)}"
                    ${canUpgrade ? '' : 'disabled'}
                  >${maxed ? '已满层' : `精进 · ${formatNumber(row.upgrade_cost || 0)} 灵石`}</button>
                </div>
              </article>
            `;
          }).join('')}
        </div>
        <div class="technique-combination-section">
          <div class="subsection-title"><strong>功法组合</strong><span>${combinations.filter(row => row.is_active).length} 个已激活</span></div>
          <div class="technique-combination-grid">
            ${combinations.map(row => `
              <article class="combination-card ${row.is_active ? 'active' : ''}">
                <span>${row.is_active ? '已激活' : '未激活'}</span>
                <strong>${escapeHtml(row.name)}</strong>
                <p>${escapeHtml(row.description || '')}</p>
                <small>${escapeHtml(combinationEffectText(row))}</small>
              </article>
            `).join('') || '<div class="empty-state">尚无功法组合配置。</div>'}
          </div>
        </div>
      </div>
    `;
  }

  function supplyPanelHtml(status) {
    const canClaim = Boolean(status?.can_claim);
    const seconds = Number(status?.seconds_until_next || 0);
    return `
      <article class="supply-card">
        <div>
          <span>洞府灵脉每日产出</span>
          <strong>${canClaim ? '补给已经成熟' : '灵脉正在凝聚'}</strong>
          <p>固定获得灵石 200、聚气丹 1；另有概率获得聚灵香。</p>
        </div>
        <button id="claimSupplyBtn" class="${canClaim ? 'primary-btn' : 'ghost-btn'}" type="button" ${canClaim ? '' : 'disabled'}>
          ${canClaim ? '领取补给' : `<span id="supplyCountdown">${formatDuration(seconds)}</span>`}
        </button>
      </article>
    `;
  }

  function inventoryPanelHtml(inventory, supplyStatus) {
    const items = inventory || [];
    return `
      ${supplyPanelHtml(supplyStatus)}
      <div class="inventory-grid">
        ${items.length ? items.map(row => {
          const definition = row.definition || {};
          const effects = definition.effects || {};
          const usable = ['instant_cultivation','timed_rate','comprehension'].includes(effects.use_type);
          return `
            <article class="inventory-card rarity-${escapeHtml(definition.rarity || 'common')}">
              <div class="inventory-icon">${escapeHtml((definition.name || '物').slice(0, 1))}</div>
              <div class="inventory-copy">
                <span>${escapeHtml(rarityName(definition.rarity))} · ${escapeHtml(definition.category || '物品')}</span>
                <strong>${escapeHtml(definition.name || '未知物品')} <small>× ${formatNumber(row.quantity)}</small></strong>
                <p>${escapeHtml(itemEffectText(row))}</p>
              </div>
              ${usable ? `<button class="primary-btn inventory-use-btn" type="button" data-use-item="${escapeHtml(row.id)}">使用</button>` : ''}
            </article>
          `;
        }).join('') : '<div class="empty-state">储物袋空空如也。</div>'}
      </div>
    `;
  }

  function updateSupplyCountdown() {
    const status = state.supplyStatus;
    if (!status || status.can_claim) return;
    const target = status.next_claim_at ? new Date(status.next_claim_at).getTime() : 0;
    const seconds = target ? Math.max(0, Math.ceil((target - Date.now()) / 1000)) : Math.max(0, Number(status.seconds_until_next || 0));
    const label = document.getElementById('supplyCountdown');
    if (label) label.textContent = seconds > 0 ? formatDuration(seconds) : '可以领取';
    if (seconds <= 0) {
      state.supplyStatus = { ...status, can_claim: true, seconds_until_next: 0 };
      const inventoryScreen = document.querySelector('[data-mobile-screen="inventory"]');
      if (inventoryScreen && state.details) {
        inventoryScreen.querySelector('.supply-card')?.remove();
        inventoryScreen.insertAdjacentHTML('afterbegin', supplyPanelHtml(state.supplyStatus));
        bindInventoryTechniqueActions();
      }
    }
  }

  function bindInventoryTechniqueActions() {
    const claimSupplyButton = document.getElementById('claimSupplyBtn');
    if (claimSupplyButton && claimSupplyButton.dataset.bound !== '1') {
      claimSupplyButton.dataset.bound = '1';
      claimSupplyButton.addEventListener('click', async () => {
        setBusy(claimSupplyButton, true, '领取中……');
        try {
          state.activeMobileTab = 'inventory';
          const result = await rpcClaimDailySupply();
          showResultModal({
            seal: '府',
            title: '洞府补给已入袋',
            message: `灵石 +${formatNumber(result?.spirit_stone || 0)}，聚气丹 +${formatNumber(result?.qi_gathering_pill || 0)}。`,
            detail: Number(result?.spirit_incense || 0) > 0 ? '灵脉额外凝成一支聚灵香。' : '今日未凝出额外珍物。',
            success: true
          });
        } catch (error) {
          showToast(translateError(error), 'error');
          setBusy(claimSupplyButton, false);
        }
      });
    }

    document.querySelectorAll('[data-use-item]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        setBusy(button, true, '炼化中……');
        try {
          state.activeMobileTab = 'inventory';
          const result = await rpcUseInventoryItem(button.dataset.useItem);
          showResultModal({
            seal: '物',
            title: `使用 · ${result?.item_name || '储物'}`,
            message: result?.reward_text || '物品已经生效。',
            detail: Number(result?.quantity_remaining || 0) > 0 ? `剩余数量：${formatNumber(result.quantity_remaining)}` : '该物品已经用尽。',
            success: true
          });
        } catch (error) {
          showToast(translateError(error), 'error');
          setBusy(button, false);
        }
      });
    });

    document.querySelectorAll('[data-technique-slot]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        setBusy(button, true, '调整中……');
        try {
          state.activeMobileTab = 'techniques';
          const result = await rpcSetTechniqueSlotV2(
            button.dataset.techniqueSlot,
            button.dataset.targetSlot || 'none'
          );
          showToast(`${result?.technique_name || '功法'}${result?.equipped ? `已放入${techniqueSlotName(result?.equipped_slot)}` : '已停止运转'}。`);
          await refreshTechniqueSystem(true);
          await syncCultivation(true);
        } catch (error) {
          showToast(translateError(error), 'error');
          setBusy(button, false);
        }
      });
    });

    document.querySelectorAll('[data-upgrade-technique-v2]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        setBusy(button, true, '参悟中……');
        try {
          state.activeMobileTab = 'techniques';
          const result = await rpcUpgradeTechniqueV2(button.dataset.upgradeTechniqueV2);
          const spiritStone = state.details?.inventory?.find(row => row.definition?.code === 'spirit_stone');
          if (spiritStone && Number.isFinite(Number(result?.spirit_stones_remaining))) {
            spiritStone.quantity = Number(result.spirit_stones_remaining);
          }
          await refreshTechniqueSystem(true);
          showResultModal({
            seal: '法',
            title: `功法精进 · 第 ${formatNumber(result?.level || 0)} 层`,
            message: `${result?.technique_name || '功法'}已突破本层桎梏。`,
            detail: `消耗灵石 ${formatNumber(result?.cost || 0)}，熟练消耗 ${formatNumber(result?.proficiency_spent || 0)}，传承点消耗 ${formatNumber(result?.mastery_spent || 0)}。`,
            success: true
          });
          await syncCultivation(true);
        } catch (error) {
          showToast(translateError(error), 'error');
          setBusy(button, false);
        }
      });
    });
  }


  function renderDashboard(bundle) {
    renderAccount();
    const c = bundle.character;
    const world = bundle.world || {};
    const stage = bundle.stage || {};
    const realm = bundle.realm || {};
    const root = bundle.spiritRoot || {};
    const fate = bundle.fate || {};
    const cultivation = bundle.cultivationStatus || state.cultivationStatus || {};
    const breakthrough = bundle.breakthroughStatus || state.breakthroughStatus || { status: 'loading' };
    const opportunity = bundle.opportunityStatus || state.opportunityStatus || { status: 'loading' };
    const rate = Number(cultivation.current_rate_per_second || 0);
    const lifespanRemaining = Math.max(0, Number(c.lifespan_total) - Number(c.lifespan_used));
    const realmLabel = realm.code === 'mortal' ? (stage.stage_name || realm.name || '凡人') : `${realm.name || ''}${stage.stage_name ? ` · ${stage.stage_name}` : ''}`;
    const techniqueSystem = bundle.techniqueSystem || state.techniqueSystem || { techniques: [], combinations: [], slots: {} };
    const techniques = Array.isArray(techniqueSystem.techniques) ? techniqueSystem.techniques : [];
    const inventory = bundle.inventory || [];
    const supplyStatus = bundle.supplyStatus || state.supplyStatus || { can_claim: false, seconds_until_next: 0 };
    const activeEffects = (bundle.cultivationEffects || []).filter(row => {
      const isCurrent = !row.expires_at || new Date(row.expires_at).getTime() > Date.now();
      const isCombination = row?.metadata?.v2_kind === 'combination' || String(row?.source_key || '').startsWith('combo:');
      return isCurrent && !isCombination;
    });
    const stackedActiveEffects = stackCultivationEffects(activeEffects);
    const offlineGain = Number(cultivation.gained || 0);
    const elapsed = Number(cultivation.elapsed_seconds || 0);
    const requiredForNext = Number(breakthrough?.cultivation_required || 0);
    const currentCultivation = Number(c.cultivation || 0);
    const toNext = Math.max(0, requiredForNext - currentCultivation);
    const nextPercent = requiredForNext > 0 ? Math.max(0, Math.min(100, currentCultivation / requiredForNext * 100)) : 0;

    app.innerHTML = `
      <section class="dashboard dashboard-reforge">
        <section class="hero-hud panel">
          <div class="hero-hud-top">
            <div class="hero-id">
              <div class="hero-avatar">${escapeHtml(c.name.slice(0, 1))}</div>
              <div class="hero-copy">
                <span class="eyebrow">${escapeHtml(world.era_name || '仙历')} <b id="worldYearValue">${escapeHtml(world.current_year || '—')}</b> 年 · ${escapeHtml(world.name || '九霄界')}</span>
                <h1>${escapeHtml(c.name)}</h1>
                <div class="hero-meta-line">
                  <span class="hero-chip realm">${escapeHtml(realmLabel)}</span>
                  <span class="hero-chip">${escapeHtml(genderName(c.gender))} · <b id="characterAgeValue">${escapeHtml(c.age)}</b> 岁</span>
                  <span class="hero-chip">道统第 ${escapeHtml(c.generation_number || 1)} 世</span>
                  <span class="hero-chip">${escapeHtml(root.name || '未测灵根')}</span>
                  <span class="hero-chip">${escapeHtml(fate.name || '未定命格')}</span>
                </div>
              </div>
            </div>
            <div class="hero-side-actions">
              <span class="badge live-badge"><i></i>自动修炼中</span>
              <button id="manualSyncBtn" class="ghost-btn hero-sync-btn" type="button">立即同步</button>
            </div>
          </div>

          <div class="hud-strip">
            <article class="hud-pill primary">
              <span>修为</span>
              <strong id="cultivationValue">${formatNumber(c.cultivation)}</strong>
              <small id="cultivationRateText">${formatRate(rate)}</small>
            </article>
            <article class="hud-pill">
              <span>寿元</span>
              <strong id="lifespanRemainingValue">${escapeHtml(lifespanRemaining)} 年</strong>
              <small id="timeCountdownText">现实1日=仙历12年</small>
            </article>
            <article class="hud-pill">
              <span>悟性</span>
              <strong>${escapeHtml(c.comprehension)}</strong>
              <small>功法领悟</small>
            </article>
            <article class="hud-pill">
              <span>气运</span>
              <strong>${escapeHtml(c.luck)}</strong>
              <small>机缘遭逢</small>
            </article>
          </div>

          <nav class="section-nav" aria-label="游戏内容导航">
            <a href="#cultivationSection">修炼</a>
            <a href="#talentSection">功法</a>
            <a href="#inventorySection">储物</a>
            <a href="#opportunitySection">机缘</a>
            <a href="#historySection">命书</a>
          </nav>
        </section>

        <section id="cultivationSection" class="panel cultivation-focus-panel" data-mobile-screen="cultivation">
          <div class="panel-title"><h3>修炼</h3><span id="cloudSaveBadge" class="badge">云端同步</span></div>
          <div class="cultivation-focus-layout">
            <div class="cultivation-visual">
              <div class="aura-ring">
                <div class="aura-inner">道</div>
              </div>
              <div class="focus-caption">洞府吐纳自行运转；仙历、年龄与寿元均由云端时间结算。</div>
            </div>
            <div class="cultivation-focus-main">
              <div class="focus-stat">
                <span>当前自动修炼速度</span>
                <strong id="liveRateValue">${formatRate(rate)}</strong>
                <small>${requiredForNext > 0 ? `距下一境还差 ${formatNumber(toNext)} 修为` : '当前版本已达可读取的道关上限。'}</small>
              </div>
              <div class="progress-label compact"><span>破境进度</span><strong id="breakthroughProgressTextCompact">${requiredForNext > 0 ? `${formatNumber(currentCultivation)} / ${formatNumber(requiredForNext)}` : '已满'}</strong></div>
              <div class="progress-track compact"><div id="breakthroughProgressFillCompact" class="progress-fill" style="width:${nextPercent}%"></div></div>
              ${offlineGain > 0 && elapsed >= 5 ? `
                <div class="offline-inline">
                  <strong>离线修炼 +${formatNumber(offlineGain)}</strong>
                  <span>共结算 ${escapeHtml(formatDuration(elapsed))}</span>
                </div>
              ` : ''}
              <div class="rate-breakdown mobile-tight">
                <div><span>基础吐纳</span><strong>+${formatNumber(cultivation.base_rate_per_second, 3)}/秒</strong></div>
                <div><span>功法加成</span><strong>+${formatNumber(cultivation.technique_flat_rate, 3)}/秒</strong></div>
                <div><span>灵根倍率</span><strong>×${formatNumber(cultivation.root_multiplier || 1, 3)}</strong></div>
                <div><span>灵气环境</span><strong>×${formatNumber(cultivation.qi_multiplier || 1, 3)}</strong></div>
                <div><span>命格修正</span><strong>${Number(cultivation.fate_bonus || 0) >= 0 ? '+' : ''}${formatNumber(Number(cultivation.fate_bonus || 0) * 100, 2)}%</strong></div>
                <div><span>持续机缘</span><strong>+${formatNumber(cultivation.effect_flat_rate, 3)}/秒</strong></div>
              </div>
            </div>
          </div>
          <div class="attribute-mini-grid">
            <div><span>心境</span><strong>${escapeHtml(c.mindset)}</strong></div>
            <div><span>因果</span><strong>${escapeHtml(c.karma)}</strong></div>
            <div><span>逆境</span><strong>${escapeHtml(c.adversity)}</strong></div>
            <div><span>天道</span><strong>${escapeHtml(world.heaven_state || 'stable')}</strong></div>
          </div>
        </section>

        <section id="talentSection" class="panel info-section" data-mobile-screen="techniques">
          <div class="panel-title"><h3>功法</h3><span class="badge">品质 · 熟练 · 组合</span></div>
          <div class="foundation-grid">
            <article class="path-card">
              <span>先天灵根 · ${escapeHtml(root.rarity || '未知')}</span>
              <strong>${escapeHtml(root.name || '未测')}</strong>
              <p>修炼速度倍率 ×${formatNumber(root.cultivation_multiplier || 1, 3)}。${escapeHtml(root.description || '')}</p>
            </article>
            <article class="path-card">
              <span>降生命格 · ${escapeHtml(fate.rarity || '未知')}</span>
              <strong>${escapeHtml(fate.name || '未定')}</strong>
              <p>${escapeHtml(fate.description || '命格信息尚未读取。')}</p>
            </article>
          </div>
          ${techniquePanelHtml(techniqueSystem, inventory)}
          ${stackedActiveEffects.length ? `
            <div class="effect-strip">
              ${stackedActiveEffects.map(effect => `
                <article>
                  <span>${escapeHtml(effectRemainingText(effect))}</span>
                  <strong>${escapeHtml(effect.display_name)} X${formatNumber(effect.effect_count || 1)}</strong>
                  <small>${Number(effect.flat_rate_per_second) ? `每秒修为 +${formatNumber(effect.flat_rate_per_second, 3)}` : ''}${Number(effect.flat_rate_per_second) && Number(effect.multiplier_bonus) ? ' · ' : ''}${Number(effect.multiplier_bonus) ? `修炼倍率 +${formatNumber(Number(effect.multiplier_bonus) * 100, 2)}%` : ''}</small>
                </article>
              `).join('')}
            </div>
          ` : ''}
        </section>

        <section id="inventorySection" class="panel info-section" data-mobile-screen="inventory">
          <div class="panel-title"><h3>储物</h3><span class="badge">洞府资源</span></div>
          ${inventoryPanelHtml(inventory, supplyStatus)}
        </section>

        <section id="opportunitySection" class="double-panel-grid">
          <section id="breakthroughPanel" class="panel progression-panel mobile-panel-card" data-mobile-screen="cultivation">
            ${breakthroughPanelHtml(breakthrough, c.cultivation)}
          </section>
          <section id="opportunityPanel" class="panel progression-panel mobile-panel-card" data-mobile-screen="opportunity">
            ${opportunityPanelHtml(opportunity)}
          </section>
        </section>

        <section id="historySection" class="panel" data-mobile-screen="history">
          <div class="panel-title"><h3>命书</h3><span class="badge">最新 100 条</span></div>
          ${historyHtml(bundle.history)}
        </section>

        <nav class="mobile-bottom-nav" aria-label="底部导航">
          <button class="mobile-tab-button ${state.activeMobileTab === 'cultivation' ? 'active' : ''}" type="button" data-mobile-tab="cultivation"><b>修</b><span>修炼</span></button>
          <button class="mobile-tab-button ${state.activeMobileTab === 'techniques' ? 'active' : ''}" type="button" data-mobile-tab="techniques"><b>法</b><span>功法</span></button>
          <button class="mobile-tab-button ${state.activeMobileTab === 'inventory' ? 'active' : ''}" type="button" data-mobile-tab="inventory"><b>物</b><span>储物</span></button>
          <button class="mobile-tab-button ${state.activeMobileTab === 'opportunity' ? 'active' : ''}" type="button" data-mobile-tab="opportunity"><b>缘</b><span>机缘</span></button>
          <button class="mobile-tab-button ${state.activeMobileTab === 'history' ? 'active' : ''}" type="button" data-mobile-tab="history"><b>书</b><span>命书</span></button>
        </nav>
      </section>
    `;

    state.liveCultivationBase = Number(c.cultivation || 0);
    state.liveCultivationStartedAt = Date.now();
    bindProgressionActions();
    bindInventoryTechniqueActions();
    bindMobileDashboardNav();
    const manualSyncBtn = document.getElementById('manualSyncBtn');
    if (manualSyncBtn && manualSyncBtn.dataset.bound !== '1') {
      manualSyncBtn.dataset.bound = '1';
      manualSyncBtn.addEventListener('click', async () => {
        setBusy(manualSyncBtn, true, '同步中…');
        try {
          const alive = await syncCultivation(false);
          if (alive !== false && state.character?.status !== 'dead') {
            await Promise.all([refreshBreakthroughStatus(), refreshOpportunity()]);
            showToast('仙历、寿元与修炼结果均已同步到云端。');
          }
        } catch (error) {
          showToast(translateError(error), 'error');
        } finally {
          setBusy(manualSyncBtn, false);
        }
      });
    }
    startCultivationLoop();
  }

  function bindMobileDashboardNav() {
    const nav = document.querySelector('.mobile-bottom-nav');
    if (!nav) return;
    const buttons = Array.from(nav.querySelectorAll('[data-mobile-tab]'));
    const screens = Array.from(document.querySelectorAll('[data-mobile-screen]'));

    const apply = (tab = state.activeMobileTab || 'cultivation', shouldScroll = false) => {
      state.activeMobileTab = tab;
      const tabbedMode = window.matchMedia('(max-width: 760px), (min-width: 1024px)').matches;
      screens.forEach(screen => {
        screen.classList.toggle('mobile-screen-hidden', tabbedMode && screen.dataset.mobileScreen !== tab);
      });
      buttons.forEach(button => button.classList.toggle('active', button.dataset.mobileTab === tab));
      if (tabbedMode && shouldScroll) window.scrollTo({ top: 0, behavior: 'smooth' });
    };

    buttons.forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => apply(button.dataset.mobileTab || 'cultivation', true));
    });

    apply(state.activeMobileTab || 'cultivation');
    const media = window.matchMedia('(max-width: 760px), (min-width: 1024px)');
    if (media.addEventListener) media.addEventListener('change', () => apply(state.activeMobileTab || 'cultivation'));
  }

  function updateLiveCultivationDisplay() {
    updateGameTimeDisplay();
    const value = document.getElementById('cultivationValue');
    if (!value || !state.cultivationStatus) return;
    const rate = Number(state.cultivationStatus.current_rate_per_second || 0);
    const elapsed = Math.max(0, (Date.now() - state.liveCultivationStartedAt) / 1000);
    value.textContent = formatNumber(Math.floor(state.liveCultivationBase + rate * elapsed));
    const compactText = document.getElementById('breakthroughProgressTextCompact');
    const compactFill = document.getElementById('breakthroughProgressFillCompact');
    if (compactText && state.breakthroughStatus && state.breakthroughStatus.status === 'available') {
      const current = currentDisplayedCultivation();
      const required = Number(state.breakthroughStatus.cultivation_required || 0);
      const percent = required > 0 ? Math.max(0, Math.min(100, current / required * 100)) : 100;
      compactText.textContent = `${formatNumber(current)} / ${formatNumber(required)}`;
      if (compactFill) compactFill.style.width = `${percent}%`;
    }
    updateProgressionDisplay();
  }

  async function syncCultivation(silent = true) {
    if (state.cultivationSyncing || !state.character) return;
    state.cultivationSyncing = true;
    const badge = document.getElementById('cloudSaveBadge');
    if (badge) badge.textContent = '正在同步';
    try {
      const timeStatus = await rpcSettleCharacterTime();
      applyTimeStatus(timeStatus);
      if (timeStatus?.status === 'dead' || timeStatus?.status === 'awaiting_reincarnation') {
        const bundle = await loadCharacterBundle();
        if (bundle) {
          state.character = bundle.character;
          state.details = bundle;
          state.history = bundle.history;
          applyTimeStatus(timeStatus);
          renderDeathScreen(bundle, timeStatus);
        }
        return false;
      }

      const result = await rpcClaimCultivation();
      if (!result) return true;
      state.cultivationStatus = result;
      state.liveCultivationBase = Number(result.cultivation_total || 0);
      state.liveCultivationStartedAt = Date.now();
      state.character.cultivation = result.cultivation_total;
      const rateText = formatRate(result.current_rate_per_second);
      const rateMetric = document.getElementById('cultivationRateText');
      const liveRate = document.getElementById('liveRateValue');
      if (rateMetric) rateMetric.textContent = rateText;
      if (liveRate) liveRate.textContent = rateText;
      updateLiveCultivationDisplay();
      if (Number(result.cultivation_total || 0) >= Number(state.breakthroughStatus?.cultivation_required || Infinity)) {
        refreshBreakthroughStatus();
      }
      if (!silent && Number(result.gained || 0) > 0) {
        showToast(`自动修炼获得 ${formatNumber(result.gained)} 点修为。`);
      }
      if (badge) badge.textContent = '云端已保存';
      return true;
    } catch (error) {
      console.error(error);
      if (badge) badge.textContent = '同步稍后重试';
      if (!silent) throw error;
      return undefined;
    } finally {
      state.cultivationSyncing = false;
    }
  }

  function startCultivationLoop() {
    stopCultivationLoop();
    state.cultivationTicker = setInterval(updateLiveCultivationDisplay, 250);
    state.cultivationSyncTimer = setInterval(() => syncCultivation(true), 15000);
    state.opportunityPollTimer = setInterval(refreshOpportunity, 10000);
    state.opportunityCountdownTimer = setInterval(updateOpportunityCountdown, 1000);
    state.supplyCountdownTimer = setInterval(updateSupplyCountdown, 1000);
    state.techniqueSyncTimer = setInterval(() => refreshTechniqueSystem(false), 60000);
    updateLiveCultivationDisplay();
    updateOpportunityCountdown();
    updateSupplyCountdown();
  }

  function historyHtml(rows) {
    const latestRows = (rows || []).slice(0, 100);
    if (!latestRows.length) return '<div class="empty-state">命书尚为空白。</div>';
    return `<div class="timeline">${latestRows.map(row => `
      <article class="timeline-item">
        <time>仙历 ${escapeHtml(row.world_year)} 年</time>
        <h4>${escapeHtml(row.title)}</h4>
        <p>${escapeHtml(row.content)}</p>
      </article>
    `).join('')}</div>`;
  }

  async function enterGame() {
    app.innerHTML = '<section class="loading-screen"><div class="loader-ring"></div><p>正在校准仙历与云端命书……</p></section>';
    try {
      state.user = await getCurrentUser();
      if (!state.user) {
        renderAuth();
        return;
      }
      await activateGameSession(false);
      state.profile = await loadProfile();
      renderAccount();

      let timeStatus = await rpcSettleCharacterTime();
      if (timeStatus?.status === 'no_character') {
        timeStatus = await rpcGetGameTime();
      }
      applyTimeStatus(timeStatus);

      const bundle = await loadCharacterBundle();
      if (!bundle) {
        state.character = null;
        state.details = null;
        renderCreateCharacter();
        return;
      }

      state.character = bundle.character;
      state.details = bundle;
      state.history = bundle.history;
      applyTimeStatus(timeStatus);

      if (bundle.character.status === 'dead' || timeStatus?.status === 'dead' || timeStatus?.status === 'awaiting_reincarnation') {
        renderDeathScreen(bundle, timeStatus);
        return;
      }

      const cultivationStatus = await rpcClaimCultivation();
      if (cultivationStatus) {
        bundle.cultivationStatus = cultivationStatus;
        bundle.character.cultivation = cultivationStatus.cultivation_total;
      }
      const [breakthroughStatus, opportunityStatus, supplyStatus, techniqueSystem] = await Promise.all([
        rpcGetBreakthroughStatus(),
        rpcGetOpportunity(),
        rpcGetDailySupplyStatus(),
        rpcGetTechniqueSystemV2()
      ]);
      bundle.breakthroughStatus = breakthroughStatus;
      bundle.opportunityStatus = opportunityStatus;
      bundle.supplyStatus = supplyStatus;
      bundle.techniqueSystem = techniqueSystem;
      state.cultivationStatus = cultivationStatus;
      state.breakthroughStatus = breakthroughStatus;
      state.opportunityStatus = opportunityStatus;
      state.supplyStatus = supplyStatus;
      state.techniqueSystem = techniqueSystem;
      renderDashboard(bundle);
    } catch (error) {
      console.error(error);
      if (String(error?.message || '').includes('GAME_SESSION_REPLACED') || String(error?.message || '').includes('GAME_SESSION_REQUIRED')) {
        handleGameSessionReplaced();
        return;
      }
      if (error?.status === 401 || String(error?.message).includes('AUTH_REQUIRED')) {
        clearSession();
        renderAuth();
        showToast('登录状态已失效，请重新登录。', 'error');
        return;
      }
      app.innerHTML = `
        <section class="notice-card">
          <div class="notice-icon">!</div>
          <h2>云端连接失败</h2>
          <p>${escapeHtml(translateError(error))}</p>
          <button id="retryBtn" class="primary-btn" type="button">重新连接</button>
        </section>
      `;
      document.getElementById('retryBtn').addEventListener('click', enterGame);
    }
  }

  async function bootstrap() {
    if (!SUPABASE_URL || !API_KEY) {
      app.innerHTML = '<section class="notice-card"><h2>游戏配置缺失</h2><p>请检查 config.js 中的 Supabase URL 与 Publishable key。</p></section>';
      return;
    }
    importSessionFromHash();
    loadStoredSession();
    document.addEventListener('visibilitychange', async () => {
      if (document.visibilityState !== 'visible') return;
      if (state.gameSessionActive) {
        try {
          const status = await rpcHeartbeatGameSession();
          if (status?.status !== 'active') return handleGameSessionReplaced();
        } catch (error) {
          if (String(error?.message || '').includes('GAME_SESSION')) return handleGameSessionReplaced();
        }
      }
      if (state.character) {
        const alive = await syncCultivation(true);
        if (alive !== false && state.character?.status !== 'dead') {
          await Promise.all([refreshOpportunity(), refreshBreakthroughStatus(), refreshSupplyStatus(), refreshTechniqueSystem(false)]);
        }
      }
    });
    window.addEventListener('focus', async () => {
      if (state.gameSessionActive) {
        try {
          const status = await rpcHeartbeatGameSession();
          if (status?.status !== 'active') return handleGameSessionReplaced();
        } catch (error) {
          if (String(error?.message || '').includes('GAME_SESSION')) return handleGameSessionReplaced();
        }
      }
      if (state.character) {
        const alive = await syncCultivation(true);
        if (alive !== false && state.character?.status !== 'dead') {
          await Promise.all([refreshOpportunity(), refreshBreakthroughStatus(), refreshSupplyStatus(), refreshTechniqueSystem(false)]);
        }
      }
    });
    if (state.session?.access_token) await enterGame();
    else renderAuth();
  }

  bootstrap();
})();
