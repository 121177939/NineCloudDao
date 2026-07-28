-- 九霄问道 B线：机缘功法改为道卷，洞府藏经架主动研习
-- 规则：
-- 1. 普通主修/辅修机缘只掉落功法书，不自动学习，不自动发首次奖励。
-- 2. 同名功法书按数量堆叠；未学时研习，已学时可参悟为原品级传承点。
-- 3. 五种专属道卷全部可获得并堆叠；只有当前命格对应的本命专属可以研习。
-- 4. 异命专属不回收、不补偿100灵石；本命权重仍按异命+2、本命重置20运行。
-- 5. 研习后不自动装备；普通功法首次研习奖励在真正研习时一次性发放。

begin;
create table if not exists public.character_technique_books(
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.player_characters(id) on delete cascade,
  book_kind text not null check(book_kind in('ordinary','exclusive')),
  technique_code text not null,
  quantity integer not null default 1 check(quantity >= 0),
  first_obtained_at timestamptz not null default clock_timestamp(),
  last_obtained_at timestamptz not null default clock_timestamp(),
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(character_id,book_kind,technique_code)
);
create index if not exists idx_character_technique_books_character
  on public.character_technique_books(character_id,book_kind,updated_at desc);

alter table public.character_technique_books enable row level security;
drop policy if exists character_technique_books_select_own on public.character_technique_books;
create policy character_technique_books_select_own
on public.character_technique_books for select to authenticated
using(exists(
  select 1 from public.player_characters pc
  where pc.id=character_technique_books.character_id and pc.user_id=auth.uid()
));
revoke all on public.character_technique_books from public,anon,authenticated;
grant select on public.character_technique_books to authenticated;

create or replace function public.technique_book_add_v1(
  p_character_id uuid,
  p_book_kind text,
  p_technique_code text,
  p_quantity integer default 1,
  p_obtained_at timestamptz default clock_timestamp(),
  p_metadata jsonb default '{}'::jsonb
) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare v_before integer:=0;v_after integer:=0;v_id uuid;
begin
  if p_character_id is null then raise exception 'CHARACTER_NOT_FOUND';end if;
  if p_book_kind not in('ordinary','exclusive') then raise exception 'INVALID_TECHNIQUE_BOOK_KIND';end if;
  if coalesce(nullif(trim(p_technique_code),''),'')='' then raise exception 'TECHNIQUE_BOOK_CODE_REQUIRED';end if;
  if coalesce(p_quantity,0)<=0 then raise exception 'TECHNIQUE_BOOK_QUANTITY_INVALID';end if;
  select quantity into v_before from public.character_technique_books
   where character_id=p_character_id and book_kind=p_book_kind and technique_code=p_technique_code for update;
  v_before:=coalesce(v_before,0);
  insert into public.character_technique_books(character_id,book_kind,technique_code,quantity,first_obtained_at,last_obtained_at,metadata)
  values(p_character_id,p_book_kind,p_technique_code,p_quantity,coalesce(p_obtained_at,clock_timestamp()),coalesce(p_obtained_at,clock_timestamp()),coalesce(p_metadata,'{}'::jsonb))
  on conflict(character_id,book_kind,technique_code) do update
    set quantity=public.character_technique_books.quantity+excluded.quantity,
        last_obtained_at=excluded.last_obtained_at,
        metadata=public.character_technique_books.metadata||excluded.metadata,
        updated_at=now()
  returning id,quantity into v_id,v_after;
  return jsonb_build_object('book_id',v_id,'quantity_before',v_before,'quantity_added',p_quantity,'quantity_total',v_after,'is_first_copy',v_before=0);
end$$;
revoke all on function public.technique_book_add_v1(uuid,text,text,integer,timestamptz,jsonb) from public,anon,authenticated;

create or replace function public.technique_book_summary_add_v1(p_summary jsonb,p_award jsonb)
returns jsonb language plpgsql immutable set search_path=public,pg_temp as $$
declare v_result jsonb:=coalesce(p_summary,'{}'::jsonb);v_key text;v_old jsonb;v_quantity integer;
begin
  if not coalesce((p_award->>'awarded')::boolean,false) then return v_result;end if;
  v_key:=coalesce(p_award->>'book_kind','ordinary')||':'||coalesce(p_award->>'technique_code','unknown');
  v_old:=coalesce(v_result->v_key,'{}'::jsonb);
  v_quantity:=coalesce((v_old->>'quantity')::integer,0)+greatest(1,coalesce((p_award->>'quantity_added')::integer,1));
  return jsonb_set(v_result,array[v_key],jsonb_build_object(
    'book_kind',coalesce(p_award->>'book_kind','ordinary'),
    'technique_code',p_award->>'technique_code',
    'name',p_award->>'technique_name',
    'grade',p_award->>'grade',
    'category',p_award->>'category',
    'quantity',v_quantity
  ),true);
end$$;
revoke all on function public.technique_book_summary_add_v1(jsonb,jsonb) from public,anon,authenticated;

