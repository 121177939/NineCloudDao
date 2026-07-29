"use strict";
const fs=require('fs'),path=require('path');const root=path.resolve(process.argv[2]||'.');
const app=fs.readFileSync(path.join(root,'app.js'),'utf8'),css=fs.readFileSync(path.join(root,'styles.css'),'utf8'),sql=fs.readFileSync(path.join(root,'SQL/33_V1.0_FIX1_挑战战报参数兼容修复.sql'),'utf8');
const tests={
 'root element chip':app.includes('heroSpiritRootChipHtmlV1')&&app.includes('heroSpiritRootChipV1')&&app.includes('element_name'),
 'fire red':css.includes('.hero-spirit-element-v1.element-fire')&&css.includes('#e06f5f'),
 'yuanshen compressed ten percent':css.includes('min-height:294px')&&css.includes('width:min(100%,257px)'),
 'cave six by six':app.includes('CAVE_STORAGE_SLOT_COUNT_B01 = 36')&&css.includes('grid-template-columns:repeat(6,minmax(0,1fr))'),
 'labels remain visible':css.includes('.cave-item-name-b01')&&css.includes('.cave-item-type-b01'),
 'challenge compatibility overload':sql.includes('p_event_level integer')&&sql.includes('::smallint')&&sql.includes('revoke all on function public.world_event_publish_v0140'),
 'friendly production error':app.includes('V1.0 FIX1 SQL')
};let failed=0;for(const [n,o] of Object.entries(tests)){console.log(`${o?'PASS':'FAIL'} ${n}`);if(!o)failed++;}console.log(`TOTAL=${Object.keys(tests).length} PASS=${Object.keys(tests).length-failed} FAIL=${failed}`);process.exit(failed?1:0);
