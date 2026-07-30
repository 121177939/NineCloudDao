#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def t(p):return (root/p).read_text('utf-8').lower()
def ck(n,o):checks.append((n,bool(o)))
pre=t('SQL/49_V1.1_升级前检查.sql');main=t('SQL/50_V1.1_双向战力挑战与界闻修复.sql');gate=t('SQL/51_V1.1_CACHE35_正式发布门禁.sql');post=t('SQL/52_V1.1_升级后检查.sql')
ck('pre-readonly',all(x not in pre for x in ['update ','insert ','delete ','create ','alter ','drop ']))
ck('main-transaction','begin;' in main and main.rstrip().endswith('commit;'))
ck('daily-20','active_challenge_daily_limit=20' in main)
ck('cooldown-20','challenge_cooldown_minutes=20' in main and 'challenge_cooldown' in main)
ck('bidirectional','target_power_not_higher' not in main and "'can_challenge',id<>v_self_id" in main)
ck('rates','higher_power_win_rate=0.005' in main and 'lower_power_win_rate=0.01' in main)
ck('stage-progress','v_loser_stage_progress' in main and 'cultivation_required' in main)
ck('no-drop','greatest(v_loser_stage_floor,cultivation-v_transfer)' in main)
ck('equal-transfer','v_escrow:=v_transfer-v_granted' in main and 'v_transfer-v_granted' in main)
ck('same-opponent','pair_challenge_daily_limit' not in main and 'target_challenged_daily_limit' not in main)
ck('correct-event-table','update public.jiuxiao_world_events' in main and 'update public.world_events' not in main)
ck('history-backfill','set world_event_id=world_event_id' in main)
ck('gate-cache35',"release_name='v1.1 cache35'" in gate and 'greatest(cache_epoch,35)' in gate)
ck('post-readonly',all(x not in post for x in ['update ','insert ','delete ','create ','alter ','drop ']))
failed=[n for n,o in checks if not o]
for n,o in checks:print(('PASS ' if o else 'FAIL ')+n)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
