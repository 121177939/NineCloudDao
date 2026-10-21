import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';
import {createPreviewModel} from '../site/preview-model.js';
import {freezeValidatedPlan} from '../site/send-plan.js';
// Reproduced from the WAP15 user screenshot: 23 scatter records, three intentionally
// repeated; duplicate rows are independent payable records, not parse failures.
const raw='5732，8732，6274，9274，0639，2639，2738，2875打1块，\n各打1块，5396，8396各打1块，\n1014，2014，9030，5030，0760，0706，2760，0763，2763各1块\n2014，2706，0706，2760各1块';
const newCtx={};vm.runInNewContext(fs.readFileSync(new URL('../site/parser.js',import.meta.url),'utf8'),newCtx);
const parser=newCtx.parser.com.example.remotea.WebParser;
const parsed=JSON.parse(parser.inspect(raw));
const model=createPreviewModel(raw,parsed);
assert.equal(parsed.valid,true);assert.equal(model.scatterCount,23);
assert.equal(model.totalCount,23);assert.equal(model.reviewCount,0);assert.equal(model.normalCount,23);
assert.equal(parsed.totalJiao,230);assert.equal(model.estimatedTotalVerified,true);
assert.deepEqual(parsed.issues.map(x=>x.notice),['DUPLICATE','DUPLICATE','DUPLICATE']);
assert.deepEqual(parsed.issues.map(x=>x.severity),['WARNING','WARNING','WARNING']);
assert.equal(model.warnings.length,3,'notices preserved instead of erased');
assert.ok(model.scatter.every(x=>x.matched && x.status==='正常'));
assert.deepEqual(model.scatter.slice(-4).map(x=>x.number),['2014','2706','0706','2760']);
assert.equal(model.scatter.filter(x=>['2014','0706','2760'].includes(x.number)).length,6);
for(const code of ['2014','0706','2760']){
 const matches=model.scatter.filter(x=>x.number===code);
 assert.equal(matches.length,2);
 assert.ok(matches[0].end<=matches[1].start,'independent source ranges for '+code);
 assert.equal(raw.slice(matches[0].start,matches[0].end),code);
 assert.equal(raw.slice(matches[1].start,matches[1].end),code);
 assert.ok(matches[1].detail.includes('保留为独立记录'));
}
const authoritative=JSON.parse(parser.plan(raw,false,false));
for(const key of ['command','totalJiao','totalLines','valid'])if(key in authoritative)assert.equal(parsed[key],authoritative[key],key+' current inspect/plan invariant');
const plan=freezeValidatedPlan(parser,raw,parsed,model);
assert.equal(plan.totalJiao,230);assert.equal(plan.scatterCount,23);
assert.equal(plan.command,authoritative.command);
// Fail-closed: UNKNOWN warnings, lookalikes and errors still require review.
for(const notice of ['GENERAL','LOOKALIKE',undefined]){
 const issue={start:0,end:4,severity:'WARNING',notice,message:'不能安全确定含义'};
 const review=createPreviewModel('1234各1元',{
  scatter:[{number:'1234',amountJiao:10}],issues:[issue],totalJiao:10
 });
 assert.equal(review.reviewCount,1,'nonduplicate notice must still be reviewed');
}
// If a valid duplicate and unrelated caution overlap, the caution must win.
const both=createPreviewModel('1234各1元',{
 scatter:[{number:'1234',amountJiao:10}],issues:[
  {start:0,end:4,severity:'WARNING',notice:'DUPLICATE',message:'重复保留'},
  {start:0,end:4,severity:'WARNING',notice:'GENERAL',message:'另一个待核对原因'}],totalJiao:10
});
assert.equal(both.reviewCount,1);
assert.match(both.scatter[0].detail,/另一个待核对原因/);
// Fake second execution item with no second source stays blocked even if duplicate warning.
const fake=createPreviewModel('1234各1元',{
 scatter:[{number:'1234',amountJiao:10},{number:'1234',amountJiao:10}],
 issues:[{start:0,end:4,severity:'WARNING',notice:'DUPLICATE',message:'重复'}],totalJiao:20
});
assert.equal(fake.reviewCount,1);
assert.equal(fake.scatter[1].matched,false);
console.log('PASS phase16 screenshot 23 independent records, 3 duplicate notices nonblocking, wire invariance, other warnings fail closed');
