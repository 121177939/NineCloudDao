-- 九霄问道 V1.0 FIX4：赌坊玩家庄安全结算
-- 1. 取消全部玩家庄系统兜底。
-- 2. 大堂及鱼虾灵局单次下注不得超过当前可用资源10%。
-- 3. 玩家庄开奖前锁定并校验最大可能赔付。
-- 4. 唯一request_id幂等，重复请求只返回首次结果。
-- 5. 玩家庄有效局统一收取5%坊税进入现有全服造化池。
-- 6. 不改变灵骰、龟卜、鱼虾灵局概率与倍率。

begin;

alter table public.casino_settings
  add column if not exists house_stake_limit_bps integer not null default 1000;
update public.casino_settings set house_stake_limit_bps=1000 where singleton_id=1;

do $$
begin
  if not exists(select 1 from pg_constraint where conname='casino_settings_house_stake_limit_bps_check') then
    alter table public.casino_settings add constraint casino_settings_house_stake_limit_bps_check
      check(house_stake_limit_bps between 1 and 10000);
  end if;
end;
$$;

create table if not exists public.casino_bet_requests_v1 (
  request_id uuid not null,
  character_id uuid not null references public.player_characters(id) on delete cascade,
  game_code text not null,
  house_mode text not null,
  stake_type text not null,
  stake_amount bigint not null,
  choice_code text,
  status text not null default 'pending',
  resource_before bigint not null default 0,
  resource_after bigint not null default 0,
  result_payload jsonb,
  settlement_version text not null default 'V1.0_FIX4',
  created_at timestamptz not null default now(),
  settled_at timestamptz,
  primary key(character_id,request_id),
  constraint casino_bet_requests_status_v1 check(status in('pending','settled','void')),
  constraint casino_bet_requests_house_v1 check(house_mode in('system','player')),
  constraint casino_bet_requests_stake_v1 check(stake_type in('spirit_stone','cultivation')),
  constraint casino_bet_requests_amount_v1 check(stake_amount>0)
);
create index if not exists casino_bet_requests_created_v1 on public.casino_bet_requests_v1(character_id,created_at desc);
alter table public.casino_bet_requests_v1 enable row level security;
revoke all on table public.casino_bet_requests_v1 from public,anon,authenticated;

alter table public.casino_house_games add column if not exists request_id uuid;
alter table public.casino_house_games add column if not exists settlement_version text;
create unique index if not exists casino_house_games_request_v1
  on public.casino_house_games(character_id,request_id) where request_id is not null;

alter table public.casino_fish_bets_v0148 add column if not exists request_id uuid;
alter table public.casino_fish_bets_v0148 add column if not exists dealer_reserved_amount bigint not null default 0;
alter table public.casino_fish_bets_v0148 add column if not exists dealer_refund_amount bigint not null default 0;
alter table public.casino_fish_bets_v0148 add column if not exists settlement_version text;
create unique index if not exists casino_fish_bets_request_v1
  on public.casino_fish_bets_v0148(character_id,request_id) where request_id is not null;

do $$
begin
  if not exists(select 1 from pg_constraint where conname='casino_fish_bet_reserve_nonnegative_v1') then
    alter table public.casino_fish_bets_v0148 add constraint casino_fish_bet_reserve_nonnegative_v1
      check(dealer_reserved_amount>=0 and dealer_refund_amount>=0);
  end if;
end;
$$;

-- 部署瞬间仍未结算的旧玩家鱼虾局没有预先冻结庄家赔付，安全起见作废并原数退款。
do $$
declare r record;
begin
  for r in
    select b.id,b.character_id,b.stake_amount,b.house_mode,b.stake_type,b.symbol_code
    from public.casino_fish_bets_v0148 b
    where not b.is_settled and b.house_mode='player'
    for update
  loop
    perform public.award_spirit_stones_v3(r.character_id,r.stake_amount);
    insert into public.casino_bet_requests_v1(
      request_id,character_id,game_code,house_mode,stake_type,stake_amount,choice_code,status,
      resource_before,resource_after,result_payload,settlement_version,settled_at
    ) values(
      gen_random_uuid(),r.character_id,'fish_shrimp','player','spirit_stone',r.stake_amount,r.symbol_code,'void',
      0,0,jsonb_build_object('void_reason','legacy_player_fish_without_reserve','refund_amount',r.stake_amount),
      'V1.0_FIX4_LEGACY_REFUND',now()
    );
    delete from public.casino_fish_bets_v0148 where id=r.id;
  end loop;
