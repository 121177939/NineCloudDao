-- 《九霄问道》Web Alpha V0.14.1
-- 灵石统一与万运博弈楼玩法重构。
-- 执行基础：V0.13.0、V0.14.0 FIX2 已成功部署；V0.14.0 FIX3 可选但建议已部署。
--
-- 本版规则：
-- 1. 全游戏只保留一种灵石：item_definitions.code='spirit_stone' 对应的非绑定库存。
-- 2. 机缘、洞府映射、赌坊、功法精进统一读写同一灵石余额。
-- 3. 取消大堂/雅间/修为局每日次数限制与每日造化签上限。
-- 4. 同一角色在每期每种资源池中只有1份等权造化资格；重复游玩不叠加个人中奖权重。
-- 5. 每笔有效赌注全额汇入全服共享的对应造化池；流局、取消、过期不入池。
-- 6. 每期开奖先从本期全部参与角色中等概率抽出1名候选者，再以40%概率中奖；60%未中时奖池全额滚存下期。

begin;

-- ---------------------------------------------------------------------------
-- 0. 基线保护
-- ---------------------------------------------------------------------------
do $$
begin
  if to_regclass('public.item_definitions') is null
     or to_regclass('public.character_inventory') is null
     or to_regclass('public.player_characters') is null then
    raise exception 'V0141_BASE_INVENTORY_MISSING';
  end if;
  if to_regclass('public.casino_settings') is null
     or to_regclass('public.casino_pools') is null
     or to_regclass('public.casino_house_games') is null
     or to_regclass('public.casino_duels') is null
     or to_regclass('public.casino_tickets') is null
     or to_regclass('public.casino_draws') is null then
    raise exception 'V0141_CASINO_BASE_MISSING';
  end if;
  if (select count(*) from public.item_definitions where code='spirit_stone') <> 1 then
    raise exception 'V0141_REQUIRES_EXACTLY_ONE_SPIRIT_STONE_DEFINITION';
  end if;
  if to_regprocedure('public.grant_cultivation_capped_v1(uuid,bigint,text,jsonb)') is null then
    raise exception 'V0141_REQUIRES_V0130_CULTIVATION_CAP';
  end if;
  if to_regclass('public.jiuxiao_world_events') is null
     or to_regprocedure('public.world_event_publish_v0140(uuid,integer,text,smallint,uuid,text,text,text,text,text,jsonb,boolean,timestamp with time zone)') is null then
    raise exception 'V0141_REQUIRES_V0140_FIX2_WORLD_EVENTS';
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 1. 赌场配置与审计字段
-- ---------------------------------------------------------------------------
alter table public.casino_settings
  add column if not exists pool_hit_chance numeric(6,5) not null default 0.40000;

update public.casino_settings
set pool_hit_chance=0.40000,
    updated_at=now()
where singleton_id=1;

do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='public' and t.relname='casino_settings'
      and c.conname='casino_settings_pool_hit_chance_v0141_check'
  ) then
    alter table public.casino_settings
      add constraint casino_settings_pool_hit_chance_v0141_check
      check (pool_hit_chance between 0 and 1);
  end if;
end
$$;

alter table public.casino_house_games
  add column if not exists pool_contribution bigint not null default 0;

alter table public.casino_duels
  add column if not exists pool_contribution bigint not null default 0;

alter table public.casino_draws
  add column if not exists candidate_character_id uuid references public.player_characters(id) on delete set null,
  add column if not exists pool_amount bigint not null default 0,
  add column if not exists did_hit boolean not null default true,
  add column if not exists hit_chance numeric(6,5) not null default 1.00000;

alter table public.casino_pools
  add column if not exists last_draw_hit boolean,
  add column if not exists last_candidate_character_id uuid references public.player_characters(id) on delete set null,
  add column if not exists last_ticket_count integer not null default 0;

-- 旧版每日造化签字段带有 <=10 检查；本版移除上限但保留字段作统计。
do $$
declare r record;
begin
  for r in
    select c.conname, n.nspname, t.relname
    from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='public'
      and t.relname in ('casino_daily_activity','casino_tickets')
      and c.contype='c'
      and pg_get_constraintdef(c.oid) ilike '%ticket_count%'
  loop
    execute format('alter table %I.%I drop constraint %I',r.nspname,r.relname,r.conname);
  end loop;
end
$$;

-- 旧轮次若曾积累多张签，升级时归一为“每名角色每期一份资格”。
update public.casino_tickets
set ticket_count=1,updated_at=now()
where ticket_count<>1;

do $$
begin
  if not exists (
    select 1 from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='public' and t.relname='casino_tickets'
      and c.conname='casino_tickets_one_qualification_v0141_check'
  ) then
    alter table public.casino_tickets
      add constraint casino_tickets_one_qualification_v0141_check check(ticket_count=1);
  end if;
  if not exists (
    select 1 from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='public' and t.relname='casino_daily_activity'
      and c.conname='casino_daily_spirit_qualification_nonnegative_v0141_check'
  ) then
    alter table public.casino_daily_activity
      add constraint casino_daily_spirit_qualification_nonnegative_v0141_check check(spirit_stone_ticket_count>=0);
  end if;
  if not exists (
    select 1 from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='public' and t.relname='casino_daily_activity'
      and c.conname='casino_daily_cultivation_qualification_nonnegative_v0141_check'
  ) then
    alter table public.casino_daily_activity
      add constraint casino_daily_cultivation_qualification_nonnegative_v0141_check check(cultivation_ticket_count>=0);
  end if;
end
$$;

-- ---------------------------------------------------------------------------
-- 2. 唯一灵石账户
-- ---------------------------------------------------------------------------
create or replace function public.spirit_stone_item_id_v0141()
returns uuid
language plpgsql
stable
security definer
set search_path=public,pg_temp
as $$
declare v_id uuid;
begin
  select i.id into v_id
  from public.item_definitions i
  where i.code='spirit_stone'
  limit 1;
  if v_id is null then raise exception 'SPIRIT_STONE_ITEM_MISSING'; end if;
  return v_id;
end;
$$;

-- 兼容旧赌场、洞府及其他既有函数：所有旧入口也解析到同一物品定义。
create or replace function public.casino_stone_item_id_v1()
returns uuid
language sql
stable
security definer
set search_path=public,pg_temp
as $$
  select public.spirit_stone_item_id_v0141();
$$;

create or replace function public.spirit_stone_balance_v0141(p_character_id uuid)
returns bigint
language sql
stable
security definer
set search_path=public,pg_temp
as $$
  select coalesce(sum(ci.quantity),0)::bigint
  from public.character_inventory ci
  where ci.character_id=p_character_id
    and ci.item_definition_id=public.spirit_stone_item_id_v0141();
$$;

create or replace function public.spirit_stone_normalize_character_v0141(p_character_id uuid)
returns bigint
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_item_id uuid:=public.spirit_stone_item_id_v0141();
  v_total bigint:=0;
  v_keep_id uuid;
  v_year integer:=1;
