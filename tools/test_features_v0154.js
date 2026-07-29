'use strict';
const fs=require('fs'),path=require('path');
const root=path.resolve(process.argv[2]||'.');
const app=fs.readFileSync(path.join(root,'app.js'),'utf8');
const css=fs.readFileSync(path.join(root,'styles.css'),'utf8');
const tests={
  'rpc breakthrough status':app.includes("rpc/get_breakthrough_status_v0154"),
  'rpc breakthrough attempt':app.includes("rpc/attempt_breakthrough_v0154"),
  'pill selector':app.includes('data-breakthrough-pill-delta')&&app.includes('渡境清元丹'),
  'optimistic ordinary':app.includes("optimisticTechniqueUpgradeV0154('ordinary'"),
  'optimistic exclusive':app.includes("optimisticTechniqueUpgradeV0154('exclusive'"),
  'background queue':app.includes('processTechniqueUpgradeQueueV0154')&&app.includes('techniqueUpgradeQueue'),
  'no upgrade busy label':!app.includes("setBusy(button, true, '升级中"),
  'result modal no enterGame default':/function showResultModal[\s\S]*?typeof onContinue === 'function'/.test(app),
  'rate clickable':app.includes('cultivationRateBreakdownBtn')&&app.includes('openCultivationRateBreakdownV0154'),
  'rate technique details':app.includes('普通功法明细')&&app.includes('专属功法明细'),
  'effect excludes techniques':app.includes("key.startsWith('opptech:') || key.startsWith('exclusive:')"),
  'treasure entry':app.includes('珍宝阁')&&app.includes('data-purchase-treasure'),
  'washing confirm':app.includes('openSpiritWashingPillModal')&&app.includes('确认重塑灵根'),
  'b02 collapse ui':app.includes('道果崩解0.3%')&&app.includes("critical: '濒死'"),
  'treasure immediate local inventory':app.includes('applyTreasurePurchaseResultV0154')&&app.includes('inventory_quantity')&&app.includes('已收入储物袋，可立即使用'),
  'treasure background correction ordered':app.includes('await refreshInventoryV0147();\n              renderCaveSystemFromState();'),
  'treasure no stale concurrent cave render':!app.includes('Promise.all([refreshTreasureShopV0154(true), refreshInventoryV0147(), refreshCaveSystem(false)])'),
  'new css':css.includes('V0.15.4 FIX5 CACHE25')&&css.includes('.rate-detail-modal')&&css.includes('.treasure-shop-grid')
};
let fail=0;for(const [n,o] of Object.entries(tests)){console.log(`${o?'PASS':'FAIL'} ${n}`);if(!o)fail++;}
console.log(`TOTAL=${Object.keys(tests).length} PASS=${Object.keys(tests).length-fail} FAIL=${fail}`);process.exit(fail?1:0);
