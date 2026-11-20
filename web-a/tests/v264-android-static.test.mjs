import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const root = new URL('../../', import.meta.url);
const release = JSON.parse(readFileSync(new URL('VERSION.json', root), 'utf8'));
const a = readFileSync(new URL(`${release.androidA}/app/src/main/java/com/example/remotea/MainActivity.kt`, root), 'utf8');
const aApi = readFileSync(new URL(`${release.androidA}/app/src/main/java/com/example/remotea/SupabaseApi.kt`, root), 'utf8');
const aPolicy = readFileSync(new URL(`${release.androidA}/app/src/main/java/com/example/remotea/OneTapStopReleasePolicy.kt`, root), 'utf8');
const b = readFileSync(new URL(`${release.androidB}/app/src/main/java/com/example/remoteb/RemoteAccessibilityService.kt`, root), 'utf8');

for (const marker of [
  'Channel.CONFLATED', 'queueWakeups.trySend(Unit)',
  'withTimeoutOrNull(5_000L) { queueWakeups.receive() }',
  'claim_intent_id', 'awaitFreshRemoteControls', 'REMOTE_CONTROL_WAITING',
  'submitted_unknown', 'return_to_editor_pending', 'task_worker_running'
]) assert.ok(b.includes(marker), `missing B invariant: ${marker}`);
assert.match(b, /RemoteControlRecoveryPolicy\.isFresh\(globalControlOkAt, now\)/);
assert.match(b, /RemoteControlRecoveryPolicy\.isFresh\(stopCheckOkAt, now\)/);
assert.ok(b.includes('verifyNoRemoteStopBeforeFinish(id)'), 'pre-submit STOP recheck must remain');

for (const role of ['remotea', 'remoteb']) {
  const file = readFileSync(new URL(`${role === 'remotea' ? release.androidA : release.androidB}/app/src/main/java/com/example/${role}/GamePresence.kt`, root), 'utf8');
  assert.ok(file.includes('pingInterval(20, TimeUnit.SECONDS)'), `${role} must retain OkHttp transport ping`);
  assert.ok(file.includes('taskWake?.invoke()'), `${role} must retain optional queue wake callback`);
  assert.ok(file.includes('scheduleWithFixedDelay'), `${role} must keep the isolated presence timer`);
  assert.ok(!file.includes('current.cancel()'), `${role} must not force-cancel the socket from the watchdog path`);
  assert.ok(!file.includes('HEARTBEAT_ACK_TIMEOUT'), `${role} uses conservative transport recovery`);
}
assert.ok(aApi.includes('remote_v260_queue_diagnostics'), 'A must have read-only queue reconciliation RPC');
assert.ok(aApi.includes('compat_read_fallback') && aApi.includes('firstActiveTask()') &&
  aApi.includes('unresolvedStopRecords()'), 'A must fall back to existing read APIs when v260 diagnostic RPC is absent');
assert.ok(aApi.includes('remote_v257_resume_queue'), 'A must use the guarded server queue-resume RPC');
assert.ok(a.includes('api.resumeQueue()'), 'A must release a held queue only after verified B resume and zero unresolved work');
const preflightAt = a.indexOf('snapshotBlocker(diagnostics, requireQueueOpen = false)');
const queueResumeAt = a.indexOf('api.resumeQueue()', preflightAt);
const queueRecheckAt = a.indexOf('api.queueDiagnostics()', queueResumeAt);
const finalPolicyAt = a.indexOf('mayFinalizeReconciledResume', queueRecheckAt);
assert.ok(preflightAt >= 0 && queueResumeAt > preflightAt && queueRecheckAt > queueResumeAt &&
  finalPolicyAt > queueRecheckAt, 'queue resume must be preflighted, performed, then re-read before unlock');
assert.ok(a.includes('mayFinalizeReconciledResume'), 'A must reconcile a verified resume/ack state');
assert.ok(a.includes('queueHeld=$heldAfter'), 'A must report exact queue blockers after server recheck');
assert.ok(aPolicy.includes('activeTasks == 0L') && aPolicy.includes('openStops == 0L'),
  'A local unlock must require empty cloud tasks and closed STOP evidence');

console.log('PASS current Android stability, B claim/STOP barriers and verified resume recovery');
