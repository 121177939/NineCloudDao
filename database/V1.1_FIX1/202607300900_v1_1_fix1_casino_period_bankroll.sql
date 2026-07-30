-- 九霄问道 V1.1 FIX1 CACHE36
-- 赌场周期资金、公平概率、30%单局上限、玩家庄100:97.5与70%奖池结算。
--
-- 正式规则：
-- 1. 系统庄每两小时独立一期；灵石期初资金固定1亿，修为期初资金固定10亿。
-- 2. 每期结束前一分钟停止全部赌场新下注；不限制每日场次与连续游玩次数。
-- 3. 本期正利润的50%加入对应造化池；亏损或零利润时不入池、不开奖。
-- 4. 造化池沿用旧等权候选规则；中奖者领取开奖前池余额70%，其余滚存。
-- 5. 单局下注总额不得超过该局开始时可用资源30%；鱼虾灵局按同一公共轮次累计。
-- 6. 玩家庄100:97.5，2.5%平台费进入赌场资金；不直接进入奖池；庄家自赔，系统零兜底。
-- 7. 灵骰采用三颗独立公平骰：小4-10、大11-17，任意豹子独立投注，豹子通吃大小。
-- 8. 系统赔率：灵骰大小100赔95、任意豹子100赔3320；龟卜平100赔90、吉凶100赔280；鱼虾1/2/3中100赔106/210/320。

begin;

-- ---------------------------------------------------------------------------
-- 1. 配置与资金表
-- ---------------------------------------------------------------------------
alter table public.casino_settings
  add column if not exists casino_period_seconds integer not null default 7200,
  add column if not exists casino_close_before_seconds integer not null default 60,
  add column if not exists casino_profit_pool_bps integer not null default 5000,
  add column if not exists casino_spirit_stone_target bigint not null default 100000000,
  add column if not exists casino_cultivation_target bigint not null default 1000000000,
  add column if not exists system_dice_side_profit_bps integer not null default 9500,
  add column if not exists system_dice_triple_profit_bps integer not null default 332000,
  add column if not exists system_turtle_neutral_profit_bps integer not null default 9000,
  add column if not exists system_turtle_edge_profit_bps integer not null default 28000,
  add column if not exists system_fish_one_profit_bps integer not null default 10600,
  add column if not exists system_fish_two_profit_bps integer not null default 21000,
  add column if not exists system_fish_three_profit_bps integer not null default 32000;

update public.casino_settings
set house_stake_limit_bps=3000,
    player_house_win_commission_bps=250,
    casino_period_seconds=7200,
    casino_close_before_seconds=60,
    casino_profit_pool_bps=5000,
    casino_spirit_stone_target=100000000,
    casino_cultivation_target=1000000000,
    system_dice_side_profit_bps=9500,
    system_dice_triple_profit_bps=332000,
    system_turtle_neutral_profit_bps=9000,
    system_turtle_edge_profit_bps=28000,
    system_fish_one_profit_bps=10600,
    system_fish_two_profit_bps=21000,
    system_fish_three_profit_bps=32000,
    draw_interval_seconds=7200,
    updated_at=now()
where singleton_id=1;

do $$
begin
  if not exists(select 1 from pg_constraint where conname='casino_settings_period_fix1_check') then
    alter table public.casino_settings add constraint casino_settings_period_fix1_check check(
      casino_period_seconds=7200 and casino_close_before_seconds=60 and casino_profit_pool_bps=5000
      and casino_spirit_stone_target=100000000 and casino_cultivation_target=1000000000
      and house_stake_limit_bps=3000 and player_house_win_commission_bps=250
      and system_dice_side_profit_bps=9500 and system_dice_triple_profit_bps=332000
      and system_turtle_neutral_profit_bps=9000 and system_turtle_edge_profit_bps=28000
      and system_fish_one_profit_bps=10600 and system_fish_two_profit_bps=21000 and system_fish_three_profit_bps=32000
    );
  end if;
end;
$$;

create table if not exists public.casino_bankroll_v1 (
  stake_type text primary key check(stake_type in('spirit_stone','cultivation')),
  target_amount bigint not null check(target_amount>0),
  balance bigint not null check(balance>=0),
  period_started_at timestamptz not null,
  betting_closes_at timestamptz not null,
  period_ends_at timestamptz not null,
  last_period_profit bigint not null default 0,
  last_pool_allocation bigint not null default 0,
  last_retained_profit bigint not null default 0,
  last_reset_adjustment bigint not null default 0,
  updated_at timestamptz not null default now(),
  constraint casino_bankroll_period_order_v1 check(period_started_at<betting_closes_at and betting_closes_at<period_ends_at)
);

