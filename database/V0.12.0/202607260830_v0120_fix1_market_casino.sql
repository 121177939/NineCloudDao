-- 《九霄问道》Web Alpha V0.12.0 FIX1
-- 市坊·万运博弈楼完整修正版。
-- 执行基础：V0.11.10 FIX1 + FIX2 已成功部署。
--
-- 正式规则：
-- 1. 大堂支持灵骰问道、气运龟卜；雅间支持灵拳对弈、五行灵拳。
-- 2. 灵石与修为不能混押；修为局仅元婴期及以上开放，单次最低 50,000。
-- 3. 修为下注最高为当前大境界可损失修为的 20%；输钱只会在当前大境界内部跌落小境界，绝不跨大境界。
-- 4. 所有分出胜负的玩法抽取总赌注 5%，100% 注入对应造化彩池；平局不抽水。
-- 5. 玩家雅间暗选招式，第二人应局后封存五分钟，一局定胜负；同招流局并全额退还。
-- 6. 公开赌桌 30 分钟无人应局自动取消并返还。
-- 7. 每两小时懒触发一次造化池开奖；每名角色每种资源每日最多取得 10 张造化签。
-- 8. 私有辅助函数全部撤销 PUBLIC/anon/authenticated 执行权，防止绕过正常 RPC 直接加资源。

begin;

create table if not exists public.casino_settings (
  singleton_id smallint primary key default 1 check (singleton_id = 1),
  enabled boolean not null default true,
  reveal_delay_seconds integer not null default 300 check (reveal_delay_seconds between 60 and 3600),
  open_expiry_seconds integer not null default 1800 check (open_expiry_seconds between 300 and 86400),
  draw_interval_seconds integer not null default 7200 check (draw_interval_seconds between 600 and 86400),
  updated_at timestamptz not null default now()
);
insert into public.casino_settings(singleton_id) values (1) on conflict (singleton_id) do nothing;

create table if not exists public.casino_pools (
  stake_type text primary key check (stake_type in ('spirit_stone','cultivation')),
  amount bigint not null default 0 check (amount >= 0),
  updated_at timestamptz not null default now()
);
alter table public.casino_pools
  add column if not exists next_draw_at timestamptz,
  add column if not exists last_draw_at timestamptz,
  add column if not exists last_winner_character_id uuid references public.player_characters(id) on delete set null,
  add column if not exists last_prize bigint not null default 0;
insert into public.casino_pools(stake_type) values ('spirit_stone'),('cultivation') on conflict (stake_type) do nothing;
update public.casino_pools
set next_draw_at = coalesce(next_draw_at, now() + interval '2 hours')
where next_draw_at is null;
alter table public.casino_pools alter column next_draw_at set not null;
alter table public.casino_pools alter column next_draw_at set default (now() + interval '2 hours');

create table if not exists public.casino_duels (
  id uuid primary key default gen_random_uuid(),
  creator_character_id uuid not null references public.player_characters(id),
  opponent_character_id uuid references public.player_characters(id),
  game_code text not null check (game_code in ('spirit_fist','five_elements')),
  stake_type text not null check (stake_type in ('spirit_stone','cultivation')),
  stake_amount bigint not null check (stake_amount > 0),
  creator_choice text not null,
  opponent_choice text,
  status text not null default 'open' check (status in ('open','sealed','settled','draw','cancelled')),
  reveal_at timestamptz,
  winner_character_id uuid references public.player_characters(id),
  result_text text,
  created_at timestamptz not null default now(),
  settled_at timestamptz
);
alter table public.casino_duels
  add column if not exists fee_amount bigint not null default 0,
  add column if not exists prize_amount bigint not null default 0,
  add column if not exists cancelled_at timestamptz,
  add column if not exists cancellation_reason text,
  add column if not exists updated_at timestamptz not null default now();

