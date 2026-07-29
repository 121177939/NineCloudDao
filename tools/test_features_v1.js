'use strict';
const fs=require('fs'),path=require('path');const root=path.resolve(process.argv[2]||'.');
const app=fs.readFileSync(path.join(root,'app.js'),'utf8'),css=fs.readFileSync(path.join(root,'styles.css'),'utf8');
const checks={
 'snapshot rpc client':app.includes("rpcGetMyBattleSnapshotV1")&&app.includes("rpc/get_my_battle_snapshot_v1"),
 'live primordial panel':app.includes('primordialSpiritPanelHtmlV1')&&app.includes("value('attack')")&&app.includes("value('defense')")&&app.includes("value('vitality')")&&app.includes("value('agility')")&&app.includes("value('power')"),
 'exact mobile order':css.includes('.yuanshen-stat-card-v0155.left-1 { order:2; }')&&css.includes('.yuanshen-stat-card-v0155.left-2 { order:3; }')&&css.includes('.yuanshen-stat-card-v0155.right-1 { order:4; }')&&css.includes('.yuanshen-stat-card-v0155.right-2 { order:5; }')&&css.includes('.yuanshen-stat-card-v0155.right-3 { order:6; }')&&css.includes('.yuanshen-stat-card-v0155.left-3 { order:7; }'),
 'three columns mobile':css.includes('grid-template-columns:repeat(3,minmax(0,1fr))'),
 'cave rich layers':['cave-depth-shrine-v1','cave-waterfall-v1','cave-qi-wisps-v1','cave-fireflies-v1','cave-pond-v1','cave-stairs-v1','cave-bonsai-v1'].every(x=>app.includes(x)),
 'cave animations':['@keyframes caveWaterfallV1','@keyframes caveQiWispV1','@keyframes caveFireflyV1','@keyframes cavePondGlowV1'].every(x=>css.includes(x)),
 'unlearned techniques in storage':app.includes('caveTechniqueBookStorageItemsV1')&&app.includes('!row.is_learned')&&app.includes('data-open-cave-technique-book'),
 'visible item name and type':app.includes('cave-item-name-b01')&&app.includes('cave-item-type-b01')&&app.includes("'功法'"),
 '30 slots and paging':app.includes('CAVE_STORAGE_SLOT_COUNT_B01 = 30')&&app.includes('data-cave-storage-page'),
 'battle ranking and challenge':['get_battle_power_ranking_bcombat01','get_battle_challenge_preview_bcombat01','challenge_battle_power_bcombat01','claim_battle_cultivation_escrow_bcombat01'].every(x=>app.includes(x)),
 '80 percent cap copy preserved':app.includes('80%')||app.includes('80％')
};let fail=0;for(const [n,ok] of Object.entries(checks)){console.log(`${ok?'PASS':'FAIL'} ${n}`);if(!ok)fail++;}console.log(`TOTAL=${Object.keys(checks).length} PASS=${Object.keys(checks).length-fail} FAIL=${fail}`);process.exit(fail?1:0);
