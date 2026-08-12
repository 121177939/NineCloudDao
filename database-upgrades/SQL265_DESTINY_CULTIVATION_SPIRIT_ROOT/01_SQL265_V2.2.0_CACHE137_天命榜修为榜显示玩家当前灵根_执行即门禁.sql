-- 九霄问道 SQL265 · V2.2.0 CACHE137
-- 功能：天命榜【修为榜】在保留 get_destiny_ranking_v1 原排名结果/排序/分页的前提下，
--       为每名玩家补充当前主灵根 spirit_root_name，并由 CACHE137 客户端显示。
-- 不修改：修为数值、排名规则、命格、财富榜、战力榜、战斗、经济、天道人物或 AI 权限边界。
-- 基线：SQL264 R3 必须已成功并看到 SQL264_GATE_PASSED。
-- 成功后：SQL265_GATE_PASSED / NEXT SQL266。

begin;

do $precheck$
declare
  v_old oid;
  v_result text;
begin
  if to_regclass('public.player_characters') is null then raise exception 'SQL265_PRECHECK_PLAYER_CHARACTERS_MISSING'; end if;
  if to_regclass('public.character_spirit_roots') is null then raise exception 'SQL265_PRECHECK_CHARACTER_SPIRIT_ROOTS_MISSING'; end if;
  if to_regclass('public.spirit_roots') is null then raise exception 'SQL265_PRECHECK_SPIRIT_ROOTS_MISSING'; end if;
  if to_regclass('public.heaven_balance_control_v264') is null
     or to_regprocedure('public.sync_tiandao_companion_cultivation_v264(uuid,boolean,uuid)') is null then
    raise exception 'SQL265_PRECHECK_SQL264_R3_REQUIRED_RUN_SQL264_R3_FIRST';
  end if;

  select p.oid into v_old
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public' and p.proname='get_destiny_ranking_v1' and p.pronargs=2
  order by p.oid desc limit 1;
  if v_old is null then raise exception 'SQL265_PRECHECK_DESTINY_RANKING_V1_MISSING'; end if;
  select pg_get_function_result(v_old) into v_result;
  if v_result <> 'jsonb' then raise exception 'SQL265_PRECHECK_DESTINY_RANKING_V1_RETURN_UNSUPPORTED:%',v_result; end if;

  if exists (
    select 1 from unnest(array['id','name','generation_number','cultivation']) r(col)
    where not exists(select 1 from information_schema.columns c where c.table_schema='public' and c.table_name='player_characters' and c.column_name=r.col)
  ) then raise exception 'SQL265_PRECHECK_PLAYER_CHARACTER_COLUMNS_MISSING'; end if;
  if exists (
    select 1 from unnest(array['character_id','spirit_root_id','is_primary','awakened_year']) r(col)
    where not exists(select 1 from information_schema.columns c where c.table_schema='public' and c.table_name='character_spirit_roots' and c.column_name=r.col)
  ) then raise exception 'SQL265_PRECHECK_CHARACTER_SPIRIT_ROOT_COLUMNS_MISSING'; end if;
  if exists (
    select 1 from unnest(array['id','code','name','rarity']) r(col)
    where not exists(select 1 from information_schema.columns c where c.table_schema='public' and c.table_name='spirit_roots' and c.column_name=r.col)
  ) then raise exception 'SQL265_PRECHECK_SPIRIT_ROOT_COLUMNS_MISSING'; end if;
end
$precheck$;

create or replace function public.get_destiny_ranking_v265(p_limit integer default 50,p_offset integer default 0)
returns jsonb
language plpgsql
security definer
set search_path=''
as $$
declare
  v_limit integer:=greatest(1,least(100,coalesce(p_limit,50)));
  v_offset integer:=greatest(0,coalesce(p_offset,0));
  v_base jsonb;
  v_entries jsonb;
