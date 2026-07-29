#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve(); checks=[]
def t(p): return (root/p).read_text('utf-8').lower()
def ck(n,o): checks.append((n,bool(o)))
pre=t('SQL/44_V1.0_FIX4_升级前检查.sql'); main=t('SQL/45_V1.0_FIX4_赌坊安全结算.sql'); gate=t('SQL/46_V1.0_FIX4_CACHE34_正式发布门禁.sql'); post=t('SQL/47_V1.0_FIX4_升级后检查.sql'); stop=t('SQL/48_V1.0_FIX4_紧急停用玩家庄.sql')
ck('pre-readonly',all(x not in pre for x in ['update ','insert ','delete ','create ','alter ','drop ']))
ck('main-transaction','begin;' in main and main.rstrip().endswith('commit;'))
ck('ten-percent','house_stake_limit_bps' in main and '1000' in main and 'casino_stake_exceeds_ten_percent' in main)
ck('no-cover',"'system_cover_amount',0" in main and "system_cover_amount=0" in main and "player_house_system_cover',false" in main)
ck('max-liability','v_max_liability' in main and 'casino_player_house_dealer_insufficient' in main and 'dealer_reserved_amount' in main)
ck('idempotency','casino_bet_requests_v1' in main and 'p_request_id uuid' in main and 'casino_request_parameter_mismatch' in main)
ck('locks','pg_advisory_xact_lock' in main and 'for update' in main)
ck('five-percent-pool','player_house_win_commission_bps' in main and 'casino_pools' in main and 'five_percent_pool' in main)
ck('old-rpc-revoked',all(x in main for x in ['revoke all on function public.play_house_game_v0147','revoke all on function public.place_fish_shrimp_bet_v0148']))
ck('new-rpc-granted',all(x in main for x in ['grant execute on function public.play_house_game_v1_fix4','grant execute on function public.place_fish_shrimp_bet_v1_fix4']))
ck('gate-cache34',"release_name='v1.0 fix4 cache34'" in gate and 'greatest(cache_epoch,34)' in gate)
ck('post-readonly',all(x not in post for x in ['update ','insert ','delete ','create ','alter ','drop ']))
ck('emergency-player-only',"player_house_enabled=false" in stop and "casino_enabled=false" not in stop)
failed=[n for n,o in checks if not o]
for n,o in checks: print(('PASS ' if o else 'FAIL ')+n)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
