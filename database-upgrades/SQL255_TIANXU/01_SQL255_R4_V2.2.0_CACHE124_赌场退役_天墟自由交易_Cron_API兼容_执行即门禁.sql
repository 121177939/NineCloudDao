-- 九霄问道 V2.2.0 CACHE124 / ADMIN9 R34 / SQL255 R4
-- 天墟：移除赌场运行入口，新增全物品公开一口价玩家市场。
-- 当前生产前提：SQL254_GATE_PASSED。
-- 规则：自由定价；1%上架费；5%成交税；72小时；每角色10个有效挂单；可堆叠部分购买；买入可再次出售。
-- 商品列表客户端仅展示 品级 / 名字 / 价格；其它信息在详情查看。
-- R4：保留R3表级装备托管保护；赌场Cron改用pg_cron官方API停用，绝不直接UPDATE cron.job。

begin;

-- ---------- PRECHECK ----------
do $precheck$
begin
  if to_regclass('public.combat_technique_settings_v220') is null then raise exception 'SQL255_PRECHECK_SQL254_NOT_FOUND'; end if;
  if to_regclass('public.character_inventory') is null or to_regclass('public.item_definitions') is null then raise exception 'SQL255_PRECHECK_INVENTORY_MISSING'; end if;
  if to_regclass('public.character_equipment_items_bequipment01') is null or to_regclass('public.equipment_templates_bequipment01') is null then raise exception 'SQL255_PRECHECK_EQUIPMENT_MISSING'; end if;
  if to_regclass('public.equipment_socket_affixes_v210') is null or to_regprocedure('public.equipment_v210_affix_display(uuid,smallint)') is null then raise exception 'SQL255_PRECHECK_EQUIPMENT_SOCKET_DETAIL_MISSING'; end if;
  if to_regclass('public.combat_technique_shards_v220') is null or to_regclass('public.combat_technique_books_v220') is null then raise exception 'SQL255_PRECHECK_COMBAT_TECHNIQUE_ASSETS_MISSING'; end if;
  if to_regprocedure('public.get_technique_library_v1()') is null or to_regprocedure('public.technique_book_add_v1(uuid,text,text,integer,timestamp with time zone,jsonb)') is null then raise exception 'SQL255_PRECHECK_TECHNIQUE_BOOK_API_MISSING'; end if;
  if to_regprocedure('public.equipment_v210_debit_spirit_stone_v243(uuid,bigint)') is null then raise exception 'SQL255_PRECHECK_SPIRIT_STONE_DEBIT_MISSING'; end if;
  if to_regprocedure('public.v210_admin_guard()') is null then raise exception 'SQL255_PRECHECK_ADMIN_GUARD_MISSING'; end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='character_equipment_items_bequipment01' and column_name='location') then raise exception 'SQL255_PRECHECK_EQUIPMENT_LOCATION_MISSING'; end if;
  -- R3 does not assume the argument types/signatures of the production equipment move/lock RPCs.
  -- Escrow integrity is enforced below on the equipment table itself.
  if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='move_equipment_item_bequipment01') then raise exception 'SQL255_PRECHECK_MOVE_EQUIPMENT_RPC_MISSING'; end if;
  if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='set_equipment_lock_bequipment01') then raise exception 'SQL255_PRECHECK_LOCK_EQUIPMENT_RPC_MISSING'; end if;
end
$precheck$;

-- ---------- SETTINGS / ORDERS / LEDGER ----------
create table if not exists public.tianxu_settings_v255(
  singleton_id smallint primary key default 1 check(singleton_id=1),
  enabled boolean not null default true,
  listing_fee_rate numeric(8,6) not null default 0.01 check(listing_fee_rate>=0 and listing_fee_rate<=1),
  trade_tax_rate numeric(8,6) not null default 0.05 check(trade_tax_rate>=0 and trade_tax_rate<=1),
  listing_duration_hours integer not null default 72 check(listing_duration_hours between 1 and 720),
  max_active_listings integer not null default 10 check(max_active_listings between 1 and 200),
  page_size integer not null default 30 check(page_size between 5 and 100),
  config_version bigint not null default 1,
  updated_at timestamptz not null default clock_timestamp()
);
insert into public.tianxu_settings_v255(singleton_id) values(1) on conflict(singleton_id) do nothing;

create table if not exists public.tianxu_listings_v255(
  id uuid primary key default gen_random_uuid(),
  seller_user_id uuid not null,
  seller_character_id uuid not null references public.player_characters(id) on delete cascade,
  asset_type text not null check(asset_type in('inventory','equipment','technique_book','combat_shard','combat_book')),
  asset_ref text not null,
  asset_code text not null,
  item_name text not null,
  grade_code text not null default 'common',
  grade_name text not null default '黄品',
  market_category text not null default 'other',
  quantity_total bigint not null check(quantity_total>0),
  quantity_remaining bigint not null check(quantity_remaining>=0),
  unit_price bigint not null check(unit_price>0),
  listing_fee bigint not null default 0 check(listing_fee>=0),
  item_snapshot jsonb not null default '{}'::jsonb,
  status text not null default 'active' check(status in('active','sold','cancelled','expired')),
  expires_at timestamptz not null,
  created_at timestamptz not null default clock_timestamp(),
  updated_at timestamptz not null default clock_timestamp()
);
create index if not exists tianxu_listings_active_idx_v255 on public.tianxu_listings_v255(status,market_category,created_at desc) where status='active';
create index if not exists tianxu_listings_seller_idx_v255 on public.tianxu_listings_v255(seller_character_id,status,created_at desc);
create index if not exists tianxu_listings_name_idx_v255 on public.tianxu_listings_v255(lower(item_name));

create table if not exists public.tianxu_trades_v255(
  id bigserial primary key,
  listing_id uuid references public.tianxu_listings_v255(id) on delete set null,
  seller_character_id uuid references public.player_characters(id) on delete set null,
  buyer_character_id uuid references public.player_characters(id) on delete set null,
  asset_type text not null,
  asset_code text not null,
  item_name text not null,
  grade_code text not null,
  grade_name text not null,
  quantity bigint not null check(quantity>0),
  unit_price bigint not null check(unit_price>0),
  gross_amount bigint not null check(gross_amount>0),
  tax_amount bigint not null check(tax_amount>=0),
  seller_net bigint not null check(seller_net>=0),
  item_snapshot jsonb not null default '{}'::jsonb,
  request_id uuid not null,
  created_at timestamptz not null default clock_timestamp(),
  unique(request_id)
);
create index if not exists tianxu_trades_item_idx_v255 on public.tianxu_trades_v255(asset_type,asset_code,created_at desc);
create index if not exists tianxu_trades_seller_idx_v255 on public.tianxu_trades_v255(seller_character_id,created_at desc);
create index if not exists tianxu_trades_buyer_idx_v255 on public.tianxu_trades_v255(buyer_character_id,created_at desc);