-- 机缘普通功法奖励改为“功法书×1”，不再调用旧的自动学习函数。
create or replace function public.opportunity_v4_award_ordinary_technique(
  p_character_id uuid,
  p_lineage_id uuid,
  p_world_year integer,
  p_technique_code text,
  p_scheduled_at timestamptz
) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare p record;t record;v_book jsonb;v_category_name text;
begin
  select * into p from public.opportunity_v4_technique_pool where technique_code=p_technique_code and is_active;
  select id,code,name,grade,category into t from public.techniques where code=p_technique_code and is_active limit 1;
  if p.technique_code is null or t.id is null then
    return jsonb_build_object('awarded',false,'reason','TECHNIQUE_POOL_OR_DEFINITION_MISSING','technique_code',p_technique_code);
  end if;
  v_book:=public.technique_book_add_v1(p_character_id,'ordinary',t.code,1,p_scheduled_at,jsonb_build_object('source','opportunity_v4','grade',p.grade,'category',t.category));
  v_category_name:=case when t.category='support' then '辅修' else '主修' end;
  return jsonb_build_object(
    'awarded',true,'is_new_book',coalesce((v_book->>'is_first_copy')::boolean,false),
    'book_kind','ordinary','book_id',v_book->>'book_id','technique_code',t.code,'technique_name',t.name,
    'grade',p.grade,'grade_code',t.grade,'category',t.category,
    'quantity_added',1,'quantity_total',coalesce((v_book->>'quantity_total')::integer,1),
    'mastery_points',0,'permanent_effects','[]'::jsonb,'items','{}'::jsonb,
    'applied',jsonb_build_object('cultivation_gain_requested',0,'cultivation_loss_requested',0,'spirit_gain',0,'spirit_loss',0,'speed_bonus',0,'duration_minutes',0),
    'narrative',p.acquisition_narrative||' 获得'||v_category_name||'功法书《'||t.name||'》×1，已收入洞府藏经架，尚未研习。'
  );
end$$;
revoke all on function public.opportunity_v4_award_ordinary_technique(uuid,uuid,integer,text,timestamptz) from public,anon,authenticated;

-- 普通功法的原有附带奖励移至首次真正研习时执行。
create or replace function public.apply_technique_book_first_rewards_v1(
  p_character_id uuid,p_lineage_id uuid,p_technique_code text,p_applied_at timestamptz default clock_timestamp()
) returns jsonb
language plpgsql security definer set search_path=public,pg_temp as $$
declare
  p record;t record;v_spec jsonb:='{}'::jsonb;v_basis jsonb;v_b numeric:=1;v_s numeric:=100;
  v_cgain bigint:=0;v_sgain bigint:=0;v_sdelta bigint:=0;v_amount numeric:=0;v_cave jsonb;v_items jsonb:='{}'::jsonb;
  v_grant record;v_granted bigint:=0;v_discarded bigint:=0;v_permanent jsonb:='[]'::jsonb;v_text text[]:=array[]::text[];
