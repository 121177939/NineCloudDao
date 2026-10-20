import assert from 'node:assert/strict';
import { planHistoryArtifacts, historyCardPresentation, historyDetailStatus } from '../site/history-detail.js';

const legacy = planHistoryArtifacts({command:'S=0655:10',result_path:'u/legacy.png'});
assert.deepEqual(legacy.map(x=>[x.title,x.path,x.kind]), [['散码小票','u/legacy.png','scatter']]);

const routed = planHistoryArtifacts({
  command:'M1|S=0655:10|T=2,0,6,5,5,1|R=2',
  scatter_path:'u/scatter.png',suite_path:'u/suite.png',result_path:'u/result.png'
});
assert.deepEqual(routed.map(x=>[x.title,x.path,x.kind]), [
  ['散码小票','u/scatter.png','scatter'],['套码成功日志摘录','u/suite.png','suite']
]);

const combined = planHistoryArtifacts({
  command:'M1|S=0655:10|T=2,0,6,5,5,1|R=0', result_path:'u/combined.png'
});
assert.deepEqual(combined.map(x=>[x.title,x.path]), [['散码 + 套码合并小票','u/combined.png']]);

const unifiedSuiteOnly = planHistoryArtifacts({
  command:'M1|S=|T=2,0,6,5,5,1|R=4', result_path:'u/unified.png'
});
assert.equal(unifiedSuiteOnly[0].title, '散码主页统一截图（套码）');

const oddsOnly = planHistoryArtifacts({command:'M1|S=0655:10|T=|O=1',result_path:'u/odds.png'});
assert.deepEqual(oddsOnly.map(x=>x.path), ['u/odds.png']);

const receiptMode = planHistoryArtifacts({
  command:'M1|S=|T=2,0,6,5,5,1|R=3',suite_path:'u/receipt.png'
});
assert.equal(receiptMode[0].title, '套码下注页截图');

const stopEvidence = planHistoryArtifacts({
  command:'S=0655:10',result_path:'u/ticket.png'
}, [{phase:'reviewed',screenshot_path:'u/stop.png'},{phase:'review',screenshot_path:'u/stop.png'}]);
assert.deepEqual(stopEvidence.map(x=>[x.kind,x.title,x.path]), [
  ['scatter','散码小票','u/ticket.png'],['stop','人工核实记录 · 已结案截图','u/stop.png']
]);
assert.equal(planHistoryArtifacts({command:'S=0655:10'}).length, 0);

assert.deepEqual(historyCardPresentation('finished'), {
  label:'已完成',tone:'success',summary:'核验完成，可到历史查看截图'
});
assert.equal(historyCardPresentation('failed','账号入口未匹配').summary, '账号入口未匹配');
assert.equal(historyCardPresentation('needs_review').tone, 'warning');
assert.equal(historyDetailStatus('finished'), '成功');
assert.equal(historyDetailStatus('unknown'), 'unknown');
console.log('PASS: 13 history-detail planning and presentation assertions');
