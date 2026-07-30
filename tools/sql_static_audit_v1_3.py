#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def ck(name,value): checks.append((name,bool(value)))
def read(rel): return (root/rel).read_text('utf-8')
gate=read('SQL/83_V1.3_CACHE41_GitHub_Pages可移植构建发布门禁.sql');post=read('SQL/84_V1.3_CACHE41_升级后检查.sql');main=read('SQL/72_V1.2_FIX1_九霄灵牌正式并线.sql')
ck('gate-transaction','begin;' in gate and 'commit;' in gate)
ck('gate-cache41',"release_name='V1.3 CACHE41'" in gate and 'greatest(cache_epoch,41)' in gate)
ck('gate-no-rule-change','不修改牌型、概率、洗牌、赔率、资金结算或战斗规则' in gate)
ck('post-release','release_cache41' in post)
ck('post-security',all(x in post for x in ['physical_tiles_32','secure_shuffle','private_secret_table','player_fee_250bps','mutation_system_retained']))
ck('create-minimums',"v_min := case when p_stake_type='cultivation' then 5000 else 10 end" in main)
for n,v in checks: print(('PASS ' if v else 'FAIL ')+n)
failed=[n for n,v in checks if not v]
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(bool(failed))
