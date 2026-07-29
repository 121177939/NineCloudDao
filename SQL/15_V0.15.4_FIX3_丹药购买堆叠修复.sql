-- 九霄问道 V0.15.4 CACHE23 丹药购买 FIX3
-- 适用场景：正式升级已成功，但购买渡境清元丹/洗灵丹时报：
-- there is no unique or exclusion constraint matching the ON CONFLICT specification
--
-- 原因：线上 character_inventory 没有 (character_id,item_definition_id) 唯一约束。
-- 修复方式：不改背包表结构；利用已持有的角色行锁，改为“先更新已有堆叠，未命中再插入”。
-- 失败的旧购买请求属于同一数据库事务，灵石扣除会随异常自动回滚。

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
  v_price bigint;
  v_total bigint;
  v_remaining bigint;
  v_owned bigint;
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

  -- 同一角色的购买请求串行执行，保证“更新或插入”不会并发生成重复堆叠。
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

  select d.id,d.name
    into v_item_id,v_name
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

  -- 只复用本系统创建的未绑定、空实例堆叠；不依赖任何唯一约束。
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
    returning id into v_inventory_id;
  else
    update public.character_inventory
       set quantity=quantity+p_quantity,
           updated_at=now()
     where id=v_inventory_id;
  end if;

  v_owned:=public.v0154_inventory_quantity(v_character.id,p_item_code);
  v_result:=jsonb_build_object(
    'success',true,
    'item_code',p_item_code,
    'item_name',v_name,
    'quantity',p_quantity,
    'unit_price',v_price,
    'total_price',v_total,
    'owned_quantity',v_owned,
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

select pg_notify('pgrst','reload schema');

commit;

-- 执行后应返回 ok=true。
select
  to_regprocedure('public.purchase_treasure_item_v0154(text,integer,uuid)') is not null
  and pg_get_functiondef(to_regprocedure('public.purchase_treasure_item_v0154(text,integer,uuid)'))
      not ilike '%on conflict(character_id,item_definition_id)%'
  and pg_get_functiondef(to_regprocedure('public.purchase_treasure_item_v0154(text,integer,uuid)'))
      ilike '%v_inventory_id%'
  as ok,
  '丹药购买RPC已改为无唯一约束依赖的安全堆叠写入' as detail;
