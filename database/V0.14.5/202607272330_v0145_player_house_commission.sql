-- B-20260727-PLAYER-HOUSE-COMMISSION-05
-- 玩家庄赢家毛利润5%佣金。
-- 用户明确批准修改V0.14.4“玩家庄零抽成”保护规则。
-- 不修改FIX7A系统庄、贵宾赌契、造化池与任何开奖概率/倍率。

begin;

alter table public.casino_settings
  add column if not exists player_house_win_commission_bps integer not null default 500;

update public.casino_settings
set player_house_win_commission_bps=500
where singleton_id=1;

do $$
begin
  if not exists(
    select 1
    from pg_constraint c
    join pg_class t on t.oid=c.conrelid
    join pg_namespace n on n.oid=t.relnamespace
    where n.nspname='public'
      and t.relname='casino_settings'
      and c.conname='casino_settings_player_house_commission_bps_check'
  ) then
    alter table public.casino_settings
      add constraint casino_settings_player_house_commission_bps_check
      check(player_house_win_commission_bps between 0 and 10000);
  end if;
end;
$$;

create or replace function public.get_casino_player_house_status_v1()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_current_id uuid;
  v_dealer_id uuid;
  v_top_id uuid;
  v_top_name text;
  v_top_wealth bigint:=0;
  v_dealer_name text;
  v_dealer_wealth bigint:=0;
  v_enabled boolean:=false;
  v_min_wealth bigint:=5000000;
  v_destiny_odds integer:=34;
  v_commission_bps integer:=500;
  v_can_activate boolean:=false;
begin
  v_current_id:=public.casino_current_character_id_v1();
  v_dealer_id:=public.casino_player_house_resolve_dealer_v1();

  select coalesce(s.player_house_enabled,false),coalesce(s.player_house_min_wealth,5000000),
         coalesce(s.spirit_dice_destiny_triple_net_odds,34),
         coalesce(s.player_house_win_commission_bps,500)
  into v_enabled,v_min_wealth,v_destiny_odds,v_commission_bps
  from public.casino_settings s
  where s.singleton_id=1;

  select x.character_id,x.character_name,x.wealth
  into v_top_id,v_top_name,v_top_wealth
  from public.casino_player_house_top_candidate_v1() x;

  if v_dealer_id is not null then
    select pc.name,public.spirit_stone_balance_v0141(pc.id)
    into v_dealer_name,v_dealer_wealth
    from public.player_characters pc
    where pc.id=v_dealer_id;
  end if;

  v_can_activate:=v_enabled
    and v_dealer_id is null
    and v_current_id=v_top_id
    and coalesce(v_top_wealth,0)>v_min_wealth;

  return jsonb_build_object(
    'status','ok',
    'mode',case when v_dealer_id is null then 'system' else 'player' end,
    'dealer_name',case when v_dealer_id is null then '荷老' else coalesce(v_dealer_name,'无名庄家') end,
    'dealer_wealth',case when v_dealer_id is null then null else v_dealer_wealth end,
    'is_self_dealer',v_dealer_id=v_current_id,
    'can_activate',v_can_activate,
    'can_deactivate',v_dealer_id=v_current_id,
    'top_name',v_top_name,
    'top_wealth',coalesce(v_top_wealth,0),
    'is_self_top',v_current_id=v_top_id,
    'eligibility_threshold',v_min_wealth,
    'eligibility_rule','财富榜第1且统一灵石严格超过500万，由本人自愿上庄',
    'player_house_only_spirit_stone',v_dealer_id is not null,
    'player_house_win_commission_bps',v_commission_bps,
    'player_house_win_commission_percent',v_commission_bps::numeric/100,
    'player_house_pool_contribution_bps',0,
    'player_house_heaven_recovery_bps',0,
    -- 继续采用原V0.14.4保守验资展示：不因佣金降低受理前保证金要求。
    'max_stake_spirit_dice',case when v_dealer_id is null then null else floor(v_dealer_wealth::numeric/greatest(v_destiny_odds,1))::bigint end,
    'max_stake_turtle_oracle',case when v_dealer_id is null then null else floor(v_dealer_wealth::numeric/3)::bigint end
  );
end;
$$;