begin
  select * into p from public.opportunity_v4_technique_pool where technique_code=p_technique_code and is_active;
  select id,code,name,grade,category into t from public.techniques where code=p_technique_code and is_active limit 1;
  if p.technique_code is null or t.id is null then raise exception 'TECHNIQUE_NOT_FOUND';end if;
  v_spec:=coalesce(p.first_reward_spec,'{}'::jsonb);
  v_basis:=public.opportunity_v4_stage_basis(p_character_id);
  v_b:=greatest(1,coalesce((v_basis->>'cultivation_basis')::numeric,1));
  v_s:=greatest(1,coalesce((v_basis->>'spirit_stone_basis')::numeric,100));
  if v_spec ? 'cultivation_gain_fixed' then v_cgain:=v_cgain+greatest(0,(v_spec->>'cultivation_gain_fixed')::bigint);end if;
  if v_spec ? 'cultivation_gain_pct' then v_cgain:=v_cgain+greatest(0,round(v_b*(v_spec->>'cultivation_gain_pct')::numeric)::bigint);end if;
  if v_spec ? 'spirit_gain_fixed' then v_sgain:=v_sgain+greatest(0,(v_spec->>'spirit_gain_fixed')::bigint);end if;
  if v_spec ? 'spirit_gain_mult' then v_sgain:=v_sgain+greatest(0,round(v_s*(v_spec->>'spirit_gain_mult')::numeric)::bigint);end if;
  if v_cgain>0 then
    select * into v_grant from public.grant_cultivation_capped_v1(p_character_id,v_cgain,'technique_book_first_study',jsonb_build_object('technique_code',t.code));
    v_granted:=coalesce(v_grant.granted_amount,0);v_discarded:=coalesce(v_grant.discarded_amount,0);
    v_text:=array_append(v_text,'修为 +'||v_granted::text||case when v_discarded>0 then '（圆满舍弃 '||v_discarded::text||'）' else '' end);
  end if;
  if v_sgain>0 then
    v_sdelta:=greatest(0,public.opportunity_v4_adjust_spirit_stones(p_character_id,v_sgain));
    v_text:=array_append(v_text,'灵石 +'||v_sdelta::text);
  end if;
  if v_spec ? 'permanent_speed_bonus' then
    v_amount:=(v_spec->>'permanent_speed_bonus')::numeric;
    if not exists(select 1 from public.character_cultivation_effects where character_id=p_character_id and source_key='opportunity_v4:first:'||t.code||':multiplier') then
      insert into public.character_cultivation_effects(character_id,source_type,source_key,display_name,flat_rate_per_second,multiplier_bonus,starts_at,expires_at,is_active,metadata)
      values(p_character_id,'opportunity','opportunity_v4:first:'||t.code||':multiplier','功法首次研习·'||t.name,0,v_amount,coalesce(p_applied_at,clock_timestamp()),null,true,jsonb_build_object('kind','technique_first_study_reward','technique_code',t.code,'grade',p.grade));
    end if;
    v_permanent:=v_permanent||jsonb_build_array('《'||t.name||'》首次研习：永久修炼速度+'||trim(to_char(v_amount*100,'FM999990.##'))||'%');
    v_text:=array_append(v_text,'永久修炼速度 +'||trim(to_char(v_amount*100,'FM999990.##'))||'%');
  end if;
  if v_spec ? 'permanent_flat_rate' then
    v_amount:=(v_spec->>'permanent_flat_rate')::numeric;
    if not exists(select 1 from public.character_cultivation_effects where character_id=p_character_id and source_key='opportunity_v4:first:'||t.code||':flat') then
      insert into public.character_cultivation_effects(character_id,source_type,source_key,display_name,flat_rate_per_second,multiplier_bonus,starts_at,expires_at,is_active,metadata)
      values(p_character_id,'opportunity','opportunity_v4:first:'||t.code||':flat','功法首次研习·'||t.name,v_amount,0,coalesce(p_applied_at,clock_timestamp()),null,true,jsonb_build_object('kind','technique_first_study_reward','technique_code',t.code,'grade',p.grade));
    end if;
    v_permanent:=v_permanent||jsonb_build_array('《'||t.name||'》首次研习：永久每秒修为+'||trim(to_char(v_amount,'FM999990.###')));
    v_text:=array_append(v_text,'永久每秒修为 +'||trim(to_char(v_amount,'FM999990.###')));
  end if;
  if v_spec ? 'cave_daily_spirit_mapping' then
    v_cave:=public.award_cave_resource_v3(p_lineage_id,t.code,(v_spec->>'cave_daily_spirit_mapping')::numeric);
    if coalesce((v_cave->>'awarded')::boolean,false) then
      v_items:=jsonb_build_object(v_cave->>'resource_name',(v_cave->>'amount')::numeric);
      v_text:=array_append(v_text,coalesce(v_cave->>'resource_name','洞府资源')||' +'||coalesce(v_cave->>'amount','0'));
    end if;
  end if;
  return jsonb_build_object(
    'cultivation_requested',v_cgain,'cultivation_granted',v_granted,'cultivation_discarded',v_discarded,
    'spirit_stones_gained',v_sdelta,'permanent_effects',v_permanent,'items',v_items,'basis',v_basis,
    'reward_text',case when coalesce(array_length(v_text,1),0)>0 then array_to_string(v_text,'；') else '无额外首次研习奖励' end
  );
end$$;
revoke all on function public.apply_technique_book_first_rewards_v1(uuid,uuid,text,timestamptz) from public,anon,authenticated;

create or replace function public.get_technique_library_v1()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare u uuid:=auth.uid();c public.player_characters%rowtype;v_fate_code text;v_fate_name text;v_books jsonb;
begin
  if u is null then raise exception 'AUTH_REQUIRED';end if;
  select * into c from public.player_characters where user_id=u and status in('active','secluded','missing') order by created_at desc limit 1;
  if c.id is null then raise exception 'NO_ACTIVE_CHARACTER';end if;
  select f.code,f.name into v_fate_code,v_fate_name from public.character_fates cf join public.fates f on f.id=cf.fate_id
   where cf.character_id=c.id and cf.is_active order by cf.created_at limit 1;
  select coalesce(jsonb_agg((to_jsonb(x)-'sort_order') order by x.sort_order,x.name),'[]'::jsonb) into v_books from (
    select b.id as book_id,b.book_kind,b.technique_code,t.name,b.quantity,
      t.grade as grade_code,p.grade as grade_name,t.category,
      case when t.category='support' then '辅修功法' else '主修功法' end as category_name,
      t.description,t.fixed_effects,coalesce(p.first_reward_spec,'{}'::jsonb) as first_reward_spec,
      exists(select 1 from public.character_techniques ct where ct.character_id=c.id and ct.technique_id=t.id) as is_learned,
      true as is_matching_fate,
      not exists(select 1 from public.character_techniques ct where ct.character_id=c.id and ct.technique_id=t.id) as can_learn,
      exists(select 1 from public.character_techniques ct where ct.character_id=c.id and ct.technique_id=t.id) as can_contemplate,
      null::text as locked_reason,null::text as fate_code,null::text as fate_name,0::numeric as base_cultivation_multiplier,
      case p.grade when '玄品' then 20 when '地品' then 30 when '天品' then 40 when '仙品' then 50 else 60 end as sort_order
    from public.character_technique_books b
    join public.techniques t on t.code=b.technique_code and t.is_active
    left join public.opportunity_v4_technique_pool p on p.technique_code=t.code and p.is_active
    where b.character_id=c.id and b.book_kind='ordinary' and b.quantity>0
    union all
    select b.id,b.book_kind,b.technique_code,etd.name,b.quantity,
      'exclusive','专属','exclusive','专属功法',etd.description,'{}'::jsonb,'{}'::jsonb,
      exists(select 1 from public.character_exclusive_techniques cet where cet.character_id=c.id and cet.exclusive_code=etd.code),
      (etd.fate_code=v_fate_code),
      (etd.fate_code=v_fate_code) and not exists(select 1 from public.character_exclusive_techniques cet where cet.character_id=c.id and cet.exclusive_code=etd.code),
      false,
      case when etd.fate_code<>v_fate_code then '命格不符' when exists(select 1 from public.character_exclusive_techniques cet where cet.character_id=c.id and cet.exclusive_code=etd.code) then '已研习·道卷留存' else null end,
      etd.fate_code,etd.fate_name,etd.base_cultivation_multiplier,10
    from public.character_technique_books b
    join public.exclusive_technique_definitions etd on etd.code=b.technique_code
    where b.character_id=c.id and b.book_kind='exclusive' and b.quantity>0
  ) x;
  return jsonb_build_object('status','ok','character_id',c.id,'current_fate_code',v_fate_code,'current_fate_name',v_fate_name,'books',v_books);
