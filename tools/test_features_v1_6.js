#!/usr/bin/env node
'use strict';
const fs=require('fs'),path=require('path');
const root=path.resolve(process.argv[2]||path.join(__dirname,'..'));
const read=r=>fs.readFileSync(path.join(root,r),'utf8');
const pg=read('paigow-app.js'),rt=read('paigow-realtime.js'),html=read('b-paigow01.html'),index=read('index.html'),loader=read('b-paigow01.js'),config=read('config.js'),sw=read('sw.js'),wf=read('.github/workflows/deploy-pages.yml'),main=read('SQL/91_V1.6_九霄牌九事件驱动与主游戏隔离.sql'),gate=read('SQL/92_V1.6_CACHE44_正式发布门禁.sql'),post=read('SQL/93_V1.6_CACHE44_升级后检查.sql'),v15=read('SQL/88_V1.5_九霄牌九资金门槛与庄家比例结算.sql');
const checks={
  'CACHE44 build':config.includes("version: '1.6.0'")&&config.includes("buildId: 'v1-6-cache44'")&&config.includes('cacheEpoch: 44'),
  'all launchers CACHE44':index.includes('b-paigow01.js?v=v1-6-cache44')&&loader.includes("v: 'v1-6-cache44'")&&html.includes('paigow-realtime.js?v=v1-6-cache44')&&html.includes('paigow-app.js?v=v1-6-cache44')&&sw.includes('nine-cloud-dao-v1.6-cache44'),
  'no high frequency polling':!pg.includes('setInterval(pollOnce')&&!pg.includes('state.poll')&&!pg.includes('}, 1000)')&&!pg.includes('}, 5000)'),
  'low frequency safety sync':pg.includes('state.roomId ? 60000 : 120000'),
  'one shot deadline fallback':pg.includes('deadlineAdvanceKey')&&pg.includes("reason: 'deadline_fallback'")&&pg.includes('state.deadlineAdvanceKey === due.key'),
  'private realtime client':rt.includes('private: true')&&rt.includes("event: 'phx_join'")&&rt.includes("this.send('phoenix', 'heartbeat'")&&rt.includes('presence: { enabled: false }'),
  'delta state merge':pg.includes('applyRealtimeDelta')&&pg.includes("kind === 'member'")&&pg.includes("kind === 'round_player'")&&pg.includes('payload?.snapshot_required !== false'),
  'snapshot version recovery':pg.includes('roomEventVersion')&&pg.includes('lobbyEventVersion')&&pg.includes('numericVersion <= state.roomSnapshotVersion'),
  'iframe full shutdown':loader.includes("postMessage({ type: 'b-paigow01-pause' }")&&loader.includes("frame.src = 'about:blank'")&&pg.includes('shutdownPaigowRuntime')&&pg.includes('state.realtime?.destroy?.()'),
  'service worker includes realtime':sw.includes("'./paigow-realtime.js?v=v1-6-cache44'"),
  'database remains authoritative':main.includes('paigow_start_round_internal_v16_bpaigow01')&&main.includes('paigow_settle_round_internal_bpaigow01')&&main.includes('revoke all on function public.paigow_emit_state_event'),
  'broadcast contains no private cards':main.includes("'delta',coalesce(p_delta")&&!main.slice(main.indexOf('create or replace function public.paigow_emit_state_event_payload'),main.indexOf('create or replace function public.paigow_emit_state_event_v16')).includes('shuffled_deck'),
  'pure snapshots':main.includes('纯读取大厅快照')&&main.includes('纯读取房间快照')&&main.includes('sync_mode\',\'realtime_broadcast'),
  'single cron':main.includes("'jiuxiao-paigow-v16-tick'")&&main.includes("'1 second'")&&main.includes('pg_try_advisory_xact_lock'),
  'V1.5 money rules retained':v15.includes('v_profit_pay_total:=least(v_profit_pool,v_winner_claim)')&&v15.includes('paigow_big_tie_fee_refund_v15')&&v15.includes('PAIGOW_CULTIVATION_STAKES_TEMPORARILY_DISABLED'),
  'portable workflow':wf.includes('python3 tools/ci_v1_6.py .')&&!wf.toLowerCase().includes('playwright')&&!wf.includes('/usr/bin/chromium'),
  'release gate':gate.includes("release_name='V1.6 CACHE44'")&&gate.includes('greatest(cache_epoch,44)'),
  'post check':post.includes('single_global_tick')&&post.includes('broadcast_payload_has_no_cards')
};
for(const [name,ok] of Object.entries(checks)) console.log((ok?'PASS ':'FAIL ')+name);
const failed=Object.entries(checks).filter(([,ok])=>!ok).map(([name])=>name);
console.log(JSON.stringify({ok:!failed.length,checks:Object.keys(checks).length,failed},null,2));
if(failed.length) throw new Error(failed.join(', '));