create table if not exists public.casino_bankroll_ledger_v1 (
  id bigint generated always as identity primary key,
  stake_type text not null check(stake_type in('spirit_stone','cultivation')),
  amount bigint not null,
  balance_after bigint not null check(balance_after>=0),
  entry_type text not null,
  reference_id uuid,
  period_ends_at timestamptz not null,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists casino_bankroll_ledger_period_v1 on public.casino_bankroll_ledger_v1(stake_type,period_ends_at,created_at);

create table if not exists public.casino_bankroll_periods_v1 (
  id bigint generated always as identity primary key,
  stake_type text not null check(stake_type in('spirit_stone','cultivation')),
  period_started_at timestamptz not null,
  period_ended_at timestamptz not null,
  opening_balance bigint not null,
  closing_balance bigint not null,
  gross_profit bigint not null,
  pool_allocation bigint not null default 0 check(pool_allocation>=0),
  retained_profit bigint not null default 0 check(retained_profit>=0),
  reset_adjustment bigint not null default 0,
  pool_prize bigint not null default 0 check(pool_prize>=0),
  did_draw boolean not null default false,
  created_at timestamptz not null default now(),
  unique(stake_type,period_ended_at)
);

create table if not exists public.casino_round_stake_usage_v1 (
  round_key uuid not null,
  character_id uuid not null references public.player_characters(id) on delete cascade,
  game_code text not null,
  stake_type text not null check(stake_type in('spirit_stone','cultivation')),
  resource_before bigint not null check(resource_before>=0),
  max_stake bigint not null check(max_stake>=0),
  used_stake bigint not null default 0 check(used_stake>=0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(round_key,character_id,game_code,stake_type),
  constraint casino_round_stake_usage_cap_v1 check(used_stake<=max_stake)
);

alter table public.casino_fish_bets_v0148
  add column if not exists system_reserved_amount bigint not null default 0;
do $$
begin
  if not exists(select 1 from pg_constraint where conname='casino_fish_system_reserve_nonnegative_fix1') then
    alter table public.casino_fish_bets_v0148 add constraint casino_fish_system_reserve_nonnegative_fix1 check(system_reserved_amount>=0);
  end if;
end;
$$;

alter table public.casino_house_games
  add column if not exists bankroll_delta bigint not null default 0,
  add column if not exists bankroll_balance_after bigint,
  add column if not exists payout_bps integer not null default 0,
  add column if not exists bankroll_period_ends_at timestamptz;

alter table public.casino_bankroll_v1 enable row level security;
alter table public.casino_bankroll_ledger_v1 enable row level security;
alter table public.casino_bankroll_periods_v1 enable row level security;
alter table public.casino_round_stake_usage_v1 enable row level security;
revoke all on table public.casino_bankroll_v1 from public,anon,authenticated;
revoke all on table public.casino_bankroll_ledger_v1 from public,anon,authenticated;
revoke all on table public.casino_bankroll_periods_v1 from public,anon,authenticated;
revoke all on table public.casino_round_stake_usage_v1 from public,anon,authenticated;

-- 升级时完整保留旧奖池与已有候选；第一期从部署时刻起计两小时。
do $$
declare
  v_start timestamptz:=clock_timestamp();
  v_end timestamptz:=clock_timestamp()+interval '2 hours';
  v_close timestamptz;
begin
  v_close:=v_end-interval '1 minute';
  insert into public.casino_bankroll_v1(stake_type,target_amount,balance,period_started_at,betting_closes_at,period_ends_at)
  values
    ('spirit_stone',100000000,100000000,v_start,v_close,v_end),
    ('cultivation',1000000000,1000000000,v_start,v_close,v_end)
  on conflict(stake_type) do update
  set target_amount=excluded.target_amount,balance=excluded.balance,period_started_at=excluded.period_started_at,
      betting_closes_at=excluded.betting_closes_at,period_ends_at=excluded.period_ends_at,
      last_period_profit=0,last_pool_allocation=0,last_retained_profit=0,last_reset_adjustment=0,updated_at=now();

  insert into public.casino_tickets(stake_type,round_ends_at,character_id,ticket_count,updated_at)
  select stake_type,v_end,character_id,1,now()
  from public.casino_tickets
  group by stake_type,character_id
  on conflict(stake_type,round_ends_at,character_id) do update set ticket_count=1,updated_at=now();
  delete from public.casino_tickets where round_ends_at<>v_end;
  update public.casino_pools set next_draw_at=v_end,updated_at=now();
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. 安全随机、资金账本与30%累计下注
-- ---------------------------------------------------------------------------
create or replace function public.casino_secure_random_int_v1(p_upper integer)
returns integer
language plpgsql
volatile
security definer
set search_path=public,pg_temp
as $$
declare
  v_bytes bytea;
  v_raw bigint;
  v_range constant bigint:=4294967296;
  v_limit bigint;
begin
  if p_upper is null or p_upper<1 then raise exception 'CASINO_RANDOM_UPPER_INVALID'; end if;
  v_limit:=(v_range/p_upper::bigint)*p_upper::bigint;
  loop
    v_bytes:=gen_random_bytes(4);
    v_raw:=get_byte(v_bytes,0)::bigint*16777216
          +get_byte(v_bytes,1)::bigint*65536
          +get_byte(v_bytes,2)::bigint*256
          +get_byte(v_bytes,3)::bigint;
    if v_raw<v_limit then return (v_raw%p_upper)::integer; end if;
  end loop;
end;
$$;

create or replace function public.casino_bankroll_available_v1(p_stake_type text)
returns bigint
language plpgsql
stable
security definer
set search_path=public,pg_temp
as $$
declare v_balance bigint:=0;v_reserved bigint:=0;
begin
  select balance into v_balance from public.casino_bankroll_v1 where stake_type=p_stake_type;
  if v_balance is null then raise exception 'CASINO_BANKROLL_MISSING'; end if;
  select coalesce(sum(system_reserved_amount),0)::bigint into v_reserved
  from public.casino_fish_bets_v0148
  where house_mode='system' and stake_type=p_stake_type and not is_settled;
  return greatest(0,v_balance-v_reserved);
end;
$$;

create or replace function public.casino_bankroll_apply_v1(
  p_stake_type text,p_amount bigint,p_entry_type text,p_reference_id uuid default null,p_detail jsonb default '{}'::jsonb
)
returns bigint
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_row public.casino_bankroll_v1%rowtype;v_after bigint;
begin
  if p_stake_type not in('spirit_stone','cultivation') then raise exception 'CASINO_INVALID_STAKE_TYPE'; end if;
  if p_amount is null then raise exception 'CASINO_BANKROLL_AMOUNT_REQUIRED'; end if;
  select * into v_row from public.casino_bankroll_v1 where stake_type=p_stake_type for update;
  if v_row.stake_type is null then raise exception 'CASINO_BANKROLL_MISSING'; end if;
  if p_amount>0 and v_row.balance>9223372036854775807-p_amount then raise exception 'CASINO_BANKROLL_OVERFLOW'; end if;
  v_after:=v_row.balance+p_amount;
  if v_after<0 then raise exception 'CASINO_BANKROLL_INSUFFICIENT'; end if;
  update public.casino_bankroll_v1 set balance=v_after,updated_at=now() where stake_type=p_stake_type;
  insert into public.casino_bankroll_ledger_v1(stake_type,amount,balance_after,entry_type,reference_id,period_ends_at,detail)
  values(p_stake_type,p_amount,v_after,coalesce(p_entry_type,'unknown'),p_reference_id,v_row.period_ends_at,coalesce(p_detail,'{}'::jsonb));
  return v_after;
end;
$$;

create or replace function public.casino_claim_round_stake_v1(
  p_round_key uuid,p_character_id uuid,p_game_code text,p_stake_type text,p_available_before bigint,p_amount bigint
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_row public.casino_round_stake_usage_v1%rowtype;v_cap bigint;
begin
  if p_round_key is null then raise exception 'CASINO_ROUND_REQUIRED'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'CASINO_INVALID_STAKE_AMOUNT'; end if;
  v_cap:=greatest(0,floor(greatest(0,p_available_before)::numeric*0.30)::bigint);
  insert into public.casino_round_stake_usage_v1(round_key,character_id,game_code,stake_type,resource_before,max_stake,used_stake)
  values(p_round_key,p_character_id,p_game_code,p_stake_type,greatest(0,p_available_before),v_cap,0)
  on conflict(round_key,character_id,game_code,stake_type) do nothing;
  select * into v_row from public.casino_round_stake_usage_v1
  where round_key=p_round_key and character_id=p_character_id and game_code=p_game_code and stake_type=p_stake_type
  for update;
  if v_row.used_stake+p_amount>v_row.max_stake then raise exception 'CASINO_STAKE_EXCEEDS_THIRTY_PERCENT'; end if;
  update public.casino_round_stake_usage_v1
  set used_stake=used_stake+p_amount,updated_at=now()
  where round_key=p_round_key and character_id=p_character_id and game_code=p_game_code and stake_type=p_stake_type
  returning * into v_row;
  return to_jsonb(v_row);
end;
$$;

create or replace function public.casino_house_stake_limit_v1(p_character_id uuid,p_stake_type text)
returns bigint
language plpgsql
stable
security definer
set search_path=public,pg_temp
as $$
declare v_available bigint:=0;
begin
  v_available:=public.casino_available_v1(p_character_id,p_stake_type);
  return greatest(0,floor(v_available::numeric*0.30)::bigint);
end;
$$;

-- 保留修为境界保底，只把大堂单局上限改为30%。
create or replace function public.casino_debit_v1(
  p_character_id uuid,p_stake_type text,p_amount bigint,p_context text,p_game_code text
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_balance bigint:=0;v_cultivation bigint:=0;v_floor bigint:=0;v_available bigint:=0;v_minimum bigint:=0;
  v_house_limit bigint:=0;v_major_order smallint;v_stage_id smallint;v_stage_name text;
begin
  if p_amount is null or p_amount<=0 then raise exception 'CASINO_INVALID_STAKE_AMOUNT';end if;
  if p_amount>9007199254740991 then raise exception 'CASINO_STAKE_TOO_LARGE';end if;
  if p_context not in('house','duel') then raise exception 'CASINO_INVALID_CONTEXT';end if;
  if p_stake_type='spirit_stone' then
    if p_amount<10 then raise exception 'CASINO_STAKE_BELOW_MINIMUM';end if;
    v_balance:=public.spirit_stone_balance_v0141(p_character_id);
    if p_context='house' and p_amount>public.casino_house_stake_limit_v1(p_character_id,'spirit_stone') then raise exception 'CASINO_STAKE_EXCEEDS_THIRTY_PERCENT';end if;
    if v_balance<p_amount then raise exception 'CASINO_INSUFFICIENT_SPIRIT_STONES';end if;
    perform public.spirit_stone_debit_v0141(p_character_id,p_amount,'CASINO_INSUFFICIENT_SPIRIT_STONES');
    return jsonb_build_object('stake_type',p_stake_type,'amount',p_amount,'available_before',v_balance,'available_after',v_balance-p_amount);
  elsif p_stake_type='cultivation' then
    select pc.cultivation,pc.realm_stage_id,rs.stage_name,r.major_order,coalesce(rs.cultivation_required,0)
    into v_cultivation,v_stage_id,v_stage_name,v_major_order,v_floor
    from public.player_characters pc join public.realm_stages rs on rs.id=pc.realm_stage_id
    join public.realms r on r.id=rs.realm_id where pc.id=p_character_id for update of pc;
    if v_stage_id is null then raise exception 'NO_ACTIVE_CHARACTER';end if;
    if v_major_order<public.casino_nascent_major_order_v1() then raise exception 'CASINO_CULTIVATION_REQUIRES_NASCENT_SOUL';end if;
    v_available:=greatest(0,v_cultivation-v_floor);
    if v_available<=0 then raise exception 'CASINO_INSUFFICIENT_CULTIVATION';end if;
    if p_context='house' then
      v_house_limit:=public.casino_house_stake_limit_v1(p_character_id,'cultivation');
      v_minimum:=least(50000,greatest(1,v_house_limit));
      if p_amount>v_house_limit then raise exception 'CASINO_STAKE_EXCEEDS_THIRTY_PERCENT';end if;
    else
      v_minimum:=least(50000,v_available);
    end if;
    if p_amount<v_minimum then raise exception 'CULTIVATION_STAKE_MINIMUM';end if;
    if p_amount>v_available then raise exception 'CASINO_INSUFFICIENT_CULTIVATION';end if;
    update public.player_characters set cultivation=greatest(v_floor,cultivation-p_amount),updated_at=now() where id=p_character_id;
    return jsonb_build_object('stake_type',p_stake_type,'amount',p_amount,'available_before',v_available,'available_after',v_available-p_amount,
      'cultivation_before',v_cultivation,'cultivation_after',greatest(v_floor,v_cultivation-p_amount),
      'stage_before_id',v_stage_id,'stage_before_name',v_stage_name,'stage_after_id',v_stage_id,'stage_after_name',v_stage_name,
      'major_order',v_major_order,'stage_floor',v_floor,'realm_locked',true);
  end if;
  raise exception 'CASINO_INVALID_STAKE_TYPE';
end;
$$;

-- 旧奖票规则：同一角色、同一资源、同一期仅作为一个等权候选；重复游玩不增加抽中权重。
create or replace function public.casino_add_ticket_v1(p_character_id uuid,p_stake_type text)
returns boolean
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_round_ends_at timestamptz;v_inserted integer:=0;
begin
  select next_draw_at into v_round_ends_at from public.casino_pools where stake_type=p_stake_type for update;
  if v_round_ends_at is null then return false; end if;
  insert into public.casino_tickets(stake_type,round_ends_at,character_id,ticket_count,updated_at)
  values(p_stake_type,v_round_ends_at,p_character_id,1,now())
  on conflict(stake_type,round_ends_at,character_id) do update set ticket_count=1,updated_at=now();
  get diagnostics v_inserted=row_count;
  return v_inserted>0;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. 公平开奖模型
-- ---------------------------------------------------------------------------
create or replace function public.casino_validate_choice_v1(p_game_code text,p_choice text)
returns boolean
language sql
immutable
security definer
set search_path=public,pg_temp
as $$
  select case
    when p_game_code='spirit_fist' then p_choice in('rock','scissors','paper')
    when p_game_code='five_elements' then p_choice in('metal','wood','earth','water','fire')
    when p_game_code='spirit_dice' then p_choice in('big','small','triple')
    when p_game_code='turtle_oracle' then p_choice in('auspicious','neutral','ominous')
    else false end;
$$;

create or replace function public.casino_draw_house_result_fix1(p_game_code text,p_choice text)
returns jsonb
language plpgsql
volatile
security definer
set search_path=public,pg_temp
as $$
declare
  v_d1 integer;v_d2 integer;v_d3 integer;v_total integer;v_is_triple boolean;v_side text;
  v_roll integer;v_result text;v_won boolean:=false;v_system_profit_bps integer:=0;v_player_gross_odds integer:=0;
  v_text text;v_payload jsonb;
begin
  if p_game_code not in('spirit_dice','turtle_oracle') then raise exception 'CASINO_INVALID_HOUSE_GAME'; end if;
  if not public.casino_validate_choice_v1(p_game_code,p_choice) then raise exception 'CASINO_INVALID_CHOICE'; end if;
  if p_game_code='spirit_dice' then
    v_d1:=public.casino_secure_random_int_v1(6)+1;
    v_d2:=public.casino_secure_random_int_v1(6)+1;
    v_d3:=public.casino_secure_random_int_v1(6)+1;
    v_total:=v_d1+v_d2+v_d3;
    v_is_triple:=v_d1=v_d2 and v_d2=v_d3;
    v_side:=case when v_is_triple then 'triple' when v_total between 4 and 10 then 'small' else 'big' end;
    v_won:=p_choice=v_side;
    if p_choice='triple' then
      select system_dice_triple_profit_bps into v_system_profit_bps from public.casino_settings where singleton_id=1;
      v_player_gross_odds:=35;
    else
      select system_dice_side_profit_bps into v_system_profit_bps from public.casino_settings where singleton_id=1;
      v_player_gross_odds:=1;
    end if;
    v_text:=format('三枚灵骰显出【%s、%s、%s】，合计%s点，结果为【%s】。%s',v_d1,v_d2,v_d3,v_total,
      case v_side when 'small' then '小' when 'big' then '大' else '豹子' end,
      case when v_won then '你押中了。' else '此局与你所押不合。' end);
    v_payload:=jsonb_build_object('dice',jsonb_build_array(v_d1,v_d2,v_d3),'total',v_total,'choice',p_choice,
      'result_side',v_side,'result_kind',case when v_is_triple then 'triple' else 'normal' end,'is_triple',v_is_triple,
      'triple_auto_side',false,'result_independent_of_choice',true,'probability_model','three_independent_fair_dice');
  else
    v_roll:=public.casino_secure_random_int_v1(100);
    v_result:=case when v_roll<25 then 'auspicious' when v_roll<75 then 'neutral' else 'ominous' end;
    v_won:=p_choice=v_result;
    if p_choice='neutral' then
      select system_turtle_neutral_profit_bps into v_system_profit_bps from public.casino_settings where singleton_id=1;
      v_player_gross_odds:=1;
    else
      select system_turtle_edge_profit_bps into v_system_profit_bps from public.casino_settings where singleton_id=1;
      v_player_gross_odds:=3;
    end if;
    v_text:=case v_result
      when 'auspicious' then '灵火骤明，龟甲裂纹如灵芝舒展，显出【吉】象。'
      when 'neutral' then '龟甲裂纹横竖相抵，灵火归静，显出【平】象。'
      else '龟甲中央崩开深纹，黑烟盘旋，显出【凶】象。' end;
    v_text:=v_text||case when v_won then ' 你押中了。' else ' 此局与你所押不合。' end;
    v_payload:=jsonb_build_object('choice',p_choice,'result',v_result,'probability_model','25_50_25_secure');
  end if;
  return jsonb_build_object('won',v_won,'system_profit_bps',v_system_profit_bps,
    'player_gross_odds',v_player_gross_odds,'net_odds',v_player_gross_odds,
    'result_text',v_text,'result_payload',v_payload);
end;
$$;

create or replace function public.casino_player_house_draw_result_v1(p_game_code text,p_choice text)
returns jsonb
language sql
volatile
security definer
set search_path=public,pg_temp
as $$ select public.casino_draw_house_result_fix1(p_game_code,p_choice) $$;

-- ---------------------------------------------------------------------------
-- 4. 周期奖池与固定资金重置
-- ---------------------------------------------------------------------------
create or replace function public.casino_pool_draw_fix1(p_stake_type text,p_round_end timestamptz,p_allow_draw boolean)
returns bigint
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_pool public.casino_pools%rowtype;v_candidates uuid[];v_participants integer:=0;v_pick integer;v_candidate uuid;
  v_name text;v_target bigint:=0;v_granted bigint:=0;v_rollover bigint:=0;v_credit jsonb;v_text text;
begin
  select * into v_pool from public.casino_pools where stake_type=p_stake_type for update;
  if v_pool.stake_type is null then raise exception 'CASINO_POOL_MISSING'; end if;
  select array_agg(character_id order by character_id::text),count(*)::integer
  into v_candidates,v_participants
  from public.casino_tickets where stake_type=p_stake_type and round_ends_at=p_round_end;
  v_participants:=coalesce(v_participants,0);

  if p_allow_draw and v_participants>0 and v_pool.amount>0 then
    v_pick:=public.casino_secure_random_int_v1(v_participants)+1;
    v_candidate:=v_candidates[v_pick];
    select name into v_name from public.player_characters where id=v_candidate;
    v_target:=floor(v_pool.amount::numeric*0.70)::bigint;
    if v_target>0 then
      v_credit:=public.casino_credit_result_v0141(v_candidate,p_stake_type,v_target);
      v_granted:=coalesce((v_credit->>'granted_amount')::bigint,0);
    end if;
    v_rollover:=greatest(0,v_pool.amount-v_granted);
    v_text:=format('本期赌场形成正利润，从%s名等权候选中抽出【%s】；其领取开奖前奖池的70%%上限，共%s%s，剩余%s%s滚存。',
      v_participants,coalesce(v_name,'无名修士'),v_granted,case when p_stake_type='cultivation' then '点修为' else '枚灵石' end,
      v_rollover,case when p_stake_type='cultivation' then '点修为' else '枚灵石' end);
    insert into public.casino_draws(stake_type,round_ended_at,winner_character_id,candidate_character_id,prize_amount,pool_amount,ticket_count,did_hit,hit_chance,result_text)
    values(p_stake_type,p_round_end,case when v_granted>0 then v_candidate else null end,v_candidate,v_granted,v_pool.amount,v_participants,true,1.00000,v_text);
    update public.casino_pools set amount=v_rollover,last_draw_at=now(),last_winner_character_id=case when v_granted>0 then v_candidate else null end,
      last_prize=v_granted,last_draw_hit=true,last_candidate_character_id=v_candidate,last_ticket_count=v_participants,updated_at=now()
    where stake_type=p_stake_type;
  else
    v_text:=case
      when not p_allow_draw then '本期赌场未形成正利润，不向奖池分配资金且不开奖；原奖池余额全部滚存。'
      when v_participants=0 then '本期没有有效等权候选，不开奖；原奖池余额全部滚存。'
      else '本期奖池余额不足1单位，不开奖；余额继续滚存。' end;
    insert into public.casino_draws(stake_type,round_ended_at,winner_character_id,candidate_character_id,prize_amount,pool_amount,ticket_count,did_hit,hit_chance,result_text)
    values(p_stake_type,p_round_end,null,null,0,v_pool.amount,v_participants,false,0.00000,v_text);
    update public.casino_pools set last_draw_at=now(),last_winner_character_id=null,last_prize=0,last_draw_hit=false,
      last_candidate_character_id=null,last_ticket_count=v_participants,updated_at=now() where stake_type=p_stake_type;
  end if;
  delete from public.casino_tickets where stake_type=p_stake_type and round_ends_at=p_round_end;
  return v_granted;
end;
$$;

create or replace function public.casino_settle_bankroll_periods_v1()
returns integer
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_row public.casino_bankroll_v1%rowtype;v_profit bigint;v_allocation bigint;v_retained bigint;v_prize bigint;
  v_after_allocation bigint;v_reset bigint;v_next_start timestamptz;v_next_end timestamptz;v_count integer:=0;v_due record;
begin
  perform pg_advisory_xact_lock(hashtextextended('casino-bankroll-period-fix1',11136));
  perform public.casino_expire_open_duels_v1();
  perform public.casino_settle_duels_v1();
  for v_due in select id from public.casino_fish_rounds_v0148 where not is_settled and settles_at<=now() order by settles_at limit 200
  loop perform public.casino_fish_settle_round_v0148(v_due.id); end loop;

  loop
    select * into v_row from public.casino_bankroll_v1
    where period_ends_at<=clock_timestamp()
    order by period_ends_at,stake_type limit 1 for update;
    exit when not found;
    v_profit:=v_row.balance-v_row.target_amount;
    v_allocation:=case when v_profit>0 then floor(v_profit::numeric*0.50)::bigint else 0 end;
    v_retained:=case when v_profit>0 then v_profit-v_allocation else 0 end;
    if v_allocation>0 then
      perform public.casino_bankroll_apply_v1(v_row.stake_type,-v_allocation,'period_pool_allocation',null,
        jsonb_build_object('period_ended_at',v_row.period_ends_at,'gross_profit',v_profit,'allocation_bps',5000));
      update public.casino_pools set amount=amount+v_allocation,updated_at=now() where stake_type=v_row.stake_type;
    end if;
    v_prize:=public.casino_pool_draw_fix1(v_row.stake_type,v_row.period_ends_at,v_profit>0);
    select balance into v_after_allocation from public.casino_bankroll_v1 where stake_type=v_row.stake_type;
    v_reset:=v_row.target_amount-v_after_allocation;
    if v_reset<>0 then
      perform public.casino_bankroll_apply_v1(v_row.stake_type,v_reset,'period_fixed_reset',null,
        jsonb_build_object('period_ended_at',v_row.period_ends_at,'fixed_target',v_row.target_amount,'historical_loss_compensation',false));
    end if;
    insert into public.casino_bankroll_periods_v1(stake_type,period_started_at,period_ended_at,opening_balance,closing_balance,
      gross_profit,pool_allocation,retained_profit,reset_adjustment,pool_prize,did_draw)
    values(v_row.stake_type,v_row.period_started_at,v_row.period_ends_at,v_row.target_amount,v_row.balance,v_profit,
      v_allocation,v_retained,v_reset,v_prize,v_prize>0)
    on conflict(stake_type,period_ended_at) do nothing;
    v_next_start:=v_row.period_ends_at;v_next_end:=v_next_start+interval '2 hours';
    update public.casino_bankroll_v1 set target_amount=case when stake_type='spirit_stone' then 100000000 else 1000000000 end,
      balance=case when stake_type='spirit_stone' then 100000000 else 1000000000 end,
      period_started_at=v_next_start,betting_closes_at=v_next_end-interval '1 minute',period_ends_at=v_next_end,
      last_period_profit=v_profit,last_pool_allocation=v_allocation,last_retained_profit=v_retained,last_reset_adjustment=v_reset,updated_at=now()
    where stake_type=v_row.stake_type;
    update public.casino_pools set next_draw_at=v_next_end,updated_at=now() where stake_type=v_row.stake_type;
    v_count:=v_count+1;
  end loop;
  return v_count;
end;
$$;

create or replace function public.casino_assert_enabled_v1()
returns void
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_close timestamptz;v_end timestamptz;
begin
  select min(betting_closes_at),min(period_ends_at) into v_close,v_end from public.casino_bankroll_v1;
  if v_end is null or clock_timestamp()>=v_end then
    perform public.casino_settle_bankroll_periods_v1();
    select min(betting_closes_at),min(period_ends_at) into v_close,v_end from public.casino_bankroll_v1;
  end if;
  if not coalesce((select enabled from public.casino_settings where singleton_id=1),false) then raise exception 'MARKET_DISABLED'; end if;
  if clock_timestamp()>=v_close and clock_timestamp()<v_end then raise exception 'CASINO_PERIOD_CLOSED'; end if;
end;
$$;

create or replace function public.casino_period_status_v1()
returns jsonb
language sql
stable
security definer
set search_path=public,pg_temp
as $$
  select jsonb_build_object(
    'period_started_at',min(period_started_at),'betting_closes_at',min(betting_closes_at),'period_ends_at',min(period_ends_at),
    'seconds_to_close',greatest(0,extract(epoch from min(betting_closes_at)-clock_timestamp())::integer),
    'seconds_to_reset',greatest(0,extract(epoch from min(period_ends_at)-clock_timestamp())::integer),
    'betting_open',clock_timestamp()<min(betting_closes_at),
    'rule','two_hours_fixed_bankroll_close_one_minute_before'
  ) from public.casino_bankroll_v1;
$$;

-- ---------------------------------------------------------------------------
-- 5. 系统庄即时玩法
-- ---------------------------------------------------------------------------
create or replace function public.play_system_house_game_v0141_fix7a(
  p_game_code text,p_stake_type text,p_stake_amount bigint,p_choice text
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_character_id uuid;v_draw jsonb;v_won boolean;v_profit_bps integer;v_profit bigint:=0;v_payout bigint:=0;
  v_credit jsonb;v_granted bigint:=0;v_ticket boolean;v_payload jsonb;v_text text;v_bankroll bigint;v_period_end timestamptz;
  v_max_bps integer;v_max_payout bigint;
begin
  perform public.casino_assert_enabled_v1();
  if p_game_code not in('spirit_dice','turtle_oracle') then raise exception 'CASINO_INVALID_HOUSE_GAME'; end if;
  if not public.casino_validate_choice_v1(p_game_code,p_choice) then raise exception 'CASINO_INVALID_CHOICE'; end if;
  v_character_id:=public.casino_current_character_id_v1();
  v_max_bps:=case
    when p_game_code='spirit_dice' and p_choice='triple' then 332000
    when p_game_code='spirit_dice' then 9500
    when p_game_code='turtle_oracle' and p_choice='neutral' then 9000
    else 28000 end;
  v_max_payout:=p_stake_amount+floor(p_stake_amount::numeric*v_max_bps/10000)::bigint;
  -- 锁定对应赌场资金行，保证“受理前偿付检查”与本局结算原子一致；不同资源可并行。
  perform 1 from public.casino_bankroll_v1 where stake_type=p_stake_type for update;
  if public.casino_bankroll_available_v1(p_stake_type)+p_stake_amount<v_max_payout then raise exception 'CASINO_BANKROLL_INSUFFICIENT'; end if;
  perform public.casino_record_activity_v1(v_character_id,'house',p_stake_type);
  perform public.casino_debit_v1(v_character_id,p_stake_type,p_stake_amount,'house',p_game_code);
  v_bankroll:=public.casino_bankroll_apply_v1(p_stake_type,p_stake_amount,'system_bet_received',null,
    jsonb_build_object('character_id',v_character_id,'game_code',p_game_code,'choice',p_choice));
  v_draw:=public.casino_draw_house_result_fix1(p_game_code,p_choice);
  v_won:=coalesce((v_draw->>'won')::boolean,false);v_profit_bps:=coalesce((v_draw->>'system_profit_bps')::integer,0);
  if v_won then
    v_profit:=floor(p_stake_amount::numeric*v_profit_bps/10000)::bigint;
    v_payout:=p_stake_amount+v_profit;
    v_credit:=public.casino_credit_result_v0141(v_character_id,p_stake_type,v_payout);
    v_granted:=coalesce((v_credit->>'granted_amount')::bigint,0);
    v_bankroll:=public.casino_bankroll_apply_v1(p_stake_type,-v_granted,'system_win_payout',null,
      jsonb_build_object('character_id',v_character_id,'game_code',p_game_code,'choice',p_choice,'requested_payout',v_payout));
  elsif p_stake_type='cultivation' then
    perform public.casino_realign_after_loss_v1(v_character_id);
  end if;
  v_ticket:=public.casino_add_ticket_v1(v_character_id,p_stake_type);
  select period_ends_at into v_period_end from public.casino_bankroll_v1 where stake_type=p_stake_type;
  v_payload:=coalesce(v_draw->'result_payload','{}'::jsonb)||jsonb_build_object(
    'house_mode','system','stake_type',p_stake_type,'payout_bps',v_profit_bps,'gross_profit',v_profit,
    'actual_reward',v_granted,'pool_contribution',0,'bankroll_balance_after',v_bankroll,'bankroll_period_ends_at',v_period_end,
    'settlement_rule','fixed_bankroll_profit_share_no_direct_pool','settlement_version','V1.1_FIX1');
  v_text:=v_draw->>'result_text';
  v_text:=v_text||case when v_won then format(' 本金返还并净赢%s%s；本局不直接抽入奖池，赌场两小时正利润的50%%统一入池。',v_profit,
    case when p_stake_type='cultivation' then '点修为' else '枚灵石' end)
    else format(' 本局损失%s%s，全部进入赌场资金。',p_stake_amount,case when p_stake_type='cultivation' then '点修为' else '枚灵石' end) end;
  insert into public.casino_house_games(character_id,game_code,stake_type,stake_amount,choice_code,outcome_code,reward_amount,
    nominal_reward_amount,fee_amount,pool_contribution,heaven_recovery_amount,result_payload,result_text,house_mode,
    dealer_debit_amount,dealer_credit_amount,max_liability_amount,system_cover_amount,settlement_version,
    bankroll_delta,bankroll_balance_after,payout_bps,bankroll_period_ends_at)
  values(v_character_id,p_game_code,p_stake_type,p_stake_amount,p_choice,case when v_won then 'win' else 'loss' end,
    v_granted,v_payout,0,0,0,v_payload,v_text,'system',0,0,v_max_payout,0,'V1.1_FIX1',
    p_stake_amount-v_granted,v_bankroll,v_profit_bps,v_period_end);
  return jsonb_build_object('won',v_won,'reward',v_granted,'nominal_reward',v_payout,'gross_profit',v_profit,
    'net_profit',case when v_won then v_granted-p_stake_amount else -p_stake_amount end,'fee',0,'pool_contribution',0,
    'ticket_awarded',v_ticket,'house_mode','system','result_text',v_text,'result_payload',v_payload,'drop',null);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. 玩家庄即时玩法：100:97.5、零系统兜底
-- ---------------------------------------------------------------------------
create or replace function public.casino_play_player_house_v1_fix4(
  p_dealer_character_id uuid,p_game_code text,p_stake_type text,p_stake_amount bigint,p_choice text,p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_bettor uuid:=public.casino_current_character_id_v1();v_dealer_name text;v_bettor_balance bigint;v_dealer_balance bigint;v_dealer_after bigint;
  v_limit bigint;v_draw jsonb;v_won boolean;v_gross_odds integer;v_gross bigint:=0;v_fee bigint:=0;v_profit bigint:=0;v_reward bigint:=0;
  v_max_liability bigint;v_dealer_debit bigint:=0;v_dealer_credit bigint:=0;v_bankroll bigint;v_payload jsonb;v_text text;
begin
  perform public.casino_assert_enabled_v1();
  if p_request_id is null then raise exception 'CASINO_REQUEST_ID_REQUIRED';end if;
  if p_dealer_character_id is null or public.casino_player_house_resolve_dealer_v1() is distinct from p_dealer_character_id then raise exception 'CASINO_PLAYER_HOUSE_NOT_ACTIVE';end if;
  if p_game_code not in('spirit_dice','turtle_oracle') or not public.casino_validate_choice_v1(p_game_code,p_choice) then raise exception 'CASINO_INVALID_CHOICE';end if;
  if p_stake_type<>'spirit_stone' then raise exception 'CASINO_PLAYER_HOUSE_ONLY_SPIRIT_STONE';end if;
  if p_stake_amount is null or p_stake_amount<40 or mod(p_stake_amount,40)<>0 then raise exception 'CASINO_PLAYER_HOUSE_STAKE_MULTIPLE_40';end if;
  if v_bettor=p_dealer_character_id then raise exception 'CASINO_PLAYER_HOUSE_SELF_BET_FORBIDDEN';end if;
  if v_bettor::text<p_dealer_character_id::text then
    perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||v_bettor::text,141));
    perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||p_dealer_character_id::text,141));
  else
    perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||p_dealer_character_id::text,141));
    perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||v_bettor::text,141));
  end if;
  v_bettor_balance:=public.spirit_stone_balance_v0141(v_bettor);v_dealer_balance:=public.spirit_stone_balance_v0141(p_dealer_character_id);
  v_limit:=floor(v_bettor_balance::numeric*0.30)::bigint;
  if p_stake_amount>v_limit then raise exception 'CASINO_STAKE_EXCEEDS_THIRTY_PERCENT';end if;
  v_max_liability:=p_stake_amount*case when p_game_code='spirit_dice' and p_choice='triple' then 35 when p_game_code='turtle_oracle' and p_choice<>'neutral' then 3 else 1 end;
  if v_dealer_balance<v_max_liability then raise exception 'CASINO_PLAYER_HOUSE_DEALER_INSUFFICIENT';end if;
  select name into v_dealer_name from public.player_characters where id=p_dealer_character_id;
  perform public.casino_record_activity_v1(v_bettor,'house','spirit_stone');
  perform public.casino_debit_v1(v_bettor,'spirit_stone',p_stake_amount,'house',p_game_code);
  v_draw:=public.casino_draw_house_result_fix1(p_game_code,p_choice);v_won:=coalesce((v_draw->>'won')::boolean,false);
  v_gross_odds:=coalesce((v_draw->>'player_gross_odds')::integer,0);
  if v_won then
    v_gross:=p_stake_amount*v_gross_odds;v_fee:=floor(v_gross::numeric*0.025)::bigint;v_profit:=v_gross-v_fee;
    perform public.spirit_stone_debit_v0141(p_dealer_character_id,v_gross,'CASINO_PLAYER_HOUSE_DEALER_INSUFFICIENT');
    perform public.award_spirit_stones_v3(v_bettor,p_stake_amount+v_profit);
    v_reward:=p_stake_amount+v_profit;v_dealer_debit:=v_gross;
  else
    v_fee:=floor(p_stake_amount::numeric*0.025)::bigint;v_dealer_credit:=p_stake_amount-v_fee;
    if v_dealer_credit>0 then perform public.award_spirit_stones_v3(p_dealer_character_id,v_dealer_credit);end if;
  end if;
  if v_fee>0 then v_bankroll:=public.casino_bankroll_apply_v1('spirit_stone',v_fee,'player_house_fee',p_request_id,
    jsonb_build_object('bettor_character_id',v_bettor,'dealer_character_id',p_dealer_character_id,'game_code',p_game_code));
  else select balance into v_bankroll from public.casino_bankroll_v1 where stake_type='spirit_stone';end if;
  v_dealer_after:=public.spirit_stone_balance_v0141(p_dealer_character_id);
  v_payload:=coalesce(v_draw->'result_payload','{}'::jsonb)||jsonb_build_object('house_mode','player','dealer_name',coalesce(v_dealer_name,'玩家庄'),
    'gross_profit',v_gross,'platform_fee',v_fee,'player_net_profit',case when v_won then v_profit else -p_stake_amount end,
    'actual_reward',v_reward,'pool_contribution',0,'dealer_debit_amount',v_dealer_debit,'dealer_credit_amount',v_dealer_credit,
    'system_cover_amount',0,'max_liability_amount',v_max_liability,'request_id',p_request_id,
    'bankroll_balance_after',v_bankroll,'settlement_rule','player_house_97_5_fee_to_bankroll_no_cover','settlement_version','V1.1_FIX1');
  v_text:=format('玩家庄【%s】：%s %s',coalesce(v_dealer_name,'无名庄家'),v_draw->>'result_text',
    case when v_won then format('闲家净赢%s枚灵石，平台费%s枚进入赌场资金；庄家承担全部%s枚毛利润，系统不兜底。',v_profit,v_fee,v_gross)
    else format('闲家损失%s枚灵石；庄家实得%s枚，平台费%s枚进入赌场资金，系统不兜底。',p_stake_amount,v_dealer_credit,v_fee) end);
  insert into public.casino_house_games(character_id,game_code,stake_type,stake_amount,choice_code,outcome_code,reward_amount,nominal_reward_amount,
    fee_amount,pool_contribution,heaven_recovery_amount,result_payload,result_text,house_mode,dealer_character_id,dealer_name_snapshot,
    dealer_debit_amount,dealer_credit_amount,max_liability_amount,system_cover_amount,request_id,settlement_version,
    bankroll_delta,bankroll_balance_after,payout_bps,bankroll_period_ends_at)
  select v_bettor,p_game_code,'spirit_stone',p_stake_amount,p_choice,case when v_won then 'win' else 'loss' end,v_reward,
    case when v_won then p_stake_amount+v_gross else 0 end,v_fee,0,0,v_payload,v_text,'player',p_dealer_character_id,coalesce(v_dealer_name,'玩家庄'),
    v_dealer_debit,v_dealer_credit,v_max_liability,0,p_request_id,'V1.1_FIX1',v_fee,v_bankroll,9750,period_ends_at
  from public.casino_bankroll_v1 where stake_type='spirit_stone';
  return jsonb_build_object('won',v_won,'reward',v_reward,'nominal_reward',case when v_won then p_stake_amount+v_gross else 0 end,
    'gross_profit',v_gross,'net_profit',case when v_won then v_profit else -p_stake_amount end,'fee',v_fee,'pool_contribution',0,
    'ticket_awarded',false,'house_mode','player','dealer_name',coalesce(v_dealer_name,'玩家庄'),'dealer_debit_amount',v_dealer_debit,
    'dealer_credit_amount',v_dealer_credit,'system_cover_amount',0,'max_liability_amount',v_max_liability,
    'result_text',v_text,'result_payload',v_payload,'drop',null);
