#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve();checks=[]
def t(r):return (root/r).read_text('utf-8').lower()
def ck(n,o):checks.append((n,bool(o)))
pre=t('SQL/39_V1.0_FIX3_升级前检查.sql');story=t('SQL/40_V1.0_FIX3_挑战界闻趣味文案.sql');gate=t('SQL/41_V1.0_FIX3_CACHE33_正式发布门禁.sql');post=t('SQL/42_V1.0_FIX3_升级后检查.sql');rollback=t('SQL/43_V1.0_FIX3_界闻趣味文案回滚.sql')
ck('pre-readonly',all(x not in pre for x in ['update ','insert ','delete ','create ','alter ','drop ']))
ck('pre-cache32','cache_epoch>=32' in pre and 'v1.0 fix2 cache32' in pre)
ck('story-transaction',story.startswith('--') and 'begin;' in story and story.rstrip().endswith('commit;'))
ck('story-private-function','bcombat01_world_event_story_fix3' in story and 'revoke all on function public.bcombat01_world_event_story_fix3' in story)
ck('story-trigger','create trigger trg_bcombat01_refresh_world_event_fix3' in story and 'after insert or update of world_event_id' in story)
ck('story-isolated','exception when others' in story and 'return new;' in story)
ck('story-scope',"event_type='battle_challenge'" in story and "story_revision','v1.0_fix3'" in story)
ck('story-rich-copy',all(x in story for x in ['向%s发起挑战','被夺走%s点修为','摧枯拉朽','险胜半招','守榜退敌']))
ck('story-no-client-grant',all(x not in story for x in ['grant execute on function public.bcombat01_world_event_story_fix3','grant execute on function public.bcombat01_refresh_world_event_fix3']))
ck('gate-transaction',gate.startswith('--') and 'begin;' in gate and gate.rstrip().endswith('commit;'))
ck('gate-cache33',"release_name='v1.0 fix3 cache33'" in gate and 'greatest(cache_epoch,33)' in gate)
ck('gate-guards','battle_story_function_missing' in gate and 'battle_story_trigger_missing' in gate)
ck('post-readonly',all(x not in post for x in ['update ','insert ','delete ','create ','alter ','drop ']))
ck('post-cache33',"release_name='v1.0 fix3 cache33'" in post and 'cache_epoch>=33' in post)
ck('rollback-explicit','drop trigger if exists trg_bcombat01_refresh_world_event_fix3' in rollback and '历史界闻正文不会自动恢复' in rollback)
failed=[n for n,o in checks if not o]
for n,o in checks:print(('PASS ' if o else 'FAIL ')+n)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}');raise SystemExit(1 if failed else 0)
