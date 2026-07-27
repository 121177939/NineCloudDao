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
    lastOpportunityNoticeId: null,
    caveSystem: null,
    caveCountdownTimer: null,
    caveSyncTimer: null,
    caveSyncing: false,
    techniqueSystem: null,
    exclusiveTechniqueSystem: null,
    heavenBalance: null,
    heavenBalanceSyncTimer: null,
    heavenBalanceSyncing: false,
    techniqueSyncTimer: null,
    techniqueSyncing: false,
    destinyRanking: null,
    destinyRankingSyncTimer: null,
    destinyRankingSyncing: false,
    destinyRankingFetchedAt: 0,
    npcSocial: null,
    npcSocialSyncTimer: null,
    npcSocialSyncing: false,
    npcSocialFetchedAt: 0,
    sectSystem: null,
    sectSystemSyncTimer: null,
    sectSystemSyncing: false,
    sectSystemFetchedAt: 0,
    marketSystem: null,
    marketView: 'home',
    casinoView: 'lobby',
    casinoDrafts: {
      house: { stakeType: 'spirit_stone', amount: 100, multiplier: null, game: 'spirit_dice', choice: 'big' },
      duel: { stakeType: 'spirit_stone', amount: 100, multiplier: null, game: 'spirit_fist', choice: 'rock' }
    },
    casinoJoinChoices: {},
    marketSyncing: false,
    marketSyncTimer: null,
    worldEvents: null,
    worldEventsSyncing: false,
    worldEventsSyncTimer: null,
    worldEventsFetchedAt: 0,
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
    if (raw.includes('BREAKTHROUGH_V0130_DISABLED')) return '天劫突破当前处于维护状态，请稍后再试。';
    if (raw.includes('CULTIVATION_FULL_CASINO_BLOCKED')) return '你当前境界修为已经圆满，请先完成突破，再参与修为博弈。';
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
    if (raw.includes('MARKET_DISABLED')) return '万运博弈楼尚未开放。';
    if (raw.includes('CASINO_INSUFFICIENT_SPIRIT_STONES')) return '统一灵石余额不足，无法落注。';
    if (raw.includes('CASINO_INSUFFICIENT_CULTIVATION')) return '可动用修为不足，且不得跌出当前大境界。';
    if (raw.includes('CULTIVATION_STAKE_MINIMUM')) return '修为赌注最低五万点。';
    if (raw.includes('CASINO_CULTIVATION_REQUIRES_NASCENT_SOUL')) return '修为局仅对元婴期及以上修士开放。';
    if (raw.includes('CASINO_CULTIVATION_STAKE_EXCEEDS_TWENTY_PERCENT')) return '单次修为赌注不能超过当前大境界可损失修为的20%。';
    if (raw.includes('CASINO_STAKE_BELOW_MINIMUM')) return '本玩法赌注低于最低限制。';
    if (raw.includes('CASINO_STAKE_ABOVE_MAXIMUM')) return '本玩法赌注超过单局上限。';
    if (raw.includes('CASINO_STAKE_TOO_LARGE')) return '赌注数值过大，请降低后重试。';
    if (raw.includes('CASINO_ACTIVE_DUEL_EXISTS')) return '你已有一张等待或封存中的赌契，请先处理。';
    if (raw.includes('CASINO_INVALID_CHOICE')) return '招式或押注选项无效。';
    if (raw.includes('DUEL_NOT_AVAILABLE')) return '这张赌桌已不可加入。';
    if (raw.includes('DUEL_OWN_TABLE')) return '不能加入自己开设的赌桌。';
    if (raw.includes('DUEL_CANNOT_CANCEL')) return '只有尚未有人应局的自建赌桌可以取消。';
    if (raw.includes('EXCLUSIVE_TECHNIQUE_NOT_FOUND')) return '没有找到这门专属功法。';
    if (raw.includes('EXCLUSIVE_TECHNIQUE_ALREADY_OWNED')) return '这门专属功法已经拥有，无需重复获取。';
    if (raw.includes('EXCLUSIVE_TECHNIQUE_FATE_MISMATCH')) return '此专属功法与当前命格不符，天道已收回并补偿100灵石。';
    if (raw.includes('EXCLUSIVE_SLOT_INVALID')) return '专属槽调整无效，请重新选择。';
    if (raw.includes('EXCLUSIVE_TECHNIQUE_MAX_LEVEL')) return '这门专属功法已经达到最高36级。';
    if (raw.includes('V080_FIXED_REQUIRED')) return 'V0.8.0 功法修正版尚未成功部署，请先执行修正版 SQL 并通过检查。';
    if (raw.includes('CAVE_SETTINGS_MISSING')) return '洞府配置缺失，请重新执行 V0.9.0 数据库升级。';
    if (raw.includes('CAVE_BUILDING_NOT_FOUND')) return '没有找到这座洞府建筑。';
    if (raw.includes('CAVE_BUILDING_MAX_LEVEL')) return '这座洞府建筑已经达到当前最高等级。';
    if (raw.includes('CAVE_INSUFFICIENT_SPIRIT_STONES')) return '灵石不足，无法扩建洞府。';
    if (raw.includes('CAVE_INSUFFICIENT_QI')) return '灵蕴不足，请等待灵脉继续凝聚。';
    if (raw.includes('CAVE_INSUFFICIENT_HERB')) return '灵草不足，请等待灵田继续生长。';
    if (raw.includes('CAVE_INSUFFICIENT_ORE')) return '灵矿不足，请等待矿室继续开采。';
    if (raw.includes('ALCHEMY_DISABLED')) return '炼丹系统目前处于暂停状态。';
    if (raw.includes('INVALID_ALCHEMY_BATCH_COUNT')) return '炼丹份数无效，请选择允许的份数。';
    if (raw.includes('ALCHEMY_RECIPE_NOT_FOUND')) return '没有找到这张丹方。';
    if (raw.includes('ALCHEMY_FURNACE_LEVEL_REQUIRED')) return '丹炉等级不足，尚未掌握这张丹方。';
    if (raw.includes('ALCHEMY_BATCH_ALREADY_ACTIVE')) return '丹炉中已有一炉丹药，出炉并领取后才能再次开炉。';
    if (raw.includes('ALCHEMY_OUTPUT_ITEM_MISSING')) return '丹方对应的物品定义缺失，请检查聚气丹、聚灵香或悟道茶配置。';
    if (raw.includes('ALCHEMY_BATCH_NOT_FOUND')) return '当前没有可以领取的炼丹批次。';
    if (raw.includes('ALCHEMY_NOT_READY')) return '丹药尚未炼成，请等待倒计时结束。';
    if (raw.includes('INVALID_RANKING_PAGE')) return '天命榜分页参数无效，请重新刷新。';
    if (raw.includes('V091_REQUIRED')) return 'V0.9.1天命榜热修复尚未完成，请先部署并检查。';
    if (raw.includes('NPC_SOCIAL_SETTINGS_MISSING')) return '红尘录配置缺失，请执行V0.10.0数据库升级。';
    if (raw.includes('NPC_INTERACTIONS_DISABLED')) return '红尘交游目前处于暂停状态。';
    if (raw.includes('NPC_RELATIONSHIPS_DISABLED')) return '关系缔结目前处于暂停状态。';
    if (raw.includes('NPC_CONTACT_NOT_FOUND')) return '没有找到这位红尘故人，请重新读取。';
    if (raw.includes('INVALID_NPC_ACTION')) return '交游方式无效，请重新选择。';
    if (raw.includes('NPC_INTERACTION_COOLDOWN')) return '刚刚交谈过，请等待片刻再来往。';
    if (raw.includes('NPC_GIFT_INSUFFICIENT_SPIRIT_STONES')) return '灵石不足，无法准备这份赠礼。';
    if (raw.includes('NPC_GUIDANCE_RELATION_REQUIRED')) return '双方交情与信任尚不足以开口请教。';
    if (raw.includes('NPC_GUIDANCE_COOLDOWN')) return '今日指点尚需消化，请稍后再来。';
    if (raw.includes('INVALID_NPC_RELATIONSHIP')) return '关系类型无效。';
    if (raw.includes('NPC_RELATIONSHIP_HOSTILE')) return '双方已成仇敌，无法缔结正向关系。';
    if (raw.includes('NPC_MASTER_REQUIREMENTS')) return '拜师需要对方修为足够，并达到好感45、信任40。';
    if (raw.includes('NPC_MASTER_ALREADY_EXISTS')) return '你当前已经有一位师尊。';
    if (raw.includes('NPC_PARTNER_REQUIREMENTS')) return '结为道侣需要好感75、信任60。';
    if (raw.includes('NPC_PARTNER_ALREADY_EXISTS')) return '你当前已经有一位道侣。';
    if (raw.includes('NPC_SWORN_FRIEND_REQUIREMENTS')) return '义结金兰需要好感60、信任50。';
    if (raw.includes('V010_REQUIRED')) return 'V0.10.0红尘录尚未成功部署，请先完成数据库升级。';
    if (raw.includes('SECT_SETTINGS_MISSING')) return '宗门配置缺失，请执行V0.11.0数据库升级。';
    if (raw.includes('SECT_JOINING_DISABLED')) return '宗门收徒目前处于暂停状态。';
    if (raw.includes('SECT_CREATION_DISABLED')) return '开山立派目前处于暂停状态。';
    if (raw.includes('SECT_TASKS_DISABLED')) return '宗门事务目前处于暂停状态。';
    if (raw.includes('SECT_STIPEND_DISABLED')) return '宗门俸禄目前处于暂停状态。';
    if (raw.includes('SECT_BUILDINGS_DISABLED')) return '宗门建筑目前处于暂停状态。';
    if (raw.includes('INVALID_SECT_CODE')) return '宗门编号无效，请重新选择。';
    if (raw.includes('SECT_MEMBERSHIP_ALREADY_EXISTS')) return '你当前已经加入一个宗门。';
    if (raw.includes('SECT_NOT_FOUND')) return '没有找到这个宗门，请刷新宗门录。';
    if (raw.includes('INVALID_SECT_NAME')) return '宗门名称需要2—16个字符。';
    if (raw.includes('DUPLICATE_SECT_NAME')) return '这个宗门名称已经存在，请换一个名字。';
    if (raw.includes('SECT_CREATION_INSUFFICIENT_SPIRIT_STONES')) return '灵石不足，无法开山立派。';
    if (raw.includes('SECT_MEMBERSHIP_REQUIRED')) return '你尚未加入宗门。';
    if (raw.includes('SECT_TASK_NOT_FOUND')) return '没有找到这项宗门事务。';
    if (raw.includes('SECT_TASK_ALREADY_COMPLETED')) return '这项宗门事务今日已经完成。';
    if (raw.includes('SECT_TASK_INSUFFICIENT_SPIRIT_STONES')) return '灵石不足，无法完成捐献事务。';
    if (raw.includes('SECT_STIPEND_ALREADY_CLAIMED')) return '今日宗门俸禄已经领取。';
    if (raw.includes('SECT_TREASURY_INSUFFICIENT')) return '宗门库藏不足，暂时无法完成此操作。';
    if (raw.includes('SECT_BUILDING_PERMISSION_REQUIRED')) return '至少成为核心弟子，才能主持扩建宗门建筑。';
    if (raw.includes('SECT_BUILDING_NOT_FOUND')) return '没有找到这座宗门建筑。';
    if (raw.includes('SECT_BUILDING_MAX_LEVEL')) return '这座宗门建筑已经达到当前上限。';
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
    if (state.caveCountdownTimer) clearInterval(state.caveCountdownTimer);
    if (state.caveSyncTimer) clearInterval(state.caveSyncTimer);
    if (state.techniqueSyncTimer) clearInterval(state.techniqueSyncTimer);
    if (state.heavenBalanceSyncTimer) clearInterval(state.heavenBalanceSyncTimer);
    if (state.destinyRankingSyncTimer) clearInterval(state.destinyRankingSyncTimer);
    if (state.npcSocialSyncTimer) clearInterval(state.npcSocialSyncTimer);
    if (state.sectSystemSyncTimer) clearInterval(state.sectSystemSyncTimer);
    if (state.marketSyncTimer) clearInterval(state.marketSyncTimer);
    if (state.worldEventsSyncTimer) clearInterval(state.worldEventsSyncTimer);
    if (state.gameSessionHeartbeatTimer) clearInterval(state.gameSessionHeartbeatTimer);
    state.cultivationTicker = null;
    state.cultivationSyncTimer = null;
    state.opportunityPollTimer = null;
    state.opportunityCountdownTimer = null;
    state.caveCountdownTimer = null;
    state.caveSyncTimer = null;
    state.techniqueSyncTimer = null;
    state.heavenBalanceSyncTimer = null;
    state.destinyRankingSyncTimer = null;
    state.npcSocialSyncTimer = null;
    state.sectSystemSyncTimer = null;
    state.marketSyncTimer = null;
    state.worldEventsSyncTimer = null;
    state.gameSessionHeartbeatTimer = null;
    state.cultivationSyncing = false;
    state.opportunitySyncing = false;
    state.caveSyncing = false;
    state.techniqueSyncing = false;
    state.heavenBalanceSyncing = false;
    state.destinyRankingSyncing = false;
    state.npcSocialSyncing = false;
    state.sectSystemSyncing = false;
    state.marketSyncing = false;
    state.worldEventsSyncing = false;
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
    state.lastOpportunityNoticeId = null;
    state.caveSystem = null;
    state.techniqueSystem = null;
    state.exclusiveTechniqueSystem = null;
    state.heavenBalance = null;
    state.destinyRanking = null;
    state.destinyRankingFetchedAt = 0;
    state.npcSocial = null;
    state.npcSocialFetchedAt = 0;
    state.sectSystem = null;
    state.sectSystemFetchedAt = 0;
    state.timeStatus = null;
    state.timeStatusStartedAt = 0;
    state.timeSyncing = false;
    state.deathHandled = false;
    state.gameSessionActive = false;
    state.activeMobileTab = 'cultivation';
    state.marketSystem = null;
    state.marketView = 'home';
    state.casinoView = 'lobby';
    state.marketSyncing = false;
    state.worldEvents = null;
    state.worldEventsSyncing = false;
    state.worldEventsFetchedAt = 0;
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

  async function rpcGetMarketV1() {
    const result = await restFetch('rpc/get_market_v1', { method: 'POST', body: {} });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcGetWorldEventsV1(limit = 20) {
    const result = await restFetch('rpc/get_world_events_v1', {
      method: 'POST',
      body: { p_limit: Number(limit) }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcPlayHouseGameV1(gameCode, stakeType, stakeAmount, choice) {
    const result = await restFetch('rpc/play_house_game_v1', { method: 'POST', body: {
      p_game_code: gameCode, p_stake_type: stakeType, p_stake_amount: Number(stakeAmount), p_choice: choice
    }});
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcCreateDuelV1(gameCode, stakeType, stakeAmount, choice) {
    const result = await restFetch('rpc/create_duel_v1', { method: 'POST', body: {
      p_game_code: gameCode, p_stake_type: stakeType, p_stake_amount: Number(stakeAmount), p_choice: choice
    }});
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcJoinDuelV1(duelId, choice) {
    const result = await restFetch('rpc/join_duel_v1', { method: 'POST', body: { p_duel_id: duelId, p_choice: choice }});
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcCancelDuelV1(duelId) {
    const result = await restFetch('rpc/cancel_duel_v1', { method: 'POST', body: { p_duel_id: duelId }});
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcGetSpiritStoneBalanceV0141() {
    const result = await restFetch('rpc/get_spirit_stone_balance_v0141', { method: 'POST', body: {} });
    const value = Array.isArray(result) ? result[0] : result;
    return Math.max(0, Number(value || 0));
  }

  function setLocalSpiritStoneBalance(amount) {
    const normalized = Math.max(0, Number(amount || 0));
    if (!state.details) return normalized;
    if (!Array.isArray(state.details.inventory)) state.details.inventory = [];
    let row = state.details.inventory.find(item => item.definition?.code === 'spirit_stone');
    if (!row) {
      row = {
        id: 'canonical-spirit-stone-v0141',
        item_definition_id: 'canonical-spirit-stone-v0141',
        quantity: normalized,
        is_bound: false,
        item_instance: {},
        acquired_year: 1,
        definition: {
          id: 'canonical-spirit-stone-v0141',
          code: 'spirit_stone',
          name: '灵石',
          category: 'currency',
          rarity: 'common',
          stack_limit: 2147483647,
          effects: {},
          description: '九霄界唯一通用货币。'
        }
      };
      state.details.inventory.unshift(row);
    }
    row.quantity = normalized;
    row.is_bound = false;
    if (state.marketSystem?.character) state.marketSystem.character.spirit_stones = normalized;
    document.querySelectorAll('[data-spirit-stone-balance]').forEach(node => {
      node.textContent = formatNumber(normalized);
    });
    return normalized;
  }

  async function refreshSpiritStoneBalanceV0141(silent = true) {
    try {
      const amount = await rpcGetSpiritStoneBalanceV0141();
      setLocalSpiritStoneBalance(amount);
      return amount;
    } catch (error) {
      if (!silent) showToast(translateError(error), 'error');
      return null;
    }
  }

  async function refreshMarketSystem(silent = false) {
    if (state.marketSyncing) return state.marketSystem;
    captureCasinoUiDrafts();
    state.marketSyncing = true;
    try {
      state.marketSystem = await rpcGetMarketV1();
      if (Number.isFinite(Number(state.marketSystem?.character?.spirit_stones))) {
        setLocalSpiritStoneBalance(Number(state.marketSystem.character.spirit_stones));
      }
      const host = document.getElementById('marketPanelHost');
      if (host) { host.innerHTML = marketPanelHtml(state.marketSystem || {}, state.casinoView || 'lobby'); bindMarketActions(); }
      return state.marketSystem;
    } catch (error) {
      if (!silent) showToast(translateError(error), 'error');
      return state.marketSystem;
    } finally { state.marketSyncing = false; }
  }

  async function refreshWorldEvents(silent = false) {
    if (state.worldEventsSyncing || !state.character || document.hidden) return state.worldEvents;
    state.worldEventsSyncing = true;
    try {
      state.worldEvents = await rpcGetWorldEventsV1(20);
      state.worldEventsFetchedAt = Date.now();
      updateWorldEventsPanel();
      return state.worldEvents;
    } catch (error) {
      state.worldEvents = {
        status: 'unavailable',
        entries: [],
        error: translateError(error)
      };
      updateWorldEventsPanel();
      if (!silent) showToast(translateError(error), 'error');
      return state.worldEvents;
    } finally {
      state.worldEventsSyncing = false;
    }
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

  async function rpcGetHeavenBalanceV1() {
    const result = await restFetch('rpc/get_heaven_balance_v1', {
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
    const result = await restFetch('rpc/get_auto_opportunity_v3', {
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

  async function rpcUseInventoryItem(inventoryId) {
    const result = await restFetch('rpc/use_inventory_item_v1', {
      method: 'POST',
      body: { p_inventory_id: inventoryId }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcGetCaveSystemV1() {
    const result = await restFetch('rpc/get_cave_system_v1', {
      method: 'POST',
      body: {}
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcUpgradeCaveBuildingV1(buildingCode) {
    const result = await restFetch('rpc/upgrade_cave_building_v1', {
      method: 'POST',
      body: { p_building_code: buildingCode }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcStartAlchemyV1(recipeCode, batchCount = 1) {
    const result = await restFetch('rpc/start_alchemy_v1', {
      method: 'POST',
      body: { p_recipe_code: recipeCode, p_batch_count: Number(batchCount || 1) }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcClaimAlchemyV1() {
    const result = await restFetch('rpc/claim_alchemy_v1', {
      method: 'POST',
      body: {}
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcGetDestinyRankingV1(limit = 50, offset = 0) {
    const result = await restFetch('rpc/get_destiny_ranking_v1', {
      method: 'POST',
      body: {
        p_limit: Math.max(1, Math.min(100, Number(limit || 50))),
        p_offset: Math.max(0, Number(offset || 0))
      }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcGetNpcSocialV1() {
    const result = await restFetch('rpc/get_npc_social_v1', {
      method: 'POST',
      body: {}
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcInteractWithNpcV1(npcId, action) {
    const result = await restFetch('rpc/interact_with_npc_v1', {
      method: 'POST',
      body: { p_npc_id: npcId, p_action: action }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcFormNpcRelationshipV1(npcId, relationshipType) {
    const result = await restFetch('rpc/form_npc_relationship_v1', {
      method: 'POST',
      body: { p_npc_id: npcId, p_relationship_type: relationshipType }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcGetSectSystemV1() {
    const result = await restFetch('rpc/get_sect_system_v1', { method: 'POST', body: {} });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcJoinSectV1(sectCode) {
    const result = await restFetch('rpc/join_sect_v1', { method: 'POST', body: { p_sect_code: sectCode } });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcCreateSectV1(name, motto, element) {
    const result = await restFetch('rpc/create_sect_v1', { method: 'POST', body: { p_name: name, p_motto: motto, p_element: element } });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcCompleteSectTaskV1(taskCode) {
    const result = await restFetch('rpc/complete_sect_task_v1', { method: 'POST', body: { p_task_code: taskCode } });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcClaimSectStipendV1() {
    const result = await restFetch('rpc/claim_sect_stipend_v1', { method: 'POST', body: {} });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcUpgradeSectBuildingV1(buildingCode) {
    const result = await restFetch('rpc/upgrade_sect_building_v1', { method: 'POST', body: { p_building_code: buildingCode } });
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

  async function rpcGetExclusiveTechniqueSystemV1() {
    const result = await restFetch('rpc/get_exclusive_technique_system_v1', { method: 'POST', body: {} });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcSetExclusiveTechniqueSlotV1(characterExclusiveId) {
    const result = await restFetch('rpc/set_exclusive_technique_slot_v1', {
      method: 'POST',
      body: { p_character_exclusive_id: characterExclusiveId || null }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcUpgradeExclusiveTechniqueV1(characterExclusiveId) {
    const result = await restFetch('rpc/upgrade_exclusive_technique_v1', {
      method: 'POST',
      body: { p_character_exclusive_id: characterExclusiveId }
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

  function mergeCanonicalSpiritStoneInventory(rows = []) {
    const source = Array.isArray(rows) ? rows : [];
    const stones = source.filter(row => row.definition?.code === 'spirit_stone');
    if (!stones.length) return source;
    const total = stones.reduce((sum, row) => sum + Math.max(0, Number(row.quantity || 0)), 0);
    const canonical = {
      ...stones[0],
      quantity: total,
      is_bound: false,
      item_instance: {},
      definition: { ...stones[0].definition, code: 'spirit_stone', name: stones[0].definition?.name || '灵石' }
    };
    return [canonical, ...source.filter(row => row.definition?.code !== 'spirit_stone')];
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
        select: 'id,code,name,rarity,cultivation_multiplier,combat_multiplier,event_luck_bonus,description',
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
    const inventory = mergeCanonicalSpiritStoneInventory((Array.isArray(inventoryLinks) ? inventoryLinks : []).map(link => ({
      ...link,
      definition: itemMap.get(link.item_definition_id) || null
    })).filter(row => row.definition && Number(row.quantity || 0) > 0));

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
    const estimated = Math.floor(state.liveCultivationBase + rate * elapsed);
    const cap = Number(state.breakthroughStatus?.cultivation_cap || state.breakthroughStatus?.cultivation_required || 0);
    return cap > 0 ? Math.min(estimated, cap) : estimated;
  }

  function breakthroughPanelHtml(status, cultivationValue) {
    if (!status || status.status === 'loading') return '<div class="empty-state">天道正在推演下一重道关……</div>';
    if (status.status === 'maximum') return `<div class="panel-title"><h3>境界突破</h3><span class="badge">道途已尽</span></div><div class="breakthrough-card"><strong>${escapeHtml(status.current_stage_name || '未知境界')}</strong><p>当前版本尚未开放更高境界。</p></div>`;
    if (status.status === 'disabled') return `<div class="panel-title"><h3>境界突破</h3><span class="badge">维护中</span></div><div class="breakthrough-card"><p>天劫突破当前处于维护状态。修为上限保护仍然生效。</p></div>`;
    const required = Number(status.cultivation_cap || status.cultivation_required || 0);
    const current = Math.min(Number(cultivationValue ?? status.cultivation_total ?? 0), required || Number.MAX_SAFE_INTEGER);
    const percent = required > 0 ? Math.max(0, Math.min(100, current / required * 100)) : 100;
    const canBreakthrough = current >= required;
    const insights = Number(status.heavenly_insight_count || 0);
    const insightBonus = Number(status.compensation_bonus || insights * 0.05);
    return `
      <div class="panel-title"><h3>境界突破</h3><span class="badge">目标 · ${escapeHtml(status.next_stage_name || '未知')}</span></div>
      <div class="breakthrough-card ${canBreakthrough ? 'cultivation-full' : ''}">
        <div class="breakthrough-heading"><div><span>下一道关</span><strong>${escapeHtml(status.next_stage_name || '未知境界')}</strong></div><div class="chance-orb"><small>本次成功率</small><b>${formatNumber(Number(status.success_rate || 0) * 100, 1)}%</b></div></div>
        <div class="progress-label"><span>${canBreakthrough ? '修为已至圆满' : '累计修为'}</span><strong id="breakthroughProgressText">${formatNumber(current)} / ${formatNumber(required)}</strong></div>
        <div class="progress-track"><div id="breakthroughProgressFill" class="progress-fill" style="width:${percent}%"></div></div>
        ${canBreakthrough ? '<div class="cultivation-full-notice"><strong>修为已至圆满</strong><p>丹田灵力已臻当前境界极限，再行吐纳亦无法寸进。唯有叩问天关、完成突破，方可继续修行。</p></div>' : ''}
        <div class="breakthrough-meta">
          <span>基础成功率：${formatNumber(Number(status.base_success_rate || 0) * 100, 1)}%</span>
          <span>天劫感悟：${formatNumber(insights)}丝（+${formatNumber(insightBonus * 100, 0)}个百分点）</span>
          <span>最终成功率上限：${formatNumber(Number(status.compensation_cap || 0.8) * 100, 0)}%</span>
          ${status.original_target_stage_name ? `<span>感悟绑定目标：${escapeHtml(status.original_target_stage_name)}；真正抵达后清除</span>` : '<span>实际受到失败惩罚后，天劫感悟+1丝，目标突破率+5%</span>'}
          <span>失败结果：身死0.5% · 大跌境5% · 小跌境8% · 全损15% · 半损30% · 有惊无险41.5%</span>
          <span>有惊无险、死亡及保护生效时不增加天劫感悟</span>
          ${status.penalty_enabled === false ? '<span>元婴以下保护：失败不死亡、不跌境、不扣修为、不增加感悟</span>' : '<span>元婴期及以上：完整天劫失败结果生效</span>'}
          ${status.major_fall_used ? `<span>大跌境锁：已触发；回到${escapeHtml(status.major_fall_origin_stage_name || '原始大境界')}后解除</span>` : '<span>同一恢复周期最多真正跌落一次大境界</span>'}
        </div>
        <button id="attemptBreakthroughBtn" class="primary-btn full" type="button" ${canBreakthrough ? '' : 'disabled'}>${canBreakthrough ? `冲击${escapeHtml(status.next_stage_name || '境界')}` : `尚缺 ${formatNumber(Math.max(0, required - current))} 修为`}</button>
      </div>`;
  }

  function latestOpportunityResult(opportunity) {
    if (!opportunity || !opportunity.last_result || typeof opportunity.last_result !== 'object') return null;
    return opportunity.last_result;
  }

  function formatHeavenCoefficient(value) {
    const n = Number(value || 1);
    return Number.isInteger(n) ? String(n) : formatNumber(n, 1);
  }

  function normalizeHeavenBalance(balance, cultivation = state.cultivationStatus || {}) {
    if (balance && balance.status && balance.status !== 'unavailable') return balance;
    const coefficient = Number(cultivation.qi_multiplier || 1);
    const statusCode = coefficient > 1 ? 'heavenly_blessing' : coefficient < 1 ? 'heaven_obstruction' : 'dao_balance';
    const statusName = statusCode === 'heavenly_blessing' ? '天道福泽' : statusCode === 'heaven_obstruction' ? '天道阻滞' : '大道均衡';
    return {
      status: 'fallback',
      status_code: statusCode,
      status_name: statusName,
      reason_label: statusCode === 'heavenly_blessing'
        ? '低修为，拥有灵气加成'
        : statusCode === 'heaven_obstruction'
          ? '高修为，灵气收益衰减'
          : '修为贴近全服平均，无加成无压制',
      coefficient,
      world_qi_base: 1,
      qi_gain_per_second: coefficient,
      player_realm_name: state.details?.realm?.name || '当前境界',
      mainstream_realm_name: '全服主流境界',
      realm_gap: 0,
      active_population: 0
    };
  }

  function heavenBalanceCopy(balance) {
    const code = balance?.status_code || 'dao_balance';
    if (code === 'heavenly_blessing') {
      return {
        title: '天道福泽触发',
        paragraphs: [
          '冥冥天道有感世间修士修为失衡，大道运转趋于不均。',
          '汝境界尚低于天下主流修士，天地灵气流露眷顾，降下天道福泽。',
          '吸纳灵气之时感悟倍增，修行速度获得增幅。'
        ]
      };
    }
    if (code === 'heaven_obstruction') {
      return {
        title: '天道阻滞触发',
        paragraphs: [
          '大道有序，不允修士无限凌驾众生。',
          '汝境界远超世间主流修士，引动天地制衡，受天道阻滞。',
          '感悟大道愈发艰难，吸纳灵气效率受到限制。'
        ]
      };
    }
    return {
      title: '大道均衡',
      paragraphs: [
        '天道循环，大道均衡。',
        '汝修为与世间主流修士相近，不受福泽加持，亦无天道桎梏。',
        '吸纳灵气遵循常道，修行平稳有序。'
      ]
    };
  }

  function heavenBalanceModalHtml(rawBalance) {
    const balance = normalizeHeavenBalance(rawBalance);
    const copy = heavenBalanceCopy(balance);
    const coefficient = Number(balance.coefficient || 1);
    const qiBase = Number(balance.world_qi_base || 1);
    const effectiveMultiplier = Number(balance.qi_gain_per_second ?? qiBase * coefficient);
    const code = escapeHtml(balance.status_code || 'dao_balance');
    return `
      <div class="heaven-balance-dialog state-${code}">
        <div class="heaven-balance-seal">道</div>
        <span class="eyebrow">九霄天道 · 动态均衡</span>
        <h2 id="heavenBalanceModalTitle">${escapeHtml(copy.title)}</h2>
        <strong class="heaven-balance-reason">${escapeHtml(balance.reason_label || '')}</strong>
        <div class="heaven-balance-lore">
          ${copy.paragraphs.map(text => `<p>${escapeHtml(text)}</p>`).join('')}
        </div>
        <div class="heaven-balance-current">
          <span>当前灵气效率</span>
          <strong>×${formatHeavenCoefficient(coefficient)}</strong>
          <small>世界灵气 ${formatNumber(qiBase, 2)} × 天道系数 ${formatHeavenCoefficient(coefficient)} = 当前自动修炼总倍率 ×${formatHeavenCoefficient(effectiveMultiplier)}</small>
        </div>
        <div class="heaven-balance-meta">
          <div><span>你的境界</span><strong>${escapeHtml(balance.player_realm_name || '未知')}</strong></div>
          <div><span>全服主流境界</span><strong>${escapeHtml(balance.mainstream_realm_name || '未知')}</strong></div>
          <div><span>境界差</span><strong>${Number(balance.realm_gap || 0) > 0 ? '+' : ''}${formatNumber(balance.realm_gap || 0, 0)}</strong></div>
          <div><span>统计修士</span><strong>${formatNumber(balance.active_population || 0, 0)} 人</strong></div>
        </div>
        <div class="heaven-balance-rule-table" aria-label="天道动态均衡系数规则">
          <div><span>低于主流5境及以上</span><strong>×5.0</strong></div>
          <div><span>低4境</span><strong>×4.0</strong></div>
          <div><span>低3境</span><strong>×3.0</strong></div>
          <div><span>低2境</span><strong>×2.0</strong></div>
          <div><span>低1境</span><strong>×1.2</strong></div>
          <div><span>贴近主流</span><strong>×1.0</strong></div>
          <div><span>高1境</span><strong>×0.8</strong></div>
          <div><span>高2境</span><strong>×0.6</strong></div>
          <div><span>高3境及以上</span><strong>×0.5</strong></div>
        </div>
        <p class="heaven-balance-note">天道福泽、均衡或阻滞会作用于当前全部自动修炼收益。×0.5表示最终速度约为原速度的一半，×5表示最终速度约为原速度的五倍。</p>
      </div>
    `;
  }

  function openHeavenBalanceModal() {
    modalRoot.innerHTML = `
      <div id="heavenBalanceModalBackdrop" class="modal-backdrop heaven-balance-modal-backdrop">
        <section class="modal heaven-balance-modal" role="dialog" aria-modal="true" aria-labelledby="heavenBalanceModalTitle">
          <button id="closeHeavenBalanceModalBtn" class="modal-close-button" type="button" aria-label="关闭天道规则窗口">×</button>
          <div id="heavenBalanceModalBody">${heavenBalanceModalHtml(state.heavenBalance)}</div>
        </section>
      </div>
    `;
    const close = () => { modalRoot.innerHTML = ''; };
    document.getElementById('closeHeavenBalanceModalBtn')?.addEventListener('click', close);
    document.getElementById('heavenBalanceModalBackdrop')?.addEventListener('click', event => {
      if (event.target?.id === 'heavenBalanceModalBackdrop') close();
    });
  }

  function bindHeavenBalanceActions() {
    const entry = document.getElementById('heavenBalanceBtn');
    if (!entry || entry.dataset.bound === '1') return;
    entry.dataset.bound = '1';
    entry.addEventListener('click', openHeavenBalanceModal);
  }

  function updateHeavenBalanceEntry() {
    const entry = document.getElementById('heavenBalanceBtn');
    if (!entry) return;
    const balance = normalizeHeavenBalance(state.heavenBalance);
    const coefficient = Number(balance.coefficient || 1);
    entry.className = 'heaven-balance-entry';
    entry.innerHTML = `<span class="heaven-balance-entry-text">灵气环境（${escapeHtml(balance.status_name || '大道均衡')}）x${formatHeavenCoefficient(coefficient)}</span>`;
    entry.setAttribute('aria-label', `查看${balance.status_name || '大道均衡'}规则，当前灵气效率${formatNumber(coefficient, 1)}倍`);
  }

  async function refreshHeavenBalance(silent = true) {
    if (!state.character || state.heavenBalanceSyncing) return state.heavenBalance;
    state.heavenBalanceSyncing = true;
    try {
      state.heavenBalance = await rpcGetHeavenBalanceV1();
      updateHeavenBalanceEntry();
      const modalBody = document.getElementById('heavenBalanceModalBody');
      if (modalBody) modalBody.innerHTML = heavenBalanceModalHtml(state.heavenBalance);
      return state.heavenBalance;
    } catch (error) {
      console.error(error);
      if (!silent) showToast(translateError(error), 'error');
      return state.heavenBalance;
    } finally {
      state.heavenBalanceSyncing = false;
    }
  }

  function opportunityWheelHtml() {
    return `
      <div class="opportunity-wheel" aria-hidden="true">
        <div class="opportunity-wheel-outer">
          <i class="opportunity-wheel-dot dot-1"></i>
          <i class="opportunity-wheel-dot dot-2"></i>
          <i class="opportunity-wheel-dot dot-3"></i>
        </div>
        <div class="opportunity-wheel-inner"></div>
        <div class="opportunity-wheel-core">机</div>
      </div>
    `;
  }

  function opportunityEntryContentHtml(opportunity) {
    const result = latestOpportunityResult(opportunity);
    const nextAt = opportunity?.next_available_at ? new Date(opportunity.next_available_at) : null;
    const seconds = nextAt ? Math.max(0, Math.ceil((nextAt.getTime() - Date.now()) / 1000)) : Math.max(0, Number(opportunity?.seconds_until_next || 0));
    return `
      <span class="opportunity-auto-mark">自主推演天机</span>
      ${opportunityWheelHtml()}
      <div class="focus-caption opportunity-entry-copy">
        <strong>下一次机缘</strong>
        <span id="opportunityEntryCountdown">${formatDuration(seconds)}</span>
        <small>角色正在自主推演天机${result ? ` · 最近：${escapeHtml(result.title || '无名机缘')}` : ''}</small>
      </div>
    `;
  }

  function updateOpportunityEntry() {
    const entry = document.getElementById('opportunityEntryBtn');
    if (!entry) return;
    entry.classList.toggle('has-opportunity', Boolean(latestOpportunityResult(state.opportunityStatus)));
    entry.setAttribute('aria-label', '查看最近一次机缘结果摘要');
    entry.innerHTML = opportunityEntryContentHtml(state.opportunityStatus);
  }

  function openOpportunityModal() {
    modalRoot.innerHTML = `
      <div id="opportunityModalBackdrop" class="modal-backdrop opportunity-modal-backdrop">
        <section class="modal opportunity-modal" role="dialog" aria-modal="true" aria-labelledby="opportunityModalTitle">
          <button id="closeOpportunityModalBtn" class="modal-close-button" type="button" aria-label="关闭机缘窗口">×</button>
          <div id="opportunityModalBody">${opportunityPanelHtml(state.opportunityStatus || { status: 'loading' })}</div>
        </section>
      </div>
    `;
    const close = () => { modalRoot.innerHTML = ''; };
    document.getElementById('closeOpportunityModalBtn')?.addEventListener('click', close);
    document.getElementById('opportunityModalBackdrop')?.addEventListener('click', event => {
      if (event.target?.id === 'opportunityModalBackdrop') close();
    });
    bindProgressionActions();
    updateOpportunityCountdown();
  }

  function bindOpportunityEntryActions() {
    const entry = document.getElementById('opportunityEntryBtn');
    if (!entry || entry.dataset.bound === '1') return;
    entry.dataset.bound = '1';
    entry.addEventListener('click', openOpportunityModal);
  }

  function opportunityPanelHtml(opportunity) {
    if (!opportunity || opportunity.status === 'loading') {
      return '<div class="empty-state">天机未显，正在观测灵气变化……</div>';
    }
    const result = latestOpportunityResult(opportunity);
    const nextAt = opportunity.next_available_at ? new Date(opportunity.next_available_at) : null;
    const seconds = nextAt ? Math.max(0, Math.ceil((nextAt.getTime() - Date.now()) / 1000)) : Math.max(0, Number(opportunity.seconds_until_next || 0));
    const rarity = result?.rarity || result?.rarity_name || 'common';
    const rarityLabel = result?.rarity_name || rarityName(rarity);
    const currentAuspiciousProbability = Math.max(0, Math.min(100, Number(opportunity?.auspicious_probability ?? result?.auspicious_probability ?? 50)));
    const currentRiskProbability = Math.max(0, Math.min(100, Number(opportunity?.risk_probability ?? result?.risk_probability ?? (100 - currentAuspiciousProbability))));
    const luckyBonus = Number(opportunity?.lucky_auspicious_bonus ?? result?.lucky_auspicious_bonus ?? 0);
    const isRisk = result?.path_name === '涉险';
    const outcomeLabel = isRisk ? '涉险代价' : '趋吉所得';
    const outcomeText = isRisk ? (result?.penalty_text || '本次涉险未记录具体代价') : (result?.reward_text || '本次趋吉结果已自动结算');
    return `
      <div class="panel-title"><h3>天机推演</h3><span class="badge ${result ? `rarity-${escapeHtml(rarity)}` : ''}">${escapeHtml(result ? rarityLabel : '天机流转')}</span></div>
      <div class="opportunity-waiting opportunity-summary-panel">
        ${opportunityWheelHtml()}
        <strong>角色正在自主推演天机</strong>
        <p>下一次机缘将在 <span id="opportunityCountdown" class="inline-countdown">${formatDuration(seconds)}</span> 后自动结算，无需手动抽取、选择或领取。</p>
        <div class="opportunity-probability-line">
          <span>趋吉 ${formatNumber(currentAuspiciousProbability, 1)}%</span>
          <span>涉险 ${formatNumber(currentRiskProbability, 1)}%</span>
          ${luckyBonus > 0 ? `<small>机缘深厚：趋吉额外 +${formatNumber(luckyBonus, 0)} 个百分点</small>` : ''}
        </div>
        ${result ? `
          <article class="opportunity-result-summary ${isRisk ? 'risk-result' : 'auspicious-result'}">
            <span class="eyebrow">最近一次机缘结果</span>
            <h4>${escapeHtml(result.title || '无名机缘')}</h4>
            <p>${escapeHtml(result.content || '天机流转，道痕已留。')}</p>
            <div class="result-summary-grid polarity-grid">
              <div><span>品级</span><strong>${escapeHtml(rarityLabel)}</strong></div>
              <div><span>路径</span><strong>${escapeHtml(result.path_name || '天机自决')}</strong></div>
              <div class="polarity-outcome"><span>${escapeHtml(outcomeLabel)}</span><strong>${escapeHtml(outcomeText)}</strong></div>
            </div>
            <small>每次机缘只会结算一种方向：趋吉只有奖励，涉险只有代价。</small>
          </article>
        ` : `
          <small>暂无最近机缘结果，系统会在倒计时结束后自动推演并结算。</small>
        `}
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

  function breakthroughOutcomeName(code) {
    const names = { death:'身死道消', major_fall:'大境跌落', minor_fall:'小境跌落', stage_reset:'道基受挫', stage_half:'灵力溃散', no_loss:'有惊无险', low_realm_no_penalty:'天道护持', major_fall_guarded:'大跌境保护', realm_floor_guarded:'元婴下限保护' };
    return names[code] || '冲关未成';
  }

  function applyLocalCultivationGain(gain) {
    const requested = Math.max(0, Number(gain || 0));
    const cap = Number(state.breakthroughStatus?.cultivation_cap || state.breakthroughStatus?.cultivation_required || 0);
    const current = Number(state.character?.cultivation || state.liveCultivationBase || 0);
    const accepted = cap > 0 ? Math.min(requested, Math.max(0, cap - current)) : requested;
    state.liveCultivationBase = Math.min(cap > 0 ? cap : Number.MAX_SAFE_INTEGER, Number(state.liveCultivationBase || current) + accepted);
    if (state.character) state.character.cultivation = current + accepted;
    return accepted;
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
            title: result?.success ? `突破成功 · ${result.target_stage_name}` : `突破失败 · ${breakthroughOutcomeName(result?.outcome_code)}`,
            message: result?.message || (result?.success ? '道关已开。' : '此番冲关未成。'),
            detail: result?.success
              ? `${Number(result.lifespan_bonus || 0) > 0 ? `寿元增加 ${formatNumber(result.lifespan_bonus)} 年。` : ''}${result.affliction_name ? ` 当前状态：${result.affliction_name}。` : ''}${Number(result.heavenly_insight_count || 0) > 0 ? ` 天劫感悟仍保留 ${formatNumber(result.heavenly_insight_count)} 丝，直到抵达原始目标。` : ' 抵达原始目标后，天劫感悟已经清除。'}`
              : `${Number(result.cultivation_lost || 0) > 0 ? `修为损失 ${formatNumber(result.cultivation_lost)}，当前修为 ${formatNumber(result.cultivation_after)}。` : '境界与修为没有额外损失。'}${result.affliction_name ? ` 状态：${result.affliction_name}。` : ''}${result.insight_gained ? ` 天劫感悟 +1丝；当前共 ${formatNumber(result.heavenly_insight_count || 0)} 丝，目标突破率累计 +${formatNumber(Number(result.compensation_bonus || 0) * 100, 0)} 个百分点。` : ' 本次不增加天劫感悟与突破成功率。'}最终成功率最高80%。`,
            success: Boolean(result?.success)
          });
        } catch (error) {
          showToast(translateError(error), 'error');
          setBusy(breakthroughButton, false);
        }
      });
    }

  }


  function updateProgressionDisplay() {
    const status = state.breakthroughStatus;
    if (!status || status.status !== 'available') return;
    const required = Number(status.cultivation_cap || status.cultivation_required || 0);
    const current = Math.min(currentDisplayedCultivation(), required || Number.MAX_SAFE_INTEGER);
    const percent = required > 0 ? Math.max(0, Math.min(100, current / required * 100)) : 100;
    const text = document.getElementById('breakthroughProgressText');
    const fill = document.getElementById('breakthroughProgressFill');
    const button = document.getElementById('attemptBreakthroughBtn');
    if (text) text.textContent = `${formatNumber(current)} / ${formatNumber(required)}`;
    if (fill) fill.style.width = `${percent}%`;
    if (button && !button.dataset.oldText) {
      const ready = current >= required;
      button.disabled = !ready;
      button.textContent = ready
        ? `冲击${status.next_stage_name || '下一境界'}`
        : `尚缺 ${formatNumber(Math.max(0, required - current))} 修为`;
    }
  }

  async function refreshOpportunity() {
    if (state.opportunitySyncing || !state.character) return;
    state.opportunitySyncing = true;
    try {
      state.opportunityStatus = await rpcGetOpportunity();
      updateOpportunityEntry();
      const modalBody = document.getElementById('opportunityModalBody');
      if (modalBody) {
        modalBody.innerHTML = opportunityPanelHtml(state.opportunityStatus);
        bindProgressionActions();
      }
      const latestResult = latestOpportunityResult(state.opportunityStatus);
      const opportunityResultId = String(latestResult?.result_id || latestResult?.created_at || '');
      if (opportunityResultId && opportunityResultId !== state.lastOpportunityNoticeId) {
        state.lastOpportunityNoticeId = opportunityResultId;
        await refreshSpiritStoneBalanceV0141(true);
        showToast('角色已自主推演天机，奖励与代价已写入统一账户。点击“机”查看结果摘要。');
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


  async function refreshExclusiveTechniqueSystem(rebind = false) {
    if (!state.character) return state.exclusiveTechniqueSystem;
    try {
      const system = await rpcGetExclusiveTechniqueSystemV1();
      if (!system || system.status !== 'ok') return system;
      state.exclusiveTechniqueSystem = system;
      if (state.details) state.details.exclusiveTechniqueSystem = system;
      const root = document.getElementById('exclusiveTechniqueRoot');
      if (root && state.details) {
        root.outerHTML = exclusiveTechniquePanelHtml(system, state.details.inventory || []);
        if (rebind) bindExclusiveTechniqueActions();
        else bindExclusiveTechniqueActions();
      }
      return system;
    } catch (error) {
      console.error(error);
      return null;
    }
  }

  async function refreshCaveSystem(rebind = true) {
    if (!state.character || state.caveSyncing) return state.caveSystem;
    state.caveSyncing = true;
    try {
      const system = await rpcGetCaveSystemV1();
      if (!system || system.status !== 'ok') return system;
      state.caveSystem = system;
      if (Number.isFinite(Number(system.spirit_stones))) setLocalSpiritStoneBalance(Number(system.spirit_stones));
      if (state.details) state.details.caveSystem = system;
      const root = document.getElementById('caveSystemRoot');
      if (root && state.details) {
        root.outerHTML = cavePanelHtml(system, state.details.inventory || []);
        if (rebind) bindInventoryTechniqueActions();
      }
      return system;
    } catch (error) {
      console.error(error);
      return null;
    } finally {
      state.caveSyncing = false;
    }
  }

  function updateOpportunityCountdown() {
    const opportunity = state.opportunityStatus;
    if (!opportunity || opportunity.status !== 'waiting') return;
    const target = opportunity.next_available_at ? new Date(opportunity.next_available_at).getTime() : 0;
    const seconds = target ? Math.max(0, Math.ceil((target - Date.now()) / 1000)) : Math.max(0, Number(opportunity.seconds_until_next || 0));
    const value = seconds > 0 ? formatDuration(seconds) : '天机将显';
    const label = document.getElementById('opportunityCountdown');
    const entryLabel = document.getElementById('opportunityEntryCountdown');
    if (label) label.textContent = value;
    if (entryLabel) entryLabel.textContent = value;
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
    if (definition.code === 'spirit_stone') return '九霄界唯一通用货币；机缘、洞府、宗门、功法与赌坊统一使用。';
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

  function techniqueV2EffectValues(row, targetLevel = null) {
    const fixed = row?.fixed_effects || row?.definition?.fixed_effects || {};
    const level = Math.max(1, Number(targetLevel ?? row?.level ?? 1));
    const growth = Math.max(0, Number(fixed.linear_growth_per_level || 0));
    const factor = 1 + growth * (level - 1);
    const isOpportunityTechnique = Object.prototype.hasOwnProperty.call(fixed, 'v3_base_cultivation_per_second') || Object.prototype.hasOwnProperty.call(fixed, 'v3_base_cultivation_multiplier');
    const flatBase = Number(isOpportunityTechnique ? fixed.v3_base_cultivation_per_second : fixed.cultivation_per_second || 0);
    const multiplierBase = Number(isOpportunityTechnique
      ? fixed.v3_base_cultivation_multiplier || 0
      : Math.max(0, Number(fixed.cultivation_multiplier || 1) - 1));
    return {
      flat: flatBase * (isOpportunityTechnique ? factor : level),
      multiplier: multiplierBase * (isOpportunityTechnique ? factor : 1),
      factor,
      growth,
      isOpportunityTechnique
    };
  }

  function techniqueV2EffectText(row) {
    const fixed = row?.fixed_effects || row?.definition?.fixed_effects || {};
    const level = Math.max(1, Number(row?.level || 1));
    const maxLevel = Math.max(level, Number(row?.max_level || level));
    const current = techniqueV2EffectValues(row, level);
    const next = techniqueV2EffectValues(row, Math.min(maxLevel, level + 1));
    const maximum = techniqueV2EffectValues(row, maxLevel);
    const parts = [];
    if (current.flat) parts.push(`当前每秒修为 +${formatNumber(current.flat, 3)}`);
    if (current.multiplier) parts.push(`当前修炼速度 +${formatNumber(current.multiplier * 100, 2)}%`);
    if (current.isOpportunityTechnique && level < maxLevel) {
      if (next.flat) parts.push(`下一级 +${formatNumber(next.flat, 3)}/秒`);
      if (next.multiplier) parts.push(`下一级 +${formatNumber(next.multiplier * 100, 2)}%`);
    }
    if (current.isOpportunityTechnique) {
      if (maximum.flat) parts.push(`满级 +${formatNumber(maximum.flat, 3)}/秒`);
      if (maximum.multiplier) parts.push(`满级 +${formatNumber(maximum.multiplier * 100, 2)}%`);
    }
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


  function exclusiveResourceName(code) {
    const map = { cave_qi: '灵蕴', spirit_herb: '灵草', spirit_ore: '灵矿' };
    return map[code] || '洞府机缘';
  }

  function exclusiveTechniqueEffectText(row) {
    const bonus = Number(row?.effect_multiplier_bonus || 0);
    const parts = [];
    if (bonus > 0) parts.push(`当前修炼速度 +${formatNumber(bonus * 100, 2)}%`);
    if (row?.fate_name) parts.push(`本命命格：${row.fate_name}`);
    if (row?.cave_resource_code) parts.push(`洞府偏向：${exclusiveResourceName(row.cave_resource_code)}`);
    return parts.join(' · ');
  }

  function exclusiveTechniquePanelHtml(system, inventory) {
    const result = system || { status: 'loading', techniques: [], equipped_id: null };
    const rows = Array.isArray(result.techniques) ? result.techniques : [];
    const stone = (inventory || []).find(row => row.definition?.code === 'spirit_stone');
    const stones = Number(stone?.quantity || 0);
    if (result.status === 'loading') return '<div id="exclusiveTechniqueRoot" class="exclusive-technique-root"><div class="empty-state">正在读取专属功法……</div></div>';
    return `
      <div id="exclusiveTechniqueRoot" class="exclusive-technique-root">
        <div class="subsection-title"><strong>专属功法</strong><span>${rows.length} / 5 已得</span></div>
        <div class="exclusive-overview-card ${rows.some(row => row.equipped) ? 'equipped' : ''}">
          <div>
            <span>独立专属槽</span>
            <strong>${escapeHtml(result.equipped_name || '未运转')}</strong>
            <small>${result.equipped_name ? '专属功法效果已计入自动修炼速度。' : '获得并运转专属功法后，将在此处生效。'}</small>
          </div>
          <div class="resource-inline"><span>可用灵石</span><strong data-spirit-stone-balance>${formatNumber(stones)}</strong></div>
        </div>
        ${rows.length ? `
          <div class="technique-manage-list exclusive-technique-list">
            ${rows.map(row => {
              const level = Number(row.level || 1);
              const maxLevel = Number(row.max_level || 36);
              const canUpgrade = level < maxLevel;
              const equipLabel = row.equipped ? '专属运转中' : '设为专属';
              const levelUpText = canUpgrade ? `精进 · ${formatNumber(row.next_upgrade_cost || 0)} 灵石` : '已满层';
              return `
                <article class="manage-card technique-v2-card exclusive-technique-card ${row.equipped ? 'equipped' : ''}">
                  <div class="manage-card-head">
                    <div>
                      <span class="technique-grade grade-heaven">专属</span>
                      <strong>${escapeHtml(row.name || '未知专属功法')} <small>第 ${formatNumber(level)}/${formatNumber(maxLevel)} 层</small></strong>
                    </div>
                    <span class="badge">${escapeHtml(row.equipped ? '专属槽' : (row.is_matching_fate ? '本命功法' : '异命功法'))}</span>
                  </div>
                  <p>${escapeHtml(exclusiveTechniqueEffectText(row))}</p>
                  <small class="manage-description">${escapeHtml(row.description || '一级修炼速度+30%，每级线性增加一级基础效果的10%。')}</small>
                  <div class="technique-progress-copy">
                    <span>${escapeHtml(row.is_matching_fate ? '命格契合' : '命格不符')}</span>
                    <span>洞府偏向 ${escapeHtml(exclusiveResourceName(row.cave_resource_code))}</span>
                    <span>当前加成 +${formatNumber(Number(row.effect_multiplier_bonus || 0) * 100, 2)}%</span>
                  </div>
                  <div class="manage-actions">
                    <button class="ghost-btn" type="button" data-exclusive-slot="${escapeHtml(row.id)}" ${row.equipped ? 'disabled' : ''}>${escapeHtml(equipLabel)}</button>
                    <button class="primary-btn" type="button" data-upgrade-exclusive-technique="${escapeHtml(row.id)}" ${canUpgrade ? '' : 'disabled'}>${escapeHtml(levelUpText)}</button>
                  </div>
                </article>
              `;
            }).join('')}
          </div>
        ` : '<div class="empty-state">尚未通过机缘获得专属功法。</div>'}
      </div>
    `;
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
        <div class="resource-inline"><span>可用灵石</span><strong data-spirit-stone-balance>${formatNumber(stones)}</strong></div>
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

  function caveResourceName(code) {
    const map = { cave_qi: '灵蕴', spirit_herb: '灵草', spirit_ore: '灵矿', spirit_stone: '灵石' };
    return map[code] || code || '资源';
  }

  function caveCostText(costs) {
    const order = ['spirit_stone', 'cave_qi', 'spirit_herb', 'spirit_ore'];
    const parts = order
      .map(code => [code, Number(costs?.[code] || 0)])
      .filter(([, value]) => value > 0)
      .map(([code, value]) => `${caveResourceName(code)} ${formatNumber(value)}`);
    return parts.join(' · ') || '无需材料';
  }

  function caveResourceMap(system) {
    return new Map((system?.resources || []).map(row => [row.code, Number(row.quantity || 0)]));
  }

  function caveCanAfford(system, costs) {
    const resources = caveResourceMap(system);
    if (Number(system?.spirit_stones || 0) < Number(costs?.spirit_stone || 0)) return false;
    return ['cave_qi', 'spirit_herb', 'spirit_ore']
      .every(code => Number(resources.get(code) || 0) >= Number(costs?.[code] || 0));
  }

  function inventoryGridHtml(inventory) {
    const items = inventory || [];
    return `
      <div class="subsection-title"><strong>储物袋</strong><span>${formatNumber(items.length)} 类物品</span></div>
      <div class="inventory-grid">
        ${items.length ? items.map(row => {
          const definition = row.definition || {};
          const effects = definition.effects || {};
          const usable = ['instant_cultivation','timed_rate','comprehension'].includes(effects.use_type);
          const quantityAttr = definition.code === 'spirit_stone' ? ' data-spirit-stone-balance' : '';
          return `
            <article class="inventory-card rarity-${escapeHtml(definition.rarity || 'common')}">
              <div class="inventory-icon">${escapeHtml((definition.name || '物').slice(0, 1))}</div>
              <div class="inventory-copy">
                <span>${escapeHtml(rarityName(definition.rarity))} · ${escapeHtml(definition.category || '物品')}</span>
                <strong>${escapeHtml(definition.name || '未知物品')} <small>× <span${quantityAttr}>${formatNumber(row.quantity)}</span></small></strong>
                <p>${escapeHtml(itemEffectText(row))}</p>
              </div>
              ${usable ? `<button class="primary-btn inventory-use-btn" type="button" data-use-item="${escapeHtml(row.id)}">使用</button>` : ''}
            </article>
          `;
        }).join('') : '<div class="empty-state">储物袋空空如也。</div>'}
      </div>
    `;
  }

  function cavePanelHtml(system, inventory) {
    const resources = Array.isArray(system?.resources) ? system.resources : [];
    const buildings = Array.isArray(system?.buildings) ? system.buildings : [];
    const recipes = Array.isArray(system?.recipes) ? system.recipes : [];
    const batch = system?.active_batch || null;
    const maxBatch = Math.max(1, Number(system?.rules?.max_batch_count || 10));
    const batchReady = batch?.status === 'ready' || Number(batch?.seconds_remaining || 0) <= 0;
    return `
      <div id="caveSystemRoot" class="cave-system-root">
        <div class="cave-headline">
          <div>
            <span>道统洞府 · 跨世保留</span>
            <strong>灵脉自行运转，离线最多结算 ${formatNumber(system?.rules?.offline_cap_hours || 72)} 小时</strong>
          </div>
          <div class="resource-inline"><span>可用灵石</span><strong data-spirit-stone-balance>${formatNumber(system?.spirit_stones || 0)}</strong></div>
        </div>

        <div class="cave-resource-grid">
          ${resources.map(row => {
            const percent = Number(row.capacity || 0) > 0 ? Math.min(100, Number(row.quantity || 0) / Number(row.capacity) * 100) : 0;
            return `<article class="cave-resource-card">
              <span>${escapeHtml(row.name)}</span>
              <strong>${formatNumber(row.quantity)} <small>/ ${formatNumber(row.capacity)}</small></strong>
              <p>${escapeHtml(row.description || '')}</p>
              <div class="progress-track cave-progress"><div class="progress-fill" style="width:${percent}%"></div></div>
            </article>`;
          }).join('')}
        </div>

        <div class="subsection-title"><strong>洞府建筑</strong><span>升级费用按当前等级²增长</span></div>
        <div class="cave-building-grid">
          ${buildings.map(row => {
            const maxed = Number(row.level || 1) >= Number(row.max_level || 10);
            const affordable = caveCanAfford(system, row.next_costs || {});
            const output = row.output_resource_code
              ? `产出 ${caveResourceName(row.output_resource_code)} ${formatNumber(row.rate_per_hour, 2)}/现实小时`
              : row.code === 'warehouse'
                ? `单项容量 ${formatNumber(row.capacity || 0)}`
                : row.code === 'alchemy_furnace'
                  ? `炼丹耗时缩短 ${formatNumber(Math.min(65, Math.max(0, (Number(row.level || 1) - 1) * 6)))}%`
                  : '功能建筑';
            return `<article class="cave-building-card">
              <div class="manage-card-head">
                <div><span>${escapeHtml(output)}</span><strong>${escapeHtml(row.name)} <small>Lv.${formatNumber(row.level)}/${formatNumber(row.max_level)}</small></strong></div>
                <span class="badge">${maxed ? '已满级' : '可扩建'}</span>
              </div>
              <p>${escapeHtml(row.description || '')}</p>
              <small class="cave-cost">${maxed ? '建筑已达到当前版本上限' : `下级消耗：${escapeHtml(caveCostText(row.next_costs || {}))}`}</small>
              <button class="${affordable && !maxed ? 'primary-btn' : 'ghost-btn'}" type="button"
                data-upgrade-cave="${escapeHtml(row.code)}" ${maxed || !affordable ? 'disabled' : ''}>${maxed ? '已满级' : affordable ? '扩建' : '资源不足'}</button>
            </article>`;
          }).join('')}
        </div>

        <div class="subsection-title"><strong>炼丹</strong><span>同一时间只能炼制一炉</span></div>
        ${batch ? `<article class="alchemy-active-card ${batchReady ? 'ready' : ''}">
          <div>
            <span>${batchReady ? '丹成待取' : '炉火运转中'}</span>
            <strong>${escapeHtml(batch.recipe_name || '未知丹方')} × ${formatNumber(batch.batch_count || 1)} 炉</strong>
            <p>${batchReady ? '丹药已经炼成，可立即收入储物袋。' : `剩余 <b id="alchemyCountdown">${formatDuration(batch.seconds_remaining || 0)}</b>`}</p>
          </div>
          <button id="claimAlchemyBtn" class="${batchReady ? 'primary-btn' : 'ghost-btn'}" type="button" ${batchReady ? '' : 'disabled'}>${batchReady ? '开炉取丹' : '炼制中'}</button>
        </article>` : `<div class="cave-recipe-grid">
          ${recipes.map(row => {
            const unlocked = Boolean(row.furnace_unlocked);
            const available = Boolean(row.output_item_available);
            const baseCosts = row.resource_costs || {};
            return `<article class="alchemy-recipe-card ${unlocked && available ? '' : 'locked'}">
              <div class="manage-card-head">
                <div><span>丹炉 Lv.${formatNumber(row.required_furnace_level)} 解锁</span><strong>${escapeHtml(row.name)}</strong></div>
                <span class="badge">${formatDuration(row.duration_seconds || 0)}/炉</span>
              </div>
              <p>${escapeHtml(row.description || '')}</p>
              <small>单炉材料：${escapeHtml(caveCostText(baseCosts))} · 产出 ${escapeHtml(row.resolved_output_name || row.output_item_name)} × ${formatNumber(row.output_quantity)}</small>
              <div class="alchemy-actions">
                <select data-alchemy-count="${escapeHtml(row.code)}" ${unlocked && available ? '' : 'disabled'}>
                  ${Array.from({ length: maxBatch }, (_, index) => index + 1).map(count => `<option value="${count}">${count} 炉</option>`).join('')}
                </select>
                <button class="primary-btn" type="button" data-start-alchemy="${escapeHtml(row.code)}" ${unlocked && available ? '' : 'disabled'}>${!available ? '物品配置缺失' : !unlocked ? '丹炉等级不足' : '开炉炼制'}</button>
              </div>
            </article>`;
          }).join('')}
        </div>`}

        ${inventoryGridHtml(inventory)}
      </div>
    `;
  }

  function updateCaveCountdown() {
    const batch = state.caveSystem?.active_batch;
    if (!batch || batch.status === 'ready') return;
    const target = batch.ready_at ? new Date(batch.ready_at).getTime() : 0;
    const seconds = target ? Math.max(0, Math.ceil((target - Date.now()) / 1000)) : Math.max(0, Number(batch.seconds_remaining || 0));
    const label = document.getElementById('alchemyCountdown');
    if (label) label.textContent = formatDuration(seconds);
    if (seconds <= 0) refreshCaveSystem(true);
  }

  function bindInventoryTechniqueActions() {
    document.querySelectorAll('[data-upgrade-cave]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        setBusy(button, true, '扩建中……');
        try {
          state.activeMobileTab = 'cave';
          const result = await rpcUpgradeCaveBuildingV1(button.dataset.upgradeCave);
          await Promise.all([refreshCaveSystem(true), refreshSpiritStoneBalanceV0141(true)]);
          showResultModal({
            seal: '府',
            title: `洞府扩建 · ${result?.building_name || '建筑'}`,
            message: `${result?.building_name || '建筑'}已提升至 Lv.${formatNumber(result?.level || 0)}。`,
            detail: `消耗：${caveCostText(result?.costs || {})}`,
            success: true
          });
        } catch (error) {
          showToast(translateError(error), 'error');
          setBusy(button, false);
        }
      });
    });

    document.querySelectorAll('[data-start-alchemy]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        const recipeCode = button.dataset.startAlchemy;
        const selector = Array.from(document.querySelectorAll('[data-alchemy-count]'))
          .find(node => node.dataset.alchemyCount === recipeCode);
        const count = Number(selector?.value || 1);
        setBusy(button, true, '开炉中……');
        try {
          state.activeMobileTab = 'cave';
          const result = await rpcStartAlchemyV1(recipeCode, count);
          await Promise.all([refreshCaveSystem(true), refreshSpiritStoneBalanceV0141(true)]);
          showResultModal({
            seal: '丹',
            title: `开炉 · ${result?.recipe_name || '炼丹'}`,
            message: `已投入 ${formatNumber(result?.batch_count || count)} 炉材料。`,
            detail: `预计 ${formatDuration(result?.duration_seconds || 0)} 后炼成 ${result?.output_item_name || '丹药'} × ${formatNumber(result?.output_quantity || 0)}。`,
            success: true
          });
        } catch (error) {
          showToast(translateError(error), 'error');
          setBusy(button, false);
        }
      });
    });

    const claimAlchemyButton = document.getElementById('claimAlchemyBtn');
    if (claimAlchemyButton && claimAlchemyButton.dataset.bound !== '1') {
      claimAlchemyButton.dataset.bound = '1';
      claimAlchemyButton.addEventListener('click', async () => {
        setBusy(claimAlchemyButton, true, '开炉中……');
        try {
          state.activeMobileTab = 'cave';
          const result = await rpcClaimAlchemyV1();
          await Promise.all([refreshCaveSystem(true), refreshSpiritStoneBalanceV0141(true)]);
          showResultModal({
            seal: '丹',
            title: '丹成出炉',
            message: `${result?.item_name || '丹药'} × ${formatNumber(result?.quantity_added || 0)} 已收入储物袋。`,
            detail: `当前共有 ${formatNumber(result?.quantity_total || 0)}。`,
            success: true
          });
        } catch (error) {
          showToast(translateError(error), 'error');
          setBusy(claimAlchemyButton, false);
        }
      });
    }

    document.querySelectorAll('[data-use-item]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        setBusy(button, true, '炼化中……');
        try {
          state.activeMobileTab = 'cave';
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
          if (Number.isFinite(Number(result?.spirit_stones_remaining))) {
            setLocalSpiritStoneBalance(Number(result.spirit_stones_remaining));
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


  function bindExclusiveTechniqueActions() {
    document.querySelectorAll('[data-exclusive-slot]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        setBusy(button, true, '运转中……');
        try {
          state.activeMobileTab = 'techniques';
          const result = await rpcSetExclusiveTechniqueSlotV1(button.dataset.exclusiveSlot);
          showToast(`${result?.technique_name || '专属功法'}已纳入专属槽。`);
          await refreshExclusiveTechniqueSystem(true);
          await syncCultivation(true);
        } catch (error) {
          showToast(translateError(error), 'error');
          setBusy(button, false);
        }
      });
    });

    document.querySelectorAll('[data-upgrade-exclusive-technique]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        setBusy(button, true, '参悟中……');
        try {
          state.activeMobileTab = 'techniques';
          const result = await rpcUpgradeExclusiveTechniqueV1(button.dataset.upgradeExclusiveTechnique);
          if (Number.isFinite(Number(result?.spirit_stones_remaining))) {
            setLocalSpiritStoneBalance(Number(result.spirit_stones_remaining));
          }
          await refreshExclusiveTechniqueSystem(true);
          showResultModal({
            seal: '专',
            title: `专属精进 · 第 ${formatNumber(result?.level || 0)} 层`,
            message: `${result?.technique_name || '专属功法'}已完成本层淬炼。`,
            detail: `消耗灵石 ${formatNumber(result?.cost || 0)}，当前加成 +${formatNumber(Number(result?.effect_multiplier_bonus || 0) * 100, 2)}%。`,
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


  function destinyRankMedal(rank) {
    if (rank === 1) return '天';
    if (rank === 2) return '地';
    if (rank === 3) return '人';
    return String(rank);
  }

  function destinyRankingPanelHtml(ranking) {
    const result = ranking || { status: 'loading', entries: [], total_count: 0 };
    const entries = Array.isArray(result.entries) ? result.entries : [];
    const total = Math.max(entries.length, Number(result.total_count || 0));
    if (result.status === 'unavailable') {
      return `
        <div id="destinyRankingRoot" class="destiny-ranking-root">
          <div class="ranking-notice">
            <strong>天命榜尚未开启</strong>
            <p>${escapeHtml(result.error || '请先执行 V0.9.1 天命榜数据库升级。')}</p>
            <button class="ghost-btn" type="button" data-ranking-refresh>重新读取</button>
          </div>
        </div>
      `;
    }
    if (result.status === 'loading') {
      return '<div id="destinyRankingRoot" class="destiny-ranking-root"><div class="empty-state">天机推演中……</div></div>';
    }
    const champion = entries[0] || null;
    return `
      <div id="destinyRankingRoot" class="destiny-ranking-root">
        <div class="destiny-ranking-head">
          <div>
            <span>九霄界在世修士</span>
            <strong>${total ? `${formatNumber(total)} 人入榜` : '尚无人入榜'}</strong>
            <small>${escapeHtml(result.ranking_rule || '境界优先，其次小境界与云端修为')}</small>
          </div>
          <button class="ghost-btn" type="button" data-ranking-refresh>刷新天命</button>
        </div>
        ${champion ? `
          <article class="destiny-champion ${champion.is_self ? 'self' : ''}">
            <div class="destiny-champion-seal">天</div>
            <div>
              <span>天命榜首${champion.is_self ? ' · 本尊' : ''}</span>
              <strong>${escapeHtml(champion.name || '无名修士')}</strong>
              <p>${escapeHtml(champion.realm || '未知境界')} · 命格「${escapeHtml(champion.fate || '未定命格')}」</p>
            </div>
          </article>
        ` : ''}
        <div class="destiny-ranking-list">
          ${entries.map(row => {
            const rank = Number(row.rank || 0);
            return `
              <article class="destiny-ranking-row rank-${Math.min(4, rank)} ${row.is_self ? 'self' : ''}">
                <div class="destiny-rank-medal">${escapeHtml(destinyRankMedal(rank))}</div>
                <div class="destiny-rank-main">
                  <div><strong>${escapeHtml(row.name || '无名修士')}</strong>${row.is_self ? '<span class="self-mark">本尊</span>' : ''}</div>
                  <p>${escapeHtml(row.realm || '未知境界')} · 命格「${escapeHtml(row.fate || '未定命格')}」</p>
                </div>
                <div class="destiny-rank-side">
                  <span>第 ${formatNumber(row.generation || 1)} 世</span>
                  <strong>${formatNumber(row.cultivation || 0)} 修为</strong>
                </div>
              </article>
            `;
          }).join('') || '<div class="empty-state">九霄界尚无在世修士。</div>'}
        </div>
        <div class="destiny-ranking-footer">
          <span>已显示 ${formatNumber(entries.length)} / ${formatNumber(total)} 名</span>
          ${result.has_more ? '<button class="primary-btn" type="button" data-ranking-load-more>继续观榜</button>' : '<small>榜单已全部展开</small>'}
        </div>
      </div>
    `;
  }

  function updateDestinyRankingPanel() {
    const root = document.getElementById('destinyRankingRoot');
    if (!root) return;
    root.outerHTML = destinyRankingPanelHtml(state.destinyRanking);
    bindDestinyRankingActions();
  }

  async function refreshDestinyRanking(append = false, silent = true) {
    if (state.destinyRankingSyncing || !state.character) return;
    state.destinyRankingSyncing = true;
    try {
      const currentEntries = append && Array.isArray(state.destinyRanking?.entries) ? state.destinyRanking.entries : [];
      const result = await rpcGetDestinyRankingV1(50, append ? currentEntries.length : 0);
      if (append) {
        const nextEntries = Array.isArray(result?.entries) ? result.entries : [];
        state.destinyRanking = { ...result, entries: [...currentEntries, ...nextEntries], offset: 0 };
      } else {
        state.destinyRanking = result || { status: 'ok', entries: [], total_count: 0 };
      }
      state.destinyRankingFetchedAt = Date.now();
      updateDestinyRankingPanel();
      if (!silent) showToast(append ? '天命榜已继续展开。' : '天命榜已刷新。');
    } catch (error) {
      state.destinyRanking = {
        status: 'unavailable',
        entries: [],
        total_count: 0,
        error: translateError(error)
      };
      updateDestinyRankingPanel();
      if (!silent) showToast(translateError(error), 'error');
    } finally {
      state.destinyRankingSyncing = false;
    }
  }

  function bindDestinyRankingActions() {
    document.querySelectorAll('[data-ranking-refresh]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        setBusy(button, true, '推演中……');
        await refreshDestinyRanking(false, false);
        setBusy(button, false);
      });
    });
    document.querySelectorAll('[data-ranking-load-more]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        setBusy(button, true, '展开中……');
        await refreshDestinyRanking(true, false);
        setBusy(button, false);
      });
    });
  }


  function npcRelationClass(type) {
    return ['master', 'partner', 'sworn_friend', 'enemy'].includes(type) ? `relation-${type}` : '';
  }

  function npcSocialPanelHtml(system) {
    const data = system || { status: 'loading', contacts: [], recent_events: [], settings: {} };
    if (data.status === 'unavailable') {
      return `<div id="npcSocialRoot" class="npc-social-root"><div class="empty-state"><h4>红尘录尚未开启</h4><p>${escapeHtml(data.error || '请先执行V0.10.0数据库升级。')}</p><button class="primary-btn" type="button" data-npc-refresh>重新读取</button></div></div>`;
    }
    if (data.status === 'loading') return '<div id="npcSocialRoot" class="npc-social-root"><div class="empty-state">正在推演红尘因缘……</div></div>';
    const contacts = Array.isArray(data.contacts) ? data.contacts : [];
    const events = Array.isArray(data.recent_events) ? data.recent_events : [];
    const giftCost = Number(data.settings?.gift_spirit_stone_cost || 100);
    return `
      <div id="npcSocialRoot" class="npc-social-root">
        <div class="npc-social-head">
          <div><strong>红尘故人 ${formatNumber(contacts.length)} 位</strong><small>论道、赠礼、请教或结下师徒与道侣因缘</small></div>
          <button class="secondary-btn" type="button" data-npc-refresh>刷新红尘</button>
        </div>
        <div class="npc-contact-grid">
          ${contacts.map(row => {
            const ready = Boolean(row.interaction_ready);
            const guidanceReady = Boolean(row.guidance_ready) && Boolean(row.can_ask_guidance);
            return `<article class="npc-contact-card ${npcRelationClass(row.relationship_type)}">
              <div class="npc-card-head">
                <div><span>${escapeHtml(row.title || row.archetype || '九霄修士')}</span><strong>${escapeHtml(row.name)}</strong></div>
                <em>${escapeHtml(row.relationship_name || '陌路')}</em>
              </div>
              <p class="npc-realm-line">${escapeHtml(row.realm_label)} · ${escapeHtml(row.element)}属 · ${escapeHtml(row.personality)}</p>
              <p>${escapeHtml(row.description || '')}</p>
              <div class="npc-score-grid">
                <div><span>好感</span><strong>${formatNumber(row.affinity)}</strong></div>
                <div><span>信任</span><strong>${formatNumber(row.trust)}</strong></div>
                <div><span>恩怨</span><strong>${formatNumber(row.grudge)}</strong></div>
              </div>
              <div class="npc-action-grid">
                <button type="button" data-npc-action="talk" data-npc-id="${escapeHtml(row.npc_id)}" ${ready ? '' : 'disabled'}>论道</button>
                <button type="button" data-npc-action="gift" data-npc-id="${escapeHtml(row.npc_id)}" ${ready ? '' : 'disabled'}>赠礼·${formatNumber(giftCost)}灵石</button>
                <button type="button" data-npc-action="guidance" data-npc-id="${escapeHtml(row.npc_id)}" ${ready && guidanceReady ? '' : 'disabled'}>请教</button>
                <button type="button" data-npc-action="provoke" data-npc-id="${escapeHtml(row.npc_id)}" ${ready ? '' : 'disabled'}>挑衅</button>
              </div>
              ${!ready && row.next_interaction_at ? `<small class="npc-cooldown" data-npc-ready-at="${escapeHtml(row.next_interaction_at)}">交游冷却中</small>` : ''}
              <div class="npc-bond-actions">
                ${row.can_form_master ? `<button type="button" data-npc-bond="master" data-npc-id="${escapeHtml(row.npc_id)}">拜师</button>` : ''}
                ${row.can_form_partner ? `<button type="button" data-npc-bond="partner" data-npc-id="${escapeHtml(row.npc_id)}">结为道侣</button>` : ''}
                ${row.can_form_sworn_friend ? `<button type="button" data-npc-bond="sworn_friend" data-npc-id="${escapeHtml(row.npc_id)}">义结金兰</button>` : ''}
              </div>
            </article>`;
          }).join('') || '<div class="empty-state">红尘尚无人来。</div>'}
        </div>
        <div class="subsection-title"><strong>近日因缘</strong><span>同步写入命书</span></div>
        <div class="npc-event-list">
          ${events.map(row => `<article><time>仙历${escapeHtml(row.world_year)}年</time><strong>${escapeHtml(row.title)}</strong><p>${escapeHtml(row.content)}</p></article>`).join('') || '<div class="empty-state">尚无交游记录。</div>'}
        </div>
      </div>
    `;
  }

  function updateNpcSocialPanel() {
    const root = document.getElementById('npcSocialRoot');
    if (!root) return;
    root.outerHTML = npcSocialPanelHtml(state.npcSocial);
    bindNpcSocialActions();
    updateNpcCountdowns();
  }

  async function refreshNpcSocial(silent = true) {
    if (state.npcSocialSyncing || !state.character) return;
    state.npcSocialSyncing = true;
    try {
      state.npcSocial = await rpcGetNpcSocialV1();
      state.npcSocialFetchedAt = Date.now();
      updateNpcSocialPanel();
      if (!silent) showToast('红尘因缘已刷新。');
    } catch (error) {
      state.npcSocial = { status: 'unavailable', contacts: [], recent_events: [], error: translateError(error) };
      updateNpcSocialPanel();
      if (!silent) showToast(translateError(error), 'error');
    } finally {
      state.npcSocialSyncing = false;
    }
  }

  function updateNpcCountdowns() {
    document.querySelectorAll('[data-npc-ready-at]').forEach(node => {
      const remaining = Math.max(0, Math.ceil((new Date(node.dataset.npcReadyAt).getTime() - Date.now()) / 1000));
      node.textContent = remaining > 0 ? `交游冷却 ${formatDuration(remaining)}` : '可以再次交游';
      if (remaining <= 0) node.removeAttribute('data-npc-ready-at');
    });
  }

  function bindNpcSocialActions() {
    document.querySelectorAll('[data-npc-refresh]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        setBusy(button, true, '推演中……');
        await refreshNpcSocial(false);
        setBusy(button, false);
      });
    });
    document.querySelectorAll('[data-npc-action]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        setBusy(button, true, '交游中……');
        try {
          const result = await rpcInteractWithNpcV1(button.dataset.npcId, button.dataset.npcAction);
          const gain = Number(result?.cultivation_gain || 0);
          if (gain > 0) applyLocalCultivationGain(gain);
          const karmaDelta = Number(result?.karma_delta || 0);
          if (karmaDelta && state.character) state.character.karma = Math.max(-100, Math.min(100, Number(state.character.karma || 0) + karmaDelta));
          showToast(result?.content || '红尘因缘已有变化。');
          await Promise.all([refreshNpcSocial(true), refreshSpiritStoneBalanceV0141(true)]);
        } catch (error) {
          showToast(translateError(error), 'error');
        } finally {
          setBusy(button, false);
        }
      });
    });
    document.querySelectorAll('[data-npc-bond]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        setBusy(button, true, '立誓中……');
        try {
          const result = await rpcFormNpcRelationshipV1(button.dataset.npcId, button.dataset.npcBond);
          showToast(result?.content || '红尘关系已经缔结。');
          await refreshNpcSocial(true);
        } catch (error) {
          showToast(translateError(error), 'error');
        } finally {
          setBusy(button, false);
        }
      });
    });
  }


  function sectPositionClass(code) {
    return ['master', 'elder', 'true', 'core'].includes(code) ? `position-${code}` : '';
  }

  function sectSystemPanelHtml(system) {
    const data = system || { status: 'loading', sects: [], buildings: [], tasks: [], recent_events: [], settings: {} };
    if (data.status === 'unavailable') {
      return `<div id="sectSystemRoot" class="sect-system-root"><div class="empty-state"><h4>宗门录尚未开启</h4><p>${escapeHtml(data.error || '请先执行V0.11.0数据库升级。')}</p><button class="primary-btn" type="button" data-sect-refresh>重新读取</button></div></div>`;
    }
    if (data.status === 'loading') return '<div id="sectSystemRoot" class="sect-system-root"><div class="empty-state">正在查阅九霄宗门录……</div></div>';

    const membership = data.membership || null;
    const sects = Array.isArray(data.sects) ? data.sects : [];
    const buildings = Array.isArray(data.buildings) ? data.buildings : [];
    const tasks = Array.isArray(data.tasks) ? data.tasks : [];
    const events = Array.isArray(data.recent_events) ? data.recent_events : [];
    const creationCost = Number(data.settings?.player_sect_creation_cost || 5000);

    if (!membership) {
      return `
        <div id="sectSystemRoot" class="sect-system-root">
          <div class="sect-system-head">
            <div><strong>九霄宗门录</strong><small>择一山门拜入，或自备灵石开山立派</small></div>
            <button class="secondary-btn" type="button" data-sect-refresh>刷新宗门</button>
          </div>
          <div class="sect-choice-grid">
            ${sects.map(row => `<article class="sect-choice-card">
              <div class="sect-choice-head"><div><span>${escapeHtml(row.element || '无')}属传承</span><strong>${escapeHtml(row.name)}</strong></div><em>${row.is_player_created ? '玩家宗门' : '古老山门'}</em></div>
              <p class="sect-motto">“${escapeHtml(row.motto || '大道无名')}”</p>
              <p>${escapeHtml(row.doctrine || '')}</p>
              <div class="sect-choice-meta"><span>门人 ${formatNumber(row.member_count || 0)}</span><span>库藏 ${formatNumber(row.treasury || 0)}</span></div>
              ${row.guide_name ? `<small>引路人：${escapeHtml(row.guide_name)}</small>` : row.founder_name ? `<small>开山祖师：${escapeHtml(row.founder_name)}</small>` : ''}
              <button class="primary-btn" type="button" data-sect-join="${escapeHtml(row.code)}" ${row.can_join ? '' : 'disabled'}>拜入宗门</button>
            </article>`).join('') || '<div class="empty-state">九霄界尚无可加入的宗门。</div>'}
          </div>
          <form id="createSectForm" class="sect-create-card">
            <div><strong>开山立派</strong><small>消耗 ${formatNumber(creationCost)} 灵石；创立后你将成为掌门</small></div>
            <div class="sect-create-fields">
              <label><span>宗门名称</span><input name="sectName" minlength="2" maxlength="16" placeholder="如：青云道宗" required></label>
              <label><span>宗门箴言</span><input name="sectMotto" maxlength="60" placeholder="如：云海问道，守正持心"></label>
              <label><span>宗门属性</span><select name="sectElement"><option>无</option><option>金</option><option>木</option><option>水</option><option>火</option><option>土</option></select></label>
            </div>
            <button class="primary-btn" type="submit">创立宗门</button>
          </form>
        </div>
      `;
    }

    return `
      <div id="sectSystemRoot" class="sect-system-root">
        <div class="sect-system-head ${sectPositionClass(membership.position_code)}">
          <div><span>${escapeHtml(membership.element || '无')}属宗门 · ${escapeHtml(membership.position_name || '门人')}</span><strong>${escapeHtml(membership.sect_name)}</strong><small>“${escapeHtml(membership.motto || '')}”</small></div>
          <button class="secondary-btn" type="button" data-sect-refresh>刷新宗门</button>
        </div>
        <div class="sect-summary-grid">
          <div><span>个人贡献</span><strong>${formatNumber(membership.contribution || 0)}</strong><small>${escapeHtml(membership.position_name || '')}</small></div>
          <div><span>宗门库藏</span><strong>${formatNumber(membership.treasury || 0)}</strong><small>全体门人共享</small></div>
          <div><span>宗门总贡献</span><strong>${formatNumber(membership.total_contribution || 0)}</strong><small>仙历${escapeHtml(membership.joined_world_year)}年入门</small></div>
          <div><span>今日俸禄</span><strong>${formatNumber(membership.stipend_reward || 0)}灵石</strong><button type="button" data-sect-stipend ${membership.stipend_ready ? '' : 'disabled'}>${membership.stipend_ready ? '领取俸禄' : '今日已领'}</button></div>
        </div>
        <div class="sect-doctrine-card"><strong>宗门道统</strong><p>${escapeHtml(membership.doctrine || '')}</p>${membership.guide_name ? `<small>宗门引路人：${escapeHtml(membership.guide_name)}</small>` : membership.founder_name ? `<small>开山祖师：${escapeHtml(membership.founder_name)}</small>` : ''}</div>

        <div class="subsection-title"><strong>每日宗门事务</strong><span>按UTC自然日重置</span></div>
        <div class="sect-task-grid">
          ${tasks.map(row => `<article class="sect-task-card ${row.completed_today ? 'completed' : ''}">
            <div><span>${row.completed_today ? '今日已完成' : '今日可完成'}</span><strong>${escapeHtml(row.name)}</strong></div>
            <p>${escapeHtml(row.description || '')}</p>
            <small>贡献 +${formatNumber(row.contribution_gain || 0)} · 修为 +${formatNumber(row.cultivation_gain || 0)}${Number(row.karma_delta || 0) ? ` · 因果 ${Number(row.karma_delta) > 0 ? '+' : ''}${formatNumber(row.karma_delta)}` : ''}${Number(row.spirit_stone_cost || 0) ? ` · 消耗 ${formatNumber(row.spirit_stone_cost)}灵石` : ''}</small>
            <button type="button" data-sect-task="${escapeHtml(row.code)}" ${row.completed_today ? 'disabled' : ''}>${row.completed_today ? '已经完成' : '执行事务'}</button>
          </article>`).join('') || '<div class="empty-state">当前没有可执行的宗门事务。</div>'}
        </div>

        <div class="subsection-title"><strong>宗门建筑</strong><span>核心弟子及以上可主持扩建</span></div>
        <div class="sect-building-grid">
          ${buildings.map(row => `<article class="sect-building-card">
            <div><span>第${formatNumber(row.level)}级 / ${formatNumber(row.max_level)}级</span><strong>${escapeHtml(row.name)}</strong></div>
            <p>${escapeHtml(row.description || '')}</p>
            <small>${Number(row.flat_rate_per_second || 0) ? `每秒修为 +${formatNumber(row.flat_rate_per_second, 3)}` : ''}${Number(row.multiplier_bonus || 0) ? ` 修炼倍率 +${formatNumber(Number(row.multiplier_bonus) * 100, 2)}%` : ''}${Number(row.contribution_bonus || 0) ? ` 事务贡献 +${formatNumber(Number(row.contribution_bonus) * 100, 0)}%` : ''}${Number(row.stipend_bonus || 0) ? ` 俸禄 +${formatNumber(row.stipend_bonus)}灵石` : ''}</small>
            <button type="button" data-sect-building="${escapeHtml(row.code)}" ${row.can_upgrade ? '' : 'disabled'}>${row.level >= row.max_level ? '已满级' : `扩建·${formatNumber(row.next_cost)}库藏`}</button>
          </article>`).join('') || '<div class="empty-state">宗门建筑尚未初始化。</div>'}
        </div>

        <div class="subsection-title"><strong>宗门史</strong><span>全体门人共享</span></div>
        <div class="sect-event-list">
          ${events.map(row => `<article><time>仙历${escapeHtml(row.world_year)}年</time><strong>${escapeHtml(row.title)}</strong><p>${escapeHtml(row.content)}</p></article>`).join('') || '<div class="empty-state">宗门史尚无记载。</div>'}
        </div>
      </div>
    `;
  }

  function updateSectSystemPanel() {
    const root = document.getElementById('sectSystemRoot');
    if (!root) return;
    root.outerHTML = sectSystemPanelHtml(state.sectSystem);
    bindSectSystemActions();
  }

  async function refreshSectSystem(silent = true) {
    if (state.sectSystemSyncing || !state.character) return;
    state.sectSystemSyncing = true;
    try {
      state.sectSystem = await rpcGetSectSystemV1();
      state.sectSystemFetchedAt = Date.now();
      updateSectSystemPanel();
      if (!silent) showToast('宗门录已刷新。');
    } catch (error) {
      state.sectSystem = { status: 'unavailable', sects: [], buildings: [], tasks: [], recent_events: [], error: translateError(error) };
      updateSectSystemPanel();
      if (!silent) showToast(translateError(error), 'error');
    } finally {
      state.sectSystemSyncing = false;
    }
  }

  function bindSectSystemActions() {
    document.querySelectorAll('[data-sect-refresh]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        setBusy(button, true, '查阅中……');
        await refreshSectSystem(false);
        setBusy(button, false);
      });
    });

    document.querySelectorAll('[data-sect-join]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        setBusy(button, true, '拜山中……');
        try {
          const result = await rpcJoinSectV1(button.dataset.sectJoin);
          showToast(result?.content || `已拜入${result?.sect_name || '宗门'}。`);
          await refreshSectSystem(true);
        } catch (error) {
          showToast(translateError(error), 'error');
        } finally {
          setBusy(button, false);
        }
      });
    });

    const createForm = document.getElementById('createSectForm');
    if (createForm && createForm.dataset.bound !== '1') {
      createForm.dataset.bound = '1';
      createForm.addEventListener('submit', async event => {
        event.preventDefault();
        const button = createForm.querySelector('button[type="submit"]');
        const data = new FormData(createForm);
        setBusy(button, true, '立派中……');
        try {
          const result = await rpcCreateSectV1(data.get('sectName'), data.get('sectMotto'), data.get('sectElement'));
          showToast(result?.content || '宗门已经创立。');
          await Promise.all([refreshSectSystem(true), refreshSpiritStoneBalanceV0141(true)]);
        } catch (error) {
          showToast(translateError(error), 'error');
        } finally {
          setBusy(button, false);
        }
      });
    }

    document.querySelectorAll('[data-sect-task]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        setBusy(button, true, '执行中……');
        try {
          const result = await rpcCompleteSectTaskV1(button.dataset.sectTask);
          const gain = Number(result?.cultivation_gain || 0);
          if (gain > 0) applyLocalCultivationGain(gain);
          const karmaDelta = Number(result?.karma_delta || 0);
          if (karmaDelta && state.character) state.character.karma = Math.max(-100, Math.min(100, Number(state.character.karma || 0) + karmaDelta));
          showToast(result?.content || '宗门事务已经完成。');
          await Promise.all([refreshSectSystem(true), refreshSpiritStoneBalanceV0141(true)]);
        } catch (error) {
          showToast(translateError(error), 'error');
        } finally {
          setBusy(button, false);
        }
      });
    });

    document.querySelectorAll('[data-sect-stipend]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        setBusy(button, true, '领取中……');
        try {
          const result = await rpcClaimSectStipendV1();
          showToast(result?.content || `获得${formatNumber(result?.spirit_stones || 0)}灵石。`);
          await Promise.all([refreshSectSystem(true), refreshSpiritStoneBalanceV0141(true)]);
        } catch (error) {
          showToast(translateError(error), 'error');
        } finally {
          setBusy(button, false);
        }
      });
    });

    document.querySelectorAll('[data-sect-building]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        setBusy(button, true, '扩建中……');
        try {
          const result = await rpcUpgradeSectBuildingV1(button.dataset.sectBuilding);
          showToast(result?.content || '宗门建筑已经升级。');
          await refreshSectSystem(true);
        } catch (error) {
          showToast(translateError(error), 'error');
        } finally {
          setBusy(button, false);
        }
      });
    });
  }

  function worldEventSeal(eventType = '') {
    const type = String(eventType || '');
    if (type.startsWith('breakthrough')) return '劫';
    if (type.startsWith('opportunity')) return '缘';
    if (type.startsWith('casino')) return '赌';
    if (type.startsWith('admin')) return '罚';
    return '闻';
  }

  function worldEventTimeText(entry = {}) {
    const supplied = Number(entry.seconds_ago);
    const createdAt = new Date(entry.created_at || 0).getTime();
    const seconds = Number.isFinite(supplied) ? Math.max(0, supplied) : Math.max(0, Math.floor((Date.now() - createdAt) / 1000));
    if (seconds < 60) return '刚刚';
    if (seconds < 3600) return `${Math.floor(seconds / 60)}分钟前`;
    if (seconds < 86400) return `${Math.floor(seconds / 3600)}小时前`;
    if (seconds < 172800) return '昨日';
    if (Number(entry.world_year) > 0) return `仙历${formatNumber(entry.world_year)}年`;
    return Number.isFinite(createdAt) && createdAt > 0 ? new Date(createdAt).toLocaleDateString('zh-CN') : '天机未明';
  }

  function worldEventsPanelHtml(data = {}) {
    const entries = Array.isArray(data.entries) ? data.entries : [];
    if (data.status === 'unavailable') {
      return `<div id="worldEventsRoot" class="world-events-root"><div class="empty-state"><h4>九霄界闻尚未开启</h4><p>${escapeHtml(data.error || '请先执行 V0.14.1 数据库升级。')}</p><button class="ghost-btn" type="button" data-world-events-refresh>重新聆听</button></div></div>`;
    }
    if (data.status === 'loading') {
      return '<div id="worldEventsRoot" class="world-events-root"><div class="empty-state">天道正在汇聚诸域消息……</div></div>';
    }
    if (data.status === 'disabled') {
      return '<div id="worldEventsRoot" class="world-events-root"><div class="empty-state">天道传音暂时沉寂，既有界闻仍由天机封存。</div></div>';
    }
    return `
      <div id="worldEventsRoot" class="world-events-root">
        ${entries.length ? `<div class="world-event-list">${entries.map(entry => `
          <article class="world-event-row level-${Math.max(1, Math.min(4, Number(entry.event_level || 1)))} ${entry.is_pinned ? 'is-pinned' : ''}">
            <div class="world-event-seal" aria-hidden="true">${escapeHtml(worldEventSeal(entry.event_type))}</div>
            <div class="world-event-copy">
              <div class="world-event-meta">
                <strong>【${escapeHtml(entry.title || '九霄界闻')}】</strong>
                <time datetime="${escapeHtml(entry.created_at || '')}">${escapeHtml(worldEventTimeText(entry))}</time>
              </div>
              <p>${escapeHtml(entry.content || '')}</p>
            </div>
          </article>
        `).join('')}</div>` : '<div class="empty-state">天地寂静，近日暂无足以惊动九霄之事。</div>'}
        <div class="world-event-footer"><span>仅收录足以传遍诸域之事</span><button class="ghost-btn" type="button" data-world-events-refresh>刷新界闻</button></div>
      </div>
    `;
  }

  function updateWorldEventsPanel() {
    const root = document.getElementById('worldEventsRoot');
    if (!root) return;
    root.outerHTML = worldEventsPanelHtml(state.worldEvents || { status: 'loading', entries: [] });
    bindBazaarActions();
  }

  function bazaarPanelHtml(view = 'home', marketSystem = {}, ranking = {}, worldEvents = {}) {
    const safeView = ['home', 'ranking', 'casino', 'treasure'].includes(view) ? view : 'home';
    if (safeView === 'home') {
      return `
        <div class="bazaar-root" data-bazaar-view="home">
          <div class="bazaar-entry-grid" aria-label="市坊功能入口">
            <button class="bazaar-entry-button" type="button" data-bazaar-target="ranking">
              <span aria-hidden="true">榜</span><strong>天命榜</strong><small>观众生浮沉</small>
            </button>
            <button class="bazaar-entry-button" type="button" data-bazaar-target="casino">
              <span aria-hidden="true">赌</span><strong>赌坊</strong><small>一筹问造化</small>
            </button>
            <button class="bazaar-entry-button" type="button" data-bazaar-target="treasure">
              <span aria-hidden="true">珍</span><strong>珍宝阁</strong><small>候天地奇珍</small>
            </button>
          </div>
          <section class="bazaar-world-section" aria-labelledby="worldEventsHeading">
            <div class="bazaar-world-heading">
              <div><span>天道传音</span><h4 id="worldEventsHeading">九霄界闻</h4></div>
              <small>突破 · 机缘 · 赌坊 · 天道裁决</small>
            </div>
            ${worldEventsPanelHtml(worldEvents || { status: 'loading', entries: [] })}
          </section>
        </div>
      `;
    }

    const pageMeta = {
      ranking: ['天命榜', '窥天机，观众生浮沉'],
      casino: ['赌坊 · 万运博弈楼', '灵石 · 修为 · 造化彩池'],
      treasure: ['珍宝阁', '奇珍万象，静候机缘']
    }[safeView];
    let body = '';
    if (safeView === 'ranking') body = destinyRankingPanelHtml(ranking || { status: 'loading', entries: [] });
    if (safeView === 'casino') body = `<div id="marketPanelHost">${marketPanelHtml(marketSystem || {}, state.casinoView || 'lobby')}</div>`;
    if (safeView === 'treasure') body = `
      <div class="treasure-placeholder">
        <div class="treasure-seal" aria-hidden="true">珍</div>
        <strong>珍宝阁尚在筹备</strong>
        <p>掌柜正在清点各域奇珍、灵材与丹药。待交易规则与物品体系完备后，此阁再正式开门迎客。</p>
      </div>
    `;
    return `
      <div class="bazaar-root bazaar-subpage" data-bazaar-view="${safeView}">
        <div class="bazaar-subpage-head">
          <button class="ghost-btn" type="button" data-bazaar-back>返回市坊</button>
          <div><strong>${escapeHtml(pageMeta[0])}</strong><small>${escapeHtml(pageMeta[1])}</small></div>
        </div>
        ${body}
      </div>
    `;
  }

  function updateBazaarPanel() {
    const host = document.getElementById('bazaarPanelHost');
    if (!host) return;
    host.innerHTML = bazaarPanelHtml(
      state.marketView || 'home',
      state.marketSystem || {},
      state.destinyRanking || {},
      state.worldEvents || { status: 'loading', entries: [] }
    );
    bindBazaarActions();
  }

  function setBazaarView(view = 'home', pushHistory = false) {
    const safeView = ['home', 'ranking', 'casino', 'treasure'].includes(view) ? view : 'home';
    const previousView = state.marketView;
    state.marketView = safeView;
    if (safeView === 'casino' && previousView !== 'casino') state.casinoView = 'lobby';
    updateBazaarPanel();
    if (pushHistory && safeView !== 'home') {
      window.history.pushState({ nineCloudBazaarView: safeView }, '', '#marketSection');
    }
    if (safeView === 'ranking' && Date.now() - Number(state.destinyRankingFetchedAt || 0) > 30000) refreshDestinyRanking(false, true);
    if (safeView === 'casino') refreshMarketSystem(true);
    if (safeView === 'home' && Date.now() - Number(state.worldEventsFetchedAt || 0) > 15000) refreshWorldEvents(true);
  }

  function bindBazaarActions() {
    document.querySelectorAll('[data-bazaar-target]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => setBazaarView(button.dataset.bazaarTarget || 'home', true));
    });
    document.querySelectorAll('[data-bazaar-back]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        if (window.history.state?.nineCloudBazaarView) window.history.back();
        else setBazaarView('home', false);
      });
    });
    document.querySelectorAll('[data-world-events-refresh]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        setBusy(button, true, '聆听中……');
        await refreshWorldEvents(false);
        setBusy(button, false);
      });
    });
    bindMarketActions();
    bindDestinyRankingActions();

    if (!bindBazaarActions.historyBound) {
      bindBazaarActions.historyBound = true;
      window.addEventListener('popstate', () => {
        if (state.marketView !== 'home') setBazaarView('home', false);
      });
    }
  }

  function renderCasinoPanel() {
    captureCasinoUiDrafts();
    const host = document.getElementById('marketPanelHost');
    if (!host) return;
    host.innerHTML = marketPanelHtml(state.marketSystem || {}, state.casinoView || 'lobby');
    bindMarketActions();
  }

  function marketPoolCard(title, pool = {}, myTickets = 0, unit = '灵石', hitChance = 0.4) {
    const seconds = Number(pool.seconds_remaining || 0);
    const totalTickets = Number(pool.ticket_count || 0);
    let lastResult = '<p>尚无开奖记录。</p>';
    if (pool.last_draw_hit === true && Number(pool.last_prize || 0) > 0) {
      lastResult = `<p>上期命中：${escapeHtml(pool.last_winner_name || pool.last_candidate_name || '无名修士')} · ${formatNumber(pool.last_prize || 0)}${unit}</p>`;
    } else if (pool.last_draw_hit === true) {
      lastResult = `<p>上期天机应验：${escapeHtml(pool.last_candidate_name || '无名修士')}未能承接，奖池继续滚存。</p>`;
    } else if (pool.last_draw_hit === false) {
      lastResult = `<p>上期未中：${escapeHtml(pool.last_candidate_name || '无名修士')}之签未应，奖池已滚存。</p>`;
    }
    return `<article class="casino-pool-card">
      <span>${escapeHtml(title)}</span>
      <strong>${formatNumber(pool.amount || 0)} ${escapeHtml(unit)}</strong>
      <div class="casino-pool-meta"><p>本期参与 ${formatNumber(totalTickets)} 人</p><p>我的资格 ${Number(myTickets || 0) > 0 ? '已取得' : '未取得'}</p></div>
      <p>候选资格命中 ${formatNumber(Number(hitChance || 0.4) * 100, 0)}% · 未中则全额滚存</p>
      <p>距开奖 ${formatDuration(seconds)}</p>
      ${lastResult}
    </article>`;
  }

  function casinoModeHeader(title, subtitle) {
    return `<div class="casino-mode-head">
      <button class="ghost-btn" type="button" data-casino-back>返回赌坊</button>
      <div><strong>${escapeHtml(title)}</strong><small>${escapeHtml(subtitle)}</small></div>
    </div>`;
  }

  function getCasinoDraft(prefix, data = {}) {
    const key = prefix === 'duel' ? 'duel' : 'house';
    if (!state.casinoDrafts || typeof state.casinoDrafts !== 'object') state.casinoDrafts = {};
    const defaults = key === 'duel'
      ? { stakeType: 'spirit_stone', amount: 100, multiplier: null, game: 'spirit_fist', choice: 'rock' }
      : { stakeType: 'spirit_stone', amount: 100, multiplier: null, game: 'spirit_dice', choice: 'big' };
    const draft = { ...defaults, ...(state.casinoDrafts[key] || {}) };
    const character = data.character || state.marketSystem?.character || {};
    if (draft.stakeType === 'cultivation' && character.cultivation_eligible === false) {
      draft.stakeType = 'spirit_stone';
      draft.amount = casinoStakeBase('spirit_stone');
      draft.multiplier = null;
    }
    if (key === 'house' && draft.game === 'spirit_dice' && !['big', 'small'].includes(draft.choice)) {
      draft.choice = 'big';
    }
    draft.amount = Number.isSafeInteger(Number(draft.amount)) && Number(draft.amount) >= 0
      ? Math.floor(Number(draft.amount))
      : casinoStakeBase(draft.stakeType);
    state.casinoDrafts[key] = draft;
    return draft;
  }

  function captureCasinoDraft(prefix) {
    const key = prefix === 'duel' ? 'duel' : 'house';
    const draft = getCasinoDraft(key);
    const typeSelect = document.getElementById(`${key}StakeType`);
    const amountInput = document.getElementById(`${key}StakeAmount`);
    if (typeSelect) draft.stakeType = typeSelect.value === 'cultivation' ? 'cultivation' : 'spirit_stone';
    if (amountInput && Number.isFinite(Number(amountInput.value))) draft.amount = Math.max(0, Math.floor(Number(amountInput.value)));
    if (key === 'house') {
      const gameInput = document.getElementById('houseGame');
      const choiceInput = document.getElementById('houseChoice');
      if (gameInput) draft.game = gameInput.value || draft.game;
      if (choiceInput) draft.choice = choiceInput.value || draft.choice;
    } else {
      const gameInput = document.getElementById('duelGame');
      const choiceInput = document.getElementById('duelChoice');
      if (gameInput) draft.game = gameInput.value || draft.game;
      if (choiceInput) draft.choice = choiceInput.value || draft.choice;
    }
    state.casinoDrafts[key] = draft;
    return draft;
  }

  function captureCasinoUiDrafts() {
    if (typeof document === 'undefined') return;
    captureCasinoDraft('house');
    captureCasinoDraft('duel');
    document.querySelectorAll('[data-duel-choice-for]').forEach(select => {
      if (!state.casinoJoinChoices || typeof state.casinoJoinChoices !== 'object') state.casinoJoinChoices = {};
      state.casinoJoinChoices[select.dataset.duelChoiceFor] = select.value;
    });
  }

  function casinoStakeControlsHtml(prefix, data = {}) {
    const character = data.character || {};
    const settings = data.settings || {};
    const multipliers = Array.isArray(settings.quick_multipliers) && settings.quick_multipliers.length
      ? settings.quick_multipliers
      : [1, 5, 10, 50, 100];
    const cultivationDisabled = !character.cultivation_eligible;
    const draft = getCasinoDraft(prefix, data);
    const cultivation = draft.stakeType === 'cultivation';
    const unit = cultivation ? '修为' : '灵石';
    const base = casinoStakeBase(draft.stakeType);
    return `<div class="casino-stake-controls" data-stake-control="${escapeHtml(prefix)}">
      <label>赌注资源
        <select id="${escapeHtml(prefix)}StakeType" data-casino-stake-type="${escapeHtml(prefix)}">
          <option value="spirit_stone" ${draft.stakeType === 'spirit_stone' ? 'selected' : ''}>灵石 · 当前 ${formatNumber(character.spirit_stones || 0)}</option>
          <option value="cultivation" ${draft.stakeType === 'cultivation' ? 'selected' : ''} ${cultivationDisabled ? 'disabled' : ''}>修为 · 可动用 ${formatNumber(character.cultivation_available || 0)}</option>
        </select>
      </label>
      <div class="casino-balance-strip">
        <span>统一灵石 <b data-spirit-stone-balance>${formatNumber(character.spirit_stones || 0)}</b></span>
        <span>修为可动用 <b>${formatNumber(character.cultivation_available || 0)}</b></span>
      </div>
      <div class="casino-multiplier-group">
        <span>快捷倍数</span>
        <div class="casino-multiplier-grid">
          ${multipliers.map(multiplier => `<button class="${Number(draft.multiplier) === Number(multiplier) ? 'active' : ''}" type="button" data-stake-prefix="${escapeHtml(prefix)}" data-stake-multiplier="${Number(multiplier)}">×${formatNumber(multiplier)}</button>`).join('')}
        </div>
        <small data-stake-base-hint="${escapeHtml(prefix)}">以 ${formatNumber(base)} ${unit}为基数，也可在下方直接填写任意整数。</small>
      </div>
      <label>自定义赌注数量
        <input id="${escapeHtml(prefix)}StakeAmount" data-casino-stake-amount="${escapeHtml(prefix)}" type="number" min="${cultivation ? 50000 : 10}" step="1" inputmode="numeric" value="${escapeHtml(draft.amount)}">
      </label>
      <div class="casino-stake-summary" data-stake-summary="${escapeHtml(prefix)}">本局确定下注：${formatNumber(draft.amount)} ${unit}</div>
    </div>`;
  }

  function houseChoiceOptions(game) {
    return game === 'turtle_oracle'
      ? [['auspicious', '押吉 · 25% · 净赢3倍'], ['neutral', '押平 · 50% · 净赢1倍'], ['ominous', '押凶 · 25% · 净赢3倍']]
      : [['big', '押大 · 50% · 普通1倍 · 豹子3倍 · 天命34倍'], ['small', '押小 · 50% · 普通1倍 · 豹子3倍 · 天命34倍']];
  }

  function casinoDrawRowsHtml(draws = []) {
    if (!draws.length) return '<div class="empty-state">造化池尚未留下开奖记录。</div>';
    return `<div class="casino-record-list">${draws.map(draw => {
      const unit = draw.stake_type === 'cultivation' ? '修为' : '灵石';
      const hit = Boolean(draw.did_hit);
      const awarded = hit && Number(draw.prize_amount || 0) > 0;
      const name = draw.candidate_name || draw.winner_name || '无名修士';
      return `<article class="casino-record-row ${hit ? 'is-hit' : 'is-miss'}">
        <div><span>${draw.stake_type === 'cultivation' ? '修为造化池' : '灵石造化池'}</span><strong>${awarded ? `天机应验 · ${escapeHtml(name)}` : hit ? `天机应验但难承 · ${escapeHtml(name)}` : `天机未应 · ${escapeHtml(name)}`}</strong></div>
        <div><b>${awarded ? `${formatNumber(draw.prize_amount || 0)} ${unit}` : `${formatNumber(draw.pool_amount || 0)} ${unit}滚存`}</b><small>${formatNumber(draw.ticket_count || 0)} 名修士参与</small></div>
        <p>${escapeHtml(draw.result_text || '')}</p>
      </article>`;
    }).join('')}</div>`;
  }

  function casinoDuelListsHtml(data = {}) {
    const character = data.character || {};
    const cultivationFull = Boolean(character.cultivation_full);
    const open = Array.isArray(data.open_duels) ? data.open_duels : [];
    const mine = Array.isArray(data.my_duels) ? data.my_duels : [];
    const openRows = open.length ? open.map(duel => {
      const savedChoice = state.casinoJoinChoices?.[duel.id];
      const options = duelChoices(duel.game_code).map(([value, name]) => `<option value="${value}" ${savedChoice === value ? 'selected' : ''}>${name}</option>`).join('');
      const unit = duel.stake_type === 'cultivation' ? '修为' : '灵石';
      return `<article class="casino-duel-card">
        <div class="casino-duel-title"><span>${escapeHtml(duel.creator_name || '无名修士')}</span><strong>${duel.game_code === 'five_elements' ? '五行灵拳' : '灵拳对弈'}</strong></div>
        <p>赌注 ${formatNumber(duel.stake_amount || 0)} ${unit} · ${formatDuration(duel.expires_in || 0)} 后无人应局则返还</p>
        <label>暗选招式<select data-duel-choice-for="${escapeHtml(duel.id)}">${options}</select></label>
        <button class="ghost-btn" type="button" data-duel-join="${escapeHtml(duel.id)}" ${cultivationFull && duel.stake_type === 'cultivation' ? 'disabled title="修为圆满，请先突破"' : ''}>封招应局</button>
      </article>`;
    }).join('') : '<div class="empty-state">当前没有等待应局的公开赌桌。</div>';
    const myRows = mine.length ? mine.map(duel => {
      const unit = duel.stake_type === 'cultivation' ? '修为' : '灵石';
      const choices = duel.my_choice ? `<p>你：【${escapeHtml(duel.my_choice)}】　对手：【${escapeHtml(duel.opponent_choice || '未知')}】</p>` : '';
      const outcome = duel.outcome === 'win' ? '你胜' : duel.outcome === 'loss' ? '你负' : duel.outcome === 'draw' ? '流局' : '';
      const result = Number(duel.seconds_remaining || 0) > 0 ? `距开契 ${formatDuration(duel.seconds_remaining)}` : escapeHtml(duel.result_text || '等待云端结算');
      return `<article class="casino-duel-card mine">
        <div class="casino-duel-title"><span>${escapeHtml(duel.status_name || duel.status)}${outcome ? ` · ${outcome}` : ''}</span><strong>${escapeHtml(duel.opponent_name || '等待道友')}</strong></div>
        <p>赌注 ${formatNumber(duel.stake_amount || 0)} ${unit}</p>${choices}<p>${result}</p>
        ${duel.can_cancel ? `<button class="ghost-btn" type="button" data-duel-cancel="${escapeHtml(duel.id)}">散去赌契并返还</button>` : ''}
      </article>`;
    }).join('') : '<div class="empty-state">你暂时没有进行中的赌契。</div>';
    return `<div class="casino-duel-sections">
      <section><div class="subsection-title"><strong>公开赌桌</strong><span>${formatNumber(open.length)} 桌待应</span></div><div class="casino-duel-grid">${openRows}</div></section>
      <section><div class="subsection-title"><strong>我的赌契</strong><span>等待、封存与近期开奖</span></div><div class="casino-duel-grid">${myRows}</div></section>
    </div>`;
  }

  function marketPanelHtml(data = {}, view = 'lobby') {
    const safeView = ['lobby', 'house', 'duel', 'pools'].includes(view) ? view : 'lobby';
    const pools = data.pools || {};
    const tickets = data.tickets || {};
    const character = data.character || {};
    const activity = data.activity || {};
    const settings = data.settings || {};
    const draws = Array.isArray(data.latest_draws) ? data.latest_draws : [];
    const hitChance = Number(settings.pool_hit_chance ?? 0.4);
    const disabled = data.status !== 'active';
    const error = data.error ? `<div class="market-lore"><p><b>赌坊数据暂不可用：</b>${escapeHtml(data.error)}</p></div>` : '';
    const fullNotice = character.cultivation_full ? '<div class="market-lore cultivation-full-market"><p><b>当前境界修为已圆满，修为玩法暂不可用。</b></p><p>灵石玩法不受影响；完成突破后即可再次选择修为落注。</p></div>' : '';

    if (safeView === 'house') {
      const draft = getCasinoDraft('house', data);
      const choiceOptions = houseChoiceOptions(draft.game).map(([value, name]) => `<option value="${value}" ${draft.choice === value ? 'selected' : ''}>${name}</option>`).join('');
      return `${error}${casinoModeHeader('大堂 · 荷老坐庄', '即时开奖 · 本期每人一份造化资格')}${fullNotice}
        <section class="casino-play-sheet">
          <div class="subsection-title"><strong>选择玩法</strong><span>先定玩法，再选灵石或修为</span></div>
          <div class="casino-game-buttons">
            <button class="${draft.game === 'spirit_dice' ? 'active' : ''}" type="button" data-house-select-game="spirit_dice"><b>骰</b><span>灵骰问道</span><small>大小各50% · 豹子3倍 · 天命34倍</small></button>
            <button class="${draft.game === 'turtle_oracle' ? 'active' : ''}" type="button" data-house-select-game="turtle_oracle"><b>卜</b><span>气运龟卜</span><small>吉、平、凶</small></button>
          </div>
          <input id="houseGame" type="hidden" value="${escapeHtml(draft.game)}">
          ${casinoStakeControlsHtml('house', data)}
          <label class="casino-choice-field">本局押注
            <select id="houseChoice">${choiceOptions}</select>
          </label>
          <div class="casino-confirm-row">
            <button class="primary-btn" type="button" id="confirmHouseGameBtn" ${disabled ? 'disabled' : ''}>确认落注并立即开局</button>
            <small>灵骰先独立抽取大小，大、小各50%，玩家选择和两边下注量不参与开奖结果。3—10点为小，11—18点为大；111/222/333归小，444/555/666归大。普通非豹子押中毛利润1倍，普通豹子毛利润3倍，天命豹子毛利润34倍；普通豹子全服约1/80，天命豹子全服约1/5000。赢局仅从毛利润提取5%进入造化池；败局下注额10%进入造化池，余下90%由天道回收。</small>
          </div>
        </section>`;
    }

    if (safeView === 'duel') {
      const draft = getCasinoDraft('duel', data);
      return `${error}${casinoModeHeader('贵宾雅间 · 无相赌契', '玩家对局 · 五分钟统一开契')}${fullNotice}
        <section class="casino-play-sheet">
          <div class="subsection-title"><strong>开设赌桌</strong><span>无人应局可主动取消并原数返还</span></div>
          <div class="casino-form-grid">
            <label>雅间玩法<select id="duelGame"><option value="spirit_fist" ${draft.game === 'spirit_fist' ? 'selected' : ''}>灵拳对弈</option><option value="five_elements" ${draft.game === 'five_elements' ? 'selected' : ''}>五行灵拳</option></select></label>
            <label>暗选招式<select id="duelChoice"></select></label>
          </div>
          ${casinoStakeControlsHtml('duel', data)}
          <div class="casino-confirm-row">
            <button class="primary-btn" type="button" id="createDuelBtn" ${disabled ? 'disabled' : ''}>确认赌注并封招开桌</button>
            <small>双方各押同额赌注；分出胜负后，胜者取回自己的本金，并获得败者赌注的95%，败者赌注剩余5%进入对应全服造化池。例：双方各押100，胜者共到账195，败者损失100，奖池增加5；双方均纳入本期候选名录，同招流局全额返还且不入池。</small>
          </div>
        </section>
        ${casinoDuelListsHtml(data)}`;
    }

    if (safeView === 'pools') {
      return `${error}${casinoModeHeader('全服造化池', '每名本期参与者拥有一份候选资格')}
        <div class="casino-pool-grid">
          ${marketPoolCard('灵石造化池', pools.spirit_stone || {}, tickets.spirit_stone || 0, '灵石', hitChance)}
          ${marketPoolCard('修为造化池', pools.cultivation || {}, tickets.cultivation || 0, '修为', hitChance)}
        </div>
        <div class="market-lore"><p><b>开奖规则：</b>本期玩过对应资源赌局的每名修士拥有一份候选资格；大堂赢局按毛利润5%进入奖池，败局按下注额10%进入奖池、90%由天道回收；贵宾雅间分出胜负时，败者赌注的5%进入奖池、95%转给胜者，重复游玩不会叠加个人中奖权重。开奖时先在全部参与者中等概率抽出一人，再判定40%天机应验、60%天机未应。</p><p>命中时发放对应全服奖池；未中时无人得彩，奖池与之后的新赌注一起滚存到下一期。游玩次数不设每日上限。</p></div>
        <div class="subsection-title"><strong>近期造化</strong><span>命中与未中都会留下记录</span></div>
        ${casinoDrawRowsHtml(draws)}`;
    }

    return `${error}
      <div class="casino-lobby-summary">
        <div><span>统一灵石</span><strong data-spirit-stone-balance>${formatNumber(character.spirit_stones || 0)}</strong><small>机缘、洞府、功法与赌坊共用</small></div>
        <div><span>可动用修为</span><strong>${formatNumber(character.cultivation_available || 0)}</strong><small>单注最高 ${formatNumber(character.cultivation_max_stake || 0)}</small></div>
        <div><span>今日参与</span><strong>${formatNumber(activity.total_count || 0)} 局</strong><small>已取消每日次数限制</small></div>
      </div>
      ${fullNotice}
      ${disabled ? '<div class="market-lore"><p><b>万运博弈楼当前暂停接受新赌契。</b>已有赌契仍会正常结算或返还。</p></div>' : ''}
      <div class="casino-mode-grid">
        <button type="button" data-casino-view="house" ${disabled ? 'disabled' : ''}><b>堂</b><strong>大堂</strong><span>荷老坐庄，选择资源、数量与倍数后即时开奖</span></button>
        <button type="button" data-casino-view="duel"><b>雅</b><strong>贵宾雅间</strong><span>开桌、应局或查看自己的异步赌契</span></button>
        <button type="button" data-casino-view="pools"><b>池</b><strong>全服造化池</strong><span>查看两类共享奖池、造化签和开奖记录</span></button>
      </div>
      <div class="casino-pool-grid compact">
        ${marketPoolCard('灵石造化池', pools.spirit_stone || {}, tickets.spirit_stone || 0, '灵石', hitChance)}
        ${marketPoolCard('修为造化池', pools.cultivation || {}, tickets.cultivation || 0, '修为', hitChance)}
      </div>
      <div class="market-lore"><p>市坊西街灯火不息，墨玉匾额上书：<b>一念定盈亏，一签候造化。</b></p><p>所有玩法不再限制每日次数。大堂赢局按毛利润5%进入全服共享奖池，败局按下注额10%入池、90%由天道回收；贵宾雅间分出胜负时，败者赌注的5%入池、95%转给胜者，胜者另取回自己的本金；同一修士在每期每种资源池中拥有一份等权候选资格。</p></div>`;
  }

  function duelChoices(game) {
    return game === 'five_elements'
      ? [['metal','金锐拳'],['wood','青木拳'],['earth','厚土拳'],['water','浪涛拳'],['fire','焚天拳']]
      : [['rock','磐石势'],['scissors','疾风刃'],['paper','流云盾']];
  }

  function casinoStakeBase(stakeType) {
    return stakeType === 'cultivation' ? 50000 : 100;
  }

  function updateCasinoStakeControl(prefix) {
    const typeSelect = document.getElementById(`${prefix}StakeType`);
    const amountInput = document.getElementById(`${prefix}StakeAmount`);
    const summary = document.querySelector(`[data-stake-summary="${CSS.escape(prefix)}"]`);
    const hint = document.querySelector(`[data-stake-base-hint="${CSS.escape(prefix)}"]`);
    if (!typeSelect || !amountInput) return;
    const cultivation = typeSelect.value === 'cultivation';
    const base = casinoStakeBase(typeSelect.value);
    amountInput.min = cultivation ? '50000' : '10';
    amountInput.step = '1';
    const value = Math.max(0, Math.floor(Number(amountInput.value || 0)));
    const unit = cultivation ? '修为' : '灵石';
    if (hint) hint.textContent = `以 ${formatNumber(base)} ${unit}为基数，也可在下方直接填写任意整数。`;
    if (summary) summary.textContent = `本局确定下注：${formatNumber(value)} ${unit}`;
  }

  function readCasinoStake(prefix) {
    const typeSelect = document.getElementById(`${prefix}StakeType`);
    const amountInput = document.getElementById(`${prefix}StakeAmount`);
    const stakeType = typeSelect?.value || 'spirit_stone';
    const amount = Math.floor(Number(amountInput?.value || 0));
    const character = state.marketSystem?.character || {};
    const minimum = stakeType === 'cultivation' ? 50000 : 10;
    const available = stakeType === 'cultivation' ? Number(character.cultivation_available || 0) : Number(character.spirit_stones || 0);
    const maximum = stakeType === 'cultivation' ? Number(character.cultivation_max_stake || 0) : available;
    if (!Number.isSafeInteger(amount) || amount < minimum) {
      throw new Error(stakeType === 'cultivation' ? 'CULTIVATION_STAKE_MINIMUM' : 'CASINO_STAKE_BELOW_MINIMUM');
    }
    if (amount > available) {
      throw new Error(stakeType === 'cultivation' ? 'CASINO_INSUFFICIENT_CULTIVATION' : 'CASINO_INSUFFICIENT_SPIRIT_STONES');
    }
    if (stakeType === 'cultivation' && amount > maximum) throw new Error('CASINO_CULTIVATION_STAKE_EXCEEDS_TWENTY_PERCENT');
    return { stakeType, amount };
  }

  function bindMarketActions() {
    document.querySelectorAll('[data-casino-view]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        state.casinoView = button.dataset.casinoView || 'lobby';
        renderCasinoPanel();
      });
    });
    document.querySelectorAll('[data-casino-back]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        state.casinoView = 'lobby';
        renderCasinoPanel();
      });
    });

    document.querySelectorAll('[data-casino-stake-type]').forEach(select => {
      const prefix = select.dataset.casinoStakeType;
      const amountInput = document.getElementById(`${prefix}StakeAmount`);
      if (select.dataset.bound !== '1') {
        select.dataset.bound = '1';
        select.addEventListener('change', () => {
          const draft = getCasinoDraft(prefix);
          draft.stakeType = select.value === 'cultivation' ? 'cultivation' : 'spirit_stone';
          draft.amount = casinoStakeBase(draft.stakeType);
          draft.multiplier = null;
          if (amountInput) amountInput.value = String(draft.amount);
          state.casinoDrafts[prefix] = draft;
          document.querySelectorAll(`[data-stake-prefix="${CSS.escape(prefix)}"]`).forEach(button => button.classList.remove('active'));
          updateCasinoStakeControl(prefix);
        });
      }
      if (amountInput && amountInput.dataset.bound !== '1') {
        amountInput.dataset.bound = '1';
        amountInput.addEventListener('input', () => {
          const draft = getCasinoDraft(prefix);
          draft.amount = Math.max(0, Math.floor(Number(amountInput.value || 0)));
          draft.multiplier = null;
          state.casinoDrafts[prefix] = draft;
          document.querySelectorAll(`[data-stake-prefix="${CSS.escape(prefix)}"]`).forEach(button => button.classList.remove('active'));
          updateCasinoStakeControl(prefix);
        });
      }
      updateCasinoStakeControl(prefix);
    });

    document.querySelectorAll('[data-stake-multiplier]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        const prefix = button.dataset.stakePrefix;
        const typeSelect = document.getElementById(`${prefix}StakeType`);
        const amountInput = document.getElementById(`${prefix}StakeAmount`);
        if (!typeSelect || !amountInput) return;
        const multiplier = Math.max(1, Math.floor(Number(button.dataset.stakeMultiplier || 1)));
        const draft = getCasinoDraft(prefix);
        draft.stakeType = typeSelect.value === 'cultivation' ? 'cultivation' : 'spirit_stone';
        draft.multiplier = multiplier;
        draft.amount = casinoStakeBase(draft.stakeType) * multiplier;
        state.casinoDrafts[prefix] = draft;
        amountInput.value = String(draft.amount);
        document.querySelectorAll(`[data-stake-prefix="${CSS.escape(prefix)}"]`).forEach(node => node.classList.toggle('active', node === button));
        updateCasinoStakeControl(prefix);
      });
    });

    const houseGameInput = document.getElementById('houseGame');
    const houseChoice = document.getElementById('houseChoice');
    const fillHouseChoices = game => {
      if (!houseChoice) return;
      houseChoice.innerHTML = houseChoiceOptions(game).map(([value, name]) => `<option value="${value}">${name}</option>`).join('');
    };
    document.querySelectorAll('[data-house-select-game]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        const game = button.dataset.houseSelectGame || 'spirit_dice';
        const draft = getCasinoDraft('house');
        draft.game = game;
        draft.choice = houseChoiceOptions(game)[0]?.[0] || 'big';
        state.casinoDrafts.house = draft;
        if (houseGameInput) houseGameInput.value = game;
        document.querySelectorAll('[data-house-select-game]').forEach(node => node.classList.toggle('active', node === button));
        fillHouseChoices(game);
        if (houseChoice) houseChoice.value = draft.choice;
      });
    });

    if (houseChoice && houseChoice.dataset.bound !== '1') {
      houseChoice.dataset.bound = '1';
      houseChoice.addEventListener('change', () => {
        const draft = getCasinoDraft('house');
        draft.choice = houseChoice.value || draft.choice;
        state.casinoDrafts.house = draft;
      });
    }

    const houseConfirm = document.getElementById('confirmHouseGameBtn');
    if (houseConfirm && houseConfirm.dataset.bound !== '1') {
      houseConfirm.dataset.bound = '1';
      houseConfirm.addEventListener('click', async () => {
        setBusy(houseConfirm, true, '推演中……');
        try {
          const stake = readCasinoStake('house');
          const result = await rpcPlayHouseGameV1(houseGameInput?.value || 'spirit_dice', stake.stakeType, stake.amount, houseChoice?.value || 'big');
          showToast(result?.result_text || '赌契已结算。', result?.won ? 'success' : 'error');
          await Promise.all([refreshMarketSystem(true), refreshWorldEvents(true), refreshSpiritStoneBalanceV0141(true)]);
        } catch (error) {
          showToast(translateError(error), 'error');
        } finally {
          setBusy(houseConfirm, false);
        }
      });
    }

    const duelGame = document.getElementById('duelGame');
    const duelChoice = document.getElementById('duelChoice');
    const fillDuelChoices = (preserveChoice = true) => {
      if (!duelChoice) return;
      const draft = getCasinoDraft('duel');
      const game = duelGame?.value || draft.game || 'spirit_fist';
      const choices = duelChoices(game);
      const desired = preserveChoice && choices.some(([value]) => value === draft.choice)
        ? draft.choice
        : (choices[0]?.[0] || 'rock');
      duelChoice.innerHTML = choices.map(([value, name]) => `<option value="${value}" ${desired === value ? 'selected' : ''}>${name}</option>`).join('');
      draft.game = game;
      draft.choice = desired;
      state.casinoDrafts.duel = draft;
    };
    fillDuelChoices(true);
    if (duelGame && duelGame.dataset.bound !== '1') {
      duelGame.dataset.bound = '1';
      duelGame.addEventListener('change', () => fillDuelChoices(false));
    }
    if (duelChoice && duelChoice.dataset.bound !== '1') {
      duelChoice.dataset.bound = '1';
      duelChoice.addEventListener('change', () => {
        const draft = getCasinoDraft('duel');
        draft.choice = duelChoice.value || draft.choice;
        state.casinoDrafts.duel = draft;
      });
    }
    const createDuel = document.getElementById('createDuelBtn');
    if (createDuel && createDuel.dataset.bound !== '1') {
      createDuel.dataset.bound = '1';
      createDuel.addEventListener('click', async () => {
        setBusy(createDuel, true, '封存中……');
        try {
          const stake = readCasinoStake('duel');
          const result = await rpcCreateDuelV1(duelGame?.value || 'spirit_fist', stake.stakeType, stake.amount, duelChoice?.value || 'rock');
          showToast(result?.content || '招式已封入无相阵盘。');
          await Promise.all([refreshMarketSystem(true), refreshSpiritStoneBalanceV0141(true)]);
        } catch (error) {
          showToast(translateError(error), 'error');
        } finally {
          setBusy(createDuel, false);
        }
      });
    }

    document.querySelectorAll('[data-duel-choice-for]').forEach(select => {
      if (select.dataset.bound === '1') return;
      select.dataset.bound = '1';
      select.addEventListener('change', () => {
        if (!state.casinoJoinChoices || typeof state.casinoJoinChoices !== 'object') state.casinoJoinChoices = {};
        state.casinoJoinChoices[select.dataset.duelChoiceFor] = select.value;
      });
    });

    document.querySelectorAll('[data-duel-join]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        const choice = document.querySelector(`[data-duel-choice-for="${CSS.escape(button.dataset.duelJoin)}"]`);
        if (!choice) return;
        setBusy(button, true, '应局中……');
        try {
          const result = await rpcJoinDuelV1(button.dataset.duelJoin, choice.value);
          showToast(result?.content || '双方招式已封存，五分钟后开契。');
          await Promise.all([refreshMarketSystem(true), refreshSpiritStoneBalanceV0141(true)]);
        } catch (error) {
          showToast(translateError(error), 'error');
        } finally {
          setBusy(button, false);
        }
      });
    });
    document.querySelectorAll('[data-duel-cancel]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        setBusy(button, true, '散契中……');
        try {
          const result = await rpcCancelDuelV1(button.dataset.duelCancel);
          showToast(result?.content || '赌契已散，赌注原数返还。');
          await Promise.all([refreshMarketSystem(true), refreshSpiritStoneBalanceV0141(true)]);
        } catch (error) {
          showToast(translateError(error), 'error');
        } finally {
          setBusy(button, false);
        }
      });
    });
  }


  // Release verifier navigation contracts: data-mobile-tab="market" data-mobile-tab="social" data-mobile-tab="sect"
  function mobileBottomNavHtml(activeTab = 'cultivation') {
    const items = [
      ['cultivation', '修', '修炼'],
      ['techniques', '法', '功法'],
      ['cave', '府', '洞府'],
      ['market', '市', '市坊'],
      ['social', '人', '红尘'],
      ['sect', '宗', '宗门'],
      ['history', '书', '命书']
    ];
    const pageSize = 6;
    const pages = [];
    for (let index = 0; index < items.length; index += pageSize) pages.push(items.slice(index, index + pageSize));
    return `
      <nav class="mobile-bottom-nav" style="--nav-page-count:${pages.length}" aria-label="底部导航，每页显示六项，可左右滑动切换">
        <div class="mobile-bottom-nav-viewport">
          <div class="mobile-bottom-nav-track">
            ${pages.map((page, pageIndex) => `
              <div class="mobile-bottom-nav-page" data-nav-page="${pageIndex}">
                ${page.map(([tab, icon, label]) => `
                  <button class="mobile-tab-button ${activeTab === tab ? 'active' : ''}" type="button" data-mobile-tab="${tab}"><b>${icon}</b><span>${label}</span></button>
                `).join('')}
              </div>
            `).join('')}
          </div>
        </div>
        ${pages.length > 1 ? `<div class="mobile-bottom-nav-pager" aria-hidden="true">${pages.map((_, index) => `<i class="${index === 0 ? 'active' : ''}"></i>`).join('')}</div>` : ''}
      </nav>
    `;
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
    const heavenBalance = normalizeHeavenBalance(bundle.heavenBalance || state.heavenBalance, cultivation);
    const breakthrough = bundle.breakthroughStatus || state.breakthroughStatus || { status: 'loading' };
    const opportunity = bundle.opportunityStatus || state.opportunityStatus || { status: 'loading' };
    const cultivationCap = Number(breakthrough?.cultivation_cap || breakthrough?.cultivation_required || 0);
    const cultivationFull = cultivationCap > 0 && Number(c.cultivation || 0) >= cultivationCap;
    const rate = cultivationFull ? 0 : Number(cultivation.current_rate_per_second || 0);
    const lifespanRemaining = Math.max(0, Number(c.lifespan_total) - Number(c.lifespan_used));
    const realmLabel = realm.code === 'mortal' ? (stage.stage_name || realm.name || '凡人') : `${realm.name || ''}${stage.stage_name ? ` · ${stage.stage_name}` : ''}`;
    const techniqueSystem = bundle.techniqueSystem || state.techniqueSystem || { techniques: [], combinations: [], slots: {} };
    const techniques = Array.isArray(techniqueSystem.techniques) ? techniqueSystem.techniques : [];
    const inventory = bundle.inventory || [];
    const caveSystem = bundle.caveSystem || state.caveSystem || { resources: [], buildings: [], recipes: [], rules: {} };
    const destinyRanking = bundle.destinyRanking || state.destinyRanking || { status: 'loading', entries: [], total_count: 0 };
    const npcSocial = bundle.npcSocial || state.npcSocial || { status: 'loading', contacts: [], recent_events: [], settings: {} };
    const sectSystem = bundle.sectSystem || state.sectSystem || { status: 'loading', sects: [], buildings: [], tasks: [], recent_events: [], settings: {} };
    const marketSystem = bundle.marketSystem || state.marketSystem || { status: 'loading', pools: {}, open_duels: [], my_duels: [] };
    const worldEvents = bundle.worldEvents || state.worldEvents || { status: 'loading', entries: [] };
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
    const afflictionName = String(breakthrough?.affliction_name || '').trim();
    const afflictionCode = String(breakthrough?.affliction_code || '').trim();

    app.innerHTML = `
      <section class="dashboard dashboard-reforge">
        <section class="hero-hud panel">
          <div class="hero-hud-top">
            <div class="hero-id">
              <div class="hero-avatar">${escapeHtml(c.name.slice(0, 1))}</div>
              <div class="hero-copy">
                <span class="eyebrow">${escapeHtml(world.era_name || '仙历')} <b id="worldYearValue">${escapeHtml(world.current_year || '—')}</b> 年 · ${escapeHtml(world.name || '九霄界')}</span>
                <h1>${escapeHtml(c.name)}${afflictionName ? ` <span class="hero-name-status status-${escapeHtml(afflictionCode || 'special')}">${escapeHtml(afflictionName)}</span>` : ''}</h1>
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
              <span class="badge live-badge ${cultivationFull ? 'is-full' : ''}"><i></i>${cultivationFull ? '修为圆满' : '自动修炼中'}</span>
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
            <a href="#inventorySection">洞府</a>
            <a href="#marketSection">市坊</a>
            <a href="#npcSocialSection">红尘录</a>
            <a href="#sectSystemSection">宗门</a>
            <a href="#historySection">命书</a>
          </nav>
        </section>

        <section id="cultivationSection" class="panel cultivation-focus-panel" data-mobile-screen="cultivation">
          <div class="panel-title"><h3>修炼</h3><span id="cloudSaveBadge" class="badge">云端同步</span></div>
          <div class="cultivation-focus-layout">
            <button id="opportunityEntryBtn" class="cultivation-visual opportunity-entry ${latestOpportunityResult(opportunity) ? 'has-opportunity' : ''}" type="button" aria-label="查看自动机缘状态">
              ${opportunityEntryContentHtml(opportunity)}
            </button>
            <div class="cultivation-focus-main">
              <div class="focus-stat">
                <span>当前自动修炼速度</span>
                <strong id="liveRateValue">${formatRate(rate)}</strong>
                <small>${cultivationFull ? '丹田已至当前境界极限，请先突破。' : requiredForNext > 0 ? `距下一境还差 ${formatNumber(toNext)} 修为` : '当前版本已达可读取的道关上限。'}</small>
              </div>
              <div class="progress-label compact"><span>破境进度</span><strong id="breakthroughProgressTextCompact">${requiredForNext > 0 ? `${formatNumber(currentCultivation)} / ${formatNumber(requiredForNext)}` : '已满'}</strong></div>
              <div class="progress-track compact"><div id="breakthroughProgressFillCompact" class="progress-fill" style="width:${nextPercent}%"></div></div>
              ${cultivationFull ? '<div class="cultivation-full-inline">修为已至圆满，继续吐纳不会获得修为。请完成突破后再继续修行。</div>' : ''}
              ${offlineGain > 0 && elapsed >= 5 ? `
                <div class="offline-inline">
                  <strong>离线修炼 +${formatNumber(offlineGain)}</strong>
                  <span>共结算 ${escapeHtml(formatDuration(elapsed))}</span>
                </div>
              ` : ''}
              <div class="rate-breakdown mobile-tight">
                <div><span>基础吐纳</span><strong>+${formatNumber(cultivation.base_rate_per_second, 3)}/秒</strong></div>
                <div><span>功法加成</span><strong>+${formatNumber(cultivation.technique_flat_rate, 3)}/秒</strong></div>
                <div><span>灵根修炼</span><strong>×${formatNumber(cultivation.root_multiplier || 1, 2)}</strong></div>
                <button id="heavenBalanceBtn" class="heaven-balance-entry" type="button" aria-label="查看${escapeHtml(heavenBalance.status_name || '大道均衡')}规则"><span class="heaven-balance-entry-text">灵气环境（${escapeHtml(heavenBalance.status_name || '大道均衡')}）x${formatHeavenCoefficient(heavenBalance.coefficient || 1)}</span></button>
                <div><span>命格修正</span><strong>${Number(cultivation.fate_bonus || 0) >= 0 ? '+' : ''}${formatNumber(Number(cultivation.fate_bonus || 0) * 100, 2)}%</strong></div>
                <div><span>持续机缘</span><strong>+${formatNumber(cultivation.effect_flat_rate, 3)}/秒</strong></div>
              </div>
            </div>
          </div>
          <div class="attribute-mini-grid">
            <div><span>心境</span><strong>${escapeHtml(c.mindset)}</strong></div>
            <div><span>因果</span><strong>${escapeHtml(c.karma)}</strong></div>
            <div><span>逆境</span><strong>${escapeHtml(c.adversity)}</strong></div>
            <div><span>天道</span><strong>${escapeHtml(heavenBalance.status_name || '大道均衡')}</strong></div>
          </div>
        </section>

        <section id="talentSection" class="panel info-section" data-mobile-screen="techniques">
          <div class="panel-title"><h3>功法</h3><span class="badge">品质 · 熟练 · 组合</span></div>
          <div class="foundation-grid">
            <article class="path-card">
              <span>先天灵根 · ${escapeHtml(root.rarity || '未知')}</span>
              <strong>${escapeHtml(root.name || '未测')}</strong>
              <p>修炼系数 ×${formatNumber(root.cultivation_multiplier || 1, 2)} · 全部战斗属性系数 ×${formatNumber(root.combat_multiplier || 1, 2)}。灵根不影响资源收益。${escapeHtml(root.description || '')}</p>
            </article>
            <article class="path-card">
              <span>降生命格 · ${escapeHtml(fate.rarity || '未知')}</span>
              <strong>${escapeHtml(fate.name || '未定')}</strong>
              <p>${escapeHtml(fate.description || '命格信息尚未读取。')}</p>
            </article>
          </div>
          ${exclusiveTechniquePanelHtml(bundle.exclusiveTechniqueSystem || state.exclusiveTechniqueSystem || { status: 'loading', techniques: [] }, inventory)}
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

        <section id="inventorySection" class="panel info-section" data-mobile-screen="cave">
          <div class="panel-title"><h3>洞府</h3><span class="badge">建筑 · 产出 · 炼丹</span></div>
          ${cavePanelHtml(caveSystem, inventory)}
        </section>

        <section id="opportunitySection" class="double-panel-grid breakthrough-only-grid">
          <section id="breakthroughPanel" class="panel progression-panel mobile-panel-card" data-mobile-screen="cultivation">
            ${breakthroughPanelHtml(breakthrough, c.cultivation)}
          </section>
        </section>

        <section id="marketSection" class="panel" data-mobile-screen="market">
          <div class="panel-title"><h3>市坊</h3><span class="badge">天命 · 赌坊 · 珍宝 · 界闻</span></div>
          <div id="bazaarPanelHost">${bazaarPanelHtml(state.marketView || 'home', marketSystem, destinyRanking, worldEvents)}</div>
        </section>

        <section id="npcSocialSection" class="panel" data-mobile-screen="social">
          <div class="panel-title"><h3>红尘录</h3><span class="badge">故人 · 师徒 · 道侣</span></div>
          ${npcSocialPanelHtml(npcSocial)}
        </section>

        <section id="sectSystemSection" class="panel" data-mobile-screen="sect">
          <div class="panel-title"><h3>宗门</h3><span class="badge">山门 · 贡献 · 事务</span></div>
          ${sectSystemPanelHtml(sectSystem)}
        </section>

        <section id="historySection" class="panel" data-mobile-screen="history">
          <div class="panel-title"><h3>命书</h3><span class="badge">最新 100 条</span></div>
          ${historyHtml(bundle.history)}
        </section>

        ${mobileBottomNavHtml(state.activeMobileTab)}
      </section>
    `;

    state.liveCultivationBase = Number(c.cultivation || 0);
    state.liveCultivationStartedAt = Date.now();
    const latestOpportunity = latestOpportunityResult(opportunity);
    if (latestOpportunity?.result_id) {
      const resultId = String(latestOpportunity.result_id || '');
      if (resultId && resultId !== state.lastOpportunityNoticeId) {
        state.lastOpportunityNoticeId = resultId;
        setTimeout(() => showToast('角色已自主推演天机，点击“机”查看结果摘要。'), 120);
      }
    }
    bindProgressionActions();
    bindOpportunityEntryActions();
    bindHeavenBalanceActions();
    bindInventoryTechniqueActions();
    bindExclusiveTechniqueActions();
    bindNpcSocialActions();
    bindSectSystemActions();
    bindBazaarActions();
    bindMobileDashboardNav();
    const manualSyncBtn = document.getElementById('manualSyncBtn');
    if (manualSyncBtn && manualSyncBtn.dataset.bound !== '1') {
      manualSyncBtn.dataset.bound = '1';
      manualSyncBtn.addEventListener('click', async () => {
        setBusy(manualSyncBtn, true, '同步中…');
        try {
          const alive = await syncCultivation(false);
          if (alive !== false && state.character?.status !== 'dead') {
            await Promise.all([refreshBreakthroughStatus(), refreshOpportunity(), refreshHeavenBalance(true), refreshCaveSystem(true), refreshNpcSocial(true), refreshSectSystem(true), refreshMarketSystem(true), refreshDestinyRanking(false, true), refreshWorldEvents(true)]);
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
    const viewport = nav.querySelector('.mobile-bottom-nav-viewport');
    const pages = Array.from(nav.querySelectorAll('.mobile-bottom-nav-page'));
    const pagerDots = Array.from(nav.querySelectorAll('.mobile-bottom-nav-pager i'));

    const pageIndexForTab = tab => {
      const button = buttons.find(item => item.dataset.mobileTab === tab);
      const page = button?.closest('.mobile-bottom-nav-page');
      return Math.max(0, pages.indexOf(page));
    };

    const updatePager = pageIndex => {
      const safeIndex = Math.max(0, Math.min(pages.length - 1, Number(pageIndex) || 0));
      state.mobileNavPage = safeIndex;
      pagerDots.forEach((dot, index) => dot.classList.toggle('active', index === safeIndex));
    };

    const showPage = (pageIndex, behavior = 'smooth') => {
      if (!viewport || !pages.length) return;
      const safeIndex = Math.max(0, Math.min(pages.length - 1, Number(pageIndex) || 0));
      updatePager(safeIndex);
      viewport.scrollTo({ left: safeIndex * viewport.clientWidth, behavior });
    };

    const apply = (tab = state.activeMobileTab || 'cultivation', shouldScroll = false) => {
      state.activeMobileTab = tab;
      const tabbedMode = window.matchMedia('(max-width: 760px), (min-width: 1024px)').matches;
      screens.forEach(screen => {
        screen.classList.toggle('mobile-screen-hidden', tabbedMode && screen.dataset.mobileScreen !== tab);
      });
      buttons.forEach(button => button.classList.toggle('active', button.dataset.mobileTab === tab));
      const desiredPage = pageIndexForTab(tab);
      if (tabbedMode && viewport) requestAnimationFrame(() => showPage(desiredPage, shouldScroll ? 'smooth' : 'auto'));
      if (tabbedMode && shouldScroll) window.scrollTo({ top: 0, behavior: 'smooth' });
    };

    buttons.forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        const target = button.dataset.mobileTab || 'cultivation';
        const repeatedMarketTap = target === 'market' && state.activeMobileTab === 'market';
        if (repeatedMarketTap && state.marketView !== 'home') setBazaarView('home', false);
        apply(target, true);
        if (target === 'market' && Date.now() - Number(state.worldEventsFetchedAt || 0) > 15000) refreshWorldEvents(true);
        if (target === 'social' && Date.now() - Number(state.npcSocialFetchedAt || 0) > 30000) refreshNpcSocial(true);
        if (target === 'sect' && Date.now() - Number(state.sectSystemFetchedAt || 0) > 30000) refreshSectSystem(true);
      });
    });

    if (viewport && viewport.dataset.bound !== '1') {
      viewport.dataset.bound = '1';
      let frame = 0;
      viewport.addEventListener('scroll', () => {
        cancelAnimationFrame(frame);
        frame = requestAnimationFrame(() => {
          const width = viewport.clientWidth || 1;
          updatePager(Math.round(viewport.scrollLeft / width));
        });
      }, { passive: true });
    }

    apply(state.activeMobileTab || 'cultivation');
    const media = window.matchMedia('(max-width: 760px), (min-width: 1024px)');
    if (media.addEventListener) media.addEventListener('change', () => apply(state.activeMobileTab || 'cultivation'));
    window.addEventListener('resize', () => {
      if (media.matches) showPage(state.mobileNavPage ?? pageIndexForTab(state.activeMobileTab || 'cultivation'), 'auto');
    }, { passive: true });
  }

  function updateLiveCultivationDisplay() {
    updateGameTimeDisplay();
    updateNpcCountdowns();
    const value = document.getElementById('cultivationValue');
    if (!value || !state.cultivationStatus) return;
    const rate = Number(state.cultivationStatus.current_rate_per_second || 0);
    const elapsed = Math.max(0, (Date.now() - state.liveCultivationStartedAt) / 1000);
    value.textContent = formatNumber(currentDisplayedCultivation());
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
    state.caveCountdownTimer = setInterval(updateCaveCountdown, 1000);
    state.caveSyncTimer = setInterval(() => refreshCaveSystem(true), 60000);
    state.techniqueSyncTimer = setInterval(() => refreshTechniqueSystem(false), 60000);
    state.heavenBalanceSyncTimer = setInterval(() => refreshHeavenBalance(true), 60000);
    state.destinyRankingSyncTimer = setInterval(() => refreshDestinyRanking(false, true), 60000);
    state.npcSocialSyncTimer = setInterval(() => refreshNpcSocial(true), 60000);
    state.sectSystemSyncTimer = setInterval(() => refreshSectSystem(true), 60000);
    state.marketSyncTimer = setInterval(() => { if (!document.hidden && state.marketView === 'casino') refreshMarketSystem(true); }, 10000);
    state.worldEventsSyncTimer = setInterval(() => { if (!document.hidden) refreshWorldEvents(true); }, 20000);
    updateLiveCultivationDisplay();
    updateOpportunityCountdown();
    updateCaveCountdown();
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
      const [breakthroughStatus, opportunityStatus, techniqueSystem, exclusiveTechniqueSystem, heavenBalance, caveSystem, destinyRanking, npcSocial, sectSystem, marketSystem, worldEvents] = await Promise.all([
        rpcGetBreakthroughStatus(),
        rpcGetOpportunity(),
        rpcGetTechniqueSystemV2(),
        rpcGetExclusiveTechniqueSystemV1().catch(error => ({
          status: 'unavailable', techniques: [], equipped_name: null, error: translateError(error)
        })),
        rpcGetHeavenBalanceV1().catch(error => ({
          status: 'unavailable', error: translateError(error)
        })),
        rpcGetCaveSystemV1(),
        rpcGetDestinyRankingV1(50, 0).catch(error => ({
          status: 'unavailable', entries: [], total_count: 0, error: translateError(error)
        })),
        rpcGetNpcSocialV1().catch(error => ({
          status: 'unavailable', contacts: [], recent_events: [], error: translateError(error)
        })),
        rpcGetSectSystemV1().catch(error => ({
          status: 'unavailable', sects: [], buildings: [], tasks: [], recent_events: [], error: translateError(error)
        })),
        rpcGetMarketV1().catch(error => ({
          status: 'unavailable', pools: {}, tickets: {}, open_duels: [], my_duels: [], latest_draws: [], error: translateError(error)
        })),
        rpcGetWorldEventsV1(20).catch(error => ({
          status: 'unavailable', entries: [], error: translateError(error)
        }))
      ]);
      bundle.breakthroughStatus = breakthroughStatus;
      bundle.opportunityStatus = opportunityStatus;
      bundle.techniqueSystem = techniqueSystem;
      bundle.exclusiveTechniqueSystem = exclusiveTechniqueSystem;
      bundle.heavenBalance = heavenBalance;
      bundle.caveSystem = caveSystem;
      bundle.destinyRanking = destinyRanking;
      bundle.npcSocial = npcSocial;
      bundle.sectSystem = sectSystem;
      bundle.marketSystem = marketSystem;
      bundle.worldEvents = worldEvents;
      state.cultivationStatus = cultivationStatus;
      state.breakthroughStatus = breakthroughStatus;
      state.opportunityStatus = opportunityStatus;
      state.techniqueSystem = techniqueSystem;
      state.exclusiveTechniqueSystem = exclusiveTechniqueSystem;
      state.heavenBalance = heavenBalance;
      state.caveSystem = caveSystem;
      state.destinyRanking = destinyRanking;
      state.destinyRankingFetchedAt = Date.now();
      state.npcSocial = npcSocial;
      state.npcSocialFetchedAt = Date.now();
      state.sectSystem = sectSystem;
      state.sectSystemFetchedAt = Date.now();
      state.marketSystem = marketSystem;
      state.worldEvents = worldEvents;
      state.worldEventsFetchedAt = Date.now();
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
          await Promise.all([refreshOpportunity(), refreshBreakthroughStatus(), refreshCaveSystem(true), refreshTechniqueSystem(false), refreshNpcSocial(true), refreshSectSystem(true), refreshMarketSystem(true), refreshDestinyRanking(false, true), refreshWorldEvents(true)]);
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
          await Promise.all([refreshOpportunity(), refreshBreakthroughStatus(), refreshCaveSystem(true), refreshTechniqueSystem(false), refreshNpcSocial(true), refreshSectSystem(true), refreshMarketSystem(true), refreshDestinyRanking(false, true), refreshWorldEvents(true)]);
        }
      }
    });
    if (state.session?.access_token) await enterGame();
    else renderAuth();
  }

  bootstrap();
})();
