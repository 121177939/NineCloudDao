from pathlib import Path
import sys,json,re
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path.cwd()
p=root/'database/V0.14.7/202607280600_v0147_library_opportunity_inventory_house.sql'; s=p.read_text('utf-8'); low=s.lower(); checks=[]
def ck(n,o): checks.append((n,bool(o)))
for token in ['begin;','commit;','security definer','auth.uid()','character_technique_books','get_technique_library_v1','use_technique_book_v1','get_opportunity_history_v0147','use_inventory_item_quantity_v0147','play_house_game_v0147','system_cover_amount',"interval '2 hours'",'revoke all','grant execute',"notify pgrst",'cache_epoch=greatest(cache_epoch,11)']: ck(token,token in low)
ck('balanced-dollar',s.count('$$')%2==0)
ck('one-transaction',len(re.findall(r'(?im)^begin;\s*$',s))==1 and len(re.findall(r'(?im)^commit;\s*$',s))==1)
ck('correct-release-table','public.jiuxiao_app_release_control' in low and 'public.app_release_control' not in low.replace('public.jiuxiao_app_release_control',''))
ck('no-wealth-rank-requirement','wealth_rank' not in low and 'top_candidate' not in low.split('-- 验收：')[0])
ck('player-unlimited-no-liability-reject','casino_player_house_liability_exceeded' not in low)
ck('system-cover-calculation','v_system_cover:=greatest(v_player_profit-v_dealer_debit,0)' in low)
ck('system-house-preserved',"play_house_game_v0147('system'" in low and 'play_system_house_game_v0141_fix7a' in low)
ck('high-tier-only-rule',"v_grade in('天品','仙品','专属')" in s)
ck('batch-use-transactional','for i in 1..p_quantity loop' in low and 'use_inventory_item_v1(p_inventory_id)' in low)
failed=[n for n,o in checks if not o]
print(json.dumps({'ok':not failed,'checks':len(checks),'failed':failed},ensure_ascii=False,indent=2)); raise SystemExit(1 if failed else 0)
