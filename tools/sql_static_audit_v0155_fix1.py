#!/usr/bin/env python3
from pathlib import Path
import sys

root = Path(sys.argv[1] if len(sys.argv) > 1 else '.').resolve()
checks = []

def ck(name, ok):
    checks.append((name, bool(ok)))

pre = (root / 'SQL/23_V0.15.5_FIX1_升级前检查.sql').read_text('utf-8').lower()
up = (root / 'SQL/24_V0.15.5_FIX1_CACHE27_洞府视觉修正发布门禁.sql').read_text('utf-8').lower()
post = (root / 'SQL/25_V0.15.5_FIX1_升级后检查.sql').read_text('utf-8').lower()

ck('precheck-readonly', all(x not in pre for x in ['update ', 'insert ', 'delete ', 'create ', 'alter ', 'drop ']))
ck('precheck-release-table', 'jiuxiao_app_release_control' in pre)
ck('precheck-cache25-direct', 'cache_epoch >= 25' in pre)
ck('upgrade-transaction', 'begin;' in up and 'commit;' in up)
ck('cache27', "release_name = 'v0.15.5 fix1 cache27'" in up and 'greatest(cache_epoch, 27)' in up)
ck('direct-from-cache25', '不要求先执行 cache26' in up)
ck('no-schema-change', all(x not in up for x in [
    'create table', 'create function', 'alter table', 'drop table', 'create trigger', 'create policy'
]))
ck('no-player-stone-write', 'player_characters set spirit_stones' not in up)
ck('no-gameplay-write', all(x not in up for x in [
    'character_inventory set', 'breakthrough', 'cave_building', 'cultivation'
]))
ck('postcheck-readonly', all(x not in post for x in ['update ', 'insert ', 'delete ', 'create ', 'alter ', 'drop ']))
ck('postcheck-cache27', 'cache_epoch >= 27' in post and "release_name = 'v0.15.5 fix1 cache27'" in post)

failed = [name for name, ok in checks if not ok]
for name, ok in checks:
    print(('PASS ' if ok else 'FAIL ') + name)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
