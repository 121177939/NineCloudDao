-- 九霄问道 V0.15.1 回滚
-- 回滚到 V0.15.0 CACHE16：鱼虾60秒轮次、鱼虾不进入界闻。
begin;

drop function if exists public.world_event_publish_fish_round_v0151(uuid);

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

create or replace function public.world_event_from_house_game_v0140()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cfg boolean := true;
  v_character public.player_characters%rowtype;
  v_world_year integer;
  v_unit text := case when new.stake_type = 'cultivation' then '点修为' else '枚灵石' end;
  v_game_name text := case new.game_code when 'spirit_dice' then '灵骰问道' else '气运龟卜' end;
  v_title text;
  v_content text;
  v_level smallint := 1;
  v_net bigint := greatest(0, coalesce(new.reward_amount, 0) - coalesce(new.stake_amount, 0));
  v_destiny_triple boolean := false;
begin
  -- V0.15.0：鱼虾灵局属于局内连续操作，不进入九霄界闻公开播报。
  if coalesce(new.game_code, '') = 'fish_shrimp' then
    return new;
  end if;

  v_destiny_triple := coalesce((new.result_payload->>'is_destiny_triple')::boolean, false);
  begin
    select s.casino_enabled into v_cfg
    from public.jiuxiao_world_event_settings s
    where s.singleton_id = 1;
    if not coalesce(v_cfg, true) then return new; end if;

    select pc.* into v_character
    from public.player_characters pc
    where pc.id = new.character_id;
    if v_character.id is null then return new; end if;

    select gw.current_year into v_world_year
    from public.game_worlds gw
    where gw.id = v_character.world_id;

    if new.outcome_code = 'win' and v_destiny_triple then
      v_title := '天命豹子';
      v_level := 3;
      v_content := format(
        '紫气贯入万运博弈楼，修士【%s】以%s%s落注“灵骰问道”，竟遇天命豹子，一局净得%s%s。',
        v_character.name, new.stake_amount, v_unit, v_net, v_unit
      );
    elsif new.outcome_code = 'win' then
      v_title := case when v_net >= greatest(100000, new.stake_amount * 10) then '一掷得势' else '赌运亨通' end;
      v_level := case when new.stake_type = 'cultivation' or v_net >= 100000 then 2 else 1 end;
      v_content := format(
        '修士【%s】于万运博弈楼以%s%s落注“%s”，押中天机，一局净得%s%s。',
        v_character.name, new.stake_amount, v_unit, v_game_name, v_net, v_unit
      );
    else
      v_title := case when new.stake_type = 'cultivation' then '修为折损' else '时运不济' end;
      v_level := case when new.stake_type = 'cultivation' or new.stake_amount >= 100000 then 2 else 1 end;
      v_content := format(
        '修士【%s】于万运博弈楼以%s%s落注“%s”，奈何天意难测，一局折损%s%s。',
        v_character.name, new.stake_amount, v_unit, v_game_name, new.stake_amount, v_unit
      );
    end if;

    perform public.world_event_publish_v0140(
      v_character.world_id,
      v_world_year,
      case when v_destiny_triple then 'casino_destiny_triple' else 'casino_house_' || new.outcome_code end,
      v_level,
      v_character.id,
      v_character.name,
      v_title,
      v_content,
      'casino_house_games',
      new.id::text,
      jsonb_build_object(
        'game_code', new.game_code,
        'stake_type', new.stake_type,
        'stake_amount', new.stake_amount,
        'reward_amount', new.reward_amount,
        'net_change', case when new.outcome_code = 'win' then v_net else -new.stake_amount end,
        'is_destiny_triple', v_destiny_triple
      ),
      false,
      null
    );
  exception when others then
    return new;
  end;
  return new;
end;
$$;

update public.jiuxiao_app_release_control
set release_name='V0.15.0 CACHE16',
    cache_epoch=greatest(cache_epoch,16),
    notice_text='已回滚V0.15.1；鱼虾灵局恢复60秒轮次并停止发布九霄界闻。',
    updated_at=now()
where singleton_id=1;

commit;
notify pgrst,'reload schema';
