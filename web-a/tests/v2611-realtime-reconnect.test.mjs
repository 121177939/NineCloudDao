import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const {GameRealtime}=await import(new URL('../site/realtime-presence.js',import.meta.url).href);
const sockets=[];
globalThis.document={hidden:false};
globalThis.WebSocket=class MockSocket {
  constructor(url){this.url=url;this.readyState=1;this.sent=[];sockets.push(this);}
  send(str){this.sent.push(JSON.parse(str));}
  close(){this.readyState=3;this.onclose?.();}
};
const api={loggedIn:true,url:'https://test.supabase.co',uid:'c8d9a0af-6fa3-4a23-9b9b-074d90a00000',key:'public-test',access:'fake-jwt',ensureSession:async()=>{}};
const updates=[];
const r=new GameRealtime(api,e=>updates.push(e));
await r.start();
let sock=sockets.at(-1);
sock.onopen();
assert.equal(sock.sent[0].ref,'1','first join ref must be 1');
sock.onmessage({data:JSON.stringify({event:'phx_reply',ref:'1',payload:{status:'ok'}})});
assert.equal(r.joined,true);
assert.equal(sock.sent[1].event,'presence');
// Presence contains more than one publisher under role B (simulates two clients).
sock.onmessage({data:JSON.stringify({event:'presence_state',payload:{B:{metas:[{phx_ref:'b1',state:'idle'},{phx_ref:'b2',state:'busy'}]}}})});
assert.equal(r.live,true);
sock.onmessage({data:JSON.stringify({event:'presence_diff',payload:{joins:{},leaves:{B:{metas:[{phx_ref:'b1'}]}}}})});
assert.equal(r.live,true,'removing one of two B sessions must not hide remaining B');
assert.equal(r.state.B.metas.length,1);
sock.onmessage({data:JSON.stringify({event:'presence_diff',payload:{joins:{},leaves:{B:{metas:[{phx_ref:'b2'}]}}}})});
assert.equal(r.live,false);
// On reconnect the Phoenix join sequence must start at 1 again.
r.lost(sock);
await r.start();
sock=sockets.at(-1);
sock.onopen();
assert.equal(sock.sent[0].ref,'1','reconnect must reset request ref to 1');
sock.onmessage({data:JSON.stringify({event:'phx_reply',ref:'1',payload:{status:'ok'}})});
assert.equal(r.joined,true,'joined must become true again after reconnect');
r.close();
console.log('PASS v2.0.61.1 Realtime reconnect / shared-key Presence diff');
