#!/usr/bin/env node
'use strict';
const fs=require('fs'),path=require('path');
const root=path.resolve(process.argv[2]||path.join(__dirname,'..'));
const read=r=>fs.readFileSync(path.join(root,r),'utf8');
const pg=read('paigow-app.js'),css=read('paigow-app.css'),html=read('b-paigow01.html'),index=read('index.html'),loader=read('b-paigow01.js'),config=read('config.js'),sw=read('sw.js'),wf=read('.github/workflows/deploy-pages.yml'),main=read('SQL/85_V1.4_九霄牌九自动准备与私密明牌.sql'),gate=read('SQL/86_V1.4_CACHE42_正式发布门禁.sql');
const checks={
  'CACHE42 build':config.includes("version: '1.4.0'")&&config.includes("buildId: 'v1-4-cache42'")&&config.includes('cacheEpoch: 42'),
  'all launchers CACHE42':index.includes('b-paigow01.js?v=v1-4-cache42')&&loader.includes("v: 'v1-4-cache42'")&&html.includes('paigow-app.js?v=v1-4-cache42')&&sw.includes('nine-cloud-dao-v1.4-cache42'),
  'stable render retained':pg.includes('state.renderHtml !== nextHtml')&&pg.includes('state.renderHtml = nextHtml'),
  'private card server rule':main.includes('只对牌主本人可见')&&main.includes("v_visible:='{}'::text[]")&&main.includes('v_visible:=v_cards[1:1]'),
  'five second small prep':main.includes('small_multiplier_seconds=5'),
  'ten second ready timeout':main.includes('ready_seconds=10')&&pg.includes('10秒内未准备'),
  'two second auto start':main.includes('auto_start_seconds=2')&&pg.includes('全员准备后2秒自动开局'),
  'manual start removed':!pg.includes('data-start')&&!pg.includes("rpc('start_paigow_round_bpaigow01'"),
  'delete waiting room':pg.includes('data-delete-room')&&pg.includes("rpc('delete_paigow_room_bpaigow01'")&&main.includes('PAIGOW_CANNOT_DELETE_ACTIVE_ROOM'),
  'settlement resource streams':pg.includes('losers.forEach')&&pg.includes('winners.forEach')&&pg.includes('pg-resource-particle')&&css.includes('.pg-resource-fx-layer'),
  'one second room tick':pg.includes('state.roomId ? 1000 : 5000'),
  'existing security retained':pg.includes("rpc('advance_paigow_round_bpaigow01'")&&main.includes('paigow_shuffle_deck_bpaigow01'),
  'portable workflow':wf.includes('python3 tools/ci_v1_4.py .')&&!wf.toLowerCase().includes('playwright')&&!wf.includes('/usr/bin/chromium'),
  'release gate':gate.includes("release_name='V1.4 CACHE42'")&&gate.includes('greatest(cache_epoch,42)')
};
for(const [name,ok] of Object.entries(checks)) console.log((ok?'PASS ':'FAIL ')+name);
const failed=Object.entries(checks).filter(([,ok])=>!ok).map(([name])=>name);
console.log(JSON.stringify({ok:!failed.length,checks:Object.keys(checks).length,failed},null,2));
if(failed.length) throw new Error(failed.join(', '));