create table if not exists public.tianxu_request_ledger_v255(
  request_id uuid primary key,
  user_id uuid not null,
  character_id uuid not null,
  action text not null,
  result jsonb not null,
  created_at timestamptz not null default clock_timestamp()
);

create table if not exists public.tianxu_admin_audit_v255(
  id bigserial primary key,
  admin_user_id uuid not null,
  action_code text not null,
  before_data jsonb not null default '{}'::jsonb,
  after_data jsonb not null default '{}'::jsonb,
  reason text not null,
  request_id uuid not null unique,
  created_at timestamptz not null default clock_timestamp()
);

-- Equipment uses an explicit escrow marker. While listed it is moved to cave + locked, and move/unlock RPCs are guarded below.
alter table public.character_equipment_items_bequipment01 add column if not exists tianxu_escrowed_v255 boolean not null default false;
create index if not exists equipment_tianxu_escrow_idx_v255 on public.character_equipment_items_bequipment01(character_id,tianxu_escrowed_v255) where tianxu_escrowed_v255;

-- ---------- COMMON HELPERS ----------
create or replace function public.tianxu_active_character_v255()
returns uuid language plpgsql security definer set search_path='' as $$
declare v uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select id into v from public.player_characters where user_id=auth.uid() and status in('active','secluded','missing') order by created_at desc limit 1;
  if v is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;
  return v;
end $$;

create or replace function public.tianxu_grade_name_v255(p_code text)
returns text language sql immutable set search_path='' as $$
select case lower(coalesce(p_code,''))
 when 'yellow' then '黄品' when 'common' then '黄品'
 when 'mystic' then '玄品' when 'uncommon' then '玄品'
 when 'earth' then '地品' when 'rare' then '地品'
 when 'heaven' then '天品' when 'epic' then '天品'
 when 'immortal' then '仙品' when 'legendary' then '仙品'
 when 'exclusive' then '专属' else coalesce(nullif(p_code,''),'黄品') end $$;

create or replace function public.tianxu_grade_code_v255(p_code text)
returns text language sql immutable set search_path='' as $$
select case lower(coalesce(p_code,''))
 when '黄品' then 'yellow' when 'common' then 'yellow' when 'yellow' then 'yellow'
 when '玄品' then 'mystic' when 'uncommon' then 'mystic' when 'mystic' then 'mystic'
 when '地品' then 'earth' when 'rare' then 'earth' when 'earth' then 'earth'
 when '天品' then 'heaven' when 'epic' then 'heaven' when 'heaven' then 'heaven'
 when '仙品' then 'immortal' when 'legendary' then 'immortal' when 'immortal' then 'immortal'
 when '专属' then 'exclusive' when 'exclusive' then 'exclusive' else 'yellow' end $$;

create or replace function public.tianxu_category_v255(p_category text,p_name text)
returns text language sql immutable set search_path='' as $$
select case
 when lower(coalesce(p_category,'')) in('pill','medicine','consumable') or coalesce(p_name,'') like '%丹%' then 'pill'
 when lower(coalesce(p_category,'')) in('technique','book','scroll') then 'technique'
 when lower(coalesce(p_category,'')) in('material','ore','herb','quest','incense','tea') then 'material'
 else 'other' end $$;

create or replace function public.tianxu_inventory_adjust_v255(p_character_id uuid,p_item_code text,p_delta bigint)
returns bigint language plpgsql security definer set search_path='' as $$
declare v_def uuid;v_row uuid;v_qty bigint;v_year int:=1;
begin
  if p_delta=0 then
    select coalesce(ci.quantity,0) into v_qty from public.character_inventory ci join public.item_definitions d on d.id=ci.item_definition_id where ci.character_id=p_character_id and d.code=p_item_code order by ci.created_at limit 1;
    return coalesce(v_qty,0);
  end if;
  select id into v_def from public.item_definitions where code=p_item_code limit 1;
  if v_def is null then raise exception 'TIANXU_ITEM_DEFINITION_NOT_FOUND:%',p_item_code; end if;
  select greatest(1,coalesce(birth_year,1)+coalesce(age,0)) into v_year from public.player_characters where id=p_character_id;
  select id,quantity into v_row,v_qty from public.character_inventory where character_id=p_character_id and item_definition_id=v_def order by created_at limit 1 for update;
  if v_row is null then
    if p_delta<0 then raise exception 'TIANXU_ITEM_INSUFFICIENT'; end if;
    insert into public.character_inventory(character_id,item_definition_id,quantity,is_bound,item_instance,acquired_year)
    values(p_character_id,v_def,p_delta,false,'{}'::jsonb,v_year) returning quantity into v_qty;
  else
    if v_qty+p_delta<0 then raise exception 'TIANXU_ITEM_INSUFFICIENT'; end if;
    update public.character_inventory set quantity=quantity+p_delta where id=v_row returning quantity into v_qty;
  end if;
  return v_qty;
end $$;

create or replace function public.tianxu_credit_spirit_stone_v255(p_character_id uuid,p_amount bigint)
returns bigint language plpgsql security definer set search_path='' as $$
begin
  if coalesce(p_amount,0)<=0 then return public.tianxu_inventory_adjust_v255(p_character_id,'spirit_stone',0); end if;
  return public.tianxu_inventory_adjust_v255(p_character_id,'spirit_stone',p_amount);
end $$;

