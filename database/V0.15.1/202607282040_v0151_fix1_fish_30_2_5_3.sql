-- 九霄问道 V0.15.1 CACHE18 鱼虾40秒节奏修正
-- 正确节奏：30秒下注、2秒封盘、5秒开骰、3秒结算展示。
-- 可在已执行V0.15.1 CACHE17的数据库上安全追加执行。

begin;

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

  v_start:=to_timestamp(p_round_no*40);
  v_result:=array[
    v_symbols[1+floor(random()*6)::integer],
    v_symbols[1+floor(random()*6)::integer],
    v_symbols[1+floor(random()*6)::integer]
  ];

  insert into public.casino_fish_rounds_v0148(
    round_no,starts_at,betting_closes_at,reveal_at,settles_at,ends_at,result_symbols
  ) values(
    p_round_no,v_start,v_start+interval '30 seconds',v_start+interval '32 seconds',
    v_start+interval '37 seconds',v_start+interval '40 seconds',v_result
  )
  on conflict(round_no) do update set round_no=excluded.round_no
  returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.casino_fish_ensure_round_v0148()
returns uuid
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_current_no bigint:=floor(extract(epoch from clock_timestamp())/40)::bigint;
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
  elsif v_now<v_round.settles_at+interval '3 seconds' then v_phase:='settled';v_phase_end:=v_round.settles_at+interval '3 seconds';
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
      'round_seconds',40,'betting_seconds',30,'lock_seconds',2,
      'reveal_seconds',5,'settlement_seconds',3,'next_seconds',0,
      'player_house_commission_bps',500
    )
  );
end;
$$;

-- 纠正当前尚未结算轮次的阶段时间；不修改历史已结算数据。
update public.casino_fish_rounds_v0148
set betting_closes_at=starts_at+interval '30 seconds',
    reveal_at=starts_at+interval '32 seconds',
    settles_at=starts_at+interval '37 seconds',
    ends_at=starts_at+interval '40 seconds'
where not is_settled and ends_at>now();

update public.jiuxiao_app_release_control
set release_name='V0.15.1 CACHE18',
    cache_epoch=greatest(cache_epoch,18),
    notice_text='鱼虾灵局40秒节奏已修正为30秒下注、2秒封盘、5秒开骰、3秒结算展示；赌场界闻庄家与净输赢播报保持启用。',
    updated_at=now()
where singleton_id=1;

commit;
notify pgrst,'reload schema';
