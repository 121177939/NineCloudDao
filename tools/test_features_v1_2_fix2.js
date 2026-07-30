#!/usr/bin/env node
'use strict';
const fs=require('fs'),path=require('path');
const root=path.resolve(process.argv[2]||path.join(__dirname,'..'));
const read=r=>fs.readFileSync(path.join(root,r),'utf8');
const app=read('app.js'),index=read('index.html'),loader=read('b-paigow01.js'),pg=read('paigow-app.js'),css=read('paigow-app.css'),sql=read('SQL/72_V1.2_FIX1_九霄灵牌正式并线.sql'),gate=read('SQL/79_V1.2_FIX2_CACHE39_牌九预览界面发布门禁.sql'),config=read('config.js');
const selector=(app.match(/const selector = `[^`]+`;/)||[''])[0];
const checks={
 'CACHE39 build':config.includes("version: '1.2.2'")&&config.includes("buildId: 'v1-2-fix2-cache39'")&&config.includes('cacheEpoch: 39'),
 'launcher cache39':index.includes('b-paigow01.js?v=v1-2-fix2-cache39')&&loader.includes("v: 'v1-2-fix2-cache39'"),
 'old visible turtle replaced':selector.includes('九霄灵牌')&&!selector.includes('气运龟卜')&&app.includes("draft.game === 'turtle_oracle'")&&app.includes("draft.game = 'spirit_dice'"),
 'V26 lobby structure':pg.includes('casino-head')&&pg.includes('lobby-grid')&&pg.includes('天地玄黄房')&&pg.includes('创建牌局'),
 'V26 seat structure':pg.includes('seat-table')&&pg.includes('seat-pos-${seat}')&&pg.includes('九席选座'),
 'V26 board structure':pg.includes('board-frame')&&pg.includes('self-zone')&&pg.includes('本局概览')&&pg.includes('开牌排名'),
 'real RPC only':pg.includes("rpc('create_paigow_room_bpaigow01'")&&pg.includes("rpc('start_paigow_round_bpaigow01'")&&pg.includes("rpc('advance_paigow_round_bpaigow01'")&&!pg.includes('makeDeck(')&&!pg.includes('沈青禾')&&!pg.includes('顾长风'),
 'tile face pips':pg.includes('tile.face')&&pg.includes('pipGrid(face.top)')&&pg.includes('pipGrid(face.bottom)'),
 'responsive V26 CSS':css.includes('.casino-head')&&css.includes('.seat-table')&&css.includes('.self-zone')&&css.includes('@media(max-width:620px)'),
 'four rooms':pg.includes('[1, 2, 3, 4]')&&sql.includes('generate_series(1,4)'),
 'small and big':pg.includes('大牌九')&&pg.includes('小牌九')&&sql.includes("game_mode in('small','big')"),
 'traditional 32 tiles':sql.includes('PAIGOW_TILE_DECK_NOT_32')&&(sql.match(/^\('/gm)||[]).length>=32,
 'secure server shuffle':sql.includes('casino_secure_random_int_v1(v_i)')&&sql.includes('paigow_round_secrets_bpaigow01'),
 'private masking':sql.includes("rp.character_id=v_character")&&sql.includes("v_visible:='{}'::text[]"),
 'hotfix77 merged':sql.includes('1::smallint')&&!sql.includes('join_paigow_room_bpaigow01(v_room.id,1,false)'),
 'hotfix78 merged':sql.includes('v_member record')&&sql.includes('from public.paigow_room_members_bpaigow01 as rm')&&!sql.includes('v_cards text[];m record'),
 'case syntax fixed':sql.includes("if v_count < (\n    case when v_room.duel_type='laohe' then 1 else 2 end\n  ) then"),
 'release gate cache39':gate.includes("release_name='V1.2 FIX2 CACHE39'")&&gate.includes('greatest(cache_epoch,39)')&&gate.includes('run_hotfix_77')&&gate.includes('run_hotfix_78'),
 'thirty percent retained':sql.includes('floor(v_available::numeric*0.30)::bigint')&&pg.includes('开局余额30%'),
 'player dealer zero cover':sql.includes("'paigow_dealer_reserve_bpaigow01'")&&pg.includes('系统不兜底'),
 'V1.2 mutation retained':app.includes('mutationAttributeHtmlV12')&&app.includes('变异灵根（${mutation}）'),
 'casino retained':app.includes('100赔3320')&&app.includes('正利润的50%')&&app.includes('领取70%')
};
for(const [n,ok] of Object.entries(checks)) console.log((ok?'PASS ':'FAIL ')+n);
const failed=Object.entries(checks).filter(([,v])=>!v).map(([n])=>n);
console.log(JSON.stringify({ok:!failed.length,checks:Object.keys(checks).length,failed},null,2));
if(failed.length) throw new Error('failed: '+failed.join(', '));
