#!/usr/bin/env python3
from pathlib import Path
import sys
root=Path(sys.argv[1] if len(sys.argv)>1 else '.').resolve()
main=(root/'database/V0.15.4/202607290100_v0154_cache23_full_upgrade.sql').read_text('utf-8').lower()
check=(root/'database/V0.15.4/202607290110_v0154_check.sql').read_text('utf-8').lower()
fix4=(root/'database/V0.15.4_FIX4/202607290730_v0154_fix4_treasure_instant_inventory_cache24.sql').read_text('utf-8').lower()
fix4check=(root/'database/V0.15.4_FIX4/202607290740_v0154_fix4_check.sql').read_text('utf-8').lower()
checks={
 'atomic-transaction':main.count('begin;')==1 and main.count('commit;')==1,
 'dollar-quotes':main.count('$$')%2==0,
 'security-definer':'security definer' in main and 'setsearch_path=public,pg_temp' in main.replace(' ',''),
 'idempotency-table':'player_operation_requests_v0154' in main,
 'ordinary-idempotent-rpc':'upgrade_technique_v0154' in main and 'p_request_id' in main,
 'exclusive-idempotent-rpc':'upgrade_exclusive_technique_v0154' in main,
 'item-idempotent-rpc':'use_inventory_item_quantity_v0154' in main,
 'stone-unified':'spirit_stone_debit_v0141' in main and 'update public.player_characters set spirit_stones' not in main,
 'technique-bucket':"e.source_key like 'opptech:%'" in main and "not (e.source_key like 'opptech:%'" in main,
 'breakthrough-pill-item':"'breakthrough_clear_origin_pill_v0154','渡境清元丹'" in main,
 'washing-pill-item':"'spirit_washing_pill_v0154','洗灵丹'" in main,
 'pill-category-fix':"array['consumable','pill','medicine','elixir','material','misc','currency']" in main and "'丹药','legendary'" not in main,
 'new-table-rls':all(x in main for x in ['alter table public.player_operation_requests_v0154 enable row level security','alter table ncd_b_module_backup.b02_functions enable row level security','alter table ncd_b_module_backup.b02_settings enable row level security']),
 'purchase-no-unsupported-on-conflict':"on conflict(character_id,item_definition_id) do update" not in main and 'v_inventory_id' in main,
 'pill-price':'1000000' in main,
 'wash-price':'5000000' in main,
 'pill-five-percent':'p_pill_quantity*0.05' in main and 'least(1.0' in main,
 'pill-same-transaction':'set_config(\'ncd.v0154_breakthrough_pill_quantity\'' in main and 'attempt_breakthrough_v1()' in main,
 'b02-no-death':"status='dead'" not in main and "v_outcome:='death'" not in main,
 'b02-collapse':'v_roll<0.003' in main and "v_outcome:='dao_collapse'" in main,
 'b02-thresholds':all(x in main for x in ['v_roll<0.053','v_roll<0.133','v_roll<0.283','v_roll<0.583']),
 'permissions':all(x in main for x in ['grant execute on function public.get_treasure_shop_v0154() to authenticated','revoke all on table public.player_operation_requests_v0154 from public,anon,authenticated']),
 'cache23':"release_name='v0.15.4 cache23'" in main and 'greatest(cache_epoch,23)' in main,
 'postcheck':'technique_bucket_fixed' in check and 'pill_to_100' in check and 'release_cache23' in check,
 'fix4-transaction':fix4.count('begin;')==1 and fix4.count('commit;')==1,
 'fix4-response-payload':all(x in fix4 for x in ["'inventory_id'","'inventory_quantity'","'item_definition_id'","'item_effects'"]),
 'fix4-no-unique-dependency':'on conflict(character_id,item_definition_id)' not in fix4,
 'fix4-cache24':"release_name='v0.15.4 fix4 cache24'" in fix4 and 'greatest(cache_epoch,24)' in fix4,
 'fix4-permissions':'revoke all on function public.purchase_treasure_item_v0154(text,integer,uuid)' in fix4 and 'to authenticated' in fix4,
 'fix4-check':'treasure_instant_inventory_payload' in fix4check and 'release_cache24' in fix4check,
}
failed=[]
for n,o in checks.items(): print(('PASS ' if o else 'FAIL ')+n);failed += [] if o else [n]
print(f'TOTAL={len(checks)} PASS={len(checks)-len(failed)} FAIL={len(failed)}');raise SystemExit(1 if failed else 0)