end$$;
revoke all on function public.get_technique_library_v1() from public,anon;
grant execute on function public.get_technique_library_v1() to authenticated;

create or replace function public.use_technique_book_v1(p_book_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  u uuid:=auth.uid();c public.player_characters%rowtype;b public.character_technique_books%rowtype;t record;p record;etd record;
  v_fate_code text;v_learned boolean:=false;v_remaining integer:=0;v_mastery integer:=0;v_rewards jsonb:='{}'::jsonb;v_ct_id uuid;v_year integer;
begin
  if u is null then raise exception 'AUTH_REQUIRED';end if;
  select * into c from public.player_characters where user_id=u and status in('active','secluded','missing') order by created_at desc limit 1 for update;
  if c.id is null then raise exception 'NO_ACTIVE_CHARACTER';end if;
  select * into b from public.character_technique_books where id=p_book_id and character_id=c.id for update;
  if b.id is null then raise exception 'TECHNIQUE_BOOK_NOT_FOUND';end if;
  if b.quantity<=0 then raise exception 'TECHNIQUE_BOOK_EMPTY';end if;
  v_year:=greatest(1,c.birth_year+c.age);

  if b.book_kind='ordinary' then
    select id,code,name,grade,category into t from public.techniques where code=b.technique_code and is_active limit 1;
    select * into p from public.opportunity_v4_technique_pool where technique_code=b.technique_code and is_active;
    if t.id is null or p.technique_code is null then raise exception 'TECHNIQUE_NOT_FOUND';end if;
    select exists(select 1 from public.character_techniques where character_id=c.id and technique_id=t.id) into v_learned;
    if not v_learned then
      insert into public.character_techniques(character_id,technique_id,level,proficiency,is_equipped,slot_type,learned_year,acquisition_count,mastery_points,last_practiced_at)
      values(c.id,t.id,1,0,false,null,v_year,1,0,clock_timestamp()) returning id into v_ct_id;
      update public.character_technique_books set quantity=quantity-1,updated_at=now() where id=b.id returning quantity into v_remaining;
      if v_remaining<=0 then delete from public.character_technique_books where id=b.id;v_remaining:=0;end if;
      v_rewards:=public.apply_technique_book_first_rewards_v1(c.id,c.lineage_id,t.code,clock_timestamp());
      perform public.refresh_opportunity_technique_effects_v1(c.id);
      return jsonb_build_object(
        'success',true,'action','learn','book_kind','ordinary','technique_code',t.code,'technique_name',t.name,'category',t.category,
        'character_technique_id',v_ct_id,'quantity_remaining',v_remaining,'auto_equipped',false,'rewards',v_rewards,
        'reward_text',v_rewards->>'reward_text','message','已学会《'||t.name||'》第1层，功法尚未装备，请前往功法页自行选择槽位。'
      );
    end if;
    v_mastery:=case t.grade when 'immortal' then 80 when 'heaven' then 65 when 'earth' then 50 when 'mystic' then 40 when 'yellow' then 30 else 25 end;
    update public.character_techniques set acquisition_count=coalesce(acquisition_count,1)+1,mastery_points=coalesce(mastery_points,0)+v_mastery,updated_at=now()
     where character_id=c.id and technique_id=t.id returning id into v_ct_id;
    if v_ct_id is null then raise exception 'ORDINARY_TECHNIQUE_NOT_LEARNED';end if;
    update public.character_technique_books set quantity=quantity-1,updated_at=now() where id=b.id returning quantity into v_remaining;
    if v_remaining<=0 then delete from public.character_technique_books where id=b.id;v_remaining:=0;end if;
    return jsonb_build_object(
      'success',true,'action','contemplate','book_kind','ordinary','technique_code',t.code,'technique_name',t.name,
      'mastery_points_gained',v_mastery,'quantity_remaining',v_remaining,'reward_text','传承点 +'||v_mastery::text,
      'message','参悟同名功法书，获得'||v_mastery::text||'点传承点。'
    );
  end if;

  if b.book_kind='exclusive' then
    select * into etd from public.exclusive_technique_definitions where code=b.technique_code;
    if etd.code is null then raise exception 'EXCLUSIVE_TECHNIQUE_NOT_FOUND';end if;
    select f.code into v_fate_code from public.character_fates cf join public.fates f on f.id=cf.fate_id
     where cf.character_id=c.id and cf.is_active order by cf.created_at limit 1;
    if etd.fate_code is distinct from v_fate_code then raise exception 'EXCLUSIVE_BOOK_FATE_MISMATCH';end if;
    select exists(select 1 from public.character_exclusive_techniques where character_id=c.id and exclusive_code=etd.code) into v_learned;
    if v_learned then raise exception 'EXCLUSIVE_TECHNIQUE_ALREADY_LEARNED';end if;
    insert into public.character_exclusive_techniques(character_id,exclusive_code,level,equipped)
    values(c.id,etd.code,1,false);
    update public.character_technique_books set quantity=quantity-1,updated_at=now() where id=b.id returning quantity into v_remaining;
    if v_remaining<=0 then delete from public.character_technique_books where id=b.id;v_remaining:=0;end if;
    return jsonb_build_object(
      'success',true,'action','learn','book_kind','exclusive','technique_code',etd.code,'technique_name',etd.name,
      'quantity_remaining',v_remaining,'auto_equipped',false,'reward_text','本命专属功法已研习，尚未装备',
      'message','已学会本命专属功法《'||etd.name||'》第1层，请前往功法页自行放入专属槽。'
    );
  end if;
  raise exception 'INVALID_TECHNIQUE_BOOK_KIND';
end$$;
revoke all on function public.use_technique_book_v1(uuid) from public,anon;
grant execute on function public.use_technique_book_v1(uuid) to authenticated;

-- 机缘主结算：保留全部V0.14.5/V0.14.6规则，只替换功法获得链路。
create or replace function public.settle_opportunity_v4(p_settle_cultivation boolean default true)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  u uuid:=auth.uid();c public.player_characters%rowtype;st public.character_opportunity_v3_state%rowtype;cfg public.opportunity_v3_settings%rowtype;
  nowv timestamptz:=clock_timestamp();v_period_start timestamptz;v_event_at timestamptz;v_due integer:=0;v_capped integer:=0;v_gap numeric:=0;v_offline boolean:=false;
  v_batch uuid:=gen_random_uuid();v_grade text;v_path text;v_story record;v_result record;v_effect jsonb;v_applied jsonb;v_result_id uuid;
  v_fate_code text;v_lucky boolean:=false;v_ausp numeric:=50;v_roll numeric;v_total numeric;v_boost numeric:=1;
  w_ex numeric:=0.2;w_im numeric:=0.5;w_he numeric:=1.5;w_ea numeric:=8;w_my numeric:=25;w_ye numeric:=64.8;
  v_grade_counts jsonb:='{"黄品":0,"玄品":0,"地品":0,"天品":0,"仙品":0,"专属":0}'::jsonb;
  v_path_counts jsonb:='{"趋吉":0,"涉险":0}'::jsonb;
  v_cgain_req bigint:=0;v_closs_req bigint:=0;v_sgain bigint:=0;v_sloss bigint:=0;v_actual_gain bigint:=0;v_actual_loss bigint:=0;
  v_claim jsonb:=null;v_summary jsonb:=null;v_latest jsonb:=null;v_remaining jsonb:='{}'::jsonb;v_floor bigint:=0;v_before bigint;v_grant record;
  v_fate_has boolean:=false;v_has_own boolean:=false;v_pity numeric:=20;v_other numeric:=20;v_pick numeric;v_running numeric;v_exclusive record;v_acquired jsonb;
  v_rates record;v_tech_category text;v_tech_pool record;v_tech_award jsonb;v_tech_new jsonb:='[]'::jsonb;v_tech_dup jsonb:='[]'::jsonb;
  v_mastery integer:=0;v_permanent jsonb:='[]'::jsonb;v_items_gain jsonb:='{}'::jsonb;v_item record;v_item_amount numeric;
  v_book_add jsonb;v_book_gains jsonb:='{}'::jsonb;v_book_list jsonb:='[]'::jsonb;
begin
  if u is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into c from public.player_characters where user_id=u and status in('active','secluded','missing') order by created_at desc limit 1 for update;
  if c.id is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;
  select * into cfg from public.opportunity_v3_settings where world_code='jiuxiao_world_1';
  if cfg.world_code is null then raise exception 'OPPORTUNITY_SETTINGS_MISSING'; end if;
  insert into public.character_opportunity_v3_state(character_id,next_available_at,last_seen_at)
  values(c.id,nowv+interval '5 minutes',nowv) on conflict(character_id) do nothing;
  select * into st from public.character_opportunity_v3_state where character_id=c.id for update;
  select f.code into v_fate_code from public.character_fates cf join public.fates f on f.id=cf.fate_id where cf.character_id=c.id and cf.is_active order by cf.created_at limit 1;
  v_lucky:=coalesce(v_fate_code='lucky_encounter',false);
  v_ausp:=public.opportunity_v3_auspicious_probability_v1(c.luck,c.mindset,v_lucky);
  v_period_start:=least(coalesce(st.last_seen_at,nowv),nowv);v_gap:=greatest(0,extract(epoch from(nowv-v_period_start)));v_offline:=v_gap>=300;
  if cfg.enabled and nowv>=st.next_available_at then
    v_due:=floor(extract(epoch from(nowv-st.next_available_at))/300)::integer+1;
    v_capped:=greatest(0,v_due-least(v_due,coalesce(cfg.offline_catchup_limit,864)));v_due:=least(v_due,coalesce(cfg.offline_catchup_limit,864));
  end if;

  if v_due>0 then
    for i in 0..v_due-1 loop
      v_event_at:=st.next_available_at+make_interval(secs=>300*i);
      if v_lucky then v_boost:=1.10; else v_boost:=1; end if;
      w_ex:=0.2*v_boost;w_im:=0.5*v_boost;w_he:=1.5*v_boost;w_ea:=8*v_boost;w_my:=25;w_ye:=64.8;v_total:=w_ex+w_im+w_he+w_ea+w_my+w_ye;v_roll:=random()*v_total;
      if v_roll<w_ex then v_grade:='专属';elsif v_roll<w_ex+w_im then v_grade:='仙品';elsif v_roll<w_ex+w_im+w_he then v_grade:='天品';elsif v_roll<w_ex+w_im+w_he+w_ea then v_grade:='地品';elsif v_roll<w_ex+w_im+w_he+w_ea+w_my then v_grade:='玄品';else v_grade:='黄品';end if;
      v_path:=case when random()*100<v_ausp then 'auspicious' else 'risk' end;
      select * into v_story from public.opportunity_v4_story_pool where grade=v_grade and polarity=v_path and is_active order by -ln(greatest(random(),0.000001))/weight limit 1;
      if v_story.code is null then raise exception 'OPPORTUNITY_V4_STORY_MISSING:%:%',v_grade,v_path; end if;
      v_grade_counts:=jsonb_set(v_grade_counts,array[v_grade],to_jsonb(coalesce((v_grade_counts->>v_grade)::int,0)+1),true);
      v_path_counts:=jsonb_set(v_path_counts,array[case when v_path='auspicious' then '趋吉' else '涉险' end],to_jsonb(coalesce((v_path_counts->>(case when v_path='auspicious' then '趋吉' else '涉险' end))::int,0)+1),true);
      v_tech_award:=null;v_tech_category:=null;v_applied:='{}'::jsonb;

      if v_grade='专属' and v_path='auspicious' then
        select exists(select 1 from public.exclusive_technique_definitions where fate_code=v_fate_code) into v_fate_has;
        if v_fate_has then
          v_pity:=greatest(20,least(100,coalesce((st.exclusive_pity->>v_fate_code)::numeric,20)));
          v_other:=(100-v_pity)/4;
        else
          v_pity:=0;v_other:=20;
        end if;
        v_pick:=random()*100;v_running:=0;
        for v_exclusive in
          select etd.*,case when etd.fate_code=v_fate_code then v_pity else v_other end draw_weight
          from public.exclusive_technique_definitions etd order by etd.code
        loop
          v_running:=v_running+v_exclusive.draw_weight;
          if v_pick<=v_running then exit;end if;
        end loop;
        if v_exclusive.code is null then raise exception 'EXCLUSIVE_TECHNIQUE_POOL_MISSING';end if;
        v_book_add:=public.technique_book_add_v1(c.id,'exclusive',v_exclusive.code,1,v_event_at,jsonb_build_object('source','opportunity_v4','grade','专属'));
        v_acquired:=coalesce(st.acquired_exclusive_codes,'[]'::jsonb);
        if not(v_acquired@>jsonb_build_array(v_exclusive.code)) then v_acquired:=v_acquired||jsonb_build_array(v_exclusive.code);end if;
        st.acquired_exclusive_codes:=v_acquired;
        if v_exclusive.fate_code=v_fate_code then
          select * into v_result from public.opportunity_v4_result_pool where grade='专属' and polarity='auspicious' and effect_spec->>'exclusive_outcome'='success' and is_active order by random() limit 1;
          st.exclusive_pity:=jsonb_set(coalesce(st.exclusive_pity,'{}'::jsonb),array[v_fate_code],to_jsonb(20),true);
          v_result.title:='本命专属道卷·'||v_exclusive.name;
          v_result.narrative:='本命天机与你的命格共鸣，获得专属道卷《'||v_exclusive.name||'》×1，已收入洞府藏经架。可自行研习，研习后不会自动装备。';
        else
          select * into v_result from public.opportunity_v4_result_pool where grade='专属' and polarity='auspicious' and effect_spec->>'exclusive_outcome'='mismatch' and is_active order by random() limit 1;
          if v_fate_has then v_pity:=least(100,v_pity+2);st.exclusive_pity:=jsonb_set(coalesce(st.exclusive_pity,'{}'::jsonb),array[v_fate_code],to_jsonb(v_pity),true);end if;
          v_result.title:='异命专属道卷·'||v_exclusive.name;
          v_result.narrative:='获得异命专属道卷《'||v_exclusive.name||'》×1，已收入洞府藏经架。此道卷与你当前命格不契合，只能收藏，不能研习。';
        end if;
        update public.character_opportunity_v3_state set acquired_exclusive_codes=st.acquired_exclusive_codes,exclusive_pity=st.exclusive_pity,updated_at=nowv where character_id=c.id;
        v_effect='{}'::jsonb;
        v_applied:=jsonb_build_object('cultivation_gain_requested',0,'cultivation_loss_requested',0,'spirit_gain',0,'spirit_loss',0,'speed_bonus',0,'duration_minutes',0);
        v_tech_award:=jsonb_build_object(
          'awarded',true,'book_kind','exclusive','technique_code',v_exclusive.code,'technique_name',v_exclusive.name,
          'grade','专属','category','exclusive','quantity_added',1,'quantity_total',coalesce((v_book_add->>'quantity_total')::int,1),
          'is_matching_fate',(v_exclusive.fate_code=v_fate_code),'applied',v_applied,'narrative',v_result.narrative
        );
        v_book_gains:=public.technique_book_summary_add_v1(v_book_gains,v_tech_award);
      elsif v_path='auspicious' and v_grade in('玄品','地品','天品','仙品') then
        select * into v_rates from public.opportunity_v4_technique_drop_rates where grade=v_grade;
        v_roll:=random();
        if v_roll<coalesce(v_rates.main_rate,0) then v_tech_category:='main';
        elsif v_roll<coalesce(v_rates.main_rate,0)+coalesce(v_rates.support_rate,0) then v_tech_category:='support';end if;
        if v_tech_category is not null then
          select * into v_tech_pool from public.opportunity_v4_technique_pool where grade=v_grade and category=v_tech_category and is_active order by -ln(greatest(random(),0.000001))/weight limit 1;
          if v_tech_pool.technique_code is null then raise exception 'OPPORTUNITY_V4_TECHNIQUE_POOL_MISSING:%:%',v_grade,v_tech_category;end if;
          v_tech_award:=public.opportunity_v4_award_ordinary_technique(c.id,c.lineage_id,greatest(1,c.birth_year+c.age),v_tech_pool.technique_code,v_event_at);
          select ('technique:'||v_tech_pool.technique_code)::text as code,('功法书·'||v_tech_pool.technique_name)::text as title,(v_tech_award->>'narrative')::text as narrative,'{}'::jsonb as effect_spec into v_result;
          v_effect:='{}'::jsonb;v_applied:=coalesce(v_tech_award->'applied','{}'::jsonb);
          v_book_gains:=public.technique_book_summary_add_v1(v_book_gains,v_tech_award);
        else
          select * into v_result from public.opportunity_v4_result_pool where grade=v_grade and polarity=v_path and is_active order by -ln(greatest(random(),0.000001))/weight limit 1;
          v_effect:=v_result.effect_spec;
        end if;
      else
        select * into v_result from public.opportunity_v4_result_pool where grade=v_grade and polarity=v_path and is_active order by -ln(greatest(random(),0.000001))/weight limit 1;
        v_effect:=v_result.effect_spec;
      end if;

      if v_tech_award is null then
        if v_effect ? 'spirit_gain_fixed' then
          v_applied:=jsonb_build_object('cultivation_gain_requested',0,'cultivation_loss_requested',0,'spirit_gain',greatest(0,public.opportunity_v4_adjust_spirit_stones(c.id,(v_effect->>'spirit_gain_fixed')::bigint)),'spirit_loss',0,'speed_bonus',0,'duration_minutes',0);
        else
          v_applied:=public.opportunity_v4_prepare_effect(c.id,gen_random_uuid(),v_grade,v_path,v_effect,v_event_at);
        end if;
      end if;
      insert into public.opportunity_v3_results(character_id,catalog_code,rarity,path_key,reward_text,penalty_text,result_data,settlement_batch_id,scheduled_at)
      values(c.id,null,v_grade,v_path,case when v_path='auspicious' then v_result.narrative else '' end,case when v_path='risk' then v_result.narrative else null end,
        jsonb_build_object('v','opportunity_v4','story_code',v_story.code,'result_code',v_result.code,'title',v_result.title,'story',v_story.story,'applied',v_applied,'effect_spec',v_effect,'technique',v_tech_award),v_batch,v_event_at)
      returning id into v_result_id;
      update public.character_cultivation_effects set source_key='opportunity_v4:'||v_result_id::text,metadata=jsonb_set(metadata,'{result_id}',to_jsonb(v_result_id),true) where character_id=c.id and source_type='opportunity_v4' and starts_at=v_event_at and source_key like 'opportunity_v4:%' and metadata->>'grade'=v_grade;
      v_cgain_req:=v_cgain_req+coalesce((v_applied->>'cultivation_gain_requested')::bigint,0);v_closs_req:=v_closs_req+coalesce((v_applied->>'cultivation_loss_requested')::bigint,0);v_sgain:=v_sgain+coalesce((v_applied->>'spirit_gain')::bigint,0);v_sloss:=v_sloss+coalesce((v_applied->>'spirit_loss')::bigint,0);
      v_latest:=jsonb_build_object('result_id',v_result_id,'title',v_result.title,'content',v_story.story,'result_text',v_result.narrative,'rarity',v_grade,'rarity_name',v_grade,'path_name',case when v_path='auspicious' then '趋吉' else '涉险' end,'applied',v_applied,'created_at',v_event_at);
      if v_grade in('天品','仙品','专属') then
        insert into public.history_logs(world_id,world_year,scope_type,scope_id,event_type,title,content,importance,visibility,metadata)
        values(c.world_id,greatest(1,c.birth_year+c.age),'character',c.id,'opportunity','机缘·'||v_result.title,v_story.story||'【'||case when v_path='auspicious' then '趋吉所得' else '涉险结果' end||'】'||v_result.narrative,
          case v_grade when '专属' then 5 when '仙品' then 5 else 4 end,'owner',jsonb_build_object('v','opportunity_v4','result_id',v_result_id,'batch_id',v_batch,'scheduled_at',v_event_at,'applied',v_applied));
      end if;
    end loop;
  end if;

  if v_due>0 then
    update public.character_opportunity_v3_state set next_available_at=case when v_capped>0 then nowv+interval '5 minutes' else st.next_available_at+make_interval(secs=>300*v_due) end,last_seen_at=nowv,total_resolved=total_resolved+v_due,last_result=v_latest,updated_at=nowv where character_id=c.id;
  else update public.character_opportunity_v3_state set last_seen_at=nowv,updated_at=nowv where character_id=c.id;end if;

  if p_settle_cultivation then select to_jsonb(x) into v_claim from public.claim_cultivation_v1() x;end if;
  select pc.cultivation,coalesce(rs.cultivation_required,0) into v_before,v_floor from public.player_characters pc join public.realm_stages rs on rs.id=pc.realm_stage_id where pc.id=c.id for update;
  v_actual_loss:=least(v_closs_req,greatest(0,v_before-v_floor));if v_actual_loss>0 then update public.player_characters set cultivation=cultivation-v_actual_loss,updated_at=now() where id=c.id;end if;
  if v_cgain_req>0 then select * into v_grant from public.grant_cultivation_capped_v1(c.id,v_cgain_req,'opportunity_v4',jsonb_build_object('batch_id',v_batch));v_actual_gain:=coalesce(v_grant.granted_amount,0);end if;
  v_remaining:=public.opportunity_v4_remaining_effects(c.id,nowv);
  select coalesce(jsonb_agg(e.value order by e.value->>'book_kind',e.value->>'grade',e.value->>'name'),'[]'::jsonb)
    into v_book_list from jsonb_each(v_book_gains) e;
  if v_due>0 then
    insert into public.opportunity_v4_settlement_batches(id,character_id,period_started_at,period_ended_at,event_count,is_offline,capped_event_count,grade_counts,polarity_counts,gains,losses,net_result,remaining_effects,cultivation_claim,shown_at)
    values(v_batch,c.id,v_period_start,nowv,v_due,v_offline,v_capped,v_grade_counts,v_path_counts,
      jsonb_build_object('cultivation_direct',v_actual_gain,'spirit_stones',v_sgain,'items',v_items_gain,'technique_books',v_book_list,'techniques_new','[]'::jsonb,'techniques_duplicate','[]'::jsonb,'mastery_points',0,'permanent_effects','[]'::jsonb),
      jsonb_build_object('cultivation_direct',v_actual_loss,'spirit_stones',v_sloss,'items','{}'::jsonb),
      jsonb_build_object('cultivation',coalesce((v_claim->>'gained')::bigint,0)+v_actual_gain-v_actual_loss,'spirit_stones',v_sgain-v_sloss,'items',v_items_gain,'effects',v_remaining,'technique_books',v_book_list,'techniques_new','[]'::jsonb,'techniques_duplicate','[]'::jsonb,'mastery_points',0,'permanent_effects','[]'::jsonb),
      v_remaining,v_claim,case when v_offline then null else nowv end);
  end if;
  select to_jsonb(b) into v_summary from public.opportunity_v4_settlement_batches b where b.character_id=c.id and b.shown_at is null order by b.created_at desc limit 1;
  select * into st from public.character_opportunity_v3_state where character_id=c.id;
  if v_claim is not null then
    v_claim:=jsonb_set(v_claim,'{gained}',to_jsonb(coalesce((v_claim->>'gained')::bigint,0)+v_actual_gain-v_actual_loss),true);
    v_claim:=jsonb_set(v_claim,'{cultivation_total}',(select to_jsonb(cultivation) from public.player_characters where id=c.id),true);
  end if;
  return jsonb_build_object(
    'opportunity',jsonb_build_object('status','waiting','automatic',true,'next_available_at',st.next_available_at,'seconds_until_next',greatest(0,extract(epoch from(st.next_available_at-nowv))::int),'last_result',st.last_result,'auspicious_probability',v_ausp,'risk_probability',100-v_ausp,'lucky_auspicious_bonus',case when v_lucky then 5 else 0 end,'online_interval_seconds',300,'offline_interval_seconds',300,'offline_catchup_limit',864),
    'cultivation',v_claim,'offline_summary',v_summary,'events_resolved',v_due,'capped_events',v_capped
  );
end$$;
revoke all on function public.settle_opportunity_v4(boolean) from public,anon;
grant execute on function public.settle_opportunity_v4(boolean) to authenticated;

notify pgrst,'reload schema';
commit;
