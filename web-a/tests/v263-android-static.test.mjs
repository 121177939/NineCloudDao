import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
// Android source checks: no crash-silent claim, no inert realtime wake, no removed STOP barriers.
const root=new URL('../../',import.meta.url);
const release=JSON.parse(readFileSync(new URL('VERSION.json',root),'utf8'));
const b=readFileSync(new URL(`${release.androidB}/app/src/main/java/com/example/remoteb/RemoteAccessibilityService.kt`,root),'utf8');
for(const marker of ['Channel.CONFLATED','queueWakeups.trySend(Unit)','withTimeoutOrNull(5_000L) { queueWakeups.receive() }',
  'claim_intent_id','GLOBAL_STOP_CHECK_STALE','TASK_STOP_CHECK_STALE','submitted_unknown',
  'return_to_editor_pending','task_worker_running'])assert.ok(b.includes(marker),`missing B invariant: ${marker}`);
assert.match(b,/SystemClock\.elapsedRealtime\(\) - globalControlOkAt > 7_000L/);
assert.match(b,/SystemClock\.elapsedRealtime\(\) - stopCheckOkAt > 7_000L/);
for(const role of ['remotea','remoteb']){
  const file=readFileSync(new URL(`${role==='remotea'?release.androidA:release.androidB}/app/src/main/java/com/example/${role}/GamePresence.kt`,root),'utf8');
  for(const marker of ['SOCKET_OPEN_TIMEOUT','JOIN_TIMEOUT','HEARTBEAT_ACK_TIMEOUT','current.cancel()','pendingHeartbeatRef'])
    assert.ok(file.includes(marker),`${role} missing ${marker}`);
}
console.log('PASS v2.0.63 Android B wake/claim/STOP and A/B realtime watchdog invariants');