end;
$$;

create or replace function public.casino_house_stake_limit_v1(p_character_id uuid,p_stake_type text)
returns bigint
language plpgsql
stable
security definer
set search_path=public,pg_temp
as $$
declare v_available bigint:=0;v_bps integer:=1000;
begin
  v_available:=public.casino_available_v1(p_character_id,p_stake_type);
  select greatest(1,least(10000,coalesce(house_stake_limit_bps,1000))) into v_bps
  from public.casino_settings where singleton_id=1;
  return greatest(0,floor(v_available::numeric*v_bps::numeric/10000)::bigint);
end;
$$;


-- 修为下注沿用原境界保底；大堂模式在可用修为不足50万时，把最低值降到10%上限，避免出现无合法下注区间。
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
    if p_context='house' and p_amount>public.casino_house_stake_limit_v1(p_character_id,'spirit_stone') then raise exception 'CASINO_STAKE_EXCEEDS_TEN_PERCENT';end if;
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
      if p_amount>v_house_limit then raise exception 'CASINO_STAKE_EXCEEDS_TEN_PERCENT';end if;
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

create or replace function public.get_casino_player_house_status_v1()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_current_id uuid:=public.casino_current_character_id_v1();v_dealer_id uuid;
  v_current_wealth bigint:=0;v_dealer_wealth bigint:=0;v_dealer_name text;
  v_enabled boolean:=false;v_min_wealth bigint:=5000000;v_fee_bps integer:=500;v_limit_bps integer:=1000;
  v_destiny_odds integer:=34;v_expires_at timestamptz;v_user_limit bigint:=0;
begin
  v_dealer_id:=public.casino_player_house_resolve_dealer_v1();
  select coalesce(player_house_enabled,false),coalesce(player_house_min_wealth,5000000),
         greatest(0,least(10000,coalesce(player_house_win_commission_bps,500))),
         greatest(1,least(10000,coalesce(house_stake_limit_bps,1000))),
         greatest(1,coalesce(spirit_dice_destiny_triple_net_odds,34))
  into v_enabled,v_min_wealth,v_fee_bps,v_limit_bps,v_destiny_odds
  from public.casino_settings where singleton_id=1;
  v_current_wealth:=public.spirit_stone_balance_v0141(v_current_id);
  v_user_limit:=floor(v_current_wealth::numeric*v_limit_bps/10000)::bigint;
  if v_dealer_id is not null then
    select pc.name,public.spirit_stone_balance_v0141(pc.id) into v_dealer_name,v_dealer_wealth
    from public.player_characters pc where pc.id=v_dealer_id;
    select expires_at into v_expires_at from public.casino_player_house_state where singleton_id=1;
  end if;
  return jsonb_build_object(
    'status','ok','mode',case when v_dealer_id is null then 'system' else 'player' end,
    'dealer_name',case when v_dealer_id is null then '荷老' else coalesce(v_dealer_name,'无名庄家') end,
    'dealer_wealth',case when v_dealer_id is null then null else v_dealer_wealth end,
    'current_wealth',v_current_wealth,'is_self_dealer',v_dealer_id=v_current_id,
    'can_activate',v_enabled and v_dealer_id is null and v_current_wealth>=v_min_wealth,
    'can_deactivate',v_dealer_id=v_current_id,'eligibility_threshold',v_min_wealth,
    'eligibility_rule','统一灵石达到500万即可申请，每次最多坐庄2小时',
    'expires_at',v_expires_at,'remaining_seconds',case when v_expires_at is null then 0 else greatest(0,extract(epoch from(v_expires_at-now()))::integer) end,
    'system_house_always_available',true,'player_house_only_spirit_stone',v_dealer_id is not null,
    'player_house_unlimited_stake',false,'player_house_system_cover',false,
    'house_stake_limit_bps',v_limit_bps,'house_stake_limit_percent',v_limit_bps::numeric/100,
    'current_character_stake_limit',v_user_limit,
    'player_house_win_commission_bps',v_fee_bps,'player_house_win_commission_percent',v_fee_bps::numeric/100,
    'player_house_pool_contribution_bps',v_fee_bps,'player_house_heaven_recovery_bps',0,
    'max_stake_spirit_dice',case when v_dealer_id is null then v_user_limit else least(v_user_limit,floor(v_dealer_wealth::numeric/v_destiny_odds)::bigint) end,
    'max_stake_turtle_oracle',case when v_dealer_id is null then v_user_limit else least(v_user_limit,floor(v_dealer_wealth::numeric/3)::bigint) end,
    'settlement_rule','ten_percent_limit_full_liability_no_system_cover_five_percent_pool'
  );