create or replace function public.casino_play_player_house_v1(
  p_dealer_character_id uuid,
  p_game_code text,
  p_stake_type text,
  p_stake_amount bigint,
  p_choice text
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_bettor_id uuid;
  v_dealer_name text;
  v_bettor_balance bigint:=0;
  v_dealer_balance bigint:=0;
  v_dealer_balance_after bigint:=0;
  v_max_net_odds integer:=1;
  v_max_liability_numeric numeric:=0;
  v_max_liability bigint:=0;
  v_draw jsonb;
  v_won boolean:=false;
  v_net_odds integer:=0;
  v_commission_bps integer:=500;
  v_gross_profit_numeric numeric:=0;
  v_gross_profit bigint:=0;
  v_commission bigint:=0;
  v_player_profit bigint:=0;
  v_reward bigint:=0;
  v_dealer_debit bigint:=0;
  v_dealer_credit bigint:=0;
  v_result_text text;
  v_result_payload jsonb;
  v_debit jsonb;
begin
  perform public.casino_assert_enabled_v1();

  if p_dealer_character_id is null then
    raise exception 'CASINO_PLAYER_HOUSE_DEALER_MISSING';
  end if;
  if p_game_code not in ('spirit_dice','turtle_oracle') then
    raise exception 'CASINO_INVALID_HOUSE_GAME';
  end if;
  if not public.casino_validate_choice_v1(p_game_code,p_choice) then
    raise exception 'CASINO_INVALID_CHOICE';
  end if;
  if p_stake_type<>'spirit_stone' then
    raise exception 'CASINO_PLAYER_HOUSE_ONLY_SPIRIT_STONE';
  end if;
  if p_stake_amount is null or p_stake_amount<10 then
    raise exception 'CASINO_STAKE_BELOW_MINIMUM';
  end if;
  if p_stake_amount>9007199254740991 then
    raise exception 'CASINO_STAKE_TOO_LARGE';
  end if;

  v_bettor_id:=public.casino_current_character_id_v1();
  if v_bettor_id=p_dealer_character_id then
    raise exception 'CASINO_PLAYER_HOUSE_SELF_BET_FORBIDDEN';
  end if;

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
  select pc.name into v_dealer_name from public.player_characters pc where pc.id=p_dealer_character_id;
  select coalesce(s.player_house_win_commission_bps,500)
  into v_commission_bps
  from public.casino_settings s
  where s.singleton_id=1;
  v_commission_bps:=greatest(0,least(10000,coalesce(v_commission_bps,500)));

  v_max_net_odds:=case
    when p_game_code='spirit_dice' then coalesce((select s.spirit_dice_destiny_triple_net_odds from public.casino_settings s where s.singleton_id=1),34)
    else 3
  end;
  -- 保持原V0.14.4保守验资：仍按未扣佣金的最高毛利润检查庄家余额。
  v_max_liability_numeric:=p_stake_amount::numeric*v_max_net_odds::numeric;
  if v_max_liability_numeric>9007199254740991::numeric then
    raise exception 'CASINO_STAKE_TOO_LARGE';
  end if;
  v_max_liability:=v_max_liability_numeric::bigint;

  if v_bettor_balance<p_stake_amount then
    raise exception 'CASINO_INSUFFICIENT_SPIRIT_STONES';
  end if;
  if v_dealer_balance<v_max_liability then
    raise exception 'CASINO_PLAYER_HOUSE_DEALER_INSUFFICIENT';
  end if;

  perform public.casino_record_activity_v1(v_bettor_id,'house','spirit_stone');
  v_debit:=public.casino_debit_v1(v_bettor_id,'spirit_stone',p_stake_amount,'house',p_game_code);
  v_draw:=public.casino_player_house_draw_result_v1(p_game_code,p_choice);
  v_won:=coalesce((v_draw->>'won')::boolean,false);
  v_net_odds:=coalesce((v_draw->>'net_odds')::integer,0);
  v_result_payload:=coalesce(v_draw->'result_payload','{}'::jsonb);

  if v_won then
    v_gross_profit_numeric:=p_stake_amount::numeric*v_net_odds::numeric;
    if v_gross_profit_numeric>9007199254740991::numeric then
      raise exception 'CASINO_STAKE_TOO_LARGE';
    end if;
    v_gross_profit:=v_gross_profit_numeric::bigint;
    -- 灵石不可拆分，佣金向下取整；押100且毛利润1倍时恰为5。
    v_commission:=floor(v_gross_profit::numeric*v_commission_bps::numeric/10000)::bigint;
    v_player_profit:=greatest(v_gross_profit-v_commission,0);

    perform public.spirit_stone_debit_v0141(
      p_dealer_character_id,v_player_profit,'CASINO_PLAYER_HOUSE_DEALER_INSUFFICIENT'
    );
    perform public.award_spirit_stones_v3(v_bettor_id,p_stake_amount+v_player_profit);
    v_reward:=p_stake_amount+v_player_profit;
    v_dealer_debit:=v_player_profit;
    v_dealer_credit:=0;
    v_result_text:=format(
      '玩家庄家【%s】开局：%s 本局押注%s枚灵石；本金%s枚原数返还，按实际净倍率%s倍计算毛利润%s枚，扣除庄家佣金%s%%共%s枚，玩家净赢%s枚，合计到账%s枚。佣金由当局庄家保留，不进入造化池。',
      coalesce(v_dealer_name,'无名庄家'),v_draw->>'result_text',
      p_stake_amount,p_stake_amount,v_net_odds,v_gross_profit,
      trim(to_char(v_commission_bps::numeric/100,'FM999990.##')),v_commission,
      v_player_profit,v_reward
    );
  else
    perform public.award_spirit_stones_v3(p_dealer_character_id,p_stake_amount);
    v_reward:=0;
    v_gross_profit:=0;
    v_commission:=0;
    v_player_profit:=0;
    v_dealer_debit:=0;
    v_dealer_credit:=p_stake_amount;
    v_result_text:=format(
      '玩家庄家【%s】开局：%s 本局押注%s枚灵石全部归庄家；败局不另收佣金，也不进入造化池。',
      coalesce(v_dealer_name,'无名庄家'),v_draw->>'result_text',p_stake_amount
    );
  end if;

  v_dealer_balance_after:=public.spirit_stone_balance_v0141(p_dealer_character_id);
  v_result_payload:=v_result_payload||jsonb_build_object(
    'house_mode','player',
    'dealer_name',coalesce(v_dealer_name,'无名庄家'),
    'stake_type','spirit_stone',
    'net_odds',v_net_odds,
    'gross_profit',v_gross_profit,
    'nominal_profit',v_gross_profit,
    'commission_bps',v_commission_bps,
    'commission_amount',v_commission,
    'player_net_profit',case when v_won then v_player_profit else -p_stake_amount end,
    'nominal_reward',case when v_won then p_stake_amount+v_gross_profit else 0 end,
    'actual_reward',v_reward,
    'pool_contribution',0,
    'pool_rate_bps',0,
    'heaven_recovery',0,
    'ticket_awarded',false,
    'dealer_debit_amount',v_dealer_debit,
    'dealer_credit_amount',v_dealer_credit,
    'dealer_retained_commission',v_commission,
    'dealer_balance_before',v_dealer_balance,
    'dealer_balance_after',v_dealer_balance_after,
    'max_liability_amount',v_max_liability,
    'settlement_rule','winner_profit_commission_5pct'
  );

  insert into public.casino_house_games(
    character_id,game_code,stake_type,stake_amount,choice_code,outcome_code,
    reward_amount,nominal_reward_amount,fee_amount,pool_contribution,heaven_recovery_amount,
    result_payload,result_text,house_mode,dealer_character_id,dealer_name_snapshot,
    dealer_debit_amount,dealer_credit_amount,max_liability_amount
  ) values(
    v_bettor_id,p_game_code,'spirit_stone',p_stake_amount,p_choice,
    case when v_won then 'win' else 'loss' end,
    v_reward,case when v_won then p_stake_amount+v_gross_profit else 0 end,v_commission,0,0,
    v_result_payload,v_result_text,'player',p_dealer_character_id,coalesce(v_dealer_name,'无名庄家'),
    v_dealer_debit,v_dealer_credit,v_max_liability
  );

  return jsonb_build_object(
    'won',v_won,
    'reward',v_reward,
    'nominal_reward',case when v_won then p_stake_amount+v_gross_profit else 0 end,
    'nominal_profit',v_gross_profit,
    'gross_profit',v_gross_profit,
    'net_profit',case when v_won then v_player_profit else -p_stake_amount end,
    'fee',v_commission,
    'commission_bps',v_commission_bps,
    'pool_contribution',0,
    'heaven_recovery',0,
    'ticket_awarded',false,
    'house_mode','player',
    'dealer_name',coalesce(v_dealer_name,'无名庄家'),
    'dealer_debit_amount',v_dealer_debit,
    'dealer_credit_amount',v_dealer_credit,
    'dealer_retained_commission',v_commission,
    'max_liability_amount',v_max_liability,
    'result_text',v_result_text,
    'result_payload',v_result_payload,
    'drop',null
  );
end;
$$;

comment on function public.play_house_game_v1(text,text,bigint,text) is
  '统一大堂入口：有效玩家庄时，赢家毛利润5%作为庄家佣金、本金原返、零入池；否则完整调用原FIX7A系统庄。';
comment on function public.casino_play_player_house_v1(uuid,text,text,bigint,text) is
  '玩家庄即时结算：败局本金全归庄家；胜局本金原返，毛利润95%给闲家、5%由庄家保留，佣金不入造化池。';

commit;