end;
$$;

create or replace function public.casino_play_player_house_v1(
  p_dealer_character_id uuid,p_game_code text,p_stake_type text,p_stake_amount bigint,p_choice text
) returns jsonb language sql security definer set search_path=public,pg_temp as $$
  select public.casino_play_player_house_v1_fix4(p_dealer_character_id,p_game_code,p_stake_type,p_stake_amount,p_choice,gen_random_uuid())
$$;

create or replace function public.play_house_game_v1_fix4(
  p_request_id uuid,p_house_mode text,p_game_code text,p_stake_type text,p_stake_amount bigint,p_choice text
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_character uuid:=public.casino_current_character_id_v1();v_request public.casino_bet_requests_v1%rowtype;v_result jsonb;
  v_before bigint;v_after bigint;v_limit bigint;v_dealer uuid;v_game_id uuid;
begin
  if p_request_id is null then raise exception 'CASINO_REQUEST_ID_REQUIRED';end if;
  if p_house_mode not in('system','player') then raise exception 'CASINO_INVALID_HOUSE_MODE';end if;
  perform pg_advisory_xact_lock(hashtextextended('casino-request:'||v_character::text||':'||p_request_id::text,104));
  select * into v_request from public.casino_bet_requests_v1 where character_id=v_character and request_id=p_request_id;
  if found then
    if v_request.game_code is distinct from p_game_code or v_request.house_mode is distinct from p_house_mode
      or v_request.stake_type is distinct from p_stake_type or v_request.stake_amount is distinct from p_stake_amount
      or v_request.choice_code is distinct from p_choice then raise exception 'CASINO_REQUEST_PARAMETER_MISMATCH';end if;
    if v_request.status='settled' and v_request.result_payload is not null then return v_request.result_payload;end if;
    raise exception 'CASINO_REQUEST_IN_PROGRESS';
  end if;
  if not pg_try_advisory_xact_lock(hashtextextended('casino-house-character:'||v_character::text,104)) then raise exception 'CASINO_REQUEST_IN_PROGRESS';end if;
  perform public.casino_assert_enabled_v1();
  v_before:=public.casino_available_v1(v_character,p_stake_type);v_limit:=floor(v_before::numeric*0.30)::bigint;
  if p_stake_amount is null or p_stake_amount<1 or p_stake_amount>v_limit then raise exception 'CASINO_STAKE_EXCEEDS_THIRTY_PERCENT';end if;
  insert into public.casino_bet_requests_v1(request_id,character_id,game_code,house_mode,stake_type,stake_amount,choice_code,resource_before,settlement_version)
  values(p_request_id,v_character,p_game_code,p_house_mode,p_stake_type,p_stake_amount,p_choice,v_before,'V1.1_FIX1');
  if p_house_mode='system' then
    v_result:=public.play_system_house_game_v0141_fix7a(p_game_code,p_stake_type,p_stake_amount,p_choice);
    select id into v_game_id from public.casino_house_games where character_id=v_character and request_id is null order by created_at desc,id desc limit 1 for update;
    if v_game_id is not null then update public.casino_house_games set request_id=p_request_id,settlement_version='V1.1_FIX1' where id=v_game_id;end if;
  else
    if p_stake_type<>'spirit_stone' then raise exception 'CASINO_PLAYER_HOUSE_ONLY_SPIRIT_STONE';end if;
    perform pg_advisory_xact_lock(hashtextextended('casino-player-house-dealer',14301));
    v_dealer:=public.casino_player_house_resolve_dealer_v1();
    if v_dealer is null then raise exception 'CASINO_PLAYER_HOUSE_NOT_ACTIVE';end if;
    v_result:=public.casino_play_player_house_v1_fix4(v_dealer,p_game_code,p_stake_type,p_stake_amount,p_choice,p_request_id);
  end if;
  v_after:=public.casino_available_v1(v_character,p_stake_type);
  update public.casino_bet_requests_v1 set status='settled',resource_after=v_after,result_payload=v_result,settlement_version='V1.1_FIX1',settled_at=now()
  where character_id=v_character and request_id=p_request_id;
  return v_result;
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. 鱼虾灵局：安全随机、30%轮次累计、系统固定赔率、玩家庄自赔
-- ---------------------------------------------------------------------------
create or replace function public.casino_fish_create_round_v0148(p_round_no bigint)
returns uuid
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_id uuid;v_start timestamptz;v_symbols constant text[]:=array['fish','shrimp','crab','coin','gourd','frog'];v_result text[];
begin
  if p_round_no is null or p_round_no<1 then raise exception 'FISH_ROUND_INVALID';end if;
  perform pg_advisory_xact_lock(hashtextextended('fish-round:'||p_round_no::text,148));
  select id into v_id from public.casino_fish_rounds_v0148 where round_no=p_round_no;
  if v_id is not null then return v_id;end if;
  v_start:=to_timestamp(p_round_no*40);
  v_result:=array[v_symbols[public.casino_secure_random_int_v1(6)+1],v_symbols[public.casino_secure_random_int_v1(6)+1],v_symbols[public.casino_secure_random_int_v1(6)+1]];
  insert into public.casino_fish_rounds_v0148(round_no,starts_at,betting_closes_at,reveal_at,settles_at,ends_at,result_symbols)
  values(p_round_no,v_start,v_start+interval '30 seconds',v_start+interval '32 seconds',v_start+interval '37 seconds',v_start+interval '40 seconds',v_result)
  on conflict(round_no) do update set round_no=excluded.round_no returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.place_fish_shrimp_bet_v1_fix4(
  p_request_id uuid,p_house_mode text,p_stake_type text,p_symbol_code text,p_stake_amount bigint
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_character uuid:=public.casino_current_character_id_v1();v_request public.casino_bet_requests_v1%rowtype;v_before bigint;v_after bigint;
  v_round_id uuid;v_round public.casino_fish_rounds_v0148%rowtype;v_dealer uuid;v_dealer_name text;v_reserve bigint;v_system_reserve bigint;
  v_bankroll bigint;v_result jsonb;
begin
  if p_request_id is null then raise exception 'CASINO_REQUEST_ID_REQUIRED';end if;
  if p_house_mode not in('system','player') then raise exception 'FISH_INVALID_HOUSE_MODE';end if;
  if p_stake_type not in('spirit_stone','cultivation') then raise exception 'CASINO_INVALID_STAKE_TYPE';end if;
  if p_symbol_code not in('fish','shrimp','crab','coin','gourd','frog') then raise exception 'FISH_INVALID_SYMBOL';end if;
  if p_house_mode='player' and (p_stake_amount is null or p_stake_amount<40 or mod(p_stake_amount,40)<>0) then
    raise exception 'CASINO_PLAYER_HOUSE_STAKE_MULTIPLE_40';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('casino-request:'||v_character::text||':'||p_request_id::text,104));
  select * into v_request from public.casino_bet_requests_v1 where character_id=v_character and request_id=p_request_id;
  if found then
    if v_request.game_code is distinct from 'fish_shrimp' or v_request.house_mode is distinct from p_house_mode
      or v_request.stake_type is distinct from p_stake_type or v_request.stake_amount is distinct from p_stake_amount
      or v_request.choice_code is distinct from p_symbol_code then raise exception 'CASINO_REQUEST_PARAMETER_MISMATCH';end if;
    if v_request.status='settled' and v_request.result_payload is not null then return v_request.result_payload;end if;
    raise exception 'CASINO_REQUEST_IN_PROGRESS';
  end if;
  if not pg_try_advisory_xact_lock(hashtextextended('casino-house-character:'||v_character::text,104)) then raise exception 'CASINO_REQUEST_IN_PROGRESS';end if;
  perform public.casino_assert_enabled_v1();
  v_round_id:=public.casino_fish_ensure_round_v0148();select * into v_round from public.casino_fish_rounds_v0148 where id=v_round_id for share;
  if clock_timestamp()>=v_round.betting_closes_at then raise exception 'FISH_BETTING_CLOSED';end if;
  v_before:=public.casino_available_v1(v_character,p_stake_type);
  perform public.casino_claim_round_stake_v1(v_round_id,v_character,'fish_shrimp',p_stake_type,v_before,p_stake_amount);
  insert into public.casino_bet_requests_v1(request_id,character_id,game_code,house_mode,stake_type,stake_amount,choice_code,resource_before,settlement_version)
  values(p_request_id,v_character,'fish_shrimp',p_house_mode,p_stake_type,p_stake_amount,p_symbol_code,v_before,'V1.1_FIX1');
  if p_house_mode='system' then
    v_system_reserve:=p_stake_amount+floor(p_stake_amount::numeric*3.20)::bigint;
    -- 与下注入账、未结算责任登记共用同一资金行锁，防止并发超额受理。
    perform 1 from public.casino_bankroll_v1 where stake_type=p_stake_type for update;
    if public.casino_bankroll_available_v1(p_stake_type)+p_stake_amount<v_system_reserve then raise exception 'CASINO_BANKROLL_INSUFFICIENT';end if;
    perform public.casino_record_activity_v1(v_character,'house',p_stake_type);
    perform public.casino_debit_v1(v_character,p_stake_type,p_stake_amount,'house','fish_shrimp');
    v_bankroll:=public.casino_bankroll_apply_v1(p_stake_type,p_stake_amount,'system_fish_bet_received',p_request_id,
      jsonb_build_object('character_id',v_character,'round_id',v_round_id,'symbol',p_symbol_code));
    insert into public.casino_fish_bets_v0148(round_id,character_id,house_mode,stake_type,symbol_code,stake_amount,request_id,
      system_reserved_amount,settlement_version)
    values(v_round_id,v_character,'system',p_stake_type,p_symbol_code,p_stake_amount,p_request_id,v_system_reserve,'V1.1_FIX1');
  else
    if p_stake_type<>'spirit_stone' then raise exception 'CASINO_PLAYER_HOUSE_ONLY_SPIRIT_STONE';end if;
    perform pg_advisory_xact_lock(hashtextextended('casino-player-house-dealer',14301));
    v_dealer:=public.casino_player_house_resolve_dealer_v1();if v_dealer is null then raise exception 'CASINO_PLAYER_HOUSE_NOT_ACTIVE';end if;
    if v_dealer=v_character then raise exception 'CASINO_PLAYER_HOUSE_SELF_BET_FORBIDDEN';end if;
    if v_character::text<v_dealer::text then
      perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||v_character::text,141));perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||v_dealer::text,141));
    else
      perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||v_dealer::text,141));perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||v_character::text,141));
    end if;
    v_reserve:=p_stake_amount*3;
    if public.spirit_stone_balance_v0141(v_dealer)<v_reserve then raise exception 'CASINO_PLAYER_HOUSE_DEALER_INSUFFICIENT';end if;
    select name into v_dealer_name from public.player_characters where id=v_dealer;
    perform public.casino_record_activity_v1(v_character,'house','spirit_stone');
    perform public.casino_debit_v1(v_character,'spirit_stone',p_stake_amount,'house','fish_shrimp');
    perform public.spirit_stone_debit_v0141(v_dealer,v_reserve,'CASINO_PLAYER_HOUSE_DEALER_INSUFFICIENT');
    insert into public.casino_fish_bets_v0148(round_id,character_id,house_mode,dealer_character_id,dealer_name_snapshot,stake_type,symbol_code,
      stake_amount,request_id,dealer_reserved_amount,settlement_version)
    values(v_round_id,v_character,'player',v_dealer,coalesce(v_dealer_name,'玩家庄'),'spirit_stone',p_symbol_code,p_stake_amount,
      p_request_id,v_reserve,'V1.1_FIX1');
  end if;
  v_result:=public.get_fish_shrimp_state_v0148(20);v_after:=public.casino_available_v1(v_character,p_stake_type);
  update public.casino_bet_requests_v1 set status='settled',resource_after=v_after,result_payload=v_result,settlement_version='V1.1_FIX1',settled_at=now()
  where character_id=v_character and request_id=p_request_id;
  return v_result;