end;
$$;

create or replace function public.casino_play_player_house_v1_fix4(
  p_dealer_character_id uuid,p_game_code text,p_stake_type text,p_stake_amount bigint,p_choice text,p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_bettor_id uuid:=public.casino_current_character_id_v1();v_dealer_name text;
  v_bettor_balance bigint:=0;v_dealer_balance bigint:=0;v_dealer_after bigint:=0;v_limit bigint:=0;
  v_max_odds integer:=1;v_max_liability numeric:=0;v_draw jsonb;v_won boolean:=false;v_odds integer:=0;
  v_fee_bps integer:=500;v_gross numeric:=0;v_gross_i bigint:=0;v_pool_calc jsonb;v_pool bigint:=0;
  v_profit bigint:=0;v_reward bigint:=0;v_dealer_debit bigint:=0;v_dealer_credit bigint:=0;
  v_text text;v_payload jsonb;v_debit jsonb;
begin
  perform public.casino_assert_enabled_v1();
  if p_request_id is null then raise exception 'CASINO_REQUEST_ID_REQUIRED';end if;
  if p_dealer_character_id is null then raise exception 'CASINO_PLAYER_HOUSE_DEALER_MISSING';end if;
  if public.casino_player_house_resolve_dealer_v1() is distinct from p_dealer_character_id then raise exception 'CASINO_PLAYER_HOUSE_NOT_ACTIVE';end if;
  if p_game_code not in('spirit_dice','turtle_oracle') then raise exception 'CASINO_INVALID_HOUSE_GAME';end if;
  if not public.casino_validate_choice_v1(p_game_code,p_choice) then raise exception 'CASINO_INVALID_CHOICE';end if;
  if p_stake_type<>'spirit_stone' then raise exception 'CASINO_PLAYER_HOUSE_ONLY_SPIRIT_STONE';end if;
  if p_stake_amount is null or p_stake_amount<10 then raise exception 'CASINO_STAKE_BELOW_MINIMUM';end if;
  if v_bettor_id=p_dealer_character_id then raise exception 'CASINO_PLAYER_HOUSE_SELF_BET_FORBIDDEN';end if;

  if v_bettor_id::text<p_dealer_character_id::text then
    perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||v_bettor_id::text,141));
    perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||p_dealer_character_id::text,141));
  else
    perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||p_dealer_character_id::text,141));
    perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||v_bettor_id::text,141));
  end if;
  perform public.spirit_stone_normalize_character_v0141(v_bettor_id);
  perform public.spirit_stone_normalize_character_v0141(p_dealer_character_id);
  v_bettor_balance:=public.spirit_stone_balance_v0141(v_bettor_id);
  v_dealer_balance:=public.spirit_stone_balance_v0141(p_dealer_character_id);
  v_limit:=public.casino_house_stake_limit_v1(v_bettor_id,'spirit_stone');
  if p_stake_amount>v_limit then raise exception 'CASINO_STAKE_EXCEEDS_TEN_PERCENT';end if;
  if v_bettor_balance<p_stake_amount then raise exception 'CASINO_INSUFFICIENT_SPIRIT_STONES';end if;
  select name into v_dealer_name from public.player_characters where id=p_dealer_character_id;
  select greatest(0,least(10000,coalesce(player_house_win_commission_bps,500))),
         case when p_game_code='spirit_dice' then greatest(1,coalesce(spirit_dice_destiny_triple_net_odds,34)) else 3 end
  into v_fee_bps,v_max_odds from public.casino_settings where singleton_id=1;
  v_max_liability:=p_stake_amount::numeric*v_max_odds::numeric;
  if v_max_liability>9007199254740991::numeric then raise exception 'CASINO_STAKE_TOO_LARGE';end if;
  if v_dealer_balance<v_max_liability::bigint then raise exception 'CASINO_PLAYER_HOUSE_DEALER_INSUFFICIENT';end if;

  perform public.casino_record_activity_v1(v_bettor_id,'house','spirit_stone');
  v_debit:=public.casino_debit_v1(v_bettor_id,'spirit_stone',p_stake_amount,'house',p_game_code);
  v_draw:=public.casino_player_house_draw_result_v1(p_game_code,p_choice);
  v_won:=coalesce((v_draw->>'won')::boolean,false);v_odds:=coalesce((v_draw->>'net_odds')::integer,0);
  v_payload:=coalesce(v_draw->'result_payload','{}'::jsonb);
  if v_won then
    v_gross:=p_stake_amount::numeric*v_odds::numeric;
    if v_gross>9007199254740991::numeric then raise exception 'CASINO_STAKE_TOO_LARGE';end if;
    v_gross_i:=v_gross::bigint;
    v_pool_calc:=public.casino_take_pool_share_v0141_fix7a('spirit_stone',v_gross_i,v_fee_bps,'win');
    v_pool:=coalesce((v_pool_calc->>'pool_contribution')::bigint,0);
    v_profit:=greatest(v_gross_i-v_pool,0);
    perform public.spirit_stone_debit_v0141(p_dealer_character_id,v_gross_i,'CASINO_PLAYER_HOUSE_DEALER_INSUFFICIENT');
    perform public.award_spirit_stones_v3(v_bettor_id,p_stake_amount+v_profit);
    if v_pool>0 then update public.casino_pools set amount=amount+v_pool,updated_at=now() where stake_type='spirit_stone';end if;
    v_reward:=p_stake_amount+v_profit;v_dealer_debit:=v_gross_i;
    v_text:=format('玩家庄【%s】：%s 押注%s枚灵石；本金原数返还，毛利润%s枚，其中%s枚（5%%）进入全服造化池，闲家净赢%s枚，合计到账%s枚。玩家庄承担全部%s枚赔付，荷老不再兜底。',coalesce(v_dealer_name,'无名庄家'),v_draw->>'result_text',p_stake_amount,v_gross_i,v_pool,v_profit,v_reward,v_gross_i);
  else
    v_pool_calc:=public.casino_take_pool_share_v0141_fix7a('spirit_stone',p_stake_amount,v_fee_bps,'loss');
    v_pool:=coalesce((v_pool_calc->>'pool_contribution')::bigint,0);
    v_dealer_credit:=greatest(p_stake_amount-v_pool,0);
    if v_dealer_credit>0 then perform public.award_spirit_stones_v3(p_dealer_character_id,v_dealer_credit);end if;
    if v_pool>0 then update public.casino_pools set amount=amount+v_pool,updated_at=now() where stake_type='spirit_stone';end if;
    v_text:=format('玩家庄【%s】：%s 闲家押注%s枚灵石落败，其中%s枚（5%%）进入全服造化池，庄家实得%s枚。荷老不参与本局赔付。',coalesce(v_dealer_name,'无名庄家'),v_draw->>'result_text',p_stake_amount,v_pool,v_dealer_credit);
  end if;
  v_dealer_after:=public.spirit_stone_balance_v0141(p_dealer_character_id);
  v_payload:=v_payload||jsonb_build_object(
    'house_mode','player','dealer_name',coalesce(v_dealer_name,'无名庄家'),'stake_type','spirit_stone',
    'net_odds',v_odds,'gross_profit',v_gross_i,'pool_contribution',v_pool,'pool_rate_bps',v_fee_bps,
    'player_net_profit',case when v_won then v_profit else -p_stake_amount end,'actual_reward',v_reward,
    'dealer_debit_amount',v_dealer_debit,'dealer_credit_amount',v_dealer_credit,'system_cover_amount',0,
    'dealer_balance_before',v_dealer_balance,'dealer_balance_after',v_dealer_after,
    'max_liability_amount',v_max_liability::bigint,'request_id',p_request_id,
    'settlement_rule','ten_percent_full_liability_five_percent_pool_no_cover','settlement_version','V1.0_FIX4'
  );
  insert into public.casino_house_games(
    character_id,game_code,stake_type,stake_amount,choice_code,outcome_code,reward_amount,nominal_reward_amount,
    fee_amount,pool_contribution,heaven_recovery_amount,result_payload,result_text,house_mode,dealer_character_id,
    dealer_name_snapshot,dealer_debit_amount,dealer_credit_amount,max_liability_amount,system_cover_amount,request_id,settlement_version
  ) values(
    v_bettor_id,p_game_code,'spirit_stone',p_stake_amount,p_choice,case when v_won then 'win' else 'loss' end,
    v_reward,case when v_won then p_stake_amount+v_gross_i else 0 end,v_pool,v_pool,0,v_payload,v_text,'player',
    p_dealer_character_id,coalesce(v_dealer_name,'无名庄家'),v_dealer_debit,v_dealer_credit,v_max_liability::bigint,0,p_request_id,'V1.0_FIX4'
  );
  return jsonb_build_object('won',v_won,'reward',v_reward,'nominal_reward',case when v_won then p_stake_amount+v_gross_i else 0 end,
    'gross_profit',v_gross_i,'net_profit',case when v_won then v_profit else -p_stake_amount end,'fee',v_pool,
    'pool_contribution',v_pool,'ticket_awarded',false,'house_mode','player','dealer_name',coalesce(v_dealer_name,'无名庄家'),
    'dealer_debit_amount',v_dealer_debit,'dealer_credit_amount',v_dealer_credit,'system_cover_amount',0,
    'max_liability_amount',v_max_liability::bigint,'result_text',v_text,'result_payload',v_payload,'drop',null);
