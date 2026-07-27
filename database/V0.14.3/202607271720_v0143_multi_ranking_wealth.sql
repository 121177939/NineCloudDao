-- 九霄问道 Web Alpha V0.14.3 CACHE7
-- 天命榜升级为三榜切换：修为榜、财富榜、战力榜占位。
-- 本迁移只新增财富榜只读RPC并提升客户端cache_epoch，不修改角色资产与任何结算规则。
-- 执行前提：V0.14.1统一灵石体系、V0.14.2九霄界闻排序均已部署。

begin;

-- 财富榜：按唯一统一灵石余额从高到低排序。
-- 同额时按大境界、小境界、修为、角色创建时间和角色ID稳定排序。
create or replace function public.get_wealth_ranking_v1(
  p_limit integer default 50,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path = pg_catalog, public, auth, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_total integer := 0;
  v_entries jsonb := '[]'::jsonb;
begin
  if v_user_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  if p_limit is null or p_limit < 1 or p_limit > 100
     or p_offset is null or p_offset < 0 then
    raise exception 'INVALID_RANKING_PAGE';
  end if;

  select count(*)::integer
  into v_total
  from public.player_characters pc
  where pc.status in ('active', 'secluded', 'missing');

  with ranked as (
    select
      row_number() over (
        order by
          coalesce(stones.wealth, 0) desc,
          r.major_order desc,
          rs.minor_level desc,
          pc.cultivation desc,
          pc.created_at asc,
          pc.id asc
      )::integer as rank,
      pc.user_id,
      pc.name,
      pc.generation_number,
      pc.cultivation,
      coalesce(stones.wealth, 0)::bigint as wealth,
      case
        when r.code = 'mortal' then coalesce(rs.stage_name, r.name, '凡人')
        else concat(r.name, case when rs.stage_name is null or rs.stage_name = '' then '' else ' · ' || rs.stage_name end)
      end as realm_label,
      coalesce(fate.fate_name, '未定命格') as fate_name
    from public.player_characters pc
    join public.realm_stages rs on rs.id = pc.realm_stage_id
    join public.realms r on r.id = rs.realm_id
    left join lateral (
      select coalesce(sum(greatest(ci.quantity, 0)), 0)::bigint as wealth
      from public.character_inventory ci
      where ci.character_id = pc.id
        and ci.item_definition_id = public.spirit_stone_item_id_v0141()
    ) stones on true
    left join lateral (
      select f.name as fate_name
      from public.character_fates cf
      join public.fates f on f.id = cf.fate_id
      where cf.character_id = pc.id
        and cf.is_active
      order by cf.created_at asc, cf.fate_id asc
      limit 1
    ) fate on true
    where pc.status in ('active', 'secluded', 'missing')
  ), page_rows as (
    select *
    from ranked
    where rank > p_offset
      and rank <= p_offset + p_limit
    order by rank asc
  )
  select coalesce(
    jsonb_agg(
      jsonb_build_object(
        'rank', rank,
        'name', name,
        'realm', realm_label,
        'fate', fate_name,
        'generation', generation_number,
        'cultivation', cultivation,
        'wealth', wealth,
        'is_self', user_id = v_user_id
      )
      order by rank asc
    ),
    '[]'::jsonb
  )
  into v_entries
  from page_rows;

  return jsonb_build_object(
    'status', 'ok',
    'board_type', 'wealth',
    'ranking_rule', '统一灵石余额由高到低；同额时按境界、小境界、修为与创建时间排序',
    'entries', v_entries,
    'total_count', v_total,
    'offset', p_offset,
    'limit', p_limit,
    'has_more', p_offset + jsonb_array_length(v_entries) < v_total
  );
end;
$$;

revoke all on function public.get_wealth_ranking_v1(integer, integer) from public, anon, authenticated;
grant execute on function public.get_wealth_ranking_v1(integer, integer) to authenticated;

comment on function public.get_wealth_ranking_v1(integer, integer) is
  'V0.14.3财富榜只读RPC：按唯一统一灵石余额排序，不返回账号、用户ID、角色ID、道统ID或会话信息。';

-- CACHE7：已安装更新守卫的旧客户端将在服务器版本号提升后自动清缓存重载。
do $$
begin
  if to_regclass('public.jiuxiao_app_release_control') is not null then
    update public.jiuxiao_app_release_control
    set
      cache_epoch = greatest(cache_epoch, 7),
      release_name = 'V0.14.3 CACHE7',
      notice_text = '榜单系统已更新，正在重新加载。',
      updated_at = now()
    where singleton_id = 1;
  end if;
end
$$;

notify pgrst, 'reload schema';

commit;

-- 自检：全部ok应为true。
select 'wealth_ranking_rpc_exists'::text as check_name,
       to_regprocedure('public.get_wealth_ranking_v1(integer,integer)') is not null as ok,
       '财富榜RPC存在'::text as detail
union all
select 'wealth_ranking_authenticated_execute',
       has_function_privilege('authenticated', 'public.get_wealth_ranking_v1(integer,integer)', 'execute'),
       'authenticated可以读取财富榜'
union all
select 'wealth_ranking_anon_denied',
       not has_function_privilege('anon', 'public.get_wealth_ranking_v1(integer,integer)', 'execute'),
       'anon不能读取财富榜'
union all
select 'wealth_ranking_security_definer',
       (select prosecdef from pg_proc where oid = 'public.get_wealth_ranking_v1(integer,integer)'::regprocedure),
       '财富榜使用安全定义者权限'
union all
select 'wealth_ranking_stable',
       (select provolatile = 's' from pg_proc where oid = 'public.get_wealth_ranking_v1(integer,integer)'::regprocedure),
       '财富榜为只读STABLE函数'
union all
select 'spirit_stone_balance_source_ready',
       to_regprocedure('public.spirit_stone_item_id_v0141()') is not null,
       '唯一统一灵石物品ID函数存在'
union all
select 'ranking_source_tables_ready',
       to_regclass('public.player_characters') is not null
       and to_regclass('public.realm_stages') is not null
       and to_regclass('public.realms') is not null
       and to_regclass('public.character_inventory') is not null,
       '榜单来源表存在'
union all
select 'release_cache_epoch_7',
       case
         when to_regclass('public.jiuxiao_app_release_control') is null then false
         else coalesce((select cache_epoch >= 7 from public.jiuxiao_app_release_control where singleton_id = 1), false)
       end,
       '客户端缓存版本已提升到CACHE7';