end;
$$;

create or replace function public.casino_fish_settle_round_v0148(p_round_id uuid)
returns boolean
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_round public.casino_fish_rounds_v0148%rowtype;v_bet public.casino_fish_bets_v0148%rowtype;v_count integer;v_profit_bps integer;
  v_profit bigint;v_payout bigint;v_granted bigint;v_credit jsonb;v_net bigint;v_fee bigint;v_gross bigint;
  v_dealer_debit bigint;v_dealer_credit bigint;v_dealer_refund bigint;v_bankroll bigint;v_ticket boolean;
begin
  if p_round_id is null then return false;end if;
  perform pg_advisory_xact_lock(hashtextextended('fish-settle:'||p_round_id::text,148));
  select * into v_round from public.casino_fish_rounds_v0148 where id=p_round_id for update;
  if v_round.id is null then return false;end if;if v_round.is_settled then return true;end if;if now()<v_round.settles_at then return false;end if;
  for v_bet in select * from public.casino_fish_bets_v0148 where round_id=p_round_id and not is_settled
    order by character_id::text,coalesce(dealer_character_id::text,''),created_at,id for update
  loop
    select count(*)::integer into v_count from unnest(v_round.result_symbols) s where s=v_bet.symbol_code;
    v_profit:=0;v_payout:=0;v_granted:=0;v_net:=-v_bet.stake_amount;v_fee:=0;v_gross:=0;
    v_dealer_debit:=0;v_dealer_credit:=0;v_dealer_refund:=0;
    if v_bet.house_mode='system' then
      if v_count>0 then
        select case v_count when 1 then system_fish_one_profit_bps when 2 then system_fish_two_profit_bps else system_fish_three_profit_bps end
        into v_profit_bps from public.casino_settings where singleton_id=1;
        v_profit:=floor(v_bet.stake_amount::numeric*v_profit_bps/10000)::bigint;v_payout:=v_bet.stake_amount+v_profit;
        v_credit:=public.casino_credit_result_v0141(v_bet.character_id,v_bet.stake_type,v_payout);v_granted:=coalesce((v_credit->>'granted_amount')::bigint,0);
        v_bankroll:=public.casino_bankroll_apply_v1(v_bet.stake_type,-v_granted,'system_fish_win_payout',v_bet.request_id,
          jsonb_build_object('round_id',p_round_id,'count',v_count,'requested_payout',v_payout));
        v_net:=v_granted-v_bet.stake_amount;
      elsif v_bet.stake_type='cultivation' then perform public.casino_realign_after_loss_v1(v_bet.character_id);end if;
      v_ticket:=public.casino_add_ticket_v1(v_bet.character_id,v_bet.stake_type);
    else
      if v_bet.dealer_character_id is null or v_bet.dealer_reserved_amount<v_bet.stake_amount*3 then raise exception 'CASINO_PLAYER_HOUSE_RESERVE_MISSING';end if;
      if v_count>0 then
        v_gross:=v_bet.stake_amount*v_count;v_fee:=floor(v_gross::numeric*0.025)::bigint;v_profit:=v_gross-v_fee;
        v_payout:=v_bet.stake_amount+v_profit;perform public.award_spirit_stones_v3(v_bet.character_id,v_payout);v_granted:=v_payout;v_net:=v_profit;
        v_dealer_debit:=v_gross;v_dealer_refund:=v_bet.dealer_reserved_amount-v_gross;
        if v_dealer_refund>0 then perform public.award_spirit_stones_v3(v_bet.dealer_character_id,v_dealer_refund);end if;
      else
        v_fee:=floor(v_bet.stake_amount::numeric*0.025)::bigint;v_dealer_credit:=v_bet.stake_amount-v_fee;v_dealer_refund:=v_bet.dealer_reserved_amount;
        perform public.award_spirit_stones_v3(v_bet.dealer_character_id,v_dealer_refund+v_dealer_credit);
      end if;
      if v_fee>0 then v_bankroll:=public.casino_bankroll_apply_v1('spirit_stone',v_fee,'player_house_fish_fee',v_bet.request_id,
        jsonb_build_object('round_id',p_round_id,'bettor_character_id',v_bet.character_id,'dealer_character_id',v_bet.dealer_character_id));end if;
    end if;
    update public.casino_fish_bets_v0148 set result_count=v_count,payout_amount=v_granted,net_profit=v_net,commission_amount=v_fee,
      pool_contribution=0,heaven_recovery=0,dealer_debit_amount=v_dealer_debit,dealer_credit_amount=v_dealer_credit,
      dealer_refund_amount=v_dealer_refund,system_cover_amount=0,outcome_code=case when v_count>0 then 'win' else 'loss' end,
      is_settled=true,settled_at=now(),settlement_version='V1.1_FIX1' where id=v_bet.id;
  end loop;
  update public.casino_fish_rounds_v0148 set is_settled=true,settled_at=now() where id=p_round_id;
  perform public.world_event_publish_fish_round_v0151(p_round_id);return true;
