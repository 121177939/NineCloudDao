-- 九霄问道 V0.15.3 FIX2 CACHE22
-- 修复功法RPC错误读取 player_characters.spirit_stones。
-- 实际灵石账户自V0.14.1起位于 character_inventory，并由统一灵石函数管理。

begin;

do $$
begin
  if to_regprocedure('public.spirit_stone_balance_v0141(uuid)') is null then
    raise exception 'MISSING_REQUIRED_FUNCTION: spirit_stone_balance_v0141(uuid)';
  end if;
  if to_regprocedure('public.spirit_stone_debit_v0141(uuid,bigint,text)') is null then
    raise exception 'MISSING_REQUIRED_FUNCTION: spirit_stone_debit_v0141(uuid,bigint,text)';
  end if;
  if to_regprocedure('public.award_spirit_stones_v3(uuid,bigint)') is null then
    raise exception 'MISSING_REQUIRED_FUNCTION: award_spirit_stones_v3(uuid,bigint)';
  end if;
end
$$;

create or replace function public.upgrade_technique_v2(p_character_technique_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare u uuid:=auth.uid();c public.player_characters%rowtype;ct public.character_techniques%rowtype;t public.techniques%rowtype;r record;v_cost bigint;v_remaining bigint;v_master boolean:=false;
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 select * into c from public.player_characters where user_id=u and status in('active','secluded','missing') order by created_at desc limit 1 for update;
 if c.id is null then raise exception 'NO_ACTIVE_CHARACTER';end if;
 if public.character_open_ordinary_slots_v0152(c.id)<1 then raise exception 'MORTAL_CANNOT_STUDY_TECHNIQUE';end if;
 perform public.claim_cultivation_v1();
 select * into ct from public.character_techniques where id=p_character_technique_id and character_id=c.id for update;
 if ct.id is null then raise exception 'TECHNIQUE_NOT_FOUND';end if;
 select * into t from public.techniques where id=ct.technique_id;select * into r from public.technique_grade_rules_v0152(t.grade);
 if ct.is_mastered then raise exception 'TECHNIQUE_ALREADY_MASTERED';end if;
 if ct.level<r.max_level then v_cost:=public.technique_upgrade_cost_v0152(t.grade,ct.level);
 else v_cost:=public.technique_mastery_cost_v0152(t.grade);v_master:=true;end if;
 v_remaining:=public.spirit_stone_debit_v0141(c.id,v_cost,'INSUFFICIENT_SPIRIT_STONES');
 if v_master then update public.character_techniques set is_mastered=true,mastered_at=clock_timestamp(),updated_at=now() where id=ct.id;
 else update public.character_techniques set level=level+1,proficiency=0,mastery_points=0,updated_at=now() where id=ct.id returning * into ct;end if;
 perform public.refresh_opportunity_technique_effects_v1(c.id);
 return jsonb_build_object('success',true,'technique_name',t.name,'level',case when v_master then ct.level else ct.level end,'max_level',r.max_level,'cost',v_cost,'mastered',v_master,'spirit_stones_after',v_remaining);
end$$;
revoke all on function public.upgrade_technique_v2(uuid) from public,anon;grant execute on function public.upgrade_technique_v2(uuid) to authenticated;

create or replace function public.redeem_technique_book_v0152(p_book_id uuid,p_quantity integer default 1,p_request_id uuid default gen_random_uuid())
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare u uuid:=auth.uid();c public.player_characters%rowtype;b public.character_technique_books%rowtype;v_grade text;v_name text;v_unit bigint;v_total bigint;v_remaining bigint;v_result jsonb;
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 select * into c from public.player_characters where user_id=u and status in('active','secluded','missing') order by created_at desc limit 1 for update;
 if c.id is null then raise exception 'NO_ACTIVE_CHARACTER';end if;
 if p_quantity is null or p_quantity<1 then raise exception 'INVALID_REDEEM_QUANTITY';end if;
 select result into v_result from public.technique_operation_requests_v0152 where request_id=p_request_id and character_id=c.id;
 if found then return v_result;end if;
 select * into b from public.character_technique_books where id=p_book_id and character_id=c.id for update;
 if b.id is null or b.quantity<p_quantity then raise exception 'TECHNIQUE_BOOK_INSUFFICIENT';end if;
 if b.book_kind='exclusive' then v_grade:='exclusive';select name into v_name from public.exclusive_technique_definitions where code=b.technique_code;
 else select grade,name into v_grade,v_name from public.techniques where code=b.technique_code and is_active limit 1;end if;
 v_unit:=public.technique_redeem_value_v0152(v_grade);v_total:=v_unit*p_quantity;
 update public.character_technique_books set quantity=quantity-p_quantity,updated_at=now() where id=b.id;
 delete from public.character_technique_books where id=b.id and quantity<=0;
 perform public.award_spirit_stones_v3(c.id,v_total);
 v_remaining:=public.spirit_stone_balance_v0141(c.id);
 v_result:=jsonb_build_object('success',true,'technique_name',coalesce(v_name,b.technique_code),'quantity',p_quantity,'unit_value',v_unit,'spirit_stones_gained',v_total,'spirit_stones_after',v_remaining);
 insert into public.technique_operation_requests_v0152(request_id,character_id,operation,result) values(p_request_id,c.id,'redeem_book',v_result);
 return v_result;
end$$;
revoke all on function public.redeem_technique_book_v0152(uuid,integer,uuid) from public,anon;grant execute on function public.redeem_technique_book_v0152(uuid,integer,uuid) to authenticated;

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
    'spirit_stones',public.spirit_stone_balance_v0141(c.id),
    'slots',coalesce(v_slots,'{}'::jsonb),
    'techniques',coalesce(v_techniques,'[]'::jsonb),
    'combinations','[]'::jsonb
  );
end
$$;
revoke all on function public.get_technique_system_v2() from public,anon;
grant execute on function public.get_technique_system_v2() to authenticated;

-- 发布门禁：强制客户端刷新到修正版。
update public.jiuxiao_app_release_control
set release_name='V0.15.3 FIX2 CACHE22',
    cache_epoch=greatest(cache_epoch,22),
    notice_text='V0.15.3 FIX2：修复功法系统读取、升级和兑换灵石账户时的字段错误。',
    updated_at=now()
where singleton_id=1;

insert into public.jiuxiao_app_release_control(singleton_id,release_name,cache_epoch,notice_text,updated_at)
select 1,'V0.15.3 FIX2 CACHE22',22,
       'V0.15.3 FIX2：修复功法系统读取、升级和兑换灵石账户时的字段错误。',now()
where not exists (
  select 1 from public.jiuxiao_app_release_control where singleton_id=1
);

notify pgrst, 'reload schema';

commit;
