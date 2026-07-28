'use strict';
const fs=require('fs'),path=require('path');
const root=path.resolve(process.argv[2]||process.argv[1]||'.');
const app=fs.readFileSync(path.join(root,'app.js'),'utf8');
const css=fs.readFileSync(path.join(root,'styles.css'),'utf8');
const sql=fs.readFileSync(path.join(root,'database/V0.14.7/202607280600_v0147_library_opportunity_inventory_house.sql'),'utf8');
const checks=[
 ['library rpc',app.includes('rpcGetTechniqueLibraryV1')&&sql.includes('get_technique_library_v1')],
 ['book study',app.includes('data-use-technique-book')&&sql.includes('use_technique_book_v1')],
 ['specific opportunity result',app.includes('opportunityResultDetailText')&&sql.includes('opportunity_result_detail_v0147')],
 ['history grade/title/story/result',app.includes('opportunity-history-result')&&app.includes('opportunity-grade-badge')&&sql.includes('get_opportunity_history_v0147')],
 ['high-tier shared color',css.includes('.opportunity-grade-badge.high-tier')&&app.includes("opportunityHighTier")],
 ['quantity modal',app.includes('inventoryQuantityBackdrop')&&app.includes('data-inventory-quantity-value="10"')],
 ['quantity rpc',app.includes('rpcUseInventoryItemQuantityV0147')&&sql.includes('use_inventory_item_quantity_v0147')],
 ['system player switch',app.includes('data-house-mode="system"')&&app.includes('data-house-mode="player"')],
 ['five million only',app.includes('统一灵石达到500万即可申请上庄')&&sql.includes('v_min_wealth bigint:=5000000')],
 ['two hour term',app.includes('最多坐庄2小时')&&sql.includes("interval '2 hours'")],
 ['unlimited player stake',app.includes('玩家庄局不限下注金额')&&sql.includes("'player_house_unlimited_stake',true")],
 ['system cover',app.includes('不足由荷老补足')&&sql.includes('v_system_cover:=greatest(v_player_profit-v_dealer_debit,0)')],
 ['commission retained',sql.includes('v_commission:=floor(v_gross_profit*v_commission_bps/10000)')&&sql.includes('v_player_profit:=greatest(v_gross_profit_int-v_commission,0)')],
 ['fix7a system route',sql.includes("play_house_game_v0147('system'")&&sql.includes('play_system_house_game_v0141_fix7a')],
 ['old client system safe',sql.includes('旧客户端固定走荷老')],
 ['no unauthorized loss',app.includes('荷老（系统庄）')]
];
for(const [n,o] of checks) console.log(o?'PASS':'FAIL',n);
const failed=checks.filter(x=>!x[1]);
console.log(`TOTAL=${checks.length} PASS=${checks.length-failed.length} FAIL=${failed.length}`);
if(failed.length) process.exit(1);