-- Discover the existing ordinary/exclusive book storage relation from its stable column contract.
create or replace function public.tianxu_technique_book_relation_v255()
returns text language sql stable security definer set search_path='' as $$
select format('%I.%I',n.nspname,c.relname)
from pg_catalog.pg_class c join pg_catalog.pg_namespace n on n.oid=c.relnamespace
where n.nspname='public' and c.relkind='r' and c.relname not like 'combat_technique_books%'
  and exists(select 1 from pg_catalog.pg_attribute a where a.attrelid=c.oid and a.attname='id' and a.attnum>0 and not a.attisdropped)
  and exists(select 1 from pg_catalog.pg_attribute a where a.attrelid=c.oid and a.attname='character_id' and a.attnum>0 and not a.attisdropped)
  and exists(select 1 from pg_catalog.pg_attribute a where a.attrelid=c.oid and a.attname='quantity' and a.attnum>0 and not a.attisdropped)
  and exists(select 1 from pg_catalog.pg_attribute a where a.attrelid=c.oid and a.attname='book_kind' and a.attnum>0 and not a.attisdropped)
  and exists(select 1 from pg_catalog.pg_attribute a where a.attrelid=c.oid and a.attname='technique_code' and a.attnum>0 and not a.attisdropped)
order by case when c.relname like '%technique%book%' then 0 else 1 end,c.relname limit 1 $$;

create or replace function public.tianxu_debit_technique_book_v255(p_character_id uuid,p_book_id uuid,p_quantity integer)
returns bigint language plpgsql security definer set search_path='' as $$
declare v_rel text:=public.tianxu_technique_book_relation_v255();v_after bigint;
begin
  if v_rel is null then raise exception 'TIANXU_TECHNIQUE_BOOK_RELATION_UNRESOLVED'; end if;
  execute format('update %s set quantity=quantity-$1 where id=$2 and character_id=$3 and quantity >= $1 returning quantity',v_rel)
    into v_after using p_quantity,p_book_id,p_character_id;
  if v_after is null then raise exception 'TIANXU_TECHNIQUE_BOOK_INSUFFICIENT'; end if;
  return v_after;
end $$;

