from pathlib import Path
import json,re,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path.cwd(); p=root/'database/V0.14.5/202607272330_v0145_opportunity_v4_techniques_player_house_commission.sql'; s=p.read_text('utf-8'); checks=[]
def ck(n,o,d=''): checks.append((n,bool(o),d))
ck('file',p.is_file()); ck('transaction',bool(re.search(r'(?mi)^begin;\s*$',s)) and bool(re.search(r'(?mi)^commit;\s*$',s)))
ck('dollar-pairs',s.count('$$')%2==0,str(s.count('$$')))
for token in ['create table if not exists public.opportunity_v4_story_pool','create table if not exists public.opportunity_v4_result_pool','create table if not exists public.opportunity_v4_settlement_batches','create table if not exists public.opportunity_v4_technique_drop_rates','create table if not exists public.opportunity_v4_technique_pool','create or replace function public.settle_opportunity_v4','create or replace function public.ack_opportunity_v4_summary','create or replace function public.claim_cultivation_v1','create or replace function public.get_auto_opportunity_v3','player_house_win_commission_bps integer not null default 500','v_commission:=floor','winner_profit_commission_5pct','online_interval_seconds=300','offline_interval_seconds=300','offline_catchup_limit=864','alter table public.opportunity_v4_settlement_batches enable row level security','revoke all on table public.opportunity_v4_settlement_batches from public,anon,authenticated',"release_name='V0.14.5 CACHE9'",'cache_epoch=greatest(cache_epoch,9)',"notify pgrst,'reload schema'"]:
 ck('token:'+token,token in s)
ck('stories-120',s.count('"weight":1')>=240)
ck('support-12',len(re.findall(r"\('opp_support_[^']+'",s))>=24)
ck('fix7a-preserved','fix7a_odds_preserved' in s)
ck('v0144-preserved',all(x in s for x in ['v0144_insight_preserved','v0144_private_notice_preserved']))
ck('no-fix8','FIX8' not in s)
failed=[x for x in checks if not x[1]]
print(json.dumps({'ok':not failed,'checks':len(checks),'failed':[{'name':n,'detail':d} for n,_,d in failed]},ensure_ascii=False,indent=2)); raise SystemExit(1 if failed else 0)