end;
$$;

-- 旧内部签名也替换为安全逻辑，防止其他服务端路径误用旧兜底实现。
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
  v_character_id uuid:=public.casino_current_character_id_v1();v_existing jsonb;v_result jsonb;
  v_request public.casino_bet_requests_v1%rowtype;
  v_before bigint:=0;v_after bigint:=0;v_limit bigint:=0;v_dealer uuid;v_game_id uuid;
begin
  if p_request_id is null then raise exception 'CASINO_REQUEST_ID_REQUIRED';end if;
  if p_house_mode not in('system','player') then raise exception 'CASINO_INVALID_HOUSE_MODE';end if;
  perform pg_advisory_xact_lock(hashtextextended('casino-request:'||v_character_id::text||':'||p_request_id::text,104));
  select * into v_request from public.casino_bet_requests_v1
  where character_id=v_character_id and request_id=p_request_id;
  if found then
    if v_request.game_code is distinct from p_game_code
       or v_request.house_mode is distinct from p_house_mode
       or v_request.stake_type is distinct from p_stake_type
       or v_request.stake_amount is distinct from p_stake_amount
       or v_request.choice_code is distinct from p_choice then
      raise exception 'CASINO_REQUEST_PARAMETER_MISMATCH';
    end if;
    if v_request.status='settled' and v_request.result_payload is not null then return v_request.result_payload;end if;
    raise exception 'CASINO_REQUEST_IN_PROGRESS';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('casino-house-character:'||v_character_id::text,104));
  v_before:=public.casino_available_v1(v_character_id,p_stake_type);
  v_limit:=public.casino_house_stake_limit_v1(v_character_id,p_stake_type);
  if p_stake_amount is null or p_stake_amount>v_limit then raise exception 'CASINO_STAKE_EXCEEDS_TEN_PERCENT';end if;
  insert into public.casino_bet_requests_v1(request_id,character_id,game_code,house_mode,stake_type,stake_amount,choice_code,resource_before)
  values(p_request_id,v_character_id,p_game_code,p_house_mode,p_stake_type,p_stake_amount,p_choice,v_before);
  if p_house_mode='system' then
    v_result:=public.play_system_house_game_v0141_fix7a(p_game_code,p_stake_type,p_stake_amount,p_choice);
    select id into v_game_id from public.casino_house_games
    where character_id=v_character_id and request_id is null order by created_at desc,id desc limit 1 for update;
    if v_game_id is not null then update public.casino_house_games set request_id=p_request_id,settlement_version='V1.0_FIX4' where id=v_game_id;end if;
  else
    if p_stake_type<>'spirit_stone' then raise exception 'CASINO_PLAYER_HOUSE_ONLY_SPIRIT_STONE';end if;
    perform pg_advisory_xact_lock(hashtextextended('casino-player-house-dealer',14301));
    v_dealer:=public.casino_player_house_resolve_dealer_v1();
    if v_dealer is null then raise exception 'CASINO_PLAYER_HOUSE_NOT_ACTIVE';end if;
    v_result:=public.casino_play_player_house_v1_fix4(v_dealer,p_game_code,p_stake_type,p_stake_amount,p_choice,p_request_id);
  end if;
  v_after:=public.casino_available_v1(v_character_id,p_stake_type);
  update public.casino_bet_requests_v1 set status='settled',resource_after=v_after,result_payload=v_result,settled_at=now()
  where character_id=v_character_id and request_id=p_request_id;
  return v_result;
