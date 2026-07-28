-- 九霄问道 V0.15.3 FIX1 CACHE21
-- 修复：新五槽值 ordinary_1..ordinary_5 被旧 equipped_slot CHECK 约束拒绝；
-- 同时统一功法读取为普通五槽、灵石升级、圆满规则。

begin;

-- 1. 品级兼容：历史凡品/未知普通功法按黄品处理。
create or replace function public.technique_grade_rules_v0152(p_grade text)
returns table(max_level integer,cost_factor numeric,redeem_rating integer)
language sql immutable set search_path=public,pg_temp as $$
  select x.max_level, x.cost_factor, x.redeem_rating
  from (values
    ('exclusive',36,1.00::numeric,1000),
    ('immortal',30,0.95::numeric,800),
    ('heaven',24,0.90::numeric,600),
    ('earth',18,0.85::numeric,400),
    ('mystic',12,0.80::numeric,200),
    ('yellow',6,0.75::numeric,100)
  ) x(grade,max_level,cost_factor,redeem_rating)
  where x.grade = case
    when p_grade in ('exclusive','immortal','heaven','earth','mystic','yellow') then p_grade
    else 'yellow'
  end
$$;
revoke all on function public.technique_grade_rules_v0152(text) from public,anon,authenticated;

-- 2. 解除旧主修/辅修约束，并兼容新五槽。
alter table public.character_techniques
  drop constraint if exists character_techniques_equipped_slot_check;

alter table public.character_techniques
  add constraint character_techniques_equipped_slot_check
  check (
    equipped_slot is null
    or equipped_slot in (
      'main','support_1','support_2',
      'ordinary_1','ordinary_2','ordinary_3','ordinary_4','ordinary_5'
    )
  );

-- 已迁移的新槽位统一写回 ordinary_N；slot_type 不再承载新槽位，避免旧 slot_type 约束冲突。
update public.character_techniques
set equipped_slot = 'ordinary_' || v0152_slot_index::text,
    slot_type = null,
    is_equipped = true,
    updated_at = now()
where v0152_slot_index between 1 and 5;

