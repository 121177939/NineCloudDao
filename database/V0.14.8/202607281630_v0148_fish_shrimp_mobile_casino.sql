-- 九霄问道 V0.14.8 CACHE12
-- B线万运博弈楼手机端排版 + 鱼虾灵局60秒公共开盘
-- 前置：V0.14.7 CACHE11

begin;

-- 基线门禁：不允许跳过V0.14.7正式基线。
do $$
begin
  if to_regclass('public.player_characters') is null then raise exception 'V0148_REQUIRED:player_characters'; end if;
  if to_regclass('public.casino_settings') is null then raise exception 'V0148_REQUIRED:casino_settings'; end if;
  if to_regclass('public.casino_pools') is null then raise exception 'V0148_REQUIRED:casino_pools'; end if;
  if to_regclass('public.casino_player_house_state') is null then raise exception 'V0148_REQUIRED:casino_player_house_state'; end if;
  if to_regprocedure('public.play_house_game_v0147(text,text,text,bigint,text)') is null then raise exception 'V0148_REQUIRED:play_house_game_v0147'; end if;
  if to_regprocedure('public.casino_current_character_id_v1()') is null then raise exception 'V0148_REQUIRED:casino_current_character_id_v1'; end if;
  if to_regprocedure('public.casino_debit_v1(uuid,text,bigint,text,text)') is null then raise exception 'V0148_REQUIRED:casino_debit_v1'; end if;
  if to_regprocedure('public.casino_credit_result_v0141(uuid,text,bigint)') is null then raise exception 'V0148_REQUIRED:casino_credit_result_v0141'; end if;
  if to_regprocedure('public.casino_take_pool_share_v0141_fix7a(text,bigint,integer,text)') is null then raise exception 'V0148_REQUIRED:casino_take_pool_share_v0141_fix7a'; end if;
  if to_regprocedure('public.casino_player_house_resolve_dealer_v1()') is null then raise exception 'V0148_REQUIRED:casino_player_house_resolve_dealer_v1'; end if;
  if to_regprocedure('public.spirit_stone_balance_v0141(uuid)') is null then raise exception 'V0148_REQUIRED:spirit_stone_balance_v0141'; end if;
  if to_regprocedure('public.spirit_stone_debit_v0141(uuid,bigint,text)') is null then raise exception 'V0148_REQUIRED:spirit_stone_debit_v0141'; end if;
  if to_regprocedure('public.award_spirit_stones_v3(uuid,bigint)') is null then raise exception 'V0148_REQUIRED:award_spirit_stones_v3'; end if;
end;
$$;

create table if not exists public.casino_fish_rounds_v0148 (
  id uuid primary key default gen_random_uuid(),
  round_no bigint not null unique,
  starts_at timestamptz not null,
  betting_closes_at timestamptz not null,
  reveal_at timestamptz not null,
  settles_at timestamptz not null,
  ends_at timestamptz not null,
  result_symbols text[] not null,
  is_settled boolean not null default false,
  settled_at timestamptz,
  created_at timestamptz not null default now(),
  constraint casino_fish_round_times_v0148 check(
    starts_at < betting_closes_at
    and betting_closes_at < reveal_at
    and reveal_at < settles_at
    and settles_at < ends_at
  ),
  constraint casino_fish_round_symbols_v0148 check(
    cardinality(result_symbols)=3
    and result_symbols <@ array['fish','shrimp','crab','coin','gourd','frog']::text[]
  )
);

create index if not exists casino_fish_rounds_time_v0148
  on public.casino_fish_rounds_v0148(round_no desc);
create index if not exists casino_fish_rounds_unsettled_v0148
  on public.casino_fish_rounds_v0148(settles_at)
  where not is_settled;

