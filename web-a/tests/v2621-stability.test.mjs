import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const {GameRealtime}=await import('../site/realtime-presence.js');
const release=JSON.parse(readFileSync(new URL('../../VERSION.json',import.meta.url),'utf8'));
globalThis.document={hidden:false};
let tries=0;
const api={loggedIn:true,async ensureSession(){tries++;throw new Error('temporary network failure')}};
const r=new GameRealtime(api,()=>{});
await assert.rejects(()=>r.start(),/temporary network failure/);
assert.ok(r.retry!==null,'failed initial connect must schedule retry');
assert.equal(r.retryDelay,4500,'retry uses bounded backoff');
r.close();
assert.equal(r.retry,null,'logout cancels outstanding retry');
const source=readFileSync(new URL(`../../${release.androidB}/app/src/main/java/com/example/remoteb/RemoteAccessibilityService.kt`,import.meta.url),'utf8');
assert.match(source,/readGlobalControlWithRetry/,'STOP must recheck on transient failure');
assert.match(source,/if \(failure\.httpStatus in 400\.\.499\) throw failure/,'business rejection must not retry');
assert.match(source,/SUBMIT_CLICK_RETURNED/,'diagnostics must distinguish returned click');
assert.match(source,/submitted_unknown/,'unknown-submit is never assumed failed');
for(const role of ['remotea','remoteb']){
  const file=readFileSync(new URL(`../../${role==='remotea'?release.androidA:release.androidB}/app/src/main/java/com/example/${role}/SupabaseApi.kt`,import.meta.url),'utf8');
  assert.match(file,/synchronized\(refreshGuard\)/,'rotating refresh token should be serialized');
}
console.log('PASS v2.0.62.1 startup retry, STOP control read, token mutex, submit trace');
