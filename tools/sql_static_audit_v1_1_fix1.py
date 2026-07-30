#!/usr/bin/env python3
from pathlib import Path
import re
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
checks: list[tuple[str, bool]] = []

def read(rel: str) -> str:
    return (root / rel).read_text('utf-8')

def ck(name: str, ok: object) -> None:
    checks.append((name, bool(ok)))

pre = read('SQL/58_V1.1_FIX1_升级前检查.sql')
main = read('SQL/59_V1.1_FIX1_赌场周期资金与公平结算.sql')
gate = read('SQL/60_V1.1_FIX1_CACHE36_正式发布门禁.sql')
post = read('SQL/61_V1.1_FIX1_升级后检查.sql')
disable = read('SQL/62_V1.1_FIX1_紧急停用赌坊.sql')
resume = read('SQL/63_V1.1_FIX1_恢复启用赌坊.sql')
low = main.lower()
compact = re.sub(r'\s+', '', low)

# Read-only scripts may contain words in comments/strings; reject executable DML/DDL at line starts.
pre_exec = '\n'.join(line for line in pre.splitlines() if not line.lstrip().startswith('--')).lower()
post_exec = '\n'.join(line for line in post.splitlines() if not line.lstrip().startswith('--')).lower()
ck('pre-readonly', not re.search(r'(?m)^\s*(update|insert|delete|create|alter|drop|truncate|grant|revoke)\b', pre_exec))
ck('post-readonly', not re.search(r'(?m)^\s*(update|insert|delete|create|alter|drop|truncate|grant|revoke)\b', post_exec))
ck('main-transaction', low.lstrip().startswith('--') and '\nbegin;' in low and low.rstrip().endswith('commit;'))
ck('balanced-dollar-quotes', main.count('$$') % 2 == 0 and main.count('$$') >= 30)

required_tables = ['casino_bankroll_v1', 'casino_bankroll_ledger_v1', 'casino_bankroll_periods_v1', 'casino_round_stake_usage_v1']
for table in required_tables:
    ck('table:' + table, f'create table if not exists public.{table}' in low)

required_functions = [
    'casino_secure_random_int_v1', 'casino_bankroll_available_v1', 'casino_bankroll_apply_v1',
    'casino_claim_round_stake_v1', 'casino_draw_house_result_fix1', 'casino_pool_draw_fix1',
    'casino_settle_bankroll_periods_v1', 'play_system_house_game_v0141_fix7a',
    'casino_play_player_house_v1_fix4', 'play_house_game_v1_fix4',
    'place_fish_shrimp_bet_v1_fix4', 'casino_fish_settle_round_v0148',
]
for fn in required_functions:
    ck('function:' + fn, f'function public.{fn}' in low)

ck('period-7200', 'casino_period_seconds=7200' in compact)
ck('close-60', 'casino_close_before_seconds=60' in compact)
ck('stone-target', 'casino_spirit_stone_target=100000000' in compact)
ck('cultivation-target', 'casino_cultivation_target=1000000000' in compact)
ck('profit-half', 'casino_profit_pool_bps=5000' in compact and 'floor(v_profit::numeric*0.50)' in compact)
ck('winner-70', 'floor(v_pool.amount::numeric*0.70)' in compact)
ck('loss-no-draw', 'v_profit>0' in compact and "notp_allow_draw" in compact)
ck('reset-exact-target', "balance=casewhenstake_type='spirit_stone'then100000000else1000000000end" in compact)
ck('no-history-offset', "historical_loss_compensation',false" in low and 'unrecovered' not in low)

ck('stake-limit-bps', 'house_stake_limit_bps=3000' in compact)
ck('stake-limit-formula', '*0.30' in main and 'casino_stake_exceeds_thirty_percent' in low)
ck('fish-round-aggregate', 'casino_claim_round_stake_v1(v_round_id' in compact)
ck('unlimited-play-copy', '不限制每日场次' in main and '不限制' in main)
ck('no-daily-limit-errors', 'casino_total_daily_limit' not in low and 'casino_house_daily_limit' not in low and 'casino_greed_cooldown' not in low)

