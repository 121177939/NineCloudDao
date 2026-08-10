-- 九霄问道 SQL257
-- V2.2.0 CACHE126 / ADMIN9 R34
-- 天墟装备上架 LEFT JOIN FOR UPDATE 修复
-- 基线：SQL256 ONLINE
-- 仅替换 create_tianxu_listing_v255，不需要客户端更新。

begin;

do $pre$
declare v_def text;
begin
  if to_regprocedure('public.create_tianxu_listing_v255(text,text,bigint,bigint,uuid)') is null then
    raise exception 'SQL257_PRECHECK_TIANXU_CREATE_LISTING_MISSING';
  end if;
  if to_regclass('public.character_equipment_items_bequipment01') is null then
    raise exception 'SQL257_PRECHECK_EQUIPMENT_TABLE_MISSING';
  end if;
  if to_regclass('public.equipment_templates_bequipment01') is null then
    raise exception 'SQL257_PRECHECK_EQUIPMENT_TEMPLATE_TABLE_MISSING';
  end if;
end
$pre$;

create or replace function public.create_tianxu_listing_v255(p_asset_type text,p_asset_ref text,p_quantity bigint,p_unit_price bigint,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.tianxu_active_character_v255();v_set public.tianxu_settings_v255%rowtype;v_old jsonb;v_count int;v_fee bigint;v_name text;v_code text;v_grade_code text:='yellow';v_grade_name text:='黄品';v_category text:='other';v_snapshot jsonb:='{}'::jsonb;v_id uuid;v_q bigint;v_lib jsonb;v_book jsonb;v_rel text;v_eq record;v_def record;v_now timestamptz:=clock_timestamp();
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;if coalesce(p_quantity,0)<=0 then raise exception 'TIANXU_QUANTITY_INVALID'; end if;if coalesce(p_unit_price,0)<=0 then raise exception 'TIANXU_PRICE_INVALID'; end if;
  select result into v_old from public.tianxu_request_ledger_v255 where request_id=p_request_id and user_id=auth.uid();if v_old is not null then return v_old||jsonb_build_object('duplicate_request',true);end if;
  perform pg_advisory_xact_lock(hashtextextended('tianxu-list:'||p_request_id::text,25501));perform public.tianxu_sweep_expired_v255(50);
  select * into v_set from public.tianxu_settings_v255 where singleton_id=1 for update;if not v_set.enabled then raise exception 'TIANXU_DISABLED';end if;
  select count(*) into v_count from public.tianxu_listings_v255 where seller_character_id=v_char and status='active' and expires_at>v_now;if v_count>=v_set.max_active_listings then raise exception 'TIANXU_LISTING_LIMIT';end if;
  case p_asset_type
    when 'inventory' then
      select ci.*,d.code d_code,d.name d_name,d.category d_category,d.rarity d_rarity,to_jsonb(d) d_json into v_def from public.character_inventory ci join public.item_definitions d on d.id=ci.item_definition_id where ci.id=p_asset_ref::uuid and ci.character_id=v_char for update of ci;
      if v_def.id is null or v_def.quantity<p_quantity then raise exception 'TIANXU_ITEM_INSUFFICIENT';end if;if v_def.d_code='spirit_stone' then raise exception 'TIANXU_CURRENCY_NOT_LISTABLE';end if;
      update public.character_inventory set quantity=quantity-p_quantity where id=v_def.id;
      v_name:=v_def.d_name;v_code:=v_def.d_code;v_grade_code:=public.tianxu_grade_code_v255(v_def.d_rarity::text);v_grade_name:=public.tianxu_grade_name_v255(v_grade_code);v_category:=public.tianxu_category_v255(v_def.d_category::text,v_name);v_snapshot:=jsonb_build_object('definition',v_def.d_json,'item_instance',v_def.item_instance,'is_bound',v_def.is_bound);
    when 'combat_shard' then
      select quantity into v_q from public.combat_technique_shards_v220 where character_id=v_char and technique_code=p_asset_ref for update;if coalesce(v_q,0)<p_quantity then raise exception 'TIANXU_ITEM_INSUFFICIENT';end if;
      select code,display_name,grade_code,family,description into v_def from public.combat_technique_definitions_v220 where code=p_asset_ref;if v_def.code is null then raise exception 'TIANXU_ASSET_NOT_FOUND';end if;
      update public.combat_technique_shards_v220 set quantity=quantity-p_quantity,updated_at=v_now where character_id=v_char and technique_code=p_asset_ref;
      v_code:=p_asset_ref;v_name:='《'||v_def.display_name||'》残卷';v_grade_code:=v_def.grade_code;v_grade_name:=public.tianxu_grade_name_v255(v_grade_code);v_category:='shard';v_snapshot:=jsonb_build_object('technique_code',v_code,'technique_name',v_def.display_name,'family',v_def.family,'description',v_def.description,'kind','shard');
    when 'combat_book' then
      select quantity into v_q from public.combat_technique_books_v220 where character_id=v_char and technique_code=p_asset_ref for update;if coalesce(v_q,0)<p_quantity then raise exception 'TIANXU_ITEM_INSUFFICIENT';end if;
      select code,display_name,grade_code,family,description into v_def from public.combat_technique_definitions_v220 where code=p_asset_ref;if v_def.code is null then raise exception 'TIANXU_ASSET_NOT_FOUND';end if;
      update public.combat_technique_books_v220 set quantity=quantity-p_quantity,updated_at=v_now where character_id=v_char and technique_code=p_asset_ref;
      v_code:=p_asset_ref;v_name:='《'||v_def.display_name||'》完整道卷';v_grade_code:=v_def.grade_code;v_grade_name:=public.tianxu_grade_name_v255(v_grade_code);v_category:='technique';v_snapshot:=jsonb_build_object('technique_code',v_code,'technique_name',v_def.display_name,'family',v_def.family,'description',v_def.description,'kind','combat_book');
    when 'technique_book' then
      v_lib:=public.get_technique_library_v1();select value into v_book from jsonb_array_elements(coalesce(v_lib->'books','[]'::jsonb)) where value->>'book_id'=p_asset_ref limit 1;if v_book is null or coalesce((v_book->>'quantity')::int,0)<p_quantity then raise exception 'TIANXU_ITEM_INSUFFICIENT';end if;
      perform public.tianxu_debit_technique_book_v255(v_char,p_asset_ref::uuid,p_quantity::integer);
      v_code:=coalesce(v_book->>'technique_code',p_asset_ref);v_name:='《'||coalesce(v_book->>'name',v_book->>'technique_name','未知道卷')||'》道卷';v_grade_code:=public.tianxu_grade_code_v255(coalesce(v_book->>'grade_code',v_book->>'grade_name','yellow'));v_grade_name:=public.tianxu_grade_name_v255(v_grade_code);v_category:='technique';v_snapshot:=v_book;
    when 'equipment' then
      select e.*,to_jsonb(e) e_json,to_jsonb(t) t_json into v_eq from public.character_equipment_items_bequipment01 e left join public.equipment_templates_bequipment01 t on t.id=e.template_id where e.id=p_asset_ref::uuid and e.character_id=v_char for update of e;
      if v_eq.id is null then raise exception 'TIANXU_ASSET_NOT_FOUND';end if;if p_quantity<>1 then raise exception 'TIANXU_EQUIPMENT_QUANTITY_ONE';end if;if v_eq.location<>'backpack' then raise exception 'TIANXU_EQUIPMENT_BACKPACK_ONLY';end if;if coalesce(v_eq.is_locked,false) or coalesce(v_eq.tianxu_escrowed_v255,false) then raise exception 'TIANXU_EQUIPMENT_LOCKED';end if;
      v_code:=coalesce(v_eq.t_json->>'code',v_eq.id::text);v_name:=coalesce(v_eq.t_json->>'full_name',v_eq.t_json->>'name',v_eq.t_json->>'short_name','未命名装备');v_grade_code:=public.tianxu_grade_code_v255(coalesce(v_eq.e_json->>'grade_code',v_eq.t_json->>'grade_code','yellow'));v_grade_name:=public.tianxu_grade_name_v255(v_grade_code);v_category:='equipment';
      v_snapshot:=jsonb_build_object(
        'item',v_eq.e_json,
        'template',v_eq.t_json,
        'sockets',coalesce((select jsonb_agg(public.equipment_v210_affix_display(v_eq.id,a.socket_index) order by a.socket_index) from public.equipment_socket_affixes_v210 a where a.equipment_item_id=v_eq.id),'[]'::jsonb)
      );
      update public.character_equipment_items_bequipment01 set location='cave',is_locked=true,tianxu_escrowed_v255=true where id=v_eq.id;
    else raise exception 'TIANXU_ASSET_TYPE_UNSUPPORTED:%',p_asset_type;
  end case;
  v_fee:=ceil((p_unit_price::numeric*p_quantity::numeric)*v_set.listing_fee_rate)::bigint;if v_fee>0 then perform public.equipment_v210_debit_spirit_stone_v243(v_char,v_fee);end if;
  insert into public.tianxu_listings_v255(seller_user_id,seller_character_id,asset_type,asset_ref,asset_code,item_name,grade_code,grade_name,market_category,quantity_total,quantity_remaining,unit_price,listing_fee,item_snapshot,expires_at)
  values(auth.uid(),v_char,p_asset_type,p_asset_ref,v_code,v_name,v_grade_code,v_grade_name,v_category,p_quantity,p_quantity,p_unit_price,v_fee,v_snapshot,v_now+make_interval(hours=>v_set.listing_duration_hours)) returning id into v_id;
  v_old:=jsonb_build_object('status','ok','listing_id',v_id,'item_name',v_name,'grade_name',v_grade_name,'quantity',p_quantity,'unit_price',p_unit_price,'listing_fee',v_fee,'expires_at',v_now+make_interval(hours=>v_set.listing_duration_hours),'spirit_stones_after',public.tianxu_inventory_adjust_v255(v_char,'spirit_stone',0));
  insert into public.tianxu_request_ledger_v255 values(p_request_id,auth.uid(),v_char,'create_listing',v_old,v_now);return v_old;
end $$;


-- 保持玩家只能通过正式 RPC 调用；CREATE OR REPLACE 会保留原有 ACL，
-- 这里仅确认函数仍为 SECURITY DEFINER 且锁定范围正确。
do $gate$
declare v_def text; v_secdef bool;
begin
  select pg_get_functiondef(p.oid), p.prosecdef
    into v_def, v_secdef
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='create_tianxu_listing_v255'
    and pg_get_function_identity_arguments(p.oid)='p_asset_type text, p_asset_ref text, p_quantity bigint, p_unit_price bigint, p_request_id uuid';

  if v_def is null then
    raise exception 'SQL257_GATE_CREATE_LISTING_MISSING';
  end if;
  if not v_secdef then
    raise exception 'SQL257_GATE_CREATE_LISTING_NOT_SECURITY_DEFINER';
  end if;
  if position('left join public.equipment_templates_bequipment01 t' in lower(v_def))=0 then
    raise exception 'SQL257_GATE_EQUIPMENT_TEMPLATE_JOIN_MISSING';
  end if;
  if position('for update of e' in lower(v_def))=0 then
    raise exception 'SQL257_GATE_EQUIPMENT_LOCK_SCOPE_NOT_FIXED';
  end if;
  if position('for update of ci' in lower(v_def))=0 then
    raise exception 'SQL257_GATE_INVENTORY_LOCK_SCOPE_NOT_FIXED';
  end if;
end
$gate$;

commit;

select jsonb_build_object(
  'sql',257,
  'gate','SQL257_GATE_PASSED',
  'patch','TIANXU_LISTING_OUTER_JOIN_LOCK_SCOPE',
  'client','CACHE126无需重发',
  'database','SQL257 ONLINE',
  'next_sql',258
) as sql257_install_result;