create table if not exists public.casino_house_games (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references public.player_characters(id) on delete cascade,
  game_code text not null check (game_code in ('spirit_dice','turtle_oracle')),
  stake_type text not null check (stake_type in ('spirit_stone','cultivation')),
  stake_amount bigint not null check (stake_amount > 0),
  choice_code text not null,
  outcome_code text not null check (outcome_code in ('win','loss')),
  reward_amount bigint not null default 0,
  fee_amount bigint not null default 0,
  result_payload jsonb not null default '{}'::jsonb,
  result_text text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.casino_daily_activity (
  character_id uuid not null references public.player_characters(id) on delete cascade,
  activity_date date not null default current_date,
  house_count integer not null default 0 check (house_count >= 0),
  duel_count integer not null default 0 check (duel_count >= 0),
  cultivation_count integer not null default 0 check (cultivation_count >= 0),
  total_count integer not null default 0 check (total_count >= 0),
  spirit_stone_ticket_count integer not null default 0 check (spirit_stone_ticket_count between 0 and 10),
  cultivation_ticket_count integer not null default 0 check (cultivation_ticket_count between 0 and 10),
  last_play_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key (character_id, activity_date)
);

create table if not exists public.casino_tickets (
  stake_type text not null check (stake_type in ('spirit_stone','cultivation')),
  round_ends_at timestamptz not null,
  character_id uuid not null references public.player_characters(id) on delete cascade,
  ticket_count integer not null default 1 check (ticket_count between 1 and 10),
  updated_at timestamptz not null default now(),
  primary key (stake_type, round_ends_at, character_id)
);

create table if not exists public.casino_draws (
  id uuid primary key default gen_random_uuid(),
  stake_type text not null check (stake_type in ('spirit_stone','cultivation')),
  round_ended_at timestamptz not null,
  winner_character_id uuid references public.player_characters(id) on delete set null,
  prize_amount bigint not null default 0 check (prize_amount >= 0),
  ticket_count integer not null default 0 check (ticket_count >= 0),
  result_text text not null,
  created_at timestamptz not null default now()
);

create index if not exists casino_duels_status_idx on public.casino_duels(status, created_at desc);
create index if not exists casino_duels_creator_active_idx on public.casino_duels(creator_character_id, status);
create index if not exists casino_duels_opponent_active_idx on public.casino_duels(opponent_character_id, status);
create index if not exists casino_house_games_character_idx on public.casino_house_games(character_id, created_at desc);
create index if not exists casino_draws_created_idx on public.casino_draws(created_at desc);
create index if not exists casino_tickets_round_idx on public.casino_tickets(stake_type, round_ends_at);

alter table public.casino_settings enable row level security;
alter table public.casino_pools enable row level security;
alter table public.casino_duels enable row level security;
alter table public.casino_house_games enable row level security;
alter table public.casino_daily_activity enable row level security;
alter table public.casino_tickets enable row level security;
alter table public.casino_draws enable row level security;

revoke all on table public.casino_settings from public, anon, authenticated;
revoke all on table public.casino_pools from public, anon, authenticated;
revoke all on table public.casino_duels from public, anon, authenticated;
revoke all on table public.casino_house_games from public, anon, authenticated;
revoke all on table public.casino_daily_activity from public, anon, authenticated;
revoke all on table public.casino_tickets from public, anon, authenticated;
revoke all on table public.casino_draws from public, anon, authenticated;

create or replace function public.casino_assert_enabled_v1()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if not coalesce((select s.enabled from public.casino_settings s where s.singleton_id = 1), false) then
    raise exception 'MARKET_DISABLED';
  end if;
end;
$$;

create or replace function public.casino_current_character_id_v1()
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_character_id uuid;
begin
  if auth.uid() is null then raise exception 'AUTH_REQUIRED'; end if;
  select pc.id into v_character_id
  from public.player_characters pc
  where pc.user_id = auth.uid()
    and pc.status in ('active','secluded','missing')
  order by pc.created_at desc
  limit 1;
  if v_character_id is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;
  return v_character_id;
end;
$$;

create or replace function public.casino_stone_item_id_v1()
returns uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare v_id uuid;
begin
  select i.id into v_id from public.item_definitions i where i.code = 'spirit_stone' limit 1;
  if v_id is null then raise exception 'SPIRIT_STONE_ITEM_MISSING'; end if;
  return v_id;
end;
$$;

create or replace function public.casino_nascent_major_order_v1()
returns smallint
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce(min(r.major_order) filter (where r.code='nascent_soul' or r.name like '元婴%'), 4)::smallint
  from public.realms r;
$$;

create or replace function public.casino_available_v1(p_character_id uuid, p_stake_type text)
returns bigint
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_amount bigint := 0;
  v_floor bigint := 0;
  v_major_order smallint;
begin
  if p_stake_type = 'spirit_stone' then
    select coalesce(ci.quantity,0) into v_amount
    from public.character_inventory ci
    where ci.character_id = p_character_id
      and ci.item_definition_id = public.casino_stone_item_id_v1();
    return coalesce(v_amount,0);
  elsif p_stake_type = 'cultivation' then
    select pc.cultivation, r.major_order
    into v_amount, v_major_order
    from public.player_characters pc
    join public.realm_stages rs on rs.id = pc.realm_stage_id
    join public.realms r on r.id = rs.realm_id
    where pc.id = p_character_id;
    select min(rs.cultivation_required) into v_floor
    from public.realm_stages rs
    join public.realms r on r.id = rs.realm_id
    where r.major_order = v_major_order;
    return greatest(0, coalesce(v_amount,0) - coalesce(v_floor,0));
  end if;
  raise exception 'CASINO_INVALID_STAKE_TYPE';
end;
$$;

create or replace function public.casino_validate_choice_v1(p_game_code text, p_choice text)
returns boolean
language sql
immutable
security definer
set search_path = public, pg_temp
as $$
  select case
    when p_game_code='spirit_fist' then p_choice in ('rock','scissors','paper')
    when p_game_code='five_elements' then p_choice in ('metal','wood','earth','water','fire')
    when p_game_code='spirit_dice' then p_choice in ('big','small','triple')
    when p_game_code='turtle_oracle' then p_choice in ('auspicious','neutral','ominous')
    else false
  end;
$$;

create or replace function public.casino_choice_name_v1(p_game_code text, p_choice text)
returns text
language sql
immutable
security definer
set search_path = public, pg_temp
as $$
  select case p_choice
    when 'rock' then '磐石势' when 'scissors' then '疾风刃' when 'paper' then '流云盾'
    when 'metal' then '金锐拳' when 'wood' then '青木拳' when 'earth' then '厚土拳'
    when 'water' then '浪涛拳' when 'fire' then '焚天拳'
    when 'big' then '大' when 'small' then '小' when 'triple' then '围骰'
    when 'auspicious' then '吉' when 'neutral' then '平' when 'ominous' then '凶'
    else coalesce(p_choice,'未知')
  end;
$$;

create or replace function public.casino_result_v1(p_game_code text, p_creator_choice text, p_opponent_choice text)
returns integer
language plpgsql
immutable
security definer
set search_path = public, pg_temp
as $$
begin
  if not public.casino_validate_choice_v1(p_game_code,p_creator_choice)
     or not public.casino_validate_choice_v1(p_game_code,p_opponent_choice) then
    raise exception 'CASINO_INVALID_CHOICE';
  end if;
  if p_creator_choice = p_opponent_choice then return 0; end if;
  if p_game_code = 'spirit_fist' then
    return case when (p_creator_choice,p_opponent_choice) in
      (('rock','scissors'),('scissors','paper'),('paper','rock')) then 1 else -1 end;
  elsif p_game_code = 'five_elements' then
    return case when (p_creator_choice,p_opponent_choice) in (
      ('metal','wood'),('metal','earth'),
      ('wood','earth'),('wood','water'),
      ('earth','water'),('earth','fire'),
      ('water','fire'),('water','metal'),
      ('fire','metal'),('fire','wood')
    ) then 1 else -1 end;
  end if;
  raise exception 'CASINO_INVALID_DUEL_GAME';
end;
$$;

create or replace function public.casino_debit_v1(
  p_character_id uuid,
  p_stake_type text,
  p_amount bigint,
  p_context text,
  p_game_code text
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_item_id uuid;
  v_quantity bigint := 0;
  v_cultivation bigint := 0;
  v_floor bigint := 0;
  v_available bigint := 0;
  v_maximum bigint := 0;
  v_minimum bigint := 0;
  v_major_order smallint;
  v_stage_id smallint;
  v_stage_name text;
begin
  if p_amount is null or p_amount <= 0 then raise exception 'CASINO_INVALID_STAKE_AMOUNT'; end if;
  if p_context not in ('house','duel') then raise exception 'CASINO_INVALID_CONTEXT'; end if;

  if p_stake_type = 'spirit_stone' then
    v_minimum := case
      when p_context='duel' then 10
      when p_game_code='spirit_dice' then 20
      when p_game_code='turtle_oracle' then 30
      else 10 end;
    v_maximum := case
      when p_context='duel' then 5000
      when p_game_code='spirit_dice' then 2000
      when p_game_code='turtle_oracle' then 1500
      else 5000 end;
    if p_amount < v_minimum then raise exception 'CASINO_STAKE_BELOW_MINIMUM'; end if;
    if p_amount > v_maximum then raise exception 'CASINO_STAKE_ABOVE_MAXIMUM'; end if;
    v_item_id := public.casino_stone_item_id_v1();
    select ci.quantity into v_quantity
    from public.character_inventory ci
    where ci.character_id = p_character_id and ci.item_definition_id = v_item_id
    for update;
    if coalesce(v_quantity,0) < p_amount then raise exception 'CASINO_INSUFFICIENT_SPIRIT_STONES'; end if;
    update public.character_inventory ci
    set quantity = ci.quantity - p_amount, updated_at = now()
    where ci.character_id = p_character_id and ci.item_definition_id = v_item_id;
    return jsonb_build_object('stake_type',p_stake_type,'amount',p_amount,'available_before',v_quantity,'available_after',v_quantity-p_amount);
  elsif p_stake_type = 'cultivation' then
    select pc.cultivation, pc.realm_stage_id, rs.stage_name, r.major_order
    into v_cultivation, v_stage_id, v_stage_name, v_major_order
    from public.player_characters pc
    join public.realm_stages rs on rs.id = pc.realm_stage_id
    join public.realms r on r.id = rs.realm_id
    where pc.id = p_character_id
    for update of pc;
    if v_stage_id is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;
    if v_major_order < public.casino_nascent_major_order_v1() then raise exception 'CASINO_CULTIVATION_REQUIRES_NASCENT_SOUL'; end if;
    select min(rs.cultivation_required) into v_floor
    from public.realm_stages rs join public.realms r on r.id = rs.realm_id
    where r.major_order = v_major_order;
    v_available := greatest(0, v_cultivation - coalesce(v_floor,0));
    v_minimum := 50000;
    v_maximum := floor(v_available * 0.20)::bigint;
    if p_amount < v_minimum then raise exception 'CULTIVATION_STAKE_MINIMUM'; end if;
    if p_amount > v_available then raise exception 'CASINO_INSUFFICIENT_CULTIVATION'; end if;
    if p_amount > v_maximum then raise exception 'CASINO_CULTIVATION_STAKE_EXCEEDS_TWENTY_PERCENT'; end if;
    update public.player_characters pc
    set cultivation = pc.cultivation - p_amount, updated_at = now()
    where pc.id = p_character_id;
    return jsonb_build_object(
      'stake_type',p_stake_type,'amount',p_amount,
      'available_before',v_available,'available_after',v_available-p_amount,
      'cultivation_before',v_cultivation,'cultivation_after',v_cultivation-p_amount,
      'stage_before_id',v_stage_id,'stage_before_name',v_stage_name,'major_order',v_major_order,'major_floor',v_floor
    );
  end if;
  raise exception 'CASINO_INVALID_STAKE_TYPE';
end;
$$;

create or replace function public.casino_credit_v1(p_character_id uuid, p_stake_type text, p_amount bigint)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if p_amount is null or p_amount <= 0 then return; end if;
  if p_stake_type='spirit_stone' then
    perform public.award_spirit_stones_v3(p_character_id,p_amount);
  elsif p_stake_type='cultivation' then
    update public.player_characters pc
    set cultivation = pc.cultivation + p_amount, updated_at = now()
    where pc.id = p_character_id;
  else
    raise exception 'CASINO_INVALID_STAKE_TYPE';
  end if;
end;
$$;

create or replace function public.casino_realign_after_loss_v1(p_character_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cultivation bigint;
  v_major_order smallint;
  v_floor bigint;
  v_old_stage_id smallint;
  v_old_stage_name text;
  v_new_stage_id smallint;
  v_new_stage_name text;
begin
  select pc.cultivation, pc.realm_stage_id, rs.stage_name, r.major_order
  into v_cultivation, v_old_stage_id, v_old_stage_name, v_major_order
  from public.player_characters pc
  join public.realm_stages rs on rs.id=pc.realm_stage_id
  join public.realms r on r.id=rs.realm_id
  where pc.id=p_character_id
  for update of pc;

  select min(rs.cultivation_required) into v_floor
  from public.realm_stages rs join public.realms r on r.id=rs.realm_id
  where r.major_order=v_major_order;
  v_cultivation := greatest(coalesce(v_cultivation,0),coalesce(v_floor,0));

  select rs.id,rs.stage_name into v_new_stage_id,v_new_stage_name
  from public.realm_stages rs join public.realms r on r.id=rs.realm_id
  where r.major_order=v_major_order and rs.cultivation_required<=v_cultivation
  order by rs.cultivation_required desc,rs.minor_level desc,rs.id desc
  limit 1;

  update public.player_characters pc
  set cultivation=v_cultivation,realm_stage_id=coalesce(v_new_stage_id,v_old_stage_id),updated_at=now()
  where pc.id=p_character_id;

  if v_new_stage_id is distinct from v_old_stage_id then
    update public.character_cultivation_state ccs
    set base_rate_per_second=public.realm_base_cultivation_rate_v1(v_new_stage_id),updated_at=now()
    where ccs.character_id=p_character_id;
  end if;

  return jsonb_build_object(
    'stage_changed',v_new_stage_id is distinct from v_old_stage_id,
    'stage_before_id',v_old_stage_id,'stage_before_name',v_old_stage_name,
    'stage_after_id',coalesce(v_new_stage_id,v_old_stage_id),'stage_after_name',coalesce(v_new_stage_name,v_old_stage_name),
    'cultivation_after',v_cultivation,'major_floor',v_floor
  );
end;
$$;

create or replace function public.casino_assert_activity_allowed_v1(p_character_id uuid,p_mode text,p_stake_type text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a public.casino_daily_activity;
begin
  if p_mode not in ('house','duel') then raise exception 'CASINO_INVALID_ACTIVITY_MODE'; end if;
  if p_stake_type not in ('spirit_stone','cultivation') then raise exception 'CASINO_INVALID_STAKE_TYPE'; end if;
  insert into public.casino_daily_activity(character_id,activity_date)
  values(p_character_id,current_date)
  on conflict(character_id,activity_date) do nothing;
  select * into a from public.casino_daily_activity
  where character_id=p_character_id and activity_date=current_date
  for update;
  if a.total_count>=30 then raise exception 'CASINO_TOTAL_DAILY_LIMIT'; end if;
  if p_mode='house' and a.house_count>=30 then raise exception 'CASINO_HOUSE_DAILY_LIMIT'; end if;
  if p_mode='duel' and a.duel_count>=15 then raise exception 'CASINO_DUEL_DAILY_LIMIT'; end if;
  if p_stake_type='cultivation' and a.cultivation_count>=10 then raise exception 'CASINO_CULTIVATION_DAILY_LIMIT'; end if;
  if a.total_count>=20 and a.last_play_at is not null and a.last_play_at>now()-interval '30 seconds' then
    raise exception 'CASINO_GREED_COOLDOWN';
  end if;
  return to_jsonb(a);
end;
$$;

create or replace function public.casino_record_activity_v1(p_character_id uuid,p_mode text,p_stake_type text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  a public.casino_daily_activity;
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
set search_path = public, pg_temp
as $$
declare
  v_round_ends_at timestamptz;
  v_count integer;
begin
  select p.next_draw_at into v_round_ends_at
  from public.casino_pools p where p.stake_type=p_stake_type for update;
  if v_round_ends_at is null then return false; end if;
  insert into public.casino_daily_activity(character_id,activity_date)
  values(p_character_id,current_date)
  on conflict(character_id,activity_date) do nothing;
  if p_stake_type='spirit_stone' then
    select a.spirit_stone_ticket_count into v_count from public.casino_daily_activity a
    where a.character_id=p_character_id and a.activity_date=current_date for update;
    if coalesce(v_count,0)>=10 then return false; end if;
    update public.casino_daily_activity a set spirit_stone_ticket_count=a.spirit_stone_ticket_count+1,updated_at=now()
    where a.character_id=p_character_id and a.activity_date=current_date;
  elsif p_stake_type='cultivation' then
    select a.cultivation_ticket_count into v_count from public.casino_daily_activity a
    where a.character_id=p_character_id and a.activity_date=current_date for update;
    if coalesce(v_count,0)>=10 then return false; end if;
    update public.casino_daily_activity a set cultivation_ticket_count=a.cultivation_ticket_count+1,updated_at=now()
    where a.character_id=p_character_id and a.activity_date=current_date;
  else
    raise exception 'CASINO_INVALID_STAKE_TYPE';
  end if;
  insert into public.casino_tickets(stake_type,round_ends_at,character_id,ticket_count)
  values(p_stake_type,v_round_ends_at,p_character_id,1)
  on conflict(stake_type,round_ends_at,character_id)
  do update set ticket_count=least(10,public.casino_tickets.ticket_count+1),updated_at=now();
  return true;
end;
$$;

create or replace function public.casino_expire_open_duels_v1()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  d record;
  v_expiry integer:=coalesce((select s.open_expiry_seconds from public.casino_settings s where s.singleton_id=1),1800);
  v_count integer:=0;
begin
  for d in
    select * from public.casino_duels x
    where x.status='open' and x.created_at<=now()-make_interval(secs=>v_expiry)
    for update skip locked
  loop
    perform public.casino_credit_v1(d.creator_character_id,d.stake_type,d.stake_amount);
    update public.casino_duels x
    set status='cancelled',cancelled_at=now(),settled_at=now(),cancellation_reason='OPEN_TABLE_EXPIRED',
        result_text='三十分钟无人应局，赌契自行散去，赌注已原数返还。',updated_at=now()
    where x.id=d.id;
    v_count:=v_count+1;
  end loop;
  return v_count;
end;
$$;

create or replace function public.casino_settle_duels_v1()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  d record;
  v_result integer;
  v_fee bigint;
  v_prize bigint;
  v_winner uuid;
  v_loser uuid;
  v_creator_name text;
  v_opponent_name text;
  v_result_text text;
  v_drop jsonb;
  v_count integer:=0;
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
      v_result_text:=format('五分钟已尽，无相阵盘同时显出【%s】。双方同招，灵力相抵，此局流局，赌注原数奉还。',public.casino_choice_name_v1(d.game_code,d.creator_choice));
      update public.casino_duels x
      set status='draw',fee_amount=0,prize_amount=0,settled_at=now(),result_text=v_result_text,updated_at=now()
      where x.id=d.id;
    else
      v_winner:=case when v_result=1 then d.creator_character_id else d.opponent_character_id end;
      v_loser:=case when v_result=1 then d.opponent_character_id else d.creator_character_id end;
      v_fee:=(d.stake_amount*2*5)/100;
      v_prize:=d.stake_amount*2-v_fee;
      update public.casino_pools p set amount=p.amount+v_fee,updated_at=now() where p.stake_type=d.stake_type;
      perform public.casino_credit_v1(v_winner,d.stake_type,v_prize);
      if d.stake_type='cultivation' then v_drop:=public.casino_realign_after_loss_v1(v_loser); end if;
      perform public.casino_add_ticket_v1(d.creator_character_id,d.stake_type);
      perform public.casino_add_ticket_v1(d.opponent_character_id,d.stake_type);
      v_result_text:=format(
        '五分钟已尽，无相阵盘开契：%s施展【%s】，%s施展【%s】。%s胜出，获得%s%s；公证费用%s%s已尽数汇入造化彩池。%s',
        coalesce(v_creator_name,'创建者'),public.casino_choice_name_v1(d.game_code,d.creator_choice),
        coalesce(v_opponent_name,'应局者'),public.casino_choice_name_v1(d.game_code,d.opponent_choice),
        case when v_result=1 then coalesce(v_creator_name,'创建者') else coalesce(v_opponent_name,'应局者') end,
        v_prize,case when d.stake_type='cultivation' then '点修为' else '枚灵石' end,
        v_fee,case when d.stake_type='cultivation' then '点修为' else '枚灵石' end,
        case when d.stake_type='cultivation' and coalesce((v_drop->>'stage_changed')::boolean,false)
          then format(' 败者境界由【%s】跌至【%s】，但未跌出当前大境界。',v_drop->>'stage_before_name',v_drop->>'stage_after_name') else '' end
      );
      update public.casino_duels x
      set status='settled',winner_character_id=v_winner,fee_amount=v_fee,prize_amount=v_prize,
          settled_at=now(),result_text=v_result_text,updated_at=now()
      where x.id=d.id;
    end if;
    v_count:=v_count+1;
  end loop;
  return v_count;
end;
$$;

create or replace function public.casino_draw_pools_v1()
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  p record;
  v_winner uuid;
  v_winner_name text;
  v_tickets integer:=0;
  v_interval integer:=coalesce((select s.draw_interval_seconds from public.casino_settings s where s.singleton_id=1),7200);
  v_result_text text;
  v_count integer:=0;
begin
  for p in select * from public.casino_pools x where x.next_draw_at<=now() for update skip locked loop
    select t.character_id into v_winner
    from public.casino_tickets t
    join public.player_characters pc on pc.id=t.character_id and pc.status in ('active','secluded','missing')
    cross join lateral generate_series(1,t.ticket_count) g(n)
    where t.stake_type=p.stake_type and t.round_ends_at=p.next_draw_at
    order by random()
    limit 1;
    select coalesce(sum(t.ticket_count),0)::integer into v_tickets
    from public.casino_tickets t
    where t.stake_type=p.stake_type and t.round_ends_at=p.next_draw_at;

    if v_winner is not null and p.amount>0 then
      perform public.casino_credit_v1(v_winner,p.stake_type,p.amount);
      select pc.name into v_winner_name from public.player_characters pc where pc.id=v_winner;
      v_result_text:=format('万运博弈楼钟鸣九响，【%s】手中造化签无火自燃，独得本期%s造化池：%s%s。',
        coalesce(v_winner_name,'无名修士'),case when p.stake_type='cultivation' then '修为' else '灵石' end,
        p.amount,case when p.stake_type='cultivation' then '点修为' else '枚灵石' end);
      insert into public.casino_draws(stake_type,round_ended_at,winner_character_id,prize_amount,ticket_count,result_text)
      values(p.stake_type,p.next_draw_at,v_winner,p.amount,v_tickets,v_result_text);
      update public.casino_pools x
      set amount=0,last_draw_at=now(),last_winner_character_id=v_winner,last_prize=p.amount,
          next_draw_at=now()+make_interval(secs=>v_interval),updated_at=now()
      where x.stake_type=p.stake_type;
      v_count:=v_count+1;
    else
      update public.casino_pools x
      set last_draw_at=now(),next_draw_at=now()+make_interval(secs=>v_interval),updated_at=now()
      where x.stake_type=p.stake_type;
    end if;
    delete from public.casino_tickets t where t.stake_type=p.stake_type and t.round_ends_at=p.next_draw_at;
  end loop;
  return v_count;
end;
$$;

create or replace function public.casino_process_v1()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_expired integer;v_settled integer;v_drawn integer;
begin
  v_expired:=public.casino_expire_open_duels_v1();
  v_settled:=public.casino_settle_duels_v1();
  v_drawn:=public.casino_draw_pools_v1();
  return jsonb_build_object('expired',v_expired,'settled',v_settled,'drawn',v_drawn);
end;
$$;

create or replace function public.get_market_v1()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_character_id uuid;
  v_stones bigint:=0;
  v_cultivation_available bigint:=0;
  v_major_order smallint;
  v_stage_name text;
  v_activity jsonb:='{}'::jsonb;
  v_enabled boolean;
begin
  perform public.casino_process_v1();
  v_character_id:=public.casino_current_character_id_v1();
  select s.enabled into v_enabled from public.casino_settings s where s.singleton_id=1;
  v_stones:=public.casino_available_v1(v_character_id,'spirit_stone');
  v_cultivation_available:=public.casino_available_v1(v_character_id,'cultivation');
  select r.major_order,rs.stage_name into v_major_order,v_stage_name
  from public.player_characters pc join public.realm_stages rs on rs.id=pc.realm_stage_id join public.realms r on r.id=rs.realm_id
  where pc.id=v_character_id;
  select to_jsonb(a) into v_activity from public.casino_daily_activity a
  where a.character_id=v_character_id and a.activity_date=current_date;

  return jsonb_build_object(
    'status',case when v_enabled then 'active' else 'disabled' end,
    'settings',(select jsonb_build_object('reveal_delay_seconds',s.reveal_delay_seconds,'open_expiry_seconds',s.open_expiry_seconds,'draw_interval_seconds',s.draw_interval_seconds) from public.casino_settings s where s.singleton_id=1),
    'character',jsonb_build_object(
      'stage_name',v_stage_name,'major_order',v_major_order,'cultivation_eligible',v_major_order>=public.casino_nascent_major_order_v1(),
      'spirit_stones',v_stones,'cultivation_available',v_cultivation_available,'cultivation_max_stake',floor(v_cultivation_available*0.20)::bigint
    ),
    'activity',coalesce(v_activity,jsonb_build_object('house_count',0,'duel_count',0,'cultivation_count',0,'total_count',0,'spirit_stone_ticket_count',0,'cultivation_ticket_count',0)),
    'pools',(select jsonb_object_agg(p.stake_type,jsonb_build_object(
      'amount',p.amount,'next_draw_at',p.next_draw_at,'seconds_remaining',greatest(0,extract(epoch from p.next_draw_at-now()))::integer,
      'last_prize',p.last_prize,'last_winner_name',pc.name
    )) from public.casino_pools p left join public.player_characters pc on pc.id=p.last_winner_character_id),
    'tickets',(select jsonb_object_agg(p.stake_type,coalesce(t.ticket_count,0))
      from public.casino_pools p left join public.casino_tickets t
      on t.stake_type=p.stake_type and t.round_ends_at=p.next_draw_at and t.character_id=v_character_id),
    'latest_draws',(select coalesce(jsonb_agg(x.obj order by x.created_at desc),'[]'::jsonb) from (
      select d.created_at,jsonb_build_object('stake_type',d.stake_type,'prize_amount',d.prize_amount,'winner_name',pc.name,'result_text',d.result_text,'created_at',d.created_at) obj
      from public.casino_draws d left join public.player_characters pc on pc.id=d.winner_character_id
      order by d.created_at desc limit 5
    ) x),
    'open_duels',(select coalesce(jsonb_agg(x.obj order by x.created_at desc),'[]'::jsonb) from (
      select d.created_at,jsonb_build_object(
        'id',d.id,'creator_name',pc.name,'game_code',d.game_code,'stake_type',d.stake_type,'stake_amount',d.stake_amount,
        'expires_in',greatest(0,extract(epoch from (d.created_at+make_interval(secs=>s.open_expiry_seconds))-now()))::integer
      ) obj
      from public.casino_duels d join public.player_characters pc on pc.id=d.creator_character_id
      cross join public.casino_settings s
      where d.status='open' and d.creator_character_id<>v_character_id
      order by d.created_at desc limit 30
    ) x),
    'my_duels',(select coalesce(jsonb_agg(x.obj order by x.created_at desc),'[]'::jsonb) from (
      select d.created_at,jsonb_build_object(
        'id',d.id,'game_code',d.game_code,'status',d.status,
        'status_name',case d.status when 'open' then '等待应局' when 'sealed' then '赌契封存中' when 'settled' then '胜负已分' when 'draw' then '流局' when 'cancelled' then '已取消' else d.status end,
        'stake_type',d.stake_type,'stake_amount',d.stake_amount,'fee_amount',d.fee_amount,'prize_amount',d.prize_amount,
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
set search_path = public, pg_temp
as $$
declare
  v_character_id uuid;
  v_fee bigint;
  v_effective bigint;
  v_roll integer;
  v_won boolean:=false;
  v_net_odds integer:=1;
  v_reward bigint:=0;
  v_result_text text;
  v_d1 integer;v_d2 integer;v_d3 integer;v_total integer;
  v_debit jsonb;
  v_drop jsonb;
  v_ticket boolean;
  v_result_payload jsonb;
begin
  perform public.casino_assert_enabled_v1();
  perform public.casino_process_v1();
  if p_game_code not in ('spirit_dice','turtle_oracle') then raise exception 'CASINO_INVALID_HOUSE_GAME'; end if;
  if not public.casino_validate_choice_v1(p_game_code,p_choice) then raise exception 'CASINO_INVALID_CHOICE'; end if;
  v_character_id:=public.casino_current_character_id_v1();
  perform public.casino_record_activity_v1(v_character_id,'house',p_stake_type);
  v_debit:=public.casino_debit_v1(v_character_id,p_stake_type,p_stake_amount,'house',p_game_code);
  v_fee:=(p_stake_amount*5)/100;
  v_effective:=p_stake_amount-v_fee;
  update public.casino_pools p set amount=p.amount+v_fee,updated_at=now() where p.stake_type=p_stake_type;

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
    v_reward:=v_effective*(1+v_net_odds);
    perform public.casino_credit_v1(v_character_id,p_stake_type,v_reward);
  elsif p_stake_type='cultivation' then
    v_drop:=public.casino_realign_after_loss_v1(v_character_id);
    if coalesce((v_drop->>'stage_changed')::boolean,false) then
      v_result_text:=v_result_text||format(' 你的境界由【%s】跌至【%s】，但大道根基未失，未跌出当前大境界。',v_drop->>'stage_before_name',v_drop->>'stage_after_name');
    end if;
  end if;
  v_ticket:=public.casino_add_ticket_v1(v_character_id,p_stake_type);
  v_result_text:=v_result_text||format(' 本局公证费用%s%s已全部汇入造化彩池。%s',v_fee,
    case when p_stake_type='cultivation' then '点修为' else '枚灵石' end,
    case when v_ticket then ' 你获得一张本期造化签。' else ' 今日该类造化签已达十张上限。' end);

  insert into public.casino_house_games(character_id,game_code,stake_type,stake_amount,choice_code,outcome_code,reward_amount,fee_amount,result_payload,result_text)
  values(v_character_id,p_game_code,p_stake_type,p_stake_amount,p_choice,case when v_won then 'win' else 'loss' end,v_reward,v_fee,v_result_payload,v_result_text);

  return jsonb_build_object('won',v_won,'reward',v_reward,'fee',v_fee,'ticket_awarded',v_ticket,'result_text',v_result_text,'drop',v_drop);
end;
$$;

create or replace function public.create_duel_v1(p_game_code text,p_stake_type text,p_stake_amount bigint,p_choice text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_character_id uuid;
  v_duel_id uuid;
begin
  perform public.casino_assert_enabled_v1();
  perform public.casino_process_v1();
  if p_game_code not in ('spirit_fist','five_elements') then raise exception 'CASINO_INVALID_DUEL_GAME'; end if;
  if not public.casino_validate_choice_v1(p_game_code,p_choice) then raise exception 'CASINO_INVALID_CHOICE'; end if;
  v_character_id:=public.casino_current_character_id_v1();
  perform pg_advisory_xact_lock(hashtextextended('casino:'||v_character_id::text,120));
  if exists(select 1 from public.casino_duels d where d.status in ('open','sealed') and v_character_id in(d.creator_character_id,d.opponent_character_id)) then
    raise exception 'CASINO_ACTIVE_DUEL_EXISTS';
  end if;
  perform public.casino_record_activity_v1(v_character_id,'duel',p_stake_type);
  perform public.casino_debit_v1(v_character_id,p_stake_type,p_stake_amount,'duel',p_game_code);
  insert into public.casino_duels(creator_character_id,game_code,stake_type,stake_amount,creator_choice,status)
  values(v_character_id,p_game_code,p_stake_type,p_stake_amount,p_choice,'open') returning id into v_duel_id;
  return jsonb_build_object('success',true,'duel_id',v_duel_id,'content','招式已封入无相阵盘。三十分钟内若无人应局，赌契将自行散去并原数返还。');
end;
$$;

create or replace function public.join_duel_v1(p_duel_id uuid,p_choice text)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_character_id uuid;
  d public.casino_duels;
  v_reveal_seconds integer:=coalesce((select s.reveal_delay_seconds from public.casino_settings s where s.singleton_id=1),300);
  v_reveal_at timestamptz;
begin
  perform public.casino_assert_enabled_v1();
  perform public.casino_process_v1();
  v_character_id:=public.casino_current_character_id_v1();
  perform pg_advisory_xact_lock(hashtextextended('casino:'||v_character_id::text,120));
  select * into d from public.casino_duels x where x.id=p_duel_id for update;
  if d.id is null or d.status<>'open' then raise exception 'DUEL_NOT_AVAILABLE'; end if;
  if d.creator_character_id=v_character_id then raise exception 'DUEL_OWN_TABLE'; end if;
  if not public.casino_validate_choice_v1(d.game_code,p_choice) then raise exception 'CASINO_INVALID_CHOICE'; end if;
  if exists(select 1 from public.casino_duels x where x.status in('open','sealed') and v_character_id in(x.creator_character_id,x.opponent_character_id)) then
    raise exception 'CASINO_ACTIVE_DUEL_EXISTS';
  end if;
  perform public.casino_record_activity_v1(v_character_id,'duel',d.stake_type);
  perform public.casino_debit_v1(v_character_id,d.stake_type,d.stake_amount,'duel',d.game_code);
  v_reveal_at:=now()+make_interval(secs=>v_reveal_seconds);
  update public.casino_duels x
  set opponent_character_id=v_character_id,opponent_choice=p_choice,status='sealed',reveal_at=v_reveal_at,updated_at=now()
  where x.id=d.id;
  return jsonb_build_object('success',true,'reveal_at',v_reveal_at,'content','双方招式已收入无相阵盘，五分钟后统一开契，一局定胜负。');
end;
$$;

create or replace function public.cancel_duel_v1(p_duel_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_character_id uuid;
  d public.casino_duels;
begin
  v_character_id:=public.casino_current_character_id_v1();
  select * into d from public.casino_duels x where x.id=p_duel_id for update;
  if d.id is null or d.creator_character_id<>v_character_id or d.status<>'open' then raise exception 'DUEL_CANNOT_CANCEL'; end if;
  perform public.casino_credit_v1(d.creator_character_id,d.stake_type,d.stake_amount);
  update public.casino_duels x
  set status='cancelled',cancelled_at=now(),settled_at=now(),cancellation_reason='CREATOR_CANCELLED',
      result_text='你主动散去了尚未有人应局的赌契，赌注已原数返还。',updated_at=now()
  where x.id=d.id;
  return jsonb_build_object('success',true,'content','赌契已散，赌注原数返还。');
end;
$$;

-- 清除V0.12.0初稿遗留的危险辅助函数；这些函数曾因默认PUBLIC执行权限而可能被直接调用。
drop function if exists public.settle_casino_duels_v1();
drop function if exists public.casino_debit(uuid,text,bigint);
drop function if exists public.casino_available(uuid,text);
drop function if exists public.casino_credit(uuid,text,bigint);
drop function if exists public.casino_result(text,text,text);
drop function if exists public.casino_stone_item_id();
drop function if exists public.casino_character();

-- 所有内部函数必须私有。
revoke all on function public.casino_assert_enabled_v1() from public,anon,authenticated;
revoke all on function public.casino_current_character_id_v1() from public,anon,authenticated;
revoke all on function public.casino_stone_item_id_v1() from public,anon,authenticated;
revoke all on function public.casino_nascent_major_order_v1() from public,anon,authenticated;
revoke all on function public.casino_available_v1(uuid,text) from public,anon,authenticated;
revoke all on function public.casino_validate_choice_v1(text,text) from public,anon,authenticated;
revoke all on function public.casino_choice_name_v1(text,text) from public,anon,authenticated;
revoke all on function public.casino_result_v1(text,text,text) from public,anon,authenticated;
revoke all on function public.casino_debit_v1(uuid,text,bigint,text,text) from public,anon,authenticated;
revoke all on function public.casino_credit_v1(uuid,text,bigint) from public,anon,authenticated;
revoke all on function public.casino_realign_after_loss_v1(uuid) from public,anon,authenticated;
revoke all on function public.casino_assert_activity_allowed_v1(uuid,text,text) from public,anon,authenticated;
revoke all on function public.casino_record_activity_v1(uuid,text,text) from public,anon,authenticated;
revoke all on function public.casino_add_ticket_v1(uuid,text) from public,anon,authenticated;
revoke all on function public.casino_expire_open_duels_v1() from public,anon,authenticated;
revoke all on function public.casino_settle_duels_v1() from public,anon,authenticated;
revoke all on function public.casino_draw_pools_v1() from public,anon,authenticated;
revoke all on function public.casino_process_v1() from public,anon,authenticated;

-- 仅开放五个玩家RPC。
revoke all on function public.get_market_v1() from public,anon,authenticated;
revoke all on function public.play_house_game_v1(text,text,bigint,text) from public,anon,authenticated;
revoke all on function public.create_duel_v1(text,text,bigint,text) from public,anon,authenticated;
revoke all on function public.join_duel_v1(uuid,text) from public,anon,authenticated;
revoke all on function public.cancel_duel_v1(uuid) from public,anon,authenticated;
grant execute on function public.get_market_v1() to authenticated;
grant execute on function public.play_house_game_v1(text,text,bigint,text) to authenticated;
grant execute on function public.create_duel_v1(text,text,bigint,text) to authenticated;
grant execute on function public.join_duel_v1(uuid,text) to authenticated;
grant execute on function public.cancel_duel_v1(uuid) to authenticated;

comment on table public.casino_pools is 'V0.12.0 FIX1：5%公证费用100%进入灵石/修为造化彩池，每两小时懒触发开奖。';
comment on table public.casino_duels is 'V0.12.0 FIX1：玩家暗选招式，第二人应局后五分钟统一揭晓，一局定胜负。';

commit;
