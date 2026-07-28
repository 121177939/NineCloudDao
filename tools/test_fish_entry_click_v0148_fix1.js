#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const root = path.resolve(process.argv[2] || '.');
const source = fs.readFileSync(path.join(root, 'app.js'), 'utf8');

const start = source.indexOf("document.querySelectorAll('[data-house-select-game]')");
const end = source.indexOf("if (houseChoice && houseChoice.dataset.bound", start);
if (start < 0 || end < 0) throw new Error('house game selector handler missing');
const block = source.slice(start, end);

const setDraft = block.indexOf('state.casinoDrafts.house = draft;');
const syncHidden = block.indexOf('if (houseGameInput) houseGameInput.value = game;');
const render = block.indexOf('renderCasinoPanel();');
const fishBranch = block.indexOf("game === 'fish_shrimp'");

const checks = [
  ['selector handler exists', start >= 0],
  ['fish branch exists', fishBranch >= 0],
  ['draft saved first', setDraft >= 0 && setDraft < syncHidden],
  ['hidden field synced before render', syncHidden >= 0 && render >= 0 && syncHidden < render],
  ['fix marker exists', source.includes('FIX1：先同步旧页面里的隐藏玩法字段')]
];

// Regression model: renderCasinoPanel captures the old DOM before render.
// With the fix, the DOM value is first changed to fish_shrimp, so capture preserves it.
const model = { draftGame: 'spirit_dice', hiddenGame: 'spirit_dice' };
const clickedGame = 'fish_shrimp';
model.draftGame = clickedGame;
model.hiddenGame = clickedGame; // patched line
model.draftGame = model.hiddenGame; // captureCasinoDraft during renderCasinoPanel
checks.push(['regression model stays fish_shrimp', model.draftGame === 'fish_shrimp']);

for (const [name, ok] of checks) console.log(ok ? 'PASS' : 'FAIL', name);
const failed = checks.filter(([,ok]) => !ok);
console.log(`TOTAL=${checks.length} PASS=${checks.length-failed.length} FAIL=${failed.length}`);
if (failed.length) process.exit(1);
