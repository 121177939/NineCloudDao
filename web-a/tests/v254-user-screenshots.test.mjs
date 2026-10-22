import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {createPreviewModel} from '../site/preview-model.js';
const ctx={};
vm.runInNewContext(fs.readFileSync(new URL('../site/parser.js',import.meta.url),'utf8'),ctx);
const engine=ctx.parser.com.example.remotea.WebParser;
const cases=[
  {raw:'5989\n3948\n3405\n7733\n6081\n各2\n全倒各0.3',rows:10,turns:5,suites:0},
  {raw:'五：\n\n014569头014569尾各40组。\n\n014569百位014569尾各40组。\n\n014569头014569百位014569十位\n014569尾各0.4组。',rows:3,turns:0,suites:3},
  {raw:'五:\n014569头014569尾各40组。\n014569百位014569尾各40组。\n014569头014569百位014569+1位014569尾各0.4组。',rows:3,turns:0,suites:3},
  {raw:'147369头百十尾各1角',rows:1,turns:0,suites:1}
];
let assertions=0;
for(const {raw,rows,turns,suites} of cases){
  const parsed=JSON.parse(engine.inspect(raw));
  assert.equal(parsed.valid,true,`should recognize: ${raw}`); assertions++;
  assert.equal(parsed.totalLines,rows); assertions++;
  assert.equal(parsed.turnCount,turns); assertions++;
  assert.equal(parsed.suites.length,suites); assertions++;
  const preview=createPreviewModel(raw,parsed);
  assert.equal(preview.reviewCount,0,`original-source audit cannot reject recognized rows: ${raw}`);assertions++;
  assert.equal(preview.normalCount,rows);assertions++;
  assert.equal(preview.estimatedTotalVerified,true);assertions++;
  assert.ok(preview.suites.every(x=>x.matched&&raw.slice(x.start,x.end)===x.source));assertions++;
  const plan=JSON.parse(engine.plan(raw,false,false));
  assert.equal(plan.valid,true,`plan must agree with inspected input: ${raw}`);assertions++;
  assert.equal(plan.totalJiao,parsed.totalJiao);assertions++;
}
// Unknown words and invalid amounts must still be fail-closed, rather than silently skipped.
for(const raw of ['014569百位014569尾各40组错误','5989\n3948\n各2\n全倒各0.333']) {
  const parsed=JSON.parse(engine.inspect(raw));
  assert.equal(parsed.valid,false,`malformed input cannot silently pass: ${raw}`);assertions++;
}
console.log(`PASS: ${assertions} v2.0.54 screenshot, source-audit, plan and fail-closed checks`);