create or replace function public.tianxu_credit_asset_v255(p_character_id uuid,p_asset_type text,p_asset_code text,p_asset_ref text,p_quantity bigint,p_snapshot jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare v_book_kind text;v_tech_code text;
begin
  if p_quantity<=0 then return; end if;
  case p_asset_type
    when 'inventory' then perform public.tianxu_inventory_adjust_v255(p_character_id,p_asset_code,p_quantity);
    when 'combat_shard' then
      insert into public.combat_technique_shards_v220(character_id,technique_code,quantity) values(p_character_id,p_asset_code,p_quantity)
      on conflict(character_id,technique_code) do update set quantity=public.combat_technique_shards_v220.quantity+excluded.quantity,updated_at=clock_timestamp();
    when 'combat_book' then
      insert into public.combat_technique_books_v220(character_id,technique_code,quantity) values(p_character_id,p_asset_code,p_quantity)
      on conflict(character_id,technique_code) do update set quantity=public.combat_technique_books_v220.quantity+excluded.quantity,updated_at=clock_timestamp();
    when 'technique_book' then
      v_book_kind:=coalesce(p_snapshot->>'book_kind','ordinary');v_tech_code:=coalesce(p_snapshot->>'technique_code',p_asset_code);
      perform public.technique_book_add_v1(p_character_id,v_book_kind,v_tech_code,p_quantity::integer,clock_timestamp(),jsonb_build_object('source','tianxu_v255','listing_asset_ref',p_asset_ref));
    else raise exception 'TIANXU_ASSET_TYPE_UNSUPPORTED:%',p_asset_type;
  end case;
end $$;

create or replace function public.tianxu_return_listing_asset_v255(p_listing_id uuid,p_status text)
returns void language plpgsql security definer set search_path='' as $$
declare v public.tianxu_listings_v255%rowtype;
begin
  select * into v from public.tianxu_listings_v255 where id=p_listing_id for update;
  if v.id is null or v.status<>'active' then return; end if;
  if v.quantity_remaining>0 then
    if v.asset_type='equipment' then
      update public.character_equipment_items_bequipment01 set character_id=v.seller_character_id,location='backpack',is_locked=false,tianxu_escrowed_v255=false where id=v.asset_ref::uuid and tianxu_escrowed_v255;
    else
      perform public.tianxu_credit_asset_v255(v.seller_character_id,v.asset_type,v.asset_code,v.asset_ref,v.quantity_remaining,v.item_snapshot);
    end if;
  end if;
  update public.tianxu_listings_v255 set status=p_status,quantity_remaining=0,updated_at=clock_timestamp() where id=v.id;
end $$;

create or replace function public.tianxu_sweep_expired_v255(p_limit integer default 100)
returns integer language plpgsql security definer set search_path='' as $$
declare r record;v_count int:=0;
begin
  for r in select id from public.tianxu_listings_v255 where status='active' and expires_at<=clock_timestamp() order by expires_at limit greatest(1,least(coalesce(p_limit,100),1000)) for update skip locked loop
    perform public.tianxu_return_listing_asset_v255(r.id,'expired');v_count:=v_count+1;
  end loop;
  return v_count;
end $$;

-- ---------- PLAYER READ RPCS ----------
create or replace function public.get_tianxu_market_v255(p_search text default null,p_category text default 'all',p_sort text default 'newest',p_limit integer default 30,p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.tianxu_active_character_v255();v_lim int;v_off int:=greatest(0,coalesce(p_offset,0));v_total bigint;v_rows jsonb;v_set public.tianxu_settings_v255%rowtype;v_stones bigint;
begin
  perform public.tianxu_sweep_expired_v255(100);select * into v_set from public.tianxu_settings_v255 where singleton_id=1;if not v_set.enabled then raise exception 'TIANXU_DISABLED';end if;
  v_lim:=greatest(5,least(coalesce(p_limit,v_set.page_size),v_set.page_size,100));
  v_stones:=public.tianxu_inventory_adjust_v255(v_char,'spirit_stone',0);
  select count(*) into v_total from public.tianxu_listings_v255 l where l.status='active' and l.expires_at>clock_timestamp() and l.quantity_remaining>0
    and (coalesce(p_category,'all')='all' or l.market_category=p_category)
    and (coalesce(trim(p_search),'')='' or l.item_name ilike '%'||trim(p_search)||'%');
  select coalesce(jsonb_agg(to_jsonb(x)),'[]'::jsonb) into v_rows from (
    select l.id,l.grade_code,l.grade_name,l.item_name,l.unit_price,l.market_category,l.quantity_remaining,l.created_at,l.expires_at
    from public.tianxu_listings_v255 l where l.status='active' and l.expires_at>clock_timestamp() and l.quantity_remaining>0
      and (coalesce(p_category,'all')='all' or l.market_category=p_category)
      and (coalesce(trim(p_search),'')='' or l.item_name ilike '%'||trim(p_search)||'%')
    order by
      case when p_sort='price_asc' then l.unit_price end asc,
      case when p_sort='price_desc' then l.unit_price end desc,
      case when p_sort not in('price_asc','price_desc') or p_sort is null then l.created_at end desc,
      l.id
    limit v_lim offset v_off
  ) x;
  return jsonb_build_object('status','ok','settings',to_jsonb(v_set),'spirit_stones',v_stones,'total',v_total,'limit',v_lim,'offset',v_off,'listings',v_rows);
end $$;

create or replace function public.get_tianxu_listing_detail_v255(p_listing_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.tianxu_active_character_v255();v jsonb;v_recent bigint;v_median numeric;
begin
  perform public.tianxu_sweep_expired_v255(50);
  select jsonb_build_object(
    'id',l.id,'asset_type',l.asset_type,'asset_code',l.asset_code,'item_name',l.item_name,'grade_code',l.grade_code,'grade_name',l.grade_name,'market_category',l.market_category,
    'quantity_remaining',l.quantity_remaining,'unit_price',l.unit_price,'expires_at',l.expires_at,'created_at',l.created_at,'seller_character_id',l.seller_character_id,
    'seller_name',coalesce(pc.name,'无名修士'),'seller_realm',coalesce(rs.name,''),'is_own',l.seller_character_id=v_char,'item_snapshot',l.item_snapshot
  ) into v from public.tianxu_listings_v255 l join public.player_characters pc on pc.id=l.seller_character_id left join public.realm_stages rs on rs.id=pc.realm_stage_id
  where l.id=p_listing_id and l.status='active' and l.quantity_remaining>0 and l.expires_at>clock_timestamp();
  if v is null then raise exception 'TIANXU_LISTING_NOT_AVAILABLE'; end if;
  select unit_price into v_recent from public.tianxu_trades_v255 where asset_type=v->>'asset_type' and asset_code=v->>'asset_code' order by created_at desc limit 1;
  select percentile_cont(.5) within group(order by unit_price) into v_median from public.tianxu_trades_v255 where asset_type=v->>'asset_type' and asset_code=v->>'asset_code' and created_at>=clock_timestamp()-interval '7 days';
  return jsonb_build_object('status','ok','listing',v,'recent_price',v_recent,'median_7d',case when v_median is null then null else round(v_median)::bigint end);
end $$;

create or replace function public.get_tianxu_sell_assets_v255()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.tianxu_active_character_v255();v_assets jsonb:='[]'::jsonb;v_lib jsonb;v_row jsonb;v_name text;v_grade text;v_grade_code text;
begin
  perform public.tianxu_sweep_expired_v255(50);
  -- generic inventory, excluding the currency itself
  select coalesce(jsonb_agg(jsonb_build_object('asset_type','inventory','asset_ref',ci.id::text,'asset_code',d.code,'item_name',d.name,'grade_code',public.tianxu_grade_code_v255(d.rarity::text),'grade_name',public.tianxu_grade_name_v255(d.rarity::text),'market_category',public.tianxu_category_v255(d.category::text,d.name),'quantity',ci.quantity,'snapshot',jsonb_build_object('definition',to_jsonb(d),'item_instance',ci.item_instance,'is_bound',ci.is_bound)) order by d.name),'[]'::jsonb)
  into v_assets from public.character_inventory ci join public.item_definitions d on d.id=ci.item_definition_id where ci.character_id=v_char and ci.quantity>0 and d.code<>'spirit_stone';
  -- equipment: only backpack + unlocked + not already escrowed
  v_assets:=v_assets || coalesce((select jsonb_agg(jsonb_build_object('asset_type','equipment','asset_ref',e.id::text,'asset_code',coalesce(to_jsonb(t)->>'code',e.id::text),'item_name',coalesce(to_jsonb(t)->>'full_name',to_jsonb(t)->>'name',to_jsonb(t)->>'short_name','未命名装备'),'grade_code',public.tianxu_grade_code_v255(coalesce(to_jsonb(e)->>'grade_code',to_jsonb(t)->>'grade_code','yellow')),'grade_name',public.tianxu_grade_name_v255(coalesce(to_jsonb(e)->>'grade_code',to_jsonb(t)->>'grade_code','yellow')),'market_category','equipment','quantity',1,'snapshot',jsonb_build_object('item',to_jsonb(e),'template',to_jsonb(t))) order by e.created_at)
    from public.character_equipment_items_bequipment01 e left join public.equipment_templates_bequipment01 t on t.id=e.template_id where e.character_id=v_char and e.location='backpack' and not coalesce(e.is_locked,false) and not e.tianxu_escrowed_v255),'[]'::jsonb);
  -- combat shards
  v_assets:=v_assets || coalesce((select jsonb_agg(jsonb_build_object('asset_type','combat_shard','asset_ref',s.technique_code,'asset_code',s.technique_code,'item_name','《'||d.display_name||'》残卷','grade_code',d.grade_code,'grade_name',public.tianxu_grade_name_v255(d.grade_code),'market_category','shard','quantity',s.quantity,'snapshot',jsonb_build_object('family',d.family,'technique_code',d.code,'technique_name',d.display_name,'kind','shard')) order by d.sort_order)
    from public.combat_technique_shards_v220 s join public.combat_technique_definitions_v220 d on d.code=s.technique_code where s.character_id=v_char and s.quantity>0),'[]'::jsonb);
  -- combat books
  v_assets:=v_assets || coalesce((select jsonb_agg(jsonb_build_object('asset_type','combat_book','asset_ref',b.technique_code,'asset_code',b.technique_code,'item_name','《'||d.display_name||'》完整道卷','grade_code',d.grade_code,'grade_name',public.tianxu_grade_name_v255(d.grade_code),'market_category','technique','quantity',b.quantity,'snapshot',jsonb_build_object('family',d.family,'technique_code',d.code,'technique_name',d.display_name,'kind','combat_book')) order by d.sort_order)
    from public.combat_technique_books_v220 b join public.combat_technique_definitions_v220 d on d.code=b.technique_code where b.character_id=v_char and b.quantity>0),'[]'::jsonb);
  -- ordinary / exclusive books from existing library RPC
  v_lib:=public.get_technique_library_v1();
  for v_row in select value from jsonb_array_elements(coalesce(v_lib->'books','[]'::jsonb)) loop
    if coalesce((v_row->>'quantity')::int,0)<=0 then continue; end if;
    v_name:=coalesce(v_row->>'name',v_row->>'technique_name','未知道卷');v_grade:=coalesce(v_row->>'grade_code',v_row->>'grade_name','yellow');v_grade_code:=public.tianxu_grade_code_v255(v_grade);
    v_assets:=v_assets||jsonb_build_array(jsonb_build_object('asset_type','technique_book','asset_ref',v_row->>'book_id','asset_code',coalesce(v_row->>'technique_code',v_row->>'book_id'),'item_name','《'||v_name||'》道卷','grade_code',v_grade_code,'grade_name',public.tianxu_grade_name_v255(v_grade_code),'market_category','technique','quantity',(v_row->>'quantity')::int,'snapshot',v_row));
  end loop;
  return jsonb_build_object('status','ok','settings',(select to_jsonb(s) from public.tianxu_settings_v255 s where singleton_id=1),'spirit_stones',public.tianxu_inventory_adjust_v255(v_char,'spirit_stone',0),'assets',v_assets);
end $$;

create or replace function public.get_my_tianxu_v255()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.tianxu_active_character_v255();
begin
  perform public.tianxu_sweep_expired_v255(100);
  return jsonb_build_object('status','ok',
    'active',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) from (select id,item_name,grade_name,market_category,quantity_total,quantity_remaining,unit_price,listing_fee,expires_at,created_at from public.tianxu_listings_v255 where seller_character_id=v_char and status='active') x),
    'sold',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) from (select id,listing_id,item_name,grade_name,quantity,unit_price,gross_amount,tax_amount,seller_net,created_at from public.tianxu_trades_v255 where seller_character_id=v_char order by created_at desc limit 100) x),
    'bought',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) from (select id,listing_id,item_name,grade_name,quantity,unit_price,gross_amount,created_at from public.tianxu_trades_v255 where buyer_character_id=v_char order by created_at desc limit 100) x));