create table if not exists public.casino_fish_bets_v0148 (
  id uuid primary key default gen_random_uuid(),
  round_id uuid not null references public.casino_fish_rounds_v0148(id) on delete cascade,
  character_id uuid not null references public.player_characters(id) on delete cascade,
  house_mode text not null,
  dealer_character_id uuid references public.player_characters(id) on delete set null,
  dealer_name_snapshot text,
  stake_type text not null,
  symbol_code text not null,
  stake_amount bigint not null,
  result_count smallint,
  payout_amount bigint not null default 0,
  net_profit bigint not null default 0,
  commission_amount bigint not null default 0,
  pool_contribution bigint not null default 0,
  heaven_recovery bigint not null default 0,
  dealer_debit_amount bigint not null default 0,
  dealer_credit_amount bigint not null default 0,
  system_cover_amount bigint not null default 0,
  outcome_code text,
  is_settled boolean not null default false,
  settled_at timestamptz,
  created_at timestamptz not null default now(),
  constraint casino_fish_bet_house_v0148 check(house_mode in ('system','player')),
  constraint casino_fish_bet_stake_v0148 check(stake_type in ('spirit_stone','cultivation')),
  constraint casino_fish_bet_symbol_v0148 check(symbol_code in ('fish','shrimp','crab','coin','gourd','frog')),
  constraint casino_fish_bet_amount_v0148 check(stake_amount between 1 and 9007199254740991),
  constraint casino_fish_bet_result_count_v0148 check(result_count is null or result_count between 0 and 3),
  constraint casino_fish_bet_outcome_v0148 check(outcome_code is null or outcome_code in ('win','loss')),
  constraint casino_fish_bet_nonnegative_v0148 check(
    payout_amount>=0 and commission_amount>=0 and pool_contribution>=0
    and heaven_recovery>=0 and dealer_debit_amount>=0
    and dealer_credit_amount>=0 and system_cover_amount>=0
  ),
  constraint casino_fish_player_only_stones_v0148 check(house_mode<>'player' or stake_type='spirit_stone')
);

create index if not exists casino_fish_bets_round_v0148
  on public.casino_fish_bets_v0148(round_id,created_at);
create index if not exists casino_fish_bets_character_v0148
  on public.casino_fish_bets_v0148(character_id,created_at desc);
create index if not exists casino_fish_bets_unsettled_v0148
  on public.casino_fish_bets_v0148(round_id)
  where not is_settled;

alter table public.casino_fish_rounds_v0148 enable row level security;
alter table public.casino_fish_bets_v0148 enable row level security;
revoke all on table public.casino_fish_rounds_v0148 from public,anon,authenticated;
revoke all on table public.casino_fish_bets_v0148 from public,anon,authenticated;

create or replace function public.casino_fish_symbol_name_v0148(p_symbol text)
returns text
language sql
immutable
security definer
set search_path=public,pg_temp
as $$
  select case p_symbol
    when 'fish' then '鱼'
    when 'shrimp' then '虾'
    when 'crab' then '蟹'
    when 'coin' then '铜钱'
    when 'gourd' then '葫芦'
    when 'frog' then '青蛙'
    else '未知法印'
  end;
$$;

create or replace function public.casino_fish_create_round_v0148(p_round_no bigint)
returns uuid
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_id uuid;
  v_start timestamptz;
  v_symbols constant text[]:=array['fish','shrimp','crab','coin','gourd','frog'];
  v_result text[];
