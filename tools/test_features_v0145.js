const fs=require('fs'),path=require('path');
const root=path.resolve(process.argv[2]||process.argv[1]||'.');
const app=fs.readFileSync(path.join(root,'app.js'),'utf8');
const css=fs.readFileSync(path.join(root,'styles.css'),'utf8');
const sql=fs.readFileSync(path.join(root,'database/V0.14.5/202607272330_v0145_opportunity_v4_techniques_player_house_commission.sql'),'utf8');
const checks=[]; const ck=(n,o)=>checks.push([n,!!o]);
[
 ['v4-rpc',app.includes('rpcSettleOpportunityV4')],['ack-rpc',app.includes('rpcAckOpportunitySummaryV4')],['offline-summary',app.includes('showOpportunityOfflineSummary')],['mobile-modal',css.includes('.opportunity-offline-summary')],['safe-area',css.includes('env(safe-area-inset-bottom)')],
 ['new-techniques',app.includes('techniques_new')&&app.includes('techniques_duplicate')],['mastery',app.includes('mastery_points')],['commission-copy',app.includes('5%')&&app.includes('全服造化池')],['system-fix7a',app.includes('系统庄沿用FIX7A')],
 ['story-pool',sql.includes('opportunity_v4_story_pool')],['result-pool',sql.includes('opportunity_v4_result_pool')],['support-seeds',(sql.match(/\('opp_support_/g)||[]).length>=24],['five-minute',sql.includes('online_interval_seconds=300')&&sql.includes('offline_interval_seconds=300')],['864',sql.includes('offline_catchup_limit=864')],['commission-500',sql.includes('player_house_win_commission_bps=500')],['rls',sql.includes('opportunity_v4_settlement_batches enable row level security')],
 ['old-protections',app.includes('境界保持不变')&&app.includes('应局并立即开契')&&app.includes('showDivineNoticeModal')],['dealer-name',app.includes('荷老')&&!app.includes('何老')]
].forEach(([n,o])=>ck(n,o));
const failed=checks.filter(x=>!x[1]); checks.forEach(x=>console.log(x[1]?'PASS':'FAIL',x[0])); console.log(`TOTAL=${checks.length} PASS=${checks.length-failed.length} FAIL=${failed.length}`); process.exit(failed.length?1:0);
