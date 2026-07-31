#!/usr/bin/env node
'use strict';
const fs=require('fs'),vm=require('vm'),path=require('path');
const source=fs.readFileSync(path.join(process.argv[2]||path.join(__dirname,'..'),'paigow-realtime.js'),'utf8');
const listeners={window:new Map(),document:new Map()};
function add(scope,type,fn){if(!listeners[scope].has(type))listeners[scope].set(type,new Set());listeners[scope].get(type).add(fn)}
function remove(scope,type,fn){listeners[scope].get(type)?.delete(fn)}
class FakeWebSocket{
  static OPEN=1;static CONNECTING=0;static CLOSING=2;static instances=[];
  constructor(url){this.url=url;this.readyState=0;this.handlers=new Map();this.sent=[];FakeWebSocket.instances.push(this)}
  addEventListener(type,fn){if(!this.handlers.has(type))this.handlers.set(type,new Set());this.handlers.get(type).add(fn)}
  emit(type,data={}){for(const fn of this.handlers.get(type)||[])fn(data)}
  send(data){this.sent.push(JSON.parse(data))}
  close(){this.readyState=3;this.emit('close',{})}
}
const context={console,setTimeout,clearTimeout,setInterval,clearInterval,URL,WebSocket:FakeWebSocket,
  window:{addEventListener:(t,f)=>add('window',t,f),removeEventListener:(t,f)=>remove('window',t,f)},
  document:{hidden:false,addEventListener:(t,f)=>add('document',t,f),removeEventListener:(t,f)=>remove('document',t,f)}};
context.window.window=context.window;vm.createContext(context);vm.runInContext(source,context);
const Client=context.window.JiuxiaoPaigowRealtimeClient;if(typeof Client!=='function')throw new Error('CLIENT_NOT_EXPORTED');
const statuses=[],received=[];
const client=new Client({url:'https://example.supabase.co',key:'publishable',getAccessToken:async()=> 'jwt-token',onStatus:s=>statuses.push(s)});
const unsubscribe=client.subscribe('paigow:room:00000000-0000-0000-0000-000000000001',msg=>received.push(msg));
const socket=FakeWebSocket.instances[0];if(!socket.url.includes('/realtime/v1/websocket?apikey=publishable&vsn=1.0.0'))throw new Error('BAD_WS_URL');
socket.readyState=FakeWebSocket.OPEN;socket.emit('open',{});
setTimeout(()=>{
  const join=socket.sent.find(x=>x.event==='phx_join');
  if(!join||join.payload?.config?.private!==true||join.payload?.access_token!=='jwt-token')throw new Error('BAD_PRIVATE_JOIN');
  socket.emit('message',{data:JSON.stringify({topic:join.topic,event:'phx_reply',payload:{status:'ok'},ref:join.ref,join_ref:join.join_ref})});
  socket.emit('message',{data:JSON.stringify({topic:join.topic,event:'broadcast',payload:{event:'paigow_state_changed',payload:{room_version:2,delta:{kind:'member'}}}})});
  if(received.length!==1||received[0].payload.room_version!==2)throw new Error('BROADCAST_NOT_DISPATCHED');
  unsubscribe();client.destroy();
  if(!statuses.includes('subscribed'))throw new Error('SUBSCRIBE_STATUS_MISSING');
  if((listeners.window.get('online')?.size||0)!==0||(listeners.document.get('visibilitychange')?.size||0)!==0)throw new Error('LISTENER_LEAK');
  console.log('PASS private join');console.log('PASS broadcast dispatch');console.log('PASS unsubscribe and destroy');
},20);
