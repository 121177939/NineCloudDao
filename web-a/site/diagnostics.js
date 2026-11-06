/** TwoPhoneRemote 2.0.63.1 local structured diagnostic logger.
 * Always log event categories, not free-form backend messages, user input or credentials.
 * No remote upload; localStorage retention is bounded, and private mode degrades to memory.
 */
const KEY='twophone-diagnostics-v262';
const KEEP=7*86400000, MAX=900;
const memory=[];
const clean=(v)=>String(v??'').replace(/[^a-zA-Z0-9_.:-]/g,'_').slice(0,75);
function load(){
  try {const x=JSON.parse(localStorage.getItem(KEY)||'[]');return Array.isArray(x)?x:memory;}catch{return memory;}
}
function save(items){
  memory.splice(0,memory.length,...items);
  try{localStorage.setItem(KEY,JSON.stringify(items));}catch{}
}
/** Route names are intentionally reduced to table/RPC names, never IDs/query strings. */
export function diagRoute(path){
  const route=String(path||'').split('?')[0];
  let match=route.match(/^\/rest\/v1\/rpc\/(remote_[a-z0-9_]+)/);
  if(match)return 'rpc.'+match[1];
  match=route.match(/^\/rest\/v1\/([a-z0-9_]+)/i);
  if(match)return 'table.'+match[1];
  if(route.startsWith('/auth/v1/token'))return 'auth.token';
  if(route.startsWith('/auth/v1/signup'))return 'auth.signup';
  if(route.startsWith('/storage/v1/'))return 'storage.object';
  return 'other';
}
export function diagEvent(area,event,{status=0,elapsedMs=-1,error=null}={}){
  const row={at:new Date().toISOString(),role:'WAP',area:clean(area),event:clean(event),
    http:Number.isInteger(Number(status))?Math.max(0,Math.min(999,Number(status))):0,
    elapsed_ms:Math.max(-1,Math.min(600000,Math.round(Number(elapsedMs)||-1))),
    exception:clean(error?.name||error?.constructor?.name||'none')};
  const items=load().filter(x=>x&&Date.parse(x.at)>Date.now()-KEEP).slice(-MAX+1);
  items.push(row);save(items);
  return row;
}
export function diagText(){
  const rows=load();
  return 'TwoPhoneRemote WAP 2.0.63.1 | Local diagnostic report\n'+
    'Exported: '+new Date().toISOString()+'\n'+
    'No passwords, tokens, email addresses, request bodies or lottery numbers are collected.\n'+
    'Events are best-effort and may be unavailable when the page is terminated abruptly.\n\n'+
    rows.map(x=>`${x.at} | ${x.role} | ${x.area} | ${x.event} | http=${x.http} | elapsed_ms=${x.elapsed_ms} | exception=${x.exception}`).join('\n');
}
export function diagDownload(){
  const url=URL.createObjectURL(new Blob([diagText()],{type:'text/plain;charset=utf-8'}));
  const a=document.createElement('a');a.href=url;a.download='TwoPhoneRemote-WAP-diagnostic-'+Date.now()+'.txt';
  document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);
}
export async function diagCopy(){
  await navigator.clipboard.writeText(diagText());
}
if(typeof window!=='undefined'){
  window.addEventListener('error',e=>diagEvent('page','UNCAUGHT_ERROR',{error:e.error||new Error('UnhandledError')}));
  window.addEventListener('unhandledrejection',e=>diagEvent('page','UNHANDLED_PROMISE',{error:e.reason instanceof Error?e.reason:new Error('PromiseRejected')}));
  window.addEventListener('online',()=>diagEvent('network','BROWSER_ONLINE'));
  window.addEventListener('offline',()=>diagEvent('network','BROWSER_OFFLINE'));
  diagEvent('page','PAGE_LOADED');
}
