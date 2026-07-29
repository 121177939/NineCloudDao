#!/usr/bin/env python3
from pathlib import Path
import re,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve(); checks=[]
def ck(n,o):checks.append((n,bool(o)))
def t(rel):return (root/rel).read_text('utf-8').lower()
pre=t('SQL/26_V1.0_升级前检查.sql'); main=t('SQL/27_V1.0_BCOMBAT01_五行战斗与越阶挑战.sql'); gate=t('SQL/28_V1.0_CACHE30_正式发布门禁.sql'); post=t('SQL/29_V1.0_升级后检查.sql'); disable=t('SQL/30_V1.0_战斗挑战紧急停用.sql'); rollback=t('SQL/31_V1.0_BCOMBAT01_完整回滚.sql')
ck('precheck-readonly',all(x not in pre for x in ['update ','insert ','delete ','create ','alter ','drop ']))
ck('precheck-cache25','cache_epoch >= 25' in pre and 'cache26/cache27' in pre)
ck('main-transaction','begin;' in main and main.rstrip().endswith('commit;'))
ck('main-44-stats','combat_realm_stats_bcombat01' in main and len(re.findall(r'\(\d+,\d+,\'[^\']+\',',main))>=44)
ck('main-five-elements',all(x in main for x in ["'metal'","'wood'","'water'","'fire'","'earth'"]))
ck('snapshot-wrapper','create or replace function public.get_my_battle_snapshot_v1()' in main and 'grant execute on function public.get_my_battle_snapshot_v1() to authenticated' in main)
ck('no-anon-snapshot','revoke all on function public.get_my_battle_snapshot_v1() from public,anon,authenticated' in main)
ck('challenge-rpcs',all(x in main for x in ['get_battle_power_ranking_bcombat01','get_battle_challenge_preview_bcombat01','challenge_battle_power_bcombat01','claim_battle_cultivation_escrow_bcombat01']))
ck('one-percent','cultivation_loss_rate numeric' in main and '0.01' in main)
ck('sword-heart-eight','sword_final_damage_bonus' in main and '0.08' in main and "-'combat_attribute_bonus'" in main)
ck('cap-preserved','character_cultivation_cap_v1' in main)
ck('world-feed-reused','world_event_publish_v0140' in main)
ck('main-no-release-control','jiuxiao_app_release_control' not in main)
ck('gate-cache30',"release_name = 'v1.0 cache30'" in gate and 'greatest(cache_epoch, 30)' in gate)
ck('post-readonly',all(x not in post for x in ['update ','insert ','delete ','create ','alter ','drop ']))
ck('post-wrapper','get_my_battle_snapshot_v1' in post and 'anon' in post and 'authenticated' in post)
ck('emergency-only-setting','battle_challenge_settings_bcombat01' in disable and 'drop ' not in disable)
ck('rollback-explicit',all(x in rollback for x in ['drop table if exists public.battle_challenges_bcombat01','cache_epoch=greatest(cache_epoch,31)','drop function if exists public.get_my_battle_snapshot_v1()']))
failed=[n for n,o in checks if not o]
for n,o in checks:print(('PASS ' if o else 'FAIL ')+n)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
