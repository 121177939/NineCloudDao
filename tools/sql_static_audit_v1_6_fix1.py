#!/usr/bin/env python3
from pathlib import Path
import sys,re
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def ck(n,v): checks.append((n,bool(v)))
def read(r): return (root/r).read_text('utf-8')
main=read('SQL/94_V1.6_FIX1_老何庄大小牌九盲牌.sql');gate=read('SQL/95_V1.6_FIX1_CACHE45_正式发布门禁.sql');post=read('SQL/96_V1.6_FIX1_CACHE45_升级后检查.sql');db=read('database/V1.6_FIX1/202607310655_v1_6_fix1_laohe_blind_cards.sql')
ck('sql-db-copy-identical',main==db)
ck('transactions',main.rstrip().endswith('commit;') and gate.rstrip().endswith('commit;'))
ck('post-read-only',post.lstrip().startswith('--') and not re.search(r'\b(insert|update|delete|alter|create|drop)\b',post.split('\n',1)[1],re.I))
ck('balanced-dollar',all(x.count('$$')%2==0 for x in [main,gate]))
ck('laohe-branch',"v_room.duel_type='laohe'" in main)
ck('small-blind',"if v_phase='settled' then v_visible:=v_cards;else v_visible:='{}'::text[];end if" in main)
ck('big-blind-until-arrange',"v_phase in('arrange','head_reveal','tail_reveal','settled')" in main)
ck('laohe-public-mask',"v_laohe_visible:='{}'::text[]" in main and "elsif v_phase='head_reveal'" in main)
ck('pure-snapshot',all(x not in main for x in ['paigow_prepare_waiting_room_bpaigow01','paigow_advance_room_internal']))
ck('gate-cache45',"release_name='V1.6 FIX1 CACHE45'" in gate and 'greatest(cache_epoch,45)' in gate)
ck('post-checks',all(x in post for x in ['laohe_small_blind_before_settlement','laohe_big_blind_before_multiplier','v16_realtime_retained']))
for n,v in checks: print(('PASS ' if v else 'FAIL ')+n)
failed=[n for n,v in checks if not v]
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(bool(failed))
