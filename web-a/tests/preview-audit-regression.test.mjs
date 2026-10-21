import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {createPreviewModel} from '../site/preview-model.js';

const ctx={};
vm.runInNewContext(fs.readFileSync(new URL('../site/parser.js',import.meta.url),'utf8'),ctx);
const parser=ctx.parser.com.example.remotea.WebParser;
const inspect=text=>JSON.parse(parser.inspect(text));
let checks=0;
const check=(predicate,why)=>{assert.ok(predicate,why);checks++;};

const repeat='12头34尾各1元，12头34尾各1元';
const repeated=createPreviewModel(repeat,inspect(repeat));
check(repeated.suites.length===2,'authoritative two-suite order preserved');
check(repeated.suites.every(s=>s.matched),'both source snippets found');
check(repeated.suites[0].start===0&&repeated.suites[1].start===10,'repeated suite snippets must point to two distinct source regions');
check(repeated.suites[0].end<=repeated.suites[1].start,'same input span must not be claimed twice');

const singleton='1头2尾各1元';
const single=createPreviewModel(singleton,inspect(singleton));
check(single.scatterCount===1&&single.suiteCount===0,'one expanded group is scatter by final count');
check(single.scatter[0].number==='1XX2','one-group positional result mapped to its actual four-slot code');
check(single.scatter[0].source==='1头2尾','audited original positional text preserved');
const mixed=createPreviewModel('1头2尾各1元，3333各1元',inspect('1头2尾各1元，3333各1元'));
check(mixed.scatterCount===2&&mixed.suiteCount===0,'single-group position + normal four digits are one scatter area');

const duplicate=createPreviewModel('1234各1元',{
  scatter:[{number:'1234',amountJiao:10},{number:'1234',amountJiao:10}],
  suites:[],issues:[]
});
check(duplicate.scatter[0].matched&&!duplicate.scatter[1].matched,'missing repeated occurrence must not reuse first source range');
check(duplicate.scatter[1].status==='需确认','unmapped canonical scatter remains visible as review required');

const swapped='1234头1尾各1元，1234各1元';
const noSteal=createPreviewModel(swapped,inspect(swapped));
check(noSteal.scatterCount===1&&noSteal.suiteCount===1,'mixed suite and scatter recognized');
check(noSteal.scatter[0].start===11,'scatter must not borrow number inside an earlier mapped suite');

const forged=createPreviewModel('完全无关原文各1元',{
 scatter:[],suites:[{canonical:'12头34尾=1',source:'原文并不存在的文字',amountJiao:10,expectedCount:4}],issues:[]
});
check(!forged.suites[0].matched&&forged.suites[0].status==='需确认','not-found suite source must never be reported matched');
check(forged.suites[0].detail.includes('无法定位'),'not-found suite must explain audit uncertainty');

const shorthand='1234-1234各1';
const safeShorthand=createPreviewModel(shorthand,inspect(shorthand));
check(safeShorthand.suites[0].source==='1234-1234','supported dash shorthand displays its exact source span without amount');
check(safeShorthand.suites[0].matched&&safeShorthand.suites[0].status==='正常','authoritative head-tail shorthand maps to its exact original source span');

console.log(`PASS: ${checks} Web A preview audit regression assertions`);
