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

  // V2.0.10 CACHE102：宗门自主节奏与事件结算可读性升级，继续沿用低频同步与服务端结算。
  const PERF_E80 = Object.freeze({
    heartbeatMs: 30 * 1000,
    cultivationSyncMs: 60 * 1000,
    opportunityPollMs: 60 * 1000,
    marketSyncMs: 30 * 1000,
    worldEventsSyncMs: 60 * 1000,
    divineNoticeSyncMs: 60 * 1000,
    heavenBalanceSyncMs: 5 * 60 * 1000,
    onDemandStaleMs: 60 * 1000,
    rankingStaleMs: 5 * 60 * 1000,
    resumeCooldownMs: 15 * 1000
  });

  function networkVisibleE80() {
    return document.visibilityState === 'visible';
  }

  function staleForE80(timestamp, maxAge = PERF_E80.onDemandStaleMs) {
    const value = Number(timestamp || 0);
    return !value || Date.now() - value >= maxAge;
  }

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
    cultivationSyncedAt: 0,
    liveCultivationBase: 0,
    liveCultivationStartedAt: 0,
    breakthroughStatus: null,
    breakthroughPillQuantity: 0,
    fateStatus: null,
    opportunityStatus: null,
    opportunityPollTimer: null,
    opportunityCountdownTimer: null,
    opportunitySyncing: false,
    opportunityFetchedAt: 0,
    opportunityOfflineSummaryOpen: false,
    lastOpportunityNoticeId: null,
    caveSystem: null,
    caveCountdownTimer: null,
    caveSyncTimer: null,
    caveSyncing: false,
    caveSystemFetchedAt: 0,
    techniqueSystem: null,
    exclusiveTechniqueSystem: null,
    techniqueLibrary: null,
    heavenBalance: null,
    heavenBalanceSyncTimer: null,
    heavenBalanceSyncing: false,
    heavenBalanceFetchedAt: 0,
    techniqueSyncTimer: null,
    techniqueSyncing: false,
    techniqueSystemFetchedAt: 0,
    techniqueUpgradeQueue: [],
    techniqueUpgradeProcessing: false,
    destinyRanking: null,
    destinyRankingSyncTimer: null,
    destinyRankingSyncing: false,
    destinyRankingFetchedAt: 0,
    rankingBoard: 'cultivation',
    wealthRanking: null,
    wealthRankingSyncing: false,
    battleRanking: null,
    battleRankingSyncing: false,
    battleSnapshotV1: null,
    battleSnapshotSyncingV1: false,
    battlePlaybackTimer: null,
    npcSocial: null,
    npcSocialSyncTimer: null,
    npcSocialSyncing: false,
    npcSocialFetchedAt: 0,
    sectSystem: null,
    sectSystemSyncTimer: null,
    sectSystemSyncing: false,
    sectSystemFetchedAt: 0,
    marketSystem: null,
    casinoFeature: null,
    casinoFeatureFetchedAt: 0,
    casinoFeatureSyncing: false,
    casinoDisabledNoticeAt: 0,
    treasureShop: null,
    treasureShopSyncing: false,
    treasureShopFetchedAt: 0,
    marketView: 'home',
    casinoView: 'lobby',
    casinoHouseMode: 'system',
    casinoDrafts: {
      house: { stakeType: 'spirit_stone', amount: 100, multiplier: null, game: 'spirit_dice', choice: 'big' },
      duel: { stakeType: 'spirit_stone', amount: 100, multiplier: null, game: 'spirit_fist', choice: 'rock' }
    },
    casinoJoinChoices: {},
    fishShrimpState: null,
    fishShrimpDraft: { stakeType: 'spirit_stone', quantity: 100, multiplier: 1 },
    fishShrimpSyncing: false,
    fishShrimpTimer: null,
    fishShrimpBoundaryRefreshTimer: null,
    fishShrimpRefreshGuard: false,
    fishShrimpBetQueue: [],
    fishShrimpBetProcessing: false,
    fishShrimpBetFlushTimer: null,
    fishShrimpLastBetMessage: '',
    spiritDiceState: null,
    spiritDiceDraft: { stakeType: 'spirit_stone', quantity: 100, multiplier: 1 },
    spiritDiceSyncing: false,
    spiritDiceTimer: null,
    spiritDiceBoundaryRefreshTimer: null,
    spiritDiceRefreshGuard: false,
    spiritDiceBetQueue: [],
    spiritDiceBetProcessing: false,
    spiritDiceBetFlushTimer: null,
    spiritDiceLastBetMessage: '',
    spiritDiceAcceptedBetRounds: {},
    spiritDiceLastFullHistoryAt: 0,
    spiritDiceBoundaryHistoryLimit: 1,
    marketSyncing: false,
    marketSyncTimer: null,
    marketSystemFetchedAt: 0,
    worldEvents: null,
    worldEventsSyncing: false,
    worldEventsSyncTimer: null,
    worldEventsFetchedAt: 0,
    divineNoticeTimer: null,
    divineNoticeSyncing: false,
    divineNoticeActive: null,
    timeStatus: null,
    timeStatusStartedAt: 0,
    timeSyncing: false,
    deathHandled: false,
    gameSessionActive: false,
    gameSessionHeartbeatTimer: null,
    sessionReplacementHandled: false,
    resumeSyncingE80: false,
    lastResumeSyncAtE80: 0,
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
    if (raw.includes('BREAKTHROUGH_PILL_INSUFFICIENT')) return '渡境清元丹数量不足。';
    if (raw.includes('BREAKTHROUGH_PILL_QUANTITY_INVALID')) return '渡境清元丹使用数量无效。';
    if (raw.includes('TREASURE_ITEM_NOT_FOUND')) return '珍宝阁没有这件商品。';
    if (raw.includes('TREASURE_QUANTITY_INVALID')) return '购买数量无效。';
    if (raw.includes('SPIRIT_WASHING_PILL_INSUFFICIENT')) return '洗灵丹数量不足。';
    if (raw.includes('TECHNIQUE_NOT_FOUND')) return '没有找到这门功法。';
    if (raw.includes('SUPPORT_SLOTS_FULL')) return '辅修槽已满，最多同时运转两门辅修功法。';
    if (raw.includes('MAIN_TECHNIQUE_REQUIRED')) return '主修功法不能卸下，请直接切换另一门主修功法。';
    if (raw.includes('TECHNIQUE_MAX_LEVEL')) return '这门功法已经修至当前品质允许的最高层。';
    if (raw.includes('TECHNIQUE_PROFICIENCY_REQUIRED')) return '功法熟练与传承点合计不足100，继续运转或参悟同名功法书后再精进。';
    if (raw.includes('TECHNIQUE_BOOK_NOT_FOUND')) return '洞府中没有找到这本道卷。';
    if (raw.includes('TECHNIQUE_BOOK_EMPTY')) return '这本道卷已经用尽。';
    if (raw.includes('TECHNIQUE_ALREADY_LEARNED')) return '这门功法已经学会，可将额外功法书用于参悟。';
    if (raw.includes('ORDINARY_TECHNIQUE_NOT_LEARNED')) return '尚未学会这门功法，不能直接参悟。';
    if (raw.includes('EXCLUSIVE_BOOK_FATE_MISMATCH')) return '此专属道卷与你当前命格不契合，只能收藏，无法研习。';
    if (raw.includes('EXCLUSIVE_TECHNIQUE_ALREADY_LEARNED')) return '这门本命专属功法已经学会，额外道卷继续留存在藏经架。';
    if (raw.includes('INVALID_TECHNIQUE_SLOT')) return '功法槽位无效，请重新选择。';
    if (raw.includes('MAIN_TECHNIQUE_SLOT_ONLY')) return '主修功法只能放入主修槽。';
    if (raw.includes('SUPPORT_TECHNIQUE_SLOT_ONLY')) return '这门功法只能放入辅修槽。';
    if (raw.includes('INSUFFICIENT_SPIRIT_STONES')) return '灵石不足，无法提升功法。';
    if (raw.includes('MARKET_DISABLED')) return '万运博弈楼尚未开放。';
    if (raw.includes('CASINO_GLOBAL_DISABLED')) return '服务器检查到当前游戏进行非法活动，已暂停此项功能。';
    if (raw.includes('CASINO_INSUFFICIENT_SPIRIT_STONES')) return '统一灵石余额不足，无法落注。';
    if (raw.includes('CASINO_INSUFFICIENT_CULTIVATION')) return '当前小境界内可动用修为不足；境界保底修为不可下注。';
    if (raw.includes('CULTIVATION_STAKE_MINIMUM')) return '修为赌注通常最低五万点；若当前30%下注上限低于五万，则按该上限落注。';
    if (raw.includes('CASINO_CULTIVATION_REQUIRES_NASCENT_SOUL')) return '修为局仅对元婴期及以上修士开放。';
    if (raw.includes('CASINO_CULTIVATION_STAKE_EXCEEDS_TWENTY_PERCENT')) return '修为赌注超过当前规则允许范围。';
    if (raw.includes('CASINO_STAKE_EXCEEDS_TEN_PERCENT') || raw.includes('CASINO_STAKE_EXCEEDS_THIRTY_PERCENT')) return '单局累计下注不得超过开局时可用灵石或修为的30%。';
    if (raw.includes('CASINO_REQUEST_ID_REQUIRED')) return '本局唯一凭证缺失，请刷新页面后重新落注。';
    if (raw.includes('CASINO_REQUEST_IN_PROGRESS')) return '上一笔赌契仍在结算；同一角色同时只能处理一局，请稍后再试。';
    if (raw.includes('CASINO_REQUEST_PARAMETER_MISMATCH')) return '赌契凭证与本次下注内容不一致，请重新落注。';
    if (raw.includes('CASINO_STAKE_BELOW_MINIMUM')) return '本玩法赌注低于最低限制。';
    if (raw.includes('CASINO_STAKE_ABOVE_MAXIMUM')) return '本玩法赌注超过单局上限。';
    if (raw.includes('CASINO_STAKE_TOO_LARGE')) return '赌注数值过大，请降低后重试。';
    if (raw.includes('CASINO_PERIOD_CLOSED')) return '本期赌场已进入开奖前一分钟封盘，清算完成后自动开放下一期。';
    if (raw.includes('CASINO_BANKROLL_INSUFFICIENT')) return '赌场当前资金不足以承担该笔最大赔付，请降低下注金额或等待下一期资金重置。';
    if (raw.includes('CASINO_PLAYER_HOUSE_STAKE_MULTIPLE_80') || raw.includes('CASINO_PLAYER_HOUSE_STAKE_MULTIPLE_40')) return '玩家庄与联合庄采用100:97.5精确整数结算，下注额必须为80灵石的整数倍。';
    if (raw.includes('CASINO_ACTIVE_DUEL_EXISTS')) return '你已有一张等待或封存中的赌契，请先处理。';
    if (raw.includes('CASINO_INVALID_CHOICE')) return '招式或押注选项无效。';
    if (raw.includes('CASINO_PLAYER_HOUSE_NOT_ELIGIBLE')) return '统一灵石达到500万后才能申请上庄。';
    if (raw.includes('CASINO_PLAYER_HOUSE_COOLDOWN')) return '触发联合庄或资金接管后，需等待30分钟才能再次申请上庄。';
    if (raw.includes('CASINO_PLAYER_HOUSE_NOT_CURRENT_DEALER')) return '你当前并不是大堂玩家庄家，无法执行下庄。';
    if (raw.includes('CASINO_PLAYER_HOUSE_SELF_BET_FORBIDDEN')) return '庄家不能下注自己坐庄的大堂赌局。';
    if (raw.includes('DICE_BETTING_CLOSED')) return '灵骰本局已经封盘，请等待下一局。';
    if (raw.includes('DICE_INVALID_BET_BATCH')) return '本次灵骰批量下注内容无效，请重新落注。';
    if (raw.includes('CASINO_SPIRIT_DICE_PUBLIC_ROUND_ONLY')) return '灵骰问道已升级为10秒公共牌桌，请刷新游戏后进入新牌桌。';
    if (raw.includes('FISH_BETTING_CLOSED')) return '本局已经封盘，请等待下一局。';
    if (raw.includes('FISH_INVALID_SYMBOL')) return '所选法印无效。';
    if (raw.includes('FISH_INVALID_HOUSE_MODE')) return '庄家类型无效。';
    if (raw.includes('FISH_ROUND_INVALID')) return '鱼虾灵局轮次异常，请刷新后重试。';
    if (raw.includes('CASINO_PLAYER_HOUSE_ONLY_SPIRIT_STONE')) return '玩家坐庄期间，大堂只接受灵石下注。';
    if (raw.includes('CASINO_PLAYER_HOUSE_DEALER_INSUFFICIENT')) return '玩家庄已不足以继续承担新责任；系统将按规则触发联合庄或由荷老接管。';
    if (raw.includes('CASINO_PLAYER_HOUSE_RESERVE_MISSING')) return '玩家庄赔付保证金异常，本局未结算，请联系维护。';
    if (raw.includes('CASINO_PLAYER_HOUSE_DISABLED')) return '玩家坐庄功能当前已停用，荷老继续坐庄。';
    if (raw.includes('CASINO_PLAYER_HOUSE_OCCUPIED')) return '已有其他修士正在坐庄，请等待其下庄或任期结束。';
    if (raw.includes('CASINO_PLAYER_HOUSE_EXPIRED')) return '本次玩家庄任期已经结束，请重新申请上庄。';
    if (raw.includes('CASINO_PLAYER_HOUSE_NOT_ACTIVE')) return '当前没有有效玩家庄，公共牌桌由荷老接管。';
    if (raw.includes('DIVINE_NOTICE_NOT_FOUND')) return '这道天谕不存在或已经确认。';
    if (raw.includes('DIVINE_NOTICE_ALREADY_CLAIMED')) return '这道天谕已由其他在线会话领取。';
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
    if (raw.includes('TREASURE_ITEM_NOT_FOUND')) return '珍宝阁中没有这件商品。';
    if (raw.includes('INVALID_TREASURE_QUANTITY')) return '购买数量不正确。';
    if (raw.includes('BREAKTHROUGH_PILL_INSUFFICIENT')) return '渡境清元丹数量不足。';
    if (raw.includes('BREAKTHROUGH_PILL_QUANTITY_EXCESS')) return '所选丹药数量超过本次提升到80%上限所需数量。';
    if (raw.includes('SPIRIT_WASHING_PILL_INSUFFICIENT')) return '洗灵丹数量不足。';
    if (raw.includes('BATTLE_CHALLENGE_DISABLED')) return '战力榜挑战目前处于维护状态。';
    if (raw.includes('INVALID_CHALLENGE_TARGET')) return '挑战目标无效。';
    if (raw.includes('CHALLENGE_TARGET_NOT_FOUND')) return '对方当前无法接受挑战。';
    if (raw.includes('CHALLENGE_WORLD_MISMATCH')) return '只能挑战同一九霄世界中的角色。';
    if (raw.includes('ACTIVE_CHALLENGE_DAILY_LIMIT')) return '你今日的20次主动挑战已经用尽。';
    if (raw.includes('CHALLENGE_COOLDOWN')) return '每次挑战后需要等待20分钟，请稍后再战。';
    if (raw.includes('COMBAT_STATS_NOT_CONFIGURED')) return '该境界的战斗四属性尚未配置。';
    if (raw.includes('INVALID_REQUEST_ID')) return '挑战请求编号无效，请重新发起。';
    if (raw.includes('world_event_publish_v0140') && raw.includes('does not exist')) return '挑战战报发布接口尚未完成兼容修复，请先执行 V1.0 FIX1 SQL。';
    if (raw.includes('INVALID_RANKING_PAGE')) return '榜单分页参数无效，请重新进入榜单。';
    if (raw.includes('V091_REQUIRED')) return 'V0.9.1修为榜基础尚未完成，请先部署并检查。';
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
    if (state.fishShrimpBetFlushTimer) clearTimeout(state.fishShrimpBetFlushTimer);
    if (state.fishShrimpTimer) clearInterval(state.fishShrimpTimer);
    if (state.fishShrimpBoundaryRefreshTimer) clearTimeout(state.fishShrimpBoundaryRefreshTimer);
    if (state.spiritDiceBetFlushTimer) clearTimeout(state.spiritDiceBetFlushTimer);
    if (state.spiritDiceTimer) clearInterval(state.spiritDiceTimer);
    if (state.spiritDiceBoundaryRefreshTimer) clearTimeout(state.spiritDiceBoundaryRefreshTimer);
    if (state.worldEventsSyncTimer) clearInterval(state.worldEventsSyncTimer);
    if (state.divineNoticeTimer) clearInterval(state.divineNoticeTimer);
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
    state.fishShrimpBetFlushTimer = null;
    state.fishShrimpTimer = null;
    state.fishShrimpBoundaryRefreshTimer = null;
    state.spiritDiceBetFlushTimer = null;
    state.spiritDiceTimer = null;
    state.spiritDiceBoundaryRefreshTimer = null;
    state.worldEventsSyncTimer = null;
    state.divineNoticeTimer = null;
    state.cultivationSyncing = false;
    state.opportunitySyncing = false;
    state.opportunityOfflineSummaryOpen = false;
    state.caveSyncing = false;
    state.techniqueSyncing = false;
    state.heavenBalanceSyncing = false;
    state.destinyRankingSyncing = false;
    state.npcSocialSyncing = false;
    state.sectSystemSyncing = false;
    state.marketSyncing = false;
    state.worldEventsSyncing = false;
    state.divineNoticeSyncing = false;
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
    state.opportunityFetchedAt = 0;
    state.opportunityOfflineSummaryOpen = false;
    document.getElementById('opportunityOfflineSummaryBackdrop')?.remove();
    state.lastOpportunityNoticeId = null;
    state.caveSystem = null;
    state.caveSystemFetchedAt = 0;
    state.techniqueSystem = null;
    state.techniqueSystemFetchedAt = 0;
    state.exclusiveTechniqueSystem = null;
    state.techniqueLibrary = null;
    state.heavenBalance = null;
    state.heavenBalanceFetchedAt = 0;
    state.destinyRanking = null;
    state.destinyRankingFetchedAt = 0;
    state.rankingBoard = 'cultivation';
    state.wealthRanking = null;
    state.wealthRankingSyncing = false;
    state.battleRanking = null;
    state.battleRankingSyncing = false;
    state.battleSnapshotV1 = null;
    state.battleSnapshotSyncingV1 = false;
    if (state.battlePlaybackTimer) clearTimeout(state.battlePlaybackTimer);
    state.battlePlaybackTimer = null;
    state.npcSocial = null;
    state.npcSocialFetchedAt = 0;
    state.sectSystem = null;
    state.sectSystemFetchedAt = 0;
    state.divineNoticeActive = null;
    state.timeStatus = null;
    state.timeStatusStartedAt = 0;
    state.timeSyncing = false;
    state.deathHandled = false;
    if (state.gameSessionHeartbeatTimer) clearInterval(state.gameSessionHeartbeatTimer);
    state.gameSessionHeartbeatTimer = null;
    state.gameSessionActive = false;
    state.resumeSyncingE80 = false;
    state.lastResumeSyncAtE80 = 0;
    state.activeMobileTab = 'cultivation';
    state.marketSystem = null;
    state.marketSystemFetchedAt = 0;
    state.marketView = 'home';
    state.casinoView = 'lobby';
    state.casinoHouseMode = 'system';
    state.fishShrimpBetQueue = [];
    state.fishShrimpBetProcessing = false;
    state.fishShrimpBetFlushTimer = null;
    state.fishShrimpLastBetMessage = '';
    state.fishShrimpState = null;
    state.spiritDiceState = null;
    state.spiritDiceBetQueue = [];
    state.spiritDiceBetProcessing = false;
    state.spiritDiceBetFlushTimer = null;
    state.spiritDiceLastBetMessage = '';
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
      if (!networkVisibleE80() || !state.session?.access_token || !state.gameSessionActive) return;
      try {
        const status = await rpcHeartbeatGameSession();
        if (status?.status !== 'active') handleGameSessionReplaced();
      } catch (error) {
        const raw = String(error?.message || '');
        if (raw.includes('GAME_SESSION_REPLACED') || raw.includes('GAME_SESSION_REQUIRED')) {
          handleGameSessionReplaced();
        }
      }
    }, PERF_E80.heartbeatMs);
  }

  async function rpcGetMarketV1() {
    const result = await restFetch('rpc/get_market_v1', { method: 'POST', body: {} });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcGetWorldEventsV1(limit = 30) {
    const result = await restFetch('rpc/get_world_events_v1', {
      method: 'POST',
      body: { p_limit: Number(limit) }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  function casinoRequestIdFix4() {
    if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();
    const bytes = new Uint8Array(16);
    globalThis.crypto?.getRandomValues?.(bytes);
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    const hex = [...bytes].map(value => value.toString(16).padStart(2, '0')).join('');
    return `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
  }

  async function rpcPlayHouseGameV1Fix4(houseMode, gameCode, stakeType, stakeAmount, choice, requestId = casinoRequestIdFix4()) {
    const result = await restFetch('rpc/play_house_game_v1_fix4', { method: 'POST', body: {
      p_request_id: requestId,
      p_house_mode: houseMode === 'player' ? 'player' : 'system',
      p_game_code: gameCode, p_stake_type: stakeType, p_stake_amount: Number(stakeAmount), p_choice: choice
    }});
    return Array.isArray(result) ? result[0] || null : result;
  }

  const CASINO_DISABLED_NOTICE_V198 = '服务器检查到当前游戏进行非法活动，已暂停此项功能。';

  async function rpcGetCasinoFeatureSwitchV198() {
    const result = await restFetch('rpc/get_casino_feature_switch_v198', { method: 'POST', body: {} });
    return Array.isArray(result) ? result[0] || null : result;
  }

  function casinoFeatureEnabledV198(snapshot = state.casinoFeature) {
    return snapshot?.enabled !== false && snapshot?.status !== 'disabled';
  }

  function casinoDisabledNoticeV198(snapshot = state.casinoFeature) {
    return String(snapshot?.notice || CASINO_DISABLED_NOTICE_V198);
  }

  function notifyCasinoDisabledV198(snapshot = state.casinoFeature, force = false) {
    const now = Date.now();
    if (!force && now - Number(state.casinoDisabledNoticeAt || 0) < 2200) return;
    state.casinoDisabledNoticeAt = now;
    showToast(casinoDisabledNoticeV198(snapshot), 'error');
  }

  async function refreshCasinoFeatureSwitchV198({ force = false, silent = true } = {}) {
    if (!state.session || !state.character) return state.casinoFeature;
    if (!force && state.casinoFeature && Date.now() - Number(state.casinoFeatureFetchedAt || 0) < 8000) return state.casinoFeature;
    if (state.casinoFeatureSyncing) return state.casinoFeature;
    state.casinoFeatureSyncing = true;
    try {
      const snapshot = await rpcGetCasinoFeatureSwitchV198();
      state.casinoFeature = snapshot || { enabled: true, status: 'active' };
      state.casinoFeatureFetchedAt = Date.now();
      return state.casinoFeature;
    } catch (error) {
      // SQL198未完成或临时断网时，不把赌场误判为关闭；实际下注仍由数据库守卫。
      if (!silent) showToast(translateError(error), 'error');
      return state.casinoFeature || { enabled: true, status: 'unknown' };
    } finally {
      state.casinoFeatureSyncing = false;
    }
  }

  async function requireCasinoEnabledV198({ force = false, notify = true } = {}) {
    const snapshot = await refreshCasinoFeatureSwitchV198({ force, silent: true });
    if (!casinoFeatureEnabledV198(snapshot)) {
      if (notify) notifyCasinoDisabledV198(snapshot, true);
      return false;
    }
    return true;
  }

  async function rpcGetCasinoPlayerHouseStatusV1() {
    const result = await restFetch('rpc/get_casino_player_house_status_v1', { method: 'POST', body: {} });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcSetCasinoPlayerHouseV1(active) {
    const result = await restFetch('rpc/set_casino_player_house_v1', {
      method: 'POST', body: { p_active: Boolean(active) }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }


  async function rpcGetFishShrimpStateV0148(limit = 20) {
    const result = await restFetch('rpc/get_fish_shrimp_state_v0148', {
      method: 'POST', body: { p_limit: Math.max(1, Math.min(20, Number(limit) || 20)) }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcPlaceFishShrimpBetV1Fix4(houseMode, stakeType, symbolCode, stakeAmount, requestId = casinoRequestIdFix4()) {
    const result = await restFetch('rpc/place_fish_shrimp_bet_v1_fix4', {
      method: 'POST', body: {
        p_request_id: requestId,
        p_house_mode: houseMode === 'player' ? 'player' : 'system',
        p_stake_type: stakeType === 'cultivation' ? 'cultivation' : 'spirit_stone',
        p_symbol_code: symbolCode,
        p_stake_amount: Number(stakeAmount)
      }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }


  async function rpcPlaceFishShrimpBetsV175(stakeType, bets, requestId = casinoRequestIdFix4()) {
    const result = await restFetch('rpc/place_fish_shrimp_bets_v175', {
      method: 'POST', body: {
        p_request_id: requestId,
        p_stake_type: stakeType === 'cultivation' ? 'cultivation' : 'spirit_stone',
        p_bets: Array.isArray(bets) ? bets : []
      }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcGetSpiritDiceStateV175(limit = 20) {
    const result = await restFetch('rpc/get_spirit_dice_state_v175', {
      method: 'POST', body: { p_limit: Math.max(1, Math.min(20, Number(limit) || 20)) }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcPlaceSpiritDiceBetsV175(stakeType, bets, requestId = casinoRequestIdFix4()) {
    const result = await restFetch('rpc/place_spirit_dice_bets_v175', {
      method: 'POST', body: {
        p_request_id: requestId,
        p_stake_type: stakeType === 'cultivation' ? 'cultivation' : 'spirit_stone',
        p_bets: Array.isArray(bets) ? bets : []
      }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }


  async function rpcClaimNextDivineNoticeV1() {
    const result = await restFetch('rpc/claim_next_divine_notice_v1', { method: 'POST', body: {} });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcAcknowledgeDivineNoticeV1(noticeId) {
    const result = await restFetch('rpc/acknowledge_divine_notice_v1', {
      method: 'POST', body: { p_notice_id: noticeId }
    });
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


  function currentSpiritStoneBalance() {
    const row = state.details?.inventory?.find(item => item.definition?.code === 'spirit_stone');
    return Math.max(0, Number(row?.quantity ?? state.techniqueSystem?.spirit_stones ?? state.marketSystem?.character?.spirit_stones ?? 0));
  }

  function findInventoryRow(inventoryId) {
    return state.details?.inventory?.find(row => String(row.id) === String(inventoryId)) || null;
  }

  function setLocalInventoryQuantity(inventoryId, quantity) {
    const row = findInventoryRow(inventoryId);
    if (!row) return null;
    row.quantity = Math.max(0, Math.floor(Number(quantity || 0)));
    if (row.quantity <= 0) state.details.inventory = state.details.inventory.filter(item => String(item.id) !== String(inventoryId));
    return row;
  }

  function applyTreasurePurchaseResultV0154(result = {}) {
    const code = String(result?.item_code || '');
    const ownedQuantity = Math.max(0, Math.floor(Number(result?.owned_quantity ?? result?.quantity ?? 0)));
    const inventoryQuantity = Math.max(0, Math.floor(Number(result?.inventory_quantity ?? ownedQuantity)));
    const balance = Number(result?.spirit_stones_after);

    if (Number.isFinite(balance)) {
      setLocalSpiritStoneBalance(balance);
      if (state.caveSystem) state.caveSystem.spirit_stones = balance;
      if (state.treasureShop) state.treasureShop.spirit_stones = balance;
    }

    const shopRow = state.treasureShop?.items?.find(row => String(row.code || '') === code);
    if (shopRow) shopRow.owned_quantity = ownedQuantity;
    if (state.treasureShop) state.treasureShopFetchedAt = Date.now();

    if (state.details) {
      if (!Array.isArray(state.details.inventory)) state.details.inventory = [];
      let row = state.details.inventory.find(item =>
        String(item?.id || '') === String(result?.inventory_id || '') ||
        String(item?.definition?.code || '') === code
      );
      const inventoryId = result?.inventory_id || row?.id || null;
      if (row) {
        row.id = inventoryId || row.id;
        row.item_definition_id = result?.item_definition_id || row.item_definition_id;
        row.quantity = inventoryQuantity;
        row.is_bound = false;
        row.item_instance = {};
        row.acquired_year = Number(result?.acquired_year || row.acquired_year || 1);
        row.definition = {
          ...(row.definition || {}),
          id: result?.item_definition_id || row.definition?.id,
          code,
          name: result?.item_name || row.definition?.name || '丹药',
          category: result?.item_category || row.definition?.category || 'consumable',
          rarity: result?.item_rarity || row.definition?.rarity || 'legendary',
          stack_limit: Number(result?.item_stack_limit || row.definition?.stack_limit || 999999),
          effects: result?.item_effects || row.definition?.effects || {},
          description: result?.item_description || row.definition?.description || ''
        };
      } else if (inventoryId && code) {
        row = {
          id: inventoryId,
          character_id: state.character?.id || null,
          item_definition_id: result?.item_definition_id || null,
          quantity: inventoryQuantity,
          is_bound: false,
          item_instance: {},
          acquired_year: Number(result?.acquired_year || 1),
          definition: {
            id: result?.item_definition_id || null,
            code,
            name: result?.item_name || '丹药',
            category: result?.item_category || 'consumable',
            rarity: result?.item_rarity || 'legendary',
            stack_limit: Number(result?.item_stack_limit || 999999),
            effects: result?.item_effects || {},
            description: result?.item_description || ''
          }
        };
        state.details.inventory.push(row);
      }
    }

    if (code === 'breakthrough_clear_origin_pill_v0154' && state.breakthroughStatus) {
      state.breakthroughStatus.breakthrough_pill_quantity = ownedQuantity;
      const panel = document.getElementById('breakthroughPanel');
      if (panel) {
        panel.innerHTML = breakthroughPanelHtml(state.breakthroughStatus, currentDisplayedCultivation());
        bindProgressionActions();
      }
    }

    if (state.marketView === 'treasure') updateBazaarPanel();
    renderCaveSystemFromState();
    return true;
  }

  function renderCaveSystemFromState() {
    const root = document.getElementById('caveSystemRoot');
    if (!root || !state.details) return;
    root.outerHTML = cavePanelHtml(state.caveSystem || {}, state.details.inventory || [], state.techniqueLibrary || { books: [] });
    bindInventoryTechniqueActions();
    window.dispatchEvent(new CustomEvent('jiuxiao:cave-rendered'));
  }

  async function refreshCultivationEffectsV0154() {
    if (!state.character || !state.details) return [];
    try {
      const rows = await restFetch('character_cultivation_effects', { query: {
        select: 'id,display_name,source_type,source_key,flat_rate_per_second,multiplier_bonus,starts_at,expires_at,is_active,metadata',
        character_id: `eq.${state.character.id}`, is_active: 'eq.true', order: 'created_at.asc'
      }});
      state.details.cultivationEffects = Array.isArray(rows) ? rows : [];
      return state.details.cultivationEffects;
    } catch (error) {
      console.error(error);
      return state.details.cultivationEffects || [];
    }
  }

  async function refreshTreasureShopV0154(silent = true) {
    if (!state.character || state.treasureShopSyncing) return state.treasureShop;
    state.treasureShopSyncing = true;
    try {
      const shop = await rpcGetTreasureShopV0154();
      if (shop?.status === 'ok') {
        state.treasureShop = shop;
        state.treasureShopFetchedAt = Date.now();
        if (Number.isFinite(Number(shop.spirit_stones))) setLocalSpiritStoneBalance(Number(shop.spirit_stones));
        if (state.marketView === 'treasure') updateBazaarPanel();
      }
      return state.treasureShop;
    } catch (error) {
      if (!silent) showToast(translateError(error), 'error');
      return state.treasureShop;
    } finally {
      state.treasureShopSyncing = false;
    }
  }

  async function refreshMarketSystem(silent = false) {
    if (state.marketSyncing) return state.marketSystem;
    captureCasinoUiDrafts();
    state.marketSyncing = true;
    try {
      const casinoFeature = await refreshCasinoFeatureSwitchV198({ force: true, silent: true });
      if (!casinoFeatureEnabledV198(casinoFeature)) {
        state.marketSystemFetchedAt = Date.now();
        if (state.marketView === 'casino') {
          state.marketView = 'home';
          updateBazaarPanel();
          notifyCasinoDisabledV198(casinoFeature);
        }
        return state.marketSystem;
      }
      const [marketSystem, playerHouse] = await Promise.all([
        rpcGetMarketV1(),
        rpcGetCasinoPlayerHouseStatusV1().catch(error => ({
          status: 'unavailable', mode: 'system', dealer_name: '荷老', error: translateError(error)
        }))
      ]);
      state.marketSystem = { ...(marketSystem || {}), player_house: playerHouse || { mode: 'system', dealer_name: '荷老' } };
      state.marketSystemFetchedAt = Date.now();
      if (Number.isFinite(Number(state.marketSystem?.character?.spirit_stones))) {
        setLocalSpiritStoneBalance(Number(state.marketSystem.character.spirit_stones));
      }
      const host = document.getElementById('marketPanelHost');
      if (host) {
        host.innerHTML = marketPanelHtml(state.marketSystem || {}, state.casinoView || 'lobby');
        bindMarketActions();
        afterCasinoRenderV0148();
      }
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
      state.worldEvents = await rpcGetWorldEventsV1(30);
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

  async function rpcGetMyBirthResultV12() {
    const result = await restFetch('rpc/get_my_birth_result_v12', { method: 'POST', body: {} });
    return Array.isArray(result) ? result[0] || null : result;
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

  async function rpcSettleOpportunityV4() {
    const result = await restFetch('rpc/settle_opportunity_v4', {
      method: 'POST',
      body: { p_settle_cultivation: true }
    });
    const normalized = Array.isArray(result) ? result[0] || null : result;
    window.dispatchEvent(new CustomEvent('jiuxiao:opportunity-settled', { detail: normalized }));
    return normalized;
  }

  async function rpcAckOpportunitySummaryV4(batchId) {
    const result = await restFetch('rpc/ack_opportunity_v4_summary', {
      method: 'POST',
      body: { p_batch_id: batchId }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcGetOpportunityHistoryV0147(limit = 100) {
    const result = await restFetch('rpc/get_opportunity_history_v0147', {
      method: 'POST',
      body: { p_limit: Math.max(1, Math.min(100, Number(limit || 100))) }
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


  async function rpcGetFateStatusB01() {
    const result = await restFetch('rpc/get_character_fate_status_b01', {
      method: 'POST',
      body: {}
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcGetBreakthroughStatus() {
    const result = await restFetch('rpc/get_breakthrough_status_v0154', {
      method: 'POST',
      body: {}
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcAttemptBreakthrough(pillQuantity = 0, requestId = createUuid()) {
    const result = await restFetch('rpc/attempt_breakthrough_v0154', {
      method: 'POST',
      body: { p_pill_quantity: Math.max(0, Math.floor(Number(pillQuantity || 0))), p_request_id: requestId }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcUseInventoryItemQuantityV0154(inventoryId, quantity, requestId = createUuid()) {
    const result = await restFetch('rpc/use_inventory_item_quantity_v0154', {
      method: 'POST',
      body: { p_inventory_id: inventoryId, p_quantity: Number(quantity), p_request_id: requestId }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcGetTreasureShopV0154() {
    const result = await restFetch('rpc/get_treasure_shop_v0154', { method: 'POST', body: {} });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcPurchaseTreasureItemV0154(itemCode, quantity = 1, requestId = createUuid()) {
    const result = await restFetch('rpc/purchase_treasure_item_v0154', {
      method: 'POST',
      body: { p_item_code: itemCode, p_quantity: Math.max(1, Math.floor(Number(quantity || 1))), p_request_id: requestId }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcUseSpiritWashingPillV0154(requestId = createUuid()) {
    const result = await restFetch('rpc/use_spirit_washing_pill_v0154', {
      method: 'POST', body: { p_request_id: requestId }
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

  async function rpcGetWealthRankingV1(limit = 50, offset = 0) {
    const result = await restFetch('rpc/get_wealth_ranking_v1', {
      method: 'POST',
      body: {
        p_limit: Math.max(1, Math.min(100, Number(limit || 50))),
        p_offset: Math.max(0, Number(offset || 0))
      }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcGetBattlePowerRankingBCombat01(limit = 50, offset = 0) {
    const result = await restFetch('rpc/get_battle_power_ranking_bcombat01', {
      method: 'POST',
      body: {
        p_limit: Math.max(1, Math.min(100, Number(limit || 50))),
        p_offset: Math.max(0, Number(offset || 0))
      }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcGetMyBattleSnapshotV1() {
    const result = await restFetch('rpc/get_my_battle_snapshot_v1', {
      method: 'POST',
      body: {},
      headers: {
        'Cache-Control': 'no-store, no-cache, must-revalidate',
        Pragma: 'no-cache'
      }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcClaimBattleCultivationEscrowBCombat01() {
    const result = await restFetch('rpc/claim_battle_cultivation_escrow_bcombat01', { method: 'POST', body: {} });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcGetBattleChallengePreviewBCombat01(targetCharacterId) {
    const result = await restFetch('rpc/get_battle_challenge_preview_bcombat01', {
      method: 'POST',
      body: { p_target_character_id: targetCharacterId }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcChallengeBattlePowerBCombat01(targetCharacterId, requestId = createUuid()) {
    const result = await restFetch('rpc/challenge_battle_power_bcombat01', {
      method: 'POST',
      body: { p_target_character_id: targetCharacterId, p_request_id: requestId }
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

  async function rpcUpgradeTechniqueV0154(characterTechniqueId, requestId = createUuid()) {
    const result = await restFetch('rpc/upgrade_technique_v0154', {
      method: 'POST',
      body: { p_character_technique_id: characterTechniqueId, p_request_id: requestId }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcGetExclusiveTechniqueSystemV1() {
    const result = await restFetch('rpc/get_exclusive_technique_system_v1', { method: 'POST', body: {} });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcGetTechniqueLibraryV1() {
    const result = await restFetch('rpc/get_technique_library_v1', { method: 'POST', body: {} });
    return Array.isArray(result) ? result[0] || null : result;
  }

  async function rpcUseTechniqueBookV1(bookId) {
    const result = await restFetch('rpc/use_technique_book_v1', {
      method: 'POST',
      body: { p_book_id: bookId }
    });
    return Array.isArray(result) ? result[0] || null : result;
  }


  async function rpcRedeemTechniqueBookV0152(bookId, quantity = 1, requestId = crypto.randomUUID()) {
    const result = await restFetch('rpc/redeem_technique_book_v0152', {
      method: 'POST',
      body: { p_book_id: bookId, p_quantity: Number(quantity || 1), p_request_id: requestId }
    });
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

  async function rpcUpgradeExclusiveTechniqueV0154(characterExclusiveId, requestId = createUuid()) {
    const result = await restFetch('rpc/upgrade_exclusive_technique_v0154', {
      method: 'POST',
      body: { p_character_exclusive_id: characterExclusiveId, p_request_id: requestId }
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

  function mergeHistoryWithOpportunityResults(historyRows = [], opportunityRows = []) {
    const baseRows = (Array.isArray(historyRows) ? historyRows : []).filter(row => row?.event_type !== 'opportunity');
    const opportunity = Array.isArray(opportunityRows) ? opportunityRows : [];
    const unique = new Map();
    [...baseRows, ...opportunity].forEach(row => {
      const key = `${row?.event_type || 'history'}:${row?.id || row?.created_at || Math.random()}`;
      if (!unique.has(key)) unique.set(key, row);
    });
    return Array.from(unique.values()).sort((left, right) => {
      const lt = new Date(left?.created_at || 0).getTime() || 0;
      const rt = new Date(right?.created_at || 0).getTime() || 0;
      return rt - lt;
    }).slice(0, 100);
  }

  async function refreshOpportunityHistoryTimeline() {
    if (!state.character) return state.history;
    try {
      const payload = await rpcGetOpportunityHistoryV0147(100);
      const entries = Array.isArray(payload?.entries) ? payload.entries : [];
      state.history = mergeHistoryWithOpportunityResults(state.history, entries);
      if (state.details) state.details.history = state.history;
      const root = document.getElementById('historyTimelineRoot');
      if (root) root.innerHTML = historyHtml(state.history);
      return state.history;
    } catch (error) {
      console.error(error);
      return state.history;
    }
  }

  async function loadCharacterBundle() {
    const character = await getOne('player_characters', {
      select: 'id,user_id,world_id,lineage_id,generation_number,name,gender,birth_year,age,realm_stage_id,cultivation,lifespan_total,lifespan_used,comprehension,luck,mindset,karma,adversity,health_status,status,created_at',
      status: 'in.(active,secluded,missing,dead)',
      order: 'created_at.desc'
    });
    if (!character) return null;

    const [world, stage, rootLink, fateLink, historyRows, opportunityHistory] = await Promise.all([
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
      }),
      rpcGetOpportunityHistoryV0147(100).catch(() => ({ status: 'unavailable', entries: [] }))
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
        select: 'id,code,name,rarity,description,modifiers,trigger_rules',
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
      history: mergeHistoryWithOpportunityResults(historyRows, opportunityHistory?.entries)
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
        const actualBirth = await rpcGetMyBirthResultV12().catch(() => null);
        showBirthModal(
          name,
          actualBirth?.spirit_root_name || birth?.spirit_root_name || '未知灵根',
          actualBirth?.fate_name || birth?.fate_name || '未知命格',
          actualBirth || birth || {}
        );
      } catch (error) {
        const box = document.getElementById('createError');
        box.textContent = translateError(error);
        box.classList.add('show');
      } finally {
        setBusy(button, false);
      }
    });
  }

  function showBirthModal(name, spiritRoot, fate, birth = {}) {
    const rootDisplay = spiritRootDisplayHtmlV12(spiritRoot, birth);
    modalRoot.innerHTML = `
      <div class="modal-backdrop">
        <section class="modal" role="dialog" aria-modal="true" aria-labelledby="birthTitle">
          <div class="modal-seal">命</div>
          <h2 id="birthTitle">${escapeHtml(name)}，此生已定</h2>
          <p>测灵石光华流转，天道在九霄界留下了你的第一笔命书。</p>
          <div class="birth-result">
            <div><span>先天灵根</span><strong>${rootDisplay}</strong></div>
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
    const map = { healthy: '安康', injured: '负伤', wounded: '重伤', critical: '濒死' };
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
    const fateStatus = state.fateStatus?.status === 'ok' ? state.fateStatus : null;
    const unyieldingStacks = Number(fateStatus?.unyielding_stack_count || 0);
    const unyieldingBonus = Number(fateStatus?.unyielding_current_bonus || 0);
    const recoveryActive = Boolean(status.major_fall_used && status.original_target_stage_name);
    const pillStock = Math.max(0, Math.floor(Number(status.breakthrough_pill_quantity || 0)));
    const normalRate = Math.max(0, Math.min(1, Number(status.success_rate || 0)));
    const serverMaxUseful = Math.max(0, Math.floor(Number(status.max_useful_pills ?? Math.ceil(Math.max(0, 0.8 - normalRate) / 0.05))));
    const maxPills = Math.min(pillStock, serverMaxUseful);
    state.breakthroughPillQuantity = Math.max(0, Math.min(maxPills, Math.floor(Number(state.breakthroughPillQuantity || 0))));
    const selectedPills = state.breakthroughPillQuantity;
    const finalRate = Math.min(0.8, normalRate + selectedPills * 0.05);
    return `
      <div class="panel-title"><h3>境界突破</h3><span class="badge">目标 · ${escapeHtml(status.next_stage_name || '未知')}</span></div>
      <div class="breakthrough-card ${canBreakthrough ? 'cultivation-full' : ''}">
        <div class="breakthrough-heading"><div><span>下一道关</span><strong>${escapeHtml(status.next_stage_name || '未知境界')}</strong></div><div class="chance-orb"><small>本次成功率</small><b id="breakthroughChanceValue">${formatNumber(finalRate * 100, 1)}%</b></div></div>
        <div class="progress-label"><span>${canBreakthrough ? '修为已至圆满' : '累计修为'}</span><strong id="breakthroughProgressText">${formatNumber(current)} / ${formatNumber(required)}</strong></div>
        <div class="progress-track"><div id="breakthroughProgressFill" class="progress-fill" style="width:${percent}%"></div></div>
        ${canBreakthrough ? '<div class="cultivation-full-notice"><strong>修为已至圆满</strong><p>丹田灵力已臻当前境界极限，再行吐纳亦无法寸进。唯有叩问天关、完成突破，方可继续修行。</p></div>' : ''}
        <div class="breakthrough-pill-selector ${pillStock > 0 ? '' : 'is-empty'}">
          <div><span>渡境清元丹</span><strong>每枚 +5 个百分点</strong><small>库存 ${formatNumber(pillStock)} 枚 · 最终成功率上限80%</small></div>
          <div class="breakthrough-pill-controls">
            <button type="button" data-breakthrough-pill-delta="-1" ${selectedPills <= 0 ? 'disabled' : ''}>−</button>
            <b id="breakthroughPillQuantity">${formatNumber(selectedPills)}</b>
            <button type="button" data-breakthrough-pill-delta="1" ${selectedPills >= maxPills ? 'disabled' : ''}>＋</button>
          </div>
          <p id="breakthroughPillPreview">${selectedPills > 0 ? `本次使用 ${formatNumber(selectedPills)} 枚：${formatNumber(normalRate * 100, 1)}% → ${formatNumber(finalRate * 100, 1)}%` : pillStock > 0 ? `当前不使用：${formatNumber(normalRate * 100, 1)}%` : '当前没有渡境清元丹'}</p>
        </div>
        <div class="breakthrough-meta">
          <span>基础成功率：${formatNumber(Number(status.base_success_rate || 0) * 100, 1)}%</span>
          <span>天劫感悟：${formatNumber(insights)}丝（突破 +${formatNumber(insightBonus * 100, 0)}个百分点 · 总修炼速度 +${formatNumber(insights * 10, 0)}%）</span>
          ${fateStatus?.code === 'unyielding_heart' ? `<span>百折道心：${formatNumber(unyieldingStacks)} / ${formatNumber(fateStatus.unyielding_stack_limit || 4)}层（突破额外 +${formatNumber(unyieldingBonus * 100, 0)}个百分点）</span>` : ''}
          ${fateStatus?.code === 'heaven_jealous' && status.penalty_enabled !== false ? `<span>天妒劫身：渡劫成功率 -${formatNumber(Number(fateStatus.tribulation_success_penalty || 0) * 100, 0)}个百分点</span>` : ''}
          <span>最终硬上限：80%；渡境清元丹、天劫感悟、百折道心及任何其他加成都不能超过80%</span>
          <span>实际受到修为或境界惩罚后获得天劫感悟；百折道心同步获得百折。恢复周期中，中途突破成功不会清空。</span>
          <span>失败结果：道果崩解0.3% · 大跌境5% · 小跌境8% · 全损15% · 半损30% · 有惊无险41.7%</span>
          <span>道果崩解不会死亡：境界与修为回到凡人、状态变为濒死；重新达到保护下限后转为重伤。</span>
          <span>有惊无险、低境界天道护持及跌境保护拦截时，不增加天劫感悟或百折。</span>
          ${status.penalty_enabled === false ? '<span>元婴以下保护：失败不死亡、不跌境、不扣修为，已存在的恢复目标与感悟不会消失</span>' : '<span>元婴期及以上：完整天劫失败结果生效，道果崩解可穿透普通跌境保护</span>'}
          ${recoveryActive
            ? `<span>恢复周期：目标 ${escapeHtml(status.original_target_stage_name || '未知')} · 首次失败锚点 ${escapeHtml(status.major_fall_origin_stage_name || '未知')} · 普通跌境下限 ${escapeHtml(status.penalty_floor_name || '未知')}</span>`
            : '<span>首次真实突破失败后，将锁定本轮恢复目标和前一大境界同层级的普通跌境保护下限</span>'}
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
      state.heavenBalanceFetchedAt = Date.now();
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

  function opportunityHighTier(rarity) {
    return ['天品', '仙品', '专属', 'heaven', 'immortal', 'exclusive'].includes(String(rarity || ''));
  }

  function opportunityResultDetailParts(result = {}) {
    const applied = result.applied || result.result_data?.applied || {};
    const technique = result.technique || result.result_data?.technique || null;
    const parts = [];
    const cultivationGain = Math.max(0, Number(applied.cultivation_gain_actual ?? applied.cultivation_gain_requested ?? 0));
    const cultivationLoss = Math.max(0, Number(applied.cultivation_loss_actual ?? applied.cultivation_loss_requested ?? 0));
    const spiritGain = Math.max(0, Number(applied.spirit_gain || 0));
    const spiritLoss = Math.max(0, Number(applied.spirit_loss || 0));
    const speedBonus = Number(applied.speed_bonus || 0);
    const duration = Math.max(0, Number(applied.duration_minutes || 0));
    if (cultivationGain > 0) parts.push(`修为 +${formatNumber(cultivationGain)}`);
    if (cultivationLoss > 0) parts.push(`修为 -${formatNumber(cultivationLoss)}`);
    if (spiritGain > 0) parts.push(`灵石 +${formatNumber(spiritGain)}`);
    if (spiritLoss > 0) parts.push(`灵石 -${formatNumber(spiritLoss)}`);
    if (speedBonus !== 0) {
      const sign = speedBonus > 0 ? '+' : '';
      parts.push(`总修炼速度 ${sign}${formatNumber(speedBonus * 100, 2)}%${duration > 0 ? `，持续${formatNumber(duration)}分钟` : ''}`);
    }
    if (technique?.awarded) {
      const bookName = technique.book_kind === 'exclusive' ? '专属道卷' : '功法书';
      const category = technique.category === 'support' ? '辅修' : technique.category === 'main' ? '主修' : '';
      const grade = technique.grade || result.rarity_name || result.rarity || '';
      parts.push(`获得${grade || ''}${category}${bookName}《${technique.technique_name || '无名道卷'}》×${formatNumber(technique.quantity_added || 1)}`);
    }
    return parts;
  }

  function opportunityResultDetailText(result = {}) {
    const structured = String(result.result_detail || '').trim();
    if (structured) return structured;
    const parts = opportunityResultDetailParts(result);
    if (parts.length) return parts.join('；');
    return String(result.path_name === '涉险'
      ? (result.penalty_text || result.result_text || '本次涉险未记录具体代价')
      : (result.reward_text || result.result_text || '本次趋吉结果已完成结算'));
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
    const outcomeText = opportunityResultDetailText(result || {});
    const highTier = opportunityHighTier(rarityLabel) || opportunityHighTier(rarity);
    return `
      <div class="panel-title"><h3>天机推演</h3><span class="badge opportunity-grade-badge ${highTier ? 'high-tier' : ''}">${escapeHtml(result ? rarityLabel : '天机流转')}</span></div>
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

  function divineNoticeTypeMeta(type) {
    if (type === 'punishment') return { seal: '罚', title: '天道惩戒', success: false };
    if (type === 'compensation') return { seal: '补', title: '天道补偿', success: true };
    return { seal: '赏', title: '天道赏赐', success: true };
  }

  function showDivineNoticeModal(notice) {
    if (!notice?.id) return;
    const meta = divineNoticeTypeMeta(notice.notice_type);
    const delta = Number(notice.amount_delta || 0);
    const amountText = `${delta >= 0 ? '+' : '−'}${formatNumber(Math.abs(delta))} 枚灵石`;
    modalRoot.innerHTML = `
      <div class="modal-backdrop divine-notice-backdrop">
        <section class="modal divine-notice-modal ${meta.success ? 'is-reward' : 'is-punishment'}" role="dialog" aria-modal="true" aria-labelledby="divineNoticeTitle">
          <div class="modal-seal ${meta.success ? '' : 'failure-seal'}">${meta.seal}</div>
          <span class="divine-notice-eyebrow">九霄天谕 · 仅你可见</span>
          <h2 id="divineNoticeTitle">${escapeHtml(notice.title || meta.title)}</h2>
          <p>${escapeHtml(notice.content || '')}</p>
          <div class="divine-notice-summary">
            <div><span>灵石变动</span><strong>${escapeHtml(amountText)}</strong></div>
            <div><span>当前余额</span><strong>${formatNumber(notice.balance_after || 0)}</strong></div>
          </div>
          ${notice.reason ? `<div class="result-detail">缘由：${escapeHtml(notice.reason)}</div>` : ''}
          <button id="ackDivineNoticeBtn" class="primary-btn full" type="button">我已知晓</button>
        </section>
      </div>
    `;
    const button = document.getElementById('ackDivineNoticeBtn');
    button?.addEventListener('click', async () => {
      setBusy(button, true, '天谕归档中……');
      try {
        await rpcAcknowledgeDivineNoticeV1(notice.id);
        if (Number.isFinite(Number(notice.balance_after))) setLocalSpiritStoneBalance(Number(notice.balance_after));
        state.divineNoticeActive = null;
        modalRoot.innerHTML = '';
        await refreshSpiritStoneBalanceV0141(true).catch(() => {});
        setTimeout(() => checkDivineNotice(true), 120);
      } catch (error) {
        showToast(translateError(error), 'error');
        setBusy(button, false);
      }
    });
  }

  async function checkDivineNotice(silent = true) {
    if (state.divineNoticeSyncing || state.divineNoticeActive || !state.character || document.hidden) return;
    if (modalRoot?.children?.length) return;
    state.divineNoticeSyncing = true;
    try {
      const notice = await rpcClaimNextDivineNoticeV1();
      if (notice?.id) {
        state.divineNoticeActive = notice;
        showDivineNoticeModal(notice);
      }
    } catch (error) {
      if (!silent) showToast(translateError(error), 'error');
    } finally {
      state.divineNoticeSyncing = false;
    }
  }

  function showResultModal({ seal = '缘', title, message, detail = '', success = true, continueText = '确定', onContinue = null }) {
    modalRoot.innerHTML = `
      <div class="modal-backdrop">
        <section class="modal" role="dialog" aria-modal="true">
          <div class="modal-seal ${success ? '' : 'failure-seal'}">${escapeHtml(seal)}</div>
          <h2>${escapeHtml(title)}</h2>
          <p>${escapeHtml(message)}</p>
          ${detail ? `<div class="result-detail">${escapeHtml(detail)}</div>` : ''}
          <button id="resultContinueBtn" class="primary-btn full" type="button">${escapeHtml(continueText)}</button>
        </section>
      </div>
    `;
    document.getElementById('resultContinueBtn').addEventListener('click', async () => {
      modalRoot.innerHTML = '';
      if (typeof onContinue === 'function') await onContinue();
    });
  }

  function breakthroughOutcomeName(code) {
    const names = { dao_collapse:'道果崩解', major_fall:'大境跌落', minor_fall:'小境跌落', stage_reset:'道基受挫', stage_half:'灵力溃散', no_loss:'有惊无险', low_realm_no_penalty:'天道护持', major_fall_guarded:'大跌境保护', minor_fall_guarded:'小跌境保护', realm_floor_guarded:'普通跌境保护' };
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

  function updateBreakthroughPillPreview() {
    const status = state.breakthroughStatus || {};
    const normalRate = Math.max(0, Math.min(1, Number(status.success_rate || 0)));
    const stock = Math.max(0, Math.floor(Number(status.breakthrough_pill_quantity || 0)));
    const maxUseful = Math.min(stock, Math.max(0, Math.floor(Number(status.max_useful_pills ?? Math.ceil(Math.max(0, 0.8 - normalRate) / 0.05)))));
    state.breakthroughPillQuantity = Math.max(0, Math.min(maxUseful, Math.floor(Number(state.breakthroughPillQuantity || 0))));
    const quantity = state.breakthroughPillQuantity;
    const finalRate = Math.min(0.8, normalRate + quantity * 0.05);
    const quantityNode = document.getElementById('breakthroughPillQuantity');
    const chanceNode = document.getElementById('breakthroughChanceValue');
    const previewNode = document.getElementById('breakthroughPillPreview');
    if (quantityNode) quantityNode.textContent = formatNumber(quantity);
    if (chanceNode) chanceNode.textContent = `${formatNumber(finalRate * 100, 1)}%`;
    if (previewNode) previewNode.textContent = quantity > 0
      ? `本次使用 ${formatNumber(quantity)} 枚：${formatNumber(normalRate * 100, 1)}% → ${formatNumber(finalRate * 100, 1)}%`
      : stock > 0 ? `当前不使用：${formatNumber(normalRate * 100, 1)}%` : '当前没有渡境清元丹';
    document.querySelectorAll('[data-breakthrough-pill-delta]').forEach(button => {
      const delta = Number(button.dataset.breakthroughPillDelta || 0);
      button.disabled = delta < 0 ? quantity <= 0 : quantity >= maxUseful;
    });
  }

  function bindProgressionActions() {
    document.querySelectorAll('[data-breakthrough-pill-delta]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        state.breakthroughPillQuantity += Number(button.dataset.breakthroughPillDelta || 0);
        updateBreakthroughPillPreview();
      });
    });
    const breakthroughButton = document.getElementById('attemptBreakthroughBtn');
    if (breakthroughButton && breakthroughButton.dataset.bound !== '1') {
      breakthroughButton.dataset.bound = '1';
      breakthroughButton.addEventListener('click', async () => {
        const pillQuantity = Math.max(0, Math.floor(Number(state.breakthroughPillQuantity || 0)));
        setBusy(breakthroughButton, true, '正在冲关……');
        try {
          const result = await rpcAttemptBreakthrough(pillQuantity, createUuid());
          state.breakthroughPillQuantity = 0;
          const pillText = Number(result?.pill_quantity_used || pillQuantity) > 0
            ? ` 渡境清元丹消耗 ${formatNumber(result?.pill_quantity_used || pillQuantity)} 枚，丹药加成 +${formatNumber(Number(result?.pill_bonus || pillQuantity * 0.05) * 100, 0)} 个百分点。`
            : '';
          showResultModal({
            seal: result?.success ? '破' : '劫',
            title: result?.success ? `突破成功 · ${result.target_stage_name}` : `突破失败 · ${breakthroughOutcomeName(result?.outcome_code)}`,
            message: result?.message || (result?.success ? '道关已开。' : '此番冲关未成。'),
            detail: (result?.success
              ? `${Number(result.lifespan_bonus || 0) > 0 ? `寿元增加 ${formatNumber(result.lifespan_bonus)} 年。` : ''}${result.affliction_name ? ` 当前状态：${result.affliction_name}。` : ''}${result.original_target_stage_name ? ` 恢复目标仍为${result.original_target_stage_name}，天劫感悟与百折继续保留。` : ' 本轮恢复目标已达成或当前没有恢复周期，天劫感悟与百折已按规则结算。'}`
              : `${Number(result.cultivation_lost || 0) > 0 ? `修为损失 ${formatNumber(result.cultivation_lost)}，当前修为 ${formatNumber(result.cultivation_after)}。` : '境界与修为没有额外损失。'}${result.affliction_name ? ` 状态：${result.affliction_name}。` : ''}${result.insight_gained ? ` 天劫感悟 +1丝；当前共 ${formatNumber(result.heavenly_insight_count || 0)} 丝。` : ' 本次不增加天劫感悟。'}${result.original_target_stage_name ? ` 恢复目标：${result.original_target_stage_name}。` : ''}`) + pillText,
            success: Boolean(result?.success),
            onContinue: () => enterGame({ silent: true })
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


  function opportunityGradeSummaryHtml(counts = {}) {
    const grades = ['黄品', '玄品', '地品', '天品', '仙品', '专属'];
    return grades.map(grade => `<span class="offline-opportunity-grade grade-${grade}"><b>${escapeHtml(grade)}</b><em>${formatNumber(Number(counts?.[grade] || 0))}</em></span>`).join('');
  }

  function opportunitySummaryItemRows(items = {}) {
    const rows = Object.entries(items || {}).filter(([, amount]) => Number(amount || 0) !== 0);
    if (!rows.length) return '<span class="offline-opportunity-empty">无</span>';
    return rows.map(([name, amount]) => `<span>${escapeHtml(name)} ${Number(amount) > 0 ? '+' : ''}${formatNumber(amount)}</span>`).join('');
  }


  function normalizeOpportunityTechniqueBooks(value) {
    const rows = Array.isArray(value) ? value : (value && typeof value === 'object' ? Object.values(value) : []);
    const grouped = new Map();
    rows.forEach(row => {
      const code = row?.technique_code || row?.code || row?.name || row?.technique_name;
      if (!code) return;
      const key = `${row?.book_kind || row?.kind || 'ordinary'}:${code}`;
      const current = grouped.get(key) || { ...row, quantity: 0 };
      current.quantity += Math.max(1, Number(row?.quantity || row?.quantity_added || 1));
      grouped.set(key, current);
    });
    return Array.from(grouped.values());
  }

  function opportunitySummaryTechniqueRows(rows = []) {
    const list = Array.isArray(rows) ? rows : [];
    if (!list.length) return '<span class="offline-opportunity-empty">无</span>';
    return list.map(row => {
      const label = row?.name || row?.technique_name || '未知功法';
      const grade = row?.grade_name || row?.grade || '';
      const category = row?.book_kind === 'exclusive' || row?.category === 'exclusive'
        ? '专属道卷'
        : row?.category === 'support' ? '辅修功法书' : '主修功法书';
      const quantity = Math.max(1, Number(row?.quantity || row?.quantity_added || 1));
      return `<span><b>《${escapeHtml(label)}》</b>${grade ? ` · ${escapeHtml(grade)}` : ''} · ${category} ×${formatNumber(quantity)}</span>`;
    }).join('');
  }

  function opportunitySummaryTextRows(rows = []) {
    const list = Array.isArray(rows) ? rows : [];
    if (!list.length) return '<span class="offline-opportunity-empty">无</span>';
    return list.map(row => `<span>${escapeHtml(typeof row === 'string' ? row : (row?.text || row?.name || '未知效果'))}</span>`).join('');
  }

  function opportunityRemainingEffectsHtml(effects = {}) {
    const rows = [];
    const positive = effects?.positive;
    const negative = effects?.negative;
    if (positive?.rate) rows.push(`<span class="gain">修炼速度 +${formatNumber(Number(positive.rate) * 100, 0)}% · 剩余 ${formatDuration(Number(positive.remaining_seconds || 0))}</span>`);
    if (negative?.rate) rows.push(`<span class="loss">修炼速度 ${formatNumber(Number(negative.rate) * 100, 0)}% · 剩余 ${formatDuration(Number(negative.remaining_seconds || 0))}</span>`);
    if (!rows.length) return '<span class="offline-opportunity-empty">无剩余机缘效果</span>';
    rows.push(`<strong>当前综合 ${Number(effects?.net_rate || 0) >= 0 ? '+' : ''}${formatNumber(Number(effects?.net_rate || 0) * 100, 0)}%</strong>`);
    return rows.join('');
  }

  async function closeOpportunityOfflineSummary(batchId) {
    document.getElementById('opportunityOfflineSummaryBackdrop')?.remove();
    state.opportunityOfflineSummaryOpen = false;
    if (batchId) {
      try { await rpcAckOpportunitySummaryV4(batchId); } catch (error) { console.error(error); }
    }
  }

  function showOpportunityOfflineSummary(summary) {
    if (!summary?.id || state.opportunityOfflineSummaryOpen || document.getElementById('opportunityOfflineSummaryBackdrop')) return;
    state.opportunityOfflineSummaryOpen = true;
    const gains = summary.gains || {};
    const losses = summary.losses || {};
    const net = summary.net_result || {};
    const claim = summary.cultivation_claim || {};
    const gradeCounts = summary.grade_counts || {};
    const polarity = summary.polarity_counts || {};
    const techniqueBooks = normalizeOpportunityTechniqueBooks(gains.technique_books || net.technique_books || []);
    const newTechniques = Array.isArray(gains.techniques_new) ? gains.techniques_new : [];
    const duplicateTechniques = Array.isArray(gains.techniques_duplicate) ? gains.techniques_duplicate : [];
    const masteryPoints = Number(gains.mastery_points || 0);
    const permanentEffects = Array.isArray(gains.permanent_effects) ? gains.permanent_effects : [];
    const periodStart = summary.period_started_at ? new Date(summary.period_started_at) : null;
    const periodEnd = summary.period_ended_at ? new Date(summary.period_ended_at) : null;
    const seconds = periodStart && periodEnd ? Math.max(0, Math.floor((periodEnd - periodStart) / 1000)) : 0;
    const host = document.createElement('div');
    host.id = 'opportunityOfflineSummaryBackdrop';
    host.className = 'modal-backdrop opportunity-offline-summary-backdrop';
    host.innerHTML = `
      <section class="modal opportunity-offline-summary" role="dialog" aria-modal="true" aria-labelledby="opportunityOfflineSummaryTitle">
        <header class="offline-summary-header">
          <div><span class="eyebrow">离线修行结算</span><h2 id="opportunityOfflineSummaryTitle">天机未曾停歇</h2></div>
          <button class="modal-close-button" type="button" data-close-offline-summary aria-label="关闭">×</button>
        </header>
        <p class="offline-summary-lead">离线 ${formatDuration(seconds)}，共结算 <strong>${formatNumber(summary.event_count || 0)}</strong> 次机缘。</p>
        <div class="offline-opportunity-grades">${opportunityGradeSummaryHtml(gradeCounts)}</div>
        <div class="offline-opportunity-polarity"><span class="gain">趋吉 ${formatNumber(polarity['趋吉'] || 0)} 次</span><span class="loss">涉险 ${formatNumber(polarity['涉险'] || 0)} 次</span></div>
        <div class="offline-summary-grid">
          <article class="offline-summary-card gain-card"><span>趋吉所得</span><strong>修为 +${formatNumber(gains.cultivation_direct || 0)}</strong><strong>灵石 +${formatNumber(gains.spirit_stones || 0)}</strong><div class="offline-item-row">物品：${opportunitySummaryItemRows(gains.items)}</div></article>
          <article class="offline-summary-card loss-card"><span>涉险损耗</span><strong>修为 -${formatNumber(losses.cultivation_direct || 0)}</strong><strong>灵石 -${formatNumber(losses.spirit_stones || 0)}</strong><div class="offline-item-row">物品：${opportunitySummaryItemRows(losses.items)}</div></article>
        </div>
        <article class="offline-summary-card cultivation-card"><span>挂机修炼</span><strong>本次挂机获得 ${formatNumber(claim.gained || 0)} 修为</strong><small>机缘速度效果已经按离线时间顺序计入。</small></article>
        <article class="offline-summary-total"><span>本次最终所得</span><div><strong>修为 ${Number(net.cultivation || 0) >= 0 ? '+' : ''}${formatNumber(net.cultivation || 0)}</strong><strong>灵石 ${Number(net.spirit_stones || 0) >= 0 ? '+' : ''}${formatNumber(net.spirit_stones || 0)}</strong></div><div class="offline-item-row">物品：${opportunitySummaryItemRows(net.items)}</div></article>
        ${techniqueBooks.length ? `<article class="offline-summary-techniques"><span>功法书所得</span><div class="offline-technique-group"><b>已收入洞府藏经架</b>${opportunitySummaryTechniqueRows(techniqueBooks)}</div></article>` : (newTechniques.length || duplicateTechniques.length || masteryPoints > 0) ? `<article class="offline-summary-techniques"><span>功法所得</span>${newTechniques.length ? `<div class="offline-technique-group"><b>新获得</b>${opportunitySummaryTechniqueRows(newTechniques)}</div>` : ''}${duplicateTechniques.length ? `<div class="offline-technique-group"><b>重复转化</b>${opportunitySummaryTechniqueRows(duplicateTechniques)}</div>` : ''}${masteryPoints > 0 ? `<strong>传承点 +${formatNumber(masteryPoints)}</strong>` : ''}</article>` : ''}
        ${permanentEffects.length ? `<article class="offline-summary-permanent"><span>新增永久效果</span><div>${opportunitySummaryTextRows(permanentEffects)}</div></article>` : ''}
        <article class="offline-summary-effects"><span>当前剩余效果</span><div>${opportunityRemainingEffectsHtml(summary.remaining_effects || net.effects || {})}</div></article>
        ${Number(summary.capped_event_count || 0) > 0 ? `<p class="offline-summary-cap">离线机缘最多结算72小时，超出部分 ${formatNumber(summary.capped_event_count)} 次未生成。</p>` : ''}
        <button class="primary-btn offline-summary-confirm" type="button" data-close-offline-summary>确定</button>
      </section>`;
    document.body.appendChild(host);
    host.querySelectorAll('[data-close-offline-summary]').forEach(btn => btn.addEventListener('click', () => closeOpportunityOfflineSummary(summary.id)));
    host.addEventListener('click', event => { if (event.target === host) closeOpportunityOfflineSummary(summary.id); });
  }

  async function refreshOpportunity() {
    if (state.opportunitySyncing || !state.character) return;
    state.opportunitySyncing = true;
    try {
      const settlement = await rpcSettleOpportunityV4();
      state.opportunityStatus = settlement?.opportunity || state.opportunityStatus;
      state.opportunityFetchedAt = Date.now();
      if (settlement?.cultivation) {
        state.cultivationStatus = settlement.cultivation;
        state.liveCultivationBase = Number(settlement.cultivation.cultivation_total || state.liveCultivationBase || 0);
        state.liveCultivationStartedAt = Date.now();
        if (state.character) state.character.cultivation = settlement.cultivation.cultivation_total;
        updateLiveCultivationDisplay();
      }
      if (settlement?.offline_summary) showOpportunityOfflineSummary(settlement.offline_summary);
      if (Number(settlement?.events_resolved || 0) > 0) await refreshOpportunityHistoryTimeline();
      if (Number(settlement?.events_resolved || 0) > 0) await refreshCaveSystem(true);
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

  async function refreshTechniqueSystem(rebind = false, force = false) {
    if (!state.character || state.techniqueSyncing) return state.techniqueSystem;
    if (!force && (state.techniqueUpgradeProcessing || state.techniqueUpgradeQueue.length)) return state.techniqueSystem;
    state.techniqueSyncing = true;
    try {
      const system = await rpcGetTechniqueSystemV2();
      if (!system || system.status !== 'ok') return system;
      state.techniqueSystem = system;
      state.techniqueSystemFetchedAt = Date.now();
      if (state.details) state.details.techniqueSystem = system;
      const root = document.getElementById('techniqueV2Root');
      if (root && state.details) {
        root.outerHTML = techniquePanelHtml(system, state.details.inventory || []);
        bindInventoryTechniqueActions();
      }
      return system;
    } catch (error) {
      console.error(error);
      return null;
    } finally {
      state.techniqueSyncing = false;
    }
  }


  async function refreshTechniqueLibrary(rebind = true) {
    if (!state.character) return state.techniqueLibrary;
    try {
      const library = await rpcGetTechniqueLibraryV1();
      state.techniqueLibrary = library || { status: 'unavailable', books: [] };
      if (state.details) state.details.techniqueLibrary = state.techniqueLibrary;
      if (document.getElementById('caveSystemRoot')) {
        renderCaveSystemFromState();
      } else if (rebind) {
        bindInventoryTechniqueActions();
      }
      return state.techniqueLibrary;
    } catch (error) {
      console.error(error);
      return state.techniqueLibrary;
    }
  }


  async function refreshExclusiveTechniqueSystem(rebind = false, force = false) {
    if (!state.character) return state.exclusiveTechniqueSystem;
    if (!force && (state.techniqueUpgradeProcessing || state.techniqueUpgradeQueue.length)) return state.exclusiveTechniqueSystem;
    try {
      const system = await rpcGetExclusiveTechniqueSystemV1();
      if (!system || system.status !== 'ok') return system;
      state.exclusiveTechniqueSystem = system;
      if (state.details) state.details.exclusiveTechniqueSystem = system;
      const root = document.getElementById('exclusiveTechniqueRoot');
      if (root && state.details) {
        root.outerHTML = exclusiveTechniquePanelHtml(system, state.details.inventory || []);
        bindExclusiveTechniqueActions();
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
      const [system, techniqueLibrary] = await Promise.all([
        rpcGetCaveSystemV1(),
        rpcGetTechniqueLibraryV1().catch(error => ({ status: 'unavailable', books: [], error: translateError(error) }))
      ]);
      if (!system || system.status !== 'ok') return system;
      state.caveSystem = system;
      state.caveSystemFetchedAt = Date.now();
      state.techniqueLibrary = techniqueLibrary || { status: 'unavailable', books: [] };
      if (Number.isFinite(Number(system.spirit_stones))) setLocalSpiritStoneBalance(Number(system.spirit_stones));
      if (state.details) {
        state.details.caveSystem = system;
        state.details.techniqueLibrary = state.techniqueLibrary;
      }
      const root = document.getElementById('caveSystemRoot');
      if (root && state.details) {
        root.outerHTML = cavePanelHtml(system, state.details.inventory || [], state.techniqueLibrary);
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
      ordinary: '普通功法',
      exclusive: '专属功法',
      main: '普通功法',
      support: '普通功法',
      divine_ability: '神通',
      body: '炼体功法',
      movement: '身法'
    };
    return map[value] || value || '普通功法';
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
    if (useType === 'spirit_root_reroll') return '按角色初生时完全相同的概率重新随机并替换当前灵根，结果可能更好、相同或更差。';
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
      ordinary_1: '第一槽 · 100%',
      ordinary_2: '第二槽 · 60%',
      ordinary_3: '第三槽 · 50%',
      ordinary_4: '第四槽 · 40%',
      ordinary_5: '第五槽 · 30%',
      main: '第一槽 · 100%',
      support_1: '第二槽 · 60%',
      support_2: '第三槽 · 50%'
    };
    return map[value] || '未运转';
  }

  function techniqueSlotMultiplier(value) {
    const map = {
      ordinary_1: 1,
      ordinary_2: 0.6,
      ordinary_3: 0.5,
      ordinary_4: 0.4,
      ordinary_5: 0.3,
      main: 1,
      support_1: 0.6,
      support_2: 0.5
    };
    return Number(map[value] || 0);
  }

  function techniqueGradeClass(value) {
    return `grade-${String(value || 'mortal').replace(/[^a-z0-9_-]/gi, '')}`;
  }

  function techniqueV2EffectValues(row, targetLevel = null) {
    const fixed = row?.fixed_effects || row?.definition?.fixed_effects || {};
    const level = Math.max(1, Number(targetLevel ?? row?.level ?? 1));
    const growth = 0.10;
    const factor = 1 + growth * (level - 1);
    const flatBase = Number(fixed.v3_base_cultivation_per_second ?? fixed.cultivation_per_second ?? 0);
    const rawMultiplier = Number(fixed.v3_base_cultivation_multiplier ?? fixed.cultivation_multiplier ?? 0);
    const multiplierBase = rawMultiplier > 1 ? rawMultiplier - 1 : Math.max(0, rawMultiplier);
    return {
      flat: flatBase * factor,
      multiplier: multiplierBase * factor,
      factor,
      growth
    };
  }

  function techniqueGradeRulesLocalV0154(grade) {
    const rules = {
      exclusive: { maxLevel: 36, factor: 1.00 }, immortal: { maxLevel: 30, factor: 0.95 },
      heaven: { maxLevel: 24, factor: 0.90 }, earth: { maxLevel: 18, factor: 0.85 },
      mystic: { maxLevel: 12, factor: 0.80 }, yellow: { maxLevel: 6, factor: 0.75 }
    };
    return rules[grade] || rules.yellow;
  }

  function techniqueCostLocalV0154(grade, level, mastery = false) {
    const rule = techniqueGradeRulesLocalV0154(grade);
    return mastery
      ? Math.ceil(1049 * Math.pow(Math.max(1, rule.maxLevel - 1), 2) * rule.factor * 1.5)
      : Math.ceil(1049 * Math.pow(Math.max(1, Number(level || 1)), 2) * rule.factor);
  }

  function localTechniqueContributionV0154() {
    let flat = 0;
    let multiplier = 0;
    const ordinary = Array.isArray(state.techniqueSystem?.techniques) ? state.techniqueSystem.techniques : [];
    ordinary.forEach(row => {
      const slot = Number(row?.slot_multiplier ?? techniqueSlotMultiplier(row?.equipped_slot));
      if (!row?.equipped_slot || slot <= 0) return;
      const values = techniqueV2EffectValues(row);
      const mastery = row?.is_mastered ? 1.2 : 1;
      flat += values.flat * slot * mastery;
      multiplier += values.multiplier * slot * mastery;
    });
    const exclusive = Array.isArray(state.exclusiveTechniqueSystem?.techniques) ? state.exclusiveTechniqueSystem.techniques : [];
    exclusive.forEach(row => {
      if (row?.equipped) multiplier += Math.max(0, Number(row.effect_multiplier_bonus || 0));
    });
    return { flat, multiplier };
  }

  function recalculateCultivationRateLocalV0154() {
    if (!state.cultivationStatus) return;
    const currentCultivation = currentDisplayedCultivation();
    state.liveCultivationBase = currentCultivation;
    state.liveCultivationStartedAt = Date.now();
    const contribution = localTechniqueContributionV0154();
    const cultivation = state.cultivationStatus;
    cultivation.technique_flat_rate = contribution.flat;
    cultivation.technique_multiplier_bonus = contribution.multiplier;
    const fixed = Number(cultivation.base_rate_per_second || 0) + contribution.flat + Number(cultivation.effect_flat_rate || 0);
    const additive = Math.max(0, 1 + Number(cultivation.fate_bonus || 0) + contribution.multiplier + Number(cultivation.effect_multiplier_bonus || 0));
    const insightMultiplier = 1 + Math.max(0, Number(state.breakthroughStatus?.heavenly_insight_count || 0)) * 0.10;
    const cap = Number(state.breakthroughStatus?.cultivation_cap || state.breakthroughStatus?.cultivation_required || 0);
    cultivation.current_rate_per_second = cap > 0 && currentCultivation >= cap
      ? 0
      : Math.max(0, fixed * Number(cultivation.root_multiplier || 1) * additive * Number(cultivation.qi_multiplier || 1) * insightMultiplier);
    const rateText = formatRate(cultivation.current_rate_per_second);
    const live = document.getElementById('liveRateValue');
    const hud = document.getElementById('cultivationRateText');
    const flatNode = document.getElementById('techniqueFlatRateSummary');
    const multiplierNode = document.getElementById('techniqueMultiplierSummary');
    if (live) live.textContent = rateText;
    if (hud) hud.textContent = rateText;
    if (flatNode) flatNode.textContent = `+${formatNumber(contribution.flat, 3)}/秒`;
    if (multiplierNode) multiplierNode.textContent = `+${formatNumber(contribution.multiplier * 100, 2)}%`;
  }

  function renderTechniqueSystemsFromStateV0154() {
    const inventory = state.details?.inventory || [];
    const ordinaryRoot = document.getElementById('techniqueV2Root');
    if (ordinaryRoot) ordinaryRoot.outerHTML = techniquePanelHtml(state.techniqueSystem || {}, inventory);
    const exclusiveRoot = document.getElementById('exclusiveTechniqueRoot');
    if (exclusiveRoot) exclusiveRoot.outerHTML = exclusiveTechniquePanelHtml(state.exclusiveTechniqueSystem || {}, inventory);
    bindInventoryTechniqueActions();
    bindExclusiveTechniqueActions();
  }

  function optimisticTechniqueUpgradeV0154(kind, id) {
    const ordinary = kind === 'ordinary';
    const rows = ordinary ? state.techniqueSystem?.techniques : state.exclusiveTechniqueSystem?.techniques;
    const row = Array.isArray(rows) ? rows.find(item => String(ordinary ? item.character_technique_id : item.id) === String(id)) : null;
    if (!row || row.is_mastered) {
      showToast('这门功法已经圆满。', 'error');
      return;
    }
    const grade = ordinary ? (row.grade_code || row.raw_grade || 'yellow') : 'exclusive';
    const level = Math.max(1, Number(row.level || 1));
    const maxLevel = Math.max(level, Number(row.max_level || techniqueGradeRulesLocalV0154(grade).maxLevel));
    const mastery = level >= maxLevel;
    const cost = Math.max(0, Number(ordinary ? row.upgrade_cost : row.next_upgrade_cost) || techniqueCostLocalV0154(grade, level, mastery));
    const balance = currentSpiritStoneBalance();
    if (balance < cost) {
      showToast(`灵石不足，尚缺 ${formatNumber(cost - balance)}。`, 'error');
      return;
    }
    const currentCultivation = currentDisplayedCultivation();
    state.liveCultivationBase = currentCultivation;
    state.liveCultivationStartedAt = Date.now();
    setLocalSpiritStoneBalance(balance - cost);
    if (mastery) row.is_mastered = true;
    else row.level = level + 1;
    const newLevel = Number(row.level || level);
    if (ordinary) {
      row.can_upgrade = !row.is_mastered;
      row.can_master = newLevel >= maxLevel && !row.is_mastered;
      row.upgrade_cost = row.is_mastered ? 0 : techniqueCostLocalV0154(grade, newLevel, newLevel >= maxLevel);
    } else {
      const base = Math.max(0, Number(row.base_cultivation_multiplier || 0));
      row.effect_multiplier_bonus = base * (1 + Math.max(0, newLevel - 1) * 0.10) * (row.is_mastered ? 1.2 : 1);
      row.next_upgrade_cost = row.is_mastered ? 0 : techniqueCostLocalV0154('exclusive', newLevel, newLevel >= maxLevel);
    }
    renderTechniqueSystemsFromStateV0154();
    recalculateCultivationRateLocalV0154();
    state.techniqueUpgradeQueue.push({ kind, id, requestId: createUuid() });
    processTechniqueUpgradeQueueV0154();
  }

  async function processTechniqueUpgradeQueueV0154() {
    if (state.techniqueUpgradeProcessing) return;
    state.techniqueUpgradeProcessing = true;
    let failure = null;
    try {
      while (state.techniqueUpgradeQueue.length) {
        const operation = state.techniqueUpgradeQueue.shift();
        const result = operation.kind === 'ordinary'
          ? await rpcUpgradeTechniqueV0154(operation.id, operation.requestId)
          : await rpcUpgradeExclusiveTechniqueV0154(operation.id, operation.requestId);
        const remaining = Number(result?.spirit_stones_after ?? result?.spirit_stones_remaining);
        if (Number.isFinite(remaining)) setLocalSpiritStoneBalance(remaining);
      }
    } catch (error) {
      failure = error;
      state.techniqueUpgradeQueue.length = 0;
    } finally {
      state.techniqueUpgradeProcessing = false;
    }
    await Promise.all([
      refreshTechniqueSystem(true, true),
      refreshExclusiveTechniqueSystem(true, true),
      refreshSpiritStoneBalanceV0141(true),
      refreshCultivationEffectsV0154(),
      syncCultivation(true)
    ]).catch(() => {});
    if (failure) showToast(`功法状态已按云端结果校正：${translateError(failure)}`, 'error');
  }


  function techniqueV2EffectText(row) {
    const fixed = row?.fixed_effects || row?.definition?.fixed_effects || {};
    const level = Math.max(1, Number(row?.level || 1));
    const maxLevel = Math.max(level, Number(row?.max_level || level));
    const current = techniqueV2EffectValues(row, level);
    const next = techniqueV2EffectValues(row, Math.min(maxLevel, level + 1));
    const slotMultiplier = Number(row?.slot_multiplier ?? techniqueSlotMultiplier(row?.equipped_slot));
    const masteryMultiplier = row?.is_mastered ? 1.2 : 1;
    const actualFlat = current.flat * slotMultiplier * masteryMultiplier;
    const actualMultiplier = current.multiplier * slotMultiplier * masteryMultiplier;
    const parts = [];
    if (current.flat) parts.push(`本层基础每秒修为 +${formatNumber(current.flat, 3)}`);
    if (current.multiplier) parts.push(`本层基础修炼速度 +${formatNumber(current.multiplier * 100, 2)}%`);
    if (row?.equipped_slot) {
      if (actualFlat) parts.push(`实际贡献 +${formatNumber(actualFlat, 3)}/秒`);
      if (actualMultiplier) parts.push(`实际贡献 +${formatNumber(actualMultiplier * 100, 2)}%`);
    } else {
      parts.push('未装备，当前不计入属性池');
    }
    if (!row?.is_mastered && level < maxLevel) {
      if (next.flat) parts.push(`下一级基础 +${formatNumber(next.flat, 3)}/秒`);
      if (next.multiplier) parts.push(`下一级基础 +${formatNumber(next.multiplier * 100, 2)}%`);
    }
    if (row?.is_mastered) parts.push('已圆满 · 数值型效果 ×120%');
    else if (level >= maxLevel) parts.push('已满级 · 可支付灵石圆满');
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
              const mastered = Boolean(row.is_mastered);
              const canUpgrade = !mastered;
              const equipLabel = row.equipped ? '专属运转中' : '设为专属';
              const levelUpText = mastered ? '已圆满' : (level < maxLevel ? `精进 · ${formatNumber(row.next_upgrade_cost || 0)} 灵石` : `圆满 · ${formatNumber(row.next_upgrade_cost || 0)} 灵石`);
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
                    <span>${mastered ? '已圆满 · 数值效果×120%' : (level >= maxLevel ? '可进行圆满' : '每级增加一级基础效果10%')}</span>
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
    const stone = (inventory || []).find(row => row.definition?.code === 'spirit_stone');
    const stones = Number(stone?.quantity ?? system?.spirit_stones ?? 0);
    const slots = system?.slots || {};
    const openSlots = Math.max(0, Math.min(5, Number(system?.open_ordinary_slots || 0)));
    if (!rows.length) return '<div id="techniqueV2Root"><div class="empty-state">尚未习得功法。</div></div>';

    return `
      <div id="techniqueV2Root" class="technique-v2-root">
        <div class="resource-inline"><span>可用灵石</span><strong data-spirit-stone-balance>${formatNumber(stones)}</strong></div>
        <div class="technique-slot-grid">
          ${['ordinary_1', 'ordinary_2', 'ordinary_3', 'ordinary_4', 'ordinary_5'].map((slot, index) => {
            const equipped = rows.find(row => row.character_technique_id === slots?.[slot] || row.equipped_slot === slot);
            const unlocked = index < openSlots;
            return `<article class="technique-slot ${equipped ? 'filled' : ''} ${unlocked ? '' : 'locked'}">
              <span>${escapeHtml(techniqueSlotName(slot))}</span>
              <strong>${escapeHtml(unlocked ? (equipped?.name || '空置') : '境界未解锁')}</strong>
              <small>${unlocked ? (equipped ? `${escapeHtml(equipped.grade_name || '黄品')} · 第 ${formatNumber(equipped.level)} 层` : '在功法卡中选择此槽') : '每突破一个大境界开放一槽'}</small>
            </article>`;
          }).join('')}
        </div>
        <div class="technique-rule-note">
          <strong>普通功法五槽</strong>
          <span>第一至第五槽依次发挥100%、60%、50%、40%、30%。升级只消耗灵石；达到品级上限后可圆满，数值型效果×120%。熟练度与传承点已取消。</span>
        </div>
        ${openSlots < 1 ? '<div class="empty-state">凡人境可以持有和兑换道卷，但不能学习、装备、升级或圆满功法。</div>' : ''}
        <div class="technique-manage-list">
          ${rows.map(row => {
            const equippedSlot = row.equipped_slot || '';
            const equipped = Boolean(equippedSlot);
            const level = Number(row.level || 1);
            const maxLevel = Number(row.max_level || 6);
            const mastered = Boolean(row.is_mastered);
            const canProgress = Boolean(row.can_upgrade) && !mastered && openSlots > 0;
            const progressLabel = mastered ? '已圆满' : (level >= maxLevel ? `圆满 · ${formatNumber(row.upgrade_cost || 0)} 灵石` : `精进 · ${formatNumber(row.upgrade_cost || 0)} 灵石`);
            const defaultSlot = equippedSlot || (openSlots > 0 ? 'ordinary_1' : 'none');
            return `
              <article class="manage-card technique-v2-card ${equipped ? 'equipped' : ''}">
                <div class="manage-card-head">
                  <div>
                    <span class="technique-grade ${escapeHtml(techniqueGradeClass(row.grade_code))}">${escapeHtml(row.grade_name || '黄品')}</span>
                    <strong>${escapeHtml(row.name || '未知功法')} <small>第 ${level}/${maxLevel} 层</small></strong>
                  </div>
                  <span class="badge">${escapeHtml(equipped ? techniqueSlotName(equippedSlot) : '普通功法')}</span>
                </div>
                <p>${escapeHtml(techniqueV2EffectText(row))}</p>
                <small class="manage-description">${escapeHtml(row.description || '')}</small>
                <div class="technique-progress-copy">
                  <span>获得 ${formatNumber(row.acquisition_count || 1)} 次</span>
                  <span>等级成长 ×${formatNumber(1 + Math.max(0, level - 1) * 0.10, 2)}</span>
                  <span>${mastered ? '圆满 ×1.20' : '未圆满'}</span>
                </div>
                <div class="technique-slot-actions">
                  <select data-technique-target-for="${escapeHtml(row.character_technique_id)}" ${openSlots > 0 ? '' : 'disabled'}>
                    ${equipped ? '<option value="none">停止运转</option>' : ''}
                    ${[1,2,3,4,5].map(index => {
                      const slot = `ordinary_${index}`;
                      const locked = index > openSlots;
                      return `<option value="${slot}" ${slot === defaultSlot ? 'selected' : ''} ${locked ? 'disabled' : ''}>${escapeHtml(techniqueSlotName(slot))}${locked ? ' · 未解锁' : ''}</option>`;
                    }).join('')}
                  </select>
                  <button class="ghost-btn" type="button" data-apply-technique-slot="${escapeHtml(row.character_technique_id)}" ${openSlots > 0 ? '' : 'disabled'}>${equipped ? '调整槽位' : '装备功法'}</button>
                </div>
                <div class="manage-actions">
                  <button class="primary-btn" type="button" data-upgrade-technique-v2="${escapeHtml(row.character_technique_id)}" ${canProgress ? '' : 'disabled'}>${escapeHtml(progressLabel)}</button>
                </div>
              </article>
            `;
          }).join('')}
        </div>
      </div>
    `;
  }

  function techniqueBookFirstRewardText(spec = {}) {
    const parts = [];
    if (Number(spec.permanent_speed_bonus || 0)) parts.push(`永久修炼速度 +${formatNumber(Number(spec.permanent_speed_bonus) * 100, 2)}%`);
    if (Number(spec.permanent_flat_rate || 0)) parts.push(`永久每秒修为 +${formatNumber(spec.permanent_flat_rate, 3)}`);
    if (Number(spec.cultivation_gain_pct || 0)) parts.push(`修为 +当前小境界需求的 ${formatNumber(Number(spec.cultivation_gain_pct) * 100, 2)}%`);
    if (Number(spec.cultivation_gain_fixed || 0)) parts.push(`修为 +${formatNumber(spec.cultivation_gain_fixed)}`);
    if (Number(spec.spirit_gain_mult || 0)) parts.push(`灵石 +境界基数×${formatNumber(spec.spirit_gain_mult, 2)}`);
    if (Number(spec.spirit_gain_fixed || 0)) parts.push(`灵石 +${formatNumber(spec.spirit_gain_fixed)}`);
    if (Number(spec.cave_daily_spirit_mapping || 0)) parts.push(`洞府资源映射 +${formatNumber(spec.cave_daily_spirit_mapping)}`);
    return parts.join(' · ') || '无额外首次研习奖励';
  }

  function techniqueBookEffectText(row = {}) {
    if (row.book_kind === 'exclusive') {
      return `一级修炼速度 +${formatNumber(Number(row.base_cultivation_multiplier || 0) * 100, 2)}% · 专属槽生效`;
    }
    const values = techniqueV2EffectValues({ fixed_effects: row.fixed_effects || {}, level: 1 }, 1);
    const parts = [];
    if (values.flat) parts.push(`一级每秒修为 +${formatNumber(values.flat, 3)}`);
    if (values.multiplier) parts.push(`一级修炼速度 +${formatNumber(values.multiplier * 100, 2)}%`);
    return parts.join(' · ') || '研习后加入功法列表，自行装备后生效';
  }

  function techniqueLibraryHtml(library = {}) {
    const books = Array.isArray(library?.books) ? library.books : [];
    const total = books.reduce((sum, row) => sum + Math.max(0, Number(row?.quantity || 0)), 0);
    return `
      <div class="subsection-title technique-library-title"><strong>藏经架</strong><span>${formatNumber(books.length)} 种道卷 · 共 ${formatNumber(total)} 本</span></div>
      <p class="technique-library-note">所有道卷均可自主选择研习、保留或兑换灵石。凡人境不能研习功法；未研习的唯一道卷也允许兑换。</p>
      <div class="inventory-grid technique-book-grid">
        ${books.length ? books.map(row => {
          const isExclusive = row.book_kind === 'exclusive';
          const actionLabel = row.can_learn ? '研习' : row.can_contemplate ? '参悟' : row.is_learned ? '已研习·留存' : row.locked_reason || '无法研习';
          const actionEnabled = Boolean(row.can_learn);
          const fateLabel = isExclusive ? (row.is_matching_fate ? '本命契合' : `异命·${row.fate_name || '命格不符'}`) : techniqueCategoryName(row.category);
          return `<article class="inventory-card technique-book-card ${isExclusive ? 'exclusive-book' : ''} ${!actionEnabled ? 'locked' : ''}">
            <div class="inventory-icon">卷</div>
            <div class="inventory-copy">
              <span>${escapeHtml(row.grade_name || row.grade_code || '功法')} · ${escapeHtml(fateLabel)}</span>
              <strong>《${escapeHtml(row.name || '未知道卷')}》 <small>× ${formatNumber(row.quantity || 0)}</small></strong>
              <p>${escapeHtml(row.description || '道纹沉静，等待有缘人展开研习。')}</p>
              <small class="technique-book-effect">功法效果：${escapeHtml(techniqueBookEffectText(row))}</small>
              ${!isExclusive ? `<small class="technique-book-reward">首次研习：${escapeHtml(techniqueBookFirstRewardText(row.first_reward_spec || {}))}</small>` : ''}
              ${isExclusive && !row.is_matching_fate ? '<small class="technique-book-lock">当前命格不契合，不能学习、不能装备、不会产生效果。</small>' : ''}
            </div>
            <div class="technique-book-actions">
              <button class="${actionEnabled ? 'primary-btn' : 'ghost-btn'} technique-book-action" type="button" data-use-technique-book="${escapeHtml(row.book_id)}" ${actionEnabled ? '' : 'disabled'}>${escapeHtml(actionLabel)}</button>
              <button class="ghost-btn technique-book-redeem" type="button" data-redeem-technique-book="${escapeHtml(row.book_id)}" data-technique-name="${escapeHtml(row.name || '功法道卷')}" data-technique-quantity="${formatNumber(row.quantity || 0)}" data-technique-redeem-price="${formatNumber(row.redeem_value || 0)}">兑换灵石</button>
            </div>
          </article>`;
        }).join('') : '<div class="empty-state">藏经架尚无功法书。机缘获得后会自动收入此处。</div>'}
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

  const CAVE_STORAGE_SLOT_COUNT_B01 = 36;

  function caveTechniqueBookRarityV1(grade) {
    const map = { exclusive: 'legendary', immortal: 'legendary', heaven: 'epic', earth: 'rare', mystic: 'uncommon', yellow: 'common' };
    return map[String(grade || '').toLowerCase()] || 'uncommon';
  }

  function caveTechniqueBookStorageItemsV1(techniqueLibrary = {}) {
    return (Array.isArray(techniqueLibrary?.books) ? techniqueLibrary.books : [])
      .filter(row => row && Number(row.quantity || 0) > 0 && !row.is_learned)
      .map(row => ({
        id: `technique-book:${row.book_id}`,
        quantity: Number(row.quantity || 0),
        is_bound: true,
        is_technique_book_v1: true,
        technique_book_v1: row,
        definition: {
          code: `technique_book_${row.technique_code || row.book_id}`,
          name: `《${row.name || '未知道卷'}》`,
          category: 'technique',
          rarity: caveTechniqueBookRarityV1(row.grade_code || row.grade_name),
          stack_limit: Math.max(1, Number(row.quantity || 1)),
          description: row.description || '尚未研习的功法道卷，已收入洞府藏经架。',
          effects: { use_type: 'learn_technique' }
        }
      }));
  }

  function caveStorageItemsB01(inventory, techniqueLibrary = state.techniqueLibrary || { books: [] }) {
    const items = (Array.isArray(inventory) ? inventory : [])
      .filter(row => row?.definition && Number(row.quantity || 0) > 0);
    const combined = [...items, ...caveTechniqueBookStorageItemsV1(techniqueLibrary)];
    if (state.caveInventorySortMode !== 'tidy') return combined;
    const rarityOrder = { legendary: 0, epic: 1, rare: 2, uncommon: 3, common: 4 };
    return [...combined].sort((left, right) => {
      const leftDefinition = left.definition || {};
      const rightDefinition = right.definition || {};
      const rarity = Number(rarityOrder[leftDefinition.rarity] ?? 9) - Number(rarityOrder[rightDefinition.rarity] ?? 9);
      if (rarity) return rarity;
      const category = String(leftDefinition.category || '').localeCompare(String(rightDefinition.category || ''), 'zh-CN');
      if (category) return category;
      return String(leftDefinition.name || '').localeCompare(String(rightDefinition.name || ''), 'zh-CN');
    });
  }

  function caveItemTypeLabelV1(row = {}) {
    if (row.is_technique_book_v1) return '功法';
    const definition = row.definition || {};
    const code = String(definition.code || '').toLowerCase();
    const name = String(definition.name || '');
    const category = String(definition.category || '').toLowerCase();
    const useType = String(definition.effects?.use_type || '').toLowerCase();
    if (code === 'spirit_stone' || name.includes('灵石')) return '灵石';
    if (category.includes('pill') || category.includes('medicine') || useType || name.includes('丹')) return '丹药';
    if (category.includes('herb') || name.includes('草') || name.includes('药材')) return '灵草';
    if (category.includes('ore') || name.includes('矿') || name.includes('铁')) return '灵矿';
    if (category.includes('incense') || name.includes('香')) return '香品';
    if (category.includes('tea') || name.includes('茶')) return '灵茶';
    if (category.includes('quest') || name.includes('符') || name.includes('令')) return '信物';
    if (category.includes('book') || category.includes('scroll') || name.includes('卷') || name.includes('经')) return '典籍';
    return '物品';
  }

  function caveItemRarityClassB01(value) {
    return ['common', 'uncommon', 'rare', 'epic', 'legendary'].includes(value) ? value : 'common';
  }

  function caveItemCornerMarkB01(row = {}) {
    if (row.is_technique_book_v1) return ['功', 'rare'];
    const definition = row.definition || {};
    const category = String(definition.category || '').toLowerCase();
    if (row.is_bound) return ['绑', 'bound'];
    if (category.includes('quest') || category.includes('任务')) return ['任', 'quest'];
    if (definition.code === 'spirit_washing_pill_v0154') return ['珍', 'rare'];
    if (definition.effects?.use_type === 'spirit_root_reroll') return ['珍', 'rare'];
    return ['', ''];
  }

  function caveItemIconKindB01(row = {}) {
    if (row.is_technique_book_v1) return 'scroll';
    const definition = row.definition || {};
    const code = String(definition.code || '').toLowerCase();
    const name = String(definition.name || '');
    const category = String(definition.category || '').toLowerCase();
    const useType = String(definition.effects?.use_type || '').toLowerCase();
    if (code === 'spirit_stone' || name.includes('灵石')) return 'spirit-stone';
    if (name.includes('香') || category.includes('incense')) return 'incense-burner';
    if (name.includes('茶') || category.includes('tea')) return 'tea-bowl';
    if (name.includes('矿') || name.includes('铁') || category.includes('ore')) return 'ore';
    if (name.includes('草') || name.includes('药材') || category.includes('herb')) return 'herb';
    if (name.includes('符') || name.includes('令') || category.includes('quest')) return 'talisman';
    if (name.includes('卷') || name.includes('经') || category.includes('book') || category.includes('scroll')) return 'scroll';
    if (useType || name.includes('丹') || category.includes('pill') || category.includes('medicine')) return 'jade-gourd';
    return 'relic';
  }

  function caveItemIconHtmlB01(row = {}, large = false) {
    const kind = caveItemIconKindB01(row);
    const className = `cave-item-svg ${large ? 'large' : ''}`;
    const icons = {
      'spirit-stone': `<svg class="${className}" viewBox="0 0 80 80" aria-hidden="true"><path class="jade-light" d="M16 55 11 38 24 18 39 11 53 18 67 38 60 58 40 69z"/><path class="paper-line" d="m24 18 9 21-22-1m42-20-11 21 25-1M33 39h9l-2 30"/><circle class="gold-line" cx="40" cy="42" r="11"/><path class="gold-line" d="M34 42c4-7 8-7 12 0-4 7-8 7-12 0zm6-8v16"/></svg>`,
      'jade-gourd': `<svg class="${className}" viewBox="0 0 80 80" aria-hidden="true"><path class="paper-fill" d="M35 8h10l2 10c8 5 13 13 12 23-1 17-9 29-19 29S22 58 21 41c-1-10 4-18 12-23z"/><path class="jade-line" d="M31 21c6 4 13 4 18 0M27 50c9 6 17 6 26 0"/><path class="red-fill" d="M27 29h26l-3 19-10 7-10-7z"/><path class="gold-line" d="M32 35h16m-13 6h10m-7 6h4"/><circle class="gold-fill" cx="40" cy="59" r="5"/></svg>`,
      'incense-burner': `<svg class="${className}" viewBox="0 0 80 80" aria-hidden="true"><path class="bronze-fill" d="M26 35h28l-3 23H29z"/><path class="gold-line" d="M22 34h36l-4-7H26zm9 24h18l5 7H26zM31 43h18m-15 7h12"/><path class="mist-line" d="M35 28C25 20 43 16 34 5c14 7 0 15 8 22 8-7-2-11 5-19"/><circle class="jade-fill" cx="40" cy="44" r="4"/></svg>`,
      'tea-bowl': `<svg class="${className}" viewBox="0 0 80 80" aria-hidden="true"><path class="celadon-fill" d="M22 34h36l-4 26H26z"/><path class="paper-line" d="M18 31h44l-5-8H23zm13-12h18l5 4H26zM26 61h28l5 5H21z"/><path class="jade-line" d="M33 43c7-9 13-7 15 2-7 7-12 6-15-2zm7-1c-1 5-3 8-6 11"/><path class="mist-line" d="M33 18c-7-7 8-9 1-17 12 7 0 11 6 17m5 0c-4-5 5-7 2-12"/></svg>`,
      'ore': `<svg class="${className}" viewBox="0 0 80 80" aria-hidden="true"><path class="ore-fill" d="M14 55 19 30 34 12l20 5 13 21-8 24-26 7z"/><path class="paper-line" d="m19 30 20 8-5-26m5 26 20 24m-20-24 15-21M14 55l25-17"/><path class="gold-line" d="M30 43c6-8 14-8 20 0-6 8-14 8-20 0zm10-7v14"/></svg>`,
      'herb': `<svg class="${className}" viewBox="0 0 80 80" aria-hidden="true"><path class="gold-line" d="M39 67c-1-17 2-33 9-48"/><path class="jade-fill" d="M44 34c7-13 17-16 25-11-4 12-12 18-25 11zm-3 10c-12-8-22-7-28 0 8 9 18 10 28 0zm5-20c-5-11-2-19 5-23 7 8 6 17-5 23z"/><path class="paper-line" d="M24 44c8 1 13 0 17-3m6-9c7-1 12-4 16-8"/></svg>`,
      'talisman': `<svg class="${className}" viewBox="0 0 80 80" aria-hidden="true"><path class="bronze-fill" d="M24 10h32l5 8-4 46-17 7-17-7-4-46z"/><path class="ink-fill" d="M29 19h22l2 35-13 7-13-7z"/><path class="gold-line" d="M34 25c6-5 12-4 15 2-6 5-11 5-15-2zm-2 12h16m-13 7h10m-8 7h6"/><circle class="gold-fill" cx="40" cy="15" r="3"/></svg>`,
      'scroll': `<svg class="${className}" viewBox="0 0 80 80" aria-hidden="true"><path class="paper-fill" d="M23 13h35c-5 4-5 10 0 14v39H23c5-5 5-10 0-15z"/><path class="bronze-fill" d="M18 12h10v16H18c-8 0-8-16 0-16zm0 39h10v16H18c-8 0-8-16 0-16z"/><path class="red-line" d="M33 25h17m-17 8h17m-17 8h12m-12 8h17"/><circle class="gold-line" cx="46" cy="56" r="7"/></svg>`,
      'relic': `<svg class="${className}" viewBox="0 0 80 80" aria-hidden="true"><path class="bronze-fill" d="M40 9 58 20l7 21-10 21-15 9-15-9-10-21 7-21z"/><path class="ink-fill" d="M40 20 52 30l-4 20-8 8-8-8-4-20z"/><path class="gold-line" d="M40 20v38M28 30h24M32 50h16"/><circle class="jade-fill" cx="40" cy="39" r="6"/></svg>`
    };
    return icons[kind] || icons.relic;
  }

  function caveBuildingGlyphB01(row = {}, index = 0) {
    const value = `${row.code || ''} ${row.name || ''}`.toLowerCase();
    if (/alchemy|furnace|丹/.test(value)) return '丹';
    if (/herb|garden|药/.test(value)) return '药';
    if (/library|scripture|book|藏经/.test(value)) return '经';
    if (/warehouse|storage|藏|库/.test(value)) return '藏';
    if (/forge|refin|器/.test(value)) return '器';
    if (/beast|兽/.test(value)) return '兽';
    if (/ore|mine|矿/.test(value)) return '矿';
    if (/qi|spirit|聚灵|灵脉/.test(value)) return '气';
    return ['气', '药', '经', '丹', '器', '兽'][index % 6];
  }

  function caveBuildingPanelKindB01(row = {}) {
    const value = `${row.code || ''} ${row.name || ''}`.toLowerCase();
    if (/alchemy|furnace|丹/.test(value)) return 'alchemy';
    if (/library|scripture|book|藏经/.test(value)) return 'library';
    if (/warehouse|storage|藏|库/.test(value)) return 'storage';
    return 'buildings';
  }

  function inventoryGridHtml(inventory, techniqueLibrary = state.techniqueLibrary || { books: [] }) {
    const items = caveStorageItemsB01(inventory, techniqueLibrary);
    const pageCount = Math.max(1, Math.ceil(items.length / CAVE_STORAGE_SLOT_COUNT_B01));
    const requestedPage = Math.max(0, Math.floor(Number(state.caveInventoryPageB01 || 0)));
    const page = Math.min(pageCount - 1, requestedPage);
    if (state.caveInventoryPageB01 !== page) state.caveInventoryPageB01 = page;
    const pageStart = page * CAVE_STORAGE_SLOT_COUNT_B01;
    const visibleItems = items.slice(pageStart, pageStart + CAVE_STORAGE_SLOT_COUNT_B01);
    const emptyCount = Math.max(0, CAVE_STORAGE_SLOT_COUNT_B01 - visibleItems.length);
    return `
      <section id="caveStorageB01" class="cave-storage-b01" aria-label="洞府储物，直接显示当前玩家物品与未研习功法">
        <div class="cave-storage-head-b01">
          <strong>洞府储物</strong>
          <span>${items.length ? `${formatNumber(pageStart + 1)}–${formatNumber(pageStart + visibleItems.length)} / ${formatNumber(items.length)}` : `0 / ${formatNumber(CAVE_STORAGE_SLOT_COUNT_B01)}`} · 物品与未研习功法直接入格</span>
        </div>
        <div class="cave-storage-grid-b01">
          ${visibleItems.map(row => {
            const definition = row.definition || {};
            const rarity = caveItemRarityClassB01(definition.rarity);
            const [cornerMark, cornerClass] = caveItemCornerMarkB01(row);
            const quantityAttr = definition.code === 'spirit_stone' ? ' data-spirit-stone-balance' : '';
            const typeLabel = caveItemTypeLabelV1(row);
            const dataAttr = row.is_technique_book_v1
              ? `data-open-cave-technique-book="${escapeHtml(row.technique_book_v1?.book_id || '')}"`
              : `data-open-cave-item="${escapeHtml(row.id)}"`;
            return `<button class="cave-item-slot-b01 rarity-${escapeHtml(rarity)}${row.is_technique_book_v1 ? ' technique-book-slot-v1' : ''}" type="button" ${dataAttr} aria-label="${escapeHtml(definition.name || '未知物品')}，${escapeHtml(typeLabel)}，数量${formatNumber(row.quantity)}">
              <span class="cave-item-aura-b01" aria-hidden="true"></span>
              ${cornerMark ? `<span class="cave-item-corner-b01 ${escapeHtml(cornerClass)}">${escapeHtml(cornerMark)}</span>` : ''}
              ${caveItemIconHtmlB01(row)}
              <span class="cave-item-name-b01">${escapeHtml(definition.name || '未知物品')}</span>
              <span class="cave-item-type-b01">${escapeHtml(typeLabel)}${row.is_technique_book_v1 ? ' · 未研习' : ''}</span>
              <strong class="cave-item-quantity-b01">×<span${quantityAttr}>${formatNumber(row.quantity)}</span></strong>
            </button>`;
          }).join('')}
          ${Array.from({ length: emptyCount }, () => '<div class="cave-item-slot-b01 empty" aria-hidden="true"><span>道</span></div>').join('')}
        </div>
        ${pageCount > 1 ? `<div class="cave-storage-pager-b01"><button type="button" data-cave-storage-page="${page - 1}" ${page <= 0 ? 'disabled' : ''}>上一层</button><span>第 ${formatNumber(page + 1)} / ${formatNumber(pageCount)} 层</span><button type="button" data-cave-storage-page="${page + 1}" ${page >= pageCount - 1 ? 'disabled' : ''}>下一层</button></div>` : ''}
      </section>
    `;
  }

  function caveBuildingWorkbenchHtmlB01(system, buildings) {
    return `<div class="subsection-title"><strong>洞府扩建</strong><span>点击建筑查看并执行升级</span></div>
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
          return `<article class="cave-building-card" data-cave-building-card="${escapeHtml(row.code)}">
            <div class="manage-card-head"><div><span>${escapeHtml(output)}</span><strong>${escapeHtml(row.name)} <small>Lv.${formatNumber(row.level)}/${formatNumber(row.max_level)}</small></strong></div><span class="badge">${maxed ? '已满级' : '可扩建'}</span></div>
            <p>${escapeHtml(row.description || '')}</p>
            <small class="cave-cost">${maxed ? '建筑已达到当前版本上限' : `下级消耗：${escapeHtml(caveCostText(row.next_costs || {}))}`}</small>
            <button class="${affordable && !maxed ? 'primary-btn' : 'ghost-btn'}" type="button" data-upgrade-cave="${escapeHtml(row.code)}" ${maxed || !affordable ? 'disabled' : ''}>${maxed ? '已满级' : affordable ? '扩建' : '资源不足'}</button>
          </article>`;
        }).join('')}
      </div>`;
  }

  function caveAlchemyWorkbenchHtmlB01(system, recipes, batch, maxBatch, batchReady) {
    return `<div class="subsection-title"><strong>炼丹</strong><span>同一时间只能炼制一炉</span></div>
      ${batch ? `<article class="alchemy-active-card ${batchReady ? 'ready' : ''}">
        <div><span>${batchReady ? '丹成待取' : '炉火运转中'}</span><strong>${escapeHtml(batch.recipe_name || '未知丹方')} × ${formatNumber(batch.batch_count || 1)} 炉</strong><p>${batchReady ? '丹药已经炼成，可立即收入洞府储物。' : `剩余 <b id="alchemyCountdown">${formatDuration(batch.seconds_remaining || 0)}</b>`}</p></div>
        <button id="claimAlchemyBtn" class="${batchReady ? 'primary-btn' : 'ghost-btn'}" type="button" ${batchReady ? '' : 'disabled'}>${batchReady ? '开炉取丹' : '炼制中'}</button>
      </article>` : `<div class="cave-recipe-grid">
        ${recipes.map(row => {
          const unlocked = Boolean(row.furnace_unlocked);
          const available = Boolean(row.output_item_available);
          const baseCosts = row.resource_costs || {};
          return `<article class="alchemy-recipe-card ${unlocked && available ? '' : 'locked'}">
            <div class="manage-card-head"><div><span>丹炉 Lv.${formatNumber(row.required_furnace_level)} 解锁</span><strong>${escapeHtml(row.name)}</strong></div><span class="badge">${formatDuration(row.duration_seconds || 0)}/炉</span></div>
            <p>${escapeHtml(row.description || '')}</p>
            <small>单炉材料：${escapeHtml(caveCostText(baseCosts))} · 产出 ${escapeHtml(row.resolved_output_name || row.output_item_name)} × ${formatNumber(row.output_quantity)}</small>
            <div class="alchemy-actions"><select data-alchemy-count="${escapeHtml(row.code)}" ${unlocked && available ? '' : 'disabled'}>${Array.from({ length: maxBatch }, (_, index) => index + 1).map(count => `<option value="${count}">${count} 炉</option>`).join('')}</select><button class="primary-btn" type="button" data-start-alchemy="${escapeHtml(row.code)}" ${unlocked && available ? '' : 'disabled'}>${!available ? '物品配置缺失' : !unlocked ? '丹炉等级不足' : '开炉炼制'}</button></div>
          </article>`;
        }).join('')}
      </div>`}`;
  }

  // V1.7.9 CACHE59 CAVEUI1：洞府底部功能区默认显示“建筑”页。
  function showCaveWorkbenchB01(panelName = 'buildings', buildingCode = '') {
    const workbench = document.getElementById('caveWorkbenchB01');
    if (!workbench) return;
    workbench.hidden = false;
    workbench.removeAttribute('hidden');
    workbench.setAttribute('aria-hidden', 'false');
    workbench.querySelectorAll('[data-cave-workbench-panel]').forEach(panel => {
      const isActive = panel.dataset.caveWorkbenchPanel === panelName;
      panel.hidden = !isActive;
      if (isActive) panel.removeAttribute('hidden');
      else panel.setAttribute('hidden', '');
    });
    workbench.querySelectorAll('[data-cave-open-panel]').forEach(tab => tab.classList.toggle('active', tab.dataset.caveOpenPanel === panelName));
    workbench.querySelectorAll('[data-cave-building-card]').forEach(card => card.classList.toggle('focused', Boolean(buildingCode) && card.dataset.caveBuildingCard === buildingCode));
  }

  function closeCaveWorkbenchB01() {
    const workbench = document.getElementById('caveWorkbenchB01');
    if (!workbench) return;
    workbench.hidden = true;
    workbench.setAttribute('hidden', '');
    workbench.setAttribute('aria-hidden', 'true');
  }

  function cavePanelHtml(system, inventory, techniqueLibrary = state.techniqueLibrary || { books: [] }) {
    const resources = Array.isArray(system?.resources) ? system.resources : [];
    const buildings = Array.isArray(system?.buildings) ? system.buildings : [];
    const recipes = Array.isArray(system?.recipes) ? system.recipes : [];
    const batch = system?.active_batch || null;
    const maxBatch = Math.max(1, Number(system?.rules?.max_batch_count || 10));
    const batchReady = batch?.status === 'ready' || Number(batch?.seconds_remaining || 0) <= 0;
    const sceneBuildings = buildings.slice(0, 6);
    const sceneSlots = [...sceneBuildings, ...Array.from({ length: Math.max(0, 6 - sceneBuildings.length) }, () => null)];
    // V1.7.4：洞府资源条只显示洞府专属资源；统一灵石仍保留在洞府储物格与全局余额中，不在此处重复展示。
    const resourceRows = resources.filter(row => row.code !== 'spirit_stone').slice(0, 4);
    return `
      <div id="caveSystemRoot" class="cave-system-root cave-system-b01">
        <section class="cave-scene-b01" aria-label="幽静洞窟、灵脉石台与仙府经营主景">
          <div class="cave-rock-arch-b01" aria-hidden="true"></div>
          <div class="cave-stalactites-b01" aria-hidden="true"></div>
          <div class="cave-depth-shrine-v1" aria-hidden="true"><span>洞天幽居</span></div>
          <div class="cave-waterfall-v1" aria-hidden="true"><i></i></div>
          <div class="cave-spirit-veins-b01" aria-hidden="true"><i></i><i></i><i></i><i></i></div>
          <div class="cave-qi-wisps-v1" aria-hidden="true"><i></i><i></i><i></i></div>
          <div class="cave-fireflies-v1" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i><i></i></div>
          <div class="cave-scene-mist-b01" aria-hidden="true"></div>
          <div class="cave-pond-v1" aria-hidden="true"></div>
          <div class="cave-stairs-v1" aria-hidden="true"><i></i><i></i><i></i><i></i></div>
          <div class="cave-bonsai-v1" aria-hidden="true"><i></i><b></b></div>
          <div class="cave-scene-lines-b01" aria-hidden="true"></div>
          <div class="cave-lantern-b01 left" aria-hidden="true"><i></i></div>
          <div class="cave-lantern-b01 right" aria-hidden="true"><i></i></div>
          <div class="cave-building-orbit-b01">
            ${sceneSlots.map((row, index) => row ? `<button class="cave-scene-building-b01 pos-${index + 1}" type="button" data-cave-open-panel="${escapeHtml(caveBuildingPanelKindB01(row))}" data-cave-building-code="${escapeHtml(row.code || '')}">
              <span class="cave-building-glyph-b01">${escapeHtml(caveBuildingGlyphB01(row, index))}</span>
              <span class="cave-building-copy-b01"><strong>${escapeHtml(row.name || '洞府建筑')}</strong><small>Lv.${formatNumber(row.level || 1)} · ${Number(row.level || 1) >= Number(row.max_level || 10) ? '已圆满' : '可扩建'}</small></span>
            </button>` : `<div class="cave-scene-building-b01 pos-${index + 1} locked" aria-hidden="true"><span class="cave-building-glyph-b01">封</span><span class="cave-building-copy-b01"><strong>待开辟</strong><small>洞天未启</small></span></div>`).join('')}
          </div>
          <div class="cave-meditation-b01" aria-hidden="true">
            <div class="cave-stone-platform-b01"></div>
            <div class="cave-meditation-ring-b01"></div>
            <div class="cave-meditation-figure-b01"><i></i><b></b><span></span></div>
          </div>
          <div class="cave-scene-caption-b01"><strong>洞天幽居 · 灵脉自运</strong><span>仙府隐修 · 离线最多结算 ${formatNumber(system?.rules?.offline_cap_hours || 72)} 小时</span></div>
        </section>

        <section class="cave-resource-strip-b01" aria-label="洞府资源">
          ${resourceRows.map(row => {
            const capacity = Number(row.capacity || 0);
            const percent = capacity > 0 ? Math.min(100, Number(row.quantity || 0) / capacity * 100) : 100;
            return `<article class="cave-resource-card-b01"><span>${escapeHtml(row.name || caveResourceName(row.code))}</span><strong>${formatNumber(row.quantity || 0)}${capacity > 0 ? ` <small>/ ${formatNumber(capacity)}</small>` : ''}</strong><div class="cave-resource-track-b01"><i style="width:${percent}%"></i></div></article>`;
          }).join('')}
        </section>

        ${inventoryGridHtml(inventory, techniqueLibrary)}

        <div class="cave-action-bar-b01">
          <button class="ghost-btn" type="button" data-cave-open-panel="buildings">洞府扩建</button>
          <button id="collectCaveYieldB01" class="primary-btn" type="button">一键收取</button>
          <button id="tidyCaveStorageB01" class="ghost-btn" type="button">${state.caveInventorySortMode === 'tidy' ? '恢复顺序' : '整理储物'}</button>
        </div>

        <section id="caveWorkbenchB01" class="cave-workbench-b01" aria-hidden="false">
          <button class="cave-workbench-close-b01" type="button" data-close-cave-workbench aria-label="关闭洞府功能面板">×</button>
          <nav class="cave-workbench-tabs-b01" aria-label="洞府功能切换">
            <button class="active" type="button" data-cave-open-panel="buildings">建筑</button>
            <button type="button" data-cave-open-panel="alchemy">炼丹</button>
            <button type="button" data-cave-open-panel="library">藏经</button>
          </nav>
          <div data-cave-workbench-panel="buildings">${caveBuildingWorkbenchHtmlB01(system, buildings)}</div>
          <div data-cave-workbench-panel="alchemy" hidden>${caveAlchemyWorkbenchHtmlB01(system, recipes, batch, maxBatch, batchReady)}</div>
          <div data-cave-workbench-panel="library" hidden>${techniqueLibraryHtml(techniqueLibrary)}</div>
        </section>
      </div>
    `;
  }

  function openCaveTechniqueBookDetailV1(bookId) {
    const row = (state.techniqueLibrary?.books || []).find(item => String(item.book_id) === String(bookId));
    if (!row || row.is_learned) { showToast('该功法道卷已不在未研习藏书中。', 'error'); return; }
    const virtual = caveTechniqueBookStorageItemsV1({ books: [row] })[0];
    modalRoot.innerHTML = `<div id="caveTechniqueBookBackdropV1" class="modal-backdrop cave-item-detail-backdrop-b01">
      <section class="modal cave-item-detail-modal-b01" role="dialog" aria-modal="true" aria-labelledby="caveTechniqueBookTitleV1">
        <button id="closeCaveTechniqueBookV1" class="modal-close-button" type="button" aria-label="关闭">×</button>
        <div class="cave-item-detail-head-b01">
          <div class="cave-item-detail-icon-b01 rarity-${escapeHtml(caveItemRarityClassB01(virtual?.definition?.rarity))}">${caveItemIconHtmlB01(virtual, true)}</div>
          <div><span>${escapeHtml(row.grade_name || row.grade_code || '功法')} · 未研习</span><h3 id="caveTechniqueBookTitleV1">《${escapeHtml(row.name || '未知道卷')}》</h3><strong>藏有 × ${formatNumber(row.quantity || 0)}</strong></div>
        </div>
        <div class="cave-item-detail-tags-b01"><span>功法</span><span>${escapeHtml(row.book_kind === 'exclusive' ? '专属道卷' : '普通道卷')}</span><span>洞府藏经</span></div>
        <p class="cave-item-detail-description-b01">${escapeHtml(row.description || '道纹沉静，等待有缘人展开研习。')}</p>
        <div class="cave-item-detail-effect-b01"><strong>研习效果</strong><p>${escapeHtml(techniqueBookEffectText(row))}</p></div>
        <small class="cave-item-detail-source-b01">当前状态：${escapeHtml(row.can_learn ? '可以研习' : row.locked_reason || '暂不可研习')}</small>
        <div class="cave-item-detail-actions-b01"><button id="openCaveLibraryV1" class="primary-btn" type="button">前往藏经架</button><button id="closeCaveTechniqueBookActionV1" class="ghost-btn" type="button">关闭</button></div>
      </section>
    </div>`;
    const close = () => { modalRoot.innerHTML = ''; };
    document.getElementById('closeCaveTechniqueBookV1')?.addEventListener('click', close);
    document.getElementById('closeCaveTechniqueBookActionV1')?.addEventListener('click', close);
    document.getElementById('caveTechniqueBookBackdropV1')?.addEventListener('click', event => { if (event.target?.id === 'caveTechniqueBookBackdropV1') close(); });
    document.getElementById('openCaveLibraryV1')?.addEventListener('click', () => {
      close();
      document.querySelector('#caveSystemRoot [data-cave-open-panel="library"]')?.click();
    });
  }

  function openCaveInventoryDetailB01(inventoryId) {
    const row = findInventoryRow(inventoryId);
    if (!row) { showToast('该物品已不在洞府储物中。', 'error'); return; }
    const definition = row.definition || {};
    const effects = definition.effects || {};
    const washPill = definition.code === 'spirit_washing_pill_v0154' || effects.use_type === 'spirit_root_reroll';
    const usable = ['instant_cultivation', 'timed_rate', 'comprehension'].includes(effects.use_type);
    const actionLabel = washPill ? '重塑灵根' : usable ? '选择使用数量' : '';
    const boundText = row.is_bound ? '已绑定 · 不可转移' : '未绑定';
    const acquiredText = Number(row.acquired_year || 0) > 0 ? ` · 仙历 ${formatNumber(row.acquired_year)} 年所得` : '';
    modalRoot.innerHTML = `<div id="caveItemDetailBackdropB01" class="modal-backdrop cave-item-detail-backdrop-b01">
      <section class="modal cave-item-detail-modal-b01" role="dialog" aria-modal="true" aria-labelledby="caveItemDetailTitleB01">
        <button id="closeCaveItemDetailB01" class="modal-close-button" type="button" aria-label="关闭">×</button>
        <div class="cave-item-detail-head-b01">
          <div class="cave-item-detail-icon-b01 rarity-${escapeHtml(caveItemRarityClassB01(definition.rarity))}">${caveItemIconHtmlB01(row, true)}</div>
          <div><span>${escapeHtml(rarityName(definition.rarity))} · ${escapeHtml(definition.category || '物品')}</span><h3 id="caveItemDetailTitleB01">${escapeHtml(definition.name || '未知物品')}</h3><strong>当前持有 × ${formatNumber(row.quantity || 0)}</strong></div>
        </div>
        <div class="cave-item-detail-tags-b01"><span>${escapeHtml(boundText)}</span><span>可堆叠上限 ${formatNumber(definition.stack_limit || 1)}</span>${effects.use_type ? `<span>${escapeHtml(effects.use_type)}</span>` : ''}</div>
        <p class="cave-item-detail-description-b01">${escapeHtml(definition.description || '此物灵韵内敛，尚无更多记载。')}</p>
        <div class="cave-item-detail-effect-b01"><strong>物品效果</strong><p>${escapeHtml(itemEffectText(row))}</p></div>
        <small class="cave-item-detail-source-b01">物品代码：${escapeHtml(definition.code || 'unknown')}${escapeHtml(acquiredText)}</small>
        <div class="cave-item-detail-actions-b01">${actionLabel ? `<button id="caveItemPrimaryActionB01" class="primary-btn" type="button">${escapeHtml(actionLabel)}</button>` : ''}<button id="caveItemCloseActionB01" class="ghost-btn" type="button">关闭</button></div>
      </section>
    </div>`;
    const close = () => { modalRoot.innerHTML = ''; };
    document.getElementById('closeCaveItemDetailB01')?.addEventListener('click', close);
    document.getElementById('caveItemCloseActionB01')?.addEventListener('click', close);
    document.getElementById('caveItemDetailBackdropB01')?.addEventListener('click', event => { if (event.target?.id === 'caveItemDetailBackdropB01') close(); });
    document.getElementById('caveItemPrimaryActionB01')?.addEventListener('click', () => {
      close();
      if (washPill) openSpiritWashingPillModal(row.id);
      else if (usable) openInventoryQuantityModal({ inventoryId: row.id, itemName: definition.name || '储物', quantity: Math.max(1, Number(row.quantity || 1)), effectText: itemEffectText(row) });
    });
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

  async function refreshInventoryV0147() {
    if (!state.character) return [];
    const links = await restFetch('character_inventory', { query: {
      select: 'id,character_id,item_definition_id,quantity,is_bound,item_instance,acquired_year',
      character_id: `eq.${state.character.id}`, quantity: 'gt.0', order: 'created_at.asc'
    }});
    const itemIds = (Array.isArray(links) ? links : []).map(row => row.item_definition_id);
    const definitions = itemIds.length ? await restFetch('item_definitions', { query: {
      select: 'id,code,name,category,rarity,stack_limit,effects,description',
      id: `in.(${itemIds.join(',')})`
    }}) : [];
    const definitionMap = new Map((Array.isArray(definitions) ? definitions : []).map(row => [row.id, row]));
    const inventory = mergeCanonicalSpiritStoneInventory((Array.isArray(links) ? links : []).map(link => ({
      ...link, definition: definitionMap.get(link.item_definition_id) || null
    })).filter(row => row.definition && Number(row.quantity || 0) > 0));
    if (state.details) state.details.inventory = inventory;
    return inventory;
  }

  function openInventoryQuantityModal({ inventoryId, itemName, quantity, effectText }) {
    const maxQuantity = Math.max(1, Math.floor(Number(quantity || 1)));
    modalRoot.innerHTML = `
      <div id="inventoryQuantityBackdrop" class="modal-backdrop inventory-quantity-backdrop">
        <section class="modal inventory-quantity-modal" role="dialog" aria-modal="true" aria-labelledby="inventoryQuantityTitle">
          <button id="closeInventoryQuantityBtn" class="modal-close-button" type="button" aria-label="关闭">×</button>
          <span class="eyebrow">洞府储物</span>
          <h3 id="inventoryQuantityTitle">使用 · ${escapeHtml(itemName)}</h3>
          <p>${escapeHtml(effectText || '选择本次使用数量。')}</p>
          <div class="inventory-quantity-stock">当前拥有 <strong>${formatNumber(maxQuantity)}</strong></div>
          <div class="inventory-quantity-stepper">
            <button type="button" data-inventory-quantity-delta="-1">−</button>
            <input id="inventoryQuantityInput" type="number" min="1" max="${maxQuantity}" step="1" inputmode="numeric" value="1">
            <button type="button" data-inventory-quantity-delta="1">＋</button>
          </div>
          <div class="inventory-quantity-quick">
            <button type="button" data-inventory-quantity-value="1">使用1个</button>
            <button type="button" data-inventory-quantity-value="10" ${maxQuantity < 10 ? 'disabled' : ''}>使用10个</button>
            <button type="button" data-inventory-quantity-value="${maxQuantity}">全部使用</button>
          </div>
          <div id="inventoryQuantityPreview" class="inventory-quantity-preview">本次使用：1个 · 使用后剩余：${formatNumber(maxQuantity - 1)}</div>
          <button id="confirmInventoryQuantityBtn" class="primary-btn" type="button">确认使用</button>
        </section>
      </div>`;
    const input = document.getElementById('inventoryQuantityInput');
    const preview = document.getElementById('inventoryQuantityPreview');
    const confirm = document.getElementById('confirmInventoryQuantityBtn');
    const normalize = value => Math.max(1, Math.min(maxQuantity, Math.floor(Number(value || 1))));
    const update = value => {
      const normalized = normalize(value);
      input.value = String(normalized);
      preview.textContent = `本次使用：${formatNumber(normalized)}个 · 使用后剩余：${formatNumber(maxQuantity - normalized)}`;
      return normalized;
    };
    const close = () => { modalRoot.innerHTML = ''; };
    document.getElementById('closeInventoryQuantityBtn')?.addEventListener('click', close);
    document.getElementById('inventoryQuantityBackdrop')?.addEventListener('click', event => { if (event.target?.id === 'inventoryQuantityBackdrop') close(); });
    input?.addEventListener('input', () => update(input.value));
    document.querySelectorAll('[data-inventory-quantity-delta]').forEach(button => button.addEventListener('click', () => update(Number(input.value || 1) + Number(button.dataset.inventoryQuantityDelta || 0))));
    document.querySelectorAll('[data-inventory-quantity-value]').forEach(button => button.addEventListener('click', () => update(button.dataset.inventoryQuantityValue)));
    confirm?.addEventListener('click', () => {
      const useQuantity = update(input.value);
      const row = findInventoryRow(inventoryId);
      if (!row || Number(row.quantity || 0) < useQuantity) {
        close();
        showToast('该物品数量不足。', 'error');
        return;
      }
      setLocalInventoryQuantity(inventoryId, Number(row.quantity || 0) - useQuantity);
      close();
      renderCaveSystemFromState();
      (async () => {
        try {
          const result = await rpcUseInventoryItemQuantityV0154(inventoryId, useQuantity, createUuid());
          await Promise.all([refreshInventoryV0147(), refreshCaveSystem(false), refreshCultivationEffectsV0154(), syncCultivation(true)]);
          showToast(result?.reward_text || `${result?.item_name || itemName}已生效。`);
        } catch (error) {
          await Promise.all([refreshInventoryV0147(), refreshCaveSystem(false), syncCultivation(true)]).catch(() => {});
          renderCaveSystemFromState();
          showToast(`物品状态已按云端校正：${translateError(error)}`, 'error');
        }
      })();
    });
  }

  function openSpiritWashingPillModal(inventoryId) {
    const currentRoot = state.details?.spiritRoot || {};
    modalRoot.innerHTML = `
      <div id="spiritWashingBackdrop" class="modal-backdrop">
        <section class="modal spirit-washing-modal" role="dialog" aria-modal="true" aria-labelledby="spiritWashingTitle">
          <button id="closeSpiritWashingBtn" class="modal-close-button" type="button" aria-label="关闭">×</button>
          <div class="modal-seal">灵</div>
          <h2 id="spiritWashingTitle">服用洗灵丹</h2>
          <p>当前灵根：<strong>${escapeHtml(currentRoot.name || '未知灵根')}</strong></p>
          <div class="result-detail">将按创建角色时完全相同的概率重新抽取灵根。结果可能更好、相同或更差，且会直接替换当前灵根。</div>
          <button id="confirmSpiritWashingBtn" class="primary-btn full" type="button">确认重塑灵根</button>
        </section>
      </div>`;
    const close = () => { modalRoot.innerHTML = ''; };
    document.getElementById('closeSpiritWashingBtn')?.addEventListener('click', close);
    document.getElementById('spiritWashingBackdrop')?.addEventListener('click', event => { if (event.target?.id === 'spiritWashingBackdrop') close(); });
    document.getElementById('confirmSpiritWashingBtn')?.addEventListener('click', () => {
      const row = findInventoryRow(inventoryId);
      if (!row || Number(row.quantity || 0) < 1) { close(); showToast('洗灵丹数量不足。', 'error'); return; }
      setLocalInventoryQuantity(inventoryId, Number(row.quantity || 0) - 1);
      close();
      renderCaveSystemFromState();
      (async () => {
        try {
          const result = await rpcUseSpiritWashingPillV0154(createUuid());
          await enterGame({ silent: true });
          showResultModal({
            seal: '灵', title: '灵根重塑',
            message: `${result?.old_root_name || currentRoot.name || '原灵根'} → ${result?.mutation_display || result?.new_root_name || '新灵根'}`,
            detail: `${result?.conflict_replaced ? `天生剑心与变异灵根发生冲突，系统已随机改为“${result?.new_root_name || '合法灵根'}”；` : ''}修炼系数 ×${formatNumber(result?.old_cultivation_multiplier || currentRoot.cultivation_multiplier || 1, 2)} → ×${formatNumber(result?.new_cultivation_multiplier || 1, 2)}${Number.isFinite(Number(result?.current_rate_per_second)) ? `；当前修炼速度 ${formatRate(result.current_rate_per_second)}` : ''}`,
            success: true
          });
        } catch (error) {
          await Promise.all([refreshInventoryV0147(), refreshCaveSystem(false)]).catch(() => {});
          renderCaveSystemFromState();
          showToast(`洗灵结果未成立：${translateError(error)}`, 'error');
        }
      })();
    });
  }

  function bindInventoryTechniqueActions() {
    document.querySelectorAll('[data-open-cave-technique-book]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => openCaveTechniqueBookDetailV1(button.dataset.openCaveTechniqueBook));
    });

    document.querySelectorAll('[data-open-cave-item]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => openCaveInventoryDetailB01(button.dataset.openCaveItem));
    });

    document.querySelectorAll('[data-cave-storage-page]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        state.caveInventoryPageB01 = Math.max(0, Math.floor(Number(button.dataset.caveStoragePage || 0)));
        renderCaveSystemFromState();
        document.getElementById('caveStorageB01')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
      });
    });

    document.querySelectorAll('[data-cave-open-panel]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        const panelName = button.dataset.caveOpenPanel || 'buildings';
        if (panelName === 'storage') {
          document.getElementById('caveStorageB01')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
          return;
        }
        const workbench = document.getElementById('caveWorkbenchB01');
        if (!workbench) return;
        showCaveWorkbenchB01(panelName, button.dataset.caveBuildingCode || '');
        workbench.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
      });
    });

    document.querySelectorAll('[data-close-cave-workbench]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        closeCaveWorkbenchB01();
      });
    });

    const collectButtonB01 = document.getElementById('collectCaveYieldB01');
    if (collectButtonB01 && collectButtonB01.dataset.bound !== '1') {
      collectButtonB01.dataset.bound = '1';
      collectButtonB01.addEventListener('click', async () => {
        setBusy(collectButtonB01, true, '收取中……');
        try {
          await refreshInventoryV0147();
          await refreshCaveSystem(false);
          renderCaveSystemFromState();
          showToast('洞府产出与当前物品已同步。');
        } catch (error) {
          showToast(translateError(error), 'error');
          setBusy(collectButtonB01, false);
        }
      });
    }

    const tidyButtonB01 = document.getElementById('tidyCaveStorageB01');
    if (tidyButtonB01 && tidyButtonB01.dataset.bound !== '1') {
      tidyButtonB01.dataset.bound = '1';
      tidyButtonB01.addEventListener('click', () => {
        state.caveInventorySortMode = state.caveInventorySortMode === 'tidy' ? 'default' : 'tidy';
        renderCaveSystemFromState();
        showToast(state.caveInventorySortMode === 'tidy' ? '已按品质与类别整理。' : '已恢复原有入库顺序。');
      });
    }
    document.querySelectorAll('[data-redeem-technique-book]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        const name = button.dataset.techniqueName || '功法道卷';
        const held = Math.max(1, Number(button.dataset.techniqueQuantity || 1));
        const unitValue = Math.max(0, Number(String(button.dataset.techniqueRedeemPrice || '0').replace(/,/g, '')));
        const raw = window.prompt(`兑换《${name}》道卷数量（当前 ${held} 本，单本 ${formatNumber(unitValue)} 灵石）`, '1');
        if (raw === null) return;
        const quantity = Math.floor(Number(raw));
        if (!Number.isFinite(quantity) || quantity < 1 || quantity > held) { showToast('兑换数量不合法。'); return; }
        const total = unitValue * quantity;
        if (!window.confirm(`即将兑换《${name}》道卷 ×${quantity}，获得 ${formatNumber(total)} 灵石。若尚未研习且兑换后归零，将无法研习直到再次获得。此操作不可撤销。`)) return;
        button.disabled = true;
        try {
          const result = await rpcRedeemTechniqueBookV0152(button.dataset.redeemTechniqueBook, quantity);
          showToast(`兑换成功，获得 ${formatNumber(result?.spirit_stones_gained || total)} 灵石。`);
          await Promise.all([
            refreshTechniqueLibrary(true),
            refreshMarketSystem(true),
            refreshTechniqueSystem(true),
            refreshSpiritStoneBalanceV0141(true)
          ]);
        } catch (error) { showToast(translateError(error)); }
        finally { button.disabled = false; }
      });
    });
    document.querySelectorAll('[data-use-technique-book]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        button.disabled = true;
        try {
          state.activeMobileTab = 'cave';
          const result = await rpcUseTechniqueBookV1(button.dataset.useTechniqueBook);
          await Promise.all([
            refreshTechniqueSystem(true),
            refreshExclusiveTechniqueSystem(true),
            refreshCaveSystem(true),
            refreshSpiritStoneBalanceV0141(true)
          ]);
          const learned = result?.action === 'learn';
          showToast(result?.message || (learned ? `《${result?.technique_name || '功法'}》已收入识海。` : `参悟完成，传承点 +${formatNumber(result?.mastery_points_gained || 0)}。`));
          await syncCultivation(true);
        } catch (error) {
          showToast(translateError(error), 'error');
          button.disabled = false;
        }
      });
    });

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
            message: `${result?.item_name || '丹药'} × ${formatNumber(result?.quantity_added || 0)} 已收入洞府储物。`,
            detail: `当前共有 ${formatNumber(result?.quantity_total || 0)}。`,
            success: true
          });
        } catch (error) {
          showToast(translateError(error), 'error');
          setBusy(claimAlchemyButton, false);
        }
      });
    }

    document.querySelectorAll('[data-use-spirit-washing-pill]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => openSpiritWashingPillModal(button.dataset.useSpiritWashingPill));
    });

    document.querySelectorAll('[data-use-item]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => openInventoryQuantityModal({
        inventoryId: button.dataset.useItem,
        itemName: button.dataset.useItemName || '储物',
        quantity: Math.max(1, Number(button.dataset.useItemQuantity || 1)),
        effectText: button.dataset.useItemEffect || ''
      }));
    });

    document.querySelectorAll('[data-apply-technique-slot]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        const techniqueId = button.dataset.applyTechniqueSlot;
        const selector = Array.from(document.querySelectorAll('[data-technique-target-for]'))
          .find(node => node.dataset.techniqueTargetFor === techniqueId);
        const targetSlot = selector?.value || 'none';
        setBusy(button, true, '调整中……');
        try {
          state.activeMobileTab = 'techniques';
          const result = await rpcSetTechniqueSlotV2(techniqueId, targetSlot);
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
      button.addEventListener('click', () => {
        state.activeMobileTab = 'techniques';
        optimisticTechniqueUpgradeV0154('ordinary', button.dataset.upgradeTechniqueV2);
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
      button.addEventListener('click', () => {
        state.activeMobileTab = 'techniques';
        optimisticTechniqueUpgradeV0154('exclusive', button.dataset.upgradeExclusiveTechnique);
      });
    });
  }


  function destinyRankMedal(rank) {
    if (rank === 1) return '天';
    if (rank === 2) return '地';
    if (rank === 3) return '人';
    return String(rank);
  }

  function rankingBoardMeta(board = 'cultivation') {
    return {
      cultivation: {
        label: '修为榜',
        empty: '九霄界尚无在世修士。',
        unavailable: '修为榜尚未开启',
        loading: '正在推演修为榜……',
        fallbackRule: '境界优先，其次小境界与已结算修为'
      },
      wealth: {
        label: '财富榜',
        empty: '九霄界尚无可入榜修士。',
        unavailable: '财富榜尚未开启',
        loading: '正在清点九霄财富……',
        fallbackRule: '统一灵石余额由高到低，同额时境界优先'
      },
      battle: {
        label: '战力榜',
        empty: '九霄界尚无已凝聚战斗四属性的修士。',
        unavailable: '战力榜尚未开启',
        loading: '正在推演众修战力……',
        fallbackRule: '道攻×10＋道御×8＋生机×1.5＋身法×5'
      }
    }[board] || null;
  }

  function rankingBoardTabsHtml(activeBoard = 'cultivation') {
    return `
      <div class="ranking-board-tabs" role="tablist" aria-label="九霄榜单切换">
        ${['cultivation', 'wealth', 'battle'].map(board => {
          const meta = rankingBoardMeta(board);
          const active = board === activeBoard;
          return `<button class="ranking-board-tab${active ? ' active' : ''}" type="button" role="tab" aria-selected="${active ? 'true' : 'false'}" data-ranking-board="${board}"><strong>${meta.label}</strong></button>`;
        }).join('')}
      </div>
    `;
  }

  function rankingEntryMetric(board, row) {
    if (board === 'wealth') return `${formatNumber(row.wealth || 0)} 灵石`;
    if (board === 'battle') return `${formatNumber(row.power || 0)} 战力`;
    return `${formatNumber(row.cultivation || 0)} 修为`;
  }

  function rankingResultForBoard(board, cultivationRanking, wealthRanking, battleRanking) {
    if (board === 'wealth') return wealthRanking;
    if (board === 'battle') return battleRanking;
    return cultivationRanking;
  }

  function rankingCenterPanelHtml(board = 'cultivation', cultivationRanking = null, wealthRanking = null, battleRanking = null) {
    const safeBoard = ['cultivation', 'wealth', 'battle'].includes(board) ? board : 'cultivation';
    const meta = rankingBoardMeta(safeBoard);
    const result = rankingResultForBoard(safeBoard, cultivationRanking, wealthRanking, battleRanking)
      || { status: 'loading', entries: [], total_count: 0 };
    const entries = Array.isArray(result.entries) ? result.entries : [];
    const total = Math.max(entries.length, Number(result.total_count || 0));
    if (result.status === 'unavailable') {
      return `
        <div id="destinyRankingRoot" class="destiny-ranking-root" data-ranking-active="${safeBoard}">
          ${rankingBoardTabsHtml(safeBoard)}
          <div class="ranking-notice">
            <strong>${meta.unavailable}</strong>
            <p>${escapeHtml(result.error || '对应数据库候选模块尚未接入。')}</p>
          </div>
        </div>
      `;
    }
    if (result.status === 'loading' || result.status === 'idle') {
      return `<div id="destinyRankingRoot" class="destiny-ranking-root" data-ranking-active="${safeBoard}">${rankingBoardTabsHtml(safeBoard)}<div class="empty-state">${meta.loading}</div></div>`;
    }
    return `
      <div id="destinyRankingRoot" class="destiny-ranking-root" data-ranking-active="${safeBoard}">
        ${rankingBoardTabsHtml(safeBoard)}
        ${safeBoard === 'battle' ? `
          ${result.self ? `
            <div class="battle-self-summary-bcombat01">
              <div><span>本尊姓名</span><strong>${escapeHtml(result.self.name || state.character?.name || '本尊')}</strong></div>
              <div><span>当前等级</span><strong>${escapeHtml(result.self.realm || '未知境界')}</strong></div>
              <div><span>本尊战力</span><strong>${formatNumber(result.self.power || result.self_power || 0)}</strong></div>
              <div><span>本命五行</span><strong>${escapeHtml(result.self.element_name || '未定')}${result.self.mutation_active ? ` · 变异${mutationAttributeHtmlV12(result.self)}` : ''}</strong></div>
            </div>
          ` : ''}
          <div class="battle-ranking-rule-bcombat01">
            <strong>战力只作综合评分，不直接决定胜负</strong>
            <span>高低战力均可互相挑战；低战力击败高战力转移败者当前阶段进度1%，其余胜利转移0.5%。</span>
          </div>
        ` : ''}
        <div class="destiny-ranking-list">
          ${entries.map(row => {
            const rank = Number(row.rank || 0);
            return `
              <article class="destiny-ranking-row rank-${Math.min(4, rank)} ${row.is_self ? 'self' : ''} ${safeBoard === 'battle' ? 'battle-ranking-row-bcombat01' : ''}">
                <div class="destiny-rank-medal">${escapeHtml(destinyRankMedal(rank))}</div>
                <div class="destiny-rank-main">
                  <div><strong>${escapeHtml(row.name || '无名修士')}</strong>${row.is_self ? '<span class="self-mark">本尊</span>' : ''}${safeBoard === 'battle' ? `<span class="battle-element-mark-bcombat01 element-${escapeHtml(row.element || 'none')}">${escapeHtml(row.element_name || '未定')}行</span>${mutationBadgeHtmlV12(row)}` : ''}</div>
                  <p>${safeBoard === 'battle'
                    ? `等级 ${escapeHtml(row.realm || '未知境界')}`
                    : `${escapeHtml(row.realm || '未知境界')} · 命格「${escapeHtml(row.fate || '未定命格')}」`}</p>
                </div>
                <div class="destiny-rank-side">
                  ${safeBoard === 'battle' ? '' : `<span>第 ${formatNumber(row.generation || 1)} 世</span>`}
                  <strong>${escapeHtml(rankingEntryMetric(safeBoard, row))}</strong>
                  ${safeBoard === 'battle' && !row.is_self ? `
                    <button class="${row.can_challenge ? 'primary-btn' : 'ghost-btn'} battle-rank-challenge-bcombat01" type="button"
                      data-battle-challenge-target="${escapeHtml(row.character_id || '')}" ${row.can_challenge ? '' : 'disabled'}>
                      ${row.can_challenge ? '挑战' : '本尊'}
                    </button>
                  ` : ''}
                </div>
              </article>
            `;
          }).join('') || `<div class="empty-state">${meta.empty}</div>`}
        </div>
        <div class="destiny-ranking-footer">
          <span>已显示 ${formatNumber(entries.length)} / ${formatNumber(total)} 名 · ${escapeHtml(result.ranking_rule || meta.fallbackRule)}</span>
          ${result.has_more ? `<button class="primary-btn" type="button" data-ranking-load-more data-ranking-load-board="${safeBoard}">继续观榜</button>` : '<small>榜单已全部展开</small>'}
        </div>
      </div>
    `;
  }

  function destinyRankingPanelHtml(ranking) {
    return rankingCenterPanelHtml(
      state.rankingBoard || 'cultivation',
      ranking || state.destinyRanking,
      state.wealthRanking,
      state.battleRanking
    );
  }

  function updateDestinyRankingPanel() {
    const root = document.getElementById('destinyRankingRoot');
    if (!root) return;
    root.outerHTML = rankingCenterPanelHtml(state.rankingBoard, state.destinyRanking, state.wealthRanking, state.battleRanking);
    bindDestinyRankingActions();
  }

  async function refreshRankingBoard(board = state.rankingBoard, append = false, silent = true) {
    const safeBoard = ['cultivation', 'wealth', 'battle'].includes(board) ? board : null;
    if (!safeBoard || !state.character) return;
    const configMap = {
      cultivation: ['destinyRankingSyncing', 'destinyRanking', rpcGetDestinyRankingV1],
      wealth: ['wealthRankingSyncing', 'wealthRanking', rpcGetWealthRankingV1],
      battle: ['battleRankingSyncing', 'battleRanking', rpcGetBattlePowerRankingBCombat01]
    };
    const [syncingKey, dataKey, fetcher] = configMap[safeBoard];
    if (state[syncingKey]) return;
    const currentEntries = append && Array.isArray(state[dataKey]?.entries) ? state[dataKey].entries : [];
    state[syncingKey] = true;
    if (!append) {
      state[dataKey] = { status: 'loading', entries: [], total_count: 0 };
      if (state.rankingBoard === safeBoard) updateDestinyRankingPanel();
    }
    try {
      const result = await fetcher(50, append ? currentEntries.length : 0);
      if (append) {
        const nextEntries = Array.isArray(result?.entries) ? result.entries : [];
        state[dataKey] = { ...result, entries: [...currentEntries, ...nextEntries], offset: 0 };
      } else {
        state[dataKey] = result || { status: 'ok', entries: [], total_count: 0 };
      }
      if (safeBoard === 'cultivation') state.destinyRankingFetchedAt = Date.now();
      if (state.rankingBoard === safeBoard) updateDestinyRankingPanel();
      if (!silent) showToast(append ? `${rankingBoardMeta(safeBoard).label}已继续展开。` : `${rankingBoardMeta(safeBoard).label}已更新。`);
    } catch (error) {
      state[dataKey] = { status: 'unavailable', entries: [], total_count: 0, error: translateError(error) };
      if (state.rankingBoard === safeBoard) updateDestinyRankingPanel();
      if (!silent) showToast(translateError(error), 'error');
    } finally {
      state[syncingKey] = false;
    }
  }

  async function refreshDestinyRanking(append = false, silent = true) {
    return refreshRankingBoard('cultivation', append, silent);
  }

  function setRankingBoard(board) {
    const safeBoard = ['cultivation', 'wealth', 'battle'].includes(board) ? board : 'cultivation';
    if (state.rankingBoard === safeBoard) return;
    state.rankingBoard = safeBoard;
    updateDestinyRankingPanel();
    refreshRankingBoard(safeBoard, false, true);
  }

  function battleElementOvercomes(attacker, defender) {
    return [['metal','wood'],['wood','earth'],['earth','water'],['water','fire'],['fire','metal']]
      .some(([left, right]) => left === attacker && right === defender);
  }

  function battleElementRelationHtml(left, right) {
    if (!left || !right || left.element === right.element) return '<strong>五行相安</strong><span>双方不存在直接克制，伤害倍率为1.00。</span>';
    if (battleElementOvercomes(left.element, right.element)) {
      return `<strong>${escapeHtml(left.element_name)}克${escapeHtml(right.element_name)}</strong><span>${escapeHtml(left.name)}占据五行之利。</span>`;
    }
    if (battleElementOvercomes(right.element, left.element)) {
      return `<strong>${escapeHtml(right.element_name)}克${escapeHtml(left.element_name)}</strong><span>${escapeHtml(right.name)}占据五行之利。</span>`;
    }
    return '<strong>五行并行</strong><span>双方不存在直接克制，伤害倍率为1.00。</span>';
  }

  function battleTechniqueLabelBCombat01(name, fallback) {
    const raw = String(name || '').trim();
    if (!raw || raw === fallback) return fallback;
    return `《${escapeHtml(raw)}》`;
  }

  function battleCombatantCardHtml(row, label) {
    return `
      <article class="battle-combatant-card-bcombat01 battle-combatant-card-compact-fix2">
        <span>${escapeHtml(label)}</span>
        <strong>${escapeHtml(row?.name || '无名修士')}</strong>
        <div class="battle-combatant-public-fix2">
          <i><b>等级</b>${escapeHtml(row?.realm || '未知境界')}</i>
          <i><b>战力</b>${formatNumber(row?.power || 0)}</i>
          <i><b>五行</b>${escapeHtml(row?.element_name || '未定')}行${row?.mutation_active ? ` · 变异${mutationAttributeHtmlV12(row)}` : ''}</i>
        </div>
      </article>
    `;
  }

  function battleDuelCombatantHtmlFix3(row, sideLabel, sideClass) {
    return `
      <article class="battle-duel-combatant-fix3 ${escapeHtml(sideClass || '')}">
        <span class="battle-duel-side-label-fix3">${escapeHtml(sideLabel)}</span>
        <strong>${escapeHtml(row?.name || '无名修士')}</strong>
        <div class="battle-duel-stat-fix3"><b>战力</b><em>${formatNumber(row?.power || 0)}</em></div>
        <div class="battle-duel-stat-fix3"><b>五行</b><em>${escapeHtml(row?.element_name || '未定')}行${row?.mutation_active ? ` · 变异${mutationAttributeHtmlV12(row)}` : ''}</em></div>
      </article>
    `;
  }

  function closeBattleChallengeModalBCombat01() {
    if (state.battlePlaybackTimer) clearTimeout(state.battlePlaybackTimer);
    state.battlePlaybackTimer = null;
    modalRoot.innerHTML = '';
  }

  function showBattleResolvingModalBCombat01() {
    modalRoot.innerHTML = `
      <div class="modal-backdrop battle-report-backdrop-fix2">
        <section class="modal battle-report-modal-fix2" role="dialog" aria-modal="true" aria-labelledby="battleResolvingTitleFix2">
          <button class="modal-close-button" type="button" data-close-battle-challenge aria-label="关闭">×</button>
          <div class="modal-seal">战</div>
          <h3 id="battleResolvingTitleFix2">战局推演中</h3>
          <div class="empty-state">双方已入战场，正在结算回合与战果……</div>
        </section>
      </div>
    `;
    modalRoot.querySelector('[data-close-battle-challenge]')?.addEventListener('click', closeBattleChallengeModalBCombat01);
  }

  function showBattleChallengeErrorModalBCombat01(error) {
    modalRoot.innerHTML = `
      <div class="modal-backdrop battle-report-backdrop-fix2">
        <section class="modal battle-report-modal-fix2" role="dialog" aria-modal="true">
          <button class="modal-close-button" type="button" data-close-battle-challenge aria-label="关闭">×</button>
          <div class="modal-seal failure-seal">止</div>
          <h3>挑战未能结算</h3>
          <p>${escapeHtml(translateError(error))}</p>
          <button class="primary-btn" type="button" data-close-battle-challenge>确定</button>
        </section>
      </div>
    `;
    modalRoot.querySelectorAll('[data-close-battle-challenge]').forEach(button => button.addEventListener('click', closeBattleChallengeModalBCombat01));
  }

  async function openBattleChallengeModalBCombat01(targetCharacterId) {
    if (!targetCharacterId) return;
    modalRoot.innerHTML = `
      <div class="modal-backdrop battle-challenge-backdrop-bcombat01">
        <section class="modal battle-challenge-modal-bcombat01" role="dialog" aria-modal="true">
          <button class="modal-close-button" type="button" data-close-battle-challenge aria-label="关闭">×</button>
          <div class="empty-state">正在读取双方战斗快照……</div>
        </section>
      </div>
    `;
    modalRoot.querySelector('[data-close-battle-challenge]')?.addEventListener('click', closeBattleChallengeModalBCombat01);
    try {
      const preview = await rpcGetBattleChallengePreviewBCombat01(targetCharacterId);
      const canStart = Boolean(preview?.can_start);
      modalRoot.innerHTML = `
        <div class="modal-backdrop battle-challenge-backdrop-bcombat01">
          <section class="modal battle-challenge-modal-bcombat01" role="dialog" aria-modal="true" aria-labelledby="battleChallengeTitleBCombat01">
            <button class="modal-close-button" type="button" data-close-battle-challenge aria-label="关闭">×</button>
            <div class="modal-seal">战</div>
            <h3 id="battleChallengeTitleBCombat01">天命榜挑战</h3>
            <div class="battle-versus-grid-bcombat01">
              ${battleCombatantCardHtml(preview?.challenger, '挑战者')}
              <div class="battle-versus-mark-bcombat01">VS</div>
              ${battleCombatantCardHtml(preview?.target, '守榜者')}
            </div>
            <div class="battle-element-relation-bcombat01">${battleElementRelationHtml(preview?.challenger, preview?.target)}</div>
            <div class="battle-risk-note-bcombat01">
              <strong>胜负皆有修为代价</strong>
              <p>挑战成功：最多转移对方当前阶段进度的 ${Number(preview?.challenger_win_rate || 0) * 100}%（${formatNumber(preview?.target_potential_loss || 0)} 修为）。<br>
              挑战失败：最多损失当前阶段进度的 ${Number(preview?.target_win_rate || 0) * 100}%（${formatNumber(preview?.challenger_potential_loss || 0)} 修为）。</p>
              <small>今日主动挑战 ${formatNumber(preview?.active_challenges_used || 0)} / ${formatNumber(preview?.active_challenges_limit || 20)} · 每场有效挑战后全局冷却20分钟 · 可以重复挑战同一对手。</small>
              ${!canStart && preview?.blocked_reason ? `<small class="battle-blocked-reason-bcombat01">当前不可挑战：${escapeHtml(preview.blocked_reason)}</small>` : ''}
              <small>${escapeHtml(preview?.transfer_note || '')}</small>
              <small>${escapeHtml(preview?.escrow_note || '')}</small>
            </div>
            <div class="modal-actions">
              <button class="ghost-btn" type="button" data-close-battle-challenge>取消</button>
              <button class="primary-btn" type="button" data-confirm-battle-challenge ${canStart ? '' : 'disabled'}>${canStart ? '确认挑战' : '当前不可挑战'}</button>
            </div>
          </section>
        </div>
      `;
      modalRoot.querySelectorAll('[data-close-battle-challenge]').forEach(button => button.addEventListener('click', closeBattleChallengeModalBCombat01));
      modalRoot.querySelector('[data-confirm-battle-challenge]')?.addEventListener('click', async event => {
        const button = event.currentTarget;
        setBusy(button, true, '交锋中……');
        closeBattleChallengeModalBCombat01();
        showBattleResolvingModalBCombat01();
        try {
          const result = await rpcChallengeBattlePowerBCombat01(targetCharacterId, createUuid());
          closeBattleChallengeModalBCombat01();
          window.setTimeout(() => showBattlePlaybackBCombat01(result), 80);
          if (state.character && result?.self_cultivation_after !== undefined) {
            state.character.cultivation = Number(result.self_cultivation_after || 0);
            state.liveCultivationBase = Number(result.self_cultivation_after || 0);
            state.liveCultivationStartedAt = Date.now();
          }
          refreshRankingBoard('battle', false, true).catch(() => {});
          refreshWorldEvents(true).catch(() => {});
        } catch (error) {
          showBattleChallengeErrorModalBCombat01(error);
        }
      });
    } catch (error) {
      modalRoot.innerHTML = `
        <div class="modal-backdrop">
          <section class="modal" role="dialog" aria-modal="true">
            <div class="modal-seal failure-seal">止</div>
            <h3>无法发起挑战</h3>
            <p>${escapeHtml(translateError(error))}</p>
            <button class="primary-btn" type="button" data-close-battle-challenge>确定</button>
          </section>
        </div>
      `;
      modalRoot.querySelector('[data-close-battle-challenge]')?.addEventListener('click', closeBattleChallengeModalBCombat01);
    }
  }

  function battleAttackCopyBCombat01(action) {
    const attacker = escapeHtml(action?.attacker_name || '无名修士');
    const defender = escapeHtml(action?.defender_name || '对手');
    const style = Math.max(1, Math.min(5, Number(action?.attack_style || 1)));
    return [
      `${attacker}凝聚灵力，正面攻向${defender}。`,
      `${attacker}踏步逼近，灵息随攻势压向${defender}。`,
      `${attacker}引动周身灵机，向${defender}发动一击。`,
      `${attacker}抓住气机变化，迅速攻向${defender}。`,
      `${attacker}身形一闪，以灵力攻势直取${defender}。`
    ][style - 1];
  }

  function battleDefenseCopyBCombat01(action) {
    const defender = escapeHtml(action?.defender_name || '对手');
    const style = Math.max(1, Math.min(5, Number(action?.defense_style || 1)));
    return [
      `${defender}稳住身形，运转道御抵挡来袭。`,
      `${defender}护住周身要害，承受这一轮攻势。`,
      `${defender}气沉丹田，以护体灵光化解部分威势。`,
      `${defender}横移卸力，尽力避开攻势锋芒。`,
      `${defender}不退反守，以自身道御承下这一击。`
    ][style - 1];
  }

  function battleActionHtmlBCombat01(action, result) {
    const challenger = result?.challenger || {};
    const target = result?.target || {};
    const attacker = action?.attacker_id === challenger.character_id ? challenger : target;
    const defender = action?.defender_id === challenger.character_id ? challenger : target;
    const multiplier = Number(action?.element_multiplier || 1);
    const elementLine = multiplier > 1
      ? `${escapeHtml(attacker.element_name || '')}行压制${escapeHtml(defender.element_name || '')}行，伤害提高${formatNumber((multiplier - 1) * 100, 0)}%。`
      : multiplier < 1
        ? `${escapeHtml(attacker.element_name || '')}行受${escapeHtml(defender.element_name || '')}行压制，伤害降低${formatNumber((1 - multiplier) * 100, 0)}%。`
        : '五行未形成直接克制，本次伤害不作修正。';
    const ringBasePercent = Math.max(0, Number(action?.ring_base_percent ?? action?.equipment_element_bonus ?? attacker?.equipment_element_bonus ?? 0));
    const ringEffectivePercent = Math.max(0, Number(action?.ring_effective_percent ?? ringBasePercent));
    const baseTalentSource = String(attacker?.talent_base_stat_source || action?.talent_base_stat_source || action?.base_stat_talent_source || '');
    const baseTalentRatePercent = Math.max(0, Number(attacker?.talent_base_stat_bonus ?? action?.talent_base_stat_bonus ?? action?.base_stat_talent_bonus ?? 0) * 100);
    const baseTalentLabel = baseTalentSource === 'mutation'
      ? `异灵根（${escapeHtml(attacker?.mutation_name || action?.mutation_name || '异')}）`
      : (baseTalentSource === 'sword_heart' ? '天生剑心' : '');
    const talentLine = [
      baseTalentLabel && baseTalentRatePercent > 0
        ? `${baseTalentLabel}已使境界基础道攻提高${formatNumber(baseTalentRatePercent, 2)}%。`
        : '',
      ringBasePercent > 0
        ? `戒指独立提供${formatNumber(ringEffectivePercent, 2)}%本命五行最终伤害加成。`
        : ''
    ].filter(Boolean).join('');
    return `
      <article class="battle-action-bcombat01 ${action?.defeated ? 'is-finisher' : ''}">
        <header><span>第 ${formatNumber(action?.round || 1)} 回合</span><strong>${escapeHtml(action?.attacker_name || '')} 出手</strong></header>
        <p>${battleAttackCopyBCombat01(action)}</p>
        <p>${battleDefenseCopyBCombat01(action)}</p>
        <p class="battle-element-line-bcombat01">${elementLine}</p>${talentLine ? `<p class="battle-talent-line-v12">${talentLine}</p>` : ''}
        <div class="battle-damage-line-bcombat01">
          <strong>造成 ${formatNumber(action?.damage || 0)} 点伤害</strong>
          <span>道御与护体共化去 ${formatNumber(Number(action?.defense_reduction || 0) * 100, 2)}%</span>
        </div>
        <div class="battle-hp-line-bcombat01"><span>${escapeHtml(action?.defender_name || '')} 生机</span><strong>${formatNumber(action?.hp_after || 0)} / ${formatNumber(action?.max_hp || 0)}</strong></div>
        ${action?.low_health ? `<small class="battle-low-health-bcombat01">${escapeHtml(action?.defender_name || '')}气息紊乱，已经显露败象。</small>` : ''}
        ${action?.defeated ? `<small class="battle-defeated-bcombat01">最后一击落下，${escapeHtml(action?.defender_name || '')}生机归零，此战胜负已定。</small>` : ''}
      </article>
    `;
  }

  function battleSettlementHtmlBCombat01(result) {
    const won = Boolean(result?.challenger_won);
    const escrow = Number(result?.cultivation_escrowed || 0);
    return `
      <section class="battle-settlement-bcombat01 ${won ? 'is-win' : 'is-loss'}">
        <div class="modal-seal ${won ? '' : 'failure-seal'}">${won ? '胜' : '败'}</div>
        <h3>${won ? '挑战成功' : '挑战失败'}</h3>
        <p><strong>${escapeHtml(result?.winner_name || '')}</strong> 击败 <strong>${escapeHtml(result?.loser_name || '')}</strong>，共战 ${formatNumber(result?.battle_rounds || 0)} 回合。</p>
        <div class="battle-reward-grid-bcombat01">
          <div><span>败者损失</span><strong>${formatNumber(result?.cultivation_transferred || 0)} 修为</strong></div>
          <div><span>胜者即时获得</span><strong>${formatNumber(result?.cultivation_granted_now || 0)} 修为</strong></div>
          ${escrow > 0 ? `<div><span>战利修为暂存</span><strong>${formatNumber(escrow)} 修为</strong></div>` : ''}
        </div>
        <small>战报已同步至九霄界闻。${Number(result?.protection_minutes || 0) > 0 ? `守榜者进入${formatNumber(result.protection_minutes)}分钟挑战保护。` : ''}</small>
        <button class="primary-btn" type="button" data-close-battle-challenge>收起战报</button>
      </section>
    `;
  }

  function showBattlePlaybackBCombat01(result) {
    if (state.battlePlaybackTimer) clearTimeout(state.battlePlaybackTimer);
    const actions = Array.isArray(result?.actions) ? result.actions : [];
    modalRoot.innerHTML = `
      <div class="modal-backdrop battle-report-backdrop-fix2">
        <section class="modal battle-challenge-modal-bcombat01 battle-playback-modal-bcombat01 battle-report-modal-fix2" role="dialog" aria-modal="true" aria-labelledby="battleReportTitleFix2">
          <button class="modal-close-button" type="button" data-close-battle-challenge aria-label="关闭">×</button>
          <h3 id="battleReportTitleFix2" class="battle-report-title-fix2">挑战战报</h3>
          <div class="battle-duel-summary-fix3" aria-label="双方对战信息">
            ${battleDuelCombatantHtmlFix3(result?.challenger, '我方', 'is-self')}
            <div class="battle-duel-versus-fix3" aria-hidden="true">战</div>
            ${battleDuelCombatantHtmlFix3(result?.target, '对方', 'is-opponent')}
          </div>
          <div class="battle-log-bcombat01 battle-log-fix3" data-battle-log aria-live="polite"></div>
          <div class="battle-playback-controls-bcombat01 battle-controls-fix3" aria-label="战报播放控制">
            <button class="ghost-btn active" type="button" data-battle-speed="1">1倍</button>
            <button class="ghost-btn" type="button" data-battle-speed="2">2倍</button>
            <button class="primary-btn" type="button" data-battle-skip>直接看结果</button>
          </div>
        </section>
      </div>
    `;
    let index = 0;
    let speed = 1;
    const log = modalRoot.querySelector('[data-battle-log]');
    const finish = () => {
      if (!log || log.dataset.finished === '1') return;
      log.dataset.finished = '1';
      log.insertAdjacentHTML('beforeend', battleSettlementHtmlBCombat01(result));
      log.querySelector('[data-close-battle-challenge]')?.addEventListener('click', closeBattleChallengeModalBCombat01);
      log.scrollTop = log.scrollHeight;
    };
    const step = () => {
      if (!log) return;
      if (index >= actions.length) return finish();
      log.insertAdjacentHTML('beforeend', battleActionHtmlBCombat01(actions[index], result));
      index += 1;
      log.scrollTop = log.scrollHeight;
      state.battlePlaybackTimer = setTimeout(step, Math.max(180, 850 / speed));
    };
    modalRoot.querySelector('[data-close-battle-challenge]')?.addEventListener('click', closeBattleChallengeModalBCombat01);
    modalRoot.querySelectorAll('[data-battle-speed]').forEach(button => button.addEventListener('click', () => {
      speed = Number(button.dataset.battleSpeed || 1);
      modalRoot.querySelectorAll('[data-battle-speed]').forEach(item => item.classList.toggle('active', item === button));
    }));
    modalRoot.querySelector('[data-battle-skip]')?.addEventListener('click', () => {
      if (state.battlePlaybackTimer) clearTimeout(state.battlePlaybackTimer);
      while (index < actions.length) {
        log?.insertAdjacentHTML('beforeend', battleActionHtmlBCombat01(actions[index], result));
        index += 1;
      }
      finish();
    });
    step();
  }

  function bindDestinyRankingActions() {
    document.querySelectorAll('[data-ranking-board]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => setRankingBoard(button.dataset.rankingBoard || 'cultivation'));
    });
    document.querySelectorAll('[data-ranking-load-more]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        const board = button.dataset.rankingLoadBoard || state.rankingBoard;
        setBusy(button, true, '展开中……');
        await refreshRankingBoard(board, true, false);
        setBusy(button, false);
      });
    });
    document.querySelectorAll('[data-battle-challenge-target]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => openBattleChallengeModalBCombat01(button.dataset.battleChallengeTarget));
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
      if (window.B_SECTV2_B01?.refresh) {
        await window.B_SECTV2_B01.refresh({ sync: true, silent });
        state.sectSystem = { status: 'module', module: 'B-SECT01' };
      } else {
        state.sectSystem = await rpcGetSectSystemV1();
        updateSectSystemPanel();
        if (!silent) showToast('宗门录已刷新。');
      }
      state.sectSystemFetchedAt = Date.now();
    } catch (error) {
      state.sectSystem = { status: 'unavailable', sects: [], buildings: [], tasks: [], recent_events: [], error: translateError(error) };
      if (!window.B_SECTV2_B01) updateSectSystemPanel();
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

  function isEquipmentEnhancementWorldEvent(eventType = '') {
    return String(eventType || '').startsWith('equipment_enhancement');
  }

  function worldEventSeal(eventType = '') {
    const type = String(eventType || '');
    if (type.startsWith('equipment_enhancement')) return '炼';
    if (type.startsWith('breakthrough')) return '劫';
    if (type.startsWith('opportunity')) return '缘';
    if (type.startsWith('secret_realm')) return '秘';
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

  function sortWorldEventEntriesNewestFirst(entries = []) {
    return [...entries].sort((left, right) => {
      const leftSequence = Number(left?.feed_sequence);
      const rightSequence = Number(right?.feed_sequence);
      if (Number.isFinite(leftSequence) && Number.isFinite(rightSequence) && leftSequence !== rightSequence) {
        return rightSequence - leftSequence;
      }
      const leftTime = new Date(left?.created_at || 0).getTime();
      const rightTime = new Date(right?.created_at || 0).getTime();
      if (leftTime !== rightTime) return rightTime - leftTime;
      return String(right?.id || '').localeCompare(String(left?.id || ''));
    });
  }

  function worldEventsPanelHtml(data = {}) {
    const entries = sortWorldEventEntriesNewestFirst(Array.isArray(data.entries) ? data.entries : []);
    if (data.status === 'unavailable') {
      return `<div id="worldEventsRoot" class="world-events-root"><div class="empty-state"><h4>九霄界闻尚未开启</h4><p>${escapeHtml(data.error || '请先执行 V0.14.2 数据库升级。')}</p><button class="ghost-btn" type="button" data-world-events-refresh>重新聆听</button></div></div>`;
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
          <article class="world-event-row level-${Math.max(1, Math.min(4, Number(entry.event_level || 1)))} ${entry.is_pinned ? 'is-pinned' : ''} ${isEquipmentEnhancementWorldEvent(entry.event_type) ? 'is-equipment-enhancement' : ''}">
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
        <div class="world-event-footer"><span>严格按最新消息排序，新消息永远置顶</span><button class="ghost-btn" type="button" data-world-events-refresh>刷新界闻</button></div>
      </div>
    `;
  }

  function updateWorldEventsPanel() {
    const root = document.getElementById('worldEventsRoot');
    if (!root) return;
    root.outerHTML = worldEventsPanelHtml(state.worldEvents || { status: 'loading', entries: [] });
    bindBazaarActions();
  }


  function treasureShopPanelHtmlV0154(shop = {}) {
    const rows = Array.isArray(shop?.items) ? shop.items : [];
    if (shop?.status === 'loading' || (!rows.length && !shop?.error)) return '<div class="empty-state">珍宝阁正在核对库存……</div>';
    if (!rows.length) return `<div class="empty-state">${escapeHtml(shop?.error || '珍宝阁暂未开放。')}</div>`;
    return `
      <div class="treasure-shop-head"><div><span>珍宝阁现货</span><strong>丹药均收入洞府储物袋</strong></div><div class="resource-inline"><span>可用灵石</span><strong data-spirit-stone-balance>${formatNumber(shop.spirit_stones ?? currentSpiritStoneBalance())}</strong></div></div>
      <div class="treasure-shop-grid">
        ${rows.map(row => `<article class="treasure-item-card rarity-${escapeHtml(row.rarity || 'rare')}">
          <div class="treasure-item-seal">${escapeHtml(String(row.name || '丹').slice(0, 1))}</div>
          <div class="treasure-item-copy"><span>${escapeHtml(row.category_name || '珍宝阁丹药')}</span><strong>${escapeHtml(row.name || '未知丹药')}</strong><p>${escapeHtml(row.description || '')}</p><small>当前持有：${formatNumber(row.owned_quantity || 0)} 枚</small></div>
          <div class="treasure-purchase"><strong>${formatNumber(row.price || 0)} 灵石 / 枚</strong><div class="treasure-quantity-stepper"><button type="button" data-treasure-quantity-delta="-1" data-treasure-code="${escapeHtml(row.code)}">−</button><input type="number" min="1" max="99" step="1" value="1" inputmode="numeric" data-treasure-quantity="${escapeHtml(row.code)}"><button type="button" data-treasure-quantity-delta="1" data-treasure-code="${escapeHtml(row.code)}">＋</button></div><button class="primary-btn" type="button" data-purchase-treasure="${escapeHtml(row.code)}">购买</button></div>
        </article>`).join('')}
      </div>`;
  }

  function bazaarPanelHtml(view = 'home', marketSystem = {}, ranking = {}, worldEvents = {}, treasureShop = {}) {
    const safeView = ['home', 'ranking', 'casino', 'treasure'].includes(view) ? view : 'home';
    if (safeView === 'home') {
      return `
        <div class="bazaar-root" data-bazaar-view="home">
          <div class="bazaar-entry-grid" aria-label="市坊功能入口">
            <button class="bazaar-entry-button" type="button" data-bazaar-target="ranking"><span aria-hidden="true">榜</span><strong>天命榜</strong><small>修为 · 财富 · 战力</small></button>
            <button class="bazaar-entry-button" type="button" data-bazaar-target="casino"><span aria-hidden="true">赌</span><strong>赌坊</strong><small>一筹问造化</small></button>
            <button class="bazaar-entry-button" type="button" data-bazaar-target="treasure"><span aria-hidden="true">珍</span><strong>珍宝阁</strong><small>渡境 · 洗灵</small></button>
          </div>
          <section class="bazaar-world-section" aria-labelledby="worldEventsHeading"><div class="bazaar-world-heading"><div><span>天道传音</span><h4 id="worldEventsHeading">九霄界闻</h4></div><small>突破 · 强化 · 机缘 · 秘境 · 赌坊</small></div>${worldEventsPanelHtml(worldEvents || { status: 'loading', entries: [] })}</section>
        </div>`;
    }
    const pageMeta = { ranking: ['天命榜', '修为、财富与战力总览'], casino: ['赌坊 · 万运博弈楼', '灵石 · 修为 · 造化彩池'], treasure: ['珍宝阁', '渡境清元丹 · 洗灵丹'] }[safeView];
    let body = '';
    if (safeView === 'ranking') body = destinyRankingPanelHtml(ranking || { status: 'loading', entries: [] });
    if (safeView === 'casino') body = `<div id="marketPanelHost">${marketPanelHtml(marketSystem || {}, state.casinoView || 'lobby')}</div>`;
    if (safeView === 'treasure') body = treasureShopPanelHtmlV0154(treasureShop || { status: 'loading', items: [] });
    return `<div class="bazaar-root bazaar-subpage" data-bazaar-view="${safeView}"><div class="bazaar-subpage-head"><button class="ghost-btn" type="button" data-bazaar-back>返回市坊</button><div><strong>${escapeHtml(pageMeta[0])}</strong><small>${escapeHtml(pageMeta[1])}</small></div></div>${body}</div>`;
  }

  function updateBazaarPanel() {
    const host = document.getElementById('bazaarPanelHost');
    if (!host) return;
    host.innerHTML = bazaarPanelHtml(state.marketView || 'home', state.marketSystem || {}, state.destinyRanking || {}, state.worldEvents || { status: 'loading', entries: [] }, state.treasureShop || {});
    bindBazaarActions();
  }

  function setBazaarView(view = 'home', pushHistory = false) {
    const safeView = ['home', 'ranking', 'casino', 'treasure'].includes(view) ? view : 'home';
    const previousView = state.marketView;
    state.marketView = safeView;
    if (safeView === 'casino' && previousView !== 'casino') state.casinoView = 'lobby';
    if (safeView === 'ranking' && previousView !== 'ranking') state.rankingBoard = 'cultivation';
    updateBazaarPanel();
    if (pushHistory && safeView !== 'home') window.history.pushState({ nineCloudBazaarView: safeView }, '', '#marketSection');
    if (safeView === 'ranking' && previousView !== 'ranking') refreshRankingBoard('cultivation', false, true);
    if (safeView === 'casino') refreshMarketSystem(true);
    if (safeView === 'treasure' && Date.now() - Number(state.treasureShopFetchedAt || 0) > 15000) refreshTreasureShopV0154(false);
    if (safeView === 'home' && Date.now() - Number(state.worldEventsFetchedAt || 0) > 15000) refreshWorldEvents(true);
  }

  function bindBazaarActions() {
    document.querySelectorAll('[data-bazaar-target]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        const target = button.dataset.bazaarTarget || 'home';
        if (target === 'casino' && !(await requireCasinoEnabledV198({ force: true, notify: true }))) return;
        setBazaarView(target, true);
      });
    });
    document.querySelectorAll('[data-bazaar-back]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => { if (window.history.state?.nineCloudBazaarView) window.history.back(); else setBazaarView('home', false); });
    });
    document.querySelectorAll('[data-world-events-refresh]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => { setBusy(button, true, '聆听中……'); await refreshWorldEvents(false); setBusy(button, false); });
    });
    document.querySelectorAll('[data-treasure-quantity-delta]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        const input = document.querySelector(`[data-treasure-quantity="${CSS.escape(button.dataset.treasureCode || '')}"]`);
        if (!input) return;
        input.value = String(Math.max(1, Math.min(99, Math.floor(Number(input.value || 1) + Number(button.dataset.treasureQuantityDelta || 0)))));
      });
    });
    document.querySelectorAll('[data-purchase-treasure]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        const code = button.dataset.purchaseTreasure;
        const input = document.querySelector(`[data-treasure-quantity="${CSS.escape(code || '')}"]`);
        const quantity = Math.max(1, Math.min(99, Math.floor(Number(input?.value || 1))));
        setBusy(button, true, '成交中……');
        try {
          const result = await rpcPurchaseTreasureItemV0154(code, quantity, createUuid());
          applyTreasurePurchaseResultV0154(result);
          setBusy(button, false);
          showToast(`已购得${result?.item_name || '丹药'} ×${formatNumber(result?.quantity || quantity)}，已收入储物袋，可立即使用。`);
          void (async () => {
            try {
              await refreshInventoryV0147();
              renderCaveSystemFromState();
              await refreshTreasureShopV0154(true);
              if (code === 'breakthrough_clear_origin_pill_v0154') await refreshBreakthroughStatus();
            } catch (syncError) {
              console.error(syncError);
            }
          })();
        } catch (error) {
          showToast(translateError(error), 'error');
          setBusy(button, false);
        }
      });
    });
    bindMarketActions();
    bindDestinyRankingActions();
    if (!bindBazaarActions.historyBound) {
      bindBazaarActions.historyBound = true;
      window.addEventListener('popstate', () => { if (state.marketView !== 'home') setBazaarView('home', false); });
    }
  }

  function renderCasinoPanel() {
    captureCasinoUiDrafts();
    const host = document.getElementById('marketPanelHost');
    if (!host) return;
    host.innerHTML = marketPanelHtml(state.marketSystem || {}, state.casinoView || 'lobby');
    bindMarketActions();
    afterCasinoRenderV0148();
  }

  function marketPoolCard(title, pool = {}, myTickets = 0, unit = '灵石') {
    const seconds = Number(pool.seconds_remaining || 0);
    const totalTickets = Number(pool.ticket_count || 0);
    let lastResult = '<p>尚无开奖记录。</p>';
    if (pool.last_draw_hit === true && Number(pool.last_prize || 0) > 0) {
      lastResult = `<p>上期抽中：${escapeHtml(pool.last_winner_name || pool.last_candidate_name || '无名修士')} · 领取 ${formatNumber(pool.last_prize || 0)} ${unit}，其余留池。</p>`;
    } else if (pool.last_draw_hit === true) {
      lastResult = `<p>上期抽中：${escapeHtml(pool.last_candidate_name || '无名修士')} · 因整数取整或修为硬上限未实际到账，奖池继续留存。</p>`;
    } else if (pool.last_draw_hit === false) {
      lastResult = `<p>上期未完成有效开奖，奖池继续留存。</p>`;
    }
    return `<article class="casino-pool-card">
      <span>${escapeHtml(title)}</span>
      <strong>${formatNumber(pool.amount || 0)} ${escapeHtml(unit)}</strong>
      <div class="casino-pool-meta"><p>本期参与 ${formatNumber(totalTickets)} 人</p><p>我的资格 ${Number(myTickets || 0) > 0 ? '已取得' : '未取得'}</p></div>
      <p>有效参与者等概率抽取 · 抽中即获奖</p>
      <p>中奖者最多领取当前奖池70% · 至少30%留存下期</p>
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

  function casinoPrimaryNavHtml(activeView = 'lobby', disabled = false) {
    const items = [
      ['lobby', '首页'],
      ['house', '大堂'],
      ['duel', '贵宾雅间'],
      ['pools', '全服造化池']
    ];
    return `<nav class="casino-primary-nav" aria-label="万运博弈楼内部导航">${items.map(([value, label]) => `<button type="button" data-casino-view="${value}" class="${activeView === value ? 'active' : ''}" ${value === 'house' && disabled ? 'disabled' : ''}>${label}</button>`).join('')}</nav>`;
  }

  function playerHouseLobbyCardsHtml(data = {}) {
    const house = data.player_house || {};
    const character = data.character || {};
    const wealth = Math.max(0, Number(house.current_wealth ?? character.spirit_stones ?? 0));
    const threshold = 5000000;
    const progress = Math.max(0, Math.min(100, threshold > 0 ? wealth / threshold * 100 : 0));
    const remaining = Math.max(0, threshold - wealth);

    if (house.status === 'unavailable') {
      return `<section id="casinoDealerStatus" class="casino-lobby-dealer-grid" aria-label="庄家状态">
        <article class="casino-lobby-dealer-card"><div class="casino-lobby-dealer-head"><strong>当前庄家</strong><span>系统庄</span></div><b>荷老</b><p>${escapeHtml(house.error || '玩家庄状态暂不可用，当前公共牌桌由荷老接管。')}</p></article>
        <article class="casino-lobby-dealer-card"><div class="casino-lobby-dealer-head"><strong>我的上庄资格</strong><span>暂不可读取</span></div><b>${formatNumber(wealth)} 灵石</b><p>统一灵石达到500万即可申请上庄。</p></article>
      </section>`;
    }

    const playerActive = house.mode === 'player';
    const dealerName = playerActive ? (house.dealer_name || '无名修士') : '荷老';
    const dealerTag = playerActive ? '玩家庄' : '系统庄';
    const dealerNote = playerActive
      ? `本次任期剩余 ${formatDuration(house.remaining_seconds || 0)}。玩家庄是公共牌桌唯一庄家；资金不足时按规则触发联合庄并在下一局下庄。`
      : '当前没有玩家庄，由荷老接管公共牌桌。';

    let eligibilityTag = '未取得';
    let eligibilityTitle = `${formatNumber(wealth)} 灵石`;
    let eligibilityNote = `距离500万上庄门槛还差 ${formatNumber(remaining)} 灵石。`;
    let eligibilityAction = '<button class="ghost-btn" type="button" data-casino-view="house">查看资格</button>';

    const cooldownSeconds = Math.max(0, Number(house.cooldown_remaining_seconds || 0));
    if (house.is_self_dealer) {
      eligibilityTag = '坐庄中';
      eligibilityTitle = '你当前正在坐庄';
      eligibilityNote = `本次任期剩余 ${formatDuration(house.remaining_seconds || 0)}，到期后需重新申请。`;
      eligibilityAction = house.can_deactivate ? '<button class="ghost-btn" type="button" data-player-house-toggle="off">主动下庄</button>' : '';
    } else if (cooldownSeconds > 0) {
      eligibilityTag = '冷却中';
      eligibilityTitle = `还需 ${formatDuration(cooldownSeconds)}`;
      eligibilityNote = '上一轮触发联合庄或风险接管，冷却结束后可再次申请上庄；期间仍可正常当闲家。';
      eligibilityAction = '<button class="ghost-btn" type="button" data-casino-view="house">进入大堂</button>';
    } else if (house.can_activate) {
      eligibilityTag = '已取得';
      eligibilityTitle = `${formatNumber(wealth)} 灵石`;
      eligibilityNote = '余额已达到500万，可自愿申请上庄，每次最多2小时。';
      eligibilityAction = '<button class="primary-btn" type="button" data-player-house-toggle="on">自愿上庄</button>';
    } else if (playerActive) {
      eligibilityTag = '已有玩家庄';
      eligibilityNote = `当前由${escapeHtml(house.dealer_name || '其他修士')}坐庄；闲家不能另选荷老。`;
    }

    return `<section id="casinoDealerStatus" class="casino-lobby-dealer-grid" aria-label="庄家状态">
      <article class="casino-lobby-dealer-card">
        <div class="casino-lobby-dealer-head"><strong>当前庄家</strong><span>${escapeHtml(dealerTag)}</span></div>
        <b>${escapeHtml(dealerName)}</b>
        <p>${dealerNote}</p>
        <div class="casino-lobby-dealer-actions"><button class="ghost-btn" type="button" data-casino-view="house">进入大堂</button></div>
      </article>
      <article class="casino-lobby-dealer-card">
        <div class="casino-lobby-dealer-head"><strong>我的上庄资格</strong><span>${escapeHtml(eligibilityTag)}</span></div>
        <b>${eligibilityTitle}</b>
        <p>${eligibilityNote}</p>
        ${!house.is_self_dealer && !house.can_activate ? `<div class="casino-lobby-dealer-progress"><i style="width:${progress.toFixed(2)}%"></i></div>` : ''}
        ${eligibilityAction ? `<div class="casino-lobby-dealer-actions">${eligibilityAction}</div>` : ''}
      </article>
    </section>`;
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
    const playerHouse = data.player_house || state.marketSystem?.player_house || {};
    if (key === 'house' && state.casinoHouseMode === 'player' && playerHouse.mode === 'player' && draft.stakeType !== 'spirit_stone') {
      draft.stakeType = 'spirit_stone';
      draft.amount = casinoStakeBase('spirit_stone', 'house');
      draft.multiplier = null;
    }
    if (key === 'house' && state.casinoHouseMode === 'player' && playerHouse.mode === 'player' && Number(draft.amount) % 80 !== 0) {
      draft.amount = casinoStakeBase('spirit_stone', 'house');
      draft.multiplier = null;
    }
    // V1.2 FIX1：气运龟卜入口已由九霄灵牌替换。兼容旧客户端本地草稿，
    // 防止隐藏的 turtle_oracle 选择继续调用旧即时开奖RPC。
    if (key === 'house' && draft.game === 'turtle_oracle') {
      draft.game = 'spirit_dice';
      draft.choice = 'big';
    }
    if (key === 'house' && !['spirit_dice','fish_shrimp'].includes(draft.game)) {
      draft.game = 'spirit_dice';
    }
    if (key === 'house' && draft.game === 'spirit_dice' && !['big', 'small', 'triple'].includes(draft.choice)) {
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
    captureFishShrimpDraftV0148();
    captureSpiritDiceDraftV175();
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
    const cultivationDisabled = !character.cultivation_eligible || Number(character.cultivation_available || 0) <= 0;
    const playerHouse = data.player_house || state.marketSystem?.player_house || {};
    const playerHouseOnlyStones = prefix === 'house' && state.casinoHouseMode === 'player' && playerHouse.mode === 'player';
    const draft = getCasinoDraft(prefix, data);
    const cultivation = draft.stakeType === 'cultivation';
    const unit = cultivation ? '修为' : '灵石';
    const base = casinoStakeBase(draft.stakeType, prefix);
    return `<div class="casino-stake-controls" data-stake-control="${escapeHtml(prefix)}">
      <label>赌注资源
        <select id="${escapeHtml(prefix)}StakeType" data-casino-stake-type="${escapeHtml(prefix)}">
          <option value="spirit_stone" ${draft.stakeType === 'spirit_stone' ? 'selected' : ''}>灵石 · 当前 ${formatNumber(character.spirit_stones || 0)}</option>
          ${playerHouseOnlyStones ? '' : `<option value="cultivation" ${draft.stakeType === 'cultivation' ? 'selected' : ''} ${cultivationDisabled ? 'disabled' : ''}>修为 · 可动用 ${formatNumber(character.cultivation_available || 0)}</option>`}
        </select>
      </label>
      <div class="casino-balance-strip">
        <span>统一灵石 <b data-spirit-stone-balance>${formatNumber(character.spirit_stones || 0)}</b></span>
        ${playerHouseOnlyStones ? '<span>玩家庄模式仅接受灵石 · 单局上限30%</span>' : `<span>当前小境界可动用 <b>${formatNumber(character.cultivation_available || 0)}</b></span><span>${prefix === 'house' ? '大堂单局上限30%' : '雅间沿用既有规则'}</span>`}
      </div>
      <div class="casino-multiplier-group">
        <span>快捷倍数</span>
        <div class="casino-multiplier-grid">
          ${multipliers.map(multiplier => `<button class="${Number(draft.multiplier) === Number(multiplier) ? 'active' : ''}" type="button" data-stake-prefix="${escapeHtml(prefix)}" data-stake-multiplier="${Number(multiplier)}">×${formatNumber(multiplier)}</button>`).join('')}
        </div>
        <small data-stake-base-hint="${escapeHtml(prefix)}">以 ${formatNumber(base)} ${unit}为基数，也可在下方直接填写任意整数。</small>
      </div>
      <label>自定义赌注数量
        <input id="${escapeHtml(prefix)}StakeAmount" data-casino-stake-amount="${escapeHtml(prefix)}" type="number" min="${cultivation ? Math.min(50000, Math.max(1, prefix === 'house' ? Math.floor(Number(character.cultivation_available || 0) * 0.30) : Number(character.cultivation_available || 0))) : 10}" step="1" inputmode="numeric" value="${escapeHtml(draft.amount)}">
      </label>
      ${cultivation && prefix !== 'house' ? `<button class="ghost-btn casino-all-in-btn" type="button" data-cultivation-all-in="${escapeHtml(prefix)}">全部修为 · ${formatNumber(character.cultivation_available || 0)}</button>` : ''}
      <div class="casino-stake-summary" data-stake-summary="${escapeHtml(prefix)}">本局确定下注：${formatNumber(draft.amount)} ${unit}</div>
    </div>`;
  }

  function houseChoiceOptions(game) {
    return game === 'turtle_oracle'
      ? [['auspicious', '押吉 · 25% · 荷老100赔280'], ['neutral', '押平 · 50% · 荷老100赔90'], ['ominous', '押凶 · 25% · 荷老100赔280']]
      : [['big', '押大 · 非豹子11～17 · 荷老100赔95'], ['small', '押小 · 非豹子4～10 · 荷老100赔95'], ['triple', '押任意豹子 · 1/36 · 荷老100赔3325']];
  }

  function casinoDrawRowsHtml(draws = []) {
    if (!draws.length) return '<div class="empty-state">造化池尚未留下开奖记录。</div>';
    return `<div class="casino-record-list">${draws.map(draw => {
      const unit = draw.stake_type === 'cultivation' ? '修为' : '灵石';
      const hit = Boolean(draw.did_hit);
      const prize = Math.max(0, Number(draw.prize_amount || 0));
      const poolAmount = Math.max(0, Number(draw.pool_amount || 0));
      const retained = Math.max(0, poolAmount - prize);
      const awarded = hit && prize > 0;
      const name = draw.candidate_name || draw.winner_name || '无名修士';
      return `<article class="casino-record-row ${hit ? 'is-hit' : 'is-miss'}">
        <div><span>${draw.stake_type === 'cultivation' ? '修为造化池' : '灵石造化池'}</span><strong>${awarded ? `票号抽中 · ${escapeHtml(name)}` : hit ? `票号抽中但未到账 · ${escapeHtml(name)}` : '未完成有效开奖'}</strong></div>
        <div><b>${awarded ? `领取 ${formatNumber(prize)} ${unit} · 留存 ${formatNumber(retained)} ${unit}` : `${formatNumber(poolAmount)} ${unit}全部留存`}</b><small>${formatNumber(draw.ticket_count || 0)} 名修士参与</small></div>
        <p>${escapeHtml(draw.result_text || '')}</p>
      </article>`;
    }).join('')}</div>`;
  }

  function casinoDuelListsHtml(data = {}) {
    const character = data.character || {};
    const cultivationAvailable = Number(character.cultivation_available || 0);
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
        <button class="ghost-btn" type="button" data-duel-join="${escapeHtml(duel.id)}" ${duel.stake_type === 'cultivation' && cultivationAvailable < Number(duel.stake_amount || 0) ? 'disabled title="当前小境界可动用修为不足"' : ''}>应局并立即开契</button>
      </article>`;
    }).join('') : '<div class="empty-state">当前没有等待应局的公开赌桌。</div>';
    const myRows = mine.length ? mine.map(duel => {
      const unit = duel.stake_type === 'cultivation' ? '修为' : '灵石';
      const choices = duel.my_choice ? `<p>你：【${escapeHtml(duel.my_choice)}】　对手：【${escapeHtml(duel.opponent_choice || '未知')}】</p>` : '';
      const outcome = duel.outcome === 'win' ? '你胜' : duel.outcome === 'loss' ? '你负' : duel.outcome === 'draw' ? '流局' : '';
      const result = escapeHtml(duel.result_text || (duel.status === 'open' ? '等待道友应局' : '结算中'));
      return `<article class="casino-duel-card mine">
        <div class="casino-duel-title"><span>${escapeHtml(duel.status_name || duel.status)}${outcome ? ` · ${outcome}` : ''}</span><strong>${escapeHtml(duel.opponent_name || '等待道友')}</strong></div>
        <p>赌注 ${formatNumber(duel.stake_amount || 0)} ${unit}</p>${choices}<p>${result}</p>
        ${duel.can_cancel ? `<button class="ghost-btn" type="button" data-duel-cancel="${escapeHtml(duel.id)}">散去赌契并返还</button>` : ''}
      </article>`;
    }).join('') : '<div class="empty-state">你暂时没有进行中的赌契。</div>';
    return `<div class="casino-duel-sections">
      <section><div class="subsection-title"><strong>公开赌桌</strong><span>${formatNumber(open.length)} 桌待应</span></div><div class="casino-duel-grid">${openRows}</div></section>
      <section><div class="subsection-title"><strong>我的赌契</strong><span>等待应局与即时结算记录</span></div><div class="casino-duel-grid">${myRows}</div></section>
    </div>`;
  }

  function playerHouseControlHtml(data = {}) {
    const house = data.player_house || {};
    if (house.status === 'unavailable') {
      return `<div class="market-lore"><p><b>玩家庄状态暂不可用。</b>${escapeHtml(house.error || '当前由荷老接管公共牌桌。')}</p></div>`;
    }
    const cooldown = Math.max(0, Number(house.cooldown_remaining_seconds || 0));
    if (house.mode === 'player') {
      const action = house.can_deactivate
        ? '<button class="ghost-btn" type="button" data-player-house-toggle="off">主动下庄</button>'
        : '';
      const pending = house.exit_pending
        ? `<p><b>本轮已触发联合庄/风险接管。</b>当前轮完整结算后自动下庄，随后30分钟不能再次上庄。</p>`
        : '';
      return `<div class="market-lore"><p><b>当前唯一庄家：${escapeHtml(house.dealer_name || '无名修士')}</b></p><p>本次任期剩余 ${formatDuration(house.remaining_seconds || 0)}，最多坐庄2小时。玩家庄存在时，闲家不能另选荷老。</p><p>玩家庄采用对称100:97.5：输家承担标准责任100%，赢家取得97.5%，2.5%固定进入赌场。玩家庄无法独立承担新责任但还能承担50%时，本轮后续由玩家庄与荷老各50%共同承担风险和庄家净收益；触发后下一轮玩家自动下庄并冷却30分钟。玩家庄/联合庄下注须为80灵石整数倍。</p>${pending}${action}</div>`;
    }
    if (cooldown > 0) {
      return `<div class="market-lore"><p><b>当前唯一庄家：荷老</b></p><p>你因上一轮触发联合庄或资金接管，距再次上庄还有 ${formatDuration(cooldown)}。冷却期间仍可正常作为闲家下注。</p></div>`;
    }
    if (house.can_activate) {
      return `<div class="market-lore"><p><b>你的统一灵石为 ${formatNumber(house.current_wealth || 0)}。</b></p><p>余额达到500万即可自愿上庄，每次最多2小时。上庄后成为公共牌桌唯一庄家；闲家不能同时选择荷老。</p><button class="primary-btn" type="button" data-player-house-toggle="on">自愿上庄</button></div>`;
    }
    return `<div class="market-lore"><p><b>当前唯一庄家：荷老</b></p><p>统一灵石达到500万即可申请上庄。没有玩家庄时，由荷老接管公共牌桌。</p></div>`;
  }


  const FISH_SHRIMP_SYMBOLS_V0148 = [
    ['fish','鱼','鱼纹法印'],
    ['shrimp','虾','虾纹法印'],
    ['crab','蟹','蟹甲法印'],
    ['coin','铜钱','古钱法印'],
    ['gourd','葫芦','葫芦法印'],
    ['frog','青蛙','蟾纹法印']
  ];

  function fishShrimpSymbolMetaV0148(code) {
    return FISH_SHRIMP_SYMBOLS_V0148.find(item => item[0] === code) || ['unknown','?','未知法印'];
  }

  const FISH_SHRIMP_SEAL_SVG_V0149 = Object.freeze({
    fish: `<svg viewBox="0 0 100 100" focusable="false"><rect x="10" y="10" width="80" height="80" rx="18" fill="rgba(199,155,88,.04)" stroke="rgba(199,155,88,.18)"/><path d="M24 50c16-20 37-25 55-9l10-8-2 16 2 16-10-8c-18 16-39 12-55-7Z" fill="none" stroke="currentColor" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/><circle cx="60" cy="44" r="3" fill="currentColor"/></svg>`,
    shrimp: `<svg viewBox="0 0 100 100" focusable="false"><rect x="10" y="10" width="80" height="80" rx="18" fill="rgba(199,155,88,.04)" stroke="rgba(199,155,88,.18)"/><path d="M73 28c-25-8-45 10-42 30 3 18 26 24 38 9 8-10 4-21-7-23-10-2-17 7-12 15" fill="none" stroke="currentColor" stroke-width="7" stroke-linecap="round"/><path d="M73 28l12-6M72 33l14 1" stroke="currentColor" stroke-width="4" stroke-linecap="round"/></svg>`,
    crab: `<svg viewBox="0 0 100 100" focusable="false"><rect x="10" y="10" width="80" height="80" rx="18" fill="rgba(199,155,88,.04)" stroke="rgba(199,155,88,.18)"/><ellipse cx="50" cy="56" rx="22" ry="14" fill="none" stroke="currentColor" stroke-width="7"/><path d="M29 49 17 37m54 12 12-12M31 61 19 65m50-4 12 4M36 68 24 80m40-12 12 12" stroke="currentColor" stroke-width="6" stroke-linecap="round"/><path d="M20 39c-5-8 2-14 10-10M80 39c5-8-2-14-10-10" fill="none" stroke="currentColor" stroke-width="5" stroke-linecap="round"/></svg>`,
    coin: `<svg viewBox="0 0 100 100" focusable="false"><rect x="10" y="10" width="80" height="80" rx="18" fill="rgba(199,155,88,.04)" stroke="rgba(199,155,88,.18)"/><circle cx="50" cy="50" r="25" fill="none" stroke="currentColor" stroke-width="8"/><rect x="39" y="39" width="22" height="22" rx="2" fill="none" stroke="currentColor" stroke-width="6"/><circle cx="50" cy="50" r="34" fill="none" stroke="currentColor" stroke-opacity=".35" stroke-width="2"/></svg>`,
    gourd: `<svg viewBox="0 0 100 100" focusable="false"><rect x="10" y="10" width="80" height="80" rx="18" fill="rgba(199,155,88,.04)" stroke="rgba(199,155,88,.18)"/><path d="M52 19c-6 6-4 13 1 19-10-2-18 4-17 14 1 6 6 11 11 13-10 2-19 10-18 21 1 12 12 19 24 17 11-2 18-12 15-23-1-7-6-11-12-14 6-4 9-9 8-16-2-8-7-12-15-11 2-6 5-11 3-20Z" fill="none" stroke="currentColor" stroke-width="7" stroke-linecap="round" stroke-linejoin="round"/></svg>`,
    frog: `<svg viewBox="0 0 100 100" focusable="false"><rect x="10" y="10" width="80" height="80" rx="18" fill="rgba(199,155,88,.04)" stroke="rgba(199,155,88,.18)"/><circle cx="35" cy="36" r="9" fill="none" stroke="currentColor" stroke-width="6"/><circle cx="65" cy="36" r="9" fill="none" stroke="currentColor" stroke-width="6"/><ellipse cx="50" cy="58" rx="24" ry="16" fill="none" stroke="currentColor" stroke-width="7"/><path d="M39 63c8 6 14 6 22 0" fill="none" stroke="currentColor" stroke-width="4" stroke-linecap="round"/></svg>`
  });

  function fishShrimpGlyphV0148(code) {
    const svg = FISH_SHRIMP_SEAL_SVG_V0149[code];
    if (!svg) {
      const meta = fishShrimpSymbolMetaV0148(code);
      return `<span class="fish-seal-glyph" aria-hidden="true">${escapeHtml(meta[1].slice(0,1))}</span>`;
    }
    return `<span class="fish-seal-glyph fish-seal-${escapeHtml(code)}" aria-hidden="true">${svg}</span>`;
  }

  function fishShrimpDraftV0148() {
    if (!state.fishShrimpDraft || typeof state.fishShrimpDraft !== 'object') {
      state.fishShrimpDraft = { stakeType: 'spirit_stone', quantity: 100, multiplier: 1 };
    }
    const draft = state.fishShrimpDraft;
    const round = state.fishShrimpState?.round || {};
    const playerBacked = Boolean(round.dealer_character_id);
    draft.stakeType = draft.stakeType === 'cultivation' ? 'cultivation' : 'spirit_stone';
    draft.quantity = Number.isSafeInteger(Number(draft.quantity)) && Number(draft.quantity) > 0
      ? Math.floor(Number(draft.quantity)) : 100;
    draft.multiplier = [1,10,100].includes(Number(draft.multiplier)) ? Number(draft.multiplier) : 1;
    if (playerBacked) {
      draft.stakeType = 'spirit_stone';
      if ((draft.quantity * draft.multiplier) % 80 !== 0) {
        draft.quantity = 80;
        draft.multiplier = 1;
      }
    }
    return draft;
  }

  function captureFishShrimpDraftV0148() {
    if (typeof document === 'undefined') return fishShrimpDraftV0148();
    const draft = fishShrimpDraftV0148();
    const quantity = document.getElementById('fishStakeQuantity');
    if (quantity && Number.isFinite(Number(quantity.value))) {
      draft.quantity = Math.max(1, Math.floor(Number(quantity.value)));
    }
    const activeType = document.querySelector('[data-fish-stake-type].active');
    if (activeType) draft.stakeType = activeType.dataset.fishStakeType === 'cultivation' ? 'cultivation' : 'spirit_stone';
    const activeMultiplier = document.querySelector('[data-fish-multiplier].active');
    if (activeMultiplier) draft.multiplier = [1,10,100].includes(Number(activeMultiplier.dataset.fishMultiplier))
      ? Number(activeMultiplier.dataset.fishMultiplier) : 1;
    state.fishShrimpDraft = draft;
    return draft;
  }

  function fishShrimpBetAmountV0148() {
    const draft = fishShrimpDraftV0148();
    const amount = Number(draft.quantity) * Number(draft.multiplier);
    return Number.isSafeInteger(amount) && amount > 0 ? amount : 0;
  }


  function fishShrimpBetQueueV0150() {
    if (!Array.isArray(state.fishShrimpBetQueue)) state.fishShrimpBetQueue = [];
    return state.fishShrimpBetQueue;
  }

  function fishShrimpBetQueueKeyV0150(roundId, houseMode, stakeType, symbolCode) {
    return [roundId || '', houseMode || 'system', stakeType || 'spirit_stone', symbolCode || ''].join('|');
  }

  function fishShrimpQueuedAmountV0150(roundId, houseMode, stakeType, symbolCode) {
    const key = fishShrimpBetQueueKeyV0150(roundId, houseMode, stakeType, symbolCode);
    return fishShrimpBetQueueV0150()
      .filter(item => item.key === key)
      .reduce((sum, item) => sum + Number(item.amount || 0), 0);
  }

  function fishShrimpQueuedClickCountV0150() {
    return fishShrimpBetQueueV0150().reduce((sum, item) => sum + Number(item.clickCount || 0), 0);
  }

  function updateFishShrimpQueueFeedbackV0150(message = '') {
    if (typeof document === 'undefined') return;
    const payload = state.fishShrimpState || {};
    const roundId = payload.round?.id || '';
    const draft = fishShrimpDraftV0148();
    const houseMode = payload.round?.dealer_character_id ? 'player' : 'system';

    document.querySelectorAll('[data-fish-symbol]').forEach(button => {
      const pending = fishShrimpQueuedAmountV0150(roundId, houseMode, draft.stakeType, button.dataset.fishSymbol);
      button.classList.toggle('queued', pending > 0);
      const pendingNode = button.querySelector?.('[data-fish-pending]');
      if (pendingNode) pendingNode.textContent = pending > 0 ? `待提交 +${formatNumber(pending)}` : '';
    });

    const status = document.getElementById('fishBetStatus');
    if (!status) return;
    const clicks = fishShrimpQueuedClickCountV0150();
    if (clicks > 0) {
      status.textContent = `已合并 ${formatNumber(clicks)} 次点击，本批只提交一次事务；本局累计不得超过首次落注时资源30%。`;
      status.classList.add('is-queueing');
      return;
    }
    status.classList.remove('is-queueing');
    if (message) status.textContent = message;
    else if (state.fishShrimpLastBetMessage) status.textContent = state.fishShrimpLastBetMessage;
  }

  function scheduleFishShrimpBetQueueV0150() {
    if (state.fishShrimpBetProcessing || state.fishShrimpBetFlushTimer) return;
    state.fishShrimpBetFlushTimer = setTimeout(() => {
      state.fishShrimpBetFlushTimer = null;
      processFishShrimpBetQueueV0150();
    }, 120);
  }

  function enqueueFishShrimpBetV0150(_houseMode, stakeType, symbolCode, amount) {
    const round = state.fishShrimpState?.round || {};
    const roundId = round.id || '';
    const houseMode = round.dealer_character_id ? 'player' : 'system';
    if (!roundId || round.phase !== 'betting') {
      showToast('本局已封盘，请等待下一局。', 'error');
      return false;
    }
    if (!Number.isSafeInteger(Number(amount)) || Number(amount) < 1) {
      showToast('请输入有效的下注数量。', 'error');
      return false;
    }
    if (round.dealer_character_id && Number(amount) % 80 !== 0) {
      showToast('玩家庄与联合庄下注必须为80灵石的整数倍。', 'error');
      return false;
    }
    const queue = fishShrimpBetQueueV0150();
    const character = state.fishShrimpState?.character || state.marketSystem?.character || {};
    const available = stakeType === 'cultivation'
      ? Number(character.cultivation_available || 0)
      : Number(character.spirit_stones || 0);
    const alreadyAccepted = (state.fishShrimpState?.my_bets || [])
      .filter(item => item.stake_type === stakeType)
      .reduce((sum,item) => sum + Number(item.stake_amount || 0),0);
    // 服务端以首次落注前可用资源为30%基准；当前余额已扣除已接受下注，故本地用“当前可用+已接受”近似还原基准。
    const maximum = Math.max(0, Math.floor((available + alreadyAccepted) * 0.30));
    const queuedForResource = queue
      .filter(item => item.roundId === roundId && item.stakeType === stakeType)
      .reduce((sum, item) => sum + Number(item.amount || 0), 0);
    if (alreadyAccepted + queuedForResource + Number(amount) > maximum) {
      showToast(`本局累计下注不得超过首次落注时可用${stakeType === 'cultivation' ? '修为' : '灵石'}的30%（约${formatNumber(maximum)}）。`, 'error');
      return false;
    }
    const key = fishShrimpBetQueueKeyV0150(roundId, houseMode, stakeType, symbolCode);
    const existing = queue.find(item => item.key === key && !item.processing);
    if (existing) {
      const nextAmount = Number(existing.amount || 0) + Number(amount);
      if (!Number.isSafeInteger(nextAmount) || nextAmount > 9007199254740991) {
        showToast('连续下注金额过大，请稍后再试。', 'error');
        return false;
      }
      existing.amount = nextAmount;
      existing.clickCount = Number(existing.clickCount || 0) + 1;
    } else {
      queue.push({ key, roundId, houseMode, stakeType, symbolCode, amount: Number(amount), clickCount: 1, processing: false });
    }
    const meta = fishShrimpSymbolMetaV0148(symbolCode);
    const unit = stakeType === 'cultivation' ? '修为' : '灵石';
    state.fishShrimpLastBetMessage = `已点${meta[1]} +${formatNumber(amount)} ${unit}；等待120ms合并本批点击。`;
    updateFishShrimpQueueFeedbackV0150();
    scheduleFishShrimpBetQueueV0150();
    return true;
  }

  function applyFishShrimpBatchPayloadV175(payload) {
    if (!payload || !payload.batch_only) {
      if (payload) { payload.client_fetched_at = Date.now(); state.fishShrimpState = payload; }
      return;
    }
    const current = state.fishShrimpState;
    if (!current?.round || String(current.round.id || '') !== String(payload.round_id || '')) {
      setTimeout(() => refreshFishShrimpStateV0148(true), 0);
      return;
    }
    current.server_now = payload.server_now || current.server_now;
    current.client_fetched_at = Date.now();
    current.character = { ...(current.character || {}), ...(payload.character || {}) };
    Object.assign(current.round, payload.round_patch || {});
    if (!Array.isArray(current.my_bets)) current.my_bets = [];
    if (!Array.isArray(current.round_totals)) current.round_totals = [];
    const accepted = Array.isArray(payload.accepted_bets) ? payload.accepted_bets : [];
    spiritDiceRememberAcceptedBetsV175(payload.round_id || current.round?.id, accepted);
    accepted.forEach(row => {
      const item = { ...row, stake_amount: Number(row.stake_amount || 0), net_profit: 0, result_count: null, is_settled: false };
      current.my_bets.push(item);
      const total = current.round_totals.find(x => x.house_mode === item.house_mode && x.stake_type === item.stake_type && x.symbol_code === item.symbol_code);
      if (total) total.stake_amount = Number(total.stake_amount || 0) + item.stake_amount;
      else current.round_totals.push({ house_mode: item.house_mode, stake_type: item.stake_type, symbol_code: item.symbol_code, stake_amount: item.stake_amount });
    });
    if (payload.character && state.marketSystem?.character) {
      state.marketSystem.character.spirit_stones = Number(payload.character.spirit_stones || 0);
      state.marketSystem.character.cultivation_available = Number(payload.character.cultivation_available || 0);
      setLocalSpiritStoneBalance(Number(payload.character.spirit_stones || 0));
    }
  }

  async function processFishShrimpBetQueueV0150() {
    if (state.fishShrimpBetProcessing) return;
    const queue = fishShrimpBetQueueV0150();
    if (!queue.length) return;
    state.fishShrimpBetProcessing = true;
    try {
      const first = queue[0];
      const batch = queue.filter(item => item.roundId === first.roundId && item.stakeType === first.stakeType && !item.processing).slice(0,6);
      batch.forEach(item => { item.processing = true; });
      const bets = batch.map(item => ({ symbol_code: item.symbolCode, stake_amount: Number(item.amount) }));
      try {
        const payload = await rpcPlaceFishShrimpBetsV175(first.stakeType, bets);
        state.fishShrimpBetQueue = queue.filter(item => !batch.includes(item));
        applyFishShrimpBatchPayloadV175(payload);
        const unit = first.stakeType === 'cultivation' ? '修为' : '灵石';
        const clicks = batch.reduce((sum,item)=>sum+Number(item.clickCount||0),0);
        const amount = batch.reduce((sum,item)=>sum+Number(item.amount||0),0);
        state.fishShrimpLastBetMessage = `本批${formatNumber(clicks)}次点击已用1次事务提交，共 ${formatNumber(amount)} ${unit}。`;
      } catch (error) {
        state.fishShrimpBetQueue = queue.filter(item => !batch.includes(item));
        const message = translateError(error);
        state.fishShrimpLastBetMessage = `本批落注失败：${message}`;
        showToast(message, 'error');
        if (String(error?.message || error).includes('FISH_BETTING_CLOSED')) {
          state.fishShrimpBetQueue = state.fishShrimpBetQueue.filter(item => item.roundId !== first.roundId);
        }
      }
      renderFishShrimpPanelV0148();
      startFishShrimpTimerV0148();
      updateFishShrimpQueueFeedbackV0150(state.fishShrimpLastBetMessage);
    } finally {
      state.fishShrimpBetProcessing = false;
      // 批量下注RPC已返回最新可用余额，避免每批再追加两次余额/修为请求。
      if (fishShrimpBetQueueV0150().length) scheduleFishShrimpBetQueueV0150();
    }
  }

  function fishShrimpBetLookupV0148(list, _houseMode, stakeType, symbolCode) {
    const rows = (Array.isArray(list) ? list : []).filter(item =>
      item.stake_type === stakeType && item.symbol_code === symbolCode
    );
    if (!rows.length) return null;
    return rows.reduce((acc, item) => ({
      ...acc,
      stake_amount: Number(acc.stake_amount || 0) + Number(item.stake_amount || 0),
      net_profit: Number(acc.net_profit || 0) + Number(item.net_profit || 0),
      bet_count: Number(acc.bet_count || 0) + Number(item.bet_count || 0)
    }), { ...rows[0], stake_amount: 0, net_profit: 0, bet_count: 0 });
  }

  function fishShrimpRoundTotalV0148(list, _houseMode, stakeType, symbolCode) {
    return (Array.isArray(list) ? list : [])
      .filter(item => item.stake_type === stakeType && item.symbol_code === symbolCode)
      .reduce((sum, item) => sum + Number(item.stake_amount || 0), 0);
  }

  function fishShrimpPhaseTextV0148(phase) {
    if (phase === 'betting') return ['开放下注','限时下注'];
    if (phase === 'locked') return ['封盘核对','落注已锁定'];
    if (phase === 'revealing') return ['正在开盘','灵骰依次停定'];
    if (phase === 'settled') return ['结算展示','查看本局结果'];
    return ['读取天机','正在同步'];
  }

  function fishShrimpHistoryGroupHtmlV0148(group) {
    const items = Array.isArray(group?.items) ? group.items : [];
    const rows = items.map(item => {
      const unit = item.stake_type === 'cultivation' ? '修为' : '灵石';
      const net = Number(item.net_profit || 0);
      return `<div class="fish-settlement-line"><span>${escapeHtml(item.symbol_name || fishShrimpSymbolMetaV0148(item.symbol_code)[1])}：${formatNumber(item.stake_amount || 0)} ${unit}</span><b class="${net >= 0 ? 'positive' : 'negative'}">${net >= 0 ? '赢' : '输'} ${formatNumber(Math.abs(net))}</b></div>`;
    }).join('');
    return `<div class="fish-settlement-group"><strong>${escapeHtml(group?.dealer_label || (group?.house_mode === 'player' ? '玩家局' : '荷老局'))}</strong>${rows || '<small>本桌无下注。</small>'}</div>`;
  }

  function fishShrimpHistoryHtmlV0148(history = []) {
    if (!Array.isArray(history) || !history.length) return '<div class="empty-state">尚无已结算轮次。</div>';
    return history.slice(0,20).map(item => {
      const result = Array.isArray(item.results) ? item.results : [];
      const groups = Array.isArray(item.groups) ? item.groups : [];
      const groupRows = groups.length ? groups.map(group => {
        const label = group.dealer_label || (group.house_mode === 'player' ? '玩家局' : '荷老局');
        const items = Array.isArray(group.items) ? group.items : [];
        const itemText = items.map(x => {
          const unit = x.stake_type === 'cultivation' ? '修为' : '灵石';
          const net = Number(x.net_profit || 0);
          return `${x.symbol_name || fishShrimpSymbolMetaV0148(x.symbol_code)[1]} ${formatNumber(x.stake_amount || 0)} ${unit}，${net >= 0 ? '赢' : '输'} ${formatNumber(Math.abs(net))}`;
        }).join('；') || '无个人下注';
        return `<div class="fish-history-group-summary"><strong>${escapeHtml(label)}</strong><small>${escapeHtml(itemText)}</small></div>`;
      }).join('') : '<div class="fish-history-group-summary"><strong>无下注</strong><small>本局没有个人下注记录。</small></div>';
      return `<article class="fish-history-row"><b>${String(item.round_no || '').slice(-6)}</b><div><div class="fish-history-dice">${result.map(code => `<span>${fishShrimpGlyphV0148(code)}</span>`).join('')}</div>${groupRows}</div></article>`;
    }).join('');
  }

  function fishShrimpPanelHtmlV0148(data = {}) {
    const payload = state.fishShrimpState || {};
    const round = payload.round || {};
    const character = payload.character || data.character || {};
    const draft = fishShrimpDraftV0148();
    const dealerMode = round.dealer_mode || (round.dealer_character_id ? 'player' : 'system');
    const playerBacked = Boolean(round.dealer_character_id);
    if (playerBacked && draft.stakeType === 'cultivation') draft.stakeType = 'spirit_stone';
    const houseMode = playerBacked ? 'player' : 'system';
    const dealerLabel = dealerMode === 'joint'
      ? `${round.dealer_name || '玩家庄'} · 荷老联庄`
      : dealerMode === 'system_takeover'
        ? '荷老接管'
        : playerBacked ? (round.dealer_name || '玩家庄') : '荷老';
    const dealerTag = dealerMode === 'joint' ? '50/50联合庄' : dealerMode === 'system_takeover' ? '风险接管' : playerBacked ? '玩家庄' : '系统庄';
    const unit = draft.stakeType === 'cultivation' ? '修为' : '灵石';
    const amount = fishShrimpBetAmountV0148();
    const phaseInfo = fishShrimpPhaseTextV0148(round.phase);
    const results = Array.isArray(round.results) ? round.results : [];
    const elapsed = Number(round.elapsed_seconds || 0);
    const myBets = Array.isArray(payload.my_bets) ? payload.my_bets : [];
    const totals = Array.isArray(payload.round_totals) ? payload.round_totals : [];
    const open = round.phase === 'betting';
    const history = Array.isArray(payload.history) ? payload.history : [];
    const latest = history.find(item => item?.has_bets) || null;
    const resultCounts = {};
    results.forEach(code => { resultCounts[code] = (resultCounts[code] || 0) + 1; });

    const diceHtml = [0,1,2].map(index => {
      const stopAt = 33 + index * 2;
      const visible = results[index] && elapsed >= stopAt;
      const code = visible ? results[index] : '';
      return `<div class="fish-die ${open ? '' : visible ? 'stopped' : 'rolling'}" data-fish-die-index="${index}" data-result-code="${escapeHtml(results[index] || '')}"><div>${code ? fishShrimpGlyphV0148(code) : '<span class="fish-die-idle">灵</span>'}</div></div>`;
    }).join('');

    const targetHtml = FISH_SHRIMP_SYMBOLS_V0148.map(([code,name,note]) => {
      const bet = fishShrimpBetLookupV0148(myBets,houseMode,draft.stakeType,code);
      const myAmount = Number(bet?.stake_amount || 0);
      const total = fishShrimpRoundTotalV0148(totals,houseMode,draft.stakeType,code);
      const hit = Boolean(round.is_settled && myAmount > 0 && Number(bet?.result_count || resultCounts[code] || 0) > 0);
      const pending = fishShrimpQueuedAmountV0150(round.id,houseMode,draft.stakeType,code);
      const cardClass = ['fish-target-card',hit ? 'win' : '',pending > 0 ? 'queued' : ''].filter(Boolean).join(' ');
      return `<button type="button" class="${cardClass}" data-fish-symbol="${code}" ${open ? '' : 'disabled'}>
        <div class="fish-target-head"><span>${fishShrimpGlyphV0148(code)}</span><div><strong>${name}</strong><small>${note}</small></div></div>
        <div class="fish-target-meta"><span>我的下注 <b>${formatNumber(myAmount)}</b></span><span>全场总额 <b>${formatNumber(total)}</b></span></div>
        <em class="fish-target-pending" data-fish-pending>${pending > 0 ? `待提交 +${formatNumber(pending)}` : ''}</em>
      </button>`;
    }).join('');

    const latestDetail = latest
      ? `<div class="fish-latest-result"><div class="fish-result-title">第${escapeHtml(latest.round_no)}局 · 开出 ${(latest.results || []).map(code => fishShrimpSymbolMetaV0148(code)[1]).join('、')}</div>${(latest.groups || []).map(fishShrimpHistoryGroupHtmlV0148).join('')}</div>`
      : '<div class="empty-state">尚无个人结算明细。</div>';

    return `<section id="fishShrimpRoot" class="fish-game-shell" data-round-id="${escapeHtml(round.id || '')}" data-server-now="${escapeHtml(payload.server_now || '')}" data-round-start="${escapeHtml(round.starts_at || '')}" data-betting-close="${escapeHtml(round.betting_closes_at || '')}" data-reveal-at="${escapeHtml(round.reveal_at || '')}" data-settle-at="${escapeHtml(round.settles_at || '')}" data-round-end="${escapeHtml(round.ends_at || '')}">
      <div class="fish-compact-top">
        <div class="fish-title-row"><div><strong>鱼虾灵局</strong><small>三骰共开 · 六门同押 · 单一庄家</small></div><span id="fishPhaseBadge">${phaseInfo[0]}</span></div>
        <div class="fish-balance-grid"><div><span>可用灵石</span><b data-spirit-stone-balance>${formatNumber(character.spirit_stones || 0)}</b></div><div><span>可用修为</span><b>${formatNumber(character.cultivation_available || 0)}</b></div></div>
      </div>
      <div class="fish-compact-block fish-time-block"><div><strong>下注时间</strong><small id="fishPhaseText">${phaseInfo[1]}</small></div><b id="fishCountdown">${formatNumber(round.seconds_remaining || 0)}秒</b><div class="fish-progress"><i id="fishProgressFill" style="width:${Math.max(0,Math.min(100,elapsed/40*100))}%"></i></div></div>
      <div class="fish-compact-block fish-dealer-block"><div><span>当前庄家 · ${dealerTag}</span><b>${escapeHtml(dealerLabel)}</b></div><div class="fish-dealer-switch single"><button type="button" class="active" disabled>${escapeHtml(dealerTag)}</button></div></div>
      <div class="fish-compact-block fish-settings-block">
        <div class="fish-settings-title"><strong>押注设置</strong><span id="fishQuickPreview">${unit} · ${formatNumber(draft.quantity)} × ${draft.multiplier}</span></div>
        <div class="fish-resource-switch"><button type="button" data-fish-stake-type="spirit_stone" class="${draft.stakeType === 'spirit_stone' ? 'active' : ''}">灵石</button><button type="button" data-fish-stake-type="cultivation" class="${draft.stakeType === 'cultivation' ? 'active' : ''}" ${playerBacked ? 'disabled title="本轮由玩家庄参与，只接受灵石"' : ''}>修为</button></div>
        <div class="fish-setting-row"><label>数量<input id="fishStakeQuantity" type="number" min="${playerBacked ? 80 : 1}" step="${playerBacked ? 80 : 1}" inputmode="numeric" value="${escapeHtml(draft.quantity)}"></label><div><span>倍率</span><div class="fish-multiplier-grid">${[1,10,100].map(multiplier => `<button type="button" data-fish-multiplier="${multiplier}" class="${draft.multiplier === multiplier ? 'active' : ''}">${multiplier}倍</button>`).join('')}</div></div></div>
        <div class="fish-bet-preview" id="fishBetPreview">本次下注：<b>${formatNumber(amount)} ${unit}</b></div>
      </div>
      <div class="fish-draw-block"><div class="fish-section-head"><div><strong>开盘灵骰</strong><small>封盘后疾转，依次停定</small></div><span>${round.round_no ? `第${escapeHtml(round.round_no)}局` : '同步中'}</span></div><div class="fish-orbit"><div class="fish-dice-row">${diceHtml}</div></div><small class="fish-draw-note">同轮所有闲家共用同一份开奖结果；本轮庄家在开盘前锁定，玩家庄存在时不能另选荷老。</small></div>
      <div class="fish-target-block"><div class="fish-section-head"><div><strong>选择压什么</strong><small>120毫秒内连续点击会合并为一次批量事务</small></div><button type="button" class="ghost-btn fish-refresh-btn" data-fish-refresh>刷新</button></div><div class="fish-target-grid">${targetHtml}</div><div class="fish-bet-status" id="fishBetStatus">${open ? '开放下注；本局累计下注不得超过首次落注时资源的30%。' : '本局已封盘，等待开盘与结算。'}</div></div>
      <div class="fish-history-block"><div class="fish-section-head"><div><strong>最近20局结算历史</strong><small>历史固定20局，避免长时间运行累积DOM</small></div></div><div class="fish-history-list">${fishShrimpHistoryHtmlV0148(history)}</div></div>
      <div class="fish-detail-block"><div class="fish-section-head"><div><strong>结算明细</strong><small>按法印列出下注与本局输赢</small></div></div>${latestDetail}</div>
      <details class="fish-rules-block"><summary>规则</summary><p>每局40秒：前30秒下注、2秒封盘、5秒依次开骰、3秒展示结算。荷老系统庄命中1、2、3枚时，每100净赢95、190、285；未出现则损失该门下注。</p><p>玩家庄是本轮唯一庄家，只接受灵石，下注须为80灵石整数倍。无论庄赢或闲家赢，输家承担标准责任100%，赢家取得97.5%，2.5%进入赌场。玩家庄无法独立承担新责任但能承担50%时，本轮后续进入玩家庄+荷老50/50联合庄；触发后下一轮玩家自动下庄并冷却30分钟。连50%也无法承担时，荷老接管后续新责任。</p></details>
    </section>`;
  }

  function renderFishShrimpPanelV0148() {
    const current = document.getElementById('fishShrimpRoot');
    if (!current) return;
    const wrapper = document.createElement('div');
    wrapper.innerHTML = fishShrimpPanelHtmlV0148(state.marketSystem || {});
    const next = wrapper.firstElementChild;
    if (!next) return;
    current.replaceWith(next);
    bindMarketActions();
    updateFishShrimpClockV0148();
  }

  async function refreshFishShrimpStateV0148(silent = false) {
    if (state.fishShrimpSyncing || state.fishShrimpBetProcessing || !state.character || document.hidden) return state.fishShrimpState;
    state.fishShrimpSyncing = true;
    try {
      const payload = await rpcGetFishShrimpStateV0148(20);
      if (payload) {
        payload.client_fetched_at = Date.now();
        state.fishShrimpState = payload;
        if (payload.character && state.marketSystem?.character) {
          state.marketSystem.character.spirit_stones = Number(payload.character.spirit_stones || 0);
          state.marketSystem.character.cultivation_available = Number(payload.character.cultivation_available || 0);
          setLocalSpiritStoneBalance(Number(payload.character.spirit_stones || 0));
        }
      }
      renderFishShrimpPanelV0148();
      startFishShrimpTimerV0148();
      return state.fishShrimpState;
    } catch (error) {
      if (!silent) showToast(translateError(error), 'error');
      return state.fishShrimpState;
    } finally {
      state.fishShrimpSyncing = false;
    }
  }

  function stopFishShrimpTimerV0148() {
    if (state.fishShrimpTimer) clearInterval(state.fishShrimpTimer);
    if (state.fishShrimpBoundaryRefreshTimer) clearTimeout(state.fishShrimpBoundaryRefreshTimer);
    state.fishShrimpTimer = null;
    state.fishShrimpBoundaryRefreshTimer = null;
    state.fishShrimpRefreshGuard = false;
  }

  function startFishShrimpTimerV0148() {
    stopFishShrimpTimerV0148();
    if (!document.getElementById('fishShrimpRoot')) return;
    state.fishShrimpTimer = setInterval(updateFishShrimpClockV0148, 500);
    updateFishShrimpClockV0148();
  }

  function updateFishShrimpClockV0148() {
    const root = document.getElementById('fishShrimpRoot');
    const payload = state.fishShrimpState;
    const round = payload?.round;
    if (!root || !round) return;
    const fetchedAt = Number(payload.client_fetched_at || Date.now());
    const serverBase = Date.parse(payload.server_now || '') || Date.now();
    const now = serverBase + (Date.now() - fetchedAt);
    const start = Date.parse(round.starts_at || '') || now;
    const close = Date.parse(round.betting_closes_at || '') || start + 30000;
    const reveal = Date.parse(round.reveal_at || '') || start + 32000;
    const settle = Date.parse(round.settles_at || '') || start + 37000;
    const end = Date.parse(round.ends_at || '') || start + 40000;
    const elapsed = Math.max(0,(now-start)/1000);
    let phase = 'betting';
    let phaseEnd = close;
    if (now >= close && now < reveal) { phase = 'locked'; phaseEnd = reveal; }
    else if (now >= reveal && now < settle) { phase = 'revealing'; phaseEnd = settle; }
    else if (now >= settle && now < settle + 3000) { phase = 'settled'; phaseEnd = settle + 3000; }
    else if (now >= settle + 3000 && now < end) { phase = 'settled'; phaseEnd = end; }
    else if (now >= end) { phase = 'next'; phaseEnd = end; }
    const info = fishShrimpPhaseTextV0148(phase);
    const countdown = Math.max(0,Math.ceil((phaseEnd-now)/1000));
    const badge = document.getElementById('fishPhaseBadge');
    const phaseText = document.getElementById('fishPhaseText');
    const countdownNode = document.getElementById('fishCountdown');
    const progress = document.getElementById('fishProgressFill');
    if (badge) badge.textContent = info[0];
    if (phaseText) phaseText.textContent = info[1];
    if (countdownNode) countdownNode.textContent = `${countdown}秒`;
    if (progress) progress.style.width = `${Math.max(0,Math.min(100,elapsed/40*100))}%`;

    root.querySelectorAll('[data-fish-die-index]').forEach(node => {
      const index = Number(node.dataset.fishDieIndex || 0);
      const code = node.dataset.resultCode || '';
      const visible = code && elapsed >= 33 + index * 2;
      node.classList.toggle('rolling', phase !== 'betting' && !visible);
      node.classList.toggle('stopped', Boolean(visible));
      const inner = node.firstElementChild;
      if (inner) inner.innerHTML = visible ? fishShrimpGlyphV0148(code) : '<span class="fish-die-idle">灵</span>';
    });
    root.querySelectorAll('[data-fish-symbol]').forEach(button => { button.disabled = phase !== 'betting'; });

    // 多人桌只在“开奖结果需要公开”和“下一轮切换”两个边界取权威状态；结算展示阶段不额外轮询。
    const needsRefresh = phase === 'next'
      || (phase === 'revealing' && (!Array.isArray(round.results) || !round.results.length));
    if (needsRefresh && !state.fishShrimpRefreshGuard && !state.fishShrimpSyncing && !state.fishShrimpBoundaryRefreshTimer) {
      state.fishShrimpRefreshGuard = true;
      // 阶段边界给不同客户端40～200ms轻微抖动，避免大量在线玩家在同一毫秒同时请求权威状态。
      const jitter = 40 + Math.floor(Math.random() * 161);
      state.fishShrimpBoundaryRefreshTimer = setTimeout(() => {
        state.fishShrimpBoundaryRefreshTimer = null;
        refreshFishShrimpStateV0148(true).finally(() => { state.fishShrimpRefreshGuard = false; });
      }, jitter);
    }
  }


  const SPIRIT_DICE_TARGETS_V175 = [
    ['big','大','总点11～17，豹子不算大'],
    ['small','小','总点4～10，豹子不算小'],
    ['triple','豹子','任意三骰相同'],
    ['face1','1','每出现1枚按1倍标准责任'],
    ['face2','2','每出现1枚按1倍标准责任'],
    ['face3','3','每出现1枚按1倍标准责任'],
    ['face4','4','每出现1枚按1倍标准责任'],
    ['face5','5','每出现1枚按1倍标准责任'],
    ['face6','6','每出现1枚按1倍标准责任']
  ];

  function spiritDiceTargetMetaV175(code) {
    return SPIRIT_DICE_TARGETS_V175.find(item => item[0] === code) || ['unknown','?','未知'];
  }

  // V1.7.5.3 CACHE54：灵骰命中高亮直接按本局公共三骰结果计算，
  // 不依赖结算明细里的 result_count；这样大/小/豹子/数字命中都能和鱼虾灵局复用同一 .win 发光边框。
  function spiritDiceChoiceHitV175(results, choiceCode) {
    const dice = Array.isArray(results) ? results.map(Number).filter(v => Number.isInteger(v) && v >= 1 && v <= 6) : [];
    if (dice.length !== 3) return false;
    const triple = dice[0] === dice[1] && dice[1] === dice[2];
    const total = dice[0] + dice[1] + dice[2];
    if (choiceCode === 'triple') return triple;
    if (choiceCode === 'big') return !triple && total >= 11 && total <= 17;
    if (choiceCode === 'small') return !triple && total >= 4 && total <= 10;
    const match = /^face([1-6])$/.exec(String(choiceCode || ''));
    if (match) return dice.includes(Number(match[1]));
    return false;
  }

  // V1.7.5.3 CACHE54：本人已接受下注使用“服务端my_bets + 本机已确认批次”双源判断。
  // 不再依赖当前灵石/修为切换，也不依赖DOM上一次重绘留下的data属性。
  function spiritDiceRememberAcceptedBetsV175(roundId, rows = []) {
    const id = String(roundId || '');
    if (!id) return;
    if (!state.spiritDiceAcceptedBetRounds || typeof state.spiritDiceAcceptedBetRounds !== 'object') {
      state.spiritDiceAcceptedBetRounds = {};
    }
    const bucket = state.spiritDiceAcceptedBetRounds[id] || {};
    (Array.isArray(rows) ? rows : []).forEach(row => {
      const code = String(row?.choice_code || '');
      const amount = Number(row?.stake_amount || 0);
      if (code && amount > 0) bucket[code] = Number(bucket[code] || 0) + amount;
    });
    state.spiritDiceAcceptedBetRounds = { [id]: bucket };
  }

  function spiritDiceHasAcceptedBetV175(roundId, choiceCode) {
    const id = String(roundId || '');
    const code = String(choiceCode || '');
    if (!id || !code) return false;
    const serverHas = (Array.isArray(state.spiritDiceState?.my_bets) ? state.spiritDiceState.my_bets : [])
      .some(row => String(row?.choice_code || '') === code && Number(row?.stake_amount || 0) > 0);
    if (serverHas) return true;
    return Number(state.spiritDiceAcceptedBetRounds?.[id]?.[code] || 0) > 0;
  }

  function spiritDiceDraftV175() {
    if (!state.spiritDiceDraft || typeof state.spiritDiceDraft !== 'object') {
      state.spiritDiceDraft = { stakeType: 'spirit_stone', quantity: 100, multiplier: 1 };
    }
    const draft = state.spiritDiceDraft;
    const round = state.spiritDiceState?.round || {};
    const playerBacked = Boolean(round.dealer_character_id);
    draft.stakeType = draft.stakeType === 'cultivation' ? 'cultivation' : 'spirit_stone';
    draft.quantity = Number.isSafeInteger(Number(draft.quantity)) && Number(draft.quantity) > 0 ? Math.floor(Number(draft.quantity)) : 100;
    draft.multiplier = [1,10,100].includes(Number(draft.multiplier)) ? Number(draft.multiplier) : 1;
    if (playerBacked) {
      draft.stakeType = 'spirit_stone';
      if ((draft.quantity * draft.multiplier) % 80 !== 0) {
        draft.quantity = 80;
        draft.multiplier = 1;
      }
    }
    return draft;
  }

  function captureSpiritDiceDraftV175() {
    const draft = spiritDiceDraftV175();
    if (typeof document === 'undefined') return draft;
    const quantity = document.getElementById('diceStakeQuantity');
    if (quantity && Number.isFinite(Number(quantity.value))) draft.quantity = Math.max(1, Math.floor(Number(quantity.value)));
    const activeType = document.querySelector('[data-dice-stake-type].active');
    if (activeType) draft.stakeType = activeType.dataset.diceStakeType === 'cultivation' ? 'cultivation' : 'spirit_stone';
    const activeMultiplier = document.querySelector('[data-dice-multiplier].active');
    if (activeMultiplier) draft.multiplier = [1,10,100].includes(Number(activeMultiplier.dataset.diceMultiplier)) ? Number(activeMultiplier.dataset.diceMultiplier) : 1;
    state.spiritDiceDraft = draft;
    return draft;
  }

  function spiritDiceBetAmountV175() {
    const draft = spiritDiceDraftV175();
    const amount = Number(draft.quantity) * Number(draft.multiplier);
    return Number.isSafeInteger(amount) && amount > 0 ? amount : 0;
  }

  function spiritDiceQueueV175() {
    if (!Array.isArray(state.spiritDiceBetQueue)) state.spiritDiceBetQueue = [];
    return state.spiritDiceBetQueue;
  }

  function spiritDiceQueueKeyV175(roundId, houseMode, stakeType, choiceCode) {
    return [roundId || '', houseMode || 'system', stakeType || 'spirit_stone', choiceCode || ''].join('|');
  }

  function spiritDiceQueuedAmountV175(roundId, houseMode, stakeType, choiceCode) {
    const key = spiritDiceQueueKeyV175(roundId, houseMode, stakeType, choiceCode);
    return spiritDiceQueueV175().filter(item => item.key === key).reduce((sum,item)=>sum+Number(item.amount||0),0);
  }

  function spiritDiceQueuedClicksV175() {
    return spiritDiceQueueV175().reduce((sum,item)=>sum+Number(item.clickCount||0),0);
  }

  function updateSpiritDiceQueueFeedbackV175(message = '') {
    if (typeof document === 'undefined') return;
    const payload = state.spiritDiceState || {};
    const roundId = payload.round?.id || '';
    const houseMode = payload.round?.dealer_character_id ? 'player' : 'system';
    const draft = spiritDiceDraftV175();
    document.querySelectorAll('[data-dice-choice]').forEach(button => {
      const pending = spiritDiceQueuedAmountV175(roundId,houseMode,draft.stakeType,button.dataset.diceChoice);
      button.classList.toggle('queued',pending>0);
      const node = button.querySelector('[data-dice-pending]');
      if (node) node.textContent = pending > 0 ? `待提交 +${formatNumber(pending)}` : '';
    });
    const status = document.getElementById('diceBetStatus');
    if (!status) return;
    const clicks = spiritDiceQueuedClicksV175();
    if (clicks > 0) {
      status.textContent = `已合并 ${formatNumber(clicks)} 次点击，本批只提交一次事务；本局累计不得超过首次落注时资源30%。`;
      status.classList.add('is-queueing');
    } else {
      status.classList.remove('is-queueing');
      if (message) status.textContent = message;
      else if (state.spiritDiceLastBetMessage) status.textContent = state.spiritDiceLastBetMessage;
    }
  }

  function scheduleSpiritDiceQueueV175() {
    if (state.spiritDiceBetProcessing || state.spiritDiceBetFlushTimer) return;
    state.spiritDiceBetFlushTimer = setTimeout(() => {
      state.spiritDiceBetFlushTimer = null;
      processSpiritDiceQueueV175();
    },120);
  }

  function enqueueSpiritDiceBetV175(stakeType, choiceCode, amount) {
    const round = state.spiritDiceState?.round || {};
    const roundId = round.id || '';
    const houseMode = round.dealer_character_id ? 'player' : 'system';
    if (!roundId || round.phase !== 'betting') return showToast('本局已封盘，请等待下一局。','error');
    if (!Number.isSafeInteger(Number(amount)) || Number(amount)<1) return showToast('请输入有效的下注数量。','error');
    if (round.dealer_character_id && Number(amount)%80!==0) return showToast('玩家庄与联合庄下注必须为80灵石的整数倍。','error');
    const queue = spiritDiceQueueV175();
    const character = state.spiritDiceState?.character || state.marketSystem?.character || {};
    const available = stakeType === 'cultivation' ? Number(character.cultivation_available||0) : Number(character.spirit_stones||0);
    const accepted = (state.spiritDiceState?.my_bets||[]).filter(item=>item.stake_type===stakeType).reduce((sum,item)=>sum+Number(item.stake_amount||0),0);
    // 与服务端“首次落注前可用资源×30%”一致：当前余额已扣掉accepted，因此加回已接受下注。
    const maximum = Math.max(0,Math.floor((available+accepted)*0.30));
    const queued = queue.filter(item=>item.roundId===roundId&&item.stakeType===stakeType).reduce((sum,item)=>sum+Number(item.amount||0),0);
    if (accepted+queued+Number(amount)>maximum) return showToast(`本局累计下注不得超过首次落注时可用${stakeType==='cultivation'?'修为':'灵石'}的30%（约${formatNumber(maximum)}）。`,'error');
    const key = spiritDiceQueueKeyV175(roundId,houseMode,stakeType,choiceCode);
    const existing = queue.find(item=>item.key===key&&!item.processing);
    if (existing) {
      const next = Number(existing.amount||0)+Number(amount);
      if (!Number.isSafeInteger(next)||next>9007199254740991) return showToast('连续下注金额过大，请稍后再试。','error');
      existing.amount=next; existing.clickCount=Number(existing.clickCount||0)+1;
    } else {
      queue.push({key,roundId,houseMode,stakeType,choiceCode,amount:Number(amount),clickCount:1,processing:false});
    }
    state.spiritDiceLastBetMessage = `已点${spiritDiceTargetMetaV175(choiceCode)[1]} +${formatNumber(amount)} ${stakeType==='cultivation'?'修为':'灵石'}；等待120ms合并本批点击。`;
    updateSpiritDiceQueueFeedbackV175();
    scheduleSpiritDiceQueueV175();
    return true;
  }

  function applySpiritDiceBatchPayloadV175(payload) {
    if (!payload || !payload.batch_only) {
      if (payload) { payload.client_fetched_at = Date.now(); state.spiritDiceState = payload; }
      return;
    }
    const current = state.spiritDiceState;
    if (!current?.round || String(current.round.id || '') !== String(payload.round_id || '')) {
      setTimeout(() => refreshSpiritDiceStateV175(true), 0);
      return;
    }
    current.server_now = payload.server_now || current.server_now;
    current.client_fetched_at = Date.now();
    current.character = { ...(current.character || {}), ...(payload.character || {}) };
    Object.assign(current.round, payload.round_patch || {});
    if (!Array.isArray(current.my_bets)) current.my_bets = [];
    if (!Array.isArray(current.round_totals)) current.round_totals = [];
    const accepted = Array.isArray(payload.accepted_bets) ? payload.accepted_bets : [];
    accepted.forEach(row => {
      const item = { ...row, stake_amount: Number(row.stake_amount || 0), net_profit: 0, result_count: null, is_settled: false };
      current.my_bets.push(item);
      const total = current.round_totals.find(x => x.stake_type === item.stake_type && x.choice_code === item.choice_code);
      if (total) total.stake_amount = Number(total.stake_amount || 0) + item.stake_amount;
      else current.round_totals.push({ stake_type: item.stake_type, choice_code: item.choice_code, stake_amount: item.stake_amount });
    });
    if (payload.character && state.marketSystem?.character) {
      state.marketSystem.character.spirit_stones = Number(payload.character.spirit_stones || 0);
      state.marketSystem.character.cultivation_available = Number(payload.character.cultivation_available || 0);
      setLocalSpiritStoneBalance(Number(payload.character.spirit_stones || 0));
    }
  }

  // V1.7.6 CACHE55：下注成功只补丁当前九门数字与余额，不再 replaceWith 整块灵骰DOM。
  function patchSpiritDiceBetDomV176() {
    const root = document.getElementById('spiritDiceRoot');
    const payload = state.spiritDiceState;
    if (!root || !payload?.round) return;
    const draft = spiritDiceDraftV175();
    const myBets = Array.isArray(payload.my_bets) ? payload.my_bets : [];
    const totals = Array.isArray(payload.round_totals) ? payload.round_totals : [];
    root.querySelectorAll('[data-dice-choice]').forEach(button => {
      const code = button.dataset.diceChoice || '';
      const meta = button.querySelector('.fish-target-meta');
      const bet = spiritDiceBetLookupV175(myBets, draft.stakeType, code);
      const mine = Number(bet?.stake_amount || 0);
      const total = spiritDiceRoundTotalV175(totals, draft.stakeType, code);
      if (meta) {
        const values = meta.querySelectorAll('b');
        if (values[0]) values[0].textContent = formatNumber(mine);
        if (values[1]) values[1].textContent = formatNumber(total);
      }
      button.dataset.diceHasBet = spiritDiceHasAcceptedBetV175(payload.round.id, code) ? '1' : '0';
    });
    root.querySelectorAll('[data-spirit-stone-balance]').forEach(node => {
      node.textContent = formatNumber(payload.character?.spirit_stones || 0);
    });
    updateSpiritDiceQueueFeedbackV175(state.spiritDiceLastBetMessage);
    updateSpiritDiceClockV175();
  }

  async function processSpiritDiceQueueV175() {
    if (state.spiritDiceBetProcessing) return;
    const queue = spiritDiceQueueV175();
    if (!queue.length) return;
    state.spiritDiceBetProcessing = true;
    try {
      const first = queue[0];
      const batch = queue.filter(item=>item.roundId===first.roundId&&item.stakeType===first.stakeType&&!item.processing).slice(0,9);
      batch.forEach(item=>{item.processing=true;});
      try {
        const payload = await rpcPlaceSpiritDiceBetsV175(first.stakeType,batch.map(item=>({choice_code:item.choiceCode,stake_amount:Number(item.amount)})));
        state.spiritDiceBetQueue = queue.filter(item=>!batch.includes(item));
        applySpiritDiceBatchPayloadV175(payload);
        const clicks=batch.reduce((sum,item)=>sum+Number(item.clickCount||0),0);
        const amount=batch.reduce((sum,item)=>sum+Number(item.amount||0),0);
        state.spiritDiceLastBetMessage=`本批${formatNumber(clicks)}次点击已用1次事务提交，共 ${formatNumber(amount)} ${first.stakeType==='cultivation'?'修为':'灵石'}。`;
      } catch(error) {
        state.spiritDiceBetQueue = queue.filter(item=>!batch.includes(item));
        const message=translateError(error); state.spiritDiceLastBetMessage=`本批落注失败：${message}`; showToast(message,'error');
        if (String(error?.message||error).includes('DICE_BETTING_CLOSED')) state.spiritDiceBetQueue=state.spiritDiceBetQueue.filter(item=>item.roundId!==first.roundId);
      }
      patchSpiritDiceBetDomV176();
      if (!state.spiritDiceTimer) startSpiritDiceTimerV175();
    } finally {
      state.spiritDiceBetProcessing=false;
      // 批量下注RPC已返回最新可用余额，避免每批再追加两次余额/修为请求。
      if (spiritDiceQueueV175().length) scheduleSpiritDiceQueueV175();
    }
  }

  function spiritDicePhaseTextV175(phase) {
    if (phase==='betting') return ['下注中','开放下注'];
    if (phase==='locked') return ['已封盘','等待开骰'];
    if (phase==='revealing') return ['开骰','三骰停定'];
    if (phase==='settled') return ['已结算','准备下一局'];
    return ['换局','同步下一局'];
  }

  function spiritDiceBetLookupV175(list, stakeType, choiceCode) {
    const rows=(list||[]).filter(item=>item.stake_type===stakeType&&item.choice_code===choiceCode);
    if(!rows.length) return null;
    return rows.reduce((acc,item)=>({
      ...acc,
      stake_amount:Number(acc.stake_amount||0)+Number(item.stake_amount||0),
      net_profit:Number(acc.net_profit||0)+Number(item.net_profit||0),
      bet_count:Number(acc.bet_count||0)+Number(item.bet_count||0)
    }),{...rows[0],stake_amount:0,net_profit:0,bet_count:0});
  }
  function spiritDiceRoundTotalV175(list, stakeType, choiceCode) {
    return Number((list||[]).filter(item=>item.stake_type===stakeType&&item.choice_code===choiceCode).reduce((sum,item)=>sum+Number(item.stake_amount||0),0));
  }
  function spiritDiceGlyphV175(value) {
    return `<span class="spirit-dice-pip" aria-hidden="true">${escapeHtml(value || '灵')}</span>`;
  }
  function spiritDiceHistoryHtmlV175(history=[]) {
    if (!history.length) return '<div class="empty-state">尚无灵骰公共轮次记录。</div>';
    return history.map(item=>{
      const results=Array.isArray(item.results)?item.results:[];
      const items=Array.isArray(item.items)?item.items:[];
      const detail=items.length?items.map(row=>{const net=Number(row.net_profit||0);return `${spiritDiceTargetMetaV175(row.choice_code)[1]} ${formatNumber(row.stake_amount||0)}，${net>=0?'赢':'输'} ${formatNumber(Math.abs(net))}`;}).join(' · '):'本局未下注';
      const dealer=item.dealer_mode==='joint'?`${item.dealer_name||'玩家庄'}·荷老联庄`:item.dealer_mode==='system_takeover'?'荷老接管':(item.dealer_name||'荷老');
      return `<article class="fish-history-row"><b>${String(item.round_no||'').slice(-6)}</b><div><div class="fish-history-dice">${results.map(v=>`<span>${spiritDiceGlyphV175(v)}</span>`).join('')}</div><small>${escapeHtml(dealer)} · ${escapeHtml(detail)}</small></div></article>`;
    }).join('');
  }

  function spiritDicePanelHtmlV175(data={}) {
    const payload=state.spiritDiceState||{};
    const round=payload.round||{};
    const character=payload.character||data.character||{};
    const draft=spiritDiceDraftV175();
    const playerBacked=Boolean(round.dealer_character_id);
    if (playerBacked&&draft.stakeType==='cultivation') draft.stakeType='spirit_stone';
    const dealerMode=round.dealer_mode||(playerBacked?'player':'system');
    const dealerLabel=dealerMode==='joint'?`${round.dealer_name||'玩家庄'} · 荷老联庄`:dealerMode==='system_takeover'?'荷老接管':playerBacked?(round.dealer_name||'玩家庄'):'荷老';
    const dealerTag=dealerMode==='joint'?'50/50联合庄':dealerMode==='system_takeover'?'风险接管':playerBacked?'玩家庄':'系统庄';
    const unit=draft.stakeType==='cultivation'?'修为':'灵石';
    const amount=spiritDiceBetAmountV175();
    const phaseInfo=spiritDicePhaseTextV175(round.phase);
    const results=Array.isArray(round.results)?round.results:[];
    const elapsed=Number(round.elapsed_seconds||0);
    const open=round.phase==='betting';
    const myBets=Array.isArray(payload.my_bets)?payload.my_bets:[];
    const totals=Array.isArray(payload.round_totals)?payload.round_totals:[];
    const history=Array.isArray(payload.history)?payload.history:[];
    const houseMode=playerBacked?'player':'system';
    const diceHtml=[0,1,2].map(index=>{
      const visible=results[index]&&elapsed>=8+index*0.28;
      return `<div class="fish-die spirit-die ${open?'':visible?'stopped':'rolling'}" data-dice-die-index="${index}" data-result-value="${escapeHtml(results[index]||'')}"><div>${visible?spiritDiceGlyphV175(results[index]):'<span class="fish-die-idle">骰</span>'}</div></div>`;
    }).join('');
    const targets=SPIRIT_DICE_TARGETS_V175.map(([code,name,note])=>{
      const bet=spiritDiceBetLookupV175(myBets,draft.stakeType,code);
      const myAmount=Number(bet?.stake_amount||0);
      const total=spiritDiceRoundTotalV175(totals,draft.stakeType,code);
      const pending=spiritDiceQueuedAmountV175(round.id,houseMode,draft.stakeType,code);
      const hasAcceptedBet=spiritDiceHasAcceptedBetV175(round.id,code);
      const hit=Boolean(
        hasAcceptedBet &&
        results.length===3 &&
        (round.is_settled || round.phase==='settled') &&
        spiritDiceChoiceHitV175(results,code)
      );
      return `<button type="button" class="fish-target-card dice-target-card ${hit?'win dice-win-glow':''} ${pending>0?'queued':''}" data-dice-choice="${code}" data-dice-has-bet="${hasAcceptedBet?'1':'0'}" ${open?'':'disabled'}><div class="fish-target-head"><span class="dice-choice-seal">${code.startsWith('face')?name:(code==='triple'?'豹':name)}</span><div><strong>${name}</strong><small>${note}</small></div></div><div class="fish-target-meta"><span>我的下注 <b>${formatNumber(myAmount)}</b></span><span>全场总额 <b>${formatNumber(total)}</b></span></div><em class="fish-target-pending" data-dice-pending>${pending>0?`待提交 +${formatNumber(pending)}`:''}</em></button>`;
    }).join('');
    const latest=history.find(item=>item?.has_bets)||null;
    const latestDetail=latest?`<div class="fish-latest-result"><div class="fish-result-title">第${escapeHtml(latest.round_no)}局 · 开出 ${(latest.results||[]).join('、')}</div>${(latest.items||[]).map(row=>{const net=Number(row.net_profit||0);return `<div class="fish-settlement-line"><span>${escapeHtml(spiritDiceTargetMetaV175(row.choice_code)[1])}：${formatNumber(row.stake_amount||0)} ${row.stake_type==='cultivation'?'修为':'灵石'}</span><b class="${net>=0?'positive':'negative'}">${net>=0?'赢':'输'} ${formatNumber(Math.abs(net))}</b></div>`;}).join('')}</div>`:'<div class="empty-state">尚无个人结算明细。</div>';
    return `<section id="spiritDiceRoot" class="fish-game-shell spirit-dice-shell" data-round-id="${escapeHtml(round.id||'')}">
      <div class="fish-compact-top"><div class="fish-title-row"><div><strong>灵骰问道</strong><small>10秒公共牌桌 · 一庄多闲 · 九门同押</small></div><span id="dicePhaseBadge">${phaseInfo[0]}</span></div><div class="fish-balance-grid"><div><span>可用灵石</span><b data-spirit-stone-balance>${formatNumber(character.spirit_stones||0)}</b></div><div><span>可用修为</span><b>${formatNumber(character.cultivation_available||0)}</b></div></div></div>
      <div class="fish-compact-block fish-time-block"><div><strong>本局10秒</strong><small id="dicePhaseText">${phaseInfo[1]}</small></div><b id="diceCountdown">${formatNumber(round.seconds_remaining||0)}秒</b><div class="fish-progress"><i id="diceProgressFill" style="width:${Math.max(0,Math.min(100,elapsed/10*100))}%"></i></div></div>
      <div class="fish-compact-block fish-dealer-block"><div><span>当前庄家 · ${dealerTag}</span><b>${escapeHtml(dealerLabel)}</b></div><div class="fish-dealer-switch single"><button type="button" class="active" disabled>${escapeHtml(dealerTag)}</button></div></div>
      <div class="fish-compact-block fish-settings-block"><div class="fish-settings-title"><strong>押注设置</strong><span id="diceQuickPreview">${unit} · ${formatNumber(draft.quantity)} × ${draft.multiplier}</span></div><div class="fish-resource-switch"><button type="button" data-dice-stake-type="spirit_stone" class="${draft.stakeType==='spirit_stone'?'active':''}">灵石</button><button type="button" data-dice-stake-type="cultivation" class="${draft.stakeType==='cultivation'?'active':''}" ${playerBacked?'disabled title="本轮由玩家庄参与，只接受灵石"':''}>修为</button></div><div class="fish-setting-row"><label>数量<input id="diceStakeQuantity" type="number" min="${playerBacked?80:1}" step="${playerBacked?80:1}" inputmode="numeric" value="${escapeHtml(draft.quantity)}"></label><div><span>倍率</span><div class="fish-multiplier-grid">${[1,10,100].map(m=>`<button type="button" data-dice-multiplier="${m}" class="${draft.multiplier===m?'active':''}">${m}倍</button>`).join('')}</div></div></div><div class="fish-bet-preview" id="diceBetPreview">本次下注：<b>${formatNumber(amount)} ${unit}</b></div></div>
      <div class="fish-draw-block"><div class="fish-section-head"><div><strong>三骰公共开奖</strong><small>第0～7秒下注 · 7～8秒封盘 · 8～9秒开奖 · 9～10秒结算</small></div><span>${round.round_no?`第${escapeHtml(round.round_no)}局`:'同步中'}</span></div><div class="fish-orbit"><div class="fish-dice-row">${diceHtml}</div></div><small class="fish-draw-note">同一轮只生成一次结果，所有闲家共用；倒计时只在本机更新，不每秒请求数据库。</small></div>
      <div class="fish-target-block"><div class="fish-section-head"><div><strong>选择下注</strong><small>大 / 小 / 豹子 / 1～6，可多门同押；120ms点击合并</small></div><button type="button" class="ghost-btn fish-refresh-btn" data-dice-refresh>刷新</button></div><div class="fish-target-grid dice-target-grid">${targets}</div><div class="fish-bet-status" id="diceBetStatus">${open?'开放下注；本局累计下注不得超过首次落注时资源的30%。':'本局已封盘，等待开奖与结算。'}</div></div>
      <div class="fish-history-block"><div class="fish-section-head"><div><strong>最近20局</strong><small>固定20局，长时间多人运行不累积页面节点</small></div></div><div class="fish-history-list">${spiritDiceHistoryHtmlV175(history)}</div></div>
      <div class="fish-detail-block"><div class="fish-section-head"><div><strong>结算明细</strong><small>本人的最近有效下注结果</small></div></div>${latestDetail}</div>
      <details class="fish-rules-block"><summary>规则</summary><p>灵骰问道改为公共10秒轮次：一名庄家对多名闲家，所有玩家共用同一组三骰。大为非豹子总点11～17，小为非豹子总点4～10；任意豹子独立命中并通杀大、小；数字1～6按该数字实际出现1、2、3枚分别结算。</p><p>荷老系统庄：大/小每100净赢95；数字命中1/2/3枚每100净赢95/190/285；任意豹子每100净赢3325，本金另返。玩家庄采用对称100:97.5和80灵石步进；触发联合庄后本轮风险与庄家净收益各50%，下一轮玩家自动下庄并冷却30分钟。</p></details>
    </section>`;
  }

  function renderSpiritDicePanelV175() {
    const current=document.getElementById('spiritDiceRoot');
    if (!current) return;
    const wrapper=document.createElement('div'); wrapper.innerHTML=spiritDicePanelHtmlV175(state.marketSystem||{}); const next=wrapper.firstElementChild; if (!next) return;
    current.replaceWith(next); bindMarketActions(); updateSpiritDiceClockV175();
  }

  function mergeSpiritDiceHistoryV176(previous = [], incoming = []) {
    const map = new Map();
    [...(Array.isArray(incoming) ? incoming : []), ...(Array.isArray(previous) ? previous : [])].forEach(item => {
      const key = String(item?.round_no ?? '');
      if (key && !map.has(key)) map.set(key, item);
    });
    return [...map.values()].sort((a,b)=>Number(b?.round_no||0)-Number(a?.round_no||0)).slice(0,20);
  }

  async function refreshSpiritDiceStateV175(silent=false, historyLimit=20, mergeHistory=false) {
    if (state.spiritDiceSyncing||state.spiritDiceBetProcessing||!state.character||document.hidden) return state.spiritDiceState;
    state.spiritDiceSyncing=true;
    try {
      const previousHistory = Array.isArray(state.spiritDiceState?.history) ? state.spiritDiceState.history : [];
      const payload=await rpcGetSpiritDiceStateV175(historyLimit);
      if (payload) {
        if (mergeHistory && previousHistory.length) payload.history = mergeSpiritDiceHistoryV176(previousHistory, payload.history);
        payload.client_fetched_at=Date.now(); state.spiritDiceState=payload;
        if (Number(historyLimit) >= 20) state.spiritDiceLastFullHistoryAt = Date.now();
        const activeRoundId=String(payload.round?.id||'');
        if (activeRoundId) {
          const localBucket=state.spiritDiceAcceptedBetRounds?.[activeRoundId]||{};
          state.spiritDiceAcceptedBetRounds={ [activeRoundId]: localBucket };
          spiritDiceRememberAcceptedBetsV175(activeRoundId,payload.my_bets||[]);
        }
        if (payload.character&&state.marketSystem?.character) {
          state.marketSystem.character.spirit_stones=Number(payload.character.spirit_stones||0);
          state.marketSystem.character.cultivation_available=Number(payload.character.cultivation_available||0);
          setLocalSpiritStoneBalance(Number(payload.character.spirit_stones||0));
        }
      }
      renderSpiritDicePanelV175(); startSpiritDiceTimerV175(); return state.spiritDiceState;
    } catch(error) { if (!silent) showToast(translateError(error),'error'); return state.spiritDiceState; }
    finally { state.spiritDiceSyncing=false; }
  }

  function stopSpiritDiceTimerV175() {
    if (state.spiritDiceTimer) clearTimeout(state.spiritDiceTimer);
    if (state.spiritDiceBoundaryRefreshTimer) clearTimeout(state.spiritDiceBoundaryRefreshTimer);
    state.spiritDiceTimer=null; state.spiritDiceBoundaryRefreshTimer=null; state.spiritDiceRefreshGuard=false;
  }
  function scheduleSpiritDiceClockV176(delay=500) {
    if (state.spiritDiceTimer) clearTimeout(state.spiritDiceTimer);
    state.spiritDiceTimer=setTimeout(() => {
      state.spiritDiceTimer=null;
      updateSpiritDiceClockV175();
      const round=state.spiritDiceState?.round;
      if (!document.getElementById('spiritDiceRoot') || !round) return;
      const fetchedAt=Number(state.spiritDiceState?.client_fetched_at||Date.now());
      const serverBase=Date.parse(state.spiritDiceState?.server_now||'')||Date.now();
      const now=serverBase+(Date.now()-fetchedAt);
      const reveal=Date.parse(round.reveal_at||'')||0;
      const settle=Date.parse(round.settles_at||'')||0;
      // 只有约1秒开骰动画窗口提高到160ms，其余时间500ms即可满足秒级倒计时。
      const nextDelay = reveal && settle && now>=reveal-180 && now<settle+120 ? 160 : 500;
      scheduleSpiritDiceClockV176(nextDelay);
    }, Math.max(80,Number(delay)||500));
  }
  function startSpiritDiceTimerV175() {
    stopSpiritDiceTimerV175(); if (!document.getElementById('spiritDiceRoot')) return;
    updateSpiritDiceClockV175(); scheduleSpiritDiceClockV176(500);
  }
  function updateSpiritDiceClockV175() {
    const root=document.getElementById('spiritDiceRoot'); const payload=state.spiritDiceState; const round=payload?.round; if (!root||!round) return;
    const fetchedAt=Number(payload.client_fetched_at||Date.now()); const serverBase=Date.parse(payload.server_now||'')||Date.now(); const now=serverBase+(Date.now()-fetchedAt);
    const start=Date.parse(round.starts_at||'')||now; const close=Date.parse(round.betting_closes_at||'')||start+7000; const reveal=Date.parse(round.reveal_at||'')||start+8000; const settle=Date.parse(round.settles_at||'')||start+9000; const end=Date.parse(round.ends_at||'')||start+10000;
    const elapsed=Math.max(0,(now-start)/1000); let phase='betting',phaseEnd=close;
    if(now>=close&&now<reveal){phase='locked';phaseEnd=reveal;}else if(now>=reveal&&now<settle){phase='revealing';phaseEnd=settle;}else if(now>=settle&&now<end){phase='settled';phaseEnd=end;}else if(now>=end){phase='next';phaseEnd=end;}
    const info=spiritDicePhaseTextV175(phase); const countdown=Math.max(0,Math.ceil((phaseEnd-now)/1000));
    const badge=document.getElementById('dicePhaseBadge'); const text=document.getElementById('dicePhaseText'); const count=document.getElementById('diceCountdown'); const progress=document.getElementById('diceProgressFill');
    if(badge)badge.textContent=info[0]; if(text)text.textContent=info[1]; if(count)count.textContent=`${countdown}秒`; if(progress)progress.style.width=`${Math.max(0,Math.min(100,elapsed/10*100))}%`;
    root.querySelectorAll('[data-dice-die-index]').forEach(node=>{const index=Number(node.dataset.diceDieIndex||0);const value=node.dataset.resultValue||'';const visible=value&&elapsed>=8+index*0.28;node.classList.toggle('rolling',phase!=='betting'&&!visible);node.classList.toggle('stopped',Boolean(visible));const inner=node.firstElementChild;if(inner)inner.innerHTML=visible?spiritDiceGlyphV175(value):'<span class="fish-die-idle">骰</span>';});
    // CACHE54：命中边框不再等待服务端 settlement 状态。三颗骰子全部停定后，
    // 直接使用本局已经公开的公共结果 + 本人已接受下注在本机计算命中。
    // 这样不新增任何数据库请求，也不会因为10秒公共桌的 settlement 边界错过发光阶段。
    const revealComplete=Array.isArray(round.results)&&round.results.length===3&&elapsed>=8.56;
    root.querySelectorAll('[data-dice-choice]').forEach(button=>{
      button.disabled=phase!=='betting';
      const choiceCode=button.dataset.diceChoice||'';
      const hasBet=spiritDiceHasAcceptedBetV175(round.id,choiceCode);
      const shouldGlow=Boolean(revealComplete&&hasBet&&spiritDiceChoiceHitV175(round.results,choiceCode));
      button.dataset.diceHasBet=hasBet?'1':'0';
      button.classList.toggle('win',shouldGlow);
      button.classList.toggle('dice-win-glow',shouldGlow);
      button.setAttribute('aria-current',shouldGlow?'true':'false');
    });
    // 10秒公共桌每轮最多在开奖边界与下一轮边界各取一次权威状态，不做逐秒/结算阶段轮询。
    const needsRefresh=phase==='next'||(phase==='revealing'&&(!Array.isArray(round.results)||!round.results.length));
    if(needsRefresh&&!state.spiritDiceRefreshGuard&&!state.spiritDiceSyncing&&!state.spiritDiceBoundaryRefreshTimer){
      state.spiritDiceRefreshGuard=true;
      // CACHE55：120～620ms错峰，并且边界只取1条历史；首次进入才读取完整20局。
      const jitter=120+Math.floor(Math.random()*501);
      state.spiritDiceBoundaryRefreshTimer=setTimeout(()=>{
        state.spiritDiceBoundaryRefreshTimer=null;
        refreshSpiritDiceStateV175(true,state.spiritDiceBoundaryHistoryLimit||1,true).finally(()=>{state.spiritDiceRefreshGuard=false;});
      },jitter);
    }
  }

  function afterCasinoRenderV0148() {
    const draft = getCasinoDraft('house', state.marketSystem || {});
    const houseActive = state.casinoView === 'house';
    const fishActive = houseActive && draft.game === 'fish_shrimp';
    const diceActive = houseActive && draft.game === 'spirit_dice';

    if (!fishActive) stopFishShrimpTimerV0148();
    else {
      startFishShrimpTimerV0148();
      if (!state.fishShrimpState && !state.fishShrimpSyncing) setTimeout(() => refreshFishShrimpStateV0148(true), 0);
    }

    if (!diceActive) stopSpiritDiceTimerV175();
    else {
      startSpiritDiceTimerV175();
      if (!state.spiritDiceState && !state.spiritDiceSyncing) setTimeout(() => refreshSpiritDiceStateV175(true), 0);
    }
  }

  function marketPanelHtml(data = {}, view = 'lobby') {
    const safeView = ['lobby', 'house', 'duel', 'pools'].includes(view) ? view : 'lobby';
    const pools = data.pools || {};
    const tickets = data.tickets || {};
    const character = data.character || {};
    const activity = data.activity || {};
    const settings = data.settings || {};
    const draws = Array.isArray(data.latest_draws) ? data.latest_draws : [];
    const hitChance = Number(settings.pool_hit_chance ?? 1);
    const casinoPeriod = data.casino_period || {};
    const bankrolls = data.bankrolls || {};
    const periodClosed = casinoPeriod.betting_open === false;
    const disabled = data.status !== 'active' || periodClosed;
    const playerHouse = data.player_house || {};
    const playerDealerActive = playerHouse.mode === 'player';
    if (!playerDealerActive && state.casinoHouseMode === 'player') state.casinoHouseMode = 'system';
    const selectedPlayerHouse = playerDealerActive;
    const houseDealerName = selectedPlayerHouse ? (playerHouse.dealer_name || '无名庄家') : '荷老';
    const error = data.error ? `<div class="market-lore"><p><b>赌坊数据暂不可用：</b>${escapeHtml(data.error)}</p></div>` : '';
    const stoneBankroll = bankrolls.spirit_stone || {};
    const cultivationBankroll = bankrolls.cultivation || {};
    const periodNotice = `<div class="market-lore"><p><b>本期赌场：</b>${periodClosed ? '开奖前一分钟封盘清算中' : `距离封盘 ${formatDuration(casinoPeriod.seconds_to_close || 0)}`}；灵石资金 ${formatNumber(stoneBankroll.balance || 0)} / 1亿，修为资金 ${formatNumber(cultivationBankroll.balance || 0)} / 10亿。</p><p>每两小时独立重置；正利润的50%进入造化池；无正利润不追加，但已有奖池仍照常开奖。获奖者领取70%，至少30%滚存。</p></div>`;
    const fullNotice = character.cultivation_full ? '<div class="market-lore cultivation-full-market"><p><b>当前境界修为已圆满。</b></p><p>仍可押注当前小境界起始线以上的修为；输光后境界保持不变。</p></div>' : '';

    if (safeView === 'house') {
      const draft = getCasinoDraft('house', data);
      const fishSelected = draft.game === 'fish_shrimp';
      const diceSelected = draft.game === 'spirit_dice';
      const selector = `<section class="casino-play-sheet casino-game-selector-v0148"><div class="subsection-title"><strong>选择玩法</strong><span>${diceSelected ? '灵骰10秒公共轮次 · 一庄多闲' : fishSelected ? '鱼虾40秒公共轮次 · 一庄多闲' : '选择玩法'}</span></div><div class="casino-game-buttons"><button class="${diceSelected ? 'active' : ''}" type="button" data-house-select-game="spirit_dice"><b>骰</b><span>灵骰问道</span><small>10秒共开 · 大小豹子 · 1～6</small></button><button type="button" data-paigow-open><b>牌</b><span>九霄灵牌</span><small>牌九 · 大牌九 · 房间对局</small></button><button class="${fishSelected ? 'active' : ''}" type="button" data-house-select-game="fish_shrimp"><b>鱼</b><span>鱼虾灵局</span><small>六门同押 · 三骰公共开盘</small></button></div></section>`;
      const publicRule = playerDealerActive
        ? `当前由${escapeHtml(playerHouse.dealer_name || '玩家庄')}作为公共牌桌唯一庄家，闲家不能另选荷老。玩家庄不足以独立承担新责任但可承担50%时，本轮触发50/50联合庄；触发后下一轮自动下庄并冷却30分钟。`
        : '当前公共牌桌由荷老坐庄；所有闲家在同一轮共享同一份开奖结果。';
      const publicHeader = `${playerHouseControlHtml(data)}${fullNotice}${selector}<div class="market-lore"><p><b>单一庄家规则：</b>${publicRule}</p><p>多人下注采用120毫秒点击合并 + 单批一次数据库事务；倒计时由服务器时间戳在本机计算，不使用1秒数据库轮询。</p></div>`;
      if (fishSelected) {
        return `${error}${periodNotice}${casinoPrimaryNavHtml('house', disabled)}${casinoModeHeader('大堂 · 鱼虾灵局', '40秒公共开盘 · 单一庄家 · 批量下注')}${publicHeader}${fishShrimpPanelHtmlV0148(data)}`;
      }
      return `${error}${periodNotice}${casinoPrimaryNavHtml('house', disabled)}${casinoModeHeader('大堂 · 灵骰问道', '10秒公共开盘 · 一庄多闲 · 九门同押')}${publicHeader}${spiritDicePanelHtmlV175(data)}`;
    }

    if (safeView === 'duel') {
      const draft = getCasinoDraft('duel', data);
      return `${error}${periodNotice}${casinoPrimaryNavHtml('duel', disabled)}${casinoModeHeader('贵宾雅间 · 无相赌契', '有人应局 · 立即开契结算')}${fullNotice}
        <section class="casino-play-sheet">
          <div class="subsection-title"><strong>开设赌桌</strong><span>无人应局可主动取消并原数返还</span></div>
          <div class="casino-form-grid">
            <label>雅间玩法<select id="duelGame"><option value="spirit_fist" ${draft.game === 'spirit_fist' ? 'selected' : ''}>灵拳对弈</option><option value="five_elements" ${draft.game === 'five_elements' ? 'selected' : ''}>五行灵拳</option></select></label>
            <label>暗选招式<select id="duelChoice"></select></label>
          </div>
          ${casinoStakeControlsHtml('duel', data)}
          <div class="casino-confirm-row">
            <button class="primary-btn" type="button" id="createDuelBtn" ${disabled ? 'disabled' : ''}>确认赌注并封招开桌</button>
            <small>双方各押同额赌注；分出胜负后，5%平台费进入赌场资金，不再直接进入奖池。赌场在两小时周期形成正利润后，其中50%统一加入造化池；双方仍按旧规则纳入本期等权候选，同招流局全额返还。</small>
          </div>
        </section>
        ${casinoDuelListsHtml(data)}`;
    }

    if (safeView === 'pools') {
      return `${error}${periodNotice}${casinoPrimaryNavHtml('pools', disabled)}${casinoModeHeader('全服造化池', '每名本期参与者拥有一份候选资格')}
        <div class="casino-pool-grid">
          ${marketPoolCard('灵石造化池', pools.spirit_stone || {}, tickets.spirit_stone || 0, '灵石')}
          ${marketPoolCard('修为造化池', pools.cultivation || {}, tickets.cultivation || 0, '修为')}
        </div>
        <div class="market-lore"><p><b>开奖规则：</b>系统赌场每两小时独立清算一次，开奖前一分钟停止新注。灵石赌场每期固定以1亿开局，修为赌场固定以10亿开局；本期形成正利润时，利润的50%加入对应造化池；亏损或零利润时不追加赌场利润，但已有造化池仍按期照常开奖。玩家庄2.5%平台费与雅间5%平台费先进入赌场资金，再参与周期利润清算。</p><p>奖票沿用旧等权规则：同一角色重复游玩不会叠加抽中权重。获奖者领取开奖前奖池的70%，整数奖励向下取整；至少30%继续滚存。游玩次数不设上限，但同一角色同时只能结算一局。</p></div>
        <div class="subsection-title"><strong>近期造化</strong><span>抽中、领取与留存都会留下记录</span></div>
        ${casinoDrawRowsHtml(draws)}`;
    }

    const lobbyDealerName = playerDealerActive ? (playerHouse.dealer_name || '无名修士') : '荷老';
    const lobbyDealerNote = playerDealerActive ? '玩家庄为公共牌桌唯一庄家；不能另选荷老' : '当前没有玩家庄，由荷老坐庄';
    return `${error}${periodNotice}
      <div class="casino-lobby-summary">
        <div><span>统一灵石</span><strong data-spirit-stone-balance>${formatNumber(character.spirit_stones || 0)}</strong><small>机缘、洞府、功法与赌坊共用</small></div>
        <div><span>当前境界可动用修为</span><strong>${formatNumber(character.cultivation_available || 0)}</strong><small>大堂单局最多30%，雅间沿用既有规则</small></div>
        <div><span>今日参与</span><strong>${formatNumber(activity.total_count || 0)} 局</strong><small>已取消每日次数限制</small></div>
        <div><span>当前庄家</span><strong>${escapeHtml(lobbyDealerName)}</strong><small>${escapeHtml(lobbyDealerNote)}</small></div>
      </div>
      ${casinoPrimaryNavHtml('lobby', disabled)}
      ${selectedPlayerHouse ? '' : fullNotice}
      ${disabled ? '<div class="market-lore"><p><b>万运博弈楼当前暂停接受新赌契。</b>已有赌契仍会正常结算或返还。</p></div>' : ''}
      <div class="casino-mode-grid">
        <button type="button" data-casino-view="house" ${disabled ? 'disabled' : ''}><b>堂</b><strong>大堂</strong><span>${playerDealerActive ? `${escapeHtml(playerHouse.dealer_name || '玩家庄')}独立坐庄；必要时本轮触发荷老50%联庄` : '荷老坐庄；灵骰10秒公共开奖、鱼虾40秒公共开奖'}</span></button>
        <button type="button" data-casino-view="duel"><b>雅</b><strong>贵宾雅间</strong><span>开桌等待应局，有人接受即刻结算</span></button>
        <button type="button" data-casino-view="pools"><b>池</b><strong>全服造化池</strong><span>查看两类共享奖池、造化签和开奖记录</span></button>
        <button type="button" data-casino-dealer-status><b>庄</b><strong>庄家状态</strong><span>查看当前庄家、上庄资格、任期与下庄入口</span></button>
      </div>
      ${playerHouseLobbyCardsHtml(data)}
      <div class="market-lore"><p>市坊西街灯火不息，墨玉匾额上书：<b>一念定盈亏，一签候造化。</b></p><p>统一灵石达到500万即可自愿上庄，每次最多2小时。玩家庄存在时即为公共牌桌唯一庄家，闲家不能另选荷老；单局累计下注最多为首次落注时可用资源的30%。玩家庄采用对称100:97.5；资金不足以独立承保但仍能承担50%时，本轮由玩家庄与荷老50/50联合承担风险和庄家净收益，触发后下一轮玩家自动下庄并冷却30分钟。2.5%平台费始终进入赌场，两小时正利润的50%再统一分配造化池；无正利润时造化池仍照常开奖。</p></div>`;
  }

  function duelChoices(game) {
    return game === 'five_elements'
      ? [['metal','金锐拳'],['wood','青木拳'],['earth','厚土拳'],['water','浪涛拳'],['fire','焚天拳']]
      : [['rock','磐石势'],['scissors','疾风刃'],['paper','流云盾']];
  }

  function casinoStakeBase(stakeType, prefix = '') {
    if (stakeType === 'cultivation') return 50000;
    return prefix === 'house' && state.casinoHouseMode === 'player' ? 200 : 100;
  }

  function updateCasinoStakeControl(prefix) {
    const typeSelect = document.getElementById(`${prefix}StakeType`);
    const amountInput = document.getElementById(`${prefix}StakeAmount`);
    const summary = document.querySelector(`[data-stake-summary="${CSS.escape(prefix)}"]`);
    const hint = document.querySelector(`[data-stake-base-hint="${CSS.escape(prefix)}"]`);
    if (!typeSelect || !amountInput) return;
    const cultivation = typeSelect.value === 'cultivation';
    const base = casinoStakeBase(typeSelect.value, prefix);
    const character = state.marketSystem?.character || {};
    const available = cultivation ? Number(character.cultivation_available || 0) : Number(character.spirit_stones || 0);
    const houseMaximum = Math.max(0, Math.floor(available * 0.30));
    const exactPlayerHouse = prefix === 'house' && state.casinoHouseMode === 'player' && !cultivation;
    const effectiveMaximum = exactPlayerHouse ? Math.floor(houseMaximum / 40) * 40 : houseMaximum;
    amountInput.min = cultivation ? String(Math.min(50000, Math.max(1, prefix === 'house' ? houseMaximum : available))) : (exactPlayerHouse ? '40' : '10');
    if (prefix === 'house') amountInput.max = String(effectiveMaximum);
    else amountInput.removeAttribute('max');
    amountInput.step = exactPlayerHouse ? '40' : '1';
    let value = Math.max(0, Math.floor(Number(amountInput.value || 0)));
    if (exactPlayerHouse && value % 40 !== 0) {
      value = effectiveMaximum >= 200 ? 200 : effectiveMaximum;
      amountInput.value = String(value);
      const draft = getCasinoDraft(prefix);
      draft.amount = value;
      draft.multiplier = null;
      state.casinoDrafts[prefix] = draft;
    }
    const unit = cultivation ? '修为' : '灵石';
    if (hint) hint.textContent = cultivation
      ? (prefix === 'house' ? `通常最低 50,000 修为；单局最多当前可动用修为30%，当前上限 ${formatNumber(houseMaximum)}。` : `通常最低 50,000 修为；不足 50,000 时按雅间既有规则处理。`)
      : (prefix === 'house' ? (exactPlayerHouse
        ? `玩家庄与联合庄为保证100:97.5及50/50精确整数结算，下注须为80灵石整数倍；当前30%上限 ${formatNumber(effectiveMaximum)}。`
        : `单局最多当前可用灵石30%，当前上限 ${formatNumber(houseMaximum)}。`) : `以 ${formatNumber(base)} ${unit}为基数，也可在下方直接填写任意整数。`);
    if (summary) summary.textContent = `本局确定下注：${formatNumber(value)} ${unit}`;
  }

  function readCasinoStake(prefix) {
    const typeSelect = document.getElementById(`${prefix}StakeType`);
    const amountInput = document.getElementById(`${prefix}StakeAmount`);
    const stakeType = typeSelect?.value || 'spirit_stone';
    const amount = Math.floor(Number(amountInput?.value || 0));
    const character = state.marketSystem?.character || {};
    const available = stakeType === 'cultivation' ? Number(character.cultivation_available || 0) : Number(character.spirit_stones || 0);
    const maximum = prefix === 'house' ? Math.max(0, Math.floor(available * 0.30)) : available;
    const exactPlayerHouse = prefix === 'house' && state.casinoHouseMode === 'player' && stakeType === 'spirit_stone';
    const minimum = stakeType === 'cultivation' ? Math.min(50000, Math.max(1, prefix === 'house' ? maximum : available)) : (exactPlayerHouse ? 40 : 10);
    if (!Number.isSafeInteger(amount) || amount < minimum) {
      throw new Error(stakeType === 'cultivation' ? 'CULTIVATION_STAKE_MINIMUM' : 'CASINO_STAKE_BELOW_MINIMUM');
    }
    if (exactPlayerHouse && amount % 40 !== 0) throw new Error('CASINO_PLAYER_HOUSE_STAKE_MULTIPLE_40');
    if (amount > available) {
      throw new Error(stakeType === 'cultivation' ? 'CASINO_INSUFFICIENT_CULTIVATION' : 'CASINO_INSUFFICIENT_SPIRIT_STONES');
    }
    if (prefix === 'house' && amount > maximum) throw new Error('CASINO_STAKE_EXCEEDS_THIRTY_PERCENT');
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

    document.querySelectorAll('[data-casino-dealer-status]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        document.getElementById('casinoDealerStatus')?.scrollIntoView({ behavior: 'smooth', block: 'start' });
      });
    });

    document.querySelectorAll('[data-house-mode]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        state.casinoHouseMode = button.dataset.houseMode === 'player' ? 'player' : 'system';
        renderCasinoPanel();
      });
    });

    document.querySelectorAll('[data-player-house-toggle]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        const active = button.dataset.playerHouseToggle === 'on';
        setBusy(button, true, active ? '上庄中……' : '下庄中……');
        try {
          const result = await rpcSetCasinoPlayerHouseV1(active);
          showToast(active
            ? `你已自愿上庄，当前大堂庄家为【${result?.dealer_name || '你'}】。`
            : '你已主动下庄，荷老重新接管大堂。', 'success');
          await Promise.all([refreshMarketSystem(true), refreshSpiritStoneBalanceV0141(true)]);
        } catch (error) {
          showToast(translateError(error), 'error');
        } finally {
          setBusy(button, false);
        }
      });
    });

    document.querySelectorAll('[data-cultivation-all-in]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        const prefix = button.dataset.cultivationAllIn;
        const typeSelect = document.getElementById(`${prefix}StakeType`);
        const amountInput = document.getElementById(`${prefix}StakeAmount`);
        const available = Math.max(0, Math.floor(Number(state.marketSystem?.character?.cultivation_available || 0)));
        if (!typeSelect || !amountInput || available <= 0) return;
        typeSelect.value = 'cultivation';
        amountInput.value = String(available);
        const draft = getCasinoDraft(prefix);
        draft.stakeType = 'cultivation';
        draft.amount = available;
        draft.multiplier = null;
        state.casinoDrafts[prefix] = draft;
        document.querySelectorAll(`[data-stake-prefix="${CSS.escape(prefix)}"]`).forEach(node => node.classList.remove('active'));
        updateCasinoStakeControl(prefix);
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
          draft.amount = casinoStakeBase(draft.stakeType, prefix);
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
        draft.amount = casinoStakeBase(draft.stakeType, prefix) * multiplier;
        state.casinoDrafts[prefix] = draft;
        amountInput.value = String(draft.amount);
        document.querySelectorAll(`[data-stake-prefix="${CSS.escape(prefix)}"]`).forEach(node => node.classList.toggle('active', node === button));
        updateCasinoStakeControl(prefix);
      });
    });


    document.querySelectorAll('[data-dice-stake-type]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        if (button.disabled) return;
        const draft = captureSpiritDiceDraftV175();
        draft.stakeType = button.dataset.diceStakeType === 'cultivation' ? 'cultivation' : 'spirit_stone';
        state.spiritDiceDraft = draft;
        renderSpiritDicePanelV175();
      });
    });

    document.querySelectorAll('[data-dice-multiplier]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        const draft = captureSpiritDiceDraftV175();
        draft.multiplier = [1,10,100].includes(Number(button.dataset.diceMultiplier)) ? Number(button.dataset.diceMultiplier) : 1;
        state.spiritDiceDraft = draft;
        renderSpiritDicePanelV175();
      });
    });

    const diceQuantity = document.getElementById('diceStakeQuantity');
    if (diceQuantity && diceQuantity.dataset.bound !== '1') {
      diceQuantity.dataset.bound = '1';
      diceQuantity.addEventListener('input', () => {
        const draft = spiritDiceDraftV175();
        draft.quantity = Math.max(1,Math.floor(Number(diceQuantity.value || 1)));
        state.spiritDiceDraft = draft;
        const unit = draft.stakeType === 'cultivation' ? '修为' : '灵石';
        const amount = spiritDiceBetAmountV175();
        const preview = document.getElementById('diceBetPreview');
        const quick = document.getElementById('diceQuickPreview');
        if (preview) preview.innerHTML = `本次下注：<b>${formatNumber(amount)} ${unit}</b>`;
        if (quick) quick.textContent = `${unit} · ${formatNumber(draft.quantity)} × ${draft.multiplier}`;
      });
    }

    document.querySelectorAll('[data-dice-choice]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        if (button.disabled) return;
        const draft = captureSpiritDiceDraftV175();
        const amount = spiritDiceBetAmountV175();
        if (!amount) return showToast('请输入有效的下注数量。','error');
        enqueueSpiritDiceBetV175(draft.stakeType,button.dataset.diceChoice,amount);
      });
    });

    document.querySelectorAll('[data-dice-refresh]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        setBusy(button,true,'刷新中…');
        await refreshSpiritDiceStateV175(false);
        setBusy(button,false);
      });
    });

    document.querySelectorAll('[data-fish-stake-type]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        if (button.disabled) return;
        const draft = captureFishShrimpDraftV0148();
        draft.stakeType = button.dataset.fishStakeType === 'cultivation' ? 'cultivation' : 'spirit_stone';
        state.fishShrimpDraft = draft;
        renderFishShrimpPanelV0148();
      });
    });

    document.querySelectorAll('[data-fish-multiplier]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        const draft = captureFishShrimpDraftV0148();
        draft.multiplier = [1,10,100].includes(Number(button.dataset.fishMultiplier)) ? Number(button.dataset.fishMultiplier) : 1;
        state.fishShrimpDraft = draft;
        renderFishShrimpPanelV0148();
      });
    });

    const fishQuantity = document.getElementById('fishStakeQuantity');
    if (fishQuantity && fishQuantity.dataset.bound !== '1') {
      fishQuantity.dataset.bound = '1';
      fishQuantity.addEventListener('input', () => {
        const draft = fishShrimpDraftV0148();
        draft.quantity = Math.max(1,Math.floor(Number(fishQuantity.value || 1)));
        state.fishShrimpDraft = draft;
        const unit = draft.stakeType === 'cultivation' ? '修为' : '灵石';
        const amount = fishShrimpBetAmountV0148();
        const preview = document.getElementById('fishBetPreview');
        const quick = document.getElementById('fishQuickPreview');
        if (preview) preview.innerHTML = `本次下注：<b>${formatNumber(amount)} ${unit}</b>`;
        if (quick) quick.textContent = `${unit} · ${formatNumber(draft.quantity)} × ${draft.multiplier}`;
      });
    }

    document.querySelectorAll('[data-fish-symbol]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        if (button.disabled) return;
        const draft = captureFishShrimpDraftV0148();
        const amount = fishShrimpBetAmountV0148();
        if (!amount) return showToast('请输入有效的下注数量。','error');
        enqueueFishShrimpBetV0150(
          state.casinoHouseMode,
          draft.stakeType,
          button.dataset.fishSymbol,
          amount
        );
      });
    });

    document.querySelectorAll('[data-fish-refresh]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        setBusy(button,true,'刷新中…');
        await refreshFishShrimpStateV0148(false);
        setBusy(button,false);
      });
    });

    const houseGameInput = document.getElementById('houseGame');
    const houseChoice = document.getElementById('houseChoice');
    const fillHouseChoices = game => {
      if (!houseChoice) return;
      houseChoice.innerHTML = houseChoiceOptions(game).map(([value, name]) => `<option value="${value}">${name}</option>`).join('');
    };
    document.querySelectorAll('[data-paigow-open]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', async () => {
        if (!(await requireCasinoEnabledV198({ force: true, notify: true }))) return;
        const moduleApi = window.JiuxiaoPaiGowB01;
        if (!moduleApi || typeof moduleApi.open !== 'function') {
          showToast('九霄灵牌模块尚未加载，请刷新页面后重试。', 'error');
          return;
        }
        moduleApi.open({ source: 'casino-house', baseline: 'V1.2_FIX1_CACHE38' });
      });
    });

    document.querySelectorAll('[data-house-select-game]').forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        const game = button.dataset.houseSelectGame || 'spirit_dice';
        const draft = getCasinoDraft('house');
        const previousGame = draft.game;
        draft.game = game;
        draft.choice = game === 'fish_shrimp' ? '' : (houseChoiceOptions(game)[0]?.[0] || 'big');
        state.casinoDrafts.house = draft;
        // FIX1：先同步旧页面里的隐藏玩法字段，再触发重绘。
        // 否则 renderCasinoPanel() 开头会从旧DOM重新抓取 spirit_dice，
        // 将刚选择的 fish_shrimp 覆盖回去，表现为点击鱼虾灵局没有反应。
        if (houseGameInput) houseGameInput.value = game;
        if (game === 'fish_shrimp' || previousGame === 'fish_shrimp') {
          renderCasinoPanel();
          return;
        }
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
          const result = await rpcPlayHouseGameV1Fix4(state.casinoHouseMode, houseGameInput?.value || 'spirit_dice', stake.stakeType, stake.amount, houseChoice?.value || 'big');
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
          showToast(result?.content || result?.result_text || '应局成功，赌契已经立即结算。', result?.outcome === 'win' ? 'success' : result?.outcome === 'loss' ? 'error' : undefined);
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



  // V2.0.8 CACHE100：异灵根与持剑天生剑心均使用境界基础道攻加成。
  // V1.0 CACHE30 · 元神战斗属性总览（接入 B-COMBAT01 服务端权威快照）
  function primordialSpiritPanelHtmlV1(root = {}, fate = {}, snapshot = state.battleSnapshotV1) {
    const rootName = root.name || '未测灵根';
    const fateName = fate.name || snapshot?.fate_name || '未定命格';
    const ready = snapshot && snapshot.status !== 'unavailable' && Number.isFinite(Number(snapshot.attack));
    const value = key => ready ? formatNumber(snapshot[key] || 0) : (snapshot?.status === 'unavailable' ? '未部署' : '同步中');
    const mutationBaseRate = ready && snapshot?.mutation_active
      ? Math.max(0, Number(snapshot.mutation_base_stat_bonus ?? 0.08))
      : 0;
    const swordBaseRate = ready && snapshot?.sword_heart_active
      ? Math.max(0, Number(snapshot.sword_heart_base_stat_bonus ?? 0.08))
      : 0;
    const activeBaseRate = snapshot?.mutation_active ? mutationBaseRate : swordBaseRate;
    const activeBaseRatePercent = activeBaseRate * 100;
    const activeBaseMultiplier = ready && (snapshot?.mutation_active || snapshot?.sword_heart_active)
      ? Math.max(1, Number(snapshot.talent_base_stat_multiplier ?? snapshot.mutation_base_stat_multiplier ?? snapshot.sword_heart_base_stat_multiplier ?? (1 + activeBaseRate)))
      : 1;
    const ringBasePercent = ready ? Math.max(0, Number(snapshot.equipment_element_bonus || 0)) : 0;
    const ringEffectivePercent = ready
      ? Math.max(0, Number(snapshot.effective_equipment_element_bonus ?? ringBasePercent))
      : 0;
    const bonusValue = ready
      ? (snapshot?.mutation_active
        ? `变异·${snapshot.mutation_name || '未知'} · 基攻+${formatNumber(activeBaseRatePercent, 2)}%`
        : (snapshot?.sword_heart_active
          ? `剑心 · 基攻+${formatNumber(activeBaseRatePercent, 2)}%`
          : (ringBasePercent > 0 ? `戒指 +${formatNumber(ringBasePercent, 2)}%` : `五行 · ${snapshot.element_name || '未定'}`)))
      : (snapshot?.status === 'unavailable' ? '未部署' : '同步中');
    const card = (position, icon, name, displayValue, detail) => `
      <button class="yuanshen-stat-card-v0155 ${position}" type="button" data-yuanshen-stat="${escapeHtml(name)}" data-yuanshen-detail="${escapeHtml(detail)}">
        <span class="yuanshen-sigil-v0155" aria-hidden="true">${escapeHtml(icon)}</span>
        <span class="yuanshen-stat-copy-v0155">
          <strong>${escapeHtml(name)}</strong>
          <i aria-hidden="true"></i>
          <small>当前 · <b>${escapeHtml(displayValue)}</b></small>
        </span>
      </button>`;
    const liveValue = key => ready ? formatNumber(snapshot[key] || 0) : (snapshot?.status === 'unavailable' ? '不可用' : '同步中');
    const liveDetail = (baseKey, realmBaseKey, equipmentKey, equipmentLabel) => {
      if (!ready) return '等待服务端权威属性';
      const baseValue = Number(snapshot[baseKey] || 0);
      const realmBaseValue = Number(snapshot[realmBaseKey] ?? baseValue);
      const equipmentValue = Number(snapshot[equipmentKey] || 0);
      const baseText = (snapshot?.mutation_active || snapshot?.sword_heart_active) && baseKey === 'base_attack'
        ? `境界 ${formatNumber(realmBaseValue)} × ${formatNumber(activeBaseMultiplier, 2)} = 基础 ${formatNumber(baseValue)}`
        : `境界基础 ${formatNumber(baseValue)}`;
      return `${baseText}${equipmentValue ? ` + ${equipmentLabel} ${formatNumber(equipmentValue)}` : ` · ${equipmentLabel} 0`}`;
    };
    const liveRow = (key, label, detail, tone = '') => `
      <div class="yuanshen-live-row-v178 ${tone}" data-live-stat="${escapeHtml(key)}">
        <span>${escapeHtml(label)}</span>
        <strong>${escapeHtml(liveValue(key))}</strong>
        <small>${escapeHtml(detail)}</small>
      </div>`;
    const bonusLabel = snapshot?.mutation_active ? '异灵根' : (snapshot?.sword_heart_active ? '天生剑心' : '戒指增伤');
    const bonusDisplay = ready
      ? ((snapshot?.mutation_active || snapshot?.sword_heart_active) ? `+${formatNumber(activeBaseRatePercent, 2)}%` : `+${formatNumber(ringEffectivePercent, 2)}%`)
      : (snapshot?.status === 'unavailable' ? '不可用' : '同步中');
    const bonusDetail = ready
      ? (snapshot?.mutation_active
        ? `境界基础道攻+${formatNumber(activeBaseRatePercent, 2)}%${ringBasePercent > 0 ? ` · 戒指独立+${formatNumber(ringEffectivePercent, 2)}%` : ''}`
        : (snapshot?.sword_heart_active
          ? `持剑生效：境界基础道攻+${formatNumber(activeBaseRatePercent, 2)}%${ringBasePercent > 0 ? ` · 戒指独立+${formatNumber(ringEffectivePercent, 2)}%` : ''}`
          : (ringBasePercent > 0 ? `戒指 ${formatNumber(ringBasePercent, 2)}%` : '暂无常驻增伤')))
      : '等待服务端权威属性';
    return `
      <div id="primordialSpiritRootV1" class="yuanshen-shell-v0155">
        <div class="yuanshen-stage-v0155" aria-label="元神战斗属性总览">
          <div class="yuanshen-beam-field-v0155" aria-hidden="true"></div>
          <aside class="yuanshen-live-rail-v178 left" aria-label="当前攻击与防御属性">
            ${liveRow('attack', '道攻', liveDetail('base_attack', 'realm_base_attack', 'effective_weapon_attack', '武器'), 'attack')}
            ${liveRow('defense', '道御', liveDetail('base_defense', 'realm_base_defense', 'effective_armor_defense', '衣服'), 'defense')}
            ${liveRow('power', '战力', ready ? '基础属性与装备变化后实时重算' : '等待服务端权威属性', 'power')}
          </aside>
          <aside class="yuanshen-live-rail-v178 right" aria-label="当前生机与身法属性">
            ${liveRow('vitality', '生机', liveDetail('base_vitality', 'realm_base_vitality', 'effective_armor_vitality', '裤子'), 'vitality')}
            ${liveRow('agility', '身法', liveDetail('base_agility', 'realm_base_agility', 'effective_armor_agility', '鞋子'), 'agility')}
            <div class="yuanshen-live-row-v178 bonus" data-live-stat="mutation_or_damage_bonus">
              <span>${escapeHtml(bonusLabel)}</span>
              <strong>${escapeHtml(bonusDisplay)}</strong>
              <small>${escapeHtml(bonusDetail)}</small>
            </div>
          </aside>
          ${card('left-1', '攻', '道攻', value('attack'), ready ? `${liveDetail('base_attack', 'realm_base_attack', 'effective_weapon_attack', '武器')}。` : '正在读取服务端权威战斗快照。')}
          ${card('left-2', '御', '道御', value('defense'), ready ? `${liveDetail('base_defense', 'realm_base_defense', 'effective_armor_defense', '法衣')}。` : '正在读取服务端权威战斗快照。')}
          ${card('left-3', '战', '战力', value('power'), '战力 = 道攻×10 + 道御×8 + 生机×1.5 + 身法×5；综合评分不直接决定胜负。')}

          <section class="yuanshen-core-v0155" aria-label="元神运转功法动画">
            <div class="yuanshen-mandala-v0155" aria-hidden="true">
              <div class="yuanshen-halo-v0155"></div>
              <div class="yuanshen-rays-v0155"></div>
              <div class="yuanshen-orbit-v0155"></div>
              <div class="yuanshen-ring-v0155 outer"></div>
              <div class="yuanshen-ring-v0155 middle"></div>
              <div class="yuanshen-ring-v0155 inner"></div>
              <span class="yuanshen-particle-v0155 p1"></span><span class="yuanshen-particle-v0155 p2"></span><span class="yuanshen-particle-v0155 p3"></span><span class="yuanshen-particle-v0155 p4"></span><span class="yuanshen-particle-v0155 p5"></span>
              <div class="yuanshen-cultivator-wrap-v0155">
                <svg class="yuanshen-cultivator-v0155" viewBox="0 0 360 360" role="img" aria-label="正在运转功法的元神剪影">
                  <defs><radialGradient id="yuanshenInnerGlowV1" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#f2d98b" stop-opacity=".42"/><stop offset=".5" stop-color="#d7b764" stop-opacity=".12"/><stop offset="1" stop-color="#d7b764" stop-opacity="0"/></radialGradient></defs>
                  <circle cx="180" cy="178" r="100" fill="url(#yuanshenInnerGlowV1)"/>
                  <path class="body" d="M180 58c-18 0-31 14-31 33 0 8 3 16 8 22-15 8-25 24-25 42 0 11 3 21 8 29-26 11-54 33-74 56l51 31-31 31h188l-31-31 51-31c-20-23-48-45-74-56 5-8 8-18 8-29 0-18-10-34-25-42 5-6 8-14 8-22 0-19-13-33-31-33Z"/>
                  <path class="body" d="M116 257 72 293l71 4 37 39 37-39 71-4-44-36-45 22h-38Z"/>
                  <path class="meridian" d="M180 103 C160 137 205 158 180 191 C156 223 199 240 180 281"/><path class="meridian" d="M180 150 C144 164 137 191 112 217" opacity=".65"/><path class="meridian" d="M180 150 C216 164 223 191 248 217" opacity=".65"/><circle class="dantian" cx="180" cy="210" r="7"/>
                </svg>
              </div>
            </div>
            <div class="yuanshen-core-copy-v0155">
              <h4>元神显化 · 战意流转</h4>
              <p>${ready ? `${escapeHtml(snapshot.realm || '未知境界')} · 本命${escapeHtml(snapshot.element_name || '未定')}行${snapshot?.mutation_active ? ` · 变异${mutationAttributeHtmlV12(snapshot)}` : ''}` : '神识内守，周天自转'}</p>
              <span>道攻 / 道御 / 生机 / 身法</span>
              <em>${ready ? `常驻战力 ${formatNumber(snapshot.power || 0)}` : '战斗属性正在与云端同步'}</em>
            </div>
          </section>

          ${card('right-1', '生', '生机', value('vitality'), ready ? `${liveDetail('base_vitality', 'realm_base_vitality', 'effective_armor_vitality', '法衣')}。` : '正在读取服务端权威战斗快照。')}
          ${card('right-2', '身', '身法', value('agility'), ready ? `${liveDetail('base_agility', 'realm_base_agility', 'effective_armor_agility', '鞋履')}；身法用于决定先手。` : '正在读取服务端权威战斗快照。')}
          ${card('right-3', '元', '加成', bonusValue, ready ? `${snapshot?.mutation_active ? `异灵根基攻+${formatNumber(activeBaseRatePercent, 2)}%` : (snapshot?.sword_heart_active ? `剑心持剑基攻+${formatNumber(activeBaseRatePercent, 2)}%` : `本命${snapshot.element_name || '未定'}行`)}${ringBasePercent > 0 ? ` · 戒指独立+${formatNumber(ringEffectivePercent, 2)}%` : ''}` : '读取中')}
        </div>
        <div id="yuanshenDetailV0155" class="yuanshen-detail-v0155" aria-live="polite">${ready ? `战斗属性由服务端实时计算；武器：${escapeHtml(snapshot.weapon_name || '赤手空拳')}，法衣：${escapeHtml(snapshot.armor_name || '赤裸')}。${snapshot?.mutation_active ? `异灵根境界基础道攻+${formatNumber(activeBaseRatePercent, 2)}%。` : (snapshot?.sword_heart_active ? `天生剑心持剑生效，境界基础道攻+${formatNumber(activeBaseRatePercent, 2)}%。` : '')}` : snapshot?.status === 'unavailable' ? `战斗数据库尚未部署：${escapeHtml(snapshot.error || '请执行 V1.0 SQL。')}` : '正在读取服务端战斗属性，界面不会生成伪造数值。'}</div>
      </div>`;
  }

  function renderPrimordialSpiritFromStateV1() {
    const root = document.getElementById('primordialSpiritRootV1');
    if (!root) return;
    const spiritRoot = state.details?.spiritRoot || {};
    const fate = state.details?.fate || {};
    root.outerHTML = primordialSpiritPanelHtmlV1(spiritRoot, fate, state.battleSnapshotV1);
    bindPrimordialSpiritPanelV0155();
    window.dispatchEvent(new CustomEvent('jiuxiao:primordial-rendered'));
  }

  async function refreshMyBattleSnapshotV1(force = false) {
    if (!state.character || state.battleSnapshotSyncingV1) return state.battleSnapshotV1;
    if (!force && state.battleSnapshotV1 && state.battleSnapshotV1.status !== 'unavailable') return state.battleSnapshotV1;
    state.battleSnapshotSyncingV1 = true;
    try {
      const snapshot = await rpcGetMyBattleSnapshotV1();
      state.battleSnapshotV1 = snapshot ? { ...snapshot, status: 'ok' } : { status: 'unavailable', error: '未找到当前角色战斗快照。' };
    } catch (error) {
      state.battleSnapshotV1 = { status: 'unavailable', error: translateError(error) };
    } finally {
      state.battleSnapshotSyncingV1 = false;
      renderPrimordialSpiritFromStateV1();
      renderHeroSpiritRootChipV1();
    }
    return state.battleSnapshotV1;
  }

  function bindPrimordialSpiritPanelV0155() {
    const cards = Array.from(document.querySelectorAll('[data-yuanshen-stat]'));
    const detail = document.getElementById('yuanshenDetailV0155');
    cards.forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        cards.forEach(item => item.classList.toggle('active', item === button));
        if (detail) detail.textContent = `${button.dataset.yuanshenStat}：${button.dataset.yuanshenDetail}`;
      });
    });
  }


  // Release verifier navigation contracts: data-mobile-tab="market" data-mobile-tab="social" data-mobile-tab="sect"
  function mobileBottomNavHtml(activeTab = 'cultivation') {
    const items = [
      ['cultivation', '修', '修炼'],
      ['primordial', '元', '元神'],
      ['techniques', '法', '功法'],
      ['cave', '府', '洞府'],
      ['secret_realm', '秘', '秘境'],
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


  function fateEffectHtml(fate, fateStatus) {
    const status = fateStatus?.status === 'ok' ? fateStatus : null;
    if (!status) return `<p>${escapeHtml(fate.description || '命格信息尚未读取。')}</p>`;
    const base = Number(status.base_cultivation_bonus || 0) * 100;
    const total = Number(status.total_cultivation_bonus || 0) * 100;
    let current = '';
    if (status.code === 'late_bloomer') {
      current = `<small>当前 ${formatNumber(status.current_age || 0)} 岁 · 厚积薄发 +${formatNumber(Number(status.current_special_cultivation_bonus || 0) * 100, 2)}个百分点 · 命格总修炼 +${formatNumber(total, 2)}%</small>`;
    } else if (status.code === 'unyielding_heart') {
      current = `<small>当前百折 ${formatNumber(status.unyielding_stack_count || 0)} / ${formatNumber(status.unyielding_stack_limit || 4)} 层 · 突破额外 +${formatNumber(Number(status.unyielding_current_bonus || 0) * 100, 0)}个百分点</small>`;
    } else if (status.code === 'sword_heart' && !status.combat_effect_enabled) {
      current = '<small>剑心通明：战斗系统尚未开放，战斗加成暂不参与其他结算。</small>';
    }
    return `<p><b>基础效果：</b>修炼速度 +${formatNumber(base, 2)}%</p><p><b>${escapeHtml(status.special_name || '专属效果')}：</b>${escapeHtml(status.special_description || '')}</p>${current}`;
  }


  function cultivationEffectGroupsV0154() {
    const now = Date.now();
    const rows = (state.details?.cultivationEffects || []).filter(row => row?.is_active !== false && (!row.expires_at || new Date(row.expires_at).getTime() > now));
    const groups = { opportunity: [], item: [], other: [] };
    rows.forEach(row => {
      const key = String(row.source_key || '');
      if (key.startsWith('opptech:') || key.startsWith('exclusive:')) return;
      const source = String(row.source_type || '').toLowerCase();
      if (source.includes('opportunity') || key.startsWith('opp:') || key.startsWith('opportunity:')) groups.opportunity.push(row);
      else if (source.includes('item') || source.includes('inventory') || key.startsWith('item:')) groups.item.push(row);
      else groups.other.push(row);
    });
    return groups;
  }

  function effectGroupTotalsV0154(rows = []) {
    return rows.reduce((sum, row) => ({
      flat: sum.flat + Number(row?.flat_rate_per_second || 0),
      multiplier: sum.multiplier + Number(row?.multiplier_bonus || 0)
    }), { flat: 0, multiplier: 0 });
  }

  function cultivationRateBreakdownModalHtmlV0154() {
    const c = state.cultivationStatus || {};
    const technique = localTechniqueContributionV0154();
    const ordinary = (state.techniqueSystem?.techniques || []).filter(row => row?.equipped_slot);
    const exclusive = (state.exclusiveTechniqueSystem?.techniques || []).filter(row => row?.equipped);
    const groups = cultivationEffectGroupsV0154();
    const opportunity = effectGroupTotalsV0154(groups.opportunity);
    const items = effectGroupTotalsV0154(groups.item);
    const other = effectGroupTotalsV0154(groups.other);
    const base = Number(c.base_rate_per_second || 0);
    const effectFlat = Number(c.effect_flat_rate || 0);
    const effectMultiplier = Number(c.effect_multiplier_bonus || 0);
    const fixedSubtotal = base + technique.flat + effectFlat;
    const additive = Math.max(0, 1 + Number(c.fate_bonus || 0) + technique.multiplier + effectMultiplier);
    const insightCount = Math.max(0, Number(state.breakthroughStatus?.heavenly_insight_count || 0));
    const insightMultiplier = 1 + insightCount * 0.10;
    const finalRate = Number(c.current_rate_per_second || 0);
    const effectRows = rows => rows.length ? rows.map(row => `<div class="rate-detail-row"><span>${escapeHtml(row.display_name || row.source_key || '未名效果')}<small>${escapeHtml(effectRemainingText(row))}</small></span><strong>${Number(row.flat_rate_per_second || 0) ? `+${formatNumber(row.flat_rate_per_second, 3)}/秒` : ''}${Number(row.flat_rate_per_second || 0) && Number(row.multiplier_bonus || 0) ? ' · ' : ''}${Number(row.multiplier_bonus || 0) ? `+${formatNumber(Number(row.multiplier_bonus) * 100, 2)}%` : ''}</strong></div>`).join('') : '<div class="rate-detail-empty">当前无此类加成</div>';
    const ordinaryRows = ordinary.length ? ordinary.map(row => {
      const values = techniqueV2EffectValues(row);
      const slot = Number(row.slot_multiplier ?? techniqueSlotMultiplier(row.equipped_slot));
      const mastery = row.is_mastered ? 1.2 : 1;
      const flat = values.flat * slot * mastery;
      const mult = values.multiplier * slot * mastery;
      return `<div class="rate-detail-row"><span>《${escapeHtml(row.name || '功法')}》<small>第${formatNumber(row.level)}层 · ${escapeHtml(techniqueSlotName(row.equipped_slot))}${row.is_mastered ? ' · 圆满×1.20' : ''}</small></span><strong>${flat ? `+${formatNumber(flat, 3)}/秒` : ''}${flat && mult ? ' · ' : ''}${mult ? `+${formatNumber(mult * 100, 2)}%` : ''}</strong></div>`;
    }).join('') : '<div class="rate-detail-empty">当前没有运转普通功法</div>';
    const exclusiveRows = exclusive.length ? exclusive.map(row => `<div class="rate-detail-row"><span>《${escapeHtml(row.name || '专属功法')}》<small>专属槽 · 第${formatNumber(row.level)}层${row.is_mastered ? ' · 圆满×1.20' : ''}</small></span><strong>+${formatNumber(Number(row.effect_multiplier_bonus || 0) * 100, 2)}%</strong></div>`).join('') : '<div class="rate-detail-empty">当前没有运转专属功法</div>';
    return `
      <div id="cultivationRateBackdrop" class="modal-backdrop rate-detail-backdrop">
        <section class="modal rate-detail-modal" role="dialog" aria-modal="true" aria-labelledby="cultivationRateDetailTitle">
          <button id="closeCultivationRateDetailBtn" class="modal-close-button" type="button" aria-label="关闭">×</button>
          <span class="eyebrow">云端命书 · 当前快照</span>
          <h2 id="cultivationRateDetailTitle">修炼速度构成</h2>
          <div class="rate-detail-total"><span>当前自动修炼速度</span><strong>${formatRate(finalRate)}</strong></div>
          <section class="rate-detail-section"><h3>固定速度</h3>
            <div class="rate-detail-row"><span>基础吐纳</span><strong>+${formatNumber(base, 3)}/秒</strong></div>
            <div class="rate-detail-row"><span>功法固定贡献</span><strong>+${formatNumber(technique.flat, 3)}/秒</strong></div>
            <div class="rate-detail-row"><span>机缘、道具与其他固定贡献</span><strong>+${formatNumber(effectFlat, 3)}/秒</strong></div>
            <div class="rate-detail-row subtotal"><span>固定速度小计</span><strong>+${formatNumber(fixedSubtotal, 3)}/秒</strong></div>
          </section>
          <details class="rate-detail-section" open><summary>普通功法明细</summary>${ordinaryRows}</details>
          <details class="rate-detail-section" open><summary>专属功法明细</summary>${exclusiveRows}</details>
          <details class="rate-detail-section"><summary>持续机缘（固定 ${opportunity.flat >= 0 ? '+' : ''}${formatNumber(opportunity.flat, 3)}/秒 · 倍率 ${opportunity.multiplier >= 0 ? '+' : ''}${formatNumber(opportunity.multiplier * 100, 2)}%）</summary>${effectRows(groups.opportunity)}</details>
          <details class="rate-detail-section"><summary>道具效果（固定 ${items.flat >= 0 ? '+' : ''}${formatNumber(items.flat, 3)}/秒 · 倍率 ${items.multiplier >= 0 ? '+' : ''}${formatNumber(items.multiplier * 100, 2)}%）</summary>${effectRows(groups.item)}</details>
          ${groups.other.length ? `<details class="rate-detail-section"><summary>其他效果（固定 ${other.flat >= 0 ? '+' : ''}${formatNumber(other.flat, 3)}/秒 · 倍率 ${other.multiplier >= 0 ? '+' : ''}${formatNumber(other.multiplier * 100, 2)}%）</summary>${effectRows(groups.other)}</details>` : ''}
          <section class="rate-detail-section"><h3>倍率修正</h3>
            <div class="rate-detail-row"><span>灵根修炼</span><strong>×${formatNumber(c.root_multiplier || 1, 3)}</strong></div>
            <div class="rate-detail-row"><span>命格修正</span><strong>${Number(c.fate_bonus || 0) >= 0 ? '+' : ''}${formatNumber(Number(c.fate_bonus || 0) * 100, 2)}%</strong></div>
            <div class="rate-detail-row"><span>功法倍率</span><strong>+${formatNumber(technique.multiplier * 100, 2)}%</strong></div>
            <div class="rate-detail-row"><span>机缘、道具与其他倍率</span><strong>${effectMultiplier >= 0 ? '+' : ''}${formatNumber(effectMultiplier * 100, 2)}%</strong></div>
            <div class="rate-detail-row"><span>灵气环境</span><strong>×${formatNumber(c.qi_multiplier || 1, 3)}</strong></div>
            <div class="rate-detail-row"><span>天劫感悟 ${formatNumber(insightCount)} 丝</span><strong>×${formatNumber(insightMultiplier, 2)}</strong></div>
          </section>
          <div class="rate-detail-formula">(${formatNumber(fixedSubtotal, 3)} × ${formatNumber(c.root_multiplier || 1, 3)} × ${formatNumber(additive, 3)}) × ${formatNumber(c.qi_multiplier || 1, 3)} × ${formatNumber(insightMultiplier, 2)} = <strong>${formatRate(finalRate)}</strong></div>
        </section>
      </div>`;
  }

  function openCultivationRateBreakdownV0154() {
    modalRoot.innerHTML = cultivationRateBreakdownModalHtmlV0154();
    const close = () => { modalRoot.innerHTML = ''; };
    document.getElementById('closeCultivationRateDetailBtn')?.addEventListener('click', close);
    document.getElementById('cultivationRateBackdrop')?.addEventListener('click', event => { if (event.target?.id === 'cultivationRateBackdrop') close(); });
  }

  function bindCultivationRateBreakdownV0154() {
    const button = document.getElementById('cultivationRateBreakdownBtn');
    if (!button || button.dataset.bound === '1') return;
    button.dataset.bound = '1';
    button.addEventListener('click', openCultivationRateBreakdownV0154);
  }

  function battleElementClassV1(element = '') {
    const safe = ['metal','wood','water','fire','earth'].includes(String(element || '').toLowerCase())
      ? String(element).toLowerCase()
      : 'none';
    return `element-${safe}`;
  }

  function mutationElementClassV12(element = '') {
    const safe = ['thunder','ice','wind'].includes(String(element || '').toLowerCase())
      ? String(element).toLowerCase()
      : 'none';
    return `mutation-${safe}`;
  }

  function mutationAttributeHtmlV12(snapshot = {}) {
    const name = String(snapshot?.mutation_name || '').trim();
    if (!name) return '';
    return `<b class="mutation-attribute-v12 ${mutationElementClassV12(snapshot?.mutation_element)}">${escapeHtml(name)}</b>`;
  }

  function spiritRootDisplayHtmlV12(rootName = '', snapshot = {}) {
    const safeRoot = escapeHtml(rootName || '未测灵根');
    const mutation = mutationAttributeHtmlV12(snapshot);
    return mutation ? `变异灵根（${mutation}）` : safeRoot;
  }

  function mutationBadgeHtmlV12(snapshot = {}) {
    const mutation = mutationAttributeHtmlV12(snapshot);
    return mutation ? `<span class="mutation-badge-v12">变异·${mutation}</span>` : '';
  }

  function heroSpiritRootChipHtmlV1(root = {}, snapshot = state.battleSnapshotV1) {
    const rootDisplay = spiritRootDisplayHtmlV12(root.name || '未测灵根', snapshot || {});
    if (snapshot?.mutation_active) return rootDisplay;
    const elementName = String(snapshot?.element_name || '').trim();
    if (!elementName) return rootDisplay;
    return `${rootDisplay}<b class="hero-spirit-element-v1 ${battleElementClassV1(snapshot?.element)}">（${escapeHtml(elementName)}）</b>`;
  }

  function renderHeroSpiritRootChipV1() {
    const chip = document.getElementById('heroSpiritRootChipV1');
    if (!chip) return;
    chip.innerHTML = heroSpiritRootChipHtmlV1(state.details?.spiritRoot || {}, state.battleSnapshotV1);
  }

  function renderDashboard(bundle) {
    renderAccount();
    const c = bundle.character;
    const world = bundle.world || {};
    const stage = bundle.stage || {};
    const realm = bundle.realm || {};
    const root = bundle.spiritRoot || {};
    const fate = bundle.fate || {};
    const fateStatus = bundle.fateStatus || state.fateStatus || null;
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
    const techniqueLibrary = bundle.techniqueLibrary || state.techniqueLibrary || { status: 'loading', books: [] };
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
                  <span id="heroSpiritRootChipV1" class="hero-chip spirit-root-chip-v1">${heroSpiritRootChipHtmlV1(root, state.battleSnapshotV1)}</span>
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
            <a href="#primordialSpiritSection">元神</a>
            <a href="#talentSection">功法</a>
            <a href="#inventorySection">洞府</a>
            <a href="#secretRealmSection">秘境</a>
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
              <button id="cultivationRateBreakdownBtn" class="focus-stat focus-stat-button" type="button" aria-label="查看修炼速度构成">
                <span>当前自动修炼速度 · 点击查看构成</span>
                <strong id="liveRateValue">${formatRate(rate)}</strong>
                <small>${cultivationFull ? '丹田已至当前境界极限，请先突破。' : requiredForNext > 0 ? `距下一境还差 ${formatNumber(toNext)} 修为` : '当前版本已达可读取的道关上限。'}</small>
              </button>
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
                <div><span>功法固定</span><strong id="techniqueFlatRateSummary">+${formatNumber(cultivation.technique_flat_rate, 3)}/秒</strong></div>
                <div><span>功法倍率</span><strong id="techniqueMultiplierSummary">+${formatNumber(Number(cultivation.technique_multiplier_bonus || 0) * 100, 2)}%</strong></div>
                <div><span>灵根修炼</span><strong>×${formatNumber(cultivation.root_multiplier || 1, 2)}</strong></div>
                <button id="heavenBalanceBtn" class="heaven-balance-entry" type="button" aria-label="查看${escapeHtml(heavenBalance.status_name || '大道均衡')}规则"><span class="heaven-balance-entry-text">灵气环境（${escapeHtml(heavenBalance.status_name || '大道均衡')}）x${formatHeavenCoefficient(heavenBalance.coefficient || 1)}</span></button>
                <div><span>命格修正</span><strong>${Number(cultivation.fate_bonus || 0) >= 0 ? '+' : ''}${formatNumber(Number(cultivation.fate_bonus || 0) * 100, 2)}%</strong></div>
                <div><span>机缘/道具固定</span><strong>+${formatNumber(cultivation.effect_flat_rate, 3)}/秒</strong></div>
                <div><span>机缘/道具倍率</span><strong>${Number(cultivation.effect_multiplier_bonus || 0) >= 0 ? '+' : ''}${formatNumber(Number(cultivation.effect_multiplier_bonus || 0) * 100, 2)}%</strong></div>
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

        <section id="primordialSpiritSection" class="panel info-section primordial-spirit-panel-v0155" data-mobile-screen="primordial">
          <div class="panel-title"><h3>元神</h3><span class="badge">五行战斗 · 已接入</span></div>
          ${primordialSpiritPanelHtmlV1(root, fate, state.battleSnapshotV1)}
        </section>

        <section id="talentSection" class="panel info-section" data-mobile-screen="techniques">
          <div class="panel-title"><h3>功法</h3><span class="badge">五槽 · 灵石升级 · 圆满</span></div>
          <div class="foundation-grid">
            <article class="path-card">
              <span>先天灵根 · ${escapeHtml(root.rarity || '未知')}</span>
              <strong>${escapeHtml(root.name || '未测')}</strong>
              <p>修炼系数 ×${formatNumber(root.cultivation_multiplier || 1, 2)}。风、冰、雷变异灵根额外使境界基础道攻提高8%；天生剑心在装备剑类武器时同样使境界基础道攻提高8%。二者冲突时只生效一个；均不增加道御、生机、身法，也不放大装备、强化、功法或戒指。其他灵根只影响修炼速度。${escapeHtml(root.description || '')}</p>
            </article>
            <article class="path-card">
              <span>降生命格 · ${escapeHtml(fate.rarity || '未知')}</span>
              <strong>${escapeHtml(fate.name || '未定')}</strong>
              ${fateEffectHtml(fate, fateStatus)}
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
          <div class="panel-title"><h3>洞府</h3><span class="badge">建筑 · 藏经 · 炼丹</span></div>
          ${cavePanelHtml(caveSystem, inventory, techniqueLibrary)}
        </section>

        <section id="secretRealmSection" class="panel" data-mobile-screen="secret_realm">
          <div class="panel-title"><h3>秘境</h3><span class="badge">全天半小时公共场 · 每日10次</span></div>
          <div id="secretRealmRootBSecretRealm01"><div class="empty-state">正在感应本轮秘境……</div></div>
        </section>

        <section id="opportunitySection" class="double-panel-grid breakthrough-only-grid">
          <section id="breakthroughPanel" class="panel progression-panel mobile-panel-card" data-mobile-screen="cultivation">
            ${breakthroughPanelHtml(breakthrough, c.cultivation)}
          </section>
        </section>

        <section id="marketSection" class="panel" data-mobile-screen="market">
          <div class="panel-title"><h3>市坊</h3><span class="badge">天命 · 赌坊 · 珍宝 · 界闻</span></div>
          <div id="bazaarPanelHost">${bazaarPanelHtml(state.marketView || 'home', marketSystem, destinyRanking, worldEvents, state.treasureShop || {})}</div>
        </section>

        <section id="npcSocialSection" class="panel" data-mobile-screen="social">
          <div class="panel-title"><h3>红尘录</h3><span class="badge">故人 · 师徒 · 道侣</span></div>
          ${npcSocialPanelHtml(npcSocial)}
        </section>

        <section id="sectSystemSection" class="panel" data-mobile-screen="sect">
          <div class="panel-title"><h3>宗门</h3><span class="badge">世界宗门 · 市集 · 晋升试炼</span></div>
          <div id="sectV2RootBSect01"><div class="empty-state">正在查阅宗门名册……</div></div>
        </section>

        <section id="historySection" class="panel" data-mobile-screen="history">
          <div class="panel-title"><h3>命书</h3><span class="badge">最新 100 条</span></div>
          <div id="historyTimelineRoot">${historyHtml(bundle.history)}</div>
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
    bindCultivationRateBreakdownV0154();
    bindPrimordialSpiritPanelV0155();
    refreshMyBattleSnapshotV1(false);
    bindInventoryTechniqueActions();
    bindExclusiveTechniqueActions();
    bindNpcSocialActions();
    bindSectSystemActions();
    bindBazaarActions();
    bindMobileDashboardNav();
    window.dispatchEvent(new CustomEvent('jiuxiao:secret-realm-rendered'));
    window.dispatchEvent(new CustomEvent('jiuxiao:sect-v2-rendered'));
    if (!window.__secretRealmClaimSyncBoundV179) {
      window.__secretRealmClaimSyncBoundV179 = true;
      window.addEventListener('jiuxiao:secret-realm-claimed', async () => {
        await Promise.allSettled([syncCultivation(true), refreshCaveSystem(true), refreshHeavenBalance(true), refreshWorldEvents(true)]);
      });
    }
    const manualSyncBtn = document.getElementById('manualSyncBtn');
    if (manualSyncBtn && manualSyncBtn.dataset.bound !== '1') {
      manualSyncBtn.dataset.bound = '1';
      manualSyncBtn.addEventListener('click', async () => {
        setBusy(manualSyncBtn, true, '同步中…');
        try {
          const alive = await syncCultivation(false);
          if (alive !== false && state.character?.status !== 'dead') {
            await Promise.all([refreshBreakthroughStatus(), refreshOpportunity(), refreshHeavenBalance(true), refreshCaveSystem(true), refreshNpcSocial(true), refreshMarketSystem(true), refreshDestinyRanking(false, true), refreshMyBattleSnapshotV1(true), refreshWorldEvents(true)]);
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


  async function refreshActiveTabDataE80(tab = state.activeMobileTab, force = false) {
    if (!networkVisibleE80() || !state.character) return;
    const tasks = [];
    switch (tab) {
      case 'cultivation':
        if (force || staleForE80(state.heavenBalanceFetchedAt, PERF_E80.heavenBalanceSyncMs)) tasks.push(refreshHeavenBalance(true));
        break;
      case 'primordial':
        if (force || !state.battleSnapshotV1) tasks.push(refreshMyBattleSnapshotV1(Boolean(force)));
        break;
      case 'techniques':
        if (force || staleForE80(state.techniqueSystemFetchedAt)) tasks.push(refreshTechniqueSystem(false, true));
        break;
      case 'cave':
        if (force || staleForE80(state.caveSystemFetchedAt)) tasks.push(refreshCaveSystem(true));
        break;
      case 'market':
        if (force || staleForE80(state.marketSystemFetchedAt)) tasks.push(refreshMarketSystem(true));
        if (force || staleForE80(state.worldEventsFetchedAt)) tasks.push(refreshWorldEvents(true));
        if (force || staleForE80(state.destinyRankingFetchedAt, PERF_E80.rankingStaleMs)) tasks.push(refreshDestinyRanking(false, true));
        break;
      case 'social':
        if (force || staleForE80(state.npcSocialFetchedAt)) tasks.push(refreshNpcSocial(true));
        break;
      case 'sect':
        window.dispatchEvent(new CustomEvent('jiuxiao:sect-v2-refresh'));
        break;
      default:
        break;
    }
    if (tasks.length) await Promise.allSettled(tasks);
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
      const previousTab = state.activeMobileTab || 'cultivation';
      state.activeMobileTab = tab;
      const tabbedMode = window.matchMedia('(max-width: 760px), (min-width: 1024px)').matches;
      const sectFocus = tab === 'sect';
      const dashboard = document.querySelector('.dashboard-reforge');
      dashboard?.classList.toggle('sect-focus-mode', sectFocus);
      document.body.classList.toggle('sect-focus-mode', sectFocus);
      screens.forEach(screen => {
        screen.classList.toggle('mobile-screen-hidden', sectFocus ? screen.dataset.mobileScreen !== 'sect' : (tabbedMode && screen.dataset.mobileScreen !== tab));
      });
      buttons.forEach(button => button.classList.toggle('active', button.dataset.mobileTab === tab));
      const desiredPage = pageIndexForTab(tab);
      if (tabbedMode && viewport) requestAnimationFrame(() => showPage(desiredPage, shouldScroll ? 'smooth' : 'auto'));
      if (tabbedMode && shouldScroll) window.scrollTo({ top: 0, behavior: 'smooth' });
      // 洞府页每次进入都默认展示建筑管理区；不再依赖先点击灵脉或矿室。
      if (tab === 'cave' && (previousTab !== 'cave' || shouldScroll)) {
        requestAnimationFrame(() => showCaveWorkbenchB01('buildings'));
      }
    };

    buttons.forEach(button => {
      if (button.dataset.bound === '1') return;
      button.dataset.bound = '1';
      button.addEventListener('click', () => {
        const target = button.dataset.mobileTab || 'cultivation';
        const repeatedMarketTap = target === 'market' && state.activeMobileTab === 'market';
        if (repeatedMarketTap && state.marketView !== 'home') setBazaarView('home', false);
        apply(target, true);
        refreshActiveTabDataE80(target, false).catch(error => {
          console.debug('[九霄问道] 页面按需刷新暂不可用：', error?.message || error);
        });
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
      state.cultivationSyncedAt = Date.now();
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

  // V1.7.6 CACHE55：公共赌场桌运行期间暂停与当前牌桌无关的后台网络同步。
  // 本地修为/洞府倒计时继续运行；离开公共桌后原有定时器会自然恢复联网同步。
  function casinoPublicTableActiveV176() {
    if (document.hidden || state.marketView !== 'casino' || state.casinoView !== 'house') return false;
    const game = state.casinoDrafts?.house?.game || 'spirit_dice';
    return game === 'spirit_dice' || game === 'fish_shrimp';
  }

  function startCultivationLoop() {
    stopCultivationLoop();

    // 纯本地显示仍保持流畅；只有云端读写降频。
    state.cultivationTicker = setInterval(updateLiveCultivationDisplay, 250);
    state.opportunityCountdownTimer = setInterval(updateOpportunityCountdown, 1000);
    state.caveCountdownTimer = setInterval(updateCaveCountdown, 1000);

    state.cultivationSyncTimer = setInterval(() => {
      if (!networkVisibleE80() || casinoPublicTableActiveV176()) return;
      syncCultivation(true);
    }, PERF_E80.cultivationSyncMs);

    state.opportunityPollTimer = setInterval(() => {
      if (!networkVisibleE80() || casinoPublicTableActiveV176()) return;
      refreshOpportunity();
    }, PERF_E80.opportunityPollMs);

    // 洞府、功法、红尘、宗门不再全局轮询；进入对应页面时按需刷新。
    state.heavenBalanceSyncTimer = setInterval(() => {
      if (!networkVisibleE80() || casinoPublicTableActiveV176()) return;
      refreshHeavenBalance(true);
    }, PERF_E80.heavenBalanceSyncMs);

    state.marketSyncTimer = setInterval(() => {
      if (!networkVisibleE80() || state.activeMobileTab !== 'market' || state.marketView !== 'casino') return;
      const publicGame = state.casinoView === 'house' ? (state.casinoDrafts?.house?.game || 'spirit_dice') : '';
      if (publicGame === 'spirit_dice' || publicGame === 'fish_shrimp') return;
      refreshMarketSystem(true);
    }, PERF_E80.marketSyncMs);

    state.worldEventsSyncTimer = setInterval(() => {
      if (!networkVisibleE80() || state.activeMobileTab !== 'market' || casinoPublicTableActiveV176()) return;
      refreshWorldEvents(true);
    }, PERF_E80.worldEventsSyncMs);

    state.divineNoticeTimer = setInterval(() => {
      if (!networkVisibleE80() || casinoPublicTableActiveV176()) return;
      checkDivineNotice(true);
    }, PERF_E80.divineNoticeSyncMs);

    updateLiveCultivationDisplay();
    updateOpportunityCountdown();
    updateCaveCountdown();
    if (networkVisibleE80()) setTimeout(() => checkDivineNotice(true), 500);
  }

  function historyHtml(rows) {
    const latestRows = (rows || []).slice(0, 100);
    if (!latestRows.length) return '<div class="empty-state">命书尚为空白。</div>';
    return `<div class="timeline">${latestRows.map(row => {
      const opportunity = row?.event_type === 'opportunity' || row?.source_type === 'opportunity_result';
      const rarity = row?.rarity || '';
      const highTier = opportunityHighTier(rarity);
      const cleanTitle = String(row?.title || '无名记载').replace(/^机缘[·・]/, '');
      const outcomeLabel = row?.outcome_label || (row?.path_name === '涉险' ? '涉险代价' : '趋吉所得');
      const detail = row?.result_detail || '';
      return `
        <article class="timeline-item ${opportunity ? 'opportunity-history-item' : ''} ${highTier ? 'opportunity-high-tier' : ''}">
          <time>仙历 ${escapeHtml(row.world_year)} 年</time>
          <h4>${opportunity ? `<span class="opportunity-history-grade ${highTier ? 'high-tier' : ''}">【${escapeHtml(rarity || '机缘')}】</span>` : ''}<span>${escapeHtml(cleanTitle)}</span></h4>
          <p>${escapeHtml(row.content || '')}</p>
          ${opportunity && detail ? `<div class="opportunity-history-result"><span>${escapeHtml(outcomeLabel)}</span><strong>${escapeHtml(detail)}</strong></div>` : ''}
        </article>`;
    }).join('')}</div>`;
  }

  async function enterGame(options = {}) {
    const silent = Boolean(options?.silent);
    if (!silent) app.innerHTML = '<section class="loading-screen"><div class="loader-ring"></div><p>正在校准仙历与云端命书……</p></section>';
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

      // V1.0：登录/突破后尝试承接战利修为暂存；RPC未部署时静默兼容旧库。
      const battleEscrowSettlement = await rpcClaimBattleCultivationEscrowBCombat01().catch(() => null);

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
      state.battleSnapshotV1 = null;
      applyTimeStatus(timeStatus);

      if (bundle.character.status === 'dead' || timeStatus?.status === 'dead' || timeStatus?.status === 'awaiting_reincarnation') {
        renderDeathScreen(bundle, timeStatus);
        return;
      }

      const opportunitySettlement = await rpcSettleOpportunityV4();
      const cultivationStatus = opportunitySettlement?.cultivation || null;
      const opportunityStatus = opportunitySettlement?.opportunity || null;
      if (cultivationStatus) {
        bundle.cultivationStatus = cultivationStatus;
        bundle.character.cultivation = cultivationStatus.cultivation_total;
      }
      const [breakthroughStatus, fateStatus, techniqueSystem, exclusiveTechniqueSystem, heavenBalance, caveSystem, techniqueLibrary, destinyRanking, npcSocial, sectSystem, marketSystem, worldEvents, treasureShop] = await Promise.all([
        rpcGetBreakthroughStatus(),
        rpcGetFateStatusB01().catch(() => null),
        rpcGetTechniqueSystemV2(),
        rpcGetExclusiveTechniqueSystemV1().catch(error => ({
          status: 'unavailable', techniques: [], equipped_name: null, error: translateError(error)
        })),
        rpcGetHeavenBalanceV1().catch(error => ({
          status: 'unavailable', error: translateError(error)
        })),
        rpcGetCaveSystemV1(),
        rpcGetTechniqueLibraryV1().catch(error => ({
          status: 'unavailable', books: [], error: translateError(error)
        })),
        rpcGetDestinyRankingV1(50, 0).catch(error => ({
          status: 'unavailable', entries: [], total_count: 0, error: translateError(error)
        })),
        rpcGetNpcSocialV1().catch(error => ({
          status: 'unavailable', contacts: [], recent_events: [], error: translateError(error)
        })),
        Promise.resolve({ status: 'module', module: 'B-SECT01' }),
        rpcGetMarketV1().catch(error => ({
          status: 'unavailable', pools: {}, tickets: {}, open_duels: [], my_duels: [], latest_draws: [], error: translateError(error)
        })),
        rpcGetWorldEventsV1(30).catch(error => ({
          status: 'unavailable', entries: [], error: translateError(error)
        })),
        rpcGetTreasureShopV0154().catch(error => ({ status: 'unavailable', items: [], error: translateError(error) }))
      ]);
      bundle.breakthroughStatus = breakthroughStatus;
      bundle.fateStatus = fateStatus;
      bundle.opportunityStatus = opportunityStatus;
      bundle.techniqueSystem = techniqueSystem;
      bundle.exclusiveTechniqueSystem = exclusiveTechniqueSystem;
      bundle.heavenBalance = heavenBalance;
      bundle.caveSystem = caveSystem;
      bundle.techniqueLibrary = techniqueLibrary;
      bundle.destinyRanking = destinyRanking;
      bundle.npcSocial = npcSocial;
      bundle.sectSystem = sectSystem;
      bundle.marketSystem = marketSystem;
      bundle.worldEvents = worldEvents;
      bundle.treasureShop = treasureShop;
      state.cultivationStatus = cultivationStatus;
      state.breakthroughStatus = breakthroughStatus;
      state.fateStatus = fateStatus;
      state.opportunityStatus = opportunityStatus;
      state.techniqueSystem = techniqueSystem;
      state.exclusiveTechniqueSystem = exclusiveTechniqueSystem;
      state.heavenBalance = heavenBalance;
      state.caveSystem = caveSystem;
      state.techniqueLibrary = techniqueLibrary;
      state.destinyRanking = destinyRanking;
      state.destinyRankingFetchedAt = Date.now();
      state.battleRanking = { status: 'idle', entries: [], total_count: 0 };
      state.battleRankingSyncing = false;
      state.npcSocial = npcSocial;
      state.npcSocialFetchedAt = Date.now();
      state.sectSystem = sectSystem;
      state.sectSystemFetchedAt = Date.now();
      state.marketSystem = marketSystem;
      state.worldEvents = worldEvents;
      state.worldEventsFetchedAt = Date.now();
      state.treasureShop = treasureShop;
      state.treasureShopFetchedAt = Date.now();
      if (Number(opportunitySettlement?.events_resolved || 0) > 0) {
        const opportunityHistory = await rpcGetOpportunityHistoryV0147(100).catch(() => ({ entries: [] }));
        bundle.history = mergeHistoryWithOpportunityResults(bundle.history, opportunityHistory?.entries);
        state.history = bundle.history;
      }
      renderDashboard(bundle);
      if (Number(battleEscrowSettlement?.granted || 0) > 0) {
        setTimeout(() => showToast(`战利修为暂存已承接 ${formatNumber(battleEscrowSettlement.granted)} 点。`, 'success'), 180);
      }
      if (opportunitySettlement?.offline_summary) setTimeout(() => showOpportunityOfflineSummary(opportunitySettlement.offline_summary), 120);
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
      if (silent) {
        showToast(`云端同步失败：${translateError(error)}`, 'error');
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
      document.getElementById('retryBtn').addEventListener('click', () => enterGame());
    }
  }

  // V1.7.9 CACHE59 UIFIX3：穿戴/卸下后以服务端快照为准，多次确认并同步战力榜缓存。
  const battleSnapshotSignatureV178 = snapshot => [
    snapshot?.attack,
    snapshot?.defense,
    snapshot?.vitality,
    snapshot?.agility,
    snapshot?.power,
    snapshot?.effective_weapon_attack,
    snapshot?.effective_armor_defense,
    snapshot?.effective_armor_vitality,
    snapshot?.effective_armor_agility,
    snapshot?.equipment_element_bonus,
    snapshot?.effective_equipment_element_bonus,
    snapshot?.talent_ring_amplification_rate
  ].map(value => Number(value || 0)).join('|');

  const waitForBattleSnapshotV178 = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));

  window.JIUXIAO_REFRESH_BATTLE_SNAPSHOT_V1 = async function (options = {}) {
    if (!state.character) return null;
    const previousSignature = battleSnapshotSignatureV178(state.battleSnapshotV1);
    const delays = options?.reason === 'equipment' ? [0, 260, 760] : [0];
    let latest = state.battleSnapshotV1;
    for (let index = 0; index < delays.length; index += 1) {
      if (delays[index] > 0) await waitForBattleSnapshotV178(delays[index]);
      let waitCount = 0;
      while (state.battleSnapshotSyncingV1 && waitCount < 30) {
        await waitForBattleSnapshotV178(50);
        waitCount += 1;
      }
      state.battleSnapshotV1 = null;
      latest = await refreshMyBattleSnapshotV1(true);
      const currentSignature = battleSnapshotSignatureV178(latest);
      if (index > 0 && currentSignature !== previousSignature) break;
    }
    refreshRankingBoard('battle', false, true).catch(() => {});
    window.dispatchEvent(new CustomEvent('jiuxiao:battle-snapshot-updated', { detail: latest || null }));
    return latest;
  };

  window.addEventListener('jiuxiao:equipment-loadout-changed', event => {
    window.JIUXIAO_REFRESH_BATTLE_SNAPSHOT_V1({ reason: 'equipment', action: event?.detail?.action || '' }).catch(error => {
      console.warn('[九霄问道] 装备变化后的战斗属性刷新失败：', error?.message || error);
    });
  });


  window.addEventListener('jiuxiao:world-events-dirty', () => {
    refreshWorldEvents(true).catch(error => {
      console.warn('[九霄问道] 九霄界闻即时刷新失败：', error?.message || error);
    });
  });

  async function bootstrap() {
    if (!SUPABASE_URL || !API_KEY) {
      app.innerHTML = '<section class="notice-card"><h2>游戏配置缺失</h2><p>请检查 config.js 中的 Supabase URL 与 Publishable key。</p></section>';
      return;
    }
    importSessionFromHash();
    loadStoredSession();
    const resumeFromBackgroundE80 = async () => {
      if (!networkVisibleE80() || state.resumeSyncingE80) return;
      const now = Date.now();
      if (now - Number(state.lastResumeSyncAtE80 || 0) < PERF_E80.resumeCooldownMs) return;
      state.resumeSyncingE80 = true;
      state.lastResumeSyncAtE80 = now;
      try {
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
            await Promise.allSettled([refreshOpportunity(), refreshBreakthroughStatus()]);
            await refreshActiveTabDataE80(state.activeMobileTab || 'cultivation', true);
            checkDivineNotice(true);
          }
        }
      } finally {
        state.resumeSyncingE80 = false;
      }
    };

    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') resumeFromBackgroundE80();
    });
    window.addEventListener('focus', resumeFromBackgroundE80, { passive: true });
    if (state.session?.access_token) await enterGame();
    else renderAuth();
  }

  bootstrap();
})();
