-- 九霄问道 V0.15.2 CACHE19
-- A线正式接入：功法五槽/灵石升级/圆满/道卷兑换，以及突破失败历史小境界保护线。

begin;

create table if not exists public.technique_v0152_settings(
  singleton_id smallint primary key default 1 check(singleton_id=1),
  upgrade_base integer not null default 1049,
  slot_multipliers jsonb not null default '[1.0,0.6,0.5,0.4,0.3]'::jsonb,
  updated_at timestamptz not null default now()
);
insert into public.technique_v0152_settings(singleton_id) values(1) on conflict(singleton_id) do nothing;

alter table public.character_techniques add column if not exists is_mastered boolean not null default false;
alter table public.character_techniques add column if not exists mastered_at timestamptz;
alter table public.character_techniques add column if not exists v0152_slot_index smallint;
alter table public.character_techniques drop constraint if exists character_techniques_v0152_slot_check;
alter table public.character_techniques add constraint character_techniques_v0152_slot_check check(v0152_slot_index is null or v0152_slot_index between 1 and 5);
drop index if exists public.uq_character_techniques_v0152_slot;
-- 唯一索引在旧槽位去重迁移完成后重建，避免历史重复主修/辅修数据导致升级中断。

alter table public.character_exclusive_techniques add column if not exists is_mastered boolean not null default false;
alter table public.character_exclusive_techniques add column if not exists mastered_at timestamptz;

alter table public.character_breakthrough_states add column if not exists historical_peak_stage_id smallint references public.realm_stages(id);
update public.character_breakthrough_states bs
set historical_peak_stage_id=coalesce(bs.historical_peak_stage_id,pc.realm_stage_id)
from public.player_characters pc where pc.id=bs.character_id;

create table if not exists public.technique_operation_requests_v0152(
  request_id uuid primary key,
  character_id uuid not null references public.player_characters(id) on delete cascade,
  operation text not null,
  result jsonb,
  created_at timestamptz not null default now()
);
revoke all on public.technique_operation_requests_v0152 from public,anon,authenticated;

create or replace function public.technique_grade_rules_v0152(p_grade text)
returns table(max_level integer,cost_factor numeric,redeem_rating integer)
language sql immutable set search_path=public,pg_temp as $$
  select x.max_level, x.cost_factor, x.redeem_rating
  from (values
    ('exclusive',36,1.00::numeric,1000),('immortal',30,0.95::numeric,800),('heaven',24,0.90::numeric,600),
    ('earth',18,0.85::numeric,400),('mystic',12,0.80::numeric,200),('yellow',6,0.75::numeric,100)
  ) x(grade,max_level,cost_factor,redeem_rating)
  where x.grade=coalesce(p_grade,'yellow')
$$;
revoke all on function public.technique_grade_rules_v0152(text) from public,anon,authenticated;

create or replace function public.technique_upgrade_cost_v0152(p_grade text,p_current_level integer)
returns bigint language sql immutable set search_path=public,pg_temp as $$
 select ceil(1049::numeric*greatest(1,p_current_level)^2*r.cost_factor)::bigint from public.technique_grade_rules_v0152(p_grade) r
$$;
create or replace function public.technique_mastery_cost_v0152(p_grade text)
returns bigint language sql immutable set search_path=public,pg_temp as $$
 select ceil(1049::numeric*(r.max_level-1)^2*r.cost_factor*1.5)::bigint from public.technique_grade_rules_v0152(p_grade) r
$$;
create or replace function public.technique_redeem_value_v0152(p_grade text)
returns bigint language sql immutable set search_path=public,pg_temp as $$
 select 1049::bigint*r.redeem_rating::bigint from public.technique_grade_rules_v0152(p_grade) r
$$;

create or replace function public.character_open_ordinary_slots_v0152(p_character_id uuid)
returns integer language sql stable security definer set search_path=public,pg_temp as $$
 select greatest(0,least(5,coalesce(r.major_order,1)-1))::integer
 from public.player_characters pc join public.realm_stages rs on rs.id=pc.realm_stage_id join public.realms r on r.id=rs.realm_id
 where pc.id=p_character_id