begin
  -- 原榜单仍是唯一排名权威；本函数只补展示字段，不重新排序。
  select public.get_destiny_ranking_v1(v_limit,v_offset) into v_base;
  if v_base is null then return jsonb_build_object('status','unavailable','entries','[]'::jsonb,'error','修为榜基础返回为空。'); end if;
  if jsonb_typeof(v_base)<>'object' then raise exception 'SQL265_DESTINY_RANKING_V1_RESULT_NOT_OBJECT'; end if;
  if jsonb_typeof(v_base->'entries') is distinct from 'array' then
    return v_base || jsonb_build_object('spirit_root_included',true,'sql_revision','SQL265');
  end if;

  select coalesce(jsonb_agg(
    e.entry || jsonb_build_object(
      'spirit_root_name',coalesce(root_info.root_name,'未测灵根'),
      'spirit_root_code',coalesce(root_info.root_code,''),
      'spirit_root_rarity',coalesce(root_info.root_rarity,'')
    ) order by e.ord
  ),'[]'::jsonb)
  into v_entries
  from jsonb_array_elements(v_base->'entries') with ordinality as e(entry,ord)
  left join lateral (
    select sr.name as root_name,sr.code as root_code,sr.rarity as root_rarity
    from public.player_characters pc
    join public.character_spirit_roots csr on csr.character_id=pc.id and csr.is_primary=true
    join public.spirit_roots sr on sr.id=csr.spirit_root_id
    where
      pc.id::text=coalesce(e.entry->>'character_id','')
      or (
        pc.name=coalesce(e.entry->>'name','')
        and pc.generation_number::text=coalesce(e.entry->>'generation','')
        and pc.cultivation::text=coalesce(e.entry->>'cultivation','')
      )
    order by
      case when pc.id::text=coalesce(e.entry->>'character_id','') then 0 else 1 end,
      csr.awakened_year desc nulls last,
      sr.name asc
    limit 1
  ) root_info on true;

  v_base:=jsonb_set(v_base,'{entries}',v_entries,true);
  return v_base || jsonb_build_object('spirit_root_included',true,'sql_revision','SQL265');
end $$;

comment on function public.get_destiny_ranking_v265(integer,integer)
is 'SQL265 CACHE137：复用 get_destiny_ranking_v1 原修为榜权威结果，仅为 entries 补充玩家当前主灵根；不重新计算或改变排名。';

revoke all on function public.get_destiny_ranking_v265(integer,integer) from public,anon,authenticated;
grant execute on function public.get_destiny_ranking_v265(integer,integer) to authenticated;

do $gate$
declare
  v_def text;
  v_exposed integer;
begin
  if to_regprocedure('public.get_destiny_ranking_v265(integer,integer)') is null then raise exception 'SQL265_GATE_RPC_MISSING'; end if;
  if not has_function_privilege('authenticated','public.get_destiny_ranking_v265(integer,integer)','EXECUTE') then raise exception 'SQL265_GATE_AUTH_EXECUTE_MISSING'; end if;
  select count(*) into v_exposed
  from information_schema.routine_privileges
  where specific_schema='public' and routine_name='get_destiny_ranking_v265'
    and grantee in('anon','PUBLIC') and privilege_type='EXECUTE';
  if v_exposed<>0 then raise exception 'SQL265_GATE_RPC_EXPOSED:%',v_exposed; end if;

  select pg_get_functiondef(to_regprocedure('public.get_destiny_ranking_v265(integer,integer)')) into v_def;
  if position('get_destiny_ranking_v1' in v_def)=0 then raise exception 'SQL265_GATE_ORIGINAL_RANKING_NOT_REUSED'; end if;
  if position('character_spirit_roots' in v_def)=0 or position('spirit_roots' in v_def)=0 then raise exception 'SQL265_GATE_SPIRIT_ROOT_JOIN_MISSING'; end if;
  if position('spirit_root_name' in v_def)=0 then raise exception 'SQL265_GATE_SPIRIT_ROOT_FIELD_MISSING'; end if;
end
$gate$;

commit;

select jsonb_build_object(
  'sql',265,
  'gate','SQL265_GATE_PASSED',
  'release','V2.2.0 CACHE137',
  'feature','天命榜修为榜显示玩家当前主灵根',
  'ranking_authority','get_destiny_ranking_v1 unchanged / SQL265 enrich only',
  'gm','ADMIN9 R40 unchanged',
  'edge','tiandao-ai CACHE135 R6 unchanged',
  'next_sql',266
) as sql265_install_result;
