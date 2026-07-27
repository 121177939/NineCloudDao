#!/usr/bin/env python3
from pathlib import Path
import re,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path(__file__).resolve().parents[1]
p=root/'database/V0.14.1/202607261700_v0141_spirit_stone_casino.sql'; s=p.read_text('utf-8'); p2=root/'database/V0.14.1/202607261930_v0141_fix2_loss_pool_rate.sql'; s2=p2.read_text('utf-8'); p3=root/'database/V0.14.1/202607262030_v0141_fix3_house_win_pool_rate.sql'; s3=p3.read_text('utf-8'); p4=root/'database/V0.14.1/202607262130_v0141_fix4_duel_pool_payout.sql'; s4=p4.read_text('utf-8'); p5=root/'database/V0.14.1/202607262230_v0141_fix4_cache1_release_control.sql'; s5=p5.read_text('utf-8'); p6=root/'database/V0.14.1/202607270100_v0141_fix5_breakthrough_insight_route.sql'; s6=p6.read_text('utf-8'); checks=[]
def ck(n,o,d=''): checks.append((n,bool(o),d))
ck('file',p.is_file()); ck('fix2-file',p2.is_file()); ck('fix3-file',p3.is_file()); ck('fix4-file',p4.is_file()); ck('cache1-file',p5.is_file()); ck('fix5-file',p6.is_file()); ck('transaction',bool(re.search(r'(?mi)^begin;\s*$',s)) and bool(re.search(r'(?mi)^commit;\s*$',s)))
ck('dollar-pairs',s.count('$$')%2==0,str(s.count('$$')))
for a,b,n in [('(',')','parentheses'),('[',']','brackets')]: ck(n,s.count(a)==s.count(b),f'{s.count(a)}/{s.count(b)}')
for token in [
 'V0141_REQUIRES_EXACTLY_ONE_SPIRIT_STONE_DEFINITION','create or replace function public.spirit_stone_normalize_character_v0141',
 'character_inventory_one_spirit_stone_v0141','create or replace function public.award_spirit_stones_v3',
 'create or replace function public.spirit_stone_debit_v0141','create or replace function public.award_cave_resource_v3',
 'create or replace function public.upgrade_exclusive_technique_v1','create or replace function public.get_spirit_stone_balance_v0141',
 'pool_hit_chance=0.40000','on conflict(stake_type,round_ends_at,character_id) do nothing','check(ticket_count=1)',
 'set amount=p.amount+p_stake_amount','v_pool_contribution:=d.stake_amount*2','random()<v_hit_chance',
 'offset v_pick limit 1','v_rollover:=p.amount','qualification_rule','one_per_character_per_round',
 'CASINO_STAKE_TOO_LARGE','notify pgrst','world_event_from_casino_draw_v0140']:
 ck('token:'+token,token in s)
for forbidden in ['CASINO_TOTAL_DAILY_LIMIT','CASINO_HOUSE_DAILY_LIMIT','CASINO_DUEL_DAILY_LIMIT','CASINO_CULTIVATION_DAILY_LIMIT','CASINO_GREED_COOLDOWN','ticket_count=t.ticket_count+1','sum(t.ticket_count)']:
 ck('removed:'+forbidden,forbidden not in s)
ck('no-ambiguous-pool-update','where p.stake_type=p_stake_type' not in s and 'where p.stake_type=p_stake_type' not in s2)
ck('one-definition-check',"count(*) from public.item_definitions where code='spirit_stone'" in s)
ck('private-internals',all(('revoke all on function public.'+fn) in s for fn in ['award_spirit_stones_v3','spirit_stone_debit_v0141','casino_credit_v1','casino_add_ticket_v1','casino_draw_pools_v1']))
ck('public-rpcs',all(('grant execute on function public.'+fn) in s for fn in ['get_market_v1','get_spirit_stone_balance_v0141','play_house_game_v1','create_duel_v1','join_duel_v1','cancel_duel_v1']))

for token in [
 'loss_pool_rate numeric(6,5) not null default 0.05000',
 'create or replace function public.casino_loss_split_v0141_fix2',
 'v_pool:=floor(p_loss_amount::numeric*v_rate)::bigint',
 'v_recovery:=p_loss_amount-v_pool',
 '仅实际败局损失',
 'heaven_recovery_amount',
 "sample_5000_pool_is_250",
 "sample_5000_recovery_is_4750"
]:
 ck('fix2-token:'+token, token in s2)
ck('fix2-transaction',bool(re.search(r'(?mi)^begin;\s*$',s2)) and bool(re.search(r'(?mi)^commit;\s*$',s2)))
ck('fix2-dollar-pairs',s2.count('$$')%2==0,str(s2.count('$$')))
ck('fix2-house-no-full-pool','set amount=p.amount+p_stake_amount' not in s2)
ck('fix2-duel-no-double-stake-pool','v_pool_contribution:=d.stake_amount*2' not in s2)
ck('fix2-permission', 'grant execute on function public.play_house_game_v1(text,text,bigint,text) to authenticated;' in s2)


