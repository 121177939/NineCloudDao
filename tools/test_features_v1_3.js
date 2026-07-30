#!/usr/bin/env node
'use strict';
const fs=require('fs'),path=require('path');
const root=path.resolve(process.argv[2]||path.join(__dirname,'..'));
const read=r=>fs.readFileSync(path.join(root,r),'utf8');
const pg=read('paigow-app.js'),html=read('b-paigow01.html'),index=read('index.html'),loader=read('b-paigow01.js'),config=read('config.js'),sw=read('sw.js'),wf=read('.github/workflows/deploy-pages.yml'),gate=read('SQL/83_V1.3_CACHE41_GitHub_Pages可移植构建发布门禁.sql');
const checks={
  'CACHE41 build':config.includes("version: '1.3.0'")&&config.includes("buildId: 'v1-3-cache41'")&&config.includes('cacheEpoch: 41'),
  'all launchers CACHE41':index.includes('b-paigow01.js?v=v1-3-cache41')&&loader.includes("v: 'v1-3-cache41'")&&html.includes('paigow-app.js?v=v1-3-cache41')&&sw.includes('nine-cloud-dao-v1.3-cache41'),
  'stable render guard':pg.includes('state.renderHtml !== nextHtml')&&pg.includes('state.renderHtml = nextHtml'),
  'poll does not call action':pg.includes('state.poll = setInterval(pollOnce')&&!pg.includes('action(async () => state.roomId ? loadRoom(true) : loadLobby())'),
  'poll overlap lock':pg.includes('state.busy || state.polling')&&pg.includes('state.polling = true')&&pg.includes('state.polling = false'),
  'form draft':pg.includes('createDraft:')&&pg.includes('captureCreateDraft')&&pg.includes('value="${esc(draft.base)}"'),
  'integer custom stake':pg.includes('step="1"')&&pg.includes("base.step = '1'")&&pg.includes("base: '20'"),
  'existing RPC retained':pg.includes("rpc('create_paigow_room_bpaigow01'")&&pg.includes("rpc('advance_paigow_round_bpaigow01'"),
  'portable workflow':wf.includes('python3 tools/ci_v1_3.py .')&&!wf.toLowerCase().includes('playwright')&&!wf.includes('/usr/bin/chromium'),
  'release gate':gate.includes("release_name='V1.3 CACHE41'")&&gate.includes('greatest(cache_epoch,41)')&&gate.includes('不修改牌型')
};
for(const [name,ok] of Object.entries(checks)) console.log((ok?'PASS ':'FAIL ')+name);
const failed=Object.entries(checks).filter(([,ok])=>!ok).map(([name])=>name);
console.log(JSON.stringify({ok:!failed.length,checks:Object.keys(checks).length,failed},null,2));
if(failed.length) throw new Error(failed.join(', '));
