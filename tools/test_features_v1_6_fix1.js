#!/usr/bin/env node
'use strict';
const fs=require('fs'),path=require('path');const root=path.resolve(process.argv[2]||path.join(__dirname,'..'));const read=r=>fs.readFileSync(path.join(root,r),'utf8');
const pg=read('paigow-app.js'),sql=read('SQL/94_V1.6_FIX1_老何庄大小牌九盲牌.sql'),config=read('config.js'),sw=read('sw.js'),wf=read('.github/workflows/deploy-pages.yml');
const checks={
 'CACHE45 build':config.includes("version: '1.6.1'")&&config.includes("buildId: 'v1-6-fix1-cache45'")&&config.includes('cacheEpoch: 45'),
 'laohe small blind SQL':sql.includes("if v_phase='settled' then v_visible:=v_cards;else v_visible:='{}'::text[];end if"),
 'laohe big blind SQL':sql.includes("v_phase in('arrange','head_reveal','tail_reveal','settled')"),
 'dealer still hidden':sql.includes("v_laohe_visible:='{}'::text[]")&&sql.includes("elsif v_phase='head_reveal'"),
 'blind multiplier copy':pg.includes('老何庄盲选倍率')&&pg.includes('大牌九选倍前不显示两张预发明牌'),
 'small blind copy':pg.includes('小牌九结算前不显示任何自己的牌'),
 'V1.6 polling remains removed':!pg.includes('setInterval(pollOnce')&&!pg.includes('}, 1000)')&&!pg.includes('}, 5000)'),
 'cache refs':sw.includes('nine-cloud-dao-v1.6-fix1-cache45'),
 'portable workflow':wf.includes('python3 tools/ci_v1_6_fix1.py .')&&!wf.toLowerCase().includes('playwright')
};
for(const [n,ok] of Object.entries(checks)) console.log((ok?'PASS ':'FAIL ')+n);const failed=Object.entries(checks).filter(([,v])=>!v).map(([n])=>n);console.log(JSON.stringify({ok:!failed.length,checks:Object.keys(checks).length,failed},null,2));if(failed.length) throw new Error(failed.join(', '));