for token in [
 'house_pool_rate numeric(6,5) not null default 0.05000',
 'create or replace function public.casino_house_stake_split_v0141_fix3',
 "v_pool:=floor(p_stake_amount::numeric*v_rate)::bigint",
 'v_requested_reward:=p_stake_amount+v_net_profit',
 'v_net_profit:=greatest(0,v_nominal_profit-v_pool_contribution)',
 'nominal_reward_amount',
 'sample_100_pool_is_5',
 'sample_even_win_total_is_195',
 '贵宾雅间继续沿用FIX2规则'
]:
 ck('fix3-token:'+token, token in s3)
ck('fix3-transaction',bool(re.search(r'(?mi)^begin;\s*$',s3)) and bool(re.search(r'(?mi)^commit;\s*$',s3)))
ck('fix3-dollar-pairs',s3.count('$$')%2==0,str(s3.count('$$')))
ck('fix3-house-pool-on-all-results','if v_won then' in s3 and s3.find('set amount=p.amount+v_pool_contribution') < s3.find("if p_game_code='spirit_dice'"))
ck('fix3-win-payout-195-example',"(100+100-(public.casino_house_stake_split_v0141_fix3(100)->>'pool_contribution')::bigint)=195" in s3)
ck('fix3-permission','grant execute on function public.play_house_game_v1(text,text,bigint,text) to authenticated;' in s3)



for token in [
 'create or replace function public.casino_duel_stake_split_v0141_fix4',
 'v_winner_transfer:=p_stake_amount-v_pool',
 "'winner_total_payout',p_stake_amount+v_winner_transfer",
 'v_requested_prize:=coalesce',
 'heaven_recovery_amount=0',
 'sample_100_winner_total_is_195',
 'sample_100_heaven_recovery_is_0',
 '败者赌注中的95转给胜者'
]:
 ck('fix4-token:'+token, token in s4)
ck('fix4-transaction',bool(re.search(r'(?mi)^begin;\s*$',s4)) and bool(re.search(r'(?mi)^commit;\s*$',s4)))
ck('fix4-dollar-pairs',s4.count('$$')%2==0,str(s4.count('$$')))
ck('fix4-no-heaven-recovery','v_heaven_recovery:=0;' in s4 and 'heaven_recovery_amount=0' in s4)
ck('fix4-payout-conservation',"'winner_total_payout',p_stake_amount+v_winner_transfer" in s4 and 'v_winner_transfer:=p_stake_amount-v_pool' in s4)


for token in [
 'create table if not exists public.jiuxiao_app_release_control',
 'create or replace function public.get_jiuxiao_app_release_control_v1()',
 'cache_epoch bigint not null default 1',
 'grant execute on function public.get_jiuxiao_app_release_control_v1() to anon, authenticated',
 "notify pgrst, 'reload schema'",
 'cache_epoch = cache_epoch + 1'
]:
 ck('cache1-token:'+token, token in s5)
ck('cache1-transaction',bool(re.search(r'(?mi)^begin;\s*$',s5)) and bool(re.search(r'(?mi)^commit;\s*$',s5)))
ck('cache1-dollar-pairs',s5.count('$$')%2==0,str(s5.count('$$')))
ck('cache1-table-private','revoke all on table public.jiuxiao_app_release_control from public, anon, authenticated;' in s5)



for token in [
 'create or replace function public.get_breakthrough_status_v1()',
 'create or replace function public.attempt_breakthrough_v1()',
 'v_bonus:=least(0.80,greatest(0,v_insights*0.05));',
 'v_effective:=least(0.80,greatest(0,v_base+v_normal+v_insights*0.05));',
 'three_insights_equal_15_percent',
 "release_name='V0.14.1 FIX5 CACHE2'"
]:
 ck('fix5-token:'+token, token in s6)
ck('fix5-transaction',bool(re.search(r'(?mi)^begin;\s*$',s6)) and bool(re.search(r'(?mi)^commit;\s*$',s6)))
ck('fix5-dollar-pairs',s6.count('$$')%2==0,str(s6.count('$$')))
s6_functions=s6.split('-- 已部署CACHE1时')[0]
ck('fix5-old-target-gates-removed','v_target_id=v_next.id then' not in s6_functions and 'v_original_target_id=v_next.id then' not in s6_functions)
failed=[x for x in checks if not x[1]]
for n,o,d in checks: print(('PASS' if o else 'FAIL'),n,d)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(1 if failed else 0)
