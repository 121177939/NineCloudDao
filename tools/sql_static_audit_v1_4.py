#!/usr/bin/env python3
from pathlib import Path
import sys,re
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def ck(name,value): checks.append((name,bool(value)))
def read(rel): return (root/rel).read_text('utf-8')
main=read('SQL/85_V1.4_九霄牌九自动准备与私密明牌.sql')
gate=read('SQL/86_V1.4_CACHE42_正式发布门禁.sql')
post=read('SQL/87_V1.4_CACHE42_升级后检查.sql')
ck('main-transaction',main.lstrip().startswith('--') and '\nbegin;' in main and main.rstrip().endswith('commit;'))
ck('columns',all(x in main for x in ['ready_deadline timestamptz','auto_start_at timestamptz','ready_seconds integer','auto_start_seconds integer']))
ck('timings',all(x in main for x in ['ready_seconds=10','auto_start_seconds=2','small_multiplier_seconds=5']))
ck('ready-timeout',all(x in main for x in ['ready_deadline<=clock_timestamp()',"set left_at=clock_timestamp(),ready=false"]))
ck('auto-start',all(x in main for x in ["auto_start_at=coalesce(auto_start_at","return public.start_paigow_round_bpaigow01(p_room_id,gen_random_uuid())"]))
ck('no-owner-start',"PAIGOW_ONLY_OWNER_STARTS" not in main and "PAIGOW_AUTO_START_NOT_READY" in main)
ck('private-card',main.count("v_visible:='{}'::text[]")>=2 and "v_visible:=v_cards[1:1]" in main and "只对牌主本人可见" in main)
ck('laohe-private',"else v_laohe_visible:='{}'::text[];end if;" in main)
ck('delete-guard',all(x in main for x in ['delete_paigow_room_bpaigow01','PAIGOW_ONLY_OWNER_DELETES','PAIGOW_CANNOT_DELETE_ACTIVE_ROOM']))
ck('permissions',"grant execute on function public.delete_paigow_room_bpaigow01(uuid) to authenticated" in main)
ck('gate-cache42',"release_name='V1.4 CACHE42'" in gate and 'greatest(cache_epoch,42)' in gate)
ck('post-checks',all(x in post for x in ['release_cache42','timing_settings','private_small_open_card','active_room_delete_guard','secure_shuffle_retained']))
ck('balanced-dollar',main.count('$$')%2==0 and gate.count('$$')%2==0)
for n,v in checks: print(('PASS ' if v else 'FAIL ')+n)
failed=[n for n,v in checks if not v]
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(bool(failed))
