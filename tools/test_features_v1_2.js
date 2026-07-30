#!/usr/bin/env node
'use strict';
const fs = require('fs');
const path = require('path');
const root = path.resolve(process.argv[2] || path.join(__dirname, '..'));
const read = rel => fs.readFileSync(path.join(root, rel), 'utf8');
const app = read('app.js');
const css = read('styles.css');
const sql = read('SQL/66_V1.2_变异灵根与剑心互斥.sql');
const config = read('config.js');
const oldElements = "[['metal','wood'],['wood','earth'],['earth','water'],['water','fire'],['fire','metal']]";
const elementFn = (app.match(/function battleElementOvercomes[\s\S]*?\n  }/) || [''])[0];

const checks = {
  'V1.2 CACHE37 build': config.includes("version: '1.2'") && config.includes("buildId: 'v1-2-cache37'") && config.includes('cacheEpoch: 37'),
  'mutation mapping SQL': sql.includes("when p_base_element='metal' then 'thunder'") && sql.includes("when p_base_element='wood' then 'wind'") && sql.includes("when p_base_element='water' then 'ice'"),
  'no fire earth mutation': !sql.includes("when p_base_element='fire'") && !sql.includes("when p_base_element='earth'"),
  'five element cycle unchanged': app.includes(oldElements),
  'no mutation overcome pairs': !elementFn.includes('thunder') && !elementFn.includes('ice') && !elementFn.includes('wind'),
  'mutation final damage eight': sql.includes('mutation_final_damage_bonus numeric(7,6) not null default 0.08') && sql.includes('v_element*v_sword*v_mutation'),
  'sword and mutation mutex damage': sql.includes("if coalesce((p_attacker->>'sword_heart_active')::boolean,false) then") && sql.includes('elsif coalesce(v_settings.mutation_bonus_enabled,true)'),
  'root conflict random replacement': sql.includes('trg_v12_mutant_root_conflict_guard') && sql.includes('v12_random_non_mutant_root'),
  'fate conflict random replacement': sql.includes('trg_v12_sword_heart_conflict_guard') && sql.includes('v12_random_non_sword_fate'),
  'birth result re-read': app.includes('rpc/get_my_birth_result_v12') && app.includes('actualBirth?.spirit_root_name'),
  'root reroll actual result': app.includes('result?.mutation_display || result?.new_root_name') && sql.includes("'conflict_replaced',v_new_root_id is distinct from v_attempted_root_id"),
  'single character wrapper': app.includes('function mutationAttributeHtmlV12') && app.includes('<b class="mutation-attribute-v12'),
  'thunder purple': css.includes('.mutation-attribute-v12.mutation-thunder') && css.includes('#a879ff'),
  'ice blue': css.includes('.mutation-attribute-v12.mutation-ice') && css.includes('#72c7ff'),
  'wind white': css.includes('.mutation-attribute-v12.mutation-wind') && css.includes('#f4f5f2'),
  'whole row not recolored': !css.includes('.mutation-badge-v12.mutation-thunder') && !css.includes('.mutation-display-v12.mutation-thunder'),
  'hero shows mutation root': app.includes('return mutation ? `变异灵根（${mutation}）` : safeRoot;'),
  'rank and battle display mutation': app.includes('变异${mutationAttributeHtmlV12(row)}') && app.includes('mutationBadgeHtmlV12'),
  'casino V1.1 retained': app.includes('100赔3320') && app.includes('100:97.5') && app.includes('正利润的50%') && app.includes('领取70%'),
  'battle V1.1 retained': app.includes('高低战力均可互相挑战') && app.includes('今日的20次主动挑战')
};
for (const [name, ok] of Object.entries(checks)) console.log((ok ? 'PASS ' : 'FAIL ') + name);
const failed = Object.entries(checks).filter(([, ok]) => !ok).map(([name]) => name);
console.log(JSON.stringify({ok: failed.length === 0, checks: Object.keys(checks).length, failed}, null, 2));
if (failed.length) throw new Error('failed: ' + failed.join(', '));
