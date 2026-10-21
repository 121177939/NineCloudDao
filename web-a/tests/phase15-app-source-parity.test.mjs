import assert from 'node:assert/strict';
import fs from 'node:fs';import vm from 'node:vm';
import {createPreviewModel} from '../site/preview-model.js';
function load(ref){const ctx={};vm.runInNewContext(fs.readFileSync(ref,'utf8'),ctx);return ctx.parser.com.example.remotea.WebParser;}
const now=load(new URL('../site/parser.js',import.meta.url));
const cases=[
 '01245679头01236789百12345689十01235678尾打1角\n147369头百十尾各1角排列',
 '147369头百十尾各1角',
 '0123456789头16尾各2元',
 '147369头147369百147369十147369尾各1角',
 '123头 123百 123十 123尾各1元',
 '第1位:123', // invalid should remain invalid
 '678—387各2元',
 '67-57X38各1元',
 '67X68-38各1元',
 '2X74、2XX4各20元',
 '1234-1234各1',
 '1234各1元，12头34尾各1元',
 '五子，全头16尾各2元，七星，678—387各2元',
 '12头34尾各1元，12头34尾各1元',
 '完全无关文字',
 '1234全转各1'
];
let checked=0;
for (const raw of cases){
 const current=JSON.parse(now.inspect(raw));
 assert.equal(typeof current.valid,'boolean',raw);
 assert.ok(Array.isArray(current.scatter)&&Array.isArray(current.suites)&&Array.isArray(current.issues),raw);
 if(current.valid){
   const plan=JSON.parse(now.plan(raw,false,false));
   assert.equal(plan.command.split('|R=')[0],current.command,`plan/inspect core wire invariant (R is plan option) for ${raw}`);
   assert.equal(current.totalJiao,plan.totalJiao,`plan / inspect total invariant for ${raw}`);
 }
 if(current.valid&&current.suites.length){
   const preview=createPreviewModel(raw,current);
   for(const row of preview.suites){
     if(row.matched){assert.equal(raw.slice(row.start,row.end),row.source);}
   }
 }
 checked++;
}
const incident=cases[0];const newRows=createPreviewModel(incident,JSON.parse(now.inspect(incident))).suites;
assert.equal(newRows[1].status,'正常');
assert.equal(newRows[1].source,'147369头百十尾');
assert.equal(newRows[1].start,40);assert.equal(newRows[1].end,50);
// Duplicate authoritative entries must claim distinct spans, not borrow the same one.
const duplicates=createPreviewModel('12头34尾各1元，12头34尾各1元',JSON.parse(now.inspect('12头34尾各1元，12头34尾各1元')));
assert.ok(duplicates.suites.every(x=>x.matched));assert.ok(duplicates.suites[0].end<=duplicates.suites[1].start);
const mismatch=createPreviewModel('任意无关文字',{suites:[{source:'147369头百十尾',canonical:'147369头147369百147369十147369尾=0.1',amountJiao:1,expectedCount:1296}]});
assert.equal(mismatch.reviewCount,1);
console.log(`PASS: ${checked} current Kotlin/JS inspect/plan invariant scenarios, exact ranges, duplicate-safe/fail-closed`);