end;
$$;

-- ---------------------------------------------------------------------------
-- 8. 贵宾赌契费用进入赌场资金，不再直接入池
-- ---------------------------------------------------------------------------
create or replace function public.casino_settle_duels_v1()
returns integer
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  d record;v_result integer;v_fee bigint;v_prize_requested bigint;v_prize bigint;v_winner uuid;v_loser uuid;
  v_creator_name text;v_opponent_name text;v_winner_name text;v_credit jsonb;v_text text;v_drop jsonb;v_count integer:=0;
begin
  for d in select * from public.casino_duels where status='sealed' and reveal_at<=now() for update skip locked
  loop
    v_result:=public.casino_result_v1(d.game_code,d.creator_choice,d.opponent_choice);
    select name into v_creator_name from public.player_characters where id=d.creator_character_id;
    select name into v_opponent_name from public.player_characters where id=d.opponent_character_id;
    if v_result=0 then
      perform public.casino_credit_v1(d.creator_character_id,d.stake_type,d.stake_amount);
      perform public.casino_credit_v1(d.opponent_character_id,d.stake_type,d.stake_amount);
      v_text:=format('双方同出【%s】，此局流局，赌注原数返还。',public.casino_choice_name_v1(d.game_code,d.creator_choice));
      update public.casino_duels set status='draw',fee_amount=0,prize_amount=0,pool_contribution=0,heaven_recovery_amount=0,
        settled_at=now(),result_text=v_text,updated_at=now() where id=d.id;
    else
      v_winner:=case when v_result=1 then d.creator_character_id else d.opponent_character_id end;
      v_loser:=case when v_result=1 then d.opponent_character_id else d.creator_character_id end;
      v_winner_name:=case when v_result=1 then coalesce(v_creator_name,'创建者') else coalesce(v_opponent_name,'应局者') end;
      v_fee:=floor((d.stake_amount*2)::numeric*0.05)::bigint;v_prize_requested:=d.stake_amount*2-v_fee;
      v_credit:=public.casino_credit_result_v0141(v_winner,d.stake_type,v_prize_requested);v_prize:=coalesce((v_credit->>'granted_amount')::bigint,0);
      if v_fee>0 then perform public.casino_bankroll_apply_v1(d.stake_type,v_fee,'duel_platform_fee',d.id,
        jsonb_build_object('winner_character_id',v_winner,'loser_character_id',v_loser));end if;
      if d.stake_type='cultivation' then v_drop:=public.casino_realign_after_loss_v1(v_loser);end if;
      perform public.casino_add_ticket_v1(d.creator_character_id,d.stake_type);perform public.casino_add_ticket_v1(d.opponent_character_id,d.stake_type);
      v_text:=format('%s胜出，到账%s%s；5%%平台费%s%s进入赌场资金，待两小时正利润清算后再按50%%分配奖池。',v_winner_name,v_prize,
        case when d.stake_type='cultivation' then '点修为' else '枚灵石' end,v_fee,case when d.stake_type='cultivation' then '点修为' else '枚灵石' end);
      update public.casino_duels set status='settled',winner_character_id=v_winner,fee_amount=v_fee,prize_amount=v_prize,
        pool_contribution=0,heaven_recovery_amount=0,settled_at=now(),result_text=v_text,updated_at=now() where id=d.id;
    end if;
    v_count:=v_count+1;
  end loop;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- 9. 周期处理、市场状态与玩家庄状态