end;
$$;

-- 鱼虾灵局玩家庄在落注时真实扣除3倍最大赔付作为保证金。
create or replace function public.place_fish_shrimp_bet_v1_fix4(
  p_request_id uuid,p_house_mode text,p_stake_type text,p_symbol_code text,p_stake_amount bigint
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_character_id uuid:=public.casino_current_character_id_v1();v_existing jsonb;v_result jsonb;
  v_request public.casino_bet_requests_v1%rowtype;
  v_before bigint:=0;v_after bigint:=0;v_limit bigint:=0;v_round_id uuid;v_round public.casino_fish_rounds_v0148%rowtype;
  v_dealer uuid;v_dealer_name text;v_reserve numeric:=0;v_debit jsonb;
begin
  perform public.casino_assert_enabled_v1();
  if p_request_id is null then raise exception 'CASINO_REQUEST_ID_REQUIRED';end if;
  if p_house_mode not in('system','player') then raise exception 'FISH_INVALID_HOUSE_MODE';end if;
  if p_stake_type not in('spirit_stone','cultivation') then raise exception 'CASINO_INVALID_STAKE_TYPE';end if;
  if p_symbol_code not in('fish','shrimp','crab','coin','gourd','frog') then raise exception 'FISH_INVALID_SYMBOL';end if;
  perform pg_advisory_xact_lock(hashtextextended('casino-request:'||v_character_id::text||':'||p_request_id::text,104));
  select * into v_request from public.casino_bet_requests_v1
  where character_id=v_character_id and request_id=p_request_id;
  if found then
    if v_request.game_code is distinct from 'fish_shrimp'
       or v_request.house_mode is distinct from p_house_mode
       or v_request.stake_type is distinct from p_stake_type
       or v_request.stake_amount is distinct from p_stake_amount
       or v_request.choice_code is distinct from p_symbol_code then
      raise exception 'CASINO_REQUEST_PARAMETER_MISMATCH';
    end if;
    if v_request.status='settled' and v_request.result_payload is not null then return v_request.result_payload;end if;
    raise exception 'CASINO_REQUEST_IN_PROGRESS';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('casino-house-character:'||v_character_id::text,104));
  v_before:=public.casino_available_v1(v_character_id,p_stake_type);v_limit:=public.casino_house_stake_limit_v1(v_character_id,p_stake_type);
  if p_stake_amount is null or p_stake_amount<1 or p_stake_amount>v_limit then raise exception 'CASINO_STAKE_EXCEEDS_TEN_PERCENT';end if;
  insert into public.casino_bet_requests_v1(request_id,character_id,game_code,house_mode,stake_type,stake_amount,choice_code,resource_before)
  values(p_request_id,v_character_id,'fish_shrimp',p_house_mode,p_stake_type,p_stake_amount,p_symbol_code,v_before);
  if p_house_mode='system' then
    v_result:=public.place_fish_shrimp_bet_v0148('system',p_stake_type,p_symbol_code,p_stake_amount);
  else
    if p_stake_type<>'spirit_stone' then raise exception 'CASINO_PLAYER_HOUSE_ONLY_SPIRIT_STONE';end if;
    v_round_id:=public.casino_fish_ensure_round_v0148();
    select * into v_round from public.casino_fish_rounds_v0148 where id=v_round_id for share;
    if clock_timestamp()>=v_round.betting_closes_at then raise exception 'FISH_BETTING_CLOSED';end if;
    perform pg_advisory_xact_lock(hashtextextended('casino-player-house-dealer',14301));
    v_dealer:=public.casino_player_house_resolve_dealer_v1();
    if v_dealer is null then raise exception 'CASINO_PLAYER_HOUSE_NOT_ACTIVE';end if;
    if v_dealer=v_character_id then raise exception 'CASINO_PLAYER_HOUSE_SELF_BET_FORBIDDEN';end if;
    if v_character_id::text<v_dealer::text then
      perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||v_character_id::text,141));
      perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||v_dealer::text,141));
    else
      perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||v_dealer::text,141));
      perform pg_advisory_xact_lock(hashtextextended('spirit-stone:'||v_character_id::text,141));
    end if;
    v_reserve:=p_stake_amount::numeric*3;
    if v_reserve>9007199254740991::numeric then raise exception 'CASINO_STAKE_TOO_LARGE';end if;
    if public.spirit_stone_balance_v0141(v_dealer)<v_reserve::bigint then raise exception 'CASINO_PLAYER_HOUSE_DEALER_INSUFFICIENT';end if;
    select name into v_dealer_name from public.player_characters where id=v_dealer;
    perform public.casino_record_activity_v1(v_character_id,'house','spirit_stone');
    v_debit:=public.casino_debit_v1(v_character_id,'spirit_stone',p_stake_amount,'house','fish_shrimp');
    perform public.spirit_stone_debit_v0141(v_dealer,v_reserve::bigint,'CASINO_PLAYER_HOUSE_DEALER_INSUFFICIENT');
    insert into public.casino_fish_bets_v0148(
      round_id,character_id,house_mode,dealer_character_id,dealer_name_snapshot,stake_type,symbol_code,stake_amount,
      request_id,dealer_reserved_amount,settlement_version
    ) values(v_round_id,v_character_id,'player',v_dealer,coalesce(v_dealer_name,'玩家庄'),'spirit_stone',p_symbol_code,p_stake_amount,
      p_request_id,v_reserve::bigint,'V1.0_FIX4');
    v_result:=public.get_fish_shrimp_state_v0148(20);
  end if;
  v_after:=public.casino_available_v1(v_character_id,p_stake_type);
  update public.casino_bet_requests_v1 set status='settled',resource_after=v_after,result_payload=v_result,settled_at=now()
  where character_id=v_character_id and request_id=p_request_id;
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
  v_round public.casino_fish_rounds_v0148%rowtype;v_bet public.casino_fish_bets_v0148%rowtype;v_count integer;
  v_gross bigint;v_pool_calc jsonb;v_pool bigint;v_heaven bigint;v_requested bigint;v_credit jsonb;v_payout bigint;v_net bigint;
  v_fee_bps integer:=500;v_fee bigint;v_profit bigint;v_dealer_debit bigint;v_dealer_credit bigint;v_dealer_refund bigint;v_ticket boolean;
