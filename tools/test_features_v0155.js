'use strict';
const fs=require('fs'),path=require('path');const root=path.resolve(process.argv[2]||'.');
const app=fs.readFileSync(path.join(root,'app.js'),'utf8'),css=fs.readFileSync(path.join(root,'styles.css'),'utf8'),config=fs.readFileSync(path.join(root,'config.js'),'utf8');
const tests={
 'primordial navigation':app.includes("['primordial', '元', '元神']")&&app.includes('data-mobile-screen="primordial"'),
 'desktop primordial navigation':app.includes('href="#primordialSpiritSection">元神</a>'),
 'primordial panel preserved':(app.includes('primordialSpiritPanelHtmlV0155')||app.includes('primordialSpiritPanelHtmlV1')),
 'four named combat stats':['道攻','道御','生机','身法'].every(x=>app.includes(x)),
 'authoritative or explicit placeholder':app.includes('get_my_battle_snapshot_v1')||app.includes('不会生成伪造数据'),
 'cultivation animation':app.includes('yuanshen-cultivator-v0155')&&app.includes('yuanshen-ring-v0155')&&css.includes('@keyframes yuanshen-meridian-v0155'),
 'responsive primordial UI':css.includes('@media (max-width: 620px)')&&css.includes('.yuanshen-stage-v0155'),
 'B cave integrated':app.includes('cave-scene-b01')&&app.includes('CAVE_STORAGE_SLOT_COUNT_B01 = 36'),
 'supported release config':config.includes("buildId: 'v1-1-cache35'")||config.includes("buildId: 'v1-fix4-cache34'")||config.includes("buildId: 'v1-fix3-cache33'")||config.includes("buildId: 'v1-fix2-cache32'")||config.includes("buildId: 'v1-fix1-cache31'")||config.includes("buildId: 'v0155-fix1-cache27'")
};let failed=0;for(const [name,ok] of Object.entries(tests)){console.log(`${ok?'PASS':'FAIL'} ${name}`);if(!ok)failed++;}console.log(`TOTAL=${Object.keys(tests).length} PASS=${Object.keys(tests).length-failed} FAIL=${failed}`);process.exit(failed?1:0);