$$;
revoke all on function public.character_open_ordinary_slots_v0152(uuid) from public,anon,authenticated;

create or replace function public.refresh_opportunity_technique_effects_v1(p_character_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare r record;v_flat numeric;v_multiplier numeric;v_slot numeric;v_master numeric;
begin
 update public.character_cultivation_effects set is_active=false,expires_at=coalesce(expires_at,clock_timestamp()),updated_at=now()
 where character_id=p_character_id and source_key like 'opptech:%' and is_active;
 for r in
   select ct.id,ct.level,ct.is_mastered,ct.v0152_slot_index,t.code,t.name,t.fixed_effects
   from public.character_techniques ct join public.techniques t on t.id=ct.technique_id
   where ct.character_id=p_character_id and ct.v0152_slot_index between 1 and 5 and t.is_active
 loop
   v_slot:=case r.v0152_slot_index when 1 then 1.0 when 2 then 0.6 when 3 then 0.5 when 4 then 0.4 when 5 then 0.3 else 0 end;
   v_master:=case when r.is_mastered then 1.2 else 1 end;
   v_flat:=greatest(0,coalesce((r.fixed_effects->>'v3_base_cultivation_per_second')::numeric,0))*(1+greatest(0,r.level-1)*0.10)*v_master*v_slot;
   v_multiplier:=greatest(0,coalesce((r.fixed_effects->>'v3_base_cultivation_multiplier')::numeric,0))*(1+greatest(0,r.level-1)*0.10)*v_master*v_slot;
   if v_flat<>0 or v_multiplier<>0 then
    insert into public.character_cultivation_effects(character_id,source_type,source_key,display_name,instant_cultivation_awarded,flat_rate_per_second,multiplier_bonus,starts_at,expires_at,is_active,metadata)
    values(p_character_id,'technique','opptech:'||r.id,'功法·'||r.name,0,v_flat,v_multiplier,clock_timestamp(),null,true,
      jsonb_build_object('version','V0.15.2','technique_code',r.code,'level',r.level,'mastered',r.is_mastered,'slot_index',r.v0152_slot_index,'slot_multiplier',v_slot));
   end if;
 end loop;
end$$;

create or replace function public.set_technique_slot_v2(p_character_technique_id uuid,p_target_slot text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare u uuid:=auth.uid();c public.player_characters%rowtype;ct public.character_techniques%rowtype;t public.techniques%rowtype;v_slot integer;v_open integer;
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 select * into c from public.player_characters where user_id=u and status in('active','secluded','missing') order by created_at desc limit 1 for update;
 if c.id is null then raise exception 'NO_ACTIVE_CHARACTER';end if;
 perform public.claim_cultivation_v1();
 select * into ct from public.character_techniques where id=p_character_technique_id and character_id=c.id for update;
 if ct.id is null then raise exception 'TECHNIQUE_NOT_FOUND';end if;
 select * into t from public.techniques where id=ct.technique_id;
 v_slot:=case p_target_slot when 'ordinary_1' then 1 when 'main' then 1 when 'ordinary_2' then 2 when 'support_1' then 2 when 'ordinary_3' then 3 when 'support_2' then 3 when 'ordinary_4' then 4 when 'ordinary_5' then 5 else null end;
 if p_target_slot is null or p_target_slot='' or p_target_slot='none' then
   update public.character_techniques set v0152_slot_index=null,is_equipped=false,equipped_slot=null,slot_type=null,updated_at=now() where id=ct.id;
   perform public.refresh_opportunity_technique_effects_v1(c.id);
   return jsonb_build_object('success',true,'equipped',false,'technique_name',t.name);
 end if;
 if v_slot is null then raise exception 'INVALID_TECHNIQUE_SLOT';end if;
 v_open:=public.character_open_ordinary_slots_v0152(c.id);
 if v_open<1 then raise exception 'MORTAL_CANNOT_USE_TECHNIQUE';end if;
 if v_slot>v_open then raise exception 'TECHNIQUE_SLOT_REALM_LOCKED';end if;
 update public.character_techniques set v0152_slot_index=null,is_equipped=false,equipped_slot=null,slot_type=null,updated_at=now() where character_id=c.id and v0152_slot_index=v_slot and id<>ct.id;
 update public.character_techniques set v0152_slot_index=v_slot,is_equipped=true,equipped_slot='ordinary_'||v_slot,slot_type='ordinary',updated_at=now() where id=ct.id;
 perform public.refresh_opportunity_technique_effects_v1(c.id);
 return jsonb_build_object('success',true,'equipped',true,'equipped_slot','ordinary_'||v_slot,'technique_name',t.name,'slot_multiplier',case v_slot when 1 then 1 when 2 then .6 when 3 then .5 when 4 then .4 else .3 end);
end$$;
revoke all on function public.set_technique_slot_v2(uuid,text) from public,anon;grant execute on function public.set_technique_slot_v2(uuid,text) to authenticated;

create or replace function public.upgrade_technique_v2(p_character_technique_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare u uuid:=auth.uid();c public.player_characters%rowtype;ct public.character_techniques%rowtype;t public.techniques%rowtype;r record;v_cost bigint;v_master boolean:=false;
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
 if c.spirit_stones<v_cost then raise exception 'INSUFFICIENT_SPIRIT_STONES';end if;
 update public.player_characters set spirit_stones=spirit_stones-v_cost,updated_at=now() where id=c.id;
 if v_master then update public.character_techniques set is_mastered=true,mastered_at=clock_timestamp(),updated_at=now() where id=ct.id;
 else update public.character_techniques set level=level+1,proficiency=0,mastery_points=0,updated_at=now() where id=ct.id returning * into ct;end if;
 perform public.refresh_opportunity_technique_effects_v1(c.id);
 return jsonb_build_object('success',true,'technique_name',t.name,'level',case when v_master then ct.level else ct.level end,'max_level',r.max_level,'cost',v_cost,'mastered',v_master,'spirit_stones_after',c.spirit_stones-v_cost);
end$$;
revoke all on function public.upgrade_technique_v2(uuid) from public,anon;grant execute on function public.upgrade_technique_v2(uuid) to authenticated;

create or replace function public.redeem_technique_book_v0152(p_book_id uuid,p_quantity integer default 1,p_request_id uuid default gen_random_uuid())
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare u uuid:=auth.uid();c public.player_characters%rowtype;b public.character_technique_books%rowtype;v_grade text;v_name text;v_unit bigint;v_total bigint;v_result jsonb;
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
 update public.player_characters set spirit_stones=spirit_stones+v_total,updated_at=now() where id=c.id;
 v_result:=jsonb_build_object('success',true,'technique_name',coalesce(v_name,b.technique_code),'quantity',p_quantity,'unit_value',v_unit,'spirit_stones_gained',v_total,'spirit_stones_after',c.spirit_stones+v_total);
 insert into public.technique_operation_requests_v0152(request_id,character_id,operation,result) values(p_request_id,c.id,'redeem_book',v_result);
 return v_result;
end$$;
revoke all on function public.redeem_technique_book_v0152(uuid,integer,uuid) from public,anon;grant execute on function public.redeem_technique_book_v0152(uuid,integer,uuid) to authenticated;

-- 藏经架增加统一名称、兑换价值；所有未学习道卷都允许兑换。
create or replace function public.get_technique_library_v1()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare u uuid:=auth.uid();c public.player_characters%rowtype;v_fate_code text;v_fate_name text;v_books jsonb;v_open integer;
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 select * into c from public.player_characters where user_id=u and status in('active','secluded','missing') order by created_at desc limit 1;
 if c.id is null then raise exception 'NO_ACTIVE_CHARACTER';end if;
 v_open:=public.character_open_ordinary_slots_v0152(c.id);
 select f.code,f.name into v_fate_code,v_fate_name from public.character_fates cf join public.fates f on f.id=cf.fate_id where cf.character_id=c.id and cf.is_active order by cf.created_at limit 1;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.sort_order,x.name),'[]'::jsonb) into v_books from(
 select b.id book_id,b.book_kind,b.technique_code,t.name,b.quantity,t.grade grade_code,coalesce(p.grade,t.grade) grade_name,'ordinary' category,'普通功法' category_name,t.description,t.fixed_effects,coalesce(p.first_reward_spec,'{}'::jsonb) first_reward_spec,
 exists(select 1 from public.character_techniques ct where ct.character_id=c.id and ct.technique_id=t.id) is_learned,true is_matching_fate,
 (v_open>0 and not exists(select 1 from public.character_techniques ct where ct.character_id=c.id and ct.technique_id=t.id)) can_learn,false can_contemplate,
 case when v_open=0 then '凡人境不能研习功法' else null end locked_reason,null::text fate_code,null::text fate_name,0::numeric base_cultivation_multiplier,
 public.technique_redeem_value_v0152(t.grade) redeem_value,case t.grade when 'immortal' then 20 when 'heaven' then 30 when 'earth' then 40 when 'mystic' then 50 else 60 end sort_order
 from public.character_technique_books b join public.techniques t on t.code=b.technique_code and t.is_active left join public.opportunity_v4_technique_pool p on p.technique_code=t.code and p.is_active where b.character_id=c.id and b.book_kind='ordinary' and b.quantity>0
 union all
 select b.id,b.book_kind,b.technique_code,e.name,b.quantity,'exclusive','专属','exclusive','专属功法',e.description,'{}','{}',
 exists(select 1 from public.character_exclusive_techniques ce where ce.character_id=c.id and ce.exclusive_code=e.code),(e.fate_code=v_fate_code),
 (v_open>0 and e.fate_code=v_fate_code and not exists(select 1 from public.character_exclusive_techniques ce where ce.character_id=c.id and ce.exclusive_code=e.code)),false,
 case when v_open=0 then '凡人境不能研习功法' when e.fate_code<>v_fate_code then '命格不符，可保留或兑换' else null end,e.fate_code,e.fate_name,e.base_cultivation_multiplier,
 public.technique_redeem_value_v0152('exclusive'),10
 from public.character_technique_books b join public.exclusive_technique_definitions e on e.code=b.technique_code where b.character_id=c.id and b.book_kind='exclusive' and b.quantity>0
 )x;
 return jsonb_build_object('status','ok','character_id',c.id,'current_fate_code',v_fate_code,'current_fate_name',v_fate_name,'open_ordinary_slots',v_open,'books',v_books);
end$$;
revoke all on function public.get_technique_library_v1() from public,anon;grant execute on function public.get_technique_library_v1() to authenticated;

-- 迁移旧槽位：主修→1，辅修1→2，辅修2→3；同一角色同一旧槽如有脏数据，只保留一条。
-- 先清空新槽位，确保脚本可安全重跑。
update public.character_techniques set v0152_slot_index=null;

with legacy_ranked as (
  select ct.id,
         case coalesce(ct.equipped_slot,ct.slot_type)
           when 'main' then 1
           when 'support_1' then 2
           when 'support_2' then 3
           else null
         end as target_slot,
         row_number() over (
           partition by ct.character_id,
             case coalesce(ct.equipped_slot,ct.slot_type)
               when 'main' then 1
               when 'support_1' then 2
               when 'support_2' then 3
               else null
             end
           order by coalesce(ct.is_equipped,false) desc,ct.updated_at desc nulls last,ct.id
         ) as rn
  from public.character_techniques ct
  where coalesce(ct.equipped_slot,ct.slot_type) in ('main','support_1','support_2')
)
update public.character_techniques ct
set v0152_slot_index=lr.target_slot
from legacy_ranked lr
where ct.id=lr.id and lr.rn=1;

-- 未被选中的历史重复装备记录退回已学习列表，避免同槽冲突。
update public.character_techniques ct
set is_equipped=false,equipped_slot=null,slot_type=null,updated_at=now()
where coalesce(ct.equipped_slot,ct.slot_type) in ('main','support_1','support_2')
  and ct.v0152_slot_index is null;

-- 境界不足的槽位退回已学习列表。
update public.character_techniques ct set v0152_slot_index=null,is_equipped=false,equipped_slot=null,slot_type=null,updated_at=now()
where v0152_slot_index>public.character_open_ordinary_slots_v0152(ct.character_id);

-- 去重完成后再建立唯一约束。
create unique index uq_character_techniques_v0152_slot
on public.character_techniques(character_id,v0152_slot_index)
where v0152_slot_index is not null;

update public.character_techniques set proficiency=0,mastery_points=0;

-- B01突破保护线修正通过独立保护函数供attempt_breakthrough_v1调用/审计。
create or replace function public.breakthrough_major_fall_target_v0152(p_character_id uuid,p_current_stage_id smallint)
returns smallint language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_peak smallint;v_minor integer;v_major integer;v_nascent integer;v_target smallint;
begin
 select coalesce(bs.historical_peak_stage_id,p_current_stage_id) into v_peak from public.character_breakthrough_states bs where bs.character_id=p_character_id;
 select rs.minor_level,r.major_order into v_minor,v_major from public.realm_stages rs join public.realms r on r.id=rs.realm_id where rs.id=v_peak;
 select coalesce(min(major_order) filter(where code='nascent_soul' or name like '元婴%'),4) into v_nascent from public.realms;
 select rs.id into v_target from public.realm_stages rs join public.realms r on r.id=rs.realm_id where r.major_order=greatest(v_nascent,v_major-1)
 order by abs(rs.minor_level-v_minor),rs.minor_level desc,rs.id limit 1;
 return coalesce(v_target,p_current_stage_id);
end$$;

-- 历史最高境界只升不降：角色成功突破后由触发器更新。
create or replace function public.trg_breakthrough_peak_v0152() returns trigger language plpgsql security definer set search_path=public,pg_temp as $$
declare v_old_order integer;v_new_order integer;v_old_minor integer;v_new_minor integer;
begin
 if new.realm_stage_id is distinct from old.realm_stage_id then
  select r.major_order,rs.minor_level into v_old_order,v_old_minor from public.realm_stages rs join public.realms r on r.id=rs.realm_id where rs.id=coalesce((select historical_peak_stage_id from public.character_breakthrough_states where character_id=new.id),old.realm_stage_id);
  select r.major_order,rs.minor_level into v_new_order,v_new_minor from public.realm_stages rs join public.realms r on r.id=rs.realm_id where rs.id=new.realm_stage_id;
  if (v_new_order,v_new_minor)>(coalesce(v_old_order,-1),coalesce(v_old_minor,-1)) then
   insert into public.character_breakthrough_states(character_id,historical_peak_stage_id) values(new.id,new.realm_stage_id)
   on conflict(character_id) do update set historical_peak_stage_id=excluded.historical_peak_stage_id,updated_at=now();
  end if;
 end if;return new;
end$$;
drop trigger if exists trg_breakthrough_peak_v0152 on public.player_characters;
create trigger trg_breakthrough_peak_v0152 after update of realm_stage_id on public.player_characters for each row execute function public.trg_breakthrough_peak_v0152();

-- 将B01函数的大境跌落目标改为历史最高小阶段对应的前一大境界。
do $$declare vdef text;begin
 vdef:=pg_get_functiondef('public.attempt_breakthrough_v1()'::regprocedure);
 if position('public.breakthrough_major_fall_target_v0152' in vdef)=0 then
  vdef:=replace(vdef,
    'select rs.* into v_target from public.realm_stages rs join public.realms r on r.id=rs.realm_id\n      where r.major_order=greatest(v_nascent,(select max(r2.major_order) from public.realms r2 join public.realm_stages rs2 on rs2.realm_id=r2.id join public.realms rc on rc.id=v_current.realm_id where r2.major_order<rc.major_order))\n      order by abs(rs.minor_level-v_current.minor_level),rs.minor_level desc,rs.id limit 1;',
    'select rs.* into v_target from public.realm_stages rs where rs.id=public.breakthrough_major_fall_target_v0152(v_character.id,v_current.id);');
  execute vdef;
 end if;
end$$;

-- 专属功法统一为36级、1049基数升级、满级后单独圆满，圆满数值效果×120%。
create or replace function public.refresh_exclusive_technique_effects_v1(p_character_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare r record;v_bonus numeric(12,6);
begin
 update public.character_cultivation_effects set is_active=false,expires_at=coalesce(expires_at,clock_timestamp()),updated_at=now()
 where character_id=p_character_id and source_key like 'exclusive:%' and is_active;
 select cet.id,cet.exclusive_code,cet.level,cet.is_mastered,etd.name,etd.base_cultivation_multiplier into r
 from public.character_exclusive_techniques cet join public.exclusive_technique_definitions etd on etd.code=cet.exclusive_code
 where cet.character_id=p_character_id and cet.equipped=true limit 1;
 if r.id is null then return;end if;
 v_bonus:=greatest(0,coalesce(r.base_cultivation_multiplier,0))*(1+greatest(0,r.level-1)*0.10)*(case when r.is_mastered then 1.2 else 1 end);
 insert into public.character_cultivation_effects(character_id,source_type,source_key,display_name,instant_cultivation_awarded,flat_rate_per_second,multiplier_bonus,starts_at,expires_at,is_active,metadata)
 values(p_character_id,'buff','exclusive:'||r.exclusive_code,'专属功法·'||r.name,0,0,v_bonus,clock_timestamp(),null,true,
 jsonb_build_object('version','V0.15.2','level',r.level,'mastered',r.is_mastered,'mastery_multiplier',case when r.is_mastered then 1.2 else 1 end));
end$$;

create or replace function public.set_exclusive_technique_slot_v1(p_character_exclusive_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare u uuid:=auth.uid();c public.player_characters%rowtype;r record;
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 select * into c from public.player_characters where user_id=u and status in('active','secluded','missing') order by created_at desc limit 1 for update;
 if c.id is null then raise exception 'NO_ACTIVE_CHARACTER';end if;
 if public.character_open_ordinary_slots_v0152(c.id)<1 then raise exception 'MORTAL_CANNOT_USE_TECHNIQUE';end if;
 perform public.claim_cultivation_v1();
 select cet.id,cet.exclusive_code,etd.name into r from public.character_exclusive_techniques cet join public.exclusive_technique_definitions etd on etd.code=cet.exclusive_code where cet.id=p_character_exclusive_id and cet.character_id=c.id;
 if r.id is null then raise exception 'EXCLUSIVE_TECHNIQUE_NOT_FOUND';end if;
 update public.character_exclusive_techniques set equipped=(id=r.id) where character_id=c.id;
 perform public.refresh_exclusive_technique_effects_v1(c.id);
 return jsonb_build_object('success',true,'technique_name',r.name,'exclusive_code',r.exclusive_code,'equipped',true);
end$$;

create or replace function public.upgrade_exclusive_technique_v1(p_character_exclusive_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare u uuid:=auth.uid();c public.player_characters%rowtype;r record;v_cost bigint;v_remaining bigint;v_master boolean:=false;v_bonus numeric;
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 select * into c from public.player_characters where user_id=u and status in('active','secluded','missing') order by created_at desc limit 1 for update;
 if c.id is null then raise exception 'NO_ACTIVE_CHARACTER';end if;
 if public.character_open_ordinary_slots_v0152(c.id)<1 then raise exception 'MORTAL_CANNOT_STUDY_TECHNIQUE';end if;
 perform public.claim_cultivation_v1();
 select cet.id,cet.character_id,cet.level,cet.equipped,cet.is_mastered,etd.name,etd.base_cultivation_multiplier into r
 from public.character_exclusive_techniques cet join public.exclusive_technique_definitions etd on etd.code=cet.exclusive_code
 where cet.id=p_character_exclusive_id and cet.character_id=c.id for update;
 if r.id is null then raise exception 'EXCLUSIVE_TECHNIQUE_NOT_FOUND';end if;
 if r.is_mastered then raise exception 'TECHNIQUE_ALREADY_MASTERED';end if;
 if r.level<36 then v_cost:=public.technique_upgrade_cost_v0152('exclusive',r.level);else v_cost:=public.technique_mastery_cost_v0152('exclusive');v_master:=true;end if;
 v_remaining:=public.spirit_stone_debit_v0141(r.character_id,v_cost,'INSUFFICIENT_SPIRIT_STONES');
 if v_master then update public.character_exclusive_techniques set is_mastered=true,mastered_at=now() where id=r.id;
 else update public.character_exclusive_techniques set level=least(36,level+1) where id=r.id;end if;
 if r.equipped then perform public.refresh_exclusive_technique_effects_v1(r.character_id);end if;
 v_bonus:=greatest(0,coalesce(r.base_cultivation_multiplier,0))*(1+greatest(0,(case when v_master then r.level else r.level+1 end)-1)*0.10)*(case when v_master then 1.2 else 1 end);
 return jsonb_build_object('success',true,'technique_name',r.name,'level',case when v_master then r.level else r.level+1 end,'max_level',36,'cost',v_cost,'mastered',v_master,'spirit_stones_remaining',v_remaining,'effect_multiplier_bonus',v_bonus);
end$$;

create or replace function public.get_exclusive_technique_system_v1()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare u uuid:=auth.uid();c public.player_characters%rowtype;v_fate_code text;v_fate_name text;v_rows jsonb;v_equipped_name text;v_open integer;
begin
 if u is null then raise exception 'AUTH_REQUIRED';end if;
 select * into c from public.player_characters where user_id=u and status in('active','secluded','missing') order by created_at desc limit 1;
 if c.id is null then raise exception 'NO_ACTIVE_CHARACTER';end if;
 v_open:=public.character_open_ordinary_slots_v0152(c.id);
 select f.code,f.name into v_fate_code,v_fate_name from public.character_fates cf join public.fates f on f.id=cf.fate_id where cf.character_id=c.id and cf.is_active order by cf.created_at limit 1;
 select coalesce(jsonb_agg(to_jsonb(x) order by x.equipped desc,x.acquired_at),'[]'::jsonb) into v_rows from(
 select cet.id,cet.exclusive_code,cet.level,36 max_level,cet.equipped,cet.is_mastered,cet.acquired_at,etd.name,etd.description,etd.fate_code,etd.fate_name,etd.cave_resource_code,(etd.fate_code=v_fate_code) is_matching_fate,
 greatest(0,coalesce(etd.base_cultivation_multiplier,0))*(1+greatest(0,cet.level-1)*0.10)*(case when cet.is_mastered then 1.2 else 1 end) effect_multiplier_bonus,
 case when cet.is_mastered then 0 when cet.level<36 then public.technique_upgrade_cost_v0152('exclusive',cet.level) else public.technique_mastery_cost_v0152('exclusive') end next_upgrade_cost,
 (cet.level>=36 and not cet.is_mastered) can_master,v_open>0 can_use
 from public.character_exclusive_techniques cet join public.exclusive_technique_definitions etd on etd.code=cet.exclusive_code where cet.character_id=c.id)x;
 select etd.name into v_equipped_name from public.character_exclusive_techniques cet join public.exclusive_technique_definitions etd on etd.code=cet.exclusive_code where cet.character_id=c.id and cet.equipped=true limit 1;
 return jsonb_build_object('status','ok','character_id',c.id,'current_fate_code',v_fate_code,'current_fate_name',v_fate_name,'equipped_name',v_equipped_name,'exclusive_slot_open',v_open>0,'techniques',v_rows);
end$$;

commit;
