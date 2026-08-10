-- 九霄问道 V2.2.0 / SQL256 R2
-- 天墟“我要出售”可上架资产读取修复。
-- 前提：SQL255 已成功 ONLINE。
-- 修复点：
-- 1) 不再依赖装备表 created_at 排序字段；
-- 2) 各资产来源独立容错，某一来源异常不再导致整个出售页变成空白；
-- 3) 保留现有 RPC 名称，CACHE126 无需重新发布；
-- 4) 返回 source_counts / source_warnings 供后续诊断，旧客户端会安全忽略额外字段。

begin;

do $precheck$
begin
  if to_regclass('public.tianxu_settings_v255') is null
     or to_regprocedure('public.get_tianxu_sell_assets_v255()') is null then
    raise exception 'SQL256_PRECHECK_SQL255_NOT_ONLINE';
  end if;
  if to_regclass('public.character_inventory') is null
     or to_regclass('public.item_definitions') is null then
    raise exception 'SQL256_PRECHECK_INVENTORY_MISSING';
  end if;
  if to_regclass('public.character_equipment_items_bequipment01') is null
     or to_regclass('public.equipment_templates_bequipment01') is null then
    raise exception 'SQL256_PRECHECK_EQUIPMENT_MISSING';
  end if;
  if to_regclass('public.combat_technique_shards_v220') is null
     or to_regclass('public.combat_technique_books_v220') is null
     or to_regclass('public.combat_technique_definitions_v220') is null then
    raise exception 'SQL256_PRECHECK_COMBAT_TECHNIQUE_ASSET_MISSING';
  end if;
  if to_regprocedure('public.get_technique_library_v1()') is null then
    raise exception 'SQL256_PRECHECK_TECHNIQUE_LIBRARY_MISSING';
  end if;
end
$precheck$;

create or replace function public.get_tianxu_sell_assets_v255()
returns jsonb
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_char uuid:=public.tianxu_active_character_v255();
  v_assets jsonb:='[]'::jsonb;
  v_piece jsonb:='[]'::jsonb;
  v_warnings jsonb:='[]'::jsonb;
  v_counts jsonb:='{}'::jsonb;
  v_lib jsonb;
  v_row jsonb;
  v_name text;
  v_grade text;
  v_grade_code text;