ck('secure-rng-bytes', 'gen_random_bytes(4)' in low)
ck('secure-rng-rejection', 'v_raw<v_limit' in compact and 'v_raw%p_upper' in compact)
ck('no-postgres-random', 'random()' not in low)
ck('three-independent-dice', low.count('casino_secure_random_int_v1(6)+1') >= 6)  # dice + fish
ck('triple-excludes-side', "v_side:=casewhenv_is_triplethen'triple'" in compact)
ck('turtle-25-50-25', "v_roll<25" in compact and "v_roll<75" in compact)

ck('system-payouts', all(x in compact for x in [
    'system_dice_side_profit_bps=9500', 'system_dice_triple_profit_bps=332000',
    'system_turtle_neutral_profit_bps=9000', 'system_turtle_edge_profit_bps=28000',
    'system_fish_one_profit_bps=10600', 'system_fish_two_profit_bps=21000', 'system_fish_three_profit_bps=32000']))
ck('system-loss-to-bankroll', "'system_bet_received'" in low and "'system_fish_bet_received'" in low)
ck('system-win-from-bankroll', "'system_win_payout'" in low and "'system_fish_win_payout'" in low)
ck('atomic-bankroll-acceptance', low.count('perform 1 from public.casino_bankroll_v1 where stake_type=p_stake_type for update') >= 2)
ck('assert-lock-only-when-due', 'if v_end is null or clock_timestamp()>=v_end then' in low)
ck('no-direct-pool-per-bet', "'pool_contribution',0" in compact and 'fixed_bankroll_profit_share_no_direct_pool' in low)

ck('player-house-fee-250', 'player_house_win_commission_bps=250' in compact and '*0.025' in main)
ck('player-house-exact-integer-step', 'casino_player_house_stake_multiple_40' in low and 'mod(p_stake_amount,40)<>0' in compact)
ck('player-house-no-cover', 'system_cover_amount=0' in compact and 'player_house_97_5_fee_to_bankroll_no_cover' in low)
ck('dealer-self-pays', "spirit_stone_debit_v0141(p_dealer_character_id,v_gross" in compact)
ck('fish-dealer-reserve', 'v_reserve:=p_stake_amount*3' in compact and 'dealer_reserved_amount' in low)
ck('player-house-fee-bankroll', "'player_house_fee'" in low and "'player_house_fish_fee'" in low)
ck('duel-fee-bankroll', "'duel_platform_fee'" in low)

ck('idempotency', 'casino_bet_requests_v1' in low and 'casino_request_parameter_mismatch' in low)
ck('reject-concurrent', 'pg_try_advisory_xact_lock' in low and 'casino_request_in_progress' in low)
ck('old-rpc-revoked', 'revoke all on function public.play_house_game_v1(text,text,bigint,text)' in low)
ck('new-rpc-authenticated', 'grant execute on function public.play_house_game_v1_fix4(uuid,text,text,text,bigint,text) to authenticated' in low)
ck('bankroll-tables-private', all(f'revoke all on table public.{t}' in low for t in required_tables))

ck('gate-cache36', "release_name='v1.1 fix1 cache36'" in gate.lower() and 'greatest(cache_epoch,36)' in gate.lower())
ck('gate-settings', all(x in gate for x in ['house_stake_limit_bps=3000', 'casino_period_seconds=7200', 'player_house_win_commission_bps=250']))
ck('post-core-checks', all(x in post for x in ['pool_70_percent', 'profit_only_draw', 'no_system_cover', 'old_rpc_revoked']))
ck('emergency-revoke', 'enabled=false' in disable.lower() and 'revoke execute' in disable.lower())
ck('resume-guard', 'V1_1_FIX1_NOT_DEPLOYED' in resume and 'grant execute' in resume.lower())

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(('PASS ' if ok else 'FAIL ') + name)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