-- ---------------------------------------------------------------------------
create or replace function public.casino_draw_pools_v1()
returns integer
language plpgsql
security definer
set search_path=public,pg_temp
as $$ begin return public.casino_settle_bankroll_periods_v1(); end; $$;

create or replace function public.casino_process_v1()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_expired integer;v_settled integer;v_periods integer;v_due record;v_fish integer:=0;
begin
  v_expired:=public.casino_expire_open_duels_v1();v_settled:=public.casino_settle_duels_v1();
  for v_due in select id from public.casino_fish_rounds_v0148 where not is_settled and settles_at<=now() order by settles_at limit 200
  loop if public.casino_fish_settle_round_v0148(v_due.id) then v_fish:=v_fish+1;end if;end loop;
  v_periods:=public.casino_settle_bankroll_periods_v1();
  return jsonb_build_object('expired',v_expired,'settled',v_settled,'fish_settled',v_fish,'periods_closed',v_periods);
end;
$$;

create or replace function public.get_casino_player_house_status_v1()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_current uuid:=public.casino_current_character_id_v1();v_dealer uuid;v_current_wealth bigint;v_dealer_wealth bigint;v_name text;
  v_enabled boolean;v_min bigint;v_expires timestamptz;v_limit bigint;
begin
  v_dealer:=public.casino_player_house_resolve_dealer_v1();
  select player_house_enabled,player_house_min_wealth into v_enabled,v_min from public.casino_settings where singleton_id=1;
  v_current_wealth:=public.spirit_stone_balance_v0141(v_current);v_limit:=floor(v_current_wealth::numeric*0.30)::bigint;
  if v_dealer is not null then
    select name,public.spirit_stone_balance_v0141(id) into v_name,v_dealer_wealth from public.player_characters where id=v_dealer;
    select expires_at into v_expires from public.casino_player_house_state where singleton_id=1;
  end if;
  return jsonb_build_object('status','ok','mode',case when v_dealer is null then 'system' else 'player' end,
    'dealer_name',case when v_dealer is null then '荷老' else coalesce(v_name,'无名庄家') end,'dealer_wealth',v_dealer_wealth,
    'current_wealth',v_current_wealth,'is_self_dealer',v_dealer=v_current,'can_activate',v_enabled and v_dealer is null and v_current_wealth>=v_min,
    'can_deactivate',v_dealer=v_current,'eligibility_threshold',v_min,'eligibility_rule','统一灵石达到500万即可申请，每次最多坐庄2小时',
    'expires_at',v_expires,'remaining_seconds',case when v_expires is null then 0 else greatest(0,extract(epoch from(v_expires-now()))::integer) end,
    'system_house_always_available',true,'player_house_only_spirit_stone',v_dealer is not null,'player_house_system_cover',false,
    'house_stake_limit_bps',3000,'house_stake_limit_percent',30,'current_character_stake_limit',v_limit,
    'player_house_win_commission_bps',250,'player_house_win_commission_percent',2.5,'player_house_stake_step',40,
    'player_house_pool_contribution_bps',0,'player_house_heaven_recovery_bps',0,
    'max_stake_spirit_dice',case when v_dealer is null then v_limit else least(v_limit,floor(v_dealer_wealth::numeric/35)::bigint) end,
    'max_stake_turtle_oracle',case when v_dealer is null then v_limit else least(v_limit,floor(v_dealer_wealth::numeric/3)::bigint) end,
    'settlement_rule','thirty_percent_player_house_97_5_fee_to_bankroll_no_cover');
