#!/usr/bin/env python3
from pathlib import Path
import sys,re
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def ck(n,v):checks.append((n,bool(v)))
def read(r):return (root/r).read_text('utf-8')
main=read('SQL/72_V1.2_FIX1_九霄灵牌正式并线.sql');h77=read('SQL/77_V1.2_FIX1_九霄灵牌创建房间入座类型修复.sql');h78=read('SQL/78_V1.2_FIX1_九霄灵牌开始牌局记录变量修复.sql');gate=read('SQL/79_V1.2_FIX2_CACHE39_牌九预览界面发布门禁.sql');post=read('SQL/80_V1.2_FIX2_CACHE39_升级后检查.sql')
ck('main-no-broken-case',"if v_count<case" not in main and "if v_count < case" not in main)
ck('main-case-parenthesized',"if v_count < (\n    case when v_room.duel_type='laohe' then 1 else 2 end\n  ) then" in main)
ck('main-hotfix77',main.count('1::smallint')>=2 and 'join_paigow_room_bpaigow01(v_room.id,1,false)' not in main)
ck('main-hotfix78','v_member record' in main and 'from public.paigow_room_members_bpaigow01 as rm' in main and 'v_cards text[];m record' not in main)
ck('hotfix77-idempotent','create or replace function public.create_paigow_room_bpaigow01' in h77 and 'notify pgrst' in h77)
ck('hotfix78-idempotent','create or replace function public.start_paigow_round_bpaigow01' in h78 and 'notify pgrst' in h78)
ck('gate-cache39',"release_name='V1.2 FIX2 CACHE39'" in gate and 'greatest(cache_epoch,39)' in gate)
ck('gate-requires-fixes','run_hotfix_77' in gate and 'run_hotfix_78' in gate and 'v_member record' in gate)
ck('post-checks',all(x in post for x in ['release_cache39','create_room_hotfix77','start_round_hotfix78_record','physical_tiles_32','secure_shuffle','mutation_system_retained']))
ck('balanced-dollar-main',main.count('$$')%2==0)
ck('balanced-dollar-gate',gate.count('$$')%2==0)
failed=[n for n,v in checks if not v]
for n,v in checks:print(('PASS ' if v else 'FAIL ')+n)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(bool(failed))
