-- 九霄问道 V0.14.6 CACHE10
-- 正式修复：
-- 1. 机缘V4临时修炼效果允许 source_type='opportunity_v4'；
-- 2. 机缘结果与结算批次外键改为事务结束时校验；
-- 3. 命书读取最近100条完整机缘结果，不再仅依赖高品级 history_logs；
-- 4. 修炼-机缘前端可显示 result_text 的具体结算内容；
-- 5. 更新缓存纪元为10。
-- 本脚本可重复执行，不修改既有玩家修为、境界、灵石或机缘结果。

begin;

do $$
begin
  if to_regclass('public.player_characters') is null then
    raise exception 'V0146_REQUIRED_TABLE_MISSING: player_characters';
  end if;
  if to_regclass('public.character_cultivation_effects') is null then
    raise exception 'V0146_REQUIRED_TABLE_MISSING: character_cultivation_effects';
  end if;
  if to_regclass('public.opportunity_v3_results') is null then
    raise exception 'V0146_REQUIRED_TABLE_MISSING: opportunity_v3_results';
  end if;
  if to_regclass('public.opportunity_v4_settlement_batches') is null then
    raise exception 'V0146_REQUIRED_TABLE_MISSING: opportunity_v4_settlement_batches';
  end if;
  if to_regclass('public.game_worlds') is null then
    raise exception 'V0146_REQUIRED_TABLE_MISSING: game_worlds';
  end if;
end
$$;

-- 兼容修复一：旧检查约束未放行机缘V4效果来源。
do $$
declare
  v_constraint_name text := 'character_cultivation_effects_source_type_check';
  v_constraint_def text;
  v_expression text;
begin
  select pg_get_constraintdef(c.oid, true)
    into v_constraint_def
  from pg_constraint c
  join pg_class t on t.oid=c.conrelid
  join pg_namespace n on n.oid=t.relnamespace
  where n.nspname='public'
    and t.relname='character_cultivation_effects'
    and c.conname=v_constraint_name
    and c.contype='c';

  if v_constraint_def is null then
    raise exception 'V0146_CONSTRAINT_MISSING: %',v_constraint_name;
  end if;

  if position('opportunity_v4' in v_constraint_def)=0 then
    v_expression:=regexp_replace(v_constraint_def,'^CHECK[[:space:]]*\((.*)\)$','\1','n');
    if v_expression is null or v_expression=v_constraint_def or btrim(v_expression)='' then
      raise exception 'V0146_CONSTRAINT_PARSE_FAILED: %',v_constraint_def;
    end if;
    execute format('alter table public.character_cultivation_effects drop constraint %I',v_constraint_name);
    execute format(
      'alter table public.character_cultivation_effects add constraint %I check ((%s) or source_type=%L)',
      v_constraint_name,v_expression,'opportunity_v4'
    );
  end if;
end
$$;

comment on constraint character_cultivation_effects_source_type_check
on public.character_cultivation_effects
is 'V0.14.6：保留历史来源类型，并允许机缘V4临时修炼效果 opportunity_v4。';

-- 兼容修复二：逐条结果先写、汇总批次后写，外键必须延迟至事务结束校验。
do $$
declare
  v_constraint_name text := 'opportunity_v3_results_settlement_batch_id_fkey';
  v_type "char";
  v_target regclass;
begin
  select c.contype,c.confrelid::regclass
    into v_type,v_target
  from pg_constraint c
  where c.conrelid='public.opportunity_v3_results'::regclass
    and c.conname=v_constraint_name;

  if v_type is null then raise exception 'V0146_CONSTRAINT_MISSING: %',v_constraint_name; end if;
  if v_type<>'f' then raise exception 'V0146_NOT_FOREIGN_KEY: %',v_constraint_name; end if;
  if v_target<>'public.opportunity_v4_settlement_batches'::regclass then
    raise exception 'V0146_UNEXPECTED_TARGET: % -> %',v_constraint_name,v_target;
  end if;

  execute format(
    'alter table public.opportunity_v3_results alter constraint %I deferrable initially deferred',
    v_constraint_name
  );
end
$$;