begin
  if p_round_no is null or p_round_no<1 then raise exception 'FISH_ROUND_INVALID'; end if;
  perform pg_advisory_xact_lock(hashtextextended('fish-round:'||p_round_no::text,148));
  select id into v_id from public.casino_fish_rounds_v0148 where round_no=p_round_no;
  if v_id is not null then return v_id; end if;

  v_start:=to_timestamp(p_round_no*60);
  v_result:=array[
    v_symbols[1+floor(random()*6)::integer],
    v_symbols[1+floor(random()*6)::integer],
    v_symbols[1+floor(random()*6)::integer]
  ];

  insert into public.casino_fish_rounds_v0148(
    round_no,starts_at,betting_closes_at,reveal_at,settles_at,ends_at,result_symbols
  ) values(
    p_round_no,v_start,v_start+interval '40 seconds',v_start+interval '43 seconds',
    v_start+interval '49 seconds',v_start+interval '60 seconds',v_result
  )
  on conflict(round_no) do update set round_no=excluded.round_no
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.casino_fish_settle_round_v0148(p_round_id uuid)
returns boolean
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_round public.casino_fish_rounds_v0148%rowtype;
  v_bet public.casino_fish_bets_v0148%rowtype;
  v_count integer;
  v_gross bigint;
  v_pool_calc jsonb;
  v_pool bigint;
  v_heaven bigint;
  v_requested bigint;
  v_credit jsonb;
  v_payout bigint;
  v_net bigint;
  v_commission_bps integer:=500;
  v_commission bigint;
  v_player_profit bigint;
  v_dealer_balance bigint;
  v_dealer_debit bigint;
  v_dealer_credit bigint;
  v_system_cover bigint;
  v_ticket boolean;
begin
  if p_round_id is null then return false; end if;
  perform pg_advisory_xact_lock(hashtextextended('fish-settle:'||p_round_id::text,148));
  select * into v_round
  from public.casino_fish_rounds_v0148
  where id=p_round_id
  for update;

  if v_round.id is null then return false; end if;
  if v_round.is_settled then return true; end if;
  if now()<v_round.settles_at then return false; end if;

  select greatest(0,least(10000,coalesce(player_house_win_commission_bps,500)))
  into v_commission_bps
  from public.casino_settings where singleton_id=1;

  for v_bet in
    select * from public.casino_fish_bets_v0148
    where round_id=p_round_id and not is_settled
    order by character_id::text,coalesce(dealer_character_id::text,''),created_at,id
    for update
  loop
    select count(*)::integer into v_count
    from unnest(v_round.result_symbols) symbol_value
    where symbol_value=v_bet.symbol_code;

    v_pool:=0;v_heaven:=0;v_payout:=0;v_net:=-v_bet.stake_amount;
    v_commission:=0;v_dealer_debit:=0;v_dealer_credit:=0;v_system_cover:=0;

    if v_bet.house_mode='system' then
      if v_count>0 then
        v_gross:=(v_bet.stake_amount::numeric*v_count::numeric)::bigint;
        v_pool_calc:=public.casino_take_pool_share_v0141_fix7a(v_bet.stake_type,v_gross,500,'win');
        v_pool:=coalesce((v_pool_calc->>'pool_contribution')::bigint,0);
        v_requested:=v_bet.stake_amount+greatest(v_gross-v_pool,0);
        if v_pool>0 then
          update public.casino_pools set amount=amount+v_pool,updated_at=now()
          where stake_type=v_bet.stake_type;
        end if;
        v_credit:=public.casino_credit_result_v0141(v_bet.character_id,v_bet.stake_type,v_requested);
        v_payout:=coalesce((v_credit->>'granted_amount')::bigint,0);
        v_net:=v_payout-v_bet.stake_amount;
      else
        v_pool_calc:=public.casino_take_pool_share_v0141_fix7a(v_bet.stake_type,v_bet.stake_amount,1000,'loss');
        v_pool:=coalesce((v_pool_calc->>'pool_contribution')::bigint,0);
        v_heaven:=greatest(v_bet.stake_amount-v_pool,0);
        if v_pool>0 then
          update public.casino_pools set amount=amount+v_pool,updated_at=now()
          where stake_type=v_bet.stake_type;
        end if;
        if v_bet.stake_type='cultivation' then
          perform public.casino_realign_after_loss_v1(v_bet.character_id);
        end if;
      end if;
      v_ticket:=public.casino_add_ticket_v1(v_bet.character_id,v_bet.stake_type);
    else
      if v_count>0 then
        v_gross:=(v_bet.stake_amount::numeric*v_count::numeric)::bigint;
        v_commission:=floor(v_gross::numeric*v_commission_bps::numeric/10000)::bigint;
        v_player_profit:=greatest(v_gross-v_commission,0);

        if v_bet.dealer_character_id is not null then
          if v_bet.character_id::text<v_bet.dealer_character_id::text then
            perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||v_bet.character_id::text,141));
            perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||v_bet.dealer_character_id::text,141));
          else
            perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||v_bet.dealer_character_id::text,141));
            perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||v_bet.character_id::text,141));
          end if;
          v_dealer_balance:=public.spirit_stone_balance_v0141(v_bet.dealer_character_id);
          v_dealer_debit:=least(v_dealer_balance,v_player_profit);
          if v_dealer_debit>0 then
            perform public.spirit_stone_debit_v0141(v_bet.dealer_character_id,v_dealer_debit,'CASINO_PLAYER_HOUSE_DEALER_INSUFFICIENT');
          end if;
        end if;
        v_system_cover:=greatest(v_player_profit-v_dealer_debit,0);
        perform public.award_spirit_stones_v3(v_bet.character_id,v_bet.stake_amount+v_player_profit);
        v_payout:=v_bet.stake_amount+v_player_profit;
        v_net:=v_player_profit;
      else
        if v_bet.dealer_character_id is not null then
          perform public.award_spirit_stones_v3(v_bet.dealer_character_id,v_bet.stake_amount);
          v_dealer_credit:=v_bet.stake_amount;
        end if;
      end if;
    end if;

    update public.casino_fish_bets_v0148
    set result_count=v_count,
        payout_amount=v_payout,
        net_profit=v_net,
        commission_amount=v_commission,
        pool_contribution=v_pool,
        heaven_recovery=v_heaven,
        dealer_debit_amount=v_dealer_debit,
        dealer_credit_amount=v_dealer_credit,
        system_cover_amount=v_system_cover,
        outcome_code=case when v_count>0 then 'win' else 'loss' end,
        is_settled=true,
        settled_at=now()
    where id=v_bet.id;
  end loop;

  update public.casino_fish_rounds_v0148
  set is_settled=true,settled_at=now()
  where id=p_round_id;
  return true;