end;
$$;

-- 保存CACHE35市场函数并用包装器补充赌场资金与周期状态。
do $$
begin
  if to_regprocedure('public.get_market_v1_cache35()') is null and to_regprocedure('public.get_market_v1()') is not null then
    alter function public.get_market_v1() rename to get_market_v1_cache35;
  end if;
end;
$$;

create or replace function public.get_market_v1()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_base jsonb;
begin
  perform public.casino_process_v1();
  v_base:=public.get_market_v1_cache35();
  return v_base||jsonb_build_object(
    'casino_period',public.casino_period_status_v1(),
    'bankrolls',(select jsonb_object_agg(stake_type,jsonb_build_object(
      'target_amount',target_amount,'balance',balance,'available_balance',public.casino_bankroll_available_v1(stake_type),
      'period_started_at',period_started_at,'betting_closes_at',betting_closes_at,'period_ends_at',period_ends_at,
      'last_period_profit',last_period_profit,'last_pool_allocation',last_pool_allocation,'last_retained_profit',last_retained_profit
    )) from public.casino_bankroll_v1),
    'casino_fix1_rules',jsonb_build_object('stake_limit_percent',30,'period_hours',2,'close_before_seconds',60,
      'positive_profit_to_pool_percent',50,'pool_prize_percent',70,'pool_rollover_percent',30,
      'player_house_winner_percent',97.5,'player_house_fee_percent',2.5,'no_session_limit',true,'player_house_system_cover',false)
  );
