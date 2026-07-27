from pathlib import Path
import sys,json
root=Path(sys.argv[1]).resolve() if len(sys.argv)>1 else Path.cwd()
s=(root/'database/V0.14.6/202607280230_v0146_opportunity_history_detail.sql').read_text('utf-8').lower()
tokens=['begin;','commit;','security definer','auth.uid()','get_opportunity_history_v0146','opportunity_v3_results','opportunity_v4','deferrable initially deferred','revoke all','grant execute','notify pgrst','cache_epoch=greatest(cache_epoch,10)']
checks={t:t in s for t in tokens}; failed=[k for k,v in checks.items() if not v]
print(json.dumps({'ok':not failed,'checks':len(checks),'failed':failed},ensure_ascii=False,indent=2)); raise SystemExit(1 if failed else 0)
