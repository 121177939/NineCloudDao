#!/usr/bin/env node
'use strict';
const fs=require('fs'),path=require('path');
const root=path.resolve(process.argv[2]||path.join(__dirname,'..'));
const read=r=>fs.readFileSync(path.join(root,r),'utf8');
const app=read('app.js'),index=read('index.html'),loader=read('b-paigow01.js'),pg=read('paigow-app.js'),css=read('paigow-app.css'),sql=read('SQL/72_V1.2_FIX1_九霄灵牌正式并线.sql'),config=read('config.js');
const selector=(app.match(/const selector = `[^`]+`;/)||[''])[0];
const checks={
 'CACHE38 build':config.includes("version: '1.2.1'")&&config.includes("buildId: 'v1-2-fix1-cache38'")&&config.includes('cacheEpoch: 38'),
 'launcher loaded':index.includes('b-paigow01.js?v=v1-2-fix1-cache38')&&loader.includes('b-paigow01.html?'),
 'old visible turtle replaced':selector.includes('九霄灵牌')&&!selector.includes('气运龟卜')&&app.includes("draft.game === 'turtle_oracle'")&&app.includes("draft.game = 'spirit_dice'"),
 'four rooms':pg.includes('天地玄黄四房')&&sql.includes('generate_series(1,4)'),
 'small and big':pg.includes('大牌九')&&pg.includes('牌九')&&sql.includes("game_mode in('small','big')"),
 'traditional 32 tiles':sql.includes('PAIGOW_TILE_DECK_NOT_32')&&(sql.match(/^\('/gm)||[]).length>=32,
 'secure server shuffle':sql.includes('casino_secure_random_int_v1(v_i)')&&sql.includes('paigow_round_secrets_bpaigow01'),
 'private masking':sql.includes("rp.character_id=v_character")&&sql.includes("v_visible:='{}'::text[]")&&sql.includes('revoke all on table public.paigow_settings_bpaigow01,public.paigow_round_secrets_bpaigow01'),
 'room timers':sql.includes('small_multiplier_seconds integer not null default 6')&&sql.includes('big_multiplier_seconds integer not null default 10')&&sql.includes('arrange_seconds integer not null default 30')&&sql.includes('head_reveal_seconds integer not null default 10'),
 'laohe existing bankroll':sql.includes("'paigow_laohe_settlement_bpaigow01'")&&sql.includes('casino_bankroll_apply_v1'),
 'player fee 2.5':sql.includes('player_fee_bps integer not null default 250')&&sql.includes("'paigow_player_fee_bpaigow01'"),
 'thirty percent':sql.includes('floor(v_available::numeric*0.30)::bigint')&&pg.includes('开局余额30%'),
 'player dealer zero cover':sql.includes("'paigow_dealer_reserve_bpaigow01'")&&pg.includes('系统绝不兜底'),
 'single robber allowed':sql.includes("array_length(v_candidates,1),0)<1"),
 'active player cannot role switch':sql.includes("v_room.status='playing' and v_existing_role='player'"),
 'tail deadline settlement only':sql.includes("v_round.phase<>'tail_reveal' or v_round.phase_deadline>clock_timestamp()"),
 'request idempotency':sql.includes('paigow_action_requests_bpaigow01')&&sql.includes('PAIGOW_REQUEST_ID_REUSED'),
 'responsive UI':css.includes('@media')&&!css.includes('min-width: 1000px'),
 'V1.2 mutation retained':app.includes('mutationAttributeHtmlV12')&&app.includes('变异灵根（${mutation}）'),
 'casino retained':app.includes('100赔3320')&&app.includes('正利润的50%')&&app.includes('领取70%')
};
for(const [n,ok] of Object.entries(checks)) console.log((ok?'PASS ':'FAIL ')+n);
const failed=Object.entries(checks).filter(([,v])=>!v).map(([n])=>n);
console.log(JSON.stringify({ok:!failed.length,checks:Object.keys(checks).length,failed},null,2));
if(failed.length) throw new Error('failed: '+failed.join(', '));
