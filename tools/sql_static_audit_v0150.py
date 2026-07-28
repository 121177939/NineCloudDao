#!/usr/bin/env python3
from pathlib import Path
import sys,re
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve()
base=root/'database/V0.15.0'
files={
 'precheck':base/'202607281900_v0150_precheck.sql',
 'main':base/'202607281910_v0150_fish_continuous_bet_world_feed_exclusion.sql',
 'check':base/'202607281920_v0150_check.sql',
 'rollback':base/'202607281930_v0150_rollback.sql'
}
checks=[]
def ck(n,o): checks.append((n,bool(o))); print(('PASS' if o else 'FAIL'),n)
for n,p in files.items(): ck('file:'+n,p.is_file())
main=files['main'].read_text('utf-8') if files['main'].is_file() else ''
check=files['check'].read_text('utf-8') if files['check'].is_file() else ''
rollback=files['rollback'].read_text('utf-8') if files['rollback'].is_file() else ''
ck('transaction',main.strip().startswith('--') and '\nbegin;' in main.lower() and main.rstrip().lower().endswith('commit;'))
ck('explicit fish guard',"coalesce(new.game_code, '') = 'fish_shrimp'" in main)
ck('early return after guard',re.search(r"game_code[^\n]*fish_shrimp[\s\S]{0,120}return new",main,re.I) is not None)
ck('preserves destiny triple','casino_destiny_triple' in main and 'is_destiny_triple' in main)
ck('preserves existing games',"when 'spirit_dice' then '灵骰问道'" in main and '气运龟卜' in main)
ck('cache16',"release_name = 'V0.15.0 CACHE16'" in main and 'greatest(cache_epoch, 16)' in main)
ck('postcheck guard','fish_world_feed_guard' in check and 'pg_get_functiondef' in check)
ck('rollback available','V0.14.9 CACHE15' in rollback and 'create or replace function public.world_event_from_house_game_v0140' in rollback)
ck('no destructive fish data',all(token not in main.lower() for token in ['drop table','truncate','delete from public.casino_fish']))
failed=[n for n,o in checks if not o]
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
