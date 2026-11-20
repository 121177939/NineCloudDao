import fs from 'node:fs';import vm from 'node:vm';import assert from 'node:assert/strict';
const root=new URL('../',import.meta.url);const js=fs.readFileSync(new URL('site/parser.js',root),'utf8');const ctx={};vm.runInNewContext(js,ctx);const engine=ctx.parser.com.example.remotea.WebParser;
let count=0;
const ambiguous=JSON.parse(engine.ambiguities('1649-49，XX17-49各2元'));
assert.equal(ambiguous.length,1);count++;
assert.equal(ambiguous[0].choices[0].title,'号码金额（散码）');count++;
assert.equal(ambiguous[0].choices[1].title,'头尾二定位（套码）');count++;
const US='\x1f';
const rule=['r1','head','(?m)^([0-9]{1,10})头各(\\d+(?:\\.\\d+)?)(?:元|块|组)$','$1头全尾各$2元','{数字}头各{金额}元','{数字}头全尾各{金额}元','1','style','1','0'].join(US);
const installed=JSON.parse(engine.installRules(12,rule));assert.equal(installed.ok,true);count++;
const ruled=JSON.parse(engine.inspect('4头各2块'));assert.equal(ruled.valid,true);count++;assert.equal(ruled.suites[0].expectedCount,10);count++;
const app=fs.readFileSync(new URL('site/app.js',root),'utf8');const supa=fs.readFileSync(new URL('site/supabase.js',root),'utf8');
for(const marker of ['recognitionRulesCurrent','syncRecognitionRules','webParser.ambiguities','inspectWithSelections','planWithSelections','taskDisplayName']){assert.ok(app.includes(marker)||supa.includes(marker),marker);count++;}
console.log(`PASS v4.1.6 A/WAP recognition lockstep ${count} assertions`);
