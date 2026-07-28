#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();base=root/'database/V0.15.1'
files={
 'precheck':base/'202607282000_v0151_precheck.sql',
 'main':base/'202607282010_v0151_casino_world_feed_dealer_and_fish_40s.sql',
 'check':base/'202607282020_v0151_check.sql',
 'rollback':base/'202607282030_v0151_rollback.sql',
 'fix':base/'202607282040_v0151_fix1_fish_30_2_5_3.sql',
 'fixcheck':base/'202607282050_v0151_fix1_check.sql',
 'fixrollback':base/'202607282060_v0151_fix1_rollback.sql'
}
checks=[]
def ck(n,o): checks.append((n,bool(o)));print(('PASS' if o else 'FAIL'),n)
for n,p in files.items():ck('file:'+n,p.is_file())
main=files['main'].read_text('utf-8') if files['main'].is_file() else ''
check=files['check'].read_text('utf-8') if files['check'].is_file() else ''
fix=files['fix'].read_text('utf-8') if files['fix'].is_file() else ''
fixcheck=files['fixcheck'].read_text('utf-8') if files['fixcheck'].is_file() else ''
fixrollback=files['fixrollback'].read_text('utf-8') if files['fixrollback'].is_file() else ''
ck('transaction','\nbegin;' in main.lower() and main.rstrip().lower().endswith("notify pgrst,'reload schema';"))
ck('fish feed restored','world_event_publish_fish_round_v0151' in main)
ck('dealer detail',"format('玩家庄【%s】'" in main and 'dealer_name_snapshot' in main and "else '荷老' end" in main)
ck('win loss text','本局净赢' in main and '本局净输' in main)
for label,sql in [('main',main),('fix',fix)]:
 ck(label+' 40 second round',"clock_timestamp())/40" in sql and "p_round_no*40" in sql)
 ck(label+' 30 2 5 3',all(x in sql for x in ["interval '30 seconds'","interval '32 seconds'","interval '37 seconds'","interval '40 seconds'"]))
 ck(label+' rules',all(x in sql for x in ["'round_seconds',40","'betting_seconds',30","'lock_seconds',2","'reveal_seconds',5","'settlement_seconds',3","'next_seconds',0"]))
ck('settled phase 3 seconds',"settles_at+interval '3 seconds'" in main and "settles_at+interval '3 seconds'" in fix)
ck('settle calls feed','perform public.world_event_publish_fish_round_v0151(p_round_id)' in main)
ck('broadcast isolation','广播失败不得阻断赌局结算' in main)
ck('cache18',"release_name='V0.15.1 CACHE18'" in main and 'greatest(cache_epoch,18)' in main and "release_name='V0.15.1 CACHE18'" in fix)
ck('postcheck corrected','fish_betting_30_seconds' in check and 'fish_reveal_32_seconds' in check and 'fish_settle_37_seconds' in check)
ck('fix postcheck','fish_rules_30_2_5_3' in fixcheck and 'release_cache18' in fixcheck)
ck('fix rollback available',"interval '25 seconds'" in fixrollback and "release_name='V0.15.1 CACHE17'" in fixrollback)
ck('no destructive data',all(x not in (main+'\n'+fix).lower() for x in ['drop table','truncate','delete from public.casino_fish','delete from public.world_events']))
failed=[n for n,o in checks if not o];print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}');raise SystemExit(1 if failed else 0)
