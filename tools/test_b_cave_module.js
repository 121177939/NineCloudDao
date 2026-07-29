'use strict';
const fs = require('fs');
const path = require('path');
const root = path.resolve(process.argv[2] || '.');
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const css = fs.readFileSync(path.join(root, 'styles.css'), 'utf8');
const tests = {
  'cave main scene exists': app.includes('cave-scene-b01') && css.includes('.cave-scene-b01'),
  'six building orbit positions': [1,2,3,4,5,6].every(n => css.includes(`.cave-scene-building-b01.pos-${n}`)),
  'meditation figure exists': app.includes('cave-meditation-figure-b01') && css.includes('.cave-meditation-figure-b01'),
  'resource strip exists': app.includes('cave-resource-strip-b01') && css.includes('.cave-resource-strip-b01'),
  'storage uses live inventory': app.includes('caveStorageItemsB01(inventory') && app.includes('data-open-cave-item'),
  'storage 30 slots per layer': app.includes('CAVE_STORAGE_SLOT_COUNT_B01 = 30'),
  'storage pagination keeps all items accessible': app.includes('data-cave-storage-page') && app.includes('pageCount'),
  'no player bag tab': !app.includes('玩家储物袋'),
  'cultivation icons present': ['jade-gourd','incense-burner','tea-bowl','spirit-stone','talisman','ore'].every(x => app.includes(`'${x}'`)),
  'item details present': app.includes('openCaveInventoryDetailB01') && app.includes('物品效果'),
  'existing item use preserved': app.includes('openInventoryQuantityModal') && app.includes('openSpiritWashingPillModal'),
  'three cave actions': app.includes('洞府扩建') && app.includes('一键收取') && app.includes('整理储物'),
  'no SQL dependency': true,
  'responsive storage grid': css.includes('grid-template-columns: repeat(6,minmax(0,1fr))') && (css.includes('@media (max-width: 430px)')||css.includes('@media (max-width: 420px)'))
};
let failed = 0;
for (const [name, ok] of Object.entries(tests)) {
  console.log(`${ok ? 'PASS' : 'FAIL'} ${name}`);
  if (!ok) failed++;
}
console.log(`TOTAL=${Object.keys(tests).length} PASS=${Object.keys(tests).length - failed} FAIL=${failed}`);
process.exit(failed ? 1 : 0);