begin
  perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||p_character_id::text,141));
  perform 1
  from public.character_inventory ci
  where ci.character_id=p_character_id and ci.item_definition_id=v_item_id
  for update;

  select coalesce(sum(ci.quantity),0)::bigint,
         coalesce(min(ci.acquired_year),1)
    into v_total,v_year
  from public.character_inventory ci
  where ci.character_id=p_character_id and ci.item_definition_id=v_item_id;

  select ci.id into v_keep_id
  from public.character_inventory ci
  where ci.character_id=p_character_id
    and ci.item_definition_id=v_item_id
    and ci.is_bound=false
  order by ci.created_at,ci.id
  limit 1;

  if v_total<=0 then
    delete from public.character_inventory ci
    where ci.character_id=p_character_id and ci.item_definition_id=v_item_id;
    return 0;
  end if;

  if v_keep_id is null then
    insert into public.character_inventory(
      character_id,item_definition_id,quantity,is_bound,item_instance,acquired_year
    ) values (
      p_character_id,v_item_id,v_total,false,'{}'::jsonb,v_year
    ) returning id into v_keep_id;
  else
    update public.character_inventory ci
    set quantity=v_total,is_bound=false,item_instance='{}'::jsonb,updated_at=now()
    where ci.id=v_keep_id;
  end if;

  delete from public.character_inventory ci
  where ci.character_id=p_character_id
    and ci.item_definition_id=v_item_id
    and ci.id<>v_keep_id;

  return v_total;
end;
$$;

-- 先合并历史上绑定/非绑定两份灵石。
do $$
declare r record;
begin
  for r in
    select distinct ci.character_id
    from public.character_inventory ci
    where ci.item_definition_id=public.spirit_stone_item_id_v0141()
  loop
    perform public.spirit_stone_normalize_character_v0141(r.character_id);
  end loop;
end
$$;

-- 所有后续写入都强制落入非绑定、无实例数据的唯一灵石行。
create or replace function public.spirit_stone_inventory_guard_v0141()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_item_id uuid:=public.spirit_stone_item_id_v0141();
  v_existing_id uuid;
begin
  if new.item_definition_id<>v_item_id then return new; end if;
  new.is_bound:=false;
  new.item_instance:='{}'::jsonb;

  if tg_op='INSERT' then
    select ci.id into v_existing_id
    from public.character_inventory ci
    where ci.character_id=new.character_id
      and ci.item_definition_id=v_item_id
      and ci.is_bound=false
    for update;
    if v_existing_id is not null and v_existing_id is distinct from new.id then
      update public.character_inventory ci
      set quantity=ci.quantity+greatest(0,new.quantity),updated_at=now()
      where ci.id=v_existing_id;
      return null;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_spirit_stone_inventory_guard_v0141 on public.character_inventory;
create trigger trg_spirit_stone_inventory_guard_v0141
before insert or update on public.character_inventory
for each row execute function public.spirit_stone_inventory_guard_v0141();

-- 数据层再增加角色级唯一保护；使用动态谓词写入真实物品UUID。
do $$
declare v_item_id uuid:=public.spirit_stone_item_id_v0141();
begin
  execute format(
    'create unique index if not exists character_inventory_one_spirit_stone_v0141 on public.character_inventory(character_id) where item_definition_id=%L::uuid',
    v_item_id::text
  );
end
$$;

create or replace function public.get_spirit_stone_balance_v0141()
returns bigint
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_user_id uuid:=auth.uid();
  v_character_id uuid;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED'; end if;
  select pc.id into v_character_id
  from public.player_characters pc
  where pc.user_id=v_user_id and pc.status in ('active','secluded','missing')
  order by pc.created_at desc
  limit 1;
  if v_character_id is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;
  perform public.spirit_stone_normalize_character_v0141(v_character_id);
  return public.spirit_stone_balance_v0141(v_character_id);
end;
$$;

create or replace function public.award_spirit_stones_v3(p_character_id uuid,p_amount bigint)
returns void
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_item_id uuid:=public.spirit_stone_item_id_v0141();
  v_updated integer:=0;
begin
  if p_character_id is null or coalesce(p_amount,0)<=0 then return; end if;
  perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||p_character_id::text,141));
  perform public.spirit_stone_normalize_character_v0141(p_character_id);
  update public.character_inventory ci
  set quantity=ci.quantity+p_amount,updated_at=now()
  where ci.character_id=p_character_id
    and ci.item_definition_id=v_item_id
    and ci.is_bound=false;
  get diagnostics v_updated=row_count;
  if v_updated=0 then
    insert into public.character_inventory(
      character_id,item_definition_id,quantity,is_bound,item_instance,acquired_year
    ) values(p_character_id,v_item_id,p_amount,false,'{}'::jsonb,1);
  end if;
end;
$$;

create or replace function public.spirit_stone_debit_v0141(
  p_character_id uuid,
  p_amount bigint,
  p_error_code text default 'INSUFFICIENT_SPIRIT_STONES'
)
returns bigint
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_item_id uuid:=public.spirit_stone_item_id_v0141();
  v_balance bigint:=0;
begin
  if p_character_id is null or coalesce(p_amount,0)<=0 then raise exception 'SPIRIT_STONE_INVALID_DEBIT'; end if;
  perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||p_character_id::text,141));
  perform public.spirit_stone_normalize_character_v0141(p_character_id);
  select ci.quantity into v_balance
  from public.character_inventory ci
  where ci.character_id=p_character_id
    and ci.item_definition_id=v_item_id
    and ci.is_bound=false
  for update;
  if coalesce(v_balance,0)<p_amount then
    raise exception using message=coalesce(nullif(p_error_code,''),'INSUFFICIENT_SPIRIT_STONES');
  end if;
  if v_balance=p_amount then
    delete from public.character_inventory ci
    where ci.character_id=p_character_id
      and ci.item_definition_id=v_item_id
      and ci.is_bound=false;
    return 0;
  end if;
  update public.character_inventory ci
  set quantity=ci.quantity-p_amount,updated_at=now()
  where ci.character_id=p_character_id
    and ci.item_definition_id=v_item_id
    and ci.is_bound=false
  returning ci.quantity into v_balance;
  return coalesce(v_balance,0);
end;
$$;

-- “洞府日增灵石”的旧兼容映射不再随机转为灵蕴/灵草/灵矿，而是写入同一灵石账户。
create or replace function public.award_cave_resource_v3(
  p_lineage_id uuid,
  p_catalog_code text,
  p_amount numeric
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_character_id uuid;
  v_amount bigint:=greatest(0,floor(coalesce(p_amount,0)))::bigint;
begin
  if p_lineage_id is null or v_amount<=0 then
    return jsonb_build_object('awarded',false);
  end if;
  select pc.id into v_character_id
  from public.player_characters pc
  where pc.lineage_id=p_lineage_id
    and pc.status in ('active','secluded','missing')
  order by pc.created_at desc
  limit 1;
  if v_character_id is null then
    return jsonb_build_object('awarded',false,'reason','NO_ACTIVE_LINEAGE_CHARACTER');
  end if;
  perform public.award_spirit_stones_v3(v_character_id,v_amount);
  return jsonb_build_object(
    'awarded',true,'resource_code','spirit_stone','resource_name','灵石',
    'amount',v_amount,'character_id',v_character_id,'source_code',p_catalog_code
  );
end;
$$;

-- 如果历史洞府资源表中曾保存独立 spirit_stone 行，迁移至当前道统角色的统一账户。
do $$
declare
  r record;
  v_character_id uuid;
  v_has_updated_at boolean:=false;
begin
  if to_regclass('public.lineage_cave_resources') is null then return; end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='lineage_cave_resources' and column_name='lineage_id') then return; end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='lineage_cave_resources' and column_name='resource_code') then return; end if;
  if not exists(select 1 from information_schema.columns where table_schema='public' and table_name='lineage_cave_resources' and column_name='quantity') then return; end if;
  select exists(
    select 1 from information_schema.columns
    where table_schema='public' and table_name='lineage_cave_resources' and column_name='updated_at'
  ) into v_has_updated_at;
  for r in execute 'select lineage_id,coalesce(quantity,0) as quantity from public.lineage_cave_resources where resource_code=''spirit_stone'' and quantity>0 for update'
  loop
    select pc.id into v_character_id
    from public.player_characters pc
    where pc.lineage_id=r.lineage_id and pc.status in ('active','secluded','missing')
    order by pc.created_at desc limit 1;
    if v_character_id is not null then
      perform public.award_spirit_stones_v3(v_character_id,floor(r.quantity)::bigint);
      if v_has_updated_at then
        execute 'update public.lineage_cave_resources set quantity=0,updated_at=now() where lineage_id=$1 and resource_code=''spirit_stone'''
        using r.lineage_id;
      else
        execute 'update public.lineage_cave_resources set quantity=0 where lineage_id=$1 and resource_code=''spirit_stone'''
        using r.lineage_id;
      end if;
    end if;
  end loop;
