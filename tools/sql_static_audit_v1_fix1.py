#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def t(r):return (root/r).read_text('utf-8').lower()
def ck(n,o):checks.append((n,bool(o)))
pre=t('SQL/32_V1.0_FIX1_升级前检查.sql');fix=t('SQL/33_V1.0_FIX1_挑战战报参数兼容修复.sql');gate=t('SQL/34_V1.0_FIX1_CACHE31_正式发布门禁.sql');post=t('SQL/35_V1.0_FIX1_升级后检查.sql');main=t('SQL/27_V1.0_BCOMBAT01_五行战斗与越阶挑战.sql')
ck('pre-readonly',all(x not in pre for x in ['update ','insert ','delete ','create ','alter ','drop ']))
ck('compat-transaction',fix.startswith('--') and 'begin;' in fix and fix.rstrip().endswith('commit;'))
ck('integer-overload','p_event_level integer' in fix and '::smallint' in fix)
ck('compat-private','revoke all on function public.world_event_publish_v0140' in fix and 'from public,anon,authenticated' in fix)
ck('main-fresh-cast',"end)::smallint" in main and 'null::timestamptz' in main)
ck('gate-cache31',"release_name='v1.0 fix1 cache31'" in gate and 'greatest(cache_epoch,31)' in gate)
ck('post-readonly',all(x not in post for x in ['update ','insert ','delete ','create ','alter ','drop ']))
ck('post-permission-check','compat_not_public' in post and 'authenticated' in post and 'anon' in post)
failed=[n for n,o in checks if not o]
for n,o in checks:print(('PASS ' if o else 'FAIL ')+n)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}');raise SystemExit(1 if failed else 0)
