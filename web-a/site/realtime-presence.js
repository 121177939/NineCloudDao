import {diagEvent} from './diagnostics.js?v=2.0.63.1';
/** Realtime is a hint/visibility channel only: Supabase SQL remains authority. */
export class GameRealtime {
  constructor(api,update,wake=()=>{}){
    this.api=api;this.update=update;this.wake=wake;
    this.ws=null;this.live=false;this.seq=1;this.timer=null;this.retry=null;
    this.topic='';this.joined=false;this.closed=false;this.state={};this.retryDelay=3000;
    this.phase='IDLE';this.startedAt=0;this.joinAt=0;this.lastHeartbeatSent=0;
    this.heartbeatPending=null;this.starting=null;
  }
  start(){
    if(this.starting)return this.starting;
    const pending=this._start();this.starting=pending;
    pending.finally(()=>{if(this.starting===pending)this.starting=null;}).catch(()=>{});
    return pending;
  }
  async _start(){
    this.closed=false;
    if(this.ws||!this.api.loggedIn||document.hidden)return;
    diagEvent('realtime','START');
    try{
      await this.api.ensureSession();
      if(this.closed||document.hidden||this.ws||!this.api.loggedIn)return;
      const base=this.api.url.replace(/^https:/,'wss:').replace(/\/$/,'');
      this.topic='realtime:two-phone:'+this.api.uid;
      this.seq=1;this.joined=false;this.live=false;this.state={};
      this.phase='CONNECTING';this.startedAt=Date.now();this.joinAt=0;
      this.lastHeartbeatSent=0;this.heartbeatPending=null;
      const ws=new WebSocket(base+'/realtime/v1/websocket?vsn=1.0.0&apikey='+encodeURIComponent(this.api.key));
      this.ws=ws;diagEvent('realtime','CONNECT_START');
      ws.onopen=()=>{
        if(this.ws!==ws)return;
        this.phase='JOINING';this.joinAt=Date.now();diagEvent('realtime','SOCKET_OPEN');
        this.send('phx_join',{config:{private:true,presence:{enabled:true,key:'A'},broadcast:{ack:true,self:false}},access_token:this.api.access},'1');
      };
      ws.onmessage=ev=>{
        if(this.ws!==ws)return;
        let m;try{m=JSON.parse(ev.data);}catch{diagEvent('realtime','MESSAGE_PARSE_FAILED');return;}
        if(m.event==='phx_reply'){
          if(m.ref==='1'&&this.phase==='JOINING'){
            if(m.payload?.status!=='ok'){
              diagEvent('realtime','JOIN_REJECTED');this.disconnect(ws,'authorization_failed');return;
            }
            diagEvent('realtime','JOIN_OK');this.joined=true;this.phase='ONLINE';this.retryDelay=3000;
            this.track();this.update({connected:true,online:false,state:'awaiting_sync'});return;
          }
          if(this.heartbeatPending&&m.ref===this.heartbeatPending.ref){
            diagEvent('realtime','HEARTBEAT_ACK',{elapsedMs:Date.now()-this.heartbeatPending.at});
            this.heartbeatPending=null;return;
          }
        }
        if(!this.joined)return;
        if(m.event==='presence_state'){this.state=m.payload||{};this.publish();}
        if(m.event==='presence_diff'){
          for(const [k,v] of Object.entries(m.payload?.joins||{})){
            const added=v?.metas||[],old=this.state[k]?.metas||[];
            const refs=new Set(added.map(x=>x.phx_ref));
            this.state[k]={metas:[...old.filter(x=>!refs.has(x.phx_ref)),...added]};
          }
          for(const [k,v] of Object.entries(m.payload?.leaves||{})){
            const drop=new Set((v?.metas||[]).map(x=>x.phx_ref));
            if(!drop.size)continue;
            const keep=(this.state[k]?.metas||[]).filter(x=>!drop.has(x.phx_ref));
            if(keep.length)this.state[k]={metas:keep};else delete this.state[k];
          }
          this.publish();
        }
        if(m.event==='broadcast'&&m.payload?.event==='queue_changed')this.wake();
        if(['phx_error','phx_close'].includes(m.event))this.disconnect(ws,'reconnecting');
      };
      ws.onclose=ev=>{diagEvent('realtime','SOCKET_CLOSED',{status:ev?.code||0});this.lost(ws);};
      ws.onerror=()=>{diagEvent('realtime','SOCKET_FAILED');this.disconnect(ws,'reconnecting');};
      clearInterval(this.timer);
      this.timer=setInterval(()=>this.keepAlive(ws),5000);
    }catch(e){
      this.phase='IDLE';diagEvent('realtime','CONNECT_SETUP_FAILED',{error:e});this.queueRetry();throw e;
    }
  }
  keepAlive(ws){
    if(this.ws!==ws||this.closed||document.hidden)return;
    const now=Date.now();
    if(this.phase==='CONNECTING'&&now-this.startedAt>12000){
      diagEvent('realtime','SOCKET_OPEN_TIMEOUT');this.disconnect(ws,'reconnecting');return;
    }
    if(this.phase==='JOINING'&&now-this.joinAt>12000){
      diagEvent('realtime','JOIN_TIMEOUT');this.disconnect(ws,'reconnecting');return;
    }
    if(!this.joined||ws.readyState!==1)return;
    if(this.heartbeatPending&&now-this.heartbeatPending.at>40000){
      diagEvent('realtime','HEARTBEAT_ACK_TIMEOUT');this.disconnect(ws,'reconnecting');return;
    }
    if(!this.heartbeatPending&&now-this.lastHeartbeatSent>=20000){
      const ref=this.send('heartbeat',{},null,'phoenix');
      if(ref){this.heartbeatPending={ref,at:now};this.lastHeartbeatSent=now;}
      // This is intentionally read-only; auth failure cannot be treated as a task result.
      this.api.ensureSession().then(()=>{
        if(this.ws===ws&&this.joined)this.send('access_token',{access_token:this.api.access},'1');
      }).catch(e=>{diagEvent('realtime','TOKEN_REFRESH_FAILED',{error:e});this.disconnect(ws,'reconnecting');});
    }
  }
  queueRetry(){
    if(this.closed||document.hidden)return;
    clearTimeout(this.retry);
    const ms=this.retryDelay;this.retryDelay=Math.min(30000,Math.round(ms*1.5));
    diagEvent('realtime','RETRY_SCHEDULED',{elapsedMs:ms});
    this.retry=setTimeout(()=>{this.retry=null;this.start().catch(()=>{});},ms);
  }
  send(event,payload,join='1',topic=this.topic){
    if(this.ws?.readyState!==1)return null;
    const ref=String(this.seq++);
    this.ws.send(JSON.stringify({topic,event,payload,ref,...(join?{join_ref:join}:{})}));
    return ref;
  }
  track(){this.send('presence',{type:'presence',event:'track',payload:{role:'A',state:'idle'}},'1');}
  publish(){
    const metas=this.state.B?.metas||[];this.live=metas.length>0;
    this.update({connected:true,online:this.live,state:metas[0]?.state||''});
  }
  disconnect(ws,reason){
    if(this.ws!==ws)return;
    try{ws.close();}catch{}
    this.lost(ws,reason);
  }
  lost(ws,reason='reconnecting'){
    if(this.ws!==ws)return;
    diagEvent('realtime','CONNECTION_LOST');this.ws=null;this.joined=false;this.live=false;
    this.phase='STALE';this.heartbeatPending=null;
    clearInterval(this.timer);this.timer=null;
    this.update({connected:false,online:false,state:reason});this.queueRetry();
  }
  close(){
    this.closed=true;clearTimeout(this.retry);this.retry=null;clearInterval(this.timer);this.timer=null;
    const ws=this.ws;this.ws=null;this.joined=false;this.live=false;
    this.phase='IDLE';this.heartbeatPending=null;
    try{ws?.close(1000,'leave');}catch{}
    this.update({connected:false,online:false,state:''});
  }
}