end
$$;

create or replace function public.lineage_cave_spirit_stone_redirect_v0141()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_character_id uuid;
  v_delta bigint:=0;
begin
  if new.resource_code<>'spirit_stone' then return new; end if;
  v_delta:=case when tg_op='INSERT' then greatest(0,floor(coalesce(new.quantity,0)))::bigint
                else greatest(0,floor(coalesce(new.quantity,0)-coalesce(old.quantity,0)))::bigint end;
  select pc.id into v_character_id
  from public.player_characters pc
  where pc.lineage_id=new.lineage_id and pc.status in ('active','secluded','missing')
  order by pc.created_at desc limit 1;
  if v_character_id is null then return new; end if;
  if v_delta>0 then perform public.award_spirit_stones_v3(v_character_id,v_delta); end if;
  new.quantity:=0;
  return new;
end;
$$;

do $$
begin
  if to_regclass('public.lineage_cave_resources') is not null
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='lineage_cave_resources' and column_name='lineage_id')
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='lineage_cave_resources' and column_name='resource_code')
     and exists(select 1 from information_schema.columns where table_schema='public' and table_name='lineage_cave_resources' and column_name='quantity') then
    execute 'drop trigger if exists trg_lineage_cave_spirit_stone_redirect_v0141 on public.lineage_cave_resources';
    execute 'create trigger trg_lineage_cave_spirit_stone_redirect_v0141 before insert or update on public.lineage_cave_resources for each row execute function public.lineage_cave_spirit_stone_redirect_v0141()';
  end if;
end
$$;

