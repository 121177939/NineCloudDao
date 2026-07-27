from pathlib import Path
import json,re,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path.cwd()
p=root/'database/V0.14.3/202607271720_v0143_multi_ranking_wealth.sql'
s=p.read_text('utf-8')
checks=[]
def ck(name,ok,detail=''): checks.append((name,bool(ok),detail))
ck('file',p.is_file())
ck('transaction',bool(re.search(r'(?mi)^begin;\s*$',s)) and bool(re.search(r'(?mi)^commit;\s*$',s)))
ck('dollar-pairs',s.count('$$')%2==0,str(s.count('$$')))
for token in [
 'create or replace function public.get_wealth_ranking_v1',
 'public.spirit_stone_item_id_v0141()',
 "pc.status in ('active', 'secluded', 'missing')",
 'coalesce(stones.wealth, 0) desc',
 'r.major_order desc',
 'rs.minor_level desc',
 'pc.cultivation desc',
 'pc.created_at asc',
 "'wealth', wealth",
 "'is_self', user_id = v_user_id",
 "grant execute on function public.get_wealth_ranking_v1(integer, integer) to authenticated;",
 "revoke all on function public.get_wealth_ranking_v1(integer, integer) from public, anon, authenticated;",
 "release_name = 'V0.14.3 CACHE7'",
 'cache_epoch = greatest(cache_epoch, 7)',
 "notify pgrst, 'reload schema'"
]: ck('token:'+token,token in s)
for banned in ['email','device_session','access_token','refresh_token','lineage_id\'']:
    ck('privacy:'+banned,banned not in s.lower())
ck('no-asset-update',not bool(re.search(r'(?mi)^\s*update\s+public\.(player_characters|character_inventory)\b',s)))
ck('self-check-count',s.count("select '")>=8)
failed=[x for x in checks if not x[1]]
print(json.dumps({'ok':not failed,'checks':len(checks),'failed':[{'name':n,'detail':d} for n,_,d in failed]},ensure_ascii=False,indent=2))
raise SystemExit(1 if failed else 0)
