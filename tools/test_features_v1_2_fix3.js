#!/usr/bin/env node
'use strict';
const fs=require('fs'),path=require('path');
const root=path.resolve(process.argv[2]||path.join(__dirname,'..'));
const read=r=>fs.readFileSync(path.join(root,r),'utf8');
const pg=read('paigow-app.js'),html=read('b-paigow01.html'),index=read('index.html'),loader=read('b-paigow01.js'),config=read('config.js'),sw=read('sw.js'),gate=read('SQL/81_V1.2_FIX3_CACHE40_牌九无闪烁与自定义底注发布门禁.sql');
const checks={
  'CACHE40 build':config.includes("version: '1.2.3'")&&config.includes("buildId: 'v1-2-fix3-cache40'")&&config.includes('cacheEpoch: 40'),
  'all launchers CACHE40':index.includes('b-paigow01.js?v=v1-2-fix3-cache40')&&loader.includes("v: 'v1-2-fix3-cache40'")&&html.includes('paigow-app.js?v=v1-2-fix3-cache40')&&sw.includes('nine-cloud-dao-v1.2-fix3-cache40'),
  'stable render guard':pg.includes('state.renderHtml !== nextHtml')&&pg.includes('state.renderHtml = nextHtml'),
  'poll does not call action':pg.includes('state.poll = setInterval(pollOnce')&&!pg.includes('action(async () => state.roomId ? loadRoom(true) : loadLobby())'),
  'poll overlap lock':pg.includes('state.busy || state.polling')&&pg.includes('state.polling = true')&&pg.includes('state.polling = false'),
  'no busy rerender':pg.includes('setBusyUi(true)')&&!pg.includes('state.busy = true;\n    render();'),
  'form draft':pg.includes('createDraft:')&&pg.includes('captureCreateDraft')&&pg.includes('value="${esc(draft.base)}"'),
  'integer custom stake':pg.includes('step="1"')&&pg.includes("base.step = '1'")&&pg.includes("base: '20'"),
  'existing RPC retained':pg.includes("rpc('create_paigow_room_bpaigow01'")&&pg.includes("rpc('advance_paigow_round_bpaigow01'"),
  'release gate':gate.includes("release_name='V1.2 FIX3 CACHE40'")&&gate.includes('greatest(cache_epoch,40)')&&gate.includes('不修改牌型')
};
for(const [name,ok] of Object.entries(checks)) console.log((ok?'PASS ':'FAIL ')+name);
const failed=Object.entries(checks).filter(([,ok])=>!ok).map(([name])=>name);
console.log(JSON.stringify({ok:!failed.length,checks:Object.keys(checks).length,failed},null,2));
if(failed.length) throw new Error(failed.join(', '));
