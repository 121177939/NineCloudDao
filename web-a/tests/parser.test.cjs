// Offline regression: requires only Node.js. No cloud access or monetary operations.
const fs=require('fs');const vm=require('vm');const assert=require('assert');
const ctx={};vm.runInNewContext(fs.readFileSync(__dirname+'/../site/parser.js','utf8'),ctx);
const engine=ctx.parser.com.example.remotea.WebParser;
const examples=[
  ['1234-1234各1',true,1,16],
  ['123头123百123十123个各1元',true,1,81],
  ['1234各1元',true,1,0],
  ['1，2，3，4各1元',true,1,1],
  ['12头\n34尾各2块',true,1,4],
  ['1234全转各2',true,1,0],
  ['1234打1块，各打1块，5678各1块',true,2,0],
  ['1234打1块，各打2块，5678各2块',false,0,0],
  ['1234全转各1组 12345头1234尾各1组 2257各1组',false,0,0],
  ['12345头1234尾各1组',true,1,20],
  ['1234全转各1组 12345头1234尾各1组',true,2,20],
  ['2头3尾各1.1元',false,0,0],
];
let passed=0;
for(const [input,valid,lines,expectedSuiteCount] of examples){
 const result=JSON.parse(engine.inspect(input));
 assert.equal(result.valid,valid,`${input}: valid`);passed++;
 if(valid){assert.equal(result.totalLines,lines,`${input}: lines`);passed++;
  if(expectedSuiteCount){assert.equal(result.suites?.[0]?.expectedCount,expectedSuiteCount,`${input}: suite count`);passed++;}
  const plan=JSON.parse(engine.plan(input,false,true));
  assert.equal(plan.valid,true,`${input}: plan roundtrip`);passed++;
  assert(plan.command?.length>0);passed++;
 }
}

const multilineTurn=JSON.parse(engine.inspect('5989\n3948\n3405\n7733\n6081\n各2\n全倒各0.3'));
assert.equal(multilineTurn.valid,true,'multiline full-turn sample valid');passed++;
assert.equal(multilineTurn.totalLines,10,'multiline full-turn total lines');passed++;
assert.equal(multilineTurn.turnCount,5,'multiline full-turn turn count');passed++;

const suiteAliases=JSON.parse(engine.inspect('五:\n\n014569头014569尾各40组。\n\n014569百位014569尾各40组。\n\n014569头014569百位014569+1位014569尾各0.4组。'));
assert.equal(suiteAliases.valid,true,'suite alias sample valid');passed++;
assert.deepEqual(suiteAliases.suites.map(x=>x.canonical),[
  '014569头014569尾=40',
  '014569百014569尾=40',
  '014569头014569百014569十014569尾=0.4'
],'suite aliases canonical');passed++;

console.log(`PASS: ${passed} Kotlin/JS parser and wire assertions`);
