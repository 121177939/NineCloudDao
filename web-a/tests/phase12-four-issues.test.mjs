import assert from 'node:assert/strict';
import fs from 'node:fs';import vm from 'node:vm';
import {createPreviewModel} from '../site/preview-model.js';
const ctx={};vm.runInNewContext(fs.readFileSync(new URL('../site/parser.js',import.meta.url),'utf8'),ctx);
const parse=ctx.parser.com.example.remotea.WebParser;
for(const input of ['0123456789头16尾各2元','678头387尾各2元','67头57百38尾各1元','67头68十38尾各1元','271645头269尾各3元','162745头7十269尾各1元']){
 const model=createPreviewModel(input,JSON.parse(parse.inspect(input)));
 assert.equal(model.suites.length,1,input);assert.equal(model.suites[0].matched,true,input);
 assert.equal(model.suites[0].source,input.split('各')[0],input);
}
const app=fs.readFileSync(new URL('../site/app.js',import.meta.url),'utf8');
const cloud=fs.readFileSync(new URL('../site/supabase.js',import.meta.url),'utf8');
assert.match(app,/let postSendWarning/);assert.match(app,/任务列表刷新失败/);
assert.match(cloud,/restoreSession\(/);assert.match(cloud,/remote_role_current/);
assert.match(cloud,/web-a-refresh-v12/);assert.doesNotMatch(cloud,/localStorage\.setItem/);
assert.match(app,/startsWith\('image\/'\)/);assert.match(app,/navigator\.canShare/);
console.log('PASS: phase12 screenshot cases, post-create read failure isolation, session restore, image file handling');