comment on constraint opportunity_v3_results_settlement_batch_id_fkey
on public.opportunity_v3_results
is 'V0.14.6：机缘V4先记录逐条结果、后写汇总批次；外键于事务结束时校验。';

-- 正式命书机缘明细接口：仅返回当前登录账号现役角色的数据。
create or replace function public.get_opportunity_history_v0146(
  p_limit integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=auth.uid();
  v_character_id uuid;
  v_world_year integer:=1;
  v_limit integer:=greatest(1,least(100,coalesce(p_limit,100)));
  v_entries jsonb:='[]'::jsonb;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED'; end if;

  select pc.id,coalesce(gw.current_year,greatest(1,pc.birth_year+pc.age))
    into v_character_id,v_world_year
  from public.player_characters pc
  left join public.game_worlds gw on gw.id=pc.world_id
  where pc.user_id=v_user_id
    and pc.status in('active','secluded','missing')
  order by pc.created_at desc
  limit 1;

  if v_character_id is null then
    return jsonb_build_object('status','no_character','entries','[]'::jsonb);
  end if;

  select coalesce(jsonb_agg(x.entry order by x.event_at desc),'[]'::jsonb)
    into v_entries
  from (
    select
      coalesce(r.scheduled_at,r.created_at) as event_at,
      jsonb_build_object(
        'id',r.id,
        'world_year',v_world_year,
        'event_type','opportunity',
        'title','机缘·'||coalesce(nullif(r.result_data->>'title',''),'无名机缘'),
        'content',
          coalesce(nullif(r.result_data->>'story',''),'天机流转，道痕已留。')
          ||'【'||case when r.path_key in('auspicious','positive') then '趋吉所得' else '涉险结果' end||'】'
          ||coalesce(
              nullif(case when r.path_key in('auspicious','positive') then r.reward_text else r.penalty_text end,''),
              '本次机缘已完成结算。'
            ),
        'importance',case r.rarity when '专属' then 5 when '仙品' then 5 when '天品' then 4 when '地品' then 3 when '玄品' then 2 else 1 end,
        'created_at',coalesce(r.scheduled_at,r.created_at),
        'source_type','opportunity_result',
        'rarity',r.rarity,
        'path_name',case when r.path_key in('auspicious','positive') then '趋吉' else '涉险' end
      ) as entry
    from public.opportunity_v3_results r
    where r.character_id=v_character_id
    order by coalesce(r.scheduled_at,r.created_at) desc
    limit v_limit
  ) x;

  return jsonb_build_object('status','ok','entries',v_entries);
end
$$;

revoke all on function public.get_opportunity_history_v0146(integer) from public,anon;
grant execute on function public.get_opportunity_history_v0146(integer) to authenticated;

comment on function public.get_opportunity_history_v0146(integer)
is 'V0.14.6：返回当前登录角色最近100条完整机缘结果，供命书与即时机缘明细展示。';

do $$
begin
  if to_regclass('public.app_release_control') is not null then
    update public.app_release_control
    set release_name='V0.14.6 CACHE10',
        cache_epoch=greatest(cache_epoch,10),
        updated_at=now();
  end if;
end
$$;

commit;

notify pgrst,'reload schema';

-- 验收：全部 passed 必须为 true。
select * from (values
  ('effect_source_constraint',exists(
    select 1 from pg_constraint c
    where c.conrelid='public.character_cultivation_effects'::regclass
      and c.conname='character_cultivation_effects_source_type_check'
      and position('opportunity_v4' in pg_get_constraintdef(c.oid,true))>0
  )),
  ('batch_fk_deferrable',exists(
    select 1 from pg_constraint c
    where c.conrelid='public.opportunity_v3_results'::regclass
      and c.conname='opportunity_v3_results_settlement_batch_id_fkey'
      and c.condeferrable and c.condeferred
  )),
  ('opportunity_history_rpc',to_regprocedure('public.get_opportunity_history_v0146(integer)') is not null),
  ('authenticated_execute',has_function_privilege('authenticated','public.get_opportunity_history_v0146(integer)','execute')),
  ('cache_epoch',case when to_regclass('public.app_release_control') is null then true else exists(
    select 1 from public.app_release_control where cache_epoch>=10
  ) end)
) as checks(check_name,passed);
