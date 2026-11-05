/** Private account-scoped Realtime Presence; database remains authority for all orders. */
export class GameRealtime {
  constructor(api, update, wake=()=>{}) { this.api=api;this.update=update;this.wake=wake;this.ws=null;this.live=false;this.seq=1;this.timer=null;this.retry=null;this.topic='';this.joined=false;this.closed=false;this.state={}; }
  async start(){
    this.closed=false;
    if(this.ws||!this.api.loggedIn || document.hidden)return;
    await this.api.ensureSession();
    const base=this.api.url.replace(/^https:/,'wss:').replace(/\/$/,'');
    this.topic='realtime:two-phone:'+this.api.uid;
    // Every new socket starts a fresh Phoenix request sequence.
    this.seq=1;this.joined=false;this.state={};
    const ws=new WebSocket(base+'/realtime/v1/websocket?vsn=1.0.0&apikey='+encodeURIComponent(this.api.key));
    this.ws=ws;
    ws.onopen=()=>this.send('phx_join',{config:{private:true,presence:{enabled:true,key:'A'},broadcast:{ack:true,self:false}},access_token:this.api.access},'1');
    ws.onmessage=ev=>{
      let m;try{m=JSON.parse(ev.data);}catch{return;}
      if(m.event==='phx_reply'&&m.ref==='1'){
        if(m.payload?.status!=='ok'){ws.close();return;}
        this.joined=true;this.track();return;
      }
      if(m.event==='presence_state'){this.state=m.payload||{};this.publish();}
      if(m.event==='presence_diff'){
        // Reconcile individual presence metadata (phx_ref), not entire shared A/B keys.
        for(const [k,v] of Object.entries(m.payload?.joins||{})){
          const added=v?.metas||[], old=this.state[k]?.metas||[];
          const addRefs=new Set(added.map(x=>x.phx_ref));
          this.state[k]={metas:[...old.filter(x=>!addRefs.has(x.phx_ref)),...added]};
        }
        for(const [k,v] of Object.entries(m.payload?.leaves||{})){
          const drop=new Set((v?.metas||[]).map(x=>x.phx_ref));
          if(!drop.size)continue;
          const remaining=(this.state[k]?.metas||[]).filter(x=>!drop.has(x.phx_ref));
          if(remaining.length)this.state[k]={metas:remaining};else delete this.state[k];
        }
        this.publish();
      }
      if(m.event==='broadcast'&&m.payload?.event==='queue_changed')this.wake();
      if(['phx_error','phx_close'].includes(m.event))ws.close();
    };
    ws.onclose=()=>this.lost(ws);ws.onerror=()=>ws.close();
    clearInterval(this.timer);this.timer=setInterval(async()=>{
      if(this.ws!==ws||ws.readyState!==1||!this.joined)return;
      this.send('heartbeat',{},null,'phoenix');
      try{await this.api.ensureSession();this.send('access_token',{access_token:this.api.access},'1');}catch{ws.close();}
    },20000);
  }
  send(event,payload,join='1',topic=this.topic){
    if(this.ws?.readyState!==1)return;
    this.ws.send(JSON.stringify({topic,event,payload,ref:String(this.seq++),...(join?{join_ref:join}:{})}));
  }
  track(){this.send('presence',{type:'presence',event:'track',payload:{role:'A',state:'idle'}},'1');}
  publish(){const metas=this.state.B?.metas||[];this.live=metas.length>0;this.update({connected:true,online:this.live,state:metas[0]?.state||''});}
  lost(ws){if(this.ws!==ws)return;this.ws=null;this.joined=false;this.live=false;clearInterval(this.timer);this.update({connected:false,online:false,state:''});if(!this.closed&&!document.hidden)this.retry=setTimeout(()=>this.start().catch(()=>{}),5000);}
  close(){this.closed=true;clearTimeout(this.retry);clearInterval(this.timer);const ws=this.ws;this.ws=null;this.joined=false;this.live=false;ws?.close(1000,'leave');this.update({connected:false,online:false,state:''});}
}
