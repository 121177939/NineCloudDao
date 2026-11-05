import assert from 'node:assert/strict';
import {historyOnlyParents, parentType, parentState} from '../site/order-history.js';
const parents=[
 {id:'a',state:'finished',selection:'seven',order_number:1},
 {id:'b',state:'cancelled',selection:'both',order_number:2},
 {id:'c',state:'reviewed_closed',selection:'arrange',order_number:3},
 {id:'d',state:'needs_review',selection:'seven',order_number:4}
];
const filtered=historyOnlyParents(parents,[{id:'a'},{id:'c'}]);
assert.deepEqual(filtered.map(p=>p.order_number),[2]);
assert.equal(parentType('both'),'排列五＋七星彩');
assert.equal(parentState('cancelled'),'已取消 · 未执行');
assert.equal(historyOnlyParents(parents,[]).length,3);
assert.equal(historyOnlyParents([],[]).length,0);
console.log('PASS v2.0.60 duplicate history parents are hidden; no-child cancellations remain clickable');