begin
  perform public.tianxu_sweep_expired_v255(50);

  -- ① 通用储物：丹药 / 材料 / 其他 item_definitions 资产；灵石本身不能挂牌。
  begin
    select coalesce(jsonb_agg(to_jsonb(x) order by x.item_name, x.asset_ref),'[]'::jsonb)
      into v_piece
    from (
      select
        'inventory'::text as asset_type,
        ci.id::text as asset_ref,
        d.code::text as asset_code,
        d.name::text as item_name,
        public.tianxu_grade_code_v255(d.rarity::text) as grade_code,
        public.tianxu_grade_name_v255(d.rarity::text) as grade_name,
        public.tianxu_category_v255(d.category::text,d.name) as market_category,
        ci.quantity::bigint as quantity,
        jsonb_build_object(
          'definition',to_jsonb(d),
          'item_instance',ci.item_instance,
          'is_bound',ci.is_bound
        ) as snapshot
      from public.character_inventory ci
      join public.item_definitions d on d.id=ci.item_definition_id
      where ci.character_id=v_char
        and ci.quantity>0
        and d.code<>'spirit_stone'
    ) x;
    v_assets:=v_assets||v_piece;
    v_counts:=v_counts||jsonb_build_object('inventory',jsonb_array_length(v_piece));
  exception when others then
    v_warnings:=v_warnings||jsonb_build_array(jsonb_build_object('source','inventory','error',sqlerrm));
    v_counts:=v_counts||jsonb_build_object('inventory',0);
  end;

  -- ② 装备：只列背包、未锁定、未处于天墟托管的唯一装备。
  -- 装备排序不依赖任何可选取得时间字段，统一使用稳定的 item_name/id 排序。
  begin
    select coalesce(jsonb_agg(to_jsonb(x) order by x.item_name, x.asset_ref),'[]'::jsonb)
      into v_piece
    from (
      select
        'equipment'::text as asset_type,
        e.id::text as asset_ref,
        coalesce(to_jsonb(t)->>'code',e.id::text) as asset_code,
        coalesce(
          to_jsonb(t)->>'full_name',
          to_jsonb(t)->>'name',
          to_jsonb(t)->>'short_name',
          '未命名装备'
        ) as item_name,
        public.tianxu_grade_code_v255(
          coalesce(to_jsonb(e)->>'grade_code',to_jsonb(t)->>'grade_code','yellow')
        ) as grade_code,
        public.tianxu_grade_name_v255(
          coalesce(to_jsonb(e)->>'grade_code',to_jsonb(t)->>'grade_code','yellow')
        ) as grade_name,
        'equipment'::text as market_category,
        1::bigint as quantity,
        jsonb_build_object('item',to_jsonb(e),'template',to_jsonb(t)) as snapshot
      from public.character_equipment_items_bequipment01 e
      left join public.equipment_templates_bequipment01 t
        on t.id=(to_jsonb(e)->>'template_id')::uuid
      where e.character_id=v_char
        and coalesce(to_jsonb(e)->>'location','')='backpack'
        and not coalesce((to_jsonb(e)->>'is_locked')::boolean,false)
        and not coalesce((to_jsonb(e)->>'tianxu_escrowed_v255')::boolean,false)
    ) x;
    v_assets:=v_assets||v_piece;
    v_counts:=v_counts||jsonb_build_object('equipment',jsonb_array_length(v_piece));
  exception when others then
    v_warnings:=v_warnings||jsonb_build_array(jsonb_build_object('source','equipment','error',sqlerrm));
    v_counts:=v_counts||jsonb_build_object('equipment',0);
  end;

  -- ③ 攻伐 / 护体功法残卷。
  begin
    select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order, x.item_name),'[]'::jsonb)
      into v_piece
    from (
      select
        'combat_shard'::text as asset_type,
        s.technique_code::text as asset_ref,
        s.technique_code::text as asset_code,
        ('《'||d.display_name||'》残卷')::text as item_name,
        d.grade_code::text as grade_code,
        public.tianxu_grade_name_v255(d.grade_code) as grade_name,
        'shard'::text as market_category,
        s.quantity::bigint as quantity,
        d.sort_order,
        jsonb_build_object(
          'family',d.family,
          'technique_code',d.code,
          'technique_name',d.display_name,
          'kind','shard'
        ) as snapshot
      from public.combat_technique_shards_v220 s
      join public.combat_technique_definitions_v220 d on d.code=s.technique_code
      where s.character_id=v_char and s.quantity>0
    ) x;
    v_assets:=v_assets||v_piece;
    v_counts:=v_counts||jsonb_build_object('combat_shard',jsonb_array_length(v_piece));
  exception when others then
    v_warnings:=v_warnings||jsonb_build_array(jsonb_build_object('source','combat_shard','error',sqlerrm));
    v_counts:=v_counts||jsonb_build_object('combat_shard',0);
  end;

  -- ④ 攻伐 / 护体完整道卷。
  begin
    select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order, x.item_name),'[]'::jsonb)
      into v_piece
    from (
      select
        'combat_book'::text as asset_type,
        b.technique_code::text as asset_ref,
        b.technique_code::text as asset_code,
        ('《'||d.display_name||'》完整道卷')::text as item_name,
        d.grade_code::text as grade_code,
        public.tianxu_grade_name_v255(d.grade_code) as grade_name,
        'technique'::text as market_category,
        b.quantity::bigint as quantity,
        d.sort_order,
        jsonb_build_object(
          'family',d.family,
          'technique_code',d.code,
          'technique_name',d.display_name,
          'kind','combat_book'
        ) as snapshot
      from public.combat_technique_books_v220 b
      join public.combat_technique_definitions_v220 d on d.code=b.technique_code
      where b.character_id=v_char and b.quantity>0
    ) x;
    v_assets:=v_assets||v_piece;
    v_counts:=v_counts||jsonb_build_object('combat_book',jsonb_array_length(v_piece));
  exception when others then
    v_warnings:=v_warnings||jsonb_build_array(jsonb_build_object('source','combat_book','error',sqlerrm));
    v_counts:=v_counts||jsonb_build_object('combat_book',0);
  end;

  -- ⑤ 现有修炼 / 专属功法完整道卷。
  -- 此来源单独容错，避免藏经架结构变化把装备、丹药、材料等全部拖成空白。
  begin
    v_piece:='[]'::jsonb;
    v_lib:=public.get_technique_library_v1();
    for v_row in
      select value from jsonb_array_elements(coalesce(v_lib->'books','[]'::jsonb))
    loop
      if coalesce((v_row->>'quantity')::int,0)<=0 then continue; end if;
      v_name:=coalesce(v_row->>'name',v_row->>'technique_name','未知道卷');
      v_grade:=coalesce(v_row->>'grade_code',v_row->>'grade_name','yellow');
      v_grade_code:=public.tianxu_grade_code_v255(v_grade);
      v_piece:=v_piece||jsonb_build_array(jsonb_build_object(
        'asset_type','technique_book',
        'asset_ref',v_row->>'book_id',
        'asset_code',coalesce(v_row->>'technique_code',v_row->>'book_id'),
        'item_name','《'||v_name||'》道卷',
        'grade_code',v_grade_code,
        'grade_name',public.tianxu_grade_name_v255(v_grade_code),
        'market_category','technique',
        'quantity',(v_row->>'quantity')::int,
        'snapshot',v_row
      ));
    end loop;
    v_assets:=v_assets||v_piece;
    v_counts:=v_counts||jsonb_build_object('technique_book',jsonb_array_length(v_piece));
  exception when others then
    v_warnings:=v_warnings||jsonb_build_array(jsonb_build_object('source','technique_book','error',sqlerrm));
    v_counts:=v_counts||jsonb_build_object('technique_book',0);
  end;

  return jsonb_build_object(
    'status','ok',
    'settings',(select to_jsonb(s) from public.tianxu_settings_v255 s where singleton_id=1),
    'spirit_stones',public.tianxu_inventory_adjust_v255(v_char,'spirit_stone',0),
    'assets',v_assets,
    'source_counts',v_counts,
    'source_warnings',v_warnings,
    'patch','SQL256_SELL_ASSET_SOURCE_ISOLATION'
  );