begin
  if p_round_id is null then return false;end if;
  perform pg_advisory_xact_lock(hashtextextended('fish-settle:'||p_round_id::text,148));
  select * into v_round from public.casino_fish_rounds_v0148 where id=p_round_id for update;
  if v_round.id is null then return false;end if;if v_round.is_settled then return true;end if;if now()<v_round.settles_at then return false;end if;
  select greatest(0,least(10000,coalesce(player_house_win_commission_bps,500))) into v_fee_bps from public.casino_settings where singleton_id=1;
  for v_bet in select * from public.casino_fish_bets_v0148 where round_id=p_round_id and not is_settled
    order by character_id::text,coalesce(dealer_character_id::text,''),created_at,id for update
  loop
    select count(*)::integer into v_count from unnest(v_round.result_symbols) as symbol_value where symbol_value=v_bet.symbol_code;
    v_pool:=0;v_heaven:=0;v_payout:=0;v_net:=-v_bet.stake_amount;v_fee:=0;v_dealer_debit:=0;v_dealer_credit:=0;v_dealer_refund:=0;
    if v_bet.house_mode='system' then
      if v_count>0 then
        v_gross:=(v_bet.stake_amount::numeric*v_count)::bigint;
        v_pool_calc:=public.casino_take_pool_share_v0141_fix7a(v_bet.stake_type,v_gross,500,'win');v_pool:=coalesce((v_pool_calc->>'pool_contribution')::bigint,0);
        v_requested:=v_bet.stake_amount+greatest(v_gross-v_pool,0);
        if v_pool>0 then update public.casino_pools set amount=amount+v_pool,updated_at=now() where stake_type=v_bet.stake_type;end if;
        v_credit:=public.casino_credit_result_v0141(v_bet.character_id,v_bet.stake_type,v_requested);v_payout:=coalesce((v_credit->>'granted_amount')::bigint,0);v_net:=v_payout-v_bet.stake_amount;
      else
        v_pool_calc:=public.casino_take_pool_share_v0141_fix7a(v_bet.stake_type,v_bet.stake_amount,1000,'loss');v_pool:=coalesce((v_pool_calc->>'pool_contribution')::bigint,0);v_heaven:=greatest(v_bet.stake_amount-v_pool,0);
        if v_pool>0 then update public.casino_pools set amount=amount+v_pool,updated_at=now() where stake_type=v_bet.stake_type;end if;
        if v_bet.stake_type='cultivation' then perform public.casino_realign_after_loss_v1(v_bet.character_id);end if;
      end if;
      v_ticket:=public.casino_add_ticket_v1(v_bet.character_id,v_bet.stake_type);
    else
      if v_bet.dealer_character_id is null or v_bet.dealer_reserved_amount<v_bet.stake_amount*3 then raise exception 'CASINO_PLAYER_HOUSE_RESERVE_MISSING';end if;
      if v_count>0 then
        v_gross:=(v_bet.stake_amount::numeric*v_count)::bigint;
        v_pool_calc:=public.casino_take_pool_share_v0141_fix7a('spirit_stone',v_gross,v_fee_bps,'win');v_pool:=coalesce((v_pool_calc->>'pool_contribution')::bigint,0);
        v_profit:=greatest(v_gross-v_pool,0);v_payout:=v_bet.stake_amount+v_profit;v_net:=v_profit;
        perform public.award_spirit_stones_v3(v_bet.character_id,v_payout);
        if v_pool>0 then update public.casino_pools set amount=amount+v_pool,updated_at=now() where stake_type='spirit_stone';end if;
        v_dealer_debit:=v_gross;v_dealer_refund:=greatest(v_bet.dealer_reserved_amount-v_gross,0);
        if v_dealer_refund>0 then perform public.award_spirit_stones_v3(v_bet.dealer_character_id,v_dealer_refund);end if;
      else
        v_pool_calc:=public.casino_take_pool_share_v0141_fix7a('spirit_stone',v_bet.stake_amount,v_fee_bps,'loss');v_pool:=coalesce((v_pool_calc->>'pool_contribution')::bigint,0);
        v_dealer_credit:=greatest(v_bet.stake_amount-v_pool,0);v_dealer_refund:=v_bet.dealer_reserved_amount;
        perform public.award_spirit_stones_v3(v_bet.dealer_character_id,v_dealer_refund+v_dealer_credit);
        if v_pool>0 then update public.casino_pools set amount=amount+v_pool,updated_at=now() where stake_type='spirit_stone';end if;
      end if;
      v_fee:=v_pool;
    end if;
    update public.casino_fish_bets_v0148 set result_count=v_count,payout_amount=v_payout,net_profit=v_net,
      commission_amount=v_fee,pool_contribution=v_pool,heaven_recovery=v_heaven,dealer_debit_amount=v_dealer_debit,
      dealer_credit_amount=v_dealer_credit,dealer_refund_amount=v_dealer_refund,system_cover_amount=0,
      outcome_code=case when v_count>0 then 'win' else 'loss' end,is_settled=true,settled_at=now(),
      settlement_version=coalesce(settlement_version,'V1.0_FIX4') where id=v_bet.id;
  end loop;
  update public.casino_fish_rounds_v0148 set is_settled=true,settled_at=now() where id=p_round_id;
  perform public.world_event_publish_fish_round_v0151(p_round_id);return true;
