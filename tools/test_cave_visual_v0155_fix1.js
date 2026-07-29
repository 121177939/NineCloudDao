'use strict';
const fs=require('fs'),path=require('path');const root=path.resolve(process.argv[2]||'.');
const app=fs.readFileSync(path.join(root,'app.js'),'utf8'),css=fs.readFileSync(path.join(root,'styles.css'),'utf8'),config=fs.readFileSync(path.join(root,'config.js'),'utf8');
const tests={
 'quiet cave semantic label':app.includes('幽静洞窟、灵脉石台与仙府经营主景')||app.includes('幽静洞府主景与建筑'),
 'rock arch layer':app.includes('cave-rock-arch-b01')&&css.includes('.cave-rock-arch-b01'),
 'stalactite layer':app.includes('cave-stalactites-b01')&&css.includes('.cave-stalactites-b01'),
 'spirit vein layer':app.includes('cave-spirit-veins-b01')&&css.includes('@keyframes caveVeinFlowB01'),
 'stone platform':app.includes('cave-stone-platform-b01')&&css.includes('.cave-stone-platform-b01'),
 'secluded cave copy':app.includes('洞天幽居 · 灵脉自运')&&app.includes('仙府隐修'),
 'business layout preserved':[1,2,3,4,5,6].every(n=>css.includes(`.cave-scene-building-b01.pos-${n}`)),
 'real storage preserved':app.includes('CAVE_STORAGE_SLOT_COUNT_B01 = 36')&&app.includes('caveStorageItemsB01(inventory'),
 'cave actions preserved':['洞府扩建','一键收取','整理储物'].every(x=>app.includes(x)),
 'no rotating yuanshen mandala in cave':!css.includes('caveRingB01'),
 'yuanshen animation remains separate':css.includes('@keyframes yuanshen-rotate-cw-v0155')&&app.includes('yuanshen-mandala-v0155'),
 'reduced motion supported':css.includes('.cave-scene-b01 *')&&css.includes('@media (prefers-reduced-motion: reduce)'),
 'supported release build':config.includes("buildId: 'v1-fix3-cache33'")||config.includes("buildId: 'v1-fix2-cache32'")||config.includes("buildId: 'v1-fix1-cache31'")||config.includes("buildId: 'v0155-fix1-cache27'")
};let failed=0;for(const [name,ok] of Object.entries(tests)){console.log(`${ok?'PASS':'FAIL'} ${name}`);if(!ok)failed++;}console.log(`TOTAL=${Object.keys(tests).length} PASS=${Object.keys(tests).length-failed} FAIL=${failed}`);process.exit(failed?1:0);