end;
$$;

create or replace function public.casino_fish_ensure_round_v0148()
returns uuid
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_current_no bigint:=floor(extract(epoch from clock_timestamp())/60)::bigint;
  v_id uuid;
  v_due record;
begin
  perform public.casino_assert_enabled_v1();
  for v_due in
    select id from public.casino_fish_rounds_v0148
    where not is_settled and settles_at<=now()
    order by round_no
    limit 100
  loop
    perform public.casino_fish_settle_round_v0148(v_due.id);
  end loop;

  v_id:=public.casino_fish_create_round_v0148(v_current_no);
  perform public.casino_fish_settle_round_v0148(v_id);
  return v_id;
end;
$$;

create or replace function public.casino_fish_round_summary_v0148(
  p_round_id uuid,p_character_id uuid
)
returns jsonb
language plpgsql
stable
security definer
set search_path=public,pg_temp
as $$
declare
  v_round public.casino_fish_rounds_v0148%rowtype;
  v_groups jsonb:='[]'::jsonb;
begin
  select * into v_round from public.casino_fish_rounds_v0148 where id=p_round_id;
  if v_round.id is null then return '{}'::jsonb; end if;

  select coalesce(jsonb_agg(group_row order by group_order),'[]'::jsonb)
  into v_groups
  from (
    select
      case when b.house_mode='system' then 1 else 2 end as group_order,
      jsonb_build_object(
        'house_mode',b.house_mode,
        'dealer_label',case when b.house_mode='system' then '荷老局' else '玩家局' end,
        'dealer_name',case when b.house_mode='system' then '荷老' else coalesce(max(b.dealer_name_snapshot),'玩家庄') end,
        'items',coalesce((
          select jsonb_agg(jsonb_build_object(
            'stake_type',i.stake_type,
            'symbol_code',i.symbol_code,
            'symbol_name',public.casino_fish_symbol_name_v0148(i.symbol_code),
            'stake_amount',i.stake_amount,
            'net_profit',i.net_profit,
            'result_count',i.result_count
          ) order by i.stake_type,i.symbol_code)
          from (
            select stake_type,symbol_code,sum(stake_amount)::bigint stake_amount,
                   sum(net_profit)::bigint net_profit,max(result_count)::integer result_count
            from public.casino_fish_bets_v0148 x
            where x.round_id=p_round_id and x.character_id=p_character_id and x.house_mode=b.house_mode
            group by stake_type,symbol_code
          ) i
        ),'[]'::jsonb),
        'stone_bet',sum(b.stake_amount) filter(where b.stake_type='spirit_stone'),
        'stone_net',sum(b.net_profit) filter(where b.stake_type='spirit_stone'),
        'cultivation_bet',sum(b.stake_amount) filter(where b.stake_type='cultivation'),
        'cultivation_net',sum(b.net_profit) filter(where b.stake_type='cultivation')
      ) as group_row
    from public.casino_fish_bets_v0148 b
    where b.round_id=p_round_id and b.character_id=p_character_id
    group by b.house_mode
  ) grouped;

  return jsonb_build_object(
    'round_id',v_round.id,
    'round_no',v_round.round_no,
    'starts_at',v_round.starts_at,
    'ends_at',v_round.ends_at,
    'results',to_jsonb(v_round.result_symbols),
    'groups',v_groups,
    'has_bets',jsonb_array_length(v_groups)>0
  );
