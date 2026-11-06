import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {WebAClient} from '../site/supabase.js';
import {GameRealtime} from '../site/realtime-presence.js';

const state=new Map();
globalThis.sessionStorage={
  getItem:k=>state.get(k)??null,
  setItem:(k,v)=>state.set(k,v),
  removeItem:k=>state.delete(k)
};
const storeKey='web-a-refresh-v12';
const makeResponse=(data,status=200)=>({
  ok:status>=200&&status<300,status,
  headers:{get:()=>new Date().toUTCString()},
  text:async()=>JSON.stringify(data)
});
const makeAuth=(token)=>({access_token:'jwt-'+token,refresh_token:token,user:{id:'879c56b4-447e-4e89-af0f-2210c4771a11'},expires_in:3600});

// Case 1: DNS/timeout is not evidence that Supabase revoked a refresh token.
state.set(storeKey,'old-token');
globalThis.fetch=async()=>{throw new TypeError('offline')};
let api=new WebAClient();
await assert.rejects(api.restoreSession(),/网络连接失败/);
assert.equal(state.get(storeKey),'old-token','offline must keep the saved refresh token');
assert.equal(api.loggedIn,false);
assert.equal(api.hasSavedSession(),true);

// Case 2: a definite 401 from Auth invalidates saved credentials.
globalThis.fetch=async()=>makeResponse({message:'invalid_grant'},401);
api=new WebAClient();
await assert.rejects(api.restoreSession(),/HTTP 401/);
assert.equal(api.hasSavedSession(),false,'definitive Auth rejection removes old session');

// Case 3: Auth rotates a refresh token successfully, but role lookup times out.
// We must preserve the NEW token, not return to the already-used old one.
state.set(storeKey,'old-token');
let call=0;
globalThis.fetch=async(url)=>{
  if(url.includes('/auth/v1/token')){call++;return makeResponse(makeAuth('rotated-token'));}
  if(url.includes('/rest/v1/rpc/remote_role_current'))throw new TypeError('temporary role API outage');
  throw Error('unexpected route '+url);
};
api=new WebAClient();
await assert.rejects(api.restoreSession(),/网络连接失败/);
assert.equal(state.get(storeKey),'rotated-token','token rotation is persisted before role verification');
assert.equal(api.loggedIn,false,'no A role authorization without server proof');
assert.equal(call,1);
// Recover with the rotated token; verified login is restored.
let observedRefresh='';
globalThis.fetch=async(url,options)=>{
  if(url.includes('/auth/v1/token')){
    observedRefresh=JSON.parse(options.body).refresh_token;
    return makeResponse(makeAuth('next-token'));
  }
  if(url.includes('/rest/v1/rpc/remote_role_current'))return makeResponse(true);
  throw Error('unexpected route');
};
assert.equal(await api.restoreSession(),true);
assert.equal(observedRefresh,'rotated-token');
assert.equal(api.loggedIn,true);
assert.equal(state.get(storeKey),'next-token');

// Case 4: Realtime socket opens without responding to phx_join; watchdog closes it.
globalThis.document={hidden:false};
const sockets=[];
globalThis.WebSocket=class {
  constructor(){this.readyState=1;this.sent=[];this.closed=false;sockets.push(this);}
  send(raw){this.sent.push(JSON.parse(raw));}
  close(){this.readyState=3;this.closed=true;this.onclose?.({code:1000});}
};
const realtimeApi={loggedIn:true,url:'https://test.supabase.co',uid:'879c56b4-447e-4e89-af0f-2210c4771a11',key:'public-key',access:'jwt',ensureSession:async()=>{}};
let changes=[];
const realtime=new GameRealtime(realtimeApi,c=>changes.push(c));
await realtime.start();
let sock=sockets.at(-1);sock.onopen();
assert.equal(realtime.phase,'JOINING');
realtime.joinAt=Date.now()-20_000;
realtime.keepAlive(sock);
assert.equal(sock.closed,true,'join timeout must actively close stuck socket');
assert.equal(realtime.ws,null);
assert.ok(realtime.retry!==null,'timeout schedules a retry');

// Case 5: healthy joined socket must track heartbeat ACK and stale transport.
clearTimeout(realtime.retry);realtime.retry=null;
await realtime.start();sock=sockets.at(-1);sock.onopen();
sock.onmessage({data:JSON.stringify({event:'phx_reply',ref:'1',payload:{status:'ok'}})});
assert.equal(realtime.joined,true);
realtime.keepAlive(sock);
const pending=realtime.heartbeatPending;
assert.ok(pending?.ref,'heartbeat requires an ACK ref');
sock.onmessage({data:JSON.stringify({event:'phx_reply',ref:pending.ref,payload:{status:'ok'}})});
assert.equal(realtime.heartbeatPending,null,'heartbeat ack should reset the watchdog');
realtime.lastHeartbeatSent=0;
realtime.keepAlive(sock);
assert.ok(realtime.heartbeatPending);
realtime.heartbeatPending.at=Date.now()-50_000;
realtime.keepAlive(sock);
assert.equal(sock.closed,true,'missing heartbeat ack triggers socket reset');
realtime.close();

console.log('PASS v2.0.63 transient session recovery and Realtime watchdog');
