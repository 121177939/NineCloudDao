#!/usr/bin/env python3
from pathlib import Path
import re,sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve(); checks=[]
def read(r): return (root/r).read_text('utf-8')
def ck(n,v): checks.append((n,bool(v)))
pre=read('SQL/71_V1.2_FIX1_升级前检查.sql');main=read('SQL/72_V1.2_FIX1_九霄灵牌正式并线.sql');gate=read('SQL/73_V1.2_FIX1_CACHE38_正式发布门禁.sql');post=read('SQL/74_V1.2_FIX1_升级后检查.sql');disable=read('SQL/75_V1.2_FIX1_紧急停用九霄灵牌.sql');resume=read('SQL/76_V1.2_FIX1_恢复九霄灵牌.sql')
for label,text in [('pre',pre),('post',post)]:
    executable='\n'.join(x for x in text.splitlines() if not x.lstrip().startswith('--')).lower()
    ck(label+'-readonly',not re.search(r'(?m)^\s*(update|insert|delete|create|alter|drop|truncate|grant|revoke)\b',executable))
for label,text in [('main',main),('gate',gate),('disable',disable),('resume',resume)]:
    ck(label+'-balanced-dollar',text.count('$$')%2==0)
    ck(label+'-balanced-transactions',text.lower().count('begin;')==text.lower().count('commit;'))
ck('pre-no-missing-relation-reference','from public.paigow_rooms_bpaigow01' not in pre.lower())
ck('tables',all(x in main for x in ['paigow_rooms_bpaigow01','paigow_room_members_bpaigow01','paigow_rounds_bpaigow01','paigow_round_players_bpaigow01','paigow_round_secrets_bpaigow01','paigow_action_requests_bpaigow01']))
ck('rls-private',main.lower().count('enable row level security')>=8 and 'revoke all on table public.paigow_settings_bpaigow01,public.paigow_round_secrets_bpaigow01' in main.lower())
ck('thirty-two',main.count("('teen1'") == 1 and 'PAIGOW_TILE_DECK_NOT_32' in main)
ck('secure-rng','casino_secure_random_int_v1(v_i)' in main and 'gen_random_bytes(' not in main)
ck('shuffle-loop','while v_i>=2 loop' in main and 'v_i:=v_i-1' in main)
ck('four-room-index','paigow_room_slot_open_bpaigow01' in main and 'generate_series(1,4)' in main)
ck('idle-close',"interval '20 minutes'" in main and 'paigow_cleanup_rooms_bpaigow01' in main)
ck('capacities',"when p_game_mode='big' and p_duel_type='laohe' then 7" in main and "when p_game_mode='big' then 8" in main and 'else 9' in main)
ck('small-six-big-ten','small_multiplier_seconds integer not null default 6' in main and 'big_multiplier_seconds integer not null default 10' in main)
ck('weak-head','PAIGOW_HEAD_MUST_NOT_EXCEED_TAIL' in main and "'valid',(v_h->>'score')::bigint<=(v_t->>'score')::bigint" in main)
ck('one-robber-valid','array_length(v_candidates,1),0)<1' in main and 'array_length(v_candidates,1),0)<2' not in main)
ck('role-switch-guard',"v_room.status='playing' and v_existing_role='player'" in main)
ck('fee-250','player_fee_bps integer not null default 250' in main and 'fee_carry_start' in main)
ck('cancel-restores-fee-carry','set fee_carry_bps=v_round.fee_carry_start' in main)
ck('30pct','floor(v_available::numeric*0.30)::bigint' in main)
ck('laohe-bankroll',"'paigow_laohe_reserve_bpaigow01'" in main and "'paigow_laohe_settlement_bpaigow01'" in main)
ck('dealer-reserve',"'paigow_dealer_reserve_bpaigow01'" in main and 'PAIGOW_DEALER_LIABILITY_LIMIT' in main)
ck('settlement-tail-only',"v_round.phase<>'tail_reveal' or v_round.phase_deadline>clock_timestamp()" in main)
ck('idempotency','PAIGOW_REQUEST_ID_REUSED' in main and 'primary key(character_id,request_id)' in main)
ck('authenticated-rpcs','grant execute on function public.start_paigow_round_bpaigow01' in main)
ck('internal-revoked','public.paigow_settle_round_internal_bpaigow01(uuid) from public,anon,authenticated' in main)
ck('gate-cache38',"release_name='V1.2 FIX1 CACHE38'" in gate and 'greatest(cache_epoch,38)' in gate)
ck('emergency-refund','paigow_cancel_round_internal_bpaigow01' in disable and 'enabled=false' in disable.replace(' ',''))
ck('resume','enabled=true' in resume.replace(' ',''))
copy={
 'SQL/71_V1.2_FIX1_升级前检查.sql':'database/V1.2_FIX1/202607301500_v1_2_fix1_precheck.sql',
 'SQL/72_V1.2_FIX1_九霄灵牌正式并线.sql':'database/V1.2_FIX1/202607301510_v1_2_fix1_paigow_main.sql',
 'SQL/73_V1.2_FIX1_CACHE38_正式发布门禁.sql':'database/V1.2_FIX1/202607301520_v1_2_fix1_cache38_release.sql',
 'SQL/74_V1.2_FIX1_升级后检查.sql':'database/V1.2_FIX1/202607301530_v1_2_fix1_check.sql',
 'SQL/75_V1.2_FIX1_紧急停用九霄灵牌.sql':'database/V1.2_FIX1/202607301540_v1_2_fix1_emergency_disable_paigow.sql',
 'SQL/76_V1.2_FIX1_恢复九霄灵牌.sql':'database/V1.2_FIX1/202607301550_v1_2_fix1_resume_paigow.sql'}
for a,b in copy.items(): ck('migration-copy:'+a,(root/a).read_bytes()==(root/b).read_bytes())
failed=[n for n,v in checks if not v]
for n,v in checks: print(('PASS ' if v else 'FAIL ')+n)
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}')
raise SystemExit(bool(failed))
