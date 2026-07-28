#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
main = (root / 'database/V0.15.3_FIX2/202607281930_v0153_fix2_spirit_stone_rpc.sql').read_text('utf-8').lower()
check = (root / 'database/V0.15.3_FIX2/202607281940_v0153_fix2_check.sql').read_text('utf-8').lower()
checks = {
    'transaction': 'begin;' in main and 'commit;' in main,
    'reader-replaced': 'create or replace function public.get_technique_system_v2()' in main,
    'upgrade-replaced': 'create or replace function public.upgrade_technique_v2' in main,
    'redeem-replaced': 'create or replace function public.redeem_technique_book_v0152' in main,
    'balance-helper': 'public.spirit_stone_balance_v0141(c.id)' in main,
    'atomic-debit': 'public.spirit_stone_debit_v0141(c.id,v_cost' in main.replace(' ', ''),
    'award-helper': 'public.award_spirit_stones_v3(c.id,v_total)' in main.replace(' ', ''),
    'no-rowtype-field': 'c.spirit_stones' not in main,
    'no-direct-player-balance-write': 'update public.player_characters set spirit_stones' not in main,
    'cache22-gate': "release_name='v0.15.3 fix2 cache22'" in main and 'greatest(cache_epoch,22)' in main,
    'schema-reload': "notify pgrst, 'reload schema'" in main,
    'final-check': 'reader_uses_inventory_balance' in check and 'upgrade_uses_atomic_debit' in check and 'redeem_uses_inventory_award' in check,
}
failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(('PASS ' if ok else 'FAIL ') + name)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
