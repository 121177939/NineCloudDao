#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def ck(n,o):checks.append((n,bool(o)))
pre=(root/'SQL/20_V0.15.5_升级前检查.sql').read_text('utf-8').lower()
up=(root/'SQL/21_V0.15.5_CACHE26_洞府元神发布门禁.sql').read_text('utf-8').lower()
post=(root/'SQL/22_V0.15.5_升级后检查.sql').read_text('utf-8').lower()
ck('precheck-readonly',all(x not in pre for x in ['update ','insert ','delete ','create ','alter ','drop ']))
ck('release-table-check','jiuxiao_app_release_control' in pre)
ck('upgrade-transaction','begin;' in up and 'commit;' in up)
ck('cache26',"release_name = 'v0.15.5 cache26'" in up and 'greatest(cache_epoch, 26)' in up)
ck('no-schema-change',all(x not in up for x in ['create table','create function','alter table','drop table']))
ck('no-player-stone-write','player_characters set spirit_stones' not in up)
ck('postcheck-readonly',all(x not in post for x in ['update ','insert ','delete ','create ','alter ','drop ']))
ck('postcheck-cache26','cache_epoch >= 26' in post)
failed=[n for n,o in checks if not o]
for n,o in checks:print(('PASS ' if o else 'FAIL ')+n)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}');raise SystemExit(1 if failed else 0)
