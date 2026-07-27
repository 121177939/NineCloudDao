const fs=require('fs');
const app=fs.readFileSync(process.argv[2]||'source/candidate/app.js','utf8');
const css=fs.readFileSync(process.argv[3]||'source/candidate/styles.css','utf8');
const checks=[
['v4 rpc',app.includes("rpc/settle_opportunity_v4")],
['ack rpc',app.includes("rpc/ack_opportunity_v4_summary")],
['mobile modal',app.includes('opportunity-offline-summary')],
['grade summary',app.includes('opportunityGradeSummaryHtml')],
['net summary',app.includes('本次最终所得')],
['no timeline list',!app.includes('查看本次机缘详情')],
['mobile media',css.includes('@media(max-width:520px)')],
['safe area',css.includes('safe-area-inset-bottom')],
['login settles v4',app.includes('const opportunitySettlement = await rpcSettleOpportunityV4()')],
['refresh settles v4',app.includes('const settlement = await rpcSettleOpportunityV4()')]
];
let fail=0;for(const [n,p] of checks){console.log(`${p?'PASS':'FAIL'} ${n}`);if(!p)fail++;}process.exit(fail?1:0);