end;
$$;

create or replace function public.get_fish_shrimp_state_v0148(p_limit integer default 20)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_character_id uuid:=public.casino_current_character_id_v1();
  v_round_id uuid;
  v_round public.casino_fish_rounds_v0148%rowtype;
  v_now timestamptz:=clock_timestamp();
  v_phase text;
  v_phase_end timestamptz;
  v_results jsonb:='[]'::jsonb;
  v_bets jsonb:='[]'::jsonb;
  v_totals jsonb:='[]'::jsonb;
  v_history jsonb:='[]'::jsonb;
  v_player_house jsonb;
  v_stones bigint:=0;
  v_cultivation bigint:=0;
  v_limit integer:=greatest(1,least(coalesce(p_limit,20),20));
begin
  v_round_id:=public.casino_fish_ensure_round_v0148();
  select * into v_round from public.casino_fish_rounds_v0148 where id=v_round_id;

  if v_now<v_round.betting_closes_at then v_phase:='betting';v_phase_end:=v_round.betting_closes_at;
  elsif v_now<v_round.reveal_at then v_phase:='locked';v_phase_end:=v_round.reveal_at;
  elsif v_now<v_round.settles_at then v_phase:='revealing';v_phase_end:=v_round.settles_at;
  elsif v_now<v_round.settles_at+interval '7 seconds' then v_phase:='settled';v_phase_end:=v_round.settles_at+interval '7 seconds';
  elsif v_now<v_round.ends_at then v_phase:='next';v_phase_end:=v_round.ends_at;
  else v_phase:='next';v_phase_end:=v_round.ends_at; end if;

  if v_now>=v_round.reveal_at then v_results:=to_jsonb(v_round.result_symbols); end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'house_mode',x.house_mode,'stake_type',x.stake_type,
    'symbol_code',x.symbol_code,'symbol_name',public.casino_fish_symbol_name_v0148(x.symbol_code),
    'stake_amount',x.stake_amount,'net_profit',x.net_profit,
    'result_count',x.result_count,'is_settled',x.is_settled
  ) order by x.house_mode,x.stake_type,x.symbol_code),'[]'::jsonb)
  into v_bets
  from (
    select house_mode,stake_type,symbol_code,sum(stake_amount)::bigint stake_amount,
           sum(net_profit)::bigint net_profit,max(result_count)::integer result_count,
           bool_and(is_settled) is_settled
    from public.casino_fish_bets_v0148
    where round_id=v_round_id and character_id=v_character_id
    group by house_mode,stake_type,symbol_code
  ) x;

  select coalesce(jsonb_agg(jsonb_build_object(
    'house_mode',x.house_mode,'stake_type',x.stake_type,
    'symbol_code',x.symbol_code,'stake_amount',x.stake_amount
  ) order by x.house_mode,x.stake_type,x.symbol_code),'[]'::jsonb)
  into v_totals
  from (
    select house_mode,stake_type,symbol_code,sum(stake_amount)::bigint stake_amount
    from public.casino_fish_bets_v0148
    where round_id=v_round_id
    group by house_mode,stake_type,symbol_code
  ) x;

  select coalesce(jsonb_agg(public.casino_fish_round_summary_v0148(r.id,v_character_id) order by r.round_no desc),'[]'::jsonb)
  into v_history
  from (
    select id,round_no from public.casino_fish_rounds_v0148
    where is_settled
    order by round_no desc
    limit v_limit
  ) r;

  v_player_house:=public.get_casino_player_house_status_v1();
  v_stones:=public.spirit_stone_balance_v0141(v_character_id);
  v_cultivation:=public.casino_available_v1(v_character_id,'cultivation');

  return jsonb_build_object(
    'status','active',
    'server_now',v_now,
    'round',jsonb_build_object(
      'id',v_round.id,'round_no',v_round.round_no,
      'starts_at',v_round.starts_at,'betting_closes_at',v_round.betting_closes_at,
      'reveal_at',v_round.reveal_at,'settles_at',v_round.settles_at,'ends_at',v_round.ends_at,
      'phase',v_phase,'phase_ends_at',v_phase_end,
      'seconds_remaining',greatest(0,ceil(extract(epoch from(v_phase_end-v_now)))::integer),
      'elapsed_seconds',greatest(0,extract(epoch from(v_now-v_round.starts_at))::numeric),
      'results',v_results,'is_settled',v_round.is_settled
    ),
    'character',jsonb_build_object('spirit_stones',v_stones,'cultivation_available',v_cultivation),
    'player_house',v_player_house,
    'my_bets',v_bets,
    'round_totals',v_totals,
    'history',v_history,
    'rules',jsonb_build_object(
      'round_seconds',60,'betting_seconds',40,'lock_seconds',3,
      'reveal_seconds',6,'settlement_seconds',7,'next_seconds',4,
      'player_house_commission_bps',500
    )
  );
