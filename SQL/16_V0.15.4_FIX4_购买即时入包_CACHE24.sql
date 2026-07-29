-- 九霄问道 V0.15.4 FIX4 CACHE24
-- 修复：珍宝阁购买成功后必须刷新才能显示、使用丹药。
-- 本脚本不回滚既有数据；可在已完成 FIX3 的数据库上直接执行。

begin;

create or replace function public.purchase_treasure_item_v0154(
  p_item_code text,
  p_quantity integer default 1,
  p_request_id uuid default gen_random_uuid()
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=auth.uid();
  v_character public.player_characters%rowtype;
  v_item_id uuid;
  v_inventory_id uuid;
  v_name text;
  v_category text;
  v_rarity text;
  v_stack_limit integer;
  v_effects jsonb;
  v_description text;
  v_price bigint;
  v_total bigint;
  v_remaining bigint;
  v_owned bigint;
  v_inventory_quantity bigint;
  v_year integer:=1;
  v_result jsonb;
begin
  if v_user_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if p_request_id is null then
    raise exception 'REQUEST_ID_REQUIRED';
  end if;
  if p_quantity is null or p_quantity<1 or p_quantity>99 then
    raise exception 'INVALID_PURCHASE_QUANTITY';
  end if;

  select pc.*
    into v_character
    from public.player_characters pc
   where pc.user_id=v_user_id
     and pc.status in('active','secluded','missing')
   order by pc.created_at desc
   limit 1
   for update;

  if v_character.id is null then
    raise exception 'NO_ACTIVE_CHARACTER';
  end if;

  select r.result
    into v_result
    from public.player_operation_requests_v0154 r
   where r.request_id=p_request_id
     and r.character_id=v_character.id
     and r.operation='purchase_treasure';
  if found then
    return v_result;
  end if;

  if exists(
    select 1
      from public.player_operation_requests_v0154 r
     where r.request_id=p_request_id
       and r.character_id<>v_character.id
  ) then
    raise exception 'REQUEST_ID_CONFLICT';
  end if;

  case p_item_code
    when 'breakthrough_clear_origin_pill_v0154' then v_price:=1000000;
    when 'spirit_washing_pill_v0154' then v_price:=5000000;
    else raise exception 'TREASURE_ITEM_NOT_FOUND';
  end case;

  select d.id,d.name,d.category::text,d.rarity::text,d.stack_limit,d.effects,d.description
    into v_item_id,v_name,v_category,v_rarity,v_stack_limit,v_effects,v_description
    from public.item_definitions d
   where d.code=p_item_code
   limit 1;

  if v_item_id is null then
    raise exception 'TREASURE_ITEM_NOT_FOUND';
  end if;

  v_total:=v_price*p_quantity::bigint;
  v_remaining:=public.spirit_stone_debit_v0141(
    v_character.id,
    v_total,
    'INSUFFICIENT_SPIRIT_STONES'
  );

  select coalesce(gw.current_year,1)
    into v_year
    from public.game_worlds gw
   where gw.id=v_character.world_id;

  select ci.id
    into v_inventory_id
    from public.character_inventory ci
   where ci.character_id=v_character.id
     and ci.item_definition_id=v_item_id
     and coalesce(ci.is_bound,false)=false
     and coalesce(ci.item_instance,'{}'::jsonb)='{}'::jsonb
   order by ci.created_at,ci.id
   limit 1
   for update;

  if v_inventory_id is null then
    insert into public.character_inventory(
      character_id,item_definition_id,quantity,is_bound,item_instance,acquired_year
    ) values (
      v_character.id,v_item_id,p_quantity,false,'{}'::jsonb,v_year
    )
    returning id,quantity into v_inventory_id,v_inventory_quantity;
  else
    update public.character_inventory
       set quantity=quantity+p_quantity,
           updated_at=now()
     where id=v_inventory_id
     returning quantity into v_inventory_quantity;
  end if;

  v_owned:=public.v0154_inventory_quantity(v_character.id,p_item_code);
  v_result:=jsonb_build_object(
    'success',true,
    'item_code',p_item_code,
    'item_name',v_name,
    'item_definition_id',v_item_id,
    'inventory_id',v_inventory_id,
    'inventory_quantity',v_inventory_quantity,
    'owned_quantity',v_owned,
    'item_category',v_category,
    'item_rarity',v_rarity,
    'item_stack_limit',v_stack_limit,
    'item_effects',coalesce(v_effects,'{}'::jsonb),
    'item_description',coalesce(v_description,''),
    'acquired_year',v_year,
    'quantity',p_quantity,
    'unit_price',v_price,
    'total_price',v_total,
    'spirit_stones_after',v_remaining,
    'request_id',p_request_id
  );

  insert into public.player_operation_requests_v0154(
    request_id,character_id,operation,result
  ) values (
    p_request_id,v_character.id,'purchase_treasure',v_result
  );

  return v_result;
end
$$;

revoke all on function public.purchase_treasure_item_v0154(text,integer,uuid)
from public,anon;
grant execute on function public.purchase_treasure_item_v0154(text,integer,uuid)
to authenticated;

update public.jiuxiao_app_release_control
set release_name='V0.15.4 FIX4 CACHE24',
    cache_epoch=greatest(cache_epoch,24),
    notice_text='V0.15.4 FIX4：珍宝阁购买成功后即时入包、即时显示并可直接使用，无需刷新。',
    updated_at=now()
where singleton_id=1;

insert into public.jiuxiao_app_release_control(
  singleton_id,release_name,cache_epoch,notice_text,updated_at
)
select 1,'V0.15.4 FIX4 CACHE24',24,
       'V0.15.4 FIX4：珍宝阁购买成功后即时入包、即时显示并可直接使用，无需刷新。',now()
where not exists(
  select 1 from public.jiuxiao_app_release_control where singleton_id=1
);

select pg_notify('pgrst','reload schema');

commit;

select
  to_regprocedure('public.purchase_treasure_item_v0154(text,integer,uuid)') is not null
  and pg_get_functiondef(to_regprocedure('public.purchase_treasure_item_v0154(text,integer,uuid)')) ilike '%inventory_id%'
  and pg_get_functiondef(to_regprocedure('public.purchase_treasure_item_v0154(text,integer,uuid)')) ilike '%item_effects%'
  and exists(
    select 1 from public.jiuxiao_app_release_control
    where singleton_id=1 and cache_epoch>=24
  ) as ok,
  '购买RPC已返回即时入包所需数据，发布缓存已升至CACHE24' as detail;
