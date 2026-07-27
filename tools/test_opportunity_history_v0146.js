'use strict';
const fs=require('fs'),path=require('path');
const root=path.resolve(process.argv[2]||process.argv[1]||'.');
const app=fs.readFileSync(path.join(root,'app.js'),'utf8');
const checks=[
 ['RPC',app.includes('rpcGetOpportunityHistoryV0146')],
 ['merge',app.includes('mergeHistoryWithOpportunityResults')],
 ['initial refresh',app.includes('Number(opportunitySettlement?.events_resolved || 0) > 0')],
 ['online refresh',app.includes('Number(settlement?.events_resolved || 0) > 0) await refreshOpportunityHistoryTimeline()')],
 ['specific result',app.includes("result?.reward_text || result?.result_text")&&app.includes("result?.penalty_text || result?.result_text")],
 ['history root',app.includes('id="historyTimelineRoot"')]
];
for(const [n,o] of checks) console.log(o?'PASS':'FAIL',n);
if(checks.some(x=>!x[1])) process.exit(1);
console.log(`TOTAL=${checks.length} PASS=${checks.length} FAIL=0`);
