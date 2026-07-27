from pathlib import Path
import json,re,sys
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path.cwd()
p=root/'database/V0.14.2/202607270900_v0142_world_feed_strict_newest.sql'
s=p.read_text('utf-8')
checks=[]
def ck(name,ok,detail=''): checks.append((name,bool(ok),detail))
ck('file',p.is_file())
ck('transaction',bool(re.search(r'(?mi)^begin;\s*$',s)) and bool(re.search(r'(?mi)^commit;\s*$',s)))
ck('dollar-pairs',s.count('$$')%2==0,str(s.count('$$')))
for token in [
 'jiuxiao_world_events_feed_sequence_seq',
 'add column if not exists feed_sequence bigint',
 "set default nextval('public.jiuxiao_world_events_feed_sequence_seq'::regclass)",
 'alter column feed_sequence set not null',
 'order by e.feed_sequence desc',
 'jsonb_agg(x.obj order by x.feed_sequence desc)',
 "'sort_mode', 'strict_newest_first'",
 "release_name = 'V0.14.2 CACHE6'",
 'cache_epoch = greatest(coalesce(cache_epoch, 0) + 1, 6)',
 'rpc_does_not_prioritize_pinned'
]: ck('token:'+token,token in s)
ck('no-pinned-order',s.lower().count('order by e.is_pinned')==1,str(s.lower().count('order by e.is_pinned')))
ck('grant','grant execute on function public.get_world_events_v1(integer) to authenticated;' in s)
ck('self-check-count',s.count("('rpc_")>=3 and "('release_control_cache6'" in s)
failed=[x for x in checks if not x[1]]
print(json.dumps({'ok':not failed,'checks':len(checks),'failed':[{'name':n,'detail':d} for n,_,d in failed]},ensure_ascii=False,indent=2))
raise SystemExit(1 if failed else 0)
