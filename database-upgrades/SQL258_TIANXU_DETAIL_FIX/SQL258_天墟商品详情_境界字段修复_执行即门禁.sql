-- 九霄问道 SQL258
-- V2.2.0 CACHE126 / 天墟商品详情境界字段修复
-- 基线：SQL257 已生效（装备可正常上架）
-- 修复：get_tianxu_listing_detail_v255 错误读取 realm_stages.name
-- 正确结构：realms.name + realm_stages.stage_name

begin;

-- ---------- PRECHECK ----------
do $precheck$
begin
  if to_regprocedure('public.get_tianxu_listing_detail_v255(uuid)') is null then
    raise exception 'SQL258_PRECHECK_TIANXU_DETAIL_RPC_MISSING';
  end if;
  if to_regclass('public.realm_stages') is null or to_regclass('public.realms') is null then
    raise exception 'SQL258_PRECHECK_REALM_TABLE_MISSING';
  end if;
  if not exists(
    select 1 from pg_catalog.pg_attribute
    where attrelid=to_regclass('public.realm_stages') and attname='stage_name' and not attisdropped
  ) then
    raise exception 'SQL258_PRECHECK_REALM_STAGE_NAME_MISSING';
  end if;
  if not exists(
    select 1 from pg_catalog.pg_attribute
    where attrelid=to_regclass('public.realm_stages') and attname='realm_id' and not attisdropped
  ) then
    raise exception 'SQL258_PRECHECK_REALM_STAGE_REALM_ID_MISSING';
  end if;
  if not exists(
    select 1 from pg_catalog.pg_attribute
    where attrelid=to_regclass('public.realms') and attname='name' and not attisdropped
  ) then
    raise exception 'SQL258_PRECHECK_REALM_NAME_MISSING';
  end if;
end
$precheck$;

-- ---------- FIX DETAIL RPC ----------
create or replace function public.get_tianxu_listing_detail_v255(p_listing_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=''
as $function$
declare
  v_char uuid:=public.tianxu_active_character_v255();
  v jsonb;
  v_recent bigint;
  v_median numeric;
begin
  perform public.tianxu_sweep_expired_v255(50);

  select jsonb_build_object(
    'id',l.id,
    'asset_type',l.asset_type,
    'asset_code',l.asset_code,
    'item_name',l.item_name,
    'grade_code',l.grade_code,
    'grade_name',l.grade_name,
    'market_category',l.market_category,
    'quantity_remaining',l.quantity_remaining,
    'unit_price',l.unit_price,
    'expires_at',l.expires_at,
    'created_at',l.created_at,
    'seller_character_id',l.seller_character_id,
    'seller_name',coalesce(pc.name,'无名修士'),
    'seller_realm',coalesce(
      nullif(pg_catalog.concat_ws('·',nullif(r.name,''),nullif(rs.stage_name,'')),''),
      ''
    ),
    'is_own',l.seller_character_id=v_char,
    'item_snapshot',l.item_snapshot
  )
  into v
  from public.tianxu_listings_v255 l
  join public.player_characters pc on pc.id=l.seller_character_id
  left join public.realm_stages rs on rs.id=pc.realm_stage_id
  left join public.realms r on r.id=rs.realm_id
  where l.id=p_listing_id
    and l.status='active'
    and l.quantity_remaining>0
    and l.expires_at>clock_timestamp();

  if v is null then
    raise exception 'TIANXU_LISTING_NOT_AVAILABLE';
  end if;

  select unit_price
  into v_recent
  from public.tianxu_trades_v255
  where asset_type=v->>'asset_type'
    and asset_code=v->>'asset_code'
  order by created_at desc
  limit 1;

  select percentile_cont(.5) within group(order by unit_price)
  into v_median
  from public.tianxu_trades_v255
  where asset_type=v->>'asset_type'
    and asset_code=v->>'asset_code'
    and created_at>=clock_timestamp()-interval '7 days';

  return jsonb_build_object(
    'status','ok',
    'listing',v,
    'recent_price',v_recent,
    'median_7d',case when v_median is null then null else round(v_median)::bigint end
  );
end
$function$;

-- ---------- GATE ----------
do $gate$
declare
  v_def text;
begin
  select pg_catalog.pg_get_functiondef('public.get_tianxu_listing_detail_v255(uuid)'::regprocedure)
  into v_def;

  if v_def is null then
    raise exception 'SQL258_GATE_DETAIL_RPC_MISSING';
  end if;
  if position('rs.name' in lower(v_def))>0 then
    raise exception 'SQL258_GATE_BAD_REALM_STAGE_NAME_STILL_PRESENT';
  end if;
  if position('rs.stage_name' in lower(v_def))=0 then
    raise exception 'SQL258_GATE_STAGE_NAME_NOT_USED';
  end if;
  if position('public.realms r' in lower(v_def))=0 then
    raise exception 'SQL258_GATE_REALMS_JOIN_MISSING';
  end if;
  if position('r.name' in lower(v_def))=0 then
    raise exception 'SQL258_GATE_REALM_NAME_NOT_USED';
  end if;
end
$gate$;

commit;

select jsonb_build_object(
  'sql',258,
  'gate','SQL258_GATE_PASSED',
  'patch','TIANXU_LISTING_DETAIL_REALM_SCHEMA_FIX',
  'client','CACHE126无需重发',
  'next_sql',259
) as sql258_install_result;
