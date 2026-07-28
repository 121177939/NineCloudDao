'use strict';
const fs=require('fs'),path=require('path');
const root=path.resolve(process.argv[2]||path.join(__dirname,'..'));
const app=fs.readFileSync(path.join(root,'source/candidate/app.js'),'utf8');
const css=fs.readFileSync(path.join(root,'source/candidate/styles.css'),'utf8');
const checks=[
 ['library rpc',app.includes("rpc/get_technique_library_v1")],
 ['use book rpc',app.includes("rpc/use_technique_book_v1")],
 ['cave library render',app.includes('function techniqueLibraryHtml')&&app.includes('藏经架')],
 ['ordinary study copy',app.includes('普通功法可研习或参悟')],
 ['exclusive fate copy',app.includes('本命专属可研习，异命专属仅供收藏')],
 ['study button',app.includes('data-use-technique-book')],
 ['no auto equip copy',app.includes('尚未自动装备')],
 ['offline book summary',app.includes('功法书所得')&&app.includes('technique_books')],
 ['online refresh library',app.includes('await refreshCaveSystem(true)')],
 ['mobile css',css.includes('.technique-book-grid')&&css.includes('@media (max-width: 380px)')],
 ['locked css',css.includes('.technique-book-lock')],
 ['legacy history hook',app.includes('Number(settlement?.events_resolved || 0) > 0) await refreshOpportunityHistoryTimeline()')]
];
for(const [name,ok] of checks) console.log(ok?'PASS':'FAIL',name);
const failed=checks.filter(x=>!x[1]);
if(failed.length) process.exit(1);
console.log(`TOTAL=${checks.length} PASS=${checks.length} FAIL=0`);