end;
$$;

create or replace function public.place_fish_shrimp_bet_v0148(
  p_house_mode text,p_stake_type text,p_symbol_code text,p_stake_amount bigint
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_character_id uuid:=public.casino_current_character_id_v1();
  v_round_id uuid;
  v_round public.casino_fish_rounds_v0148%rowtype;
  v_dealer_id uuid;
  v_dealer_name text;
  v_debit jsonb;
begin
  perform public.casino_assert_enabled_v1();
  if p_house_mode not in('system','player') then raise exception 'FISH_INVALID_HOUSE_MODE'; end if;
  if p_stake_type not in('spirit_stone','cultivation') then raise exception 'CASINO_INVALID_STAKE_TYPE'; end if;
  if p_symbol_code not in('fish','shrimp','crab','coin','gourd','frog') then raise exception 'FISH_INVALID_SYMBOL'; end if;
  if p_stake_amount is null or p_stake_amount<1 then raise exception 'CASINO_INVALID_STAKE_AMOUNT'; end if;
  if p_stake_amount>9007199254740991 then raise exception 'CASINO_STAKE_TOO_LARGE'; end if;

  v_round_id:=public.casino_fish_ensure_round_v0148();
  select * into v_round from public.casino_fish_rounds_v0148 where id=v_round_id for share;
  if clock_timestamp()>=v_round.betting_closes_at then raise exception 'FISH_BETTING_CLOSED'; end if;

  if p_house_mode='player' then
    if p_stake_type<>'spirit_stone' then raise exception 'CASINO_PLAYER_HOUSE_ONLY_SPIRIT_STONE'; end if;
    perform pg_advisory_xact_lock(hashtextextended('casino-player-house-dealer',14301));
    v_dealer_id:=public.casino_player_house_resolve_dealer_v1();
    if v_dealer_id is null then raise exception 'CASINO_PLAYER_HOUSE_NOT_ACTIVE'; end if;
    if v_dealer_id=v_character_id then raise exception 'CASINO_PLAYER_HOUSE_SELF_BET_FORBIDDEN'; end if;
    select name into v_dealer_name from public.player_characters where id=v_dealer_id;
  else
    v_dealer_name:='荷老';
  end if;

  perform public.casino_record_activity_v1(v_character_id,'house',p_stake_type);
  v_debit:=public.casino_debit_v1(v_character_id,p_stake_type,p_stake_amount,'house','fish_shrimp');

  insert into public.casino_fish_bets_v0148(
    round_id,character_id,house_mode,dealer_character_id,dealer_name_snapshot,
    stake_type,symbol_code,stake_amount
  ) values(
    v_round_id,v_character_id,p_house_mode,v_dealer_id,coalesce(v_dealer_name,'玩家庄'),
    p_stake_type,p_symbol_code,p_stake_amount
  );

  return public.get_fish_shrimp_state_v0148(20);
end;
$$;

revoke all on function public.casino_fish_symbol_name_v0148(text) from public,anon,authenticated;
revoke all on function public.casino_fish_create_round_v0148(bigint) from public,anon,authenticated;
revoke all on function public.casino_fish_settle_round_v0148(uuid) from public,anon,authenticated;
revoke all on function public.casino_fish_ensure_round_v0148() from public,anon,authenticated;
revoke all on function public.casino_fish_round_summary_v0148(uuid,uuid) from public,anon,authenticated;
revoke all on function public.get_fish_shrimp_state_v0148(integer) from public,anon;
revoke all on function public.place_fish_shrimp_bet_v0148(text,text,text,bigint) from public,anon;
grant execute on function public.get_fish_shrimp_state_v0148(integer) to authenticated;
grant execute on function public.place_fish_shrimp_bet_v0148(text,text,text,bigint) to authenticated;

update public.jiuxiao_app_release_control
set release_name='V0.14.8 CACHE12',
    cache_epoch=greatest(cache_epoch,12),
    notice_text='万运博弈楼手机端已简化，鱼虾灵局已开放，正在加载最新页面。',
    updated_at=now()
where singleton_id=1;

commit;
notify pgrst,'reload schema';

-- 执行后检查：ok均应为true。
select * from (values
  ('fish_round_table',to_regclass('public.casino_fish_rounds_v0148') is not null),
  ('fish_bet_table',to_regclass('public.casino_fish_bets_v0148') is not null),
  ('fish_state_rpc',to_regprocedure('public.get_fish_shrimp_state_v0148(integer)') is not null),
  ('fish_bet_rpc',to_regprocedure('public.place_fish_shrimp_bet_v0148(text,text,text,bigint)') is not null),
  ('authenticated_state',has_function_privilege('authenticated','public.get_fish_shrimp_state_v0148(integer)','execute')),
  ('authenticated_bet',has_function_privilege('authenticated','public.place_fish_shrimp_bet_v0148(text,text,text,bigint)','execute')),
  ('release_cache12',coalesce((select release_name='V0.14.8 CACHE12' and cache_epoch>=12 from public.jiuxiao_app_release_control where singleton_id=1),false))
) as checks(check_name,ok);
