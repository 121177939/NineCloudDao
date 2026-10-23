import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {createPreviewModel} from '../site/preview-model.js';
const ctx={};
vm.runInNewContext(fs.readFileSync(new URL('../site/parser.js',import.meta.url),'utf8'),ctx);
const parser=ctx.parser.com.example.remotea.WebParser;
let checks=0;
const good=[
  {raw:'9++7=20',code:'9XX7-20',jiao:200,rows:1},
  {raw:'7+8+\n7684\n8309\n各5',code:'7X8X-5;7684-5;8309-5',jiao:150,rows:3},
  {raw:'516274头62749尾二=5\n1274头679尾二=5\n516274头649尾二=5\n5274头627尾二=5',
   code:'M1|S=|T=2,516274,_,_,62749,5;2,1274,_,_,679,5;2,516274,_,_,649,5;2,5274,_,_,627,5',jiao:3600,rows:4},
  {raw:'9++7全倒各20',code:'M1|S=9XX7-20|T=|F=1',jiao:2400,rows:1},
  {raw:'8309全倒各0.5',code:'M1|S=8309-0.5|T=|F=1',jiao:120,rows:1},
  {raw:'27.16.38.49各0.5',code:'M1|S=|T=4,27,16,38,49,0.5',jiao:80,rows:1},
  {raw:'168.1386.3058.3849各0.2',code:'M1|S=|T=4,168,1386,3058,3849,0.2',jiao:384,rows:1},
  {raw:'7+8+\n7684\n8309\n各5\n27.16.38.49\n各0.5\n168.1386.3058.3849\n各0.2',
   code:'M1|S=7X8X-5;7684-5;8309-5|T=4,27,16,38,49,0.5;4,168,1386,3058,3849,0.2',jiao:614,rows:5},
  {raw:'7+8+\n7684\n8309\n各5\n8309全倒各0.5\n27.16.38.49\n各0.5\n168.1386.3058.3849\n各0.2',
   code:'M1|S=7X8X-5;7684-5;8309-5;8309-0.5|T=4,27,16,38,49,0.5;4,168,1386,3058,3849,0.2|F=0001',jiao:734,rows:6},
  {raw:'014569头014569尾各40组',code:'M1|S=|T=2,014569,_,_,014569,40',jiao:14400,rows:1},
];
for(const t of good){
  const got=JSON.parse(parser.inspect(t.raw));
  assert.equal(got.valid,true,`recognize ${t.raw}`);checks++;
  assert.equal(got.command,t.code,`exact wire ${t.raw}`);checks++;
  assert.equal(got.totalJiao,t.jiao);checks++;
  assert.equal(got.totalLines,t.rows);checks++;
  const preview=createPreviewModel(t.raw,got);
  assert.equal(preview.normalCount,t.rows);checks++;
  assert.equal(preview.reviewCount,0);checks++;
  assert.equal(preview.estimatedTotalVerified,true);checks++;
  if(t.raw.includes('二=5')){
    assert.equal(preview.suites.length,4);checks++;
    assert.deepEqual(preview.suites.map(s=>s.expectedCount),[30,12,18,12]);checks++;
    for(const suite of preview.suites){
      assert.equal(suite.matched,true);checks++;
      assert.equal(t.raw.slice(suite.start,suite.end),suite.source);checks++;
    }
  }
  const plan=JSON.parse(parser.plan(t.raw,false,false));
  assert.equal(plan.valid,true);checks++;
  assert.equal(plan.totalJiao,got.totalJiao);checks++;
}
const invalid=[
  '27.16.38各0.5', // only three groups: no silent four-position guess
  '9++7=0.5', // established two-position fractional price rejection
  '9+++ =20', // more than two wildcards
  '516274头62749尾百二=5', // mismatch: 二 marker is never a third position
  '516274头62749尾二=0.5', // established two-position amount policy
  '516274头62749尾三=5', // do not infer an unapproved "三" suffix
  '9++7=20乱', // unknown text cannot silently disappear
];
for(const raw of invalid){
  const result=JSON.parse(parser.inspect(raw));
  assert.equal(result.valid,false,`fail-closed ${raw}`);checks++;
  assert.equal(result.command,null);checks++;
  assert.equal(JSON.parse(parser.plan(raw,false,false)).valid,false);checks++;
}
console.log(`PASS v2.0.55 ${checks} shorthand, original-source, amount, wire and fail-closed assertions`);
