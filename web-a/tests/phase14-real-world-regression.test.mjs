import assert from 'node:assert/strict';
import fs from 'node:fs';import vm from 'node:vm';
import {createPreviewModel as updated} from '../site/preview-model.js';
import {createPreviewModel as baseline} from '../../../Web_A_GitHubPages_阶段十二_WAP四项修复/web-a/site/preview-model.js';
const context={};vm.runInNewContext(fs.readFileSync(new URL('../site/parser.js',import.meta.url),'utf8'),context);
const parser=context.parser.com.example.remotea.WebParser;
const original=[
 '0123456789头16尾各2元',
 '678头387尾各2元',
 '67头57百38尾各1元',
 '67头68十38尾各1元',
 '271645头269尾各3元',
 '162745头7十269尾各1元'
];
const spaced=[
 '0123456789头 16尾各2元',
 '678头\n387尾各2元',
 '67头 57百\t38尾各1元',
 '67头 68十 38尾各1元',
 '271645头 269尾各3元',
 '162745头\n7十 269尾各1元'
];
const raw='2X74、2XX4各20元\n'+spaced.join('\n');
const parsed=JSON.parse(parser.inspect(raw));
assert.equal(parsed.valid,true);
// Stage 12 must be fed its original, canonical-only bridge output;
// stage 15 now carries actual ChineseCodeParser.Entry.source through its own bridge.
const oldCtx={}; vm.runInNewContext(fs.readFileSync(new URL('../../../Web_A_GitHubPages_阶段十二_WAP四项修复/web-a/site/parser.js',import.meta.url),'utf8'),oldCtx);
const oldParsed=JSON.parse(oldCtx.parser.com.example.remotea.WebParser.inspect(raw));
const before=baseline(raw,oldParsed),after=updated(raw,parsed);
assert.equal(parsed.command,oldParsed.command);assert.equal(parsed.totalJiao,oldParsed.totalJiao);
assert.equal(parsed.suites.length,6);
assert.ok(before.suites.some(x=>!x.matched),'reproduced original bug');
assert.ok(after.suites.every(x=>x.matched&&x.status==='正常'),'all spaced tuples proven source-mapped');
for(let i=0;i<spaced.length;i++){
 const row=after.suites[i];
 assert.equal(raw.slice(row.start,row.end),spaced[i].split('各')[0]);
 assert.equal(row.recognition,original[i].split('各')[0]);
 assert.equal(row.canonical,parsed.suites[i].canonical);
}
assert.equal(after.reviewCount,0);
assert.equal(after.estimatedTotalVerified,before.estimatedTotalVerified,'authoritative value consistency preserved');
assert.equal(JSON.stringify(before.suites.map(x=>x.canonical)),JSON.stringify(after.suites.map(x=>x.canonical)),'same Kotlin suites');
const forged=updated('完全无关原文',{scatter:[],suites:[{canonical:'12头34尾=1',source:'12头34尾=1',amountJiao:10,expectedCount:8}],issues:[]});
assert.equal(forged.suites[0].matched,false,'forged canonical must NOT bypass source evidence');
const impossible=updated('12头34尾各1元',{scatter:[],suites:[{canonical:'56头78尾=1',source:'56头78尾=1',amountJiao:10,expectedCount:8}],issues:[]});
assert.equal(impossible.suites[0].matched,false);
const app=fs.readFileSync(new URL('../site/app.js',import.meta.url),'utf8');
const html=fs.readFileSync(new URL('../site/index.html',import.meta.url),'utf8');
assert.match(html,/<title>控制中心 · Web A 阶段十七/);
assert.match(html,/识别预览 <span[^>]+>WAP 17<\/span>/);
assert.match(app,/function systemShareFiles\(files\)/);
assert.match(app,/return navigator\.share\(\{files\}\)/);
assert.doesNotMatch(app,/navigator\.share\(\{files,title:/);
assert.match(app,/save\.download=file\.name/);
assert.match(app,/modal\('分享真实小票图片'/);
assert.match(app,/点“系统分享图片”/);
assert.match(app,/仅在本机生成/);
assert.match(app,/图片先预览，再在新点击中选择系统分享/);
console.log('PASS: six screenshot samples with real spaced source, stage12 fail reproduces, stage15 maps exact raw offsets, forged fail-closed, image file share second gesture & save controls, build marker');
