#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def t(r):return (root/r).read_text('utf-8').lower()
def ck(n,o):checks.append((n,bool(o)))
pre=t('SQL/36_V1.0_FIX2_升级前检查.sql');gate=t('SQL/37_V1.0_FIX2_CACHE32_正式发布门禁.sql');post=t('SQL/38_V1.0_FIX2_升级后检查.sql')
ck('pre-readonly',all(x not in pre for x in ['update ','insert ','delete ','create ','alter ','drop ']))
ck('pre-cache31','cache_epoch>=31' in pre and 'v1.0 fix1 cache31' in pre)
ck('gate-transaction',gate.startswith('--') and 'begin;' in gate and gate.rstrip().endswith('commit;'))
ck('gate-cache32',"release_name='v1.0 fix2 cache32'" in gate and 'greatest(cache_epoch,32)' in gate)
ck('gate-no-schema-ddl',all(x not in gate for x in ['create table','alter table','drop table','create function','create trigger','enable row level security']))
ck('gate-rpc-guards',all(x in gate for x in ['get_battle_power_ranking_bcombat01','get_battle_challenge_preview_bcombat01','challenge_battle_power_bcombat01']))
ck('post-readonly',all(x not in post for x in ['update ','insert ','delete ','create ','alter ','drop ']))
ck('post-cache32',"release_name='v1.0 fix2 cache32'" in post and 'cache_epoch>=32' in post)
failed=[n for n,o in checks if not o]
for n,o in checks:print(('PASS ' if o else 'FAIL ')+n)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}');raise SystemExit(1 if failed else 0)
