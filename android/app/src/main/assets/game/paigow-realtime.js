(() => {
  'use strict';

  /**
   * 九霄牌九专用 Supabase Realtime 轻量客户端。
   * 只实现私有 Broadcast 订阅，不引入完整 SDK，避免小游戏给主游戏增加大型依赖。
   * 协议：Supabase Realtime / Phoenix JSON v1.0.0。
   */
  class JiuxiaoPaigowRealtimeClient {
    constructor(options = {}) {
      this.url = String(options.url || '').replace(/\/+$/, '');
      this.key = String(options.key || '');
      this.getAccessToken = typeof options.getAccessToken === 'function'
        ? options.getAccessToken
        : () => '';
      this.onStatus = typeof options.onStatus === 'function'
        ? options.onStatus
        : () => undefined;
      this.socket = null;
      this.destroyed = false;
      this.connecting = false;
      this.ref = 0;
      this.joinRefs = new Map();
      this.handlers = new Map();
      this.heartbeatTimer = null;
      this.reconnectTimer = null;
      this.reconnectAttempt = 0;
      this.lastStatus = 'idle';
      this.boundOnline = () => this.connect();
      this.boundVisibility = () => {
        if (!document.hidden && this.handlers.size) this.connect();
      };
      window.addEventListener('online', this.boundOnline, { passive: true });
      document.addEventListener('visibilitychange', this.boundVisibility, { passive: true });
    }

    status(next, detail = '') {
      if (this.lastStatus === next && !detail) return;
      this.lastStatus = next;
      try { this.onStatus(next, detail); }
      catch (error) { console.debug('[牌九Realtime] 状态回调失败', error); }
    }

    websocketUrl() {
      if (!this.url || !this.key) return '';
      const ws = this.url.replace(/^http:/i, 'ws:').replace(/^https:/i, 'wss:');
      return `${ws}/realtime/v1/websocket?apikey=${encodeURIComponent(this.key)}&vsn=1.0.0`;
    }

    nextRef() {
      this.ref += 1;
      return String(this.ref);
    }

    send(topic, event, payload = {}, joinRef = null) {
      if (!this.socket || this.socket.readyState !== WebSocket.OPEN) return false;
      const ref = this.nextRef();
      this.socket.send(JSON.stringify({
        topic,
        event,
        payload,
        ref,
        join_ref: joinRef
      }));
      return ref;
    }

    async join(topic) {
      if (!this.handlers.has(topic)) return;
      const socketTopic = `realtime:${topic}`;
      const joinRef = this.nextRef();
      this.joinRefs.set(topic, joinRef);
      let token = '';
      try { token = String(await this.getAccessToken() || ''); }
      catch { token = ''; }
      if (!this.socket || this.socket.readyState !== WebSocket.OPEN || !this.handlers.has(topic)) return;
      this.socket.send(JSON.stringify({
        topic: socketTopic,
        event: 'phx_join',
        payload: {
          config: {
            broadcast: { ack: false, self: false },
            presence: { enabled: false },
            postgres_changes: [],
            private: true
          },
          access_token: token
        },
        ref: joinRef,
        join_ref: joinRef
      }));
    }

    leave(topic) {
      const joinRef = this.joinRefs.get(topic);
      this.joinRefs.delete(topic);
      if (joinRef) this.send(`realtime:${topic}`, 'phx_leave', {}, joinRef);
    }

    subscribe(topic, handler) {
      if (!topic || typeof handler !== 'function') throw new Error('PAIGOW_REALTIME_SUBSCRIPTION_INVALID');
      let set = this.handlers.get(topic);
      if (!set) {
        set = new Set();
        this.handlers.set(topic, set);
      }
      set.add(handler);
      this.connect();
      if (this.socket?.readyState === WebSocket.OPEN && !this.joinRefs.has(topic)) this.join(topic);
      return () => {
        const current = this.handlers.get(topic);
        if (!current) return;
        current.delete(handler);
        if (!current.size) {
          this.handlers.delete(topic);
          this.leave(topic);
        }
        if (!this.handlers.size) this.disconnect('idle');
      };
    }

    dispatch(topic, event, data, raw) {
      const set = this.handlers.get(topic);
      if (!set) return;
      for (const handler of set) {
        try { handler({ topic, event, payload: data, raw }); }
        catch (error) { console.error('[牌九Realtime] 事件处理失败', error); }
      }
    }

    handleMessage(message) {
      let frame;
      try { frame = JSON.parse(message.data); }
      catch { return; }
      const topicWithPrefix = String(frame?.topic || '');
      const topic = topicWithPrefix.startsWith('realtime:')
        ? topicWithPrefix.slice('realtime:'.length)
        : topicWithPrefix;

      if (frame?.event === 'phx_reply') {
        const status = frame?.payload?.status;
        if (status === 'ok') this.status('subscribed');
        else if (status === 'error') this.status('authorization_error', String(frame?.payload?.response?.reason || 'join failed'));
        return;
      }
      if (frame?.event === 'phx_error' || frame?.event === 'phx_close') {
        this.status('channel_error', frame.event);
        return;
      }
      if (frame?.event !== 'broadcast') return;

      const envelope = frame.payload || {};
      const event = String(envelope.event || envelope.type || 'state_changed');
      const payload = envelope.payload ?? envelope;
      this.dispatch(topic, event, payload, frame);
    }

    startHeartbeat() {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = setInterval(() => {
        if (!this.socket || this.socket.readyState !== WebSocket.OPEN) return;
        this.send('phoenix', 'heartbeat', {}, null);
      }, 20000);
    }

    scheduleReconnect() {
      if (this.destroyed || !this.handlers.size || this.reconnectTimer) return;
      const delay = Math.min(15000, 600 * (2 ** Math.min(5, this.reconnectAttempt)));
      this.reconnectAttempt += 1;
      this.status('reconnecting', String(delay));
      this.reconnectTimer = setTimeout(() => {
        this.reconnectTimer = null;
        this.connect();
      }, delay);
    }

    connect() {
      if (this.destroyed || !this.handlers.size || this.connecting) return;
      if (this.socket && (this.socket.readyState === WebSocket.OPEN || this.socket.readyState === WebSocket.CONNECTING)) return;
      const endpoint = this.websocketUrl();
      if (!endpoint || typeof WebSocket === 'undefined') {
        this.status('unavailable', 'WebSocket unavailable');
        return;
      }
      this.connecting = true;
      this.status('connecting');
      try {
        const socket = new WebSocket(endpoint);
        this.socket = socket;
        socket.addEventListener('open', () => {
          if (this.socket !== socket || this.destroyed) return;
          this.connecting = false;
          this.reconnectAttempt = 0;
          this.joinRefs.clear();
          this.startHeartbeat();
          this.status('connected');
          for (const topic of this.handlers.keys()) this.join(topic);
        });
        socket.addEventListener('message', event => this.handleMessage(event));
        socket.addEventListener('error', () => this.status('socket_error'));
        socket.addEventListener('close', () => {
          if (this.socket !== socket) return;
          this.socket = null;
          this.connecting = false;
          this.joinRefs.clear();
          clearInterval(this.heartbeatTimer);
          this.heartbeatTimer = null;
          if (!this.destroyed && this.handlers.size) this.scheduleReconnect();
          else this.status('closed');
        });
      } catch (error) {
        this.connecting = false;
        this.status('socket_error', String(error?.message || error));
        this.scheduleReconnect();
      }
    }

    async refreshAuth() {
      if (!this.socket || this.socket.readyState !== WebSocket.OPEN) return;
      let token = '';
      try { token = String(await this.getAccessToken() || ''); }
      catch { token = ''; }
      for (const [topic, joinRef] of this.joinRefs.entries()) {
        this.send(`realtime:${topic}`, 'access_token', { access_token: token }, joinRef);
      }
    }

    disconnect(reason = 'manual') {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
      this.joinRefs.clear();
      const socket = this.socket;
      this.socket = null;
      this.connecting = false;
      if (socket && socket.readyState < WebSocket.CLOSING) socket.close(1000, reason);
      this.status('closed', reason);
    }

    destroy() {
      if (this.destroyed) return;
      this.destroyed = true;
      this.handlers.clear();
      this.disconnect('destroy');
      window.removeEventListener('online', this.boundOnline);
      document.removeEventListener('visibilitychange', this.boundVisibility);
    }
  }

  window.JiuxiaoPaigowRealtimeClient = JiuxiaoPaigowRealtimeClient;
})();
