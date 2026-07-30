(() => {
  'use strict';
  const cfg = window.GAME_CONFIG || {};
  const url = String(cfg.supabaseUrl || '').replace(/\/+$/, '');
  const key = String(cfg.supabasePublishableKey || '');
  const project = (() => { try { return new URL(url).hostname.split('.')[0]; } catch { return 'unknown'; } })();
  const sessionKey = `nine_cloud_dao_session_${project}_v1`;
  const app = document.getElementById('paigowApp');
  const toastEl = document.getElementById('pgToast');
  const state = { lobby: null, room: null, roomId: null, busy: false, selectedHead: [], poll: null, clock: null, lastError: '' };

  const esc = value => String(value ?? '').replace(/[&<>"']/g, char => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#039;'}[char]));
  const fmt = value => Number(value || 0).toLocaleString('zh-CN');
  const uuid = () => globalThis.crypto?.randomUUID?.() || 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => { const r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16); });
  function session() { try { return JSON.parse(localStorage.getItem(sessionKey) || 'null'); } catch { return null; } }
  function toast(message) { toastEl.textContent = message; toastEl.classList.add('show'); clearTimeout(toast.timer); toast.timer = setTimeout(() => toastEl.classList.remove('show'), 2600); }
  function errorText(error) {
    const raw = String(error?.message || error || '未知错误');
    const map = [
      ['PAIGOW_DISABLED','九霄灵牌当前处于维护状态。'],['AUTH_REQUIRED','登录状态已失效，请返回主界面重新登录。'],
      ['PAIGOW_ROOM_LIMIT_REACHED','天地玄黄四间房已经全部开放。'],['PAIGOW_BASE_STAKE_INVALID','底注不符合当前资源的最低要求。'],['PAIGOW_SEAT_OCCUPIED','该座位刚被其他修士选中。'],
      ['PAIGOW_PLAYERS_NOT_READY','仍有入座玩家尚未准备。'],['PAIGOW_NOT_ENOUGH_PLAYERS','当前参战人数不足。'],
      ['PAIGOW_ONLY_OWNER_STARTS','只有房主可以开始本局。'],['PAIGOW_STAKE_EXCEEDS_THIRTY_PERCENT_OR_BALANCE','本局赌注和手续费超过开局余额30%或余额不足。'],
      ['PAIGOW_DEALER_LIABILITY_LIMIT','庄家30%责任资金不足，请降低倍率。'],['PAIGOW_HEAD_MUST_NOT_EXCEED_TAIL','头牌必须弱于或等于尾牌。'],
      ['PAIGOW_CANNOT_LEAVE_ACTIVE_ROUND','进行中的参战玩家不能离房。'],['CASINO_CULTIVATION_REQUIRES_NASCENT_SOUL','修为局仅对元婴期及以上开放。'],
      ['CULTIVATION_STAKE_MINIMUM','修为下注额不足最低限制。'],['CASINO_INSUFFICIENT_SPIRIT_STONES','灵石余额不足。'],
      ['CASINO_INSUFFICIENT_CULTIVATION','当前可动用修为不足。'],['PAIGOW_REQUEST_IN_PROGRESS','上一项动作仍在处理，请稍后。']
    ];
    return map.find(([code]) => raw.includes(code))?.[1] || raw;
  }
  async function rpc(name, body = {}) {
    const s = session();
    if (!s?.access_token) throw new Error('AUTH_REQUIRED');
    const response = await fetch(`${url}/rest/v1/rpc/${name}`, {
      method: 'POST',
      headers: { apikey: key, Authorization: `Bearer ${s.access_token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body)
    });
    const text = await response.text();
    let data = null; try { data = text ? JSON.parse(text) : null; } catch { data = text; }
    if (!response.ok) throw new Error(data?.message || data?.msg || data?.error || `HTTP ${response.status}`);
    return data;
  }
  async function action(fn) {
    if (state.busy) return;
    state.busy = true;
    try { await fn(); state.lastError = ''; }
    catch (error) { state.lastError = errorText(error); toast(state.lastError); }
    finally { state.busy = false; render(); }
  }
  const duelLabel = room => room.duel_type === 'laohe' ? '老何固定庄' : room.pvp_mode === 'rob' ? '玩家随机抢庄' : '玩家开船';
  const gameLabel = room => room.game_mode === 'big' ? '大牌九' : '牌九';
  const currencyLabel = type => type === 'cultivation' ? '修为' : '灵石';
  const phaseLabel = phase => ({rob:'抢庄',multiplier:'选择倍率',arrange:'组合头尾',head_reveal:'先亮弱头',tail_reveal:'再亮强尾',settled:'本局结算',cancelled:'本局取消',waiting:'等待'}[phase] || phase || '等待');

  function tileHtml(tile, selectable = false, selected = false, index = -1) {
    if (!tile) return '<span class="pg-hidden-card">九</span>';
    return `<button type="button" class="pg-tile ${selectable ? 'selectable' : ''} ${selected ? 'selected' : ''}" ${selectable ? `data-head-index="${index}"` : 'disabled'}><b>${esc(tile.name)}</b><small>${esc(tile.pips)}点</small></button>`;
  }
  function cardsHtml(cards = [], selectable = false) {
    if (!cards.length) return '<span class="pg-note">牌面尚未公开</span>';
    return cards.map((tile, index) => tileHtml(tile, selectable, state.selectedHead.includes(index), index)).join('');
  }

  function pairValue(cards) {
    if (!Array.isArray(cards) || cards.length !== 2) return {score:-1,label:'未成牌'};
    const [a,b] = cards, supreme = a.pair_key === 'gee' && b.pair_key === 'gee' && a.code !== b.code;
    const points = (Number(a.pips) + Number(b.pips)) % 10;
    if (supreme) return {score:100000,label:'至尊宝'};
    if (a.pair_key === b.pair_key && a.pair_key !== 'gee') return {score:90000 + Math.max(a.pair_rank,b.pair_rank) * 100,label:`${a.name}对`};
    const honor = [a,b].find(t => t.key === 'teen' || t.key === 'day');
    const mate = honor ? (honor === a ? b : a) : null;
    if (honor && mate.pips === 9) return {score:80000 + (honor.key === 'teen' ? 200 : 100),label:honor.key === 'teen' ? '天王':'地王'};
    if (honor && mate.pips === 8) return {score:70000 + (honor.key === 'teen' ? 200 : 100),label:honor.key === 'teen' ? '天杠':'地杠'};
    if (honor && mate.pips === 7) return {score:60000 + (honor.key === 'teen' ? 200 : 100),label:honor.key === 'teen' ? '天高九':'地高九'};
    return {score:points === 0 ? 0 : points * 1000 + Math.max(a.single_rank,b.single_rank) * 10,label:`${points}点`};
  }
  function splitValue(cards, head) {
    const tail = [0,1,2,3].filter(i => !head.includes(i));
    const h = pairValue(head.map(i => cards[i])), t = pairValue(tail.map(i => cards[i]));
    return {head,tail,h,t,valid:h.score <= t.score};
  }
  function recommend(cards) {
    const candidates = [[0,1],[0,2],[0,3]].map(head => {
      let value = splitValue(cards, head);
      if (!value.valid) value = splitValue(cards, value.tail);
      return value;
    });
    return candidates.sort((a,b) => b.h.score - a.h.score || b.t.score - a.t.score)[0]?.head || [0,1];
  }

  function headerHtml() {
    const lobby = state.lobby;
    const balances = lobby?.balances || {};
    return `<header class="pg-head"><div class="pg-brand"><h1>九霄灵牌</h1><p>传统三十二张骨牌 · 服务端安全洗牌 · V1.2 FIX1 CACHE38</p></div><div class="pg-balance">灵石 <b>${fmt(balances.spirit_stone)}</b> · 修为 <b>${fmt(balances.cultivation)}</b><br><small>老何资金：${fmt(lobby?.bankrolls?.spirit_stone)}灵石 / ${fmt(lobby?.bankrolls?.cultivation)}修为</small></div></header>`;
  }
  function lobbyHtml() {
    const rooms = state.lobby?.rooms || [];
    const slots = [1,2,3,4].map(slot => rooms.find(room => room.slot_no === slot));
    return `${headerHtml()}${state.lastError ? `<div class="pg-error">${esc(state.lastError)}</div>` : ''}<div class="pg-grid"><section class="pg-panel"><div class="pg-panel-head"><h2>天地玄黄四房</h2><button class="pg-btn" data-refresh-lobby>刷新</button></div><div class="pg-panel-body"><div class="pg-room-grid">${slots.map((room,index) => room ? `<article class="pg-room"><h3>${esc(room.name)}</h3><div class="pg-meta"><span class="pg-tag">${duelLabel(room)}</span><span class="pg-tag">${gameLabel(room)}</span><span class="pg-tag">${currencyLabel(room.stake_type)}</span></div><div class="pg-note">底注 ${fmt(room.base_stake)} · ${room.players}/${room.capacity}人 · 观战${room.spectators}人<br>${room.status === 'playing' ? '对局进行中' : '等待准备'}</div><button class="pg-btn primary" data-open-room="${room.id}">${room.joined ? '返回房间' : room.status === 'playing' ? '进入观战' : '选座入房'}</button></article>` : `<article class="pg-room empty"><h3>${['天字一号房','地字二号房','玄字三号房','黄字四号房'][index]}</h3><div class="pg-note">当前空闲。创建后20分钟仍未开始首局会自动关闭。</div></article>`).join('')}</div></div></section><aside class="pg-panel"><div class="pg-panel-head"><h2>创建房间</h2></div><div class="pg-panel-body"><form id="createRoomForm" class="pg-form"><div class="pg-field"><label>对局方式</label><select name="duel"><option value="laohe">老何 VS 玩家</option><option value="rob">玩家随机抢庄</option><option value="boat">玩家开船</option></select></div><div class="pg-field"><label>玩法</label><select name="game"><option value="small">牌九</option><option value="big">大牌九</option></select></div><div class="pg-field"><label>下注资源</label><select name="stake"><option value="spirit_stone">灵石</option><option value="cultivation">修为</option></select></div><div class="pg-field"><label>底注</label><input name="base" type="number" min="10" step="10" value="100" required></div><button class="pg-btn primary" type="submit">创建并入座</button><div class="pg-note">倍率为10、50、100。玩家局每笔确认赌注另收2.5%，精确进入现有赌场资金；所有参战者单局累计资金不超过开局余额30%。</div></form></div></aside></div>`;
  }

  function seatGridHtml(roomState) {
    const room = roomState.room, members = roomState.members || [], round = roomState.round;
    const capacity = room.game_mode === 'big' ? (room.duel_type === 'laohe' ? 7 : 8) : 9;
    const bySeat = new Map(members.filter(m => m.role === 'player').map(m => [m.seat_no,m]));
    const roundById = new Map((round?.players || []).map(p => [p.character_id,p]));
    return `<div class="pg-seat-grid">${Array.from({length:9},(_,i) => i+1).map(seat => {
      const member = bySeat.get(seat), player = member ? roundById.get(member.character_id) : null;
      if (!member) return `<button class="pg-seat empty" ${seat > capacity || room.status === 'playing' ? 'disabled' : `data-join-seat="${seat}"`}><b>${seat}号席</b><small>${seat > capacity ? '本模式候补席' : '点击入座'}</small></button>`;
      return `<div class="pg-seat ${member.is_self ? 'self':''} ${player?.is_dealer ? 'dealer':''}"><b>${esc(member.name)}${player?.is_dealer ? ' · 庄':''}</b><small>${seat}号席${member.is_owner ? ' · 房主':''}</small><span class="${member.ready ? 'pg-ready':''}">${member.ready ? '已准备':'未准备'}</span>${player?.multiplier ? `<small>${player.multiplier}倍 · 押${fmt(player.stake_amount)}</small>`:''}</div>`;
    }).join('')}</div>`;
  }
  function roundHtml(roomState) {
    const round = roomState.round, room = roomState.room;
    if (!round) return '<div class="pg-phase">等待玩家准备，由房主开始首局。</div>';
    const self = (round.players || []).find(p => p.is_self);
    const deadline = round.phase_deadline ? new Date(round.phase_deadline).getTime() : 0;
    const control = [];
    if (round.phase === 'rob' && self?.active && self.rob_choice == null) {
      control.push('<button class="pg-btn primary" data-rob="true">抢庄</button><button class="pg-btn" data-rob="false">不抢</button>');
    }
    if (round.phase === 'multiplier' && self?.active && !self.action_confirmed && !self.is_dealer) {
      [10,50,100].forEach(mult => control.push(`<button class="pg-btn ${mult===10?'primary':''}" data-multiplier="${mult}">${mult}倍</button>`));
    }
    const arranging = round.phase === 'arrange' && self?.active && !self.action_confirmed;
    if (arranging) control.push('<button class="pg-btn" data-recommend>系统推荐</button><button class="pg-btn primary" data-confirm-head>确认弱头</button>');
    const laohe = round.laohe && room.duel_type === 'laohe' ? `<div class="pg-player-row dealer"><div class="pg-player-top"><b>老何 · 庄家</b><span>系统庄</span></div><div class="pg-cards">${cardsHtml(round.laohe.cards || [])}</div>${round.laohe.public_value?.label ? `<div class="pg-result">${esc(round.laohe.public_value.label)}</div>`:''}</div>` : '';
    const players = laohe + (round.players || []).map(player => `<div class="pg-player-row"><div class="pg-player-top"><b>${esc(player.name)}${player.is_self?'（你）':''}${player.is_dealer?' · 庄家':''}</b><span>${player.active ? (player.multiplier ? `${player.multiplier}倍 · ${fmt(player.stake_amount)}` : '等待动作') : `退出本局：${esc(player.fold_reason || '')}`}</span></div><div class="pg-cards">${cardsHtml(player.cards || [], arranging && player.is_self)}</div>${player.public_value?.label ? `<div class="pg-result">${esc(player.public_value.label)}</div>`:''}${round.phase === 'settled' ? `<div class="pg-result ${player.net_amount >= 0 ? 'pg-positive':'pg-negative'}">返还 ${fmt(player.payout_amount)} · 净${player.net_amount >= 0 ? '+':''}${fmt(player.net_amount)}</div>`:''}</div>`).join('');
    const results = round.phase === 'settled' ? `<div class="pg-summary">${(round.result_payload?.players || []).map(row => `<div class="pg-summary-row"><span>${esc((round.players || []).find(p=>p.character_id===row.character_id)?.name || row.character_id)}</span><span>押${fmt(row.stake)} / 费${fmt(row.fee)}</span><b class="${row.net>=0?'pg-positive':'pg-negative'}">${row.net>=0?'+':''}${fmt(row.net)}</b></div>`).join('')}</div>` : '';
    return `<div class="pg-round"><div class="pg-phase">第${round.round_no}局 · <strong>${phaseLabel(round.phase)}</strong>${deadline ? ` · <span class="pg-countdown" data-deadline="${deadline}">--</span>`:''}<br><small>${round.dealer_character_id ? '本局庄家已经确定' : room.duel_type === 'laohe' ? '老何坐庄' : '等待庄家'}</small></div>${self ? `<section><h3>你的牌面</h3><div class="pg-cards">${cardsHtml(self.cards || [], arranging)}</div>${arranging ? `<div class="pg-note">选择两张作为先出的较弱头牌；头牌不得强于尾牌。</div>`:''}</section>`:''}<div class="pg-actions">${control.join('')}</div><div class="pg-player-list">${players}</div>${results}</div>`;
  }
  function roomHtml() {
    const data = state.room, room = data.room, self = data.self_member;
    const waiting = room.status === 'waiting';
    return `${headerHtml()}<div class="pg-toolbar"><button class="pg-btn" data-back-lobby>返回大堂</button><button class="pg-btn" data-refresh-room>刷新状态</button>${!self ? '<button class="pg-btn" data-watch>加入观战</button>' : ''}${self?.role === 'player' && waiting ? `<button class="pg-btn ${self.ready?'':'primary'}" data-ready="${self.ready ? 'false':'true'}">${self.ready ? '取消准备':'准备'}</button>`:''}${self?.is_owner && waiting ? '<button class="pg-btn primary" data-start>开始本局</button>':''}${self && waiting ? '<button class="pg-btn danger" data-leave>离开房间</button>':''}</div>${state.lastError ? `<div class="pg-error">${esc(state.lastError)}</div>`:''}<div class="pg-grid"><section class="pg-panel"><div class="pg-panel-head"><div><h2>${esc(room.room_name)}</h2><div class="pg-meta"><span class="pg-tag">${duelLabel(room)}</span><span class="pg-tag">${gameLabel(room)}</span><span class="pg-tag">${currencyLabel(room.stake_type)}底注${fmt(room.base_stake)}</span></div></div><span>${room.status === 'playing' ? '对局中':'等待准备'}</span></div><div class="pg-panel-body">${seatGridHtml(data)}<div class="pg-divider"></div>${roundHtml(data)}</div></section><aside class="pg-panel"><div class="pg-panel-head"><h3>房间规则</h3></div><div class="pg-panel-body pg-note"><b>老何庄：</b>100∶100等额输赢，盈利从现有赌场资金支付，败款进入同一资金。<br><b>随机抢庄：</b>庄家责任资金先冻结，系统绝不兜底。<br><b>玩家开船：</b>赌注进入公共池，按牌力顺序赔付；并列按赌注比例分配。<br><b>牌九：</b>6秒选倍，超时默认10倍。<br><b>大牌九：</b>10秒选倍、30秒组合，先亮弱头10秒，再亮强尾。传统32张牌下，老何局最多7名玩家，玩家局最多8名。<br><b>安全：</b>洗牌、阶段截止、私牌遮罩和结算全部由数据库执行。</div></aside></div>`;
  }
  function render() {
    if (!session()?.access_token) { app.innerHTML = '<div class="pg-loading"><h2>需要登录</h2><p>请关闭九霄灵牌，先在主界面登录游戏。</p></div>'; return; }
    if (state.roomId && state.room) app.innerHTML = roomHtml();
    else if (state.lobby) app.innerHTML = lobbyHtml();
    else app.innerHTML = '<div class="pg-loading">正在连接九霄灵牌……</div>';
    updateCountdown();
  }
  function updateCountdown() {
    document.querySelectorAll('[data-deadline]').forEach(el => {
      const seconds = Math.max(0, Math.ceil((Number(el.dataset.deadline) - Date.now()) / 1000));
      el.textContent = `${seconds}秒`;
    });
  }

  async function loadLobby() {
    state.lobby = await rpc('get_paigow_lobby_bpaigow01');
    if (state.lobby.status !== 'active') throw new Error('PAIGOW_DISABLED');
    render();
  }
  async function loadRoom(advance = false) {
    if (!state.roomId) return;
    state.room = advance ? await rpc('advance_paigow_round_bpaigow01',{p_room_id:state.roomId}) : await rpc('get_paigow_room_state_bpaigow01',{p_room_id:state.roomId});
    if (!state.lobby) await loadLobby(); else {
      state.lobby.balances[state.room.room.stake_type] = state.room.self_balance;
      state.lobby.bankrolls[state.room.room.stake_type] = state.room.bankroll_balance;
    }
    const self = state.room.round?.players?.find(p => p.is_self);
    if (state.room.round?.phase === 'arrange' && self?.cards?.length === 4 && state.selectedHead.length !== 2) state.selectedHead = recommend(self.cards);
    render();
  }
  function startPolling() {
    clearInterval(state.poll); clearInterval(state.clock);
    state.poll = setInterval(() => { if (state.busy) return; action(async () => state.roomId ? loadRoom(true) : loadLobby()); }, state.roomId ? 2000 : 5000);
    state.clock = setInterval(updateCountdown, 250);
  }
  function openRoom(id) { state.roomId = id; state.room = null; state.selectedHead = []; render(); action(async () => { await loadRoom(true); startPolling(); }); }

  app.addEventListener('click', event => {
    const target = event.target.closest('button'); if (!target) return;
    if (target.dataset.openRoom) return openRoom(target.dataset.openRoom);
    if (target.hasAttribute('data-refresh-lobby')) return action(loadLobby);
    if (target.hasAttribute('data-refresh-room')) return action(() => loadRoom(true));
    if (target.hasAttribute('data-back-lobby')) { state.roomId = null; state.room = null; state.selectedHead = []; startPolling(); return action(loadLobby); }
    if (target.dataset.joinSeat) return action(async () => { state.room = await rpc('join_paigow_room_bpaigow01',{p_room_id:state.roomId,p_seat_no:Number(target.dataset.joinSeat),p_spectator:false}); });
    if (target.hasAttribute('data-watch')) return action(async () => { state.room = await rpc('join_paigow_room_bpaigow01',{p_room_id:state.roomId,p_seat_no:null,p_spectator:true}); });
    if (target.dataset.ready) return action(async () => { state.room = await rpc('set_paigow_ready_bpaigow01',{p_room_id:state.roomId,p_ready:target.dataset.ready==='true'}); });
    if (target.hasAttribute('data-start')) return action(async () => { state.room = await rpc('start_paigow_round_bpaigow01',{p_room_id:state.roomId,p_request_id:uuid()}); });
    if (target.dataset.rob) return action(async () => { state.room = await rpc('choose_paigow_rob_bpaigow01',{p_room_id:state.roomId,p_rob:target.dataset.rob==='true',p_request_id:uuid()}); });
    if (target.dataset.multiplier) return action(async () => { state.room = await rpc('choose_paigow_multiplier_bpaigow01',{p_room_id:state.roomId,p_multiplier:Number(target.dataset.multiplier),p_request_id:uuid()}); });
    if (target.dataset.headIndex != null) { const index = Number(target.dataset.headIndex); state.selectedHead = state.selectedHead.includes(index) ? state.selectedHead.filter(i=>i!==index) : state.selectedHead.length < 2 ? [...state.selectedHead,index] : [state.selectedHead[1],index]; return render(); }
    if (target.hasAttribute('data-recommend')) { const self=state.room?.round?.players?.find(p=>p.is_self); if(self?.cards?.length===4) state.selectedHead=recommend(self.cards); return render(); }
    if (target.hasAttribute('data-confirm-head')) return action(async () => { if(state.selectedHead.length!==2) throw new Error('请选择两张头牌'); state.room=await rpc('arrange_paigow_big_bpaigow01',{p_room_id:state.roomId,p_head_indices:state.selectedHead,p_request_id:uuid()}); });
    if (target.hasAttribute('data-leave')) return action(async () => { await rpc('leave_paigow_room_bpaigow01',{p_room_id:state.roomId}); state.roomId=null;state.room=null;await loadLobby();startPolling(); });
  });
  app.addEventListener('change', event => {
    if (event.target?.name !== 'stake' || event.target.form?.id !== 'createRoomForm') return;
    const base = event.target.form.elements.base;
    const cultivation = event.target.value === 'cultivation';
    base.min = cultivation ? '5000' : '10';
    base.step = cultivation ? '5000' : '10';
    if (Number(base.value || 0) < Number(base.min)) base.value = base.min;
  });
  app.addEventListener('submit', event => {
    if (event.target.id !== 'createRoomForm') return; event.preventDefault();
    const form = new FormData(event.target), duel = form.get('duel'), stake = form.get('stake');
    action(async () => {
      const result = await rpc('create_paigow_room_bpaigow01',{
        p_duel_type:duel==='laohe'?'laohe':'pvp',p_pvp_mode:duel==='laohe'?null:duel,
        p_game_mode:form.get('game'),p_stake_type:stake,p_base_stake:Number(form.get('base'))
      });
      const id = result?.room?.id || result?.state?.room?.id; if (!id) throw new Error('房间创建结果异常');
      state.roomId=id;state.room=result.state || await rpc('get_paigow_room_state_bpaigow01',{p_room_id:id});startPolling();
    });
  });
  window.addEventListener('message', event => { if (event.data?.type === 'b-paigow01-refresh') action(() => state.roomId ? loadRoom(true) : loadLobby()); });
  window.addEventListener('beforeunload', () => { clearInterval(state.poll); clearInterval(state.clock); });
  render(); action(async () => { await loadLobby(); startPolling(); });
})();