end
$fn$;

revoke all on function public.get_tianxu_sell_assets_v255() from public,anon;
grant execute on function public.get_tianxu_sell_assets_v255() to authenticated;

-- 静态/结构门禁：实际执行各来源的“全局空查询”，确保 SQL 中引用的稳定结构可被数据库解析。
do $gate$
declare
  v_def text;
  v_dummy bigint;
begin
  select pg_get_functiondef('public.get_tianxu_sell_assets_v255()'::regprocedure) into v_def;
  -- 只检查可执行函数体中的脆弱字段引用；当前定义不再包含旧取得时间字段。
  if position('created_at' in lower(v_def))>0 then
    raise exception 'SQL256_GATE_FRAGILE_EQUIPMENT_TIME_FIELD_STILL_PRESENT';
  end if;
  if position('source_warnings' in lower(v_def))=0
     or position('combat_shard' in lower(v_def))=0
     or position('technique_book' in lower(v_def))=0 then
    raise exception 'SQL256_GATE_SOURCE_ISOLATION_MISSING';
  end if;

  select count(*) into v_dummy
  from public.character_inventory ci
  join public.item_definitions d on d.id=ci.item_definition_id
  where false;

  select count(*) into v_dummy
  from public.character_equipment_items_bequipment01 e
  left join public.equipment_templates_bequipment01 t
    on t.id=(to_jsonb(e)->>'template_id')::uuid
  where false;

  select count(*) into v_dummy
  from public.combat_technique_shards_v220 s
  join public.combat_technique_definitions_v220 d on d.code=s.technique_code
  where false;

  select count(*) into v_dummy
  from public.combat_technique_books_v220 b
  join public.combat_technique_definitions_v220 d on d.code=b.technique_code
  where false;
end
$gate$;

commit;

select jsonb_build_object(
  'sql',256,
  'gate','SQL256_GATE_PASSED',
  'patch','TIANXU_SELL_ASSET_SOURCE_ISOLATION_R2',
  'client','CACHE126无需重发',
  'next_sql',257
) as sql256_install_result;