end;
$$;

-- 旧客户端入口全部撤权，防止绕过10%限制与幂等保护。
revoke all on function public.play_house_game_v0147(text,text,text,bigint,text) from public,anon,authenticated;
revoke all on function public.play_house_game_v1(text,text,bigint,text) from public,anon,authenticated;
revoke all on function public.place_fish_shrimp_bet_v0148(text,text,text,bigint) from public,anon,authenticated;
revoke all on function public.casino_play_player_house_v1(uuid,text,text,bigint,text) from public,anon,authenticated;
revoke all on function public.casino_play_player_house_v1_fix4(uuid,text,text,bigint,text,uuid) from public,anon,authenticated;
revoke all on function public.casino_house_stake_limit_v1(uuid,text) from public,anon,authenticated;
revoke all on function public.play_house_game_v1_fix4(uuid,text,text,text,bigint,text) from public,anon;
revoke all on function public.place_fish_shrimp_bet_v1_fix4(uuid,text,text,text,bigint) from public,anon;
grant execute on function public.play_house_game_v1_fix4(uuid,text,text,text,bigint,text) to authenticated;
grant execute on function public.place_fish_shrimp_bet_v1_fix4(uuid,text,text,text,bigint) to authenticated;

comment on function public.play_house_game_v1_fix4(uuid,text,text,text,bigint,text) is
  'V1.0 FIX4：唯一请求幂等；单局最多当前可用资源10%；玩家庄最大赔付锁定、5%入造化池、零系统兜底。';
comment on function public.place_fish_shrimp_bet_v1_fix4(uuid,text,text,text,bigint) is
  'V1.0 FIX4：鱼虾灵局10%下注上限与请求幂等；玩家庄下注时预扣3倍最大赔付保证金。';

notify pgrst,'reload schema';
commit;
