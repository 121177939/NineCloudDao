#!/usr/bin/env node
'use strict';
const fs=require('fs'),path=require('path');
const root=path.resolve(process.argv[2]||path.join(__dirname,'..'));
const read=r=>fs.readFileSync(path.join(root,r),'utf8');
const pg=read('paigow-app.js'),css=read('paigow-app.css'),html=read('b-paigow01.html'),index=read('index.html'),loader=read('b-paigow01.js'),config=read('config.js'),sw=read('sw.js'),wf=read('.github/workflows/deploy-pages.yml'),main=read('SQL/88_V1.5_九霄牌九资金门槛与庄家比例结算.sql'),gate=read('SQL/89_V1.5_CACHE43_正式发布门禁.sql'),post=read('SQL/90_V1.5_CACHE43_升级后检查.sql');
const checks={
  'CACHE43 build':config.includes("version: '1.5.0'")&&config.includes("buildId: 'v1-5-cache43'")&&config.includes('cacheEpoch: 43'),
  'all launchers CACHE43':index.includes('b-paigow01.js?v=v1-5-cache43')&&loader.includes("v: 'v1-5-cache43'")&&html.includes('paigow-app.js?v=v1-5-cache43')&&sw.includes('nine-cloud-dao-v1.5-cache43'),
  'stable render retained':pg.includes('state.renderHtml !== nextHtml')&&pg.includes('state.renderHtml = nextHtml'),
  'private card retained':pg.includes('仅牌主本人可见')&&main.includes('paigow_round_compare_bpaigow01'),
  'five minute close':main.includes("interval '5 minutes'")&&main.includes('idle_close_seconds=300')&&pg.includes('5分钟'),
  'ten times entry':main.includes('return p_base_stake*10')&&pg.includes('底注10倍')&&pg.includes('minimum_entry_balance'),
  'underfunded spectator':main.includes('paigow_eject_underfunded_players_bpaigow01')&&main.includes("role='spectator'")&&pg.includes('自动起身'),
  'cultivation hidden':!pg.includes('name="stake" value="cultivation"')&&pg.includes('修为牌九暂时关闭')&&main.includes('PAIGOW_CULTIVATION_STAKES_TEMPORARILY_DISABLED'),
  'single hand ties banker':main.includes('paigow_pair_compare_vs_dealer_bpaigow01')&&main.includes('return -1;'),
  'big tie rule':main.includes('return 0; -- 大牌九仅一胜一负为整局平局')&&pg.includes('一胜一负为平局'),
  'tie fee refunded':main.includes('paigow_big_tie_fee_refund_v15')&&main.includes('v_requested:=rp.stake_amount+rp.fee_amount')&&pg.includes('手续费全退'),
  'dealer pro rata':main.includes('v_profit_pay_total:=least(v_profit_pool,v_winner_claim)')&&main.includes('remainder_rank')&&pg.includes('比例赔付'),
  'V1.4 flow retained':main.includes('ready_seconds')||read('SQL/85_V1.4_九霄牌九自动准备与私密明牌.sql').includes('ready_seconds=10'),
  'resource effects retained':pg.includes('pg-resource-particle')&&css.includes('.pg-resource-fx-layer'),
  'portable workflow':wf.includes('python3 tools/ci_v1_5.py .')&&!wf.toLowerCase().includes('playwright')&&!wf.includes('/usr/bin/chromium'),
  'release gate':gate.includes("release_name='V1.5 CACHE43'")&&gate.includes('greatest(cache_epoch,43)'),
  'post check':post.includes('player_dealer_pro_rata')&&post.includes('big_tie_fee_refund')
};
for(const [name,ok] of Object.entries(checks)) console.log((ok?'PASS ':'FAIL ')+name);
const failed=Object.entries(checks).filter(([,ok])=>!ok).map(([name])=>name);
console.log(JSON.stringify({ok:!failed.length,checks:Object.keys(checks).length,failed},null,2));
if(failed.length) throw new Error(failed.join(', '));