-- 3. 重建五槽装备RPC：明确选槽、先结算旧配置、再立即启用新配置。
create or replace function public.set_technique_slot_v2(
  p_character_technique_id uuid,
  p_target_slot text
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  u uuid := auth.uid();
  c public.player_characters%rowtype;
  ct public.character_techniques%rowtype;
  t public.techniques%rowtype;
  v_slot integer;
  v_open integer;
  v_slot_multiplier numeric;
begin
  if u is null then raise exception 'AUTH_REQUIRED'; end if;

  select * into c
  from public.player_characters
  where user_id=u and status in ('active','secluded','missing')
  order by created_at desc
  limit 1
  for update;

  if c.id is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;

  -- 先结算旧配置。
  perform public.claim_cultivation_v1();

  select * into ct
  from public.character_techniques
  where id=p_character_technique_id and character_id=c.id
  for update;

  if ct.id is null then raise exception 'TECHNIQUE_NOT_FOUND'; end if;

  select * into t from public.techniques where id=ct.technique_id;

  if p_target_slot is null or p_target_slot='' or p_target_slot='none' then
    update public.character_techniques
    set v0152_slot_index=null,
        is_equipped=false,
        equipped_slot=null,
        slot_type=null,
        updated_at=now()
    where id=ct.id;

    perform public.refresh_opportunity_technique_effects_v1(c.id);

    return jsonb_build_object(
      'success',true,
      'equipped',false,
      'technique_name',t.name
    );
  end if;

  v_slot := case p_target_slot
    when 'ordinary_1' then 1
    when 'ordinary_2' then 2
    when 'ordinary_3' then 3
    when 'ordinary_4' then 4
    when 'ordinary_5' then 5
    -- 兼容旧客户端，只映射已有旧槽。
    when 'main' then 1
    when 'support_1' then 2
    when 'support_2' then 3
    else null
  end;

  if v_slot is null then raise exception 'INVALID_TECHNIQUE_SLOT'; end if;

  v_open := public.character_open_ordinary_slots_v0152(c.id);
  if v_open < 1 then raise exception 'MORTAL_CANNOT_USE_TECHNIQUE'; end if;
  if v_slot > v_open then raise exception 'TECHNIQUE_SLOT_REALM_LOCKED'; end if;

  -- 同槽只保留一门功法，被替换功法退回已学习列表。
  update public.character_techniques
  set v0152_slot_index=null,
      is_equipped=false,
      equipped_slot=null,
      slot_type=null,
      updated_at=now()
  where character_id=c.id
    and v0152_slot_index=v_slot
    and id<>ct.id;

  update public.character_techniques
  set v0152_slot_index=v_slot,
      is_equipped=true,
      equipped_slot='ordinary_' || v_slot::text,
      slot_type=null,
      updated_at=now()
  where id=ct.id;

  perform public.refresh_opportunity_technique_effects_v1(c.id);

  v_slot_multiplier := case v_slot
    when 1 then 1.0
    when 2 then 0.6
    when 3 then 0.5
    when 4 then 0.4
    else 0.3
  end;

  return jsonb_build_object(
    'success',true,
    'equipped',true,
    'equipped_slot','ordinary_' || v_slot::text,
    'technique_name',t.name,
    'slot_multiplier',v_slot_multiplier
  );
end
$$;
revoke all on function public.set_technique_slot_v2(uuid,text) from public,anon;
grant execute on function public.set_technique_slot_v2(uuid,text) to authenticated;

-- 4. 重建普通功法读取RPC，停止返回旧主修/辅修、熟练度和传承点规则。
create or replace function public.get_technique_system_v2()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  u uuid := auth.uid();
  c public.player_characters%rowtype;
  v_open integer;
  v_techniques jsonb;
  v_slots jsonb;
begin
  if u is null then raise exception 'AUTH_REQUIRED'; end if;

  select * into c
  from public.player_characters
  where user_id=u and status in ('active','secluded','missing')
  order by created_at desc
  limit 1;

  if c.id is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;

  v_open := public.character_open_ordinary_slots_v0152(c.id);

  select coalesce(
    jsonb_agg(to_jsonb(x) order by x.grade_sort desc,x.name),
    '[]'::jsonb
  )
  into v_techniques
  from (
    select
      ct.id as character_technique_id,
      t.id as technique_id,
      t.code,
      t.name,
      'ordinary'::text as category,
      '普通功法'::text as category_name,
      case
        when t.grade in ('immortal','heaven','earth','mystic','yellow') then t.grade
        else 'yellow'
      end as grade_code,
      case
        when t.grade='immortal' then '仙品'
        when t.grade='heaven' then '天品'
        when t.grade='earth' then '地品'
        when t.grade='mystic' then '玄品'
        else '黄品'
      end as grade_name,
      case
        when t.grade='immortal' then 6
        when t.grade='heaven' then 5
        when t.grade='earth' then 4
        when t.grade='mystic' then 3
        else 2
      end as grade_sort,
      t.grade as raw_grade,
      t.description,
      coalesce(t.fixed_effects,'{}'::jsonb) as fixed_effects,
      least(greatest(1,coalesce(ct.level,1)),rules.max_level) as level,
      rules.max_level,
      coalesce(ct.is_mastered,false) as is_mastered,
      case
        when ct.v0152_slot_index between 1 and 5
          then 'ordinary_' || ct.v0152_slot_index::text
        else null
      end as equipped_slot,
      ct.v0152_slot_index as slot_index,
      case ct.v0152_slot_index
        when 1 then 1.0::numeric
        when 2 then 0.6::numeric
        when 3 then 0.5::numeric
        when 4 then 0.4::numeric
        when 5 then 0.3::numeric
        else 0::numeric
      end as slot_multiplier,
      coalesce(ct.acquisition_count,1) as acquisition_count,
      0::integer as proficiency,
      0::integer as mastery_points,
      0::integer as progress_needed,
      (v_open > 0 and not coalesce(ct.is_mastered,false)) as can_upgrade,
      (ct.level >= rules.max_level and not coalesce(ct.is_mastered,false)) as can_master,
      case
        when coalesce(ct.is_mastered,false) then 0
        when ct.level < rules.max_level
          then public.technique_upgrade_cost_v0152(
            case when t.grade in ('immortal','heaven','earth','mystic','yellow') then t.grade else 'yellow' end,
            greatest(1,ct.level)
          )
        else public.technique_mastery_cost_v0152(
          case when t.grade in ('immortal','heaven','earth','mystic','yellow') then t.grade else 'yellow' end
        )
      end as upgrade_cost
    from public.character_techniques ct
    join public.techniques t on t.id=ct.technique_id
    cross join lateral public.technique_grade_rules_v0152(
      case when t.grade in ('immortal','heaven','earth','mystic','yellow') then t.grade else 'yellow' end
    ) rules
    where ct.character_id=c.id
      and coalesce(t.is_active,true)
  ) x;

  select jsonb_build_object(
    'ordinary_1', max(case when ct.v0152_slot_index=1 then ct.id::text end),
    'ordinary_2', max(case when ct.v0152_slot_index=2 then ct.id::text end),
    'ordinary_3', max(case when ct.v0152_slot_index=3 then ct.id::text end),
    'ordinary_4', max(case when ct.v0152_slot_index=4 then ct.id::text end),
    'ordinary_5', max(case when ct.v0152_slot_index=5 then ct.id::text end)
  )
  into v_slots
  from public.character_techniques ct
  where ct.character_id=c.id;

  return jsonb_build_object(
    'status','ok',
    'character_id',c.id,
    'open_ordinary_slots',v_open,
    'spirit_stones',c.spirit_stones,
    'slots',coalesce(v_slots,'{}'::jsonb),
    'techniques',coalesce(v_techniques,'[]'::jsonb),
    'combinations','[]'::jsonb
  );
end
$$;
revoke all on function public.get_technique_system_v2() from public,anon;
grant execute on function public.get_technique_system_v2() to authenticated;


-- 5. 提升缓存纪元，强制客户端取得修正后的功法界面。
update public.jiuxiao_app_release_control
set release_name='V0.15.3 FIX1 CACHE21',
    cache_epoch=greatest(cache_epoch,21),
    notice_text='V0.15.3 FIX1：修复普通功法五槽数据库约束与旧主修/辅修界面。',
    updated_at=now()
where singleton_id=1;

insert into public.jiuxiao_app_release_control(singleton_id,release_name,cache_epoch,notice_text,updated_at)
select 1,'V0.15.3 FIX1 CACHE21',21,
       'V0.15.3 FIX1：修复普通功法五槽数据库约束与旧主修/辅修界面。',now()
where not exists (
  select 1 from public.jiuxiao_app_release_control where singleton_id=1
);

commit;