end;
$$;

-- ---------------------------------------------------------------------------
-- 10. 权限、旧入口封锁与注释
-- ---------------------------------------------------------------------------
revoke all on function public.casino_secure_random_int_v1(integer) from public,anon,authenticated;
revoke all on function public.casino_bankroll_available_v1(text) from public,anon,authenticated;
revoke all on function public.casino_bankroll_apply_v1(text,bigint,text,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.casino_claim_round_stake_v1(uuid,uuid,text,text,bigint,bigint) from public,anon,authenticated;
revoke all on function public.casino_draw_house_result_fix1(text,text) from public,anon,authenticated;
revoke all on function public.casino_pool_draw_fix1(text,timestamptz,boolean) from public,anon,authenticated;
revoke all on function public.casino_settle_bankroll_periods_v1() from public,anon,authenticated;
revoke all on function public.casino_period_status_v1() from public,anon,authenticated;
revoke all on function public.play_system_house_game_v0141_fix7a(text,text,bigint,text) from public,anon,authenticated;
revoke all on function public.casino_player_house_draw_result_v1(text,text) from public,anon,authenticated;
revoke all on function public.casino_play_player_house_v1(uuid,text,text,bigint,text) from public,anon,authenticated;
revoke all on function public.casino_play_player_house_v1_fix4(uuid,text,text,bigint,text,uuid) from public,anon,authenticated;
revoke all on function public.play_house_game_v0147(text,text,text,bigint,text) from public,anon,authenticated;
revoke all on function public.play_house_game_v1(text,text,bigint,text) from public,anon,authenticated;
revoke all on function public.place_fish_shrimp_bet_v0148(text,text,text,bigint) from public,anon,authenticated;
revoke all on function public.play_house_game_v1_fix4(uuid,text,text,text,bigint,text) from public,anon;
revoke all on function public.place_fish_shrimp_bet_v1_fix4(uuid,text,text,text,bigint) from public,anon;
revoke all on function public.get_market_v1_cache35() from public,anon,authenticated;
revoke all on function public.get_market_v1() from public,anon;
revoke all on function public.get_casino_player_house_status_v1() from public,anon;
grant execute on function public.play_house_game_v1_fix4(uuid,text,text,text,bigint,text) to authenticated;
grant execute on function public.place_fish_shrimp_bet_v1_fix4(uuid,text,text,text,bigint) to authenticated;
grant execute on function public.get_market_v1() to authenticated;
grant execute on function public.get_casino_player_house_status_v1() to authenticated;

comment on function public.play_house_game_v1_fix4(uuid,text,text,text,bigint,text) is
  'V1.1 FIX1：公平三骰/龟卜；单局30%；系统真实周期资金；玩家庄100:97.5且零系统兜底；玩家庄下注按40灵石步进确保2.5%整数精确；请求幂等并拒绝同角色并发。';
comment on function public.place_fish_shrimp_bet_v1_fix4(uuid,text,text,text,bigint) is
  'V1.1 FIX1：鱼虾公共轮次累计30%；系统赔率106/210/320；玩家庄2.5%平台费、40灵石步进、庄家预扣3倍责任、零系统兜底。';
comment on function public.casino_settle_bankroll_periods_v1() is
  'V1.1 FIX1：每两小时独立清算；正利润50%入池后70%派奖；亏损不开奖；随后灵石固定重置1亿、修为固定重置10亿。';

notify pgrst,'reload schema';
commit;
