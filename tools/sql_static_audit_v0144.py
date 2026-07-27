from pathlib import Path
import json,re,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path.cwd()
p=root/'database/V0.14.4/202607272200_v0144_player_house_casino_notice_insight.sql'; s=p.read_text('utf-8'); checks=[]
def ck(n,o,d=''): checks.append((n,bool(o),d))
ck('file',p.is_file()); ck('transaction',bool(re.search(r'(?mi)^begin;\s*$',s)) and bool(re.search(r'(?mi)^commit;\s*$',s)))
ck('dollar-pairs',s.count('$$')%2==0,str(s.count('$$')))
for token in [
 'create or replace function public.get_casino_player_house_status_v1',
 'create or replace function public.set_casino_player_house_v1',
 'play_system_house_game_v0141_fix7a',
 'player_house_min_wealth=5000000',
 "p_stake_type<>'spirit_stone'",
 "'settlement_rule','zero_fee_full_transfer'",
 'create or replace function public.casino_current_stage_floor_v0144',
 'v_minimum:=least(50000,v_available)',
 'set cultivation=greatest(v_floor,pc.cultivation-p_amount)',
 "'realm_locked',true",
 'reveal_delay_seconds=0',
 'drop constraint if exists casino_settings_reveal_delay_seconds_check',
 'check (reveal_delay_seconds between 0 and 3600)',
 'reveal_at=now()',
 "perform public.casino_settle_duels_v1()",
 'create or replace function public.heavenly_insight_cultivation_multiplier_v0144',
 'coalesce(bs.heavenly_insight_count,0)::numeric * 0.10',
 'v_segment_fixed_rate * v_effective_qi_multiplier * v_insight_multiplier',
 'create table if not exists public.player_divine_notices',
 'create or replace function public.claim_next_divine_notice_v1',
 'create or replace function public.acknowledge_divine_notice_v1',
 "release_name='V0.14.4 CACHE8'",'cache_epoch=greatest(cache_epoch,8)',
 "notify pgrst,'reload schema'"
]: ck('token:'+token,token in s)
ck('no-realm-stage-update',not bool(re.search(r'(?is)update\s+public\.player_characters\s+[^;]*set\s+[^;]*realm_stage_id',s)))
ck('fix7a-odds',all(x in s for x in ['spirit_dice_ordinary_triple_denominator=80','spirit_dice_destiny_triple_result_denominator=5000','spirit_dice_ordinary_triple_net_odds=3','spirit_dice_destiny_triple_net_odds=34']))
ck('no-fix8','FIX8' not in s or '严禁执行V0.14.1 FIX8' in s)
ck('self-check-count',s.count("('player_house_rpc'") == 1 and s.count("('notice_ack_rpc'")==1)
failed=[x for x in checks if not x[1]]
print(json.dumps({'ok':not failed,'checks':len(checks),'failed':[{'name':n,'detail':d} for n,_,d in failed]},ensure_ascii=False,indent=2))
raise SystemExit(1 if failed else 0)