-- 专属功法也改为统一账户扣费。
create or replace function public.upgrade_exclusive_technique_v1(p_character_exclusive_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  u uuid:=auth.uid();
  r record;
  v_cost bigint;
  v_remaining bigint;
  v_bonus numeric(12,6);
begin
  select cet.id,cet.character_id,cet.level,cet.equipped,
         etd.name,etd.max_level,etd.upgrade_cost_base,etd.base_cultivation_multiplier,
         pc.user_id
    into r
    from public.character_exclusive_techniques cet
    join public.exclusive_technique_definitions etd on etd.code=cet.exclusive_code
    join public.player_characters pc on pc.id=cet.character_id
   where cet.id=p_character_exclusive_id and pc.user_id=u
   for update;
  if r.id is null then raise exception 'EXCLUSIVE_TECHNIQUE_NOT_FOUND'; end if;
  if r.level>=r.max_level then raise exception 'EXCLUSIVE_TECHNIQUE_MAX_LEVEL'; end if;
  v_cost:=r.upgrade_cost_base*r.level*r.level;
  v_remaining:=public.spirit_stone_debit_v0141(r.character_id,v_cost,'INSUFFICIENT_SPIRIT_STONES');
  update public.character_exclusive_techniques set level=level+1 where id=r.id;
  if r.equipped then perform public.refresh_exclusive_technique_effects_v1(r.character_id); end if;
  v_bonus:=public.exclusive_technique_effect_bonus_v1(r.level+1,r.base_cultivation_multiplier);
  return jsonb_build_object(
    'success',true,'technique_name',r.name,'level',r.level+1,'cost',v_cost,
    'spirit_stones_remaining',v_remaining,'effect_multiplier_bonus',v_bonus
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. 赌场不限次、全额入池、每人每期一份等权资格
-- ---------------------------------------------------------------------------
create or replace function public.casino_available_v1(p_character_id uuid,p_stake_type text)
returns bigint
language plpgsql
stable
security definer
set search_path=public,pg_temp
as $$
declare
  v_amount bigint:=0;
  v_floor bigint:=0;
  v_major_order smallint;
begin
  if p_stake_type='spirit_stone' then
    return public.spirit_stone_balance_v0141(p_character_id);
  elsif p_stake_type='cultivation' then
    select pc.cultivation,r.major_order into v_amount,v_major_order
    from public.player_characters pc
    join public.realm_stages rs on rs.id=pc.realm_stage_id
    join public.realms r on r.id=rs.realm_id
    where pc.id=p_character_id;
    select min(rs.cultivation_required) into v_floor
    from public.realm_stages rs join public.realms r on r.id=rs.realm_id
    where r.major_order=v_major_order;
    return greatest(0,coalesce(v_amount,0)-coalesce(v_floor,0));
  end if;
  raise exception 'CASINO_INVALID_STAKE_TYPE';
end;
$$;

create or replace function public.casino_debit_v1(
  p_character_id uuid,p_stake_type text,p_amount bigint,p_context text,p_game_code text
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_balance bigint:=0;
  v_cultivation bigint:=0;
  v_floor bigint:=0;
  v_available bigint:=0;
  v_maximum bigint:=0;
  v_major_order smallint;
  v_stage_id smallint;
  v_stage_name text;
begin
  if p_amount is null or p_amount<=0 then raise exception 'CASINO_INVALID_STAKE_AMOUNT'; end if;
  if p_amount>9007199254740991 then raise exception 'CASINO_STAKE_TOO_LARGE'; end if;
  if p_context not in ('house','duel') then raise exception 'CASINO_INVALID_CONTEXT'; end if;
  if p_stake_type='spirit_stone' then
    if p_amount<10 then raise exception 'CASINO_STAKE_BELOW_MINIMUM'; end if;
    v_balance:=public.spirit_stone_balance_v0141(p_character_id);
    if v_balance<p_amount then raise exception 'CASINO_INSUFFICIENT_SPIRIT_STONES'; end if;
    perform public.spirit_stone_debit_v0141(p_character_id,p_amount,'CASINO_INSUFFICIENT_SPIRIT_STONES');
    return jsonb_build_object('stake_type',p_stake_type,'amount',p_amount,'available_before',v_balance,'available_after',v_balance-p_amount);
  elsif p_stake_type='cultivation' then
    if public.character_cultivation_full_v1(p_character_id) then raise exception 'CULTIVATION_FULL_CASINO_BLOCKED'; end if;
    select pc.cultivation,pc.realm_stage_id,rs.stage_name,r.major_order
      into v_cultivation,v_stage_id,v_stage_name,v_major_order
    from public.player_characters pc
    join public.realm_stages rs on rs.id=pc.realm_stage_id
    join public.realms r on r.id=rs.realm_id
    where pc.id=p_character_id
    for update of pc;
    if v_stage_id is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;
    if v_major_order<public.casino_nascent_major_order_v1() then raise exception 'CASINO_CULTIVATION_REQUIRES_NASCENT_SOUL'; end if;
    select min(rs.cultivation_required) into v_floor
    from public.realm_stages rs join public.realms r on r.id=rs.realm_id
    where r.major_order=v_major_order;
    v_available:=greatest(0,v_cultivation-coalesce(v_floor,0));
    v_maximum:=floor(v_available*0.20)::bigint;
    if p_amount<50000 then raise exception 'CULTIVATION_STAKE_MINIMUM'; end if;
    if p_amount>v_available then raise exception 'CASINO_INSUFFICIENT_CULTIVATION'; end if;
    if p_amount>v_maximum then raise exception 'CASINO_CULTIVATION_STAKE_EXCEEDS_TWENTY_PERCENT'; end if;
    update public.player_characters pc set cultivation=pc.cultivation-p_amount,updated_at=now() where pc.id=p_character_id;
    return jsonb_build_object(
      'stake_type',p_stake_type,'amount',p_amount,'available_before',v_available,'available_after',v_available-p_amount,
      'cultivation_before',v_cultivation,'cultivation_after',v_cultivation-p_amount,
      'stage_before_id',v_stage_id,'stage_before_name',v_stage_name,'major_order',v_major_order,'major_floor',v_floor
    );
  end if;
  raise exception 'CASINO_INVALID_STAKE_TYPE';
end;
$$;

create or replace function public.casino_credit_result_v0141(p_character_id uuid,p_stake_type text,p_amount bigint)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_grant record;
begin
  if p_amount is null or p_amount<=0 then
    return jsonb_build_object('requested_amount',greatest(coalesce(p_amount,0),0),'granted_amount',0,'discarded_amount',0);
  end if;
  if p_stake_type='spirit_stone' then
    perform public.award_spirit_stones_v3(p_character_id,p_amount);
    return jsonb_build_object('requested_amount',p_amount,'granted_amount',p_amount,'discarded_amount',0);
  elsif p_stake_type='cultivation' then
    select * into v_grant
    from public.grant_cultivation_capped_v1(
      p_character_id,p_amount,'casino_credit',jsonb_build_object('stake_type',p_stake_type,'version','0.14.1')
    );
    return jsonb_build_object(
      'requested_amount',coalesce(v_grant.requested_amount,p_amount),
      'granted_amount',coalesce(v_grant.granted_amount,0),
      'discarded_amount',coalesce(v_grant.discarded_amount,0),
      'cultivation_total',v_grant.cultivation_total,
      'cultivation_cap',v_grant.cultivation_cap,
      'cultivation_full',v_grant.cultivation_full
    );
  end if;
  raise exception 'CASINO_INVALID_STAKE_TYPE';
end;
$$;

create or replace function public.casino_credit_v1(p_character_id uuid,p_stake_type text,p_amount bigint)
returns void
language plpgsql
security definer
set search_path=public,pg_temp
as $$
begin
  perform public.casino_credit_result_v0141(p_character_id,p_stake_type,p_amount);
end;
$$;

create or replace function public.casino_assert_activity_allowed_v1(p_character_id uuid,p_mode text,p_stake_type text)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare a public.casino_daily_activity;
begin
  if p_mode not in ('house','duel') then raise exception 'CASINO_INVALID_ACTIVITY_MODE'; end if;
  if p_stake_type not in ('spirit_stone','cultivation') then raise exception 'CASINO_INVALID_STAKE_TYPE'; end if;
  insert into public.casino_daily_activity(character_id,activity_date)
  values(p_character_id,current_date)
  on conflict(character_id,activity_date) do nothing;
  select * into a from public.casino_daily_activity
  where character_id=p_character_id and activity_date=current_date
  for update;
  return to_jsonb(a);
end;
$$;

create or replace function public.casino_record_activity_v1(p_character_id uuid,p_mode text,p_stake_type text)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare a public.casino_daily_activity;
begin
  perform public.casino_assert_activity_allowed_v1(p_character_id,p_mode,p_stake_type);
  update public.casino_daily_activity x
  set house_count=x.house_count+case when p_mode='house' then 1 else 0 end,
      duel_count=x.duel_count+case when p_mode='duel' then 1 else 0 end,
      cultivation_count=x.cultivation_count+case when p_stake_type='cultivation' then 1 else 0 end,
      total_count=x.total_count+1,last_play_at=now(),updated_at=now()
  where x.character_id=p_character_id and x.activity_date=current_date
  returning * into a;
  return to_jsonb(a);
end;
$$;

create or replace function public.casino_add_ticket_v1(p_character_id uuid,p_stake_type text)
returns boolean
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_round_ends_at timestamptz;
  v_stake_type text:=p_stake_type;
  v_inserted integer:=0;
begin
  if v_stake_type not in ('spirit_stone','cultivation') then raise exception 'CASINO_INVALID_STAKE_TYPE'; end if;
  select p.next_draw_at into v_round_ends_at
  from public.casino_pools p where p.stake_type=v_stake_type for update;
  if v_round_ends_at is null then return false; end if;

  insert into public.casino_tickets(stake_type,round_ends_at,character_id,ticket_count)
  values(v_stake_type,v_round_ends_at,p_character_id,1)
  on conflict(stake_type,round_ends_at,character_id) do nothing;
  get diagnostics v_inserted=row_count;
  if v_inserted=0 then return false; end if;

  insert into public.casino_daily_activity(character_id,activity_date)
  values(p_character_id,current_date)
  on conflict(character_id,activity_date) do nothing;
  if v_stake_type='spirit_stone' then
    update public.casino_daily_activity a
    set spirit_stone_ticket_count=a.spirit_stone_ticket_count+1,updated_at=now()
    where a.character_id=p_character_id and a.activity_date=current_date;
  else
    update public.casino_daily_activity a
    set cultivation_ticket_count=a.cultivation_ticket_count+1,updated_at=now()
    where a.character_id=p_character_id and a.activity_date=current_date;
  end if;
  return true;
end;
$$;

create or replace function public.casino_settle_duels_v1()
returns integer
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  d record;v_result integer;v_prize bigint;v_pool_contribution bigint;
  v_winner uuid;v_loser uuid;v_creator_name text;v_opponent_name text;
  v_credit jsonb;v_requested_prize bigint;
  v_result_text text;v_drop jsonb;v_count integer:=0;
  v_creator_new_qualification boolean;v_opponent_new_qualification boolean;
begin
  for d in
    select * from public.casino_duels x
    where x.status='sealed' and x.reveal_at<=now()
    for update skip locked
  loop
    v_result:=public.casino_result_v1(d.game_code,d.creator_choice,d.opponent_choice);
    select pc.name into v_creator_name from public.player_characters pc where pc.id=d.creator_character_id;
    select pc.name into v_opponent_name from public.player_characters pc where pc.id=d.opponent_character_id;
    if v_result=0 then
      perform public.casino_credit_v1(d.creator_character_id,d.stake_type,d.stake_amount);
      perform public.casino_credit_v1(d.opponent_character_id,d.stake_type,d.stake_amount);
      v_result_text:=format('五分钟已尽，无相阵盘同时显出【%s】。双方同招，此局流局，赌注原数奉还；流局不进入造化池。',public.casino_choice_name_v1(d.game_code,d.creator_choice));
      update public.casino_duels x
      set status='draw',fee_amount=0,prize_amount=0,pool_contribution=0,settled_at=now(),result_text=v_result_text,updated_at=now()
      where x.id=d.id;
    else
      v_winner:=case when v_result=1 then d.creator_character_id else d.opponent_character_id end;
      v_loser:=case when v_result=1 then d.opponent_character_id else d.creator_character_id end;
      v_pool_contribution:=d.stake_amount*2;
      v_requested_prize:=d.stake_amount*2;
      update public.casino_pools p set amount=p.amount+v_pool_contribution,updated_at=now() where p.stake_type=d.stake_type;
      v_credit:=public.casino_credit_result_v0141(v_winner,d.stake_type,v_requested_prize);
      v_prize:=coalesce((v_credit->>'granted_amount')::bigint,0);
      if d.stake_type='cultivation' then v_drop:=public.casino_realign_after_loss_v1(v_loser); end if;
      v_creator_new_qualification:=public.casino_add_ticket_v1(d.creator_character_id,d.stake_type);
      v_opponent_new_qualification:=public.casino_add_ticket_v1(d.opponent_character_id,d.stake_type);
      v_result_text:=format(
        '无相阵盘开契：%s施展【%s】，%s施展【%s】。%s胜出，获得%s%s；双方共%s%s赌注全额汇入全服造化池，二人均已纳入本期等权候选名录。%s',
        coalesce(v_creator_name,'创建者'),public.casino_choice_name_v1(d.game_code,d.creator_choice),
        coalesce(v_opponent_name,'应局者'),public.casino_choice_name_v1(d.game_code,d.opponent_choice),
        case when v_result=1 then coalesce(v_creator_name,'创建者') else coalesce(v_opponent_name,'应局者') end,
        v_prize,case when d.stake_type='cultivation' then '点修为' else '枚灵石' end,
        v_pool_contribution,case when d.stake_type='cultivation' then '点修为' else '枚灵石' end,
        case when d.stake_type='cultivation' and coalesce((v_credit->>'discarded_amount')::bigint,0)>0
          then format(' 胜者受境界上限所限，另有%s点修为未能纳入体内。',v_credit->>'discarded_amount')
          when d.stake_type='cultivation' and coalesce((v_drop->>'stage_changed')::boolean,false)
          then format(' 败者境界由【%s】跌至【%s】，但未跌出当前大境界。',v_drop->>'stage_before_name',v_drop->>'stage_after_name') else '' end
      );
      update public.casino_duels x
      set status='settled',winner_character_id=v_winner,fee_amount=0,prize_amount=v_prize,
          pool_contribution=v_pool_contribution,settled_at=now(),result_text=v_result_text,updated_at=now()
      where x.id=d.id;
    end if;
    v_count:=v_count+1;
    v_drop:=null;v_credit:=null;
  end loop;
  return v_count;
end;
$$;

create or replace function public.casino_draw_pools_v1()
returns integer
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  p record;
  v_candidate uuid;
  v_candidate_name text;
  v_participants integer:=0;
  v_pick integer:=0;
  v_interval integer:=coalesce((select s.draw_interval_seconds from public.casino_settings s where s.singleton_id=1),7200);
  v_hit_chance numeric(6,5):=coalesce((select s.pool_hit_chance from public.casino_settings s where s.singleton_id=1),0.40000);
  v_hit boolean:=false;
  v_result_text text;
  v_count integer:=0;
  v_credit jsonb;
  v_granted bigint:=0;
  v_rollover bigint:=0;
begin
  for p in
    select * from public.casino_pools x
    where x.next_draw_at<=now()
    for update skip locked
  loop
    select count(*)::integer into v_participants
    from public.casino_tickets t
    join public.player_characters pc on pc.id=t.character_id and pc.status in ('active','secluded','missing')
    where t.stake_type=p.stake_type and t.round_ends_at=p.next_draw_at;

    if v_participants>0 then
      v_pick:=floor(random()*v_participants)::integer;
      select t.character_id into v_candidate
      from public.casino_tickets t
      join public.player_characters pc on pc.id=t.character_id and pc.status in ('active','secluded','missing')
      where t.stake_type=p.stake_type and t.round_ends_at=p.next_draw_at
      order by t.character_id
      offset v_pick limit 1;
    else
      v_candidate:=null;
    end if;

    v_hit:=v_candidate is not null and p.amount>0 and random()<v_hit_chance;
    select pc.name into v_candidate_name from public.player_characters pc where pc.id=v_candidate;

    if v_hit then
      v_credit:=public.casino_credit_result_v0141(v_candidate,p.stake_type,p.amount);
      v_granted:=coalesce((v_credit->>'granted_amount')::bigint,0);
      v_rollover:=greatest(0,p.amount-v_granted);
    else
      v_granted:=0;
      v_rollover:=p.amount;
    end if;

    if v_hit then
      if v_granted>0 then
        v_result_text:=format(
          '万运博弈楼钟鸣九响，从本期%s名参与者中等概率抽出【%s】，天机应验，得获%s%s%s。',
          v_participants,coalesce(v_candidate_name,'无名修士'),v_granted,
          case when p.stake_type='cultivation' then '点修为' else '枚灵石' end,
          case when v_rollover>0 then format('；受境界上限所限，余下%s点修为继续滚存下期',v_rollover) else '' end
        );
      else
        v_result_text:=format(
          '万运博弈楼从本期%s名参与者中等概率抽出【%s】，天机虽已应验，奈何其修为已至当前境界圆满，未能承接奖池；%s修为全额滚存下期。',
          v_participants,coalesce(v_candidate_name,'无名修士'),p.amount
        );
      end if;
      insert into public.casino_draws(
        stake_type,round_ended_at,winner_character_id,candidate_character_id,
        prize_amount,pool_amount,ticket_count,did_hit,hit_chance,result_text
      ) values(
        p.stake_type,p.next_draw_at,case when v_granted>0 then v_candidate else null end,v_candidate,
        v_granted,p.amount,v_participants,true,v_hit_chance,v_result_text
      );
      update public.casino_pools x
      set amount=v_rollover,last_draw_at=now(),last_winner_character_id=case when v_granted>0 then v_candidate else null end,last_prize=v_granted,
          last_draw_hit=true,last_candidate_character_id=v_candidate,last_ticket_count=v_participants,
          next_draw_at=now()+make_interval(secs=>v_interval),updated_at=now()
      where x.stake_type=p.stake_type;
      v_count:=v_count+1;
    elsif v_candidate is not null and p.amount>0 then
      v_result_text:=format(
        '万运博弈楼从本期%s名参与者中等概率抽出【%s】，奈何天机未应。本期无人得彩，%s造化池%s%s全额滚存下期。',
        v_participants,coalesce(v_candidate_name,'无名修士'),
        case when p.stake_type='cultivation' then '修为' else '灵石' end,
        p.amount,case when p.stake_type='cultivation' then '点修为' else '枚灵石' end
      );
      insert into public.casino_draws(
        stake_type,round_ended_at,winner_character_id,candidate_character_id,
        prize_amount,pool_amount,ticket_count,did_hit,hit_chance,result_text
      ) values(
        p.stake_type,p.next_draw_at,null,v_candidate,
        0,p.amount,v_participants,false,v_hit_chance,v_result_text
      );
      update public.casino_pools x
      set amount=p.amount,last_draw_at=now(),last_winner_character_id=null,last_prize=0,
          last_draw_hit=false,last_candidate_character_id=v_candidate,last_ticket_count=v_participants,
          next_draw_at=now()+make_interval(secs=>v_interval),updated_at=now()
      where x.stake_type=p.stake_type;
      v_count:=v_count+1;
    else
      update public.casino_pools x
      set last_draw_at=now(),last_winner_character_id=null,last_prize=0,
          last_draw_hit=null,last_candidate_character_id=null,last_ticket_count=0,
          next_draw_at=now()+make_interval(secs=>v_interval),updated_at=now()
      where x.stake_type=p.stake_type;
    end if;

    delete from public.casino_tickets t
    where t.stake_type=p.stake_type and t.round_ends_at=p.next_draw_at;
    v_candidate:=null;v_candidate_name:=null;v_participants:=0;v_pick:=0;
    v_hit:=false;v_credit:=null;v_granted:=0;v_rollover:=0;
  end loop;
  return v_count;
end;
$$;

create or replace function public.get_market_v1()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_character_id uuid;v_stones bigint:=0;v_cultivation_available bigint:=0;
  v_major_order smallint;v_stage_name text;v_activity jsonb:='{}'::jsonb;v_enabled boolean;
  v_cultivation_cap bigint;v_cultivation_full boolean:=false;
begin
  perform public.casino_process_v1();
  v_character_id:=public.casino_current_character_id_v1();
  perform public.spirit_stone_normalize_character_v0141(v_character_id);
  select s.enabled into v_enabled from public.casino_settings s where s.singleton_id=1;
  v_stones:=public.casino_available_v1(v_character_id,'spirit_stone');
  v_cultivation_available:=public.casino_available_v1(v_character_id,'cultivation');
  select r.major_order,rs.stage_name,public.character_cultivation_cap_v1(pc.realm_stage_id),public.character_cultivation_full_v1(pc.id)
  into v_major_order,v_stage_name,v_cultivation_cap,v_cultivation_full
  from public.player_characters pc join public.realm_stages rs on rs.id=pc.realm_stage_id join public.realms r on r.id=rs.realm_id
  where pc.id=v_character_id;
  select to_jsonb(a) into v_activity from public.casino_daily_activity a
  where a.character_id=v_character_id and a.activity_date=current_date;

  return jsonb_build_object(
    'status',case when v_enabled then 'active' else 'disabled' end,
    'settings',(select jsonb_build_object(
      'reveal_delay_seconds',s.reveal_delay_seconds,'open_expiry_seconds',s.open_expiry_seconds,
      'draw_interval_seconds',s.draw_interval_seconds,'pool_hit_chance',s.pool_hit_chance,
      'stone_minimum',10,'cultivation_minimum',50000,'quick_multipliers',jsonb_build_array(1,5,10,50,100),
      'qualification_rule','one_per_character_per_round'
    ) from public.casino_settings s where s.singleton_id=1),
    'character',jsonb_build_object(
      'stage_name',v_stage_name,'major_order',v_major_order,
      'cultivation_eligible',v_major_order>=public.casino_nascent_major_order_v1() and not v_cultivation_full,
      'cultivation_full',v_cultivation_full,'cultivation_cap',v_cultivation_cap,
      'spirit_stones',v_stones,'cultivation_available',v_cultivation_available,'cultivation_max_stake',floor(v_cultivation_available*0.20)::bigint
    ),
    'activity',coalesce(v_activity,jsonb_build_object('house_count',0,'duel_count',0,'cultivation_count',0,'total_count',0,'spirit_stone_ticket_count',0,'cultivation_ticket_count',0)),
    'pools',(select jsonb_object_agg(p.stake_type,jsonb_build_object(
      'amount',p.amount,'next_draw_at',p.next_draw_at,'seconds_remaining',greatest(0,extract(epoch from p.next_draw_at-now()))::integer,
      'ticket_count',(select count(*)::integer from public.casino_tickets t where t.stake_type=p.stake_type and t.round_ends_at=p.next_draw_at),
      'last_prize',p.last_prize,'last_winner_name',winner.name,'last_draw_hit',p.last_draw_hit,
      'last_candidate_name',candidate.name,'last_ticket_count',p.last_ticket_count
    )) from public.casino_pools p
       left join public.player_characters winner on winner.id=p.last_winner_character_id
       left join public.player_characters candidate on candidate.id=p.last_candidate_character_id),
    'tickets',(select jsonb_object_agg(p.stake_type,coalesce(t.ticket_count,0))
      from public.casino_pools p left join public.casino_tickets t
      on t.stake_type=p.stake_type and t.round_ends_at=p.next_draw_at and t.character_id=v_character_id),
    'latest_draws',(select coalesce(jsonb_agg(x.obj order by x.created_at desc),'[]'::jsonb) from (
      select d.created_at,jsonb_build_object(
        'stake_type',d.stake_type,'prize_amount',d.prize_amount,'pool_amount',d.pool_amount,
        'did_hit',d.did_hit,'hit_chance',d.hit_chance,'winner_name',winner.name,'candidate_name',candidate.name,
        'ticket_count',d.ticket_count,'result_text',d.result_text,'created_at',d.created_at
      ) obj
      from public.casino_draws d
      left join public.player_characters winner on winner.id=d.winner_character_id
      left join public.player_characters candidate on candidate.id=d.candidate_character_id
      order by d.created_at desc limit 8
    ) x),
    'open_duels',(select coalesce(jsonb_agg(x.obj order by x.created_at desc),'[]'::jsonb) from (
      select d.created_at,jsonb_build_object(
        'id',d.id,'creator_name',pc.name,'game_code',d.game_code,'stake_type',d.stake_type,'stake_amount',d.stake_amount,
        'expires_in',greatest(0,extract(epoch from (d.created_at+make_interval(secs=>s.open_expiry_seconds))-now()))::integer
      ) obj
      from public.casino_duels d join public.player_characters pc on pc.id=d.creator_character_id
      cross join public.casino_settings s
      where d.status='open' and d.creator_character_id<>v_character_id
        and (d.stake_type<>'cultivation' or not v_cultivation_full)
      order by d.created_at desc limit 30
    ) x),
    'my_duels',(select coalesce(jsonb_agg(x.obj order by x.created_at desc),'[]'::jsonb) from (
      select d.created_at,jsonb_build_object(
        'id',d.id,'game_code',d.game_code,'status',d.status,
        'status_name',case d.status when 'open' then '等待应局' when 'sealed' then '赌契封存中' when 'settled' then '胜负已分' when 'draw' then '流局' when 'cancelled' then '已取消' else d.status end,
        'stake_type',d.stake_type,'stake_amount',d.stake_amount,'fee_amount',d.fee_amount,'prize_amount',d.prize_amount,'pool_contribution',d.pool_contribution,
        'seconds_remaining',case when d.reveal_at is null then 0 else greatest(0,extract(epoch from d.reveal_at-now()))::integer end,
        'result_text',d.result_text,
        'opponent_name',coalesce(case when d.creator_character_id=v_character_id then op.name else cr.name end,'等待道友'),
        'outcome',case when d.status='draw' then 'draw' when d.status='settled' and d.winner_character_id=v_character_id then 'win' when d.status='settled' then 'loss' else d.status end,
        'my_choice',public.casino_choice_name_v1(d.game_code,case when d.creator_character_id=v_character_id then d.creator_choice else d.opponent_choice end),
        'opponent_choice',case when d.status in ('settled','draw') then public.casino_choice_name_v1(d.game_code,case when d.creator_character_id=v_character_id then d.opponent_choice else d.creator_choice end) end,
        'can_cancel',d.status='open' and d.creator_character_id=v_character_id
      ) obj
      from public.casino_duels d
      join public.player_characters cr on cr.id=d.creator_character_id
      left join public.player_characters op on op.id=d.opponent_character_id
      where v_character_id in (d.creator_character_id,d.opponent_character_id)
      order by d.created_at desc limit 20
    ) x)
  );
end;
$$;

create or replace function public.play_house_game_v1(p_game_code text,p_stake_type text,p_stake_amount bigint,p_choice text)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_character_id uuid;v_roll integer;v_won boolean:=false;v_net_odds integer:=1;v_reward bigint:=0;
  v_result_text text;v_d1 integer;v_d2 integer;v_d3 integer;v_total integer;
  v_debit jsonb;v_drop jsonb;v_ticket boolean;v_result_payload jsonb;
  v_stake_type text:=p_stake_type;v_credit jsonb;v_requested_reward bigint:=0;
begin
  perform public.casino_assert_enabled_v1();
  perform public.casino_process_v1();
  if p_game_code not in ('spirit_dice','turtle_oracle') then raise exception 'CASINO_INVALID_HOUSE_GAME'; end if;
  if not public.casino_validate_choice_v1(p_game_code,p_choice) then raise exception 'CASINO_INVALID_CHOICE'; end if;
  v_character_id:=public.casino_current_character_id_v1();
  perform public.casino_record_activity_v1(v_character_id,'house',v_stake_type);
  v_debit:=public.casino_debit_v1(v_character_id,v_stake_type,p_stake_amount,'house',p_game_code);
  update public.casino_pools p
  set amount=p.amount+p_stake_amount,updated_at=now()
  where p.stake_type=v_stake_type;

  if p_game_code='spirit_dice' then
    v_d1:=1+floor(random()*6)::integer;v_d2:=1+floor(random()*6)::integer;v_d3:=1+floor(random()*6)::integer;v_total:=v_d1+v_d2+v_d3;
    if p_choice='triple' then v_won:=v_d1=v_d2 and v_d2=v_d3;v_net_odds:=34;
    else v_won:=not(v_d1=v_d2 and v_d2=v_d3) and ((p_choice='small' and v_total between 4 and 10) or (p_choice='big' and v_total between 11 and 17));v_net_odds:=1; end if;
    v_result_text:=format('荷老揭开玉盅，三枚灵骰显出【%s、%s、%s】，共%s点。%s',v_d1,v_d2,v_d3,v_total,
      case when v_d1=v_d2 and v_d2=v_d3 then '三相归一，围骰通杀。' when v_won then '你押中了此局。' else '此局与你所押不合。' end);
    v_result_payload:=jsonb_build_object('dice',jsonb_build_array(v_d1,v_d2,v_d3),'total',v_total,'choice',p_choice);
  else
    v_roll:=floor(random()*100)::integer;
    v_won:=(p_choice='auspicious' and v_roll<25) or (p_choice='neutral' and v_roll>=25 and v_roll<75) or (p_choice='ominous' and v_roll>=75);
    v_net_odds:=case when p_choice='neutral' then 1 else 3 end;
    v_result_text:=case when v_roll<25 then '灵火骤明，龟甲裂纹如灵芝舒展，显出【吉】象。'
      when v_roll<75 then '龟甲裂纹横竖相抵，灵火归静，显出【平】象。'
      else '龟甲中央崩开深纹，黑烟盘旋，显出【凶】象。' end;
    v_result_text:=v_result_text||case when v_won then ' 荷老颔首：“道友押中了。”' else ' 荷老淡声道：“落筹无悔。”' end;
    v_result_payload:=jsonb_build_object('roll',v_roll,'choice',p_choice,'result',case when v_roll<25 then 'auspicious' when v_roll<75 then 'neutral' else 'ominous' end);
  end if;

  if v_won then
    v_requested_reward:=p_stake_amount*(1+v_net_odds);
    v_credit:=public.casino_credit_result_v0141(v_character_id,v_stake_type,v_requested_reward);
    v_reward:=coalesce((v_credit->>'granted_amount')::bigint,0);
    if v_stake_type='cultivation' and coalesce((v_credit->>'discarded_amount')::bigint,0)>0 then
      v_result_text:=v_result_text||format(' 受境界上限所限，另有%s点修为未能纳入体内。',v_credit->>'discarded_amount');
    end if;
  elsif v_stake_type='cultivation' then
    v_drop:=public.casino_realign_after_loss_v1(v_character_id);
    if coalesce((v_drop->>'stage_changed')::boolean,false) then
      v_result_text:=v_result_text||format(' 你的境界由【%s】跌至【%s】，但未跌出当前大境界。',v_drop->>'stage_before_name',v_drop->>'stage_after_name');
    end if;
  end if;
  v_ticket:=public.casino_add_ticket_v1(v_character_id,v_stake_type);
  v_result_text:=v_result_text||format(' 本局%s%s赌注已全额汇入全服造化池；%s',p_stake_amount,
    case when v_stake_type='cultivation' then '点修为' else '枚灵石' end,
    case when v_ticket then '你已取得本期等权候选资格。' else '你已在本期候选名录中，本局不会叠加个人中奖权重。' end);

  insert into public.casino_house_games(character_id,game_code,stake_type,stake_amount,choice_code,outcome_code,reward_amount,fee_amount,pool_contribution,result_payload,result_text)
  values(v_character_id,p_game_code,v_stake_type,p_stake_amount,p_choice,case when v_won then 'win' else 'loss' end,v_reward,0,p_stake_amount,v_result_payload,v_result_text);

  return jsonb_build_object('won',v_won,'reward',v_reward,'fee',0,'pool_contribution',p_stake_amount,'ticket_awarded',v_ticket,'result_text',v_result_text,'drop',v_drop);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. 造化池界闻适配：中奖与未中均可被玩家看见
-- ---------------------------------------------------------------------------
create or replace function public.world_event_from_casino_draw_v0140()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_cfg boolean:=true;v_character public.player_characters%rowtype;v_world_year integer;
  v_unit text:=case when new.stake_type='cultivation' then '点修为' else '枚灵石' end;
  v_world_id uuid;v_title text;v_content text;v_actor_id uuid;v_actor_name text;
begin
  begin
    if to_regclass('public.jiuxiao_world_event_settings') is null then return new; end if;
    select s.casino_enabled into v_cfg from public.jiuxiao_world_event_settings s where s.singleton_id=1;
    if not coalesce(v_cfg,true) then return new; end if;
    v_actor_id:=coalesce(new.winner_character_id,new.candidate_character_id);
    select pc.* into v_character from public.player_characters pc where pc.id=v_actor_id;
    if v_character.id is null then return new; end if;
    v_world_id:=v_character.world_id;v_actor_name:=v_character.name;
    select gw.current_year into v_world_year from public.game_worlds gw where gw.id=v_world_id;
    if new.did_hit and new.winner_character_id is not null and new.prize_amount>0 then
      v_title:='造化开奖';
      v_content:=format('万运博弈楼从%s名参与者中等概率抽出修士【%s】，天机应验，得获本期造化%s%s%s。',new.ticket_count,v_actor_name,new.prize_amount,v_unit,case when new.pool_amount>new.prize_amount then format('，余下%s%s滚存下期',new.pool_amount-new.prize_amount,v_unit) else '' end);
    elsif new.did_hit then
      v_title:='造化难承';
      v_content:=format('万运博弈楼从%s名参与者中等概率抽出修士【%s】，天机虽已应验，奈何其修为已至圆满，未能承接；造化池%s%s全额滚存下期。',new.ticket_count,v_actor_name,new.pool_amount,v_unit);
    else
      v_title:='造化未应';
      v_content:=format('万运博弈楼从%s名参与者中等概率抽出修士【%s】，奈何天机未应。本期无人得彩，造化池%s%s全额滚存下期。',new.ticket_count,v_actor_name,new.pool_amount,v_unit);
    end if;
    perform public.world_event_publish_v0140(
      v_world_id,v_world_year,case when new.did_hit then 'casino_pool_hit' else 'casino_pool_miss' end,
      (case when new.did_hit then 3 else 2 end)::smallint,
      v_actor_id,v_actor_name,v_title,v_content,'casino_draws',new.id::text,
      jsonb_build_object('stake_type',new.stake_type,'prize_amount',new.prize_amount,'pool_amount',new.pool_amount,'ticket_count',new.ticket_count,'did_hit',new.did_hit,'hit_chance',new.hit_chance),
      true,null::timestamptz
    );
  exception when others then return new;
  end;
  return new;
end;
$$;

drop trigger if exists trg_world_event_casino_draw_v0140 on public.casino_draws;
create trigger trg_world_event_casino_draw_v0140
after insert on public.casino_draws
for each row execute function public.world_event_from_casino_draw_v0140();

-- ---------------------------------------------------------------------------
-- 5. 权限与版本注释
-- ---------------------------------------------------------------------------
revoke all on function public.spirit_stone_item_id_v0141() from public,anon,authenticated;
revoke all on function public.casino_stone_item_id_v1() from public,anon,authenticated;
revoke all on function public.spirit_stone_balance_v0141(uuid) from public,anon,authenticated;
revoke all on function public.spirit_stone_normalize_character_v0141(uuid) from public,anon,authenticated;
revoke all on function public.spirit_stone_inventory_guard_v0141() from public,anon,authenticated;
revoke all on function public.spirit_stone_debit_v0141(uuid,bigint,text) from public,anon,authenticated;
revoke all on function public.get_spirit_stone_balance_v0141() from public,anon,authenticated;
revoke all on function public.casino_credit_result_v0141(uuid,text,bigint) from public,anon,authenticated;
revoke all on function public.lineage_cave_spirit_stone_redirect_v0141() from public,anon,authenticated;
revoke all on function public.award_spirit_stones_v3(uuid,bigint) from public,anon,authenticated;
revoke all on function public.award_cave_resource_v3(uuid,text,numeric) from public,anon,authenticated;
revoke all on function public.casino_available_v1(uuid,text) from public,anon,authenticated;
revoke all on function public.casino_debit_v1(uuid,text,bigint,text,text) from public,anon,authenticated;
revoke all on function public.casino_credit_v1(uuid,text,bigint) from public,anon,authenticated;
revoke all on function public.casino_assert_activity_allowed_v1(uuid,text,text) from public,anon,authenticated;
revoke all on function public.casino_record_activity_v1(uuid,text,text) from public,anon,authenticated;
revoke all on function public.casino_add_ticket_v1(uuid,text) from public,anon,authenticated;
revoke all on function public.casino_settle_duels_v1() from public,anon,authenticated;
revoke all on function public.casino_draw_pools_v1() from public,anon,authenticated;
revoke all on function public.world_event_from_casino_draw_v0140() from public,anon,authenticated;

-- 玩家入口权限保持原状，只开放正式RPC。
revoke all on function public.get_market_v1() from public,anon,authenticated;
revoke all on function public.play_house_game_v1(text,text,bigint,text) from public,anon,authenticated;
revoke all on function public.create_duel_v1(text,text,bigint,text) from public,anon,authenticated;
revoke all on function public.join_duel_v1(uuid,text) from public,anon,authenticated;
revoke all on function public.cancel_duel_v1(uuid) from public,anon,authenticated;
revoke all on function public.upgrade_exclusive_technique_v1(uuid) from public,anon,authenticated;
grant execute on function public.get_market_v1() to authenticated;
grant execute on function public.get_spirit_stone_balance_v0141() to authenticated;
grant execute on function public.play_house_game_v1(text,text,bigint,text) to authenticated;
grant execute on function public.create_duel_v1(text,text,bigint,text) to authenticated;
grant execute on function public.join_duel_v1(uuid,text) to authenticated;
grant execute on function public.cancel_duel_v1(uuid) to authenticated;
grant execute on function public.upgrade_exclusive_technique_v1(uuid) to authenticated;

comment on function public.award_spirit_stones_v3(uuid,bigint) is 'V0.14.1：机缘、洞府、赌坊及其他奖励统一写入唯一非绑定灵石账户。';
comment on table public.casino_pools is 'V0.14.1：全服共享灵石/修为造化池；有效赌注全额入池，40%开奖命中，未中全额滚存。';
comment on function public.casino_assert_activity_allowed_v1(uuid,text,text) is 'V0.14.1：仅校验玩法与资源类型，不再限制每日次数或冷却。';
comment on function public.casino_add_ticket_v1(uuid,text) is 'V0.14.1：同一角色每期每种资源池只有一份等权候选资格；重复游玩不叠加权重。';

commit;
notify pgrst,'reload schema';

-- ---------------------------------------------------------------------------
-- 6. 执行后自检（结果应全部为 true）
-- ---------------------------------------------------------------------------
select * from (values
  ('version_migration_committed', true, 'V0.14.1主迁移已提交'),
  ('one_spirit_stone_definition', (select count(*)=1 from public.item_definitions where code='spirit_stone'), '只存在一个spirit_stone物品定义'),
  ('one_spirit_stone_row_per_character', not exists(
      select 1 from public.character_inventory ci
      where ci.item_definition_id=public.spirit_stone_item_id_v0141()
      group by ci.character_id having count(*)>1
    ), '每名角色最多一行灵石库存'),
  ('spirit_stone_rows_unbound', not exists(
      select 1 from public.character_inventory ci
      where ci.item_definition_id=public.spirit_stone_item_id_v0141() and ci.is_bound
    ), '灵石统一为非绑定通用货币'),
  ('pool_hit_chance_40_percent', coalesce((select pool_hit_chance=0.40000 from public.casino_settings where singleton_id=1),false), '造化池命中率为40%'),
  ('pool_rows_ready', (select count(*)=2 from public.casino_pools where stake_type in ('spirit_stone','cultivation')), '灵石池与修为池均存在'),
  ('one_qualification_per_character_round', not exists(
      select 1 from public.casino_tickets t group by t.stake_type,t.round_ends_at,t.character_id having count(*)>1 or max(t.ticket_count)<>1
    ), '每名角色每期每种资源池最多一份等权候选资格'),
  ('legacy_stone_helper_unified', to_regprocedure('public.casino_stone_item_id_v1()') is not null, '旧赌场灵石入口已指向唯一灵石定义'),
  ('spirit_stone_balance_rpc_ready', to_regprocedure('public.get_spirit_stone_balance_v0141()') is not null, '统一灵石余额读取RPC已更新'),
  ('house_rpc_ready', to_regprocedure('public.play_house_game_v1(text,text,bigint,text)') is not null, '大堂RPC已更新'),
  ('duel_settlement_ready', to_regprocedure('public.casino_settle_duels_v1()') is not null, '雅间结算RPC已更新'),
  ('draw_rpc_ready', to_regprocedure('public.casino_draw_pools_v1()') is not null, '40%命中/60%滚存开奖RPC已更新'),
  ('world_event_trigger_ready', exists(
      select 1 from pg_trigger where tgname='trg_world_event_casino_draw_v0140' and not tgisinternal
    ), '造化池开奖结果会写入九霄界闻')
) as checks(name,ok,detail)
order by name;
