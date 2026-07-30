(() => {
  'use strict';

  const cfg = window.GAME_CONFIG || {};
  const url = String(cfg.supabaseUrl || '').replace(/\/+$/, '');
  const key = String(cfg.supabasePublishableKey || '');
  const project = (() => {
    try { return new URL(url).hostname.split('.')[0]; }
    catch { return 'unknown'; }
  })();
  const sessionKey = `nine_cloud_dao_session_${project}_v1`;
  const app = document.getElementById('paigowApp');
  const toastEl = document.getElementById('pgToast');
  const state = {
    lobby: null,
    room: null,
    roomId: null,
    busy: false,
    selectedHead: [],
    poll: null,
    clock: null,
    lastError: '',
    renderHtml: '',
    polling: false,
    createDraft: {
      duelType: 'pvp',
      pvpMode: 'rob',
      game: 'small',
      stake: 'spirit_stone',
      base: '20'
    }
  };

  const esc = value => String(value ?? '').replace(/[&<>"']/g, char => ({
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;'
  }[char]));
  const fmt = value => Number(value || 0).toLocaleString('zh-CN');
  const uuid = () => globalThis.crypto?.randomUUID?.() || 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
    const r = Math.random() * 16 | 0;
    return (c === 'x' ? r : (r & 3 | 8)).toString(16);
  });

  function session() {
    try { return JSON.parse(localStorage.getItem(sessionKey) || 'null'); }
    catch { return null; }
  }

  function toast(message) {
    toastEl.textContent = message;
    toastEl.classList.add('show');
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => toastEl.classList.remove('show'), 2800);
  }

  function errorText(error) {
    const raw = String(error?.message || error || '未知错误');
    const map = [
      ['PAIGOW_DISABLED', '九霄灵牌当前处于维护状态。'],
      ['AUTH_REQUIRED', '登录状态已失效，请返回主界面重新登录。'],
      ['PAIGOW_ROOM_LIMIT_REACHED', '天地玄黄四间房已经全部开放。'],
      ['PAIGOW_BASE_STAKE_INVALID', '底注不符合当前资源的最低要求。'],
      ['PAIGOW_SEAT_OCCUPIED', '该座位刚被其他修士选中。'],
      ['PAIGOW_SEAT_NOT_ACTIVE_FOR_MODE', '该席位在当前玩法中属于候补席。'],
      ['PAIGOW_PLAYERS_NOT_READY', '仍有入座玩家尚未准备。'],
      ['PAIGOW_NOT_ENOUGH_PLAYERS', '当前参战人数不足。'],
      ['PAIGOW_ONLY_OWNER_STARTS', '只有房主可以开始本局。'],
      ['PAIGOW_STAKE_EXCEEDS_THIRTY_PERCENT_OR_BALANCE', '本局赌注和手续费超过开局余额30%或余额不足。'],
      ['PAIGOW_DEALER_LIABILITY_LIMIT', '庄家30%责任资金不足，请降低倍率。'],
      ['PAIGOW_HEAD_MUST_NOT_EXCEED_TAIL', '头牌必须弱于或等于尾牌。'],
      ['PAIGOW_CANNOT_LEAVE_ACTIVE_ROUND', '进行中的参战玩家不能离房。'],
      ['CASINO_CULTIVATION_REQUIRES_NASCENT_SOUL', '修为局仅对元婴期及以上开放。'],
      ['CULTIVATION_STAKE_MINIMUM', '修为下注额不足最低限制。'],
      ['CASINO_INSUFFICIENT_SPIRIT_STONES', '灵石余额不足。'],
      ['CASINO_INSUFFICIENT_CULTIVATION', '当前可动用修为不足。'],
      ['PAIGOW_REQUEST_IN_PROGRESS', '上一项动作仍在处理，请稍后。'],
      ['record "m" is not assigned yet', '数据库仍是旧版开局函数，请执行78号修复SQL。'],
      ['join_paigow_room_bpaigow01(uuid, integer, boolean) does not exist', '数据库仍是旧版入座函数，请执行77号修复SQL。']
    ];
    return map.find(([code]) => raw.includes(code))?.[1] || raw;
  }

  async function rpc(name, body = {}) {
    const s = session();
    if (!s?.access_token) throw new Error('AUTH_REQUIRED');
    const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: {
        apikey: key,
        Authorization: `Bearer ${s.access_token}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(body)
    });
    const text = await response.text();
    let data = null;
    try { data = text ? JSON.parse(text) : null; }
    catch { data = text; }
    if (!response.ok) throw new Error(data?.message || data?.msg || data?.error || `HTTP ${response.status}`);
    return data;
  }

  function setBusyUi(busy) {
    app.classList.toggle('is-busy', busy);
    app.setAttribute('aria-busy', busy ? 'true' : 'false');
  }

  async function action(fn) {
    if (state.busy) return;
    state.busy = true;
    setBusyUi(true);
    try {
      await fn();
      state.lastError = '';
    } catch (error) {
      state.lastError = errorText(error);
      toast(state.lastError);
    } finally {
      state.busy = false;
      setBusyUi(false);
      render();
    }
  }

  const duelLabel = room => room.duel_type === 'laohe'
    ? '老何固定庄'
    : room.pvp_mode === 'rob' ? '随机抢庄' : '玩家开船';
  const duelShort = room => room.duel_type === 'laohe'
    ? '老何 VS 玩家'
    : room.pvp_mode === 'rob' ? '玩家抢庄' : '玩家开船';
  const gameLabel = room => room.game_mode === 'big' ? '大牌九' : '牌九';
  const currencyLabel = type => type === 'cultivation' ? '修为' : '灵石';
  const phaseLabel = phase => ({
    rob: '随机抢庄',
    multiplier: '选择倍率',
    arrange: '组合头尾',
    head_reveal: '先亮弱头',
    tail_reveal: '再亮强尾',
    settled: '本局结算',
    cancelled: '本局取消',
    waiting: '等待开局'
  }[phase] || phase || '等待开局');
  const initials = name => Array.from(String(name || '道')).slice(-1)[0] || '道';

  function deadlineMs(round) {
    return round?.phase_deadline ? new Date(round.phase_deadline).getTime() : 0;
  }

  function pipGrid(face = {}) {
    const red = new Set(Array.isArray(face.r) ? face.r.map(Number) : []);
    const white = new Set(Array.isArray(face.w) ? face.w.map(Number) : []);
    return `<span class="half">${Array.from({ length: 9 }, (_, i) => {
      const n = i + 1;
      if (!red.has(n) && !white.has(n)) return '<i></i>';
      return `<i class="pip ${red.has(n) ? 'red' : ''}"></i>`;
    }).join('')}</span>`;
  }

  function tileHtml(tile, options = {}) {
    const { big = false, selectable = false, selected = false, index = -1, hidden = false } = options;
    if (hidden || !tile) {
      return `<button type="button" class="tile3d ${big ? 'big' : ''}" disabled aria-label="暗牌"><span class="tile-face tile-back">九</span></button>`;
    }
    const face = tile.face && typeof tile.face === 'object' ? tile.face : {};
    return `<button type="button" class="tile3d flipped ${big ? 'big' : ''} ${selectable ? 'selectable' : ''} ${selected ? 'head-selected' : ''}" ${selectable ? `data-head-index="${index}"` : 'disabled'} aria-label="${esc(tile.name)}">
      <span class="tile-face tile-back">九</span>
      <span class="tile-face tile-front">${pipGrid(face.top)}${pipGrid(face.bottom)}<small class="tile-name">${esc(tile.name)}</small></span>
    </button>`;
  }

  function pairValue(cards) {
    if (!Array.isArray(cards) || cards.length !== 2) return { score: -1, label: '未成牌' };
    const [a, b] = cards;
    const supreme = a.pair_key === 'gee' && b.pair_key === 'gee' && a.code !== b.code;
    const points = (Number(a.pips) + Number(b.pips)) % 10;
    if (supreme) return { score: 100000, label: '至尊宝' };
    if (a.pair_key === b.pair_key && a.pair_key !== 'gee') {
      return { score: 90000 + Math.max(a.pair_rank, b.pair_rank) * 100, label: `${a.name}对` };
    }
    const honor = [a, b].find(t => t.key === 'teen' || t.key === 'day');
    const mate = honor ? (honor === a ? b : a) : null;
    if (honor && mate.pips === 9) return { score: 80000 + (honor.key === 'teen' ? 200 : 100), label: honor.key === 'teen' ? '天王' : '地王' };
    if (honor && mate.pips === 8) return { score: 70000 + (honor.key === 'teen' ? 200 : 100), label: honor.key === 'teen' ? '天杠' : '地杠' };
    if (honor && mate.pips === 7) return { score: 60000 + (honor.key === 'teen' ? 200 : 100), label: honor.key === 'teen' ? '天高九' : '地高九' };
    return { score: points === 0 ? 0 : points * 1000 + Math.max(a.single_rank, b.single_rank) * 10, label: `${points}点` };
  }

  function splitValue(cards, head) {
    const tail = [0, 1, 2, 3].filter(i => !head.includes(i));
    const h = pairValue(head.map(i => cards[i]));
    const t = pairValue(tail.map(i => cards[i]));
    return { head, tail, h, t, valid: h.score <= t.score };
  }

  function recommend(cards) {
    const candidates = [[0, 1], [0, 2], [0, 3]].map(head => {
      let value = splitValue(cards, head);
      if (!value.valid) value = splitValue(cards, value.tail);
      return value;
    });
    return candidates.sort((a, b) => b.h.score - a.h.score || b.t.score - a.t.score)[0]?.head || [0, 1];
  }

  function errorHtml() {
    return state.lastError ? `<div class="pg-inline-error">${esc(state.lastError)}</div>` : '';
  }

  function casinoHeaderHtml(title, subtitle, seal = '赌') {
    const lobby = state.lobby;
    const balances = lobby?.balances || {};
    return `<header class="casino-head">
      <div class="casino-title"><span class="seal">${esc(seal)}</span><div><h1>${esc(title)}</h1><p>${esc(subtitle)}</p></div></div>
      <div class="casino-balance">灵石 <b>${fmt(balances.spirit_stone)}</b> · 修为 <b>${fmt(balances.cultivation)}</b>
        <span class="fund-line">赌场资金池：灵石 <b>${fmt(lobby?.bankrolls?.spirit_stone)}</b> · 修为 <b>${fmt(lobby?.bankrolls?.cultivation)}</b></span>
      </div>
    </header>`;
  }

  function checked(value, expected) {
    return value === expected ? 'checked' : '';
  }

  function createFormHtml() {
    const draft = state.createDraft;
    return `<form id="createRoomForm" class="create-body">
      <div class="form-block">
        <span class="form-label">对局类型</span>
        <div class="choice-grid">
          <label class="choice"><input type="radio" name="duelType" value="laohe" ${checked(draft.duelType, 'laohe')}><span>老何 VS 玩家<br>老何固定庄</span></label>
          <label class="choice"><input type="radio" name="duelType" value="pvp" ${checked(draft.duelType, 'pvp')}><span>玩家 VS 玩家<br>自由牌局</span></label>
        </div>
      </div>
      <div id="pvpModeBlock" class="form-block">
        <span class="form-label">玩家局模式</span>
        <div class="choice-grid">
          <label class="choice"><input type="radio" name="pvpMode" value="rob" ${checked(draft.pvpMode, 'rob')}><span>随机抢庄</span></label>
          <label class="choice"><input type="radio" name="pvpMode" value="boat" ${checked(draft.pvpMode, 'boat')}><span>开船模式</span></label>
        </div>
      </div>
      <div class="form-block">
        <span class="form-label">游戏玩法</span>
        <div class="choice-grid">
          <label class="choice"><input type="radio" name="game" value="small" ${checked(draft.game, 'small')}><span>牌九<br>两牌玩法</span></label>
          <label class="choice"><input type="radio" name="game" value="big" ${checked(draft.game, 'big')}><span>大牌九<br>四牌分头尾</span></label>
        </div>
      </div>
      <div class="form-block">
        <span class="form-label">下注资源</span>
        <div class="choice-grid">
          <label class="choice"><input type="radio" name="stake" value="spirit_stone" ${checked(draft.stake, 'spirit_stone')}><span>灵石</span></label>
          <label class="choice"><input type="radio" name="stake" value="cultivation" ${checked(draft.stake, 'cultivation')}><span>修为</span></label>
        </div>
      </div>
      <div class="form-block">
        <label class="form-label" for="baseBetInput">自定义底注</label>
        <div class="base-bet-wrap"><input id="baseBetInput" name="base" type="number" inputmode="numeric" min="10" step="1" value="${esc(draft.base)}" required autocomplete="off"><div id="currencyPreview" class="currency-preview">灵石</div></div>
      </div>
      <div id="createRulePreview" class="rule-preview">玩家局每笔确认赌注收取2.5%手续费；赌注与手续费合计不得超过开局余额30%。</div>
      <button class="create-submit" type="submit">创建房间</button>
    </form>`;
  }

  function roomCardHtml(room, index) {
    const titles = ['天字一号房', '地字二号房', '玄字三号房', '黄字四号房'];
    if (!room) {
      return `<article class="room-card empty-room-card"><div class="room-title-row"><h3>${titles[index]}</h3><span class="room-status">空闲</span></div><div class="room-rule">当前空闲。创建后20分钟仍未开始首局会自动关闭并释放房名。</div></article>`;
    }
    const expires = room.expires_at ? new Date(room.expires_at).getTime() : 0;
    return `<article class="room-card ${room.status === 'playing' ? 'started' : ''}">
      <div class="room-title-row"><h3>${esc(room.name)}</h3><span class="room-status ${room.status === 'playing' ? 'playing' : ''}">${room.status === 'playing' ? '对局中' : '等待中'}</span></div>
      <div class="room-tags"><span class="room-tag">${duelLabel(room)}</span><span class="room-tag gold">${gameLabel(room)}</span><span class="room-tag">${currencyLabel(room.stake_type)}底注${fmt(room.base_stake)}</span></div>
      <div class="room-rule">${room.players}/${room.capacity}人入座 · ${room.spectators}人观战。${room.status === 'playing' ? '当前牌局正在进行，可进入观战。' : '入座后准备，由房主开始本局。'}</div>
      <div class="room-foot"><span class="room-countdown" ${expires ? `data-deadline-long="${expires}"` : ''}>${room.status === 'playing' ? '牌局已开始' : '首局倒计时'}</span><div class="room-actions"><button class="enter-room" type="button" data-open-room="${room.id}">${room.joined ? '返回房间' : room.status === 'playing' ? '进入观战' : '选择座位'}</button></div></div>
    </article>`;
  }

  function lobbyHtml() {
    const rooms = state.lobby?.rooms || [];
    const slots = [1, 2, 3, 4].map(slot => rooms.find(room => Number(room.slot_no) === slot));
    return `<section class="view-shell">
      ${casinoHeaderHtml('九霄赌坊 · 九霄牌九', '创建房间、选座入局、老何庄／抢庄／开船')}
      ${errorHtml()}
      <div class="lobby-grid">
        <section class="lobby-panel"><div class="lobby-panel-head"><h2>创建牌局</h2><span>${rooms.length} / 4 房</span></div>${createFormHtml()}</section>
        <section class="lobby-panel"><div class="lobby-panel-head"><h2>天地玄黄房</h2><button class="secondary-btn" type="button" data-refresh-lobby>刷新状态</button></div><div class="room-list-body"><div class="room-grid">${slots.map(roomCardHtml).join('')}</div>
          <div class="lobby-notes"><div class="lobby-note"><b>自动关闭</b>创建后20分钟仍未开始第一局，房间自动关闭并释放房名。</div><div class="lobby-note"><b>老何固定庄</b>输赢按100∶100等额结算，使用现有赌场资金池。</div><div class="lobby-note"><b>玩家牌局扣点</b>随机抢庄与开船均按确认赌注收取2.5%赌场收入。</div></div>
        </div></section>
      </div>
    </section>`;
  }

  function roomCapacity(room) {
    return room.game_mode === 'big' ? (room.duel_type === 'laohe' ? 7 : 8) : 9;
  }

  function seatNodesHtml(data) {
    const room = data.room;
    const members = data.members || [];
    const roundPlayers = new Map((data.round?.players || []).map(player => [player.character_id, player]));
    const bySeat = new Map(members.filter(member => member.role === 'player').map(member => [Number(member.seat_no), member]));
    const capacity = roomCapacity(room);
    return Array.from({ length: 9 }, (_, i) => i + 1).map(seat => {
      const member = bySeat.get(seat);
      const player = member ? roundPlayers.get(member.character_id) : null;
      const disabled = seat > capacity || room.status === 'playing';
      if (!member) {
        return `<div class="seat-node seat-pos-${seat} empty ${seat > capacity ? 'standby' : ''}"><button type="button" ${disabled ? 'disabled' : `data-join-seat="${seat}"`}><span class="seat-avatar">${seat}</span><strong>${seat}号席</strong><small>${seat > capacity ? '本模式候补席' : '点击入座'}</small></button></div>`;
      }
      return `<div class="seat-node seat-pos-${seat} ${member.is_self ? 'selected' : ''} ${player?.is_dealer ? 'banker' : ''}">
        ${player?.is_dealer ? '<span class="banker-corner">庄</span>' : ''}<span class="seat-avatar">${esc(initials(member.name))}</span><strong>${esc(member.name)}</strong><small>${seat}号席${member.is_owner ? ' · 房主' : ''}</small><small class="${member.ready ? 'is-ready' : ''}">${member.ready ? '已准备' : '未准备'}</small>
      </div>`;
    }).join('');
  }

  function waitingControlsHtml(data) {
    const self = data.self_member;
    const room = data.room;
    const controls = [];
    if (!self) controls.push('<button class="seat-enter" type="button" data-watch>以观战身份进入</button>');
    if (self?.role === 'player' && room.status === 'waiting') {
      controls.push(`<button class="seat-enter" type="button" data-ready="${self.ready ? 'false' : 'true'}">${self.ready ? '取消准备' : '确认准备'}</button>`);
    }
    if (self?.is_owner && room.status === 'waiting') controls.push('<button class="seat-enter start-round" type="button" data-start>开始本局</button>');
    controls.push('<button class="seat-back" type="button" data-refresh-room>刷新状态</button>');
    if (self && room.status === 'waiting') controls.push('<button class="seat-back danger-text" type="button" data-leave>离开房间</button>');
    controls.push('<button class="seat-back" type="button" data-back-lobby>返回房间大厅</button>');
    return controls.join('');
  }

  function seatViewHtml(data) {
    const room = data.room;
    const members = data.members || [];
    const players = members.filter(m => m.role === 'player');
    const self = data.self_member;
    return `<section class="view-shell">
      ${casinoHeaderHtml(room.room_name, '请选择空位入座；自己的座位进入牌局后自动位于牌桌下方', '席')}
      ${errorHtml()}
      <section class="seat-shell">
        <div class="seat-head"><div><h2>选择桌位</h2><p>${duelLabel(room)} · ${gameLabel(room)} · ${currencyLabel(room.stake_type)}底注${fmt(room.base_stake)}</p></div><span class="room-status">${players.length} / ${roomCapacity(room)}</span></div>
        <div class="seat-content">
          <div class="seat-table" aria-label="九席选座">${seatNodesHtml(data)}<div class="seat-table-center"><strong>九霄牌九</strong><small>${gameLabel(room)}</small></div></div>
          <aside class="seat-side">
            <div class="seat-summary"><b>房间规则</b><br>${duelLabel(room)}<br>${gameLabel(room)} · ${currencyLabel(room.stake_type)}底注${fmt(room.base_stake)}<br>当前${players.length}人入座、${members.filter(m => m.role === 'spectator').length}人观战。</div>
            <div class="seat-summary">${self ? `<b>你的身份</b><br>${self.role === 'player' ? `${self.seat_no}号席 · ${self.ready ? '已准备' : '未准备'}` : '观战者'}${self.is_owner ? '<br>你是房主，可在所有玩家准备后开始本局。' : ''}` : '尚未入座，可点击空位或以观战身份进入。'}</div>
            <div class="seat-actions">${waitingControlsHtml(data)}</div>
          </aside>
        </div>
      </section>
    </section>`;
  }

  function visibleCardsHtml(cards, expected, options = {}) {
    const actual = Array.isArray(cards) ? cards : [];
    const result = actual.map((tile, index) => tileHtml(tile, {
      big: options.big,
      selectable: options.selectable,
      selected: state.selectedHead.includes(index),
      index
    }));
    while (result.length < expected) result.push(tileHtml(null, { big: options.big, hidden: true }));
    return result.join('');
  }

  function playerStateText(player, member, round) {
    if (!player) return member?.ready ? '已准备' : '等待开局';
    if (!player.active) return player.fold_reason ? `退出：${player.fold_reason}` : '本局未参与';
    if (round.phase === 'rob') return player.rob_choice == null ? '等待抢庄选择' : player.rob_choice ? '已抢庄' : '不抢庄';
    if (round.phase === 'multiplier') return player.multiplier ? `已选${player.multiplier}倍` : '等待选择倍率';
    if (round.phase === 'arrange') return player.action_confirmed ? '头尾已确定' : '正在组合头尾';
    if (round.phase === 'head_reveal') return '头牌已亮';
    if (round.phase === 'tail_reveal') return '尾牌已亮';
    if (round.phase === 'settled') return player.net_amount >= 0 ? `净胜${fmt(player.net_amount)}` : `净负${fmt(Math.abs(player.net_amount))}`;
    return '牌局进行中';
  }

  function playerSeatHtml(entry, index, data) {
    const { player, member, isLaohe } = entry;
    const side = index % 2 === 0 ? 'left' : 'right';
    const row = `r${Math.floor(index / 2) + 1}`;
    const expected = data.room.game_mode === 'big' ? 4 : 2;
    const cards = isLaohe ? data.round?.laohe?.cards : player?.cards;
    const publicValue = isLaohe ? data.round?.laohe?.public_value : player?.public_value;
    const name = isLaohe ? '老何' : member?.name || player?.name || '无名道友';
    const seat = isLaohe ? '系统庄' : `${member?.seat_no || player?.seat_no || '-'}号席${member?.is_owner ? ' · 房主' : ''}`;
    const dealer = isLaohe || player?.is_dealer;
    const stateText = isLaohe ? '老何固定庄' : playerStateText(player, member, data.round);
    const stake = player?.stake_amount || 0;
    return `<article class="seat ${side} ${row} ${member?.ready ? 'ready' : ''} ${dealer ? 'banker-seat' : ''}">
      ${dealer ? '<span class="banker-corner">庄</span>' : ''}
      <div class="seat-inner ${data.room.game_mode === 'big' ? 'big-seat' : ''}">
        <div class="avatar-wrap"><div class="avatar">${esc(initials(name))}</div>${player?.multiplier ? `<div class="mult-badge show">×${player.multiplier}</div>` : ''}<span class="ready-mark ${member?.ready ? 'show' : ''}">已准备</span></div>
        <div class="info"><strong>${esc(name)}</strong><small>${esc(seat)}</small><div class="stake-line">${currencyLabel(data.room.stake_type)} <b>${stake ? fmt(stake) : '未下注'}</b></div><div class="state-line ${member?.ready ? 'is-ready' : ''}">${esc(stateText)}</div>${publicValue?.label ? `<div class="pair-type-label">${esc(publicValue.label)}</div>` : ''}</div>
        <div class="mini-cards ${data.room.game_mode === 'big' ? 'big-four' : 'small-pair-hand'}">${visibleCardsHtml(cards, expected)}</div>
      </div>
    </article>`;
  }

  function actionPanelHtml(data, selfPlayer) {
    const room = data.room;
    const round = data.round;
    const selfMember = data.self_member;
    const deadline = deadlineMs(round);
    const countdown = deadline ? `<span class="countdown-inline" data-deadline="${deadline}">--</span>` : '';

    if (!selfMember || selfMember.role !== 'player') {
      return `<div class="phase-title">观战中 ${countdown}</div><div class="ready-note">你以观战身份进入，私牌与牌堆不会向客户端公开。</div>`;
    }

    if (room.status === 'waiting' && (!round || ['settled', 'cancelled'].includes(round.phase))) {
      return `<div class="phase-title">等待下一局</div>
        <button class="primary-btn" type="button" data-ready="${selfMember.ready ? 'false' : 'true'}">${selfMember.ready ? '取消准备' : '准备入局'}</button>
        ${selfMember.is_owner ? '<button class="ghost-btn" type="button" data-start>开始本局</button>' : ''}`;
    }

    if (round?.phase === 'rob' && selfPlayer?.active && selfPlayer.rob_choice == null) {
      return `<div class="phase-title">随机抢庄 ${countdown}</div><div class="banker-actions inline-banker"><button class="grab" type="button" data-rob="true">抢庄</button><button type="button" data-rob="false">不抢庄</button></div>`;
    }

    if (round?.phase === 'multiplier' && selfPlayer?.active && !selfPlayer.action_confirmed && !selfPlayer.is_dealer) {
      return `<div class="phase-title">请选择倍率 ${countdown}</div><div class="mult-grid"><button class="multiplier-btn" data-multiplier="10" type="button">10倍</button><button class="multiplier-btn" data-multiplier="50" type="button">50倍</button><button class="multiplier-btn" data-multiplier="100" type="button">100倍</button></div><div class="ready-note">超时默认10倍。赌注与手续费合计不得超过开局余额30%。</div>`;
    }

    if (round?.phase === 'arrange' && selfPlayer?.active && !selfPlayer.action_confirmed) {
      const cards = selfPlayer.cards || [];
      let copy = `请选择两张较弱牌作为头牌 ${countdown}`;
      let summary = '尚未选择两张头牌';
      let legal = false;
      if (state.selectedHead.length === 2 && cards.length === 4) {
        const split = splitValue(cards, state.selectedHead);
        legal = split.valid;
        summary = `头牌：${split.h.label} · 尾牌：${split.t.label}`;
        copy = legal ? `组合合法 ${countdown}` : `头牌强于尾牌，不能提交 ${countdown}`;
      }
      return `<div class="phase-title">${copy}</div><div class="split-summary"><div class="split-box">当前组合<b>${esc(summary)}</b></div></div><div class="split-actions"><button class="recommend-btn" type="button" data-recommend>系统推荐出牌</button><button class="confirm-split-btn" type="button" data-confirm-head ${legal ? '' : 'disabled'}>确定头尾并准备</button></div>`;
    }

    return `<div class="phase-title">${phaseLabel(round?.phase)} ${countdown}</div><div class="ready-note">${round?.phase === 'head_reveal' ? '较弱头牌已经亮出，等待统一揭示强尾。' : round?.phase === 'tail_reveal' ? '强尾已经亮出，正在等待服务端结算。' : round?.phase === 'settled' ? '本局已经完成结算。' : '等待其他玩家完成当前阶段。'}</div>`;
  }

  function selfZoneHtml(data) {
    const round = data.round;
    const selfMember = data.self_member;
    const selfPlayer = (round?.players || []).find(player => player.is_self);
    const expected = data.room.game_mode === 'big' ? 4 : 2;
    const arranging = round?.phase === 'arrange' && selfPlayer?.active && !selfPlayer.action_confirmed;
    const cards = selfPlayer?.cards || [];
    const selectableCards = cards.map((tile, index) => tileHtml(tile, {
      big: true,
      selectable: arranging,
      selected: state.selectedHead.includes(index),
      index
    })).join('');
    const hidden = Array.from({ length: Math.max(0, expected - cards.length) }, () => tileHtml(null, { big: true, hidden: true })).join('');
    const name = (data.members || []).find(m => m.is_self)?.name || '观战者';
    const result = selfPlayer && round?.phase === 'settled'
      ? `<div class="self-card-note ${selfPlayer.net_amount >= 0 ? 'positive' : 'negative'}">本局净胜负：${selfPlayer.net_amount >= 0 ? '+' : ''}${fmt(selfPlayer.net_amount)}</div>`
      : `<div class="self-card-note">${selfPlayer?.public_value?.label ? esc(selfPlayer.public_value.label) : arranging ? '点选两张作为较弱头牌' : cards.length ? '你的可见牌面' : '牌面尚未发放'}</div>`;
    return `<section class="self-zone ${data.room.game_mode === 'big' ? 'big-mode-zone' : ''}">
      ${selfPlayer?.is_dealer ? '<span class="banker-corner">庄</span>' : ''}
      <div class="self-grid"><div class="self-id"><div class="avatar">${esc(initials(name))}</div><strong>${esc(name)}</strong><small>${selfMember?.role === 'player' ? `${selfMember.seat_no}号席${selfMember.is_owner ? ' · 房主' : ''}` : '观战身份'}</small><span class="self-stake">${selfPlayer?.stake_amount ? `已押 ${fmt(selfPlayer.stake_amount)} ${currencyLabel(data.room.stake_type)}` : '尚未下注'}</span></div>
      <div><div class="self-cards ${data.room.game_mode === 'big' ? 'big-hand' : ''}">${selectableCards}${hidden}</div>${result}</div>
      <div class="action-panel">${actionPanelHtml(data, selfPlayer)}</div></div>
    </section>`;
  }

  function metricsHtml(data) {
    const round = data.round;
    const players = round?.players || [];
    const self = players.find(player => player.is_self);
    const pot = players.reduce((sum, player) => sum + Number(player.stake_amount || 0), 0);
    const fees = players.reduce((sum, player) => sum + Number(player.fee_amount || 0), 0);
    const ready = (data.members || []).filter(member => member.role === 'player' && member.ready).length;
    const total = (data.members || []).filter(member => member.role === 'player').length;
    const dealer = round?.laohe ? '老何' : players.find(player => player.is_dealer)?.name || '未定';
    return `<div class="metric-grid"><div class="metric"><span>你的${currencyLabel(data.room.stake_type)}</span><strong>${fmt(data.self_balance)}</strong></div><div class="metric"><span>当前总池</span><strong>${fmt(pot)}</strong></div><div class="metric"><span>已准备</span><strong>${ready}/${total}</strong></div><div class="metric"><span>你的净胜负</span><strong class="${Number(self?.net_amount || 0) >= 0 ? 'positive' : 'negative'}">${Number(self?.net_amount || 0) >= 0 ? '+' : ''}${fmt(self?.net_amount || 0)}</strong></div><div class="metric"><span>当前庄家</span><strong>${esc(dealer)}</strong></div><div class="metric"><span>本局手续费</span><strong>${fmt(fees)}</strong></div></div>`;
  }

  function rankHtml(data) {
    const round = data.round;
    if (!round || round.phase !== 'settled') return '<div class="log-row">开牌结算后显示排名与净胜负。</div>';
    const players = [...(round.players || [])].sort((a, b) => Number(b.net_amount || 0) - Number(a.net_amount || 0));
    return players.map((player, index) => `<div class="rank-row ${Number(player.net_amount || 0) > 0 ? 'stage-win' : ''}"><span class="rank-no">${index + 1}</span><span>${esc(player.name)}<small>${player.public_value?.label ? esc(player.public_value.label) : '已结算'}</small></span><b class="${Number(player.net_amount || 0) >= 0 ? 'positive' : 'negative'}">${Number(player.net_amount || 0) >= 0 ? '+' : ''}${fmt(player.net_amount || 0)}</b></div>`).join('');
  }

  function logHtml(data) {
    const round = data.round;
    const rows = [];
    if (!round) rows.push('房间已经创建，等待玩家入座准备。');
    else {
      rows.push(`第${round.round_no}局：${phaseLabel(round.phase)}。`);
      if (round.dealer_character_id || round.laohe) rows.push(`庄家：${round.laohe ? '老何' : (round.players || []).find(p => p.is_dealer)?.name || '已确定'}。`);
      const confirmed = (round.players || []).filter(p => p.action_confirmed).length;
      if (confirmed) rows.push(`${confirmed}名玩家已确认当前阶段动作。`);
      if (round.phase === 'settled') rows.push('服务端已完成整桌原子结算。');
    }
    return rows.map(text => `<div class="log-row"><time>·</time>${esc(text)}</div>`).join('');
  }

  function gameViewHtml(data) {
    const room = data.room;
    const round = data.round;
    const members = data.members || [];
    const memberById = new Map(members.map(member => [member.character_id, member]));
    const selfPlayer = (round?.players || []).find(player => player.is_self);
    const opponents = [];
    if (round?.laohe) opponents.push({ isLaohe: true, player: null, member: null });
    (round?.players || []).filter(player => !player.is_self).forEach(player => opponents.push({ player, member: memberById.get(player.character_id), isLaohe: false }));
    if (!round) members.filter(member => member.role === 'player' && !member.is_self).forEach(member => opponents.push({ player: null, member, isLaohe: false }));
    const padded = opponents.slice(0, 8);
    while (padded.length < 8) padded.push({ player: null, member: null, isLaohe: false, empty: true });
    const opponentsHtml = padded.map((entry, index) => entry.empty
      ? `<article class="seat ${index % 2 === 0 ? 'left' : 'right'} r${Math.floor(index / 2) + 1} standby"><div class="seat-inner"><div class="avatar-wrap"><div class="avatar">空</div></div><div class="info"><strong>空席</strong><small>等待道友</small><div class="state-line">暂无玩家</div></div><div class="mini-cards"></div></div></article>`
      : playerSeatHtml(entry, index, data)).join('');
    const deadline = deadlineMs(round);
    return `<section id="gameView">
      <header class="topbar"><div class="brand"><button class="back-btn" type="button" data-back-lobby aria-label="返回房间大厅">×</button><span class="brand-seal">道</span><div class="brand-copy"><strong>${esc(room.room_name)} · ${duelShort(room)}</strong><small>${gameLabel(room)} · 传统32张骨牌 · 服务端权威结算 · V1.2 FIX3 CACHE40</small></div></div><div class="top-actions"><span class="balance-chip">${currencyLabel(room.stake_type)} <b>${fmt(data.self_balance)}</b></span><button class="menu-btn" type="button" data-refresh-room aria-label="刷新">↻</button></div></header>
      ${errorHtml()}
      <main class="app-shell"><section class="room-strip"><strong>${esc(room.room_name)}</strong><div class="mode-switch room-locked"><button class="mode-btn ${room.game_mode === 'small' ? 'active' : ''}" disabled>小牌九</button><button class="mode-btn ${room.game_mode === 'big' ? 'active' : ''}" disabled>大牌九</button></div><div class="room-quick-actions"><button type="button" data-refresh-room>刷新状态</button>${room.status === 'waiting' && data.self_member?.is_owner ? '<button class="primary-mini" type="button" data-start>开始本局</button>' : ''}</div><div class="room-meta"><span>底注 <b>${fmt(room.base_stake)}${currencyLabel(room.stake_type)}</b></span><span>席位 <b>${members.filter(m => m.role === 'player').length}/${roomCapacity(room)}</b></span><span>局数 <b>${round?.round_no || 0}</b></span><span>阶段 <b>${phaseLabel(round?.phase)}</b></span>${deadline ? `<span>倒计时 <b data-deadline="${deadline}">--</b></span>` : ''}<span class="room-locked-note">${duelLabel(room)}</span></div></section>
      <div class="layout"><section class="board-frame" aria-label="九霄牌九桌"><div class="felt"><div id="opponentSeats">${opponentsHtml}</div>${selfZoneHtml(data)}</div></section><aside class="side-stack"><section class="panel"><div class="panel-head"><h3>本局概览</h3><span>${gameLabel(room)}</span></div><div class="panel-body">${metricsHtml(data)}</div></section><section class="panel"><div class="panel-head"><h3>开牌排名</h3><span>按服务端结果</span></div><div class="panel-body"><div class="rank-list">${rankHtml(data)}</div></div></section><section class="panel"><div class="panel-head"><h3>牌局动态</h3><span>当前状态</span></div><div class="panel-body"><div class="log-list">${logHtml(data)}</div></div></section><section class="panel"><div class="panel-head"><h3>玩法说明</h3><span>${duelLabel(room)}</span></div><div class="panel-body rule-note"><b>老何庄：</b>100∶100等额结算，直接使用现有赌场资金。<br><b>玩家局：</b>每笔确认赌注收取2.5%手续费，庄家责任资金预先冻结，系统不兜底。<br><b>倍率：</b>10、50、100倍；赌注与手续费合计不得超过开局余额30%。<br><b>安全：</b>洗牌、私牌遮罩、阶段截止与资金结算均由数据库完成。</div></section></aside></div>
      <div class="game-footer-actions"><button class="secondary-btn" type="button" data-refresh-room>刷新状态</button>${data.self_member && room.status === 'waiting' ? '<button class="secondary-btn danger-text" type="button" data-leave>离开房间</button>' : ''}</div></main>
    </section>`;
  }

  function roomHtml() {
    if (!state.room?.room) return '<div class="loading-screen">正在进入房间……</div>';
    const hasRound = Boolean(state.room.round);
    const self = state.room.self_member;
    const needsSeatView = !hasRound || (state.room.room.status === 'waiting' && (!self || self.role !== 'player'));
    return needsSeatView ? seatViewHtml(state.room) : gameViewHtml(state.room);
  }

  function render() {
    let nextHtml = '';
    if (!session()?.access_token) {
      nextHtml = '<section class="loading-screen"><h2>需要登录</h2><p>请关闭九霄灵牌，先在主界面登录游戏。</p></section>';
    } else if (state.roomId && state.room) {
      nextHtml = roomHtml();
    } else if (state.lobby) {
      nextHtml = lobbyHtml();
    } else {
      nextHtml = '<section class="loading-screen">正在连接九霄灵牌……</section>';
    }

    if (state.renderHtml !== nextHtml) {
      const scrollX = window.scrollX;
      const scrollY = window.scrollY;
      app.innerHTML = nextHtml;
      state.renderHtml = nextHtml;
      requestAnimationFrame(() => window.scrollTo(scrollX, scrollY));
    }
    updateCountdown();
    syncCreateForm();
  }

  function updateCountdown() {
    document.querySelectorAll('[data-deadline]').forEach(el => {
      const seconds = Math.max(0, Math.ceil((Number(el.dataset.deadline) - Date.now()) / 1000));
      el.textContent = `${seconds}秒`;
    });
    document.querySelectorAll('[data-deadline-long]').forEach(el => {
      const seconds = Math.max(0, Math.ceil((Number(el.dataset.deadlineLong) - Date.now()) / 1000));
      const minutes = Math.floor(seconds / 60);
      const rest = seconds % 60;
      el.textContent = seconds > 0 ? `首局倒计时 ${minutes}:${String(rest).padStart(2, '0')}` : '即将自动关闭';
      el.classList.toggle('expiring', seconds <= 180);
    });
  }

  function captureCreateDraft(form) {
    if (!form) return;
    state.createDraft = {
      duelType: form.querySelector('input[name="duelType"]:checked')?.value || state.createDraft.duelType,
      pvpMode: form.querySelector('input[name="pvpMode"]:checked')?.value || state.createDraft.pvpMode,
      game: form.querySelector('input[name="game"]:checked')?.value || state.createDraft.game,
      stake: form.querySelector('input[name="stake"]:checked')?.value || state.createDraft.stake,
      base: form.elements.base?.value ?? state.createDraft.base
    };
  }

  function syncCreateForm({ normalizeBase = false } = {}) {
    const form = document.getElementById('createRoomForm');
    if (!form) return;
    const duel = form.querySelector('input[name="duelType"]:checked')?.value || state.createDraft.duelType;
    const stake = form.querySelector('input[name="stake"]:checked')?.value || state.createDraft.stake;
    const pvp = document.getElementById('pvpModeBlock');
    if (pvp) pvp.hidden = duel === 'laohe';
    const base = form.elements.base;
    const cultivation = stake === 'cultivation';
    if (base) {
      base.min = cultivation ? '5000' : '10';
      base.step = '1';
      if (normalizeBase && (!base.value || Number(base.value) < Number(base.min))) {
        base.value = base.min;
        state.createDraft.base = base.value;
      }
    }
    const preview = document.getElementById('currencyPreview');
    if (preview) preview.textContent = cultivation ? '修为' : '灵石';
    const rule = document.getElementById('createRulePreview');
    if (rule) rule.innerHTML = duel === 'laohe'
      ? '<b>老何固定庄：</b>玩家与老何按100∶100等额结算，输赢直接进入现有赌场资金池。'
      : '<b>玩家牌局：</b>每笔确认赌注收取2.5%手续费；赌注与手续费合计不得超过开局余额30%。';
  }

  async function loadLobby() {
    state.lobby = await rpc('get_paigow_lobby_bpaigow01');
    if (state.lobby.status !== 'active') throw new Error('PAIGOW_DISABLED');
    render();
  }

  async function loadRoom(advance = false) {
    if (!state.roomId) return;
    state.room = advance
      ? await rpc('advance_paigow_round_bpaigow01', { p_room_id: state.roomId })
      : await rpc('get_paigow_room_state_bpaigow01', { p_room_id: state.roomId });
    if (!state.lobby) await loadLobby();
    else {
      state.lobby.balances[state.room.room.stake_type] = state.room.self_balance;
      state.lobby.bankrolls[state.room.room.stake_type] = state.room.bankroll_balance;
    }
    const self = state.room.round?.players?.find(player => player.is_self);
    if (state.room.round?.phase === 'arrange' && self?.cards?.length === 4 && state.selectedHead.length !== 2) {
      state.selectedHead = recommend(self.cards);
    }
    render();
  }

  async function pollOnce() {
    if (state.busy || state.polling) return;
    state.polling = true;
    try {
      state.lastError = '';
      if (state.roomId) await loadRoom(true);
      else await loadLobby();
    } catch (error) {
      const message = errorText(error);
      if (message !== state.lastError) toast(message);
      state.lastError = message;
      render();
    } finally {
      state.polling = false;
    }
  }

  function startPolling() {
    clearInterval(state.poll);
    clearInterval(state.clock);
    state.poll = setInterval(pollOnce, state.roomId ? 2000 : 5000);
    state.clock = setInterval(updateCountdown, 250);
  }

  function openRoom(id) {
    state.roomId = id;
    state.room = null;
    state.selectedHead = [];
    render();
    action(async () => {
      await loadRoom(true);
      startPolling();
    });
  }

  app.addEventListener('click', event => {
    const target = event.target.closest('button');
    if (!target) return;
    if (target.dataset.openRoom) return openRoom(target.dataset.openRoom);
    if (target.hasAttribute('data-refresh-lobby')) return action(loadLobby);
    if (target.hasAttribute('data-refresh-room')) return action(() => loadRoom(true));
    if (target.hasAttribute('data-back-lobby')) {
      state.roomId = null;
      state.room = null;
      state.selectedHead = [];
      startPolling();
      return action(loadLobby);
    }
    if (target.dataset.joinSeat) {
      return action(async () => {
        state.room = await rpc('join_paigow_room_bpaigow01', {
          p_room_id: state.roomId,
          p_seat_no: Number(target.dataset.joinSeat),
          p_spectator: false
        });
      });
    }
    if (target.hasAttribute('data-watch')) {
      return action(async () => {
        state.room = await rpc('join_paigow_room_bpaigow01', {
          p_room_id: state.roomId,
          p_seat_no: null,
          p_spectator: true
        });
      });
    }
    if (target.dataset.ready) {
      return action(async () => {
        state.room = await rpc('set_paigow_ready_bpaigow01', {
          p_room_id: state.roomId,
          p_ready: target.dataset.ready === 'true'
        });
      });
    }
    if (target.hasAttribute('data-start')) {
      return action(async () => {
        state.room = await rpc('start_paigow_round_bpaigow01', {
          p_room_id: state.roomId,
          p_request_id: uuid()
        });
      });
    }
    if (target.dataset.rob) {
      return action(async () => {
        state.room = await rpc('choose_paigow_rob_bpaigow01', {
          p_room_id: state.roomId,
          p_rob: target.dataset.rob === 'true',
          p_request_id: uuid()
        });
      });
    }
    if (target.dataset.multiplier) {
      return action(async () => {
        state.room = await rpc('choose_paigow_multiplier_bpaigow01', {
          p_room_id: state.roomId,
          p_multiplier: Number(target.dataset.multiplier),
          p_request_id: uuid()
        });
      });
    }
    if (target.dataset.headIndex != null) {
      const index = Number(target.dataset.headIndex);
      state.selectedHead = state.selectedHead.includes(index)
        ? state.selectedHead.filter(i => i !== index)
        : state.selectedHead.length < 2
          ? [...state.selectedHead, index]
          : [state.selectedHead[1], index];
      return render();
    }
    if (target.hasAttribute('data-recommend')) {
      const self = state.room?.round?.players?.find(player => player.is_self);
      if (self?.cards?.length === 4) state.selectedHead = recommend(self.cards);
      return render();
    }
    if (target.hasAttribute('data-confirm-head')) {
      return action(async () => {
        if (state.selectedHead.length !== 2) throw new Error('请选择两张头牌');
        state.room = await rpc('arrange_paigow_big_bpaigow01', {
          p_room_id: state.roomId,
          p_head_indices: state.selectedHead,
          p_request_id: uuid()
        });
      });
    }
    if (target.hasAttribute('data-leave')) {
      return action(async () => {
        await rpc('leave_paigow_room_bpaigow01', { p_room_id: state.roomId });
        state.roomId = null;
        state.room = null;
        await loadLobby();
        startPolling();
      });
    }
  });

  app.addEventListener('input', event => {
    const form = event.target.closest('#createRoomForm');
    if (!form) return;
    captureCreateDraft(form);
    syncCreateForm();
  });

  app.addEventListener('change', event => {
    const form = event.target.closest('#createRoomForm');
    if (!form) return;
    captureCreateDraft(form);
    syncCreateForm({ normalizeBase: event.target.name === 'stake' });
  });

  app.addEventListener('submit', event => {
    if (event.target.id !== 'createRoomForm') return;
    event.preventDefault();
    captureCreateDraft(event.target);
    const form = new FormData(event.target);
    const duelType = form.get('duelType');
    const stake = form.get('stake');
    const pvpMode = duelType === 'laohe' ? null : form.get('pvpMode');
    action(async () => {
      const result = await rpc('create_paigow_room_bpaigow01', {
        p_duel_type: duelType,
        p_pvp_mode: pvpMode,
        p_game_mode: form.get('game'),
        p_stake_type: stake,
        p_base_stake: Number(form.get('base'))
      });
      const id = result?.room?.id || result?.state?.room?.id;
      if (!id) throw new Error('房间创建结果异常');
      state.roomId = id;
      state.room = result.state || await rpc('get_paigow_room_state_bpaigow01', { p_room_id: id });
      startPolling();
    });
  });

  window.addEventListener('message', event => {
    if (event.data?.type === 'b-paigow01-refresh') action(() => state.roomId ? loadRoom(true) : loadLobby());
  });
  window.addEventListener('beforeunload', () => {
    clearInterval(state.poll);
    clearInterval(state.clock);
  });

  render();
  action(async () => {
    await loadLobby();
    startPolling();
  });
})();
