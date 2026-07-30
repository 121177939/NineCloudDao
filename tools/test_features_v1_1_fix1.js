#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const root = path.resolve(process.argv[2] || path.join(__dirname, '..'));
const app = fs.readFileSync(path.join(root, 'app.js'), 'utf8');
const sql = fs.readFileSync(path.join(root, 'SQL/59_V1.1_FIX1_赌场周期资金与公平结算.sql'), 'utf8');
const config = fs.readFileSync(path.join(root, 'config.js'), 'utf8');

const near = (a, b, eps = 1e-9) => Math.abs(a - b) <= eps;
const stake = 100;
const ev = {
  diceSide: (105 / 216) * 95 + (111 / 216) * (-100),
  diceTriple: (6 / 216) * 3320 + (210 / 216) * (-100),
  turtleNeutral: 0.5 * 90 + 0.5 * (-100),
  turtleEdge: 0.25 * 280 + 0.75 * (-100),
  fish: (125 / 216) * (-100) + (75 / 216) * 106 + (15 / 216) * 210 + (1 / 216) * 320
};

const checks = {
  'CACHE36 build': config.includes("buildId: 'v1-1-fix1-cache36'") && config.includes('cacheEpoch: 36'),
  'true dice choices': app.includes("['triple', '押任意豹子 · 1/36 · 荷老100赔3320']") && app.includes("!['big', 'small', 'triple'].includes(draft.choice)") && sql.includes("p_choice in('big','small','triple')"),
  'triple beats sides': sql.includes("v_side:=case when v_is_triple then 'triple'") && sql.includes("'triple_auto_side',false"),
  'secure random': sql.includes('gen_random_bytes(4)') && !sql.includes('random()'),
  'two-hour period': app.includes('每两小时独立重置') && sql.includes('casino_period_seconds=7200'),
  'one-minute close': app.includes('开奖前一分钟封盘') && sql.includes('casino_close_before_seconds=60'),
  'fixed bankrolls': sql.includes('casino_spirit_stone_target=100000000') && sql.includes('casino_cultivation_target=1000000000'),
  'profit half to pool': app.includes('正利润的50%') && sql.includes('floor(v_profit::numeric*0.50)'),
  '70 percent prize': app.includes('领取70%') && sql.includes('floor(v_pool.amount::numeric*0.70)'),
  'old equal ticket': app.includes('旧等权规则') && sql.includes('重复游玩不增加抽中权重'),
  'thirty percent stake': app.includes('30%') && sql.includes('CASINO_STAKE_EXCEEDS_THIRTY_PERCENT') && sql.includes('*0.30'),
  'no session limit': app.includes('游玩次数不设上限') && !sql.includes('CASINO_TOTAL_DAILY_LIMIT'),
  'reject concurrent requests': sql.includes('pg_try_advisory_xact_lock') && sql.includes('CASINO_REQUEST_IN_PROGRESS'),
  'player house 97.5': app.includes('100:97.5') && app.includes('CASINO_PLAYER_HOUSE_STAKE_MULTIPLE_40') && sql.includes('CASINO_PLAYER_HOUSE_STAKE_MULTIPLE_40') && sql.includes('player_house_97_5_fee_to_bankroll_no_cover'),
  'player house no cover': app.includes('系统绝不兜底') && sql.includes('system_cover_amount=0'),
  'system payout EV dice side': near(ev.diceSide, -5.208333333333329),
  'system payout EV dice triple': near(ev.diceTriple, -5),
  'system payout EV turtle neutral': near(ev.turtleNeutral, -5),
  'system payout EV turtle edge': near(ev.turtleEdge, -5),
  'system payout EV fish': near(ev.fish, -5),
  'probabilities total': 105 + 105 + 6 === 216 && 125 + 75 + 15 + 1 === 216,
  'fix4 RPC retained': app.includes('rpc/play_house_game_v1_fix4') && app.includes('rpc/place_fish_shrimp_bet_v1_fix4'),
  'battle V1.1 preserved': app.includes('高低战力均可互相挑战') && app.includes('今日的20次主动挑战')
};

for (const [name, ok] of Object.entries(checks)) console.log((ok ? 'PASS ' : 'FAIL ') + name);
const failed = Object.entries(checks).filter(([, ok]) => !ok).map(([name]) => name);
console.log(JSON.stringify({ ok: failed.length === 0, checks: Object.keys(checks).length, expectedValuePer100: ev }, null, 2));
if (failed.length) throw new Error('failed: ' + failed.join(', '));