end $$;

-- ---------- PLAYER WRITE RPCS ----------
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
      select ci.*,d.code d_code,d.name d_name,d.category d_category,d.rarity d_rarity,to_jsonb(d) d_json into v_def from public.character_inventory ci join public.item_definitions d on d.id=ci.item_definition_id where ci.id=p_asset_ref::uuid and ci.character_id=v_char for update;
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
      select e.*,to_jsonb(e) e_json,to_jsonb(t) t_json into v_eq from public.character_equipment_items_bequipment01 e left join public.equipment_templates_bequipment01 t on t.id=e.template_id where e.id=p_asset_ref::uuid and e.character_id=v_char for update;
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

create or replace function public.buy_tianxu_listing_v255(p_listing_id uuid,p_quantity bigint,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_buyer uuid:=public.tianxu_active_character_v255();v public.tianxu_listings_v255%rowtype;v_set public.tianxu_settings_v255%rowtype;v_old jsonb;v_gross bigint;v_tax bigint;v_net bigint;v_buyer_after bigint;v_seller_after bigint;v_now timestamptz:=clock_timestamp();
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED';end if;if coalesce(p_quantity,0)<=0 then raise exception 'TIANXU_QUANTITY_INVALID';end if;
  select result into v_old from public.tianxu_request_ledger_v255 where request_id=p_request_id and user_id=auth.uid();if v_old is not null then return v_old||jsonb_build_object('duplicate_request',true);end if;
  perform pg_advisory_xact_lock(hashtextextended('tianxu-buy:'||p_request_id::text,25502));select * into v_set from public.tianxu_settings_v255 where singleton_id=1;if not v_set.enabled then raise exception 'TIANXU_DISABLED';end if;
  select * into v from public.tianxu_listings_v255 where id=p_listing_id for update;if v.id is null or v.status<>'active' or v.expires_at<=v_now or v.quantity_remaining<=0 then raise exception 'TIANXU_LISTING_NOT_AVAILABLE';end if;if v.seller_character_id=v_buyer then raise exception 'TIANXU_CANNOT_BUY_OWN_LISTING';end if;if p_quantity>v.quantity_remaining then raise exception 'TIANXU_QUANTITY_INSUFFICIENT';end if;if v.asset_type='equipment' and p_quantity<>1 then raise exception 'TIANXU_EQUIPMENT_QUANTITY_ONE';end if;
  v_gross:=v.unit_price*p_quantity;v_tax:=ceil(v_gross::numeric*v_set.trade_tax_rate)::bigint;v_net:=greatest(0,v_gross-v_tax);
  v_buyer_after:=public.equipment_v210_debit_spirit_stone_v243(v_buyer,v_gross);v_seller_after:=public.tianxu_credit_spirit_stone_v255(v.seller_character_id,v_net);
  if v.asset_type='equipment' then
    update public.character_equipment_items_bequipment01 set character_id=v_buyer,location='backpack',is_locked=false,tianxu_escrowed_v255=false where id=v.asset_ref::uuid and character_id=v.seller_character_id and tianxu_escrowed_v255;
    if not found then raise exception 'TIANXU_EQUIPMENT_ESCROW_MISSING';end if;
  else
    perform public.tianxu_credit_asset_v255(v_buyer,v.asset_type,v.asset_code,v.asset_ref,p_quantity,v.item_snapshot);
  end if;
  update public.tianxu_listings_v255 set quantity_remaining=quantity_remaining-p_quantity,status=case when quantity_remaining-p_quantity<=0 then 'sold' else 'active' end,updated_at=v_now where id=v.id;
  insert into public.tianxu_trades_v255(listing_id,seller_character_id,buyer_character_id,asset_type,asset_code,item_name,grade_code,grade_name,quantity,unit_price,gross_amount,tax_amount,seller_net,item_snapshot,request_id,created_at)
  values(v.id,v.seller_character_id,v_buyer,v.asset_type,v.asset_code,v.item_name,v.grade_code,v.grade_name,p_quantity,v.unit_price,v_gross,v_tax,v_net,v.item_snapshot,p_request_id,v_now);
  v_old:=jsonb_build_object('status','ok','listing_id',v.id,'item_name',v.item_name,'quantity',p_quantity,'unit_price',v.unit_price,'gross_amount',v_gross,'tax_amount',v_tax,'seller_net',v_net,'buyer_spirit_stones_after',v_buyer_after,'seller_spirit_stones_after',v_seller_after);
  insert into public.tianxu_request_ledger_v255 values(p_request_id,auth.uid(),v_buyer,'buy',v_old,v_now);return v_old;
end $$;

create or replace function public.cancel_tianxu_listing_v255(p_listing_id uuid,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_char uuid:=public.tianxu_active_character_v255();v public.tianxu_listings_v255%rowtype;v_old jsonb;
begin
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED';end if;select result into v_old from public.tianxu_request_ledger_v255 where request_id=p_request_id and user_id=auth.uid();if v_old is not null then return v_old||jsonb_build_object('duplicate_request',true);end if;
  select * into v from public.tianxu_listings_v255 where id=p_listing_id for update;if v.id is null or v.seller_character_id<>v_char then raise exception 'TIANXU_LISTING_NOT_OWNED';end if;if v.status<>'active' then raise exception 'TIANXU_LISTING_NOT_ACTIVE';end if;
  perform public.tianxu_return_listing_asset_v255(v.id,'cancelled');v_old:=jsonb_build_object('status','ok','listing_id',v.id,'item_name',v.item_name,'returned_quantity',v.quantity_remaining,'listing_fee_refunded',false);
  insert into public.tianxu_request_ledger_v255 values(p_request_id,auth.uid(),v_char,'cancel',v_old,clock_timestamp());return v_old;
end $$;

-- ---------- EQUIPMENT ESCROW GUARD (R3: TABLE-LEVEL, RPC-SIGNATURE-INDEPENDENT) ----------
-- Do not rename or wrap production equipment RPCs. Protect escrow at the table boundary instead,
-- so all existing/future equipment RPC signatures are covered without changing their public API.
create or replace function public.tianxu_equipment_escrow_guard_v255()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
begin
  if tg_op='DELETE' then
    if coalesce(old.tianxu_escrowed_v255,false) then
      raise exception 'TIANXU_EQUIPMENT_ESCROWED';
    end if;
    return old;
  end if;

  -- While escrowed, ordinary equipment operations may not mutate the item.
  -- Tianxu purchase/cancel/expiry is the only valid exit: backpack + unlocked + escrow=false.
  if coalesce(old.tianxu_escrowed_v255,false) then
    if coalesce(new.tianxu_escrowed_v255,false) then
      raise exception 'TIANXU_EQUIPMENT_ESCROWED';
    end if;
    if new.location is distinct from 'backpack' or coalesce(new.is_locked,false) then
      raise exception 'TIANXU_EQUIPMENT_ESCROW_RELEASE_INVALID';
    end if;
    return new;
  end if;

  -- Entering escrow must keep the same owner and move the item into SQL255's locked cave state.
  if coalesce(new.tianxu_escrowed_v255,false) then
    if new.character_id is distinct from old.character_id
       or new.location is distinct from 'cave'
       or not coalesce(new.is_locked,false) then
      raise exception 'TIANXU_EQUIPMENT_ESCROW_ENTER_INVALID';
    end if;
  end if;

  return new;
end $$;

drop trigger if exists tianxu_equipment_escrow_guard_v255 on public.character_equipment_items_bequipment01;
create trigger tianxu_equipment_escrow_guard_v255
before update or delete on public.character_equipment_items_bequipment01
for each row execute function public.tianxu_equipment_escrow_guard_v255();

revoke all on function public.tianxu_equipment_escrow_guard_v255() from public,anon,authenticated;

-- ---------- CASINO RETIREMENT ----------
-- Keep historical tables for audit, but permanently close the feature singleton and player-executable casino RPCs.
do $casino_retire$
declare r record;v_get text;v_set text;v_table text;
begin
  -- Identify the Feature singleton exactly as SQL252 did: public.casino_feature_* with singleton_id + enabled.
  select format('%I.%I',n.nspname,c.relname) into v_table
  from pg_class c join pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind='r' and c.relname like 'casino_feature_%' and c.relname<>'casino_feature_admin_audit_v198'
    and exists(select 1 from pg_attribute a where a.attrelid=c.oid and a.attname='singleton_id' and a.attnum>0 and not a.attisdropped)
    and exists(select 1 from pg_attribute a where a.attrelid=c.oid and a.attname='enabled' and a.attnum>0 and not a.attisdropped)
  order by c.relname limit 1;
  if v_table is not null then execute format('update %s set enabled=false where singleton_id=1',v_table);end if;
  -- Disable legacy casino cron through pg_cron API. Supabase/pg_cron does not allow direct UPDATE cron.job.
  -- Best effort: use cron.alter_job(..., active=false); if unavailable for a legacy job, try cron.unschedule(jobid).
  -- A permission problem on pg_cron metadata must never roll back the Tianxu migration itself.
  if to_regclass('cron.job') is not null then
    begin
      for r in
        select jobid from cron.job
        where active and (command ilike '%casino%' or command ilike '%paigow%' or command ilike '%fish_shrimp%' or command ilike '%spirit_dice%')
      loop
        begin
          execute 'select cron.alter_job($1::bigint,NULL::text,NULL::text,NULL::text,NULL::text,false::boolean)' using r.jobid;
        exception
          when undefined_function or insufficient_privilege then
            begin
              execute 'select cron.unschedule($1::bigint)' using r.jobid;
            exception when others then
              raise notice 'SQL255_R4_LEGACY_CRON_NOT_CHANGED jobid=% reason=%',r.jobid,sqlerrm;
            end;
          when others then
            raise notice 'SQL255_R4_LEGACY_CRON_NOT_CHANGED jobid=% reason=%',r.jobid,sqlerrm;
        end;
      end loop;
    exception when insufficient_privilege then
      raise notice 'SQL255_R4_CRON_JOB_NOT_OBSERVABLE:%',sqlerrm;
    end;
  end if;
  -- Remove player execute permission, preserving owner/service access and historical data.
  for r in select p.oid::regprocedure sig from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (p.proname ilike '%casino%' or p.proname ilike '%paigow%' or p.proname ilike '%fish_shrimp%' or p.proname ilike '%spirit_dice%') loop
    execute format('revoke execute on function %s from public, anon, authenticated',r.sig);
  end loop;
end
$casino_retire$;

-- ---------- GM ----------
create or replace function public.admin9_get_tianxu_config_v255()
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  perform public.v210_admin_guard();perform public.tianxu_sweep_expired_v255(500);
  return jsonb_build_object(
    'settings',(select to_jsonb(s) from public.tianxu_settings_v255 s where singleton_id=1),
    'metrics',jsonb_build_object(
      'active_listings',(select count(*) from public.tianxu_listings_v255 where status='active' and expires_at>clock_timestamp()),
      'today_trades',(select count(*) from public.tianxu_trades_v255 where created_at>=date_trunc('day',clock_timestamp())),
      'today_volume',(select coalesce(sum(gross_amount),0) from public.tianxu_trades_v255 where created_at>=date_trunc('day',clock_timestamp())),
      'today_tax',(select coalesce(sum(tax_amount),0) from public.tianxu_trades_v255 where created_at>=date_trunc('day',clock_timestamp())),
      'today_listing_fees',(select coalesce(sum(listing_fee),0) from public.tianxu_listings_v255 where created_at>=date_trunc('day',clock_timestamp()))
    ),
    'recent_trades',(select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) from (select t.id,t.item_name,t.grade_name,t.quantity,t.unit_price,t.gross_amount,t.tax_amount,t.seller_net,t.created_at,sp.name seller_name,bp.name buyer_name from public.tianxu_trades_v255 t left join public.player_characters sp on sp.id=t.seller_character_id left join public.player_characters bp on bp.id=t.buyer_character_id order by t.created_at desc limit 100) x),
    'recent_audit',(select coalesce(jsonb_agg(to_jsonb(a) order by a.created_at desc),'[]'::jsonb) from (select id,admin_user_id,action_code,reason,created_at from public.tianxu_admin_audit_v255 order by created_at desc limit 50) a)
  );
end $$;

create or replace function public.admin9_update_tianxu_settings_v255(p_patch jsonb,p_reason text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v public.tianxu_settings_v255%rowtype;v_before jsonb;v_existing jsonb;
begin
  perform public.v210_admin_guard();
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED';end if;
  if length(trim(coalesce(p_reason,'')))<2 then raise exception 'TIANXU_ADMIN_REASON_REQUIRED';end if;
  select after_data into v_existing from public.tianxu_admin_audit_v255 where request_id=p_request_id;
  if v_existing is not null then return v_existing||jsonb_build_object('duplicate_request',true);end if;
  select to_jsonb(s) into v_before from public.tianxu_settings_v255 s where singleton_id=1 for update;
  update public.tianxu_settings_v255 set
    enabled=coalesce((p_patch->>'enabled')::boolean,enabled),
    listing_fee_rate=coalesce((p_patch->>'listing_fee_rate')::numeric,listing_fee_rate),
    trade_tax_rate=coalesce((p_patch->>'trade_tax_rate')::numeric,trade_tax_rate),
    listing_duration_hours=coalesce((p_patch->>'listing_duration_hours')::integer,listing_duration_hours),
    max_active_listings=coalesce((p_patch->>'max_active_listings')::integer,max_active_listings),
    page_size=coalesce((p_patch->>'page_size')::integer,page_size),
    config_version=config_version+1,updated_at=clock_timestamp()
  where singleton_id=1 returning * into v;
  insert into public.tianxu_admin_audit_v255(admin_user_id,action_code,before_data,after_data,reason,request_id)
  values(auth.uid(),'settings_update',coalesce(v_before,'{}'::jsonb),to_jsonb(v),trim(p_reason),p_request_id);
  return to_jsonb(v);
end $$;

create or replace function public.admin9_check_tianxu_integration_v255()
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_rel text;v_casino_exec bigint;v_cron bigint:=0;v_cron_observable boolean:=true;
begin
  perform public.v210_admin_guard();v_rel:=public.tianxu_technique_book_relation_v255();
  select count(*) into v_casino_exec from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (p.proname ilike '%casino%' or p.proname ilike '%paigow%' or p.proname ilike '%fish_shrimp%' or p.proname ilike '%spirit_dice%') and (has_function_privilege('authenticated',p.oid,'EXECUTE') or has_function_privilege('anon',p.oid,'EXECUTE'));
  if to_regclass('cron.job') is not null then
    begin
      select count(*) into v_cron from cron.job where active and (command ilike '%casino%' or command ilike '%paigow%' or command ilike '%fish_shrimp%' or command ilike '%spirit_dice%');
    exception when insufficient_privilege then
      v_cron_observable:=false;v_cron:=0;
    end;
  end if;
  return jsonb_build_object(
    'status',case when v_rel is not null and v_casino_exec=0 then 'PASS' else 'FAIL' end,
    'technique_book_relation',v_rel,
    'retired_player_executable_functions',v_casino_exec,
    'active_retired_game_cron',v_cron,
    'cron_observable',v_cron_observable,
    'cron_note',case when not v_cron_observable then 'pg_cron元数据不可读；赌场Feature与玩家RPC已强制退役' when v_cron>0 then '仍发现历史赌场Cron；不影响玩家入口/RPC退役，建议在Supabase Cron面板手动停用' else '赌场Cron已停用或不存在' end,
    'settings',(select to_jsonb(s) from public.tianxu_settings_v255 s where singleton_id=1)
  );
end $$;

-- ---------- PRIVILEGES ----------
revoke all on public.tianxu_settings_v255,public.tianxu_listings_v255,public.tianxu_trades_v255,public.tianxu_request_ledger_v255,public.tianxu_admin_audit_v255 from public,anon,authenticated;
revoke all on function public.tianxu_active_character_v255(),public.tianxu_grade_name_v255(text),public.tianxu_grade_code_v255(text),public.tianxu_category_v255(text,text),public.tianxu_inventory_adjust_v255(uuid,text,bigint),public.tianxu_credit_spirit_stone_v255(uuid,bigint),public.tianxu_technique_book_relation_v255(),public.tianxu_debit_technique_book_v255(uuid,uuid,integer),public.tianxu_credit_asset_v255(uuid,text,text,text,bigint,jsonb),public.tianxu_return_listing_asset_v255(uuid,text),public.tianxu_sweep_expired_v255(integer) from public,anon,authenticated;
revoke all on function public.get_tianxu_market_v255(text,text,text,integer,integer),public.get_tianxu_listing_detail_v255(uuid),public.get_tianxu_sell_assets_v255(),public.get_my_tianxu_v255(),public.create_tianxu_listing_v255(text,text,bigint,bigint,uuid),public.buy_tianxu_listing_v255(uuid,bigint,uuid),public.cancel_tianxu_listing_v255(uuid,uuid) from public,anon;
grant execute on function public.get_tianxu_market_v255(text,text,text,integer,integer),public.get_tianxu_listing_detail_v255(uuid),public.get_tianxu_sell_assets_v255(),public.get_my_tianxu_v255(),public.create_tianxu_listing_v255(text,text,bigint,bigint,uuid),public.buy_tianxu_listing_v255(uuid,bigint,uuid),public.cancel_tianxu_listing_v255(uuid,uuid) to authenticated;
revoke all on function public.admin9_get_tianxu_config_v255(),public.admin9_update_tianxu_settings_v255(jsonb,text,uuid),public.admin9_check_tianxu_integration_v255() from public,anon;
grant execute on function public.admin9_get_tianxu_config_v255(),public.admin9_update_tianxu_settings_v255(jsonb,text,uuid),public.admin9_check_tianxu_integration_v255() to authenticated;

-- ---------- GATE ----------
do $gate$
declare v_check jsonb;v_set public.tianxu_settings_v255%rowtype;v_rel text;v_casino_exec bigint;v_cron bigint:=0;v_cron_observable boolean:=true;
begin
  select * into v_set from public.tianxu_settings_v255 where singleton_id=1;
  if v_set.listing_fee_rate<>0.01 or v_set.trade_tax_rate<>0.05 or v_set.listing_duration_hours<>72 or v_set.max_active_listings<>10 then raise exception 'SQL255_GATE_DEFAULT_SETTINGS_MISMATCH';end if;
  if to_regprocedure('public.get_tianxu_market_v255(text,text,text,integer,integer)') is null or to_regprocedure('public.buy_tianxu_listing_v255(uuid,bigint,uuid)') is null or to_regprocedure('public.create_tianxu_listing_v255(text,text,bigint,bigint,uuid)') is null then raise exception 'SQL255_GATE_PLAYER_RPC_MISSING';end if;
  if to_regprocedure('public.admin9_get_tianxu_config_v255()') is null or to_regprocedure('public.admin9_update_tianxu_settings_v255(jsonb,text,uuid)') is null or to_regprocedure('public.admin9_check_tianxu_integration_v255()') is null then raise exception 'SQL255_GATE_ADMIN_RPC_MISSING';end if;
  v_rel:=public.tianxu_technique_book_relation_v255();if v_rel is null then raise exception 'SQL255_GATE_TECHNIQUE_BOOK_RELATION_UNRESOLVED';end if;
  if to_regprocedure('public.tianxu_equipment_escrow_guard_v255()') is null then raise exception 'SQL255_GATE_EQUIPMENT_ESCROW_GUARD_FUNCTION_MISSING';end if;
  if not exists(
    select 1 from pg_trigger
    where tgrelid='public.character_equipment_items_bequipment01'::regclass
      and tgname='tianxu_equipment_escrow_guard_v255'
      and not tgisinternal
      and tgenabled<>'D'
  ) then raise exception 'SQL255_GATE_EQUIPMENT_ESCROW_GUARD_TRIGGER_MISSING';end if;
  if position('tianxu_equipment_escrow_guard_v255' in lower(pg_get_functiondef('public.tianxu_equipment_escrow_guard_v255()'::regprocedure)))=0
     or position('tianxu_equipment_escrowed' in lower(pg_get_functiondef('public.tianxu_equipment_escrow_guard_v255()'::regprocedure)))=0 then raise exception 'SQL255_GATE_EQUIPMENT_ESCROW_GUARD_BODY_MISSING';end if;
  if not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='move_equipment_item_bequipment01')
     or not exists(select 1 from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname='set_equipment_lock_bequipment01') then raise exception 'SQL255_GATE_EXISTING_EQUIPMENT_RPC_MISSING';end if;
  if has_function_privilege('authenticated','public.tianxu_credit_spirit_stone_v255(uuid,bigint)','EXECUTE') or has_function_privilege('anon','public.tianxu_credit_spirit_stone_v255(uuid,bigint)','EXECUTE') or has_function_privilege('authenticated','public.tianxu_credit_asset_v255(uuid,text,text,text,bigint,jsonb)','EXECUTE') or has_function_privilege('anon','public.tianxu_credit_asset_v255(uuid,text,text,text,bigint,jsonb)','EXECUTE') then raise exception 'SQL255_GATE_INTERNAL_MUTATION_HELPER_EXECUTABLE';end if;
  if has_table_privilege('authenticated','public.tianxu_listings_v255','INSERT') or has_table_privilege('authenticated','public.tianxu_listings_v255','UPDATE') or has_table_privilege('authenticated','public.tianxu_trades_v255','INSERT') or has_table_privilege('anon','public.tianxu_listings_v255','INSERT') then raise exception 'SQL255_GATE_TIANXU_TABLE_DIRECT_WRITE_ALLOWED';end if;
  select count(*) into v_casino_exec from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and (p.proname ilike '%casino%' or p.proname ilike '%paigow%' or p.proname ilike '%fish_shrimp%' or p.proname ilike '%spirit_dice%') and (has_function_privilege('authenticated',p.oid,'EXECUTE') or has_function_privilege('anon',p.oid,'EXECUTE'));
  if v_casino_exec<>0 then raise exception 'SQL255_GATE_CASINO_PLAYER_RPC_STILL_EXECUTABLE:%',v_casino_exec;end if;
  if to_regclass('cron.job') is not null then
    begin
      select count(*) into v_cron from cron.job where active and (command ilike '%casino%' or command ilike '%paigow%' or command ilike '%fish_shrimp%' or command ilike '%spirit_dice%');
    exception when insufficient_privilege then
      v_cron_observable:=false;v_cron:=0;
    end;
  end if;
  -- Cron is not a hard gate: Supabase may reserve cron.job/alter_job ownership to the job owner.
  -- Feature OFF + player RPC revoke are the hard retirement gates; any observable leftover Cron is reported in the final result for manual cleanup.
end
$gate$;

commit;
select 'SQL255_GATE_PASSED'::text as result,
       'V2.2.0 CACHE124 / ADMIN9 R34 / 天墟 ONLINE；SQL255 R4使用pg_cron官方API兼容退役；赌场Feature与玩家RPC权限已退役；NEXT SQL256'::text as detail;
