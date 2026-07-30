-- 九霄问道 V1.5 CACHE43
-- 88：牌九5分钟首局关闭、底注10倍入座门槛、余额不足自动转观战、玩家庄比例赔付、无单手和局、大牌九平局退手续费、暂停售修为牌九。
-- 生产库已完成87号时直接执行本脚本。

begin;

do $$
begin
  if to_regprocedure('public.join_paigow_room_bpaigow01(uuid,smallint,boolean)') is null then raise exception 'V1_5_REQUIRED:join_room_rpc'; end if;
  if to_regprocedure('public.paigow_settle_round_internal_bpaigow01(uuid)') is null then raise exception 'V1_5_REQUIRED:settlement_rpc'; end if;
  if to_regclass('public.paigow_settings_bpaigow01') is null then raise exception 'V1_5_REQUIRED:settings'; end if;
end
$$;

alter table public.paigow_settings_bpaigow01
  add column if not exists idle_close_seconds integer not null default 300 check(idle_close_seconds between 60 and 3600),
  add column if not exists minimum_entry_multiplier integer not null default 10 check(minimum_entry_multiplier between 1 and 1000),
  add column if not exists cultivation_stakes_enabled boolean not null default false;

alter table public.paigow_round_players_bpaigow01
  add column if not exists fee_refund_amount bigint not null default 0 check(fee_refund_amount>=0);

alter table public.paigow_rooms_bpaigow01
  alter column idle_expires_at set default (now()+interval '5 minutes');

update public.paigow_settings_bpaigow01
set idle_close_seconds=300,
    minimum_entry_multiplier=10,
    cultivation_stakes_enabled=false,
    updated_at=now()
where singleton_id=1;

-- 已存在但未开始的房间按创建时间改为5分钟；超时房间由清理函数关闭。
update public.paigow_rooms_bpaigow01
set idle_expires_at=created_at+interval '5 minutes',updated_at=now()
where first_round_started_at is null and status='waiting';

create or replace function public.paigow_minimum_entry_balance_bpaigow01(p_base_stake bigint)
returns bigint
language plpgsql
immutable
as $$
begin
  if p_base_stake is null or p_base_stake<=0 then return 0; end if;
  if p_base_stake>922337203685477580 then raise exception 'PAIGOW_ENTRY_REQUIREMENT_OVERFLOW'; end if;
  return p_base_stake*10;
end
$$;

create or replace function public.paigow_cleanup_rooms_bpaigow01()
returns integer
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_ids uuid[];
  v_count integer:=0;
  v_cult_enabled boolean:=false;
begin
  select coalesce(cultivation_stakes_enabled,false)
  into v_cult_enabled
  from public.paigow_settings_bpaigow01 where singleton_id=1;

  select array_agg(q.id) into v_ids
  from (
    select id from public.paigow_rooms_bpaigow01
    where status='waiting'
      and (
        (first_round_started_at is null and idle_expires_at<=clock_timestamp())
        or (stake_type='cultivation' and not v_cult_enabled)
      )
    for update
  ) q;

  if coalesce(array_length(v_ids,1),0)>0 then
    update public.paigow_room_members_bpaigow01
    set left_at=clock_timestamp(),ready=false,ready_deadline=null
    where room_id=any(v_ids) and left_at is null;

    update public.paigow_rooms_bpaigow01
    set status='closed',closed_at=clock_timestamp(),auto_start_at=null,updated_at=now()
    where id=any(v_ids);
    get diagnostics v_count=row_count;
  end if;
  return v_count;
end
$$;

create or replace function public.paigow_eject_underfunded_players_bpaigow01(p_room_id uuid)
returns integer
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_room public.paigow_rooms_bpaigow01%rowtype;
  v_required bigint;
  v_count integer:=0;
begin
  select * into v_room from public.paigow_rooms_bpaigow01 where id=p_room_id for update;
  if v_room.id is null or v_room.status<>'waiting' then return 0; end if;
  v_required:=public.paigow_minimum_entry_balance_bpaigow01(v_room.base_stake);

  update public.paigow_room_members_bpaigow01 m
  set seat_no=null,role='spectator',ready=false,ready_deadline=null
  where m.room_id=p_room_id and m.left_at is null and m.role='player'
    and public.casino_available_v1(m.character_id,v_room.stake_type)<v_required;
  get diagnostics v_count=row_count;
  return v_count;
end
$$;

create or replace function public.paigow_prepare_waiting_room_bpaigow01(p_room_id uuid)
returns void
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_room public.paigow_rooms_bpaigow01%rowtype;
  v_players integer;
  v_ready integer;
  v_min integer;
  v_auto_seconds integer;
  v_new_owner uuid;
  v_cult_enabled boolean:=false;
begin
  select * into v_room from public.paigow_rooms_bpaigow01 where id=p_room_id for update;
  if v_room.id is null or v_room.status<>'waiting' then return; end if;

  select coalesce(cultivation_stakes_enabled,false),coalesce(auto_start_seconds,2)
  into v_cult_enabled,v_auto_seconds
  from public.paigow_settings_bpaigow01 where singleton_id=1;

  if (v_room.first_round_started_at is null and v_room.idle_expires_at<=clock_timestamp())
     or (v_room.stake_type='cultivation' and not v_cult_enabled) then
    update public.paigow_room_members_bpaigow01
    set left_at=clock_timestamp(),ready=false,ready_deadline=null
    where room_id=p_room_id and left_at is null;
    update public.paigow_rooms_bpaigow01
    set status='closed',closed_at=clock_timestamp(),auto_start_at=null,updated_at=now()
    where id=p_room_id;
    return;
  end if;

  -- 10秒未准备者离开房间。
  update public.paigow_room_members_bpaigow01
  set left_at=clock_timestamp(),ready=false,ready_deadline=null
  where room_id=p_room_id and left_at is null and role='player' and not ready
    and ready_deadline is not null and ready_deadline<=clock_timestamp();

  -- 余额低于底注10倍者只转为观战，不中断已经进行的牌局。
  perform public.paigow_eject_underfunded_players_bpaigow01(p_room_id);

  if not exists(
    select 1 from public.paigow_room_members_bpaigow01
    where room_id=p_room_id and character_id=v_room.owner_character_id and left_at is null and role='player'
  ) then
    select character_id into v_new_owner
    from public.paigow_room_members_bpaigow01
    where room_id=p_room_id and left_at is null and role='player'
    order by joined_at,seat_no limit 1;

    if v_new_owner is null then
      update public.paigow_room_members_bpaigow01
      set left_at=clock_timestamp(),ready=false,ready_deadline=null
      where room_id=p_room_id and left_at is null;
      update public.paigow_rooms_bpaigow01
      set status='closed',closed_at=clock_timestamp(),auto_start_at=null,updated_at=now()
      where id=p_room_id;
      return;
    end if;

    update public.paigow_rooms_bpaigow01 set owner_character_id=v_new_owner,updated_at=now() where id=p_room_id;
  end if;

  select count(*),count(*) filter(where ready)
  into v_players,v_ready
  from public.paigow_room_members_bpaigow01
  where room_id=p_room_id and left_at is null and role='player';

  v_min:=case when v_room.duel_type='laohe' then 1 else 2 end;
  if v_players>=v_min and v_ready=v_players then
    update public.paigow_rooms_bpaigow01
    set auto_start_at=coalesce(auto_start_at,clock_timestamp()+make_interval(secs=>v_auto_seconds)),updated_at=now()
    where id=p_room_id and status='waiting';
  else
    update public.paigow_rooms_bpaigow01 set auto_start_at=null,updated_at=now()
    where id=p_room_id and status='waiting' and auto_start_at is not null;
  end if;
end
$$;

create or replace function public.create_paigow_room_bpaigow01(
  p_duel_type text,p_pvp_mode text,p_game_mode text,p_stake_type text,p_base_stake bigint
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_character uuid:=public.casino_current_character_id_v1();
  v_slot smallint;
  v_room public.paigow_rooms_bpaigow01%rowtype;
  v_required bigint;
begin
  perform public.paigow_assert_enabled_bpaigow01();
  perform public.paigow_cleanup_rooms_bpaigow01();

  if p_duel_type not in('laohe','pvp') or p_game_mode not in('small','big') then raise exception 'PAIGOW_ROOM_CONFIG_INVALID'; end if;
  if p_stake_type<>'spirit_stone' then raise exception 'PAIGOW_CULTIVATION_STAKES_TEMPORARILY_DISABLED'; end if;
  if p_duel_type='pvp' and p_pvp_mode not in('rob','boat') then raise exception 'PAIGOW_PVP_MODE_INVALID'; end if;
  if p_duel_type='laohe' then p_pvp_mode:=null; end if;
  if p_base_stake is null or p_base_stake<10 or p_base_stake>9007199254740 then raise exception 'PAIGOW_BASE_STAKE_INVALID'; end if;

  v_required:=public.paigow_minimum_entry_balance_bpaigow01(p_base_stake);
  if public.casino_available_v1(v_character,'spirit_stone')<v_required then
    raise exception 'PAIGOW_ENTRY_BALANCE_BELOW_TEN_TIMES_BASE';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('bpaigow01-room-slots',7101));
  select s::smallint into v_slot
  from generate_series(1,4) s
  where not exists(select 1 from public.paigow_rooms_bpaigow01 r where r.slot_no=s and r.status in('waiting','playing'))
  order by s limit 1;
  if v_slot is null then raise exception 'PAIGOW_ROOM_LIMIT_REACHED'; end if;

  insert into public.paigow_rooms_bpaigow01(
    slot_no,room_name,owner_character_id,duel_type,pvp_mode,game_mode,stake_type,base_stake,idle_expires_at
  ) values(
    v_slot,public.paigow_room_name_bpaigow01(v_slot),v_character,p_duel_type,p_pvp_mode,p_game_mode,'spirit_stone',p_base_stake,
    clock_timestamp()+interval '5 minutes'
  ) returning * into v_room;

  perform public.join_paigow_room_bpaigow01(v_room.id,1::smallint,false);
  return jsonb_build_object('room',to_jsonb(v_room),'state',public.get_paigow_room_state_bpaigow01(v_room.id));
end
$$;

create or replace function public.join_paigow_room_bpaigow01(p_room_id uuid,p_seat_no smallint default null,p_spectator boolean default false)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_character uuid:=public.casino_current_character_id_v1();
  v_room public.paigow_rooms_bpaigow01%rowtype;
  v_limit integer;v_players integer;v_existing_role text;v_required bigint;
begin
  perform public.paigow_assert_enabled_bpaigow01();
  perform public.paigow_cleanup_rooms_bpaigow01();
  select * into v_room from public.paigow_rooms_bpaigow01 where id=p_room_id and status in('waiting','playing') for update;
  if v_room.id is null then raise exception 'PAIGOW_ROOM_NOT_AVAILABLE'; end if;

  select role into v_existing_role from public.paigow_room_members_bpaigow01
  where room_id=p_room_id and character_id=v_character and left_at is null;
  if v_room.status='playing' and v_existing_role='player' then return public.get_paigow_room_state_bpaigow01(p_room_id); end if;
  if v_room.status='playing' and not p_spectator then raise exception 'PAIGOW_ROUND_ALREADY_PLAYING'; end if;

  v_limit:=public.paigow_room_capacity_bpaigow01(v_room.duel_type,v_room.game_mode);
  select count(*) into v_players from public.paigow_room_members_bpaigow01
  where room_id=p_room_id and left_at is null and role='player';

  if p_spectator or v_room.stake_type<>'spirit_stone' or (v_players>=v_limit and coalesce(v_existing_role,'')<>'player') then
    insert into public.paigow_room_members_bpaigow01(room_id,character_id,seat_no,role,left_at,ready)
    values(p_room_id,v_character,null,'spectator',null,false)
    on conflict(room_id,character_id) do update set seat_no=null,role='spectator',left_at=null,ready=false,ready_deadline=null,joined_at=now();
  else
    v_required:=public.paigow_minimum_entry_balance_bpaigow01(v_room.base_stake);
    if public.casino_available_v1(v_character,v_room.stake_type)<v_required then
      raise exception 'PAIGOW_ENTRY_BALANCE_BELOW_TEN_TIMES_BASE';
    end if;
    if p_seat_no is null or p_seat_no not between 1 and 9 then raise exception 'PAIGOW_SEAT_INVALID'; end if;
    if p_seat_no>v_limit then raise exception 'PAIGOW_SEAT_NOT_ACTIVE_FOR_MODE'; end if;
    if exists(select 1 from public.paigow_room_members_bpaigow01 where room_id=p_room_id and seat_no=p_seat_no and left_at is null and role='player' and character_id<>v_character) then
      raise exception 'PAIGOW_SEAT_OCCUPIED';
    end if;
    insert into public.paigow_room_members_bpaigow01(room_id,character_id,seat_no,role,left_at,ready)
    values(p_room_id,v_character,p_seat_no,'player',null,false)
    on conflict(room_id,character_id) do update set seat_no=excluded.seat_no,role='player',left_at=null,ready=false,joined_at=now();
  end if;
  perform public.paigow_prepare_waiting_room_bpaigow01(p_room_id);
  return public.get_paigow_room_state_bpaigow01(p_room_id);
end
$$;

create or replace function public.set_paigow_ready_bpaigow01(p_room_id uuid,p_ready boolean)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_character uuid:=public.casino_current_character_id_v1();
  v_room public.paigow_rooms_bpaigow01%rowtype;
  v_required bigint;
begin
  perform public.paigow_prepare_waiting_room_bpaigow01(p_room_id);
  select * into v_room from public.paigow_rooms_bpaigow01 where id=p_room_id and status='waiting' for update;
  if v_room.id is null then raise exception 'PAIGOW_ROOM_NOT_WAITING'; end if;

  if coalesce(p_ready,false) then
    v_required:=public.paigow_minimum_entry_balance_bpaigow01(v_room.base_stake);
    if public.casino_available_v1(v_character,v_room.stake_type)<v_required then
      update public.paigow_room_members_bpaigow01
      set role='spectator',seat_no=null,ready=false,ready_deadline=null
      where room_id=p_room_id and character_id=v_character and left_at is null and role='player';
      perform public.paigow_prepare_waiting_room_bpaigow01(p_room_id);
      return public.get_paigow_room_state_bpaigow01(p_room_id);
    end if;
  end if;

  update public.paigow_room_members_bpaigow01 set ready=coalesce(p_ready,false)
  where room_id=p_room_id and character_id=v_character and left_at is null and role='player';
  if not found then raise exception 'PAIGOW_PLAYER_NOT_SEATED_OR_READY_TIMEOUT'; end if;
  perform public.paigow_prepare_waiting_room_bpaigow01(p_room_id);
  return public.get_paigow_room_state_bpaigow01(p_room_id);
end
$$;

create or replace function public.get_paigow_lobby_bpaigow01()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_character uuid:=public.casino_current_character_id_v1();
  v_rooms jsonb;v_stone bigint;v_cult bigint;v_enabled boolean;v_row record;v_stone_available bigint;
begin
  perform public.paigow_cleanup_rooms_bpaigow01();
  for v_row in select id from public.paigow_rooms_bpaigow01 where status='waiting' loop
    perform public.paigow_prepare_waiting_room_bpaigow01(v_row.id);
  end loop;
  select enabled into v_enabled from public.paigow_settings_bpaigow01 where singleton_id=1;
  v_stone_available:=public.casino_available_v1(v_character,'spirit_stone');

  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'slot_no',r.slot_no,'name',r.room_name,'owner_character_id',r.owner_character_id,
    'is_owner',r.owner_character_id=v_character,
    'can_delete',r.owner_character_id=v_character and r.status='waiting'
      and not exists(select 1 from public.paigow_rounds_bpaigow01 ar where ar.room_id=r.id and ar.phase not in('settled','cancelled')),
    'duel_type',r.duel_type,'pvp_mode',r.pvp_mode,'game_mode',r.game_mode,'stake_type',r.stake_type,
    'base_stake',r.base_stake,'minimum_entry_balance',public.paigow_minimum_entry_balance_bpaigow01(r.base_stake),
    'can_take_seat',r.stake_type='spirit_stone' and v_stone_available>=public.paigow_minimum_entry_balance_bpaigow01(r.base_stake),
    'status',r.status,'expires_at',r.idle_expires_at,'first_round_started_at',r.first_round_started_at,'auto_start_at',r.auto_start_at,
    'players',(select count(*) from public.paigow_room_members_bpaigow01 m where m.room_id=r.id and m.left_at is null and m.role='player'),
    'capacity',public.paigow_room_capacity_bpaigow01(r.duel_type,r.game_mode),
    'spectators',(select count(*) from public.paigow_room_members_bpaigow01 m where m.room_id=r.id and m.left_at is null and m.role='spectator'),
    'joined',exists(select 1 from public.paigow_room_members_bpaigow01 m where m.room_id=r.id and m.character_id=v_character and m.left_at is null)
  ) order by r.slot_no),'[]'::jsonb) into v_rooms
  from public.paigow_rooms_bpaigow01 r where r.status in('waiting','playing');

  select balance into v_stone from public.casino_bankroll_v1 where stake_type='spirit_stone';
  select balance into v_cult from public.casino_bankroll_v1 where stake_type='cultivation';
  return jsonb_build_object(
    'status',case when v_enabled then 'active' else 'disabled' end,
    'rooms',v_rooms,'room_limit',4,'character_id',v_character,
    'balances',jsonb_build_object('spirit_stone',v_stone_available,'cultivation',public.casino_available_v1(v_character,'cultivation')),
    'bankrolls',jsonb_build_object('spirit_stone',v_stone,'cultivation',v_cult),
    'rules',jsonb_build_object(
      'idle_close_seconds',300,'ready_seconds',10,'auto_start_seconds',2,'small_prepare_seconds',5,
      'minimum_entry_multiplier',10,'cultivation_stakes_enabled',false,'player_fee_bps',250,
      'player_dealer_pro_rata',true,'big_tie_fee_refund',true,'multipliers',jsonb_build_array(10,50,100)
    )
  );
end
$$;

-- 单手比较没有和局：玩家只有严格大于庄家才赢；同为0点、同分、同牌型均判庄家赢。
create or replace function public.paigow_pair_compare_vs_dealer_bpaigow01(p_player_cards text[],p_dealer_cards text[])
returns integer
language plpgsql
stable
security definer
set search_path=public,pg_temp
as $$
declare v_player jsonb;v_dealer jsonb;
begin
  v_player:=public.paigow_pair_value_bpaigow01(p_player_cards);
  v_dealer:=public.paigow_pair_value_bpaigow01(p_dealer_cards);
  if (v_player->>'score')::bigint>(v_dealer->>'score')::bigint then return 1; end if;
  return -1;
end
$$;

create or replace function public.paigow_round_compare_bpaigow01(
  p_game_mode text,p_cards_a text[],p_head_a smallint[],p_cards_b text[],p_head_b smallint[]
)
returns integer
language plpgsql
stable
security definer
set search_path=public,pg_temp
as $$
declare
  va jsonb;vb jsonb;ah bigint;at bigint;bh bigint;bt bigint;v_head integer;v_tail integer;
begin
  if p_game_mode='small' then
    return public.paigow_pair_compare_vs_dealer_bpaigow01(p_cards_a,p_cards_b);
  end if;
  va:=public.paigow_split_value_bpaigow01(p_cards_a,p_head_a);
  vb:=public.paigow_split_value_bpaigow01(p_cards_b,p_head_b);
  ah:=(va->'head'->>'score')::bigint;at:=(va->'tail'->>'score')::bigint;
  bh:=(vb->'head'->>'score')::bigint;bt:=(vb->'tail'->>'score')::bigint;
  v_head:=case when ah>bh then 1 else -1 end;
  v_tail:=case when at>bt then 1 else -1 end;
  if v_head=1 and v_tail=1 then return 1; end if;
  if v_head=-1 and v_tail=-1 then return -1; end if;
  return 0; -- 大牌九仅一胜一负为整局平局。
end
$$;

-- 玩家庄选定后冻结庄家当时全部可用灵石，作为本局唯一赔付上限；系统不兜底。
create or replace function public.paigow_choose_dealer_internal_bpaigow01(p_round_id uuid)
returns uuid
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_round public.paigow_rounds_bpaigow01%rowtype;v_room public.paigow_rooms_bpaigow01%rowtype;
  v_candidates uuid[];v_dealer uuid;v_seconds integer;v_available bigint;
begin
  select * into v_round from public.paigow_rounds_bpaigow01 where id=p_round_id for update;
  select * into v_room from public.paigow_rooms_bpaigow01 where id=v_round.room_id;
  if v_round.phase<>'rob' then return v_round.dealer_character_id; end if;
  select array_agg(character_id order by seat_no) into v_candidates
  from public.paigow_round_players_bpaigow01 where round_id=p_round_id and active_in_round and rob_choice is true;
  if coalesce(array_length(v_candidates,1),0)=0 then
    select array_agg(character_id order by seat_no) into v_candidates
    from public.paigow_round_players_bpaigow01 where round_id=p_round_id and active_in_round;
  end if;
  if coalesce(array_length(v_candidates,1),0)<1 then
    perform public.paigow_cancel_round_internal_bpaigow01(p_round_id,'not_enough_players_after_rob');return null;
  end if;
  v_dealer:=v_candidates[public.casino_secure_random_int_v1(array_length(v_candidates,1))+1];
  v_available:=public.casino_available_v1(v_dealer,v_room.stake_type);
  if v_available<public.paigow_minimum_entry_balance_bpaigow01(v_room.base_stake) then
    perform public.paigow_cancel_round_internal_bpaigow01(p_round_id,'dealer_below_entry_requirement');return null;
  end if;
  perform public.casino_debit_v1(v_dealer,v_room.stake_type,v_available,'duel','paigow_dealer_full_reserve_v15');
  select case when v_room.game_mode='small' then small_multiplier_seconds else big_multiplier_seconds end
  into v_seconds from public.paigow_settings_bpaigow01 where singleton_id=1;
  update public.paigow_rounds_bpaigow01
  set dealer_character_id=v_dealer,phase='multiplier',phase_deadline=clock_timestamp()+make_interval(secs=>v_seconds)
  where id=p_round_id;
  update public.paigow_round_players_bpaigow01
  set action_confirmed=(character_id=v_dealer),multiplier=null,
      bankroll_reserve=case when character_id=v_dealer then v_available else 0 end,
      resource_before=case when character_id=v_dealer then v_available else resource_before end,
      stake_cap=case when character_id=v_dealer then v_available else stake_cap end,
      result_payload=result_payload||case when character_id=v_dealer then jsonb_build_object('dealer_reserve',v_available,'reserve_policy','all_available_at_selection') else '{}'::jsonb end
  where round_id=p_round_id;
  return v_dealer;
end
$$;

create or replace function public.paigow_apply_multiplier_internal_bpaigow01(p_round_id uuid,p_character_id uuid,p_multiplier integer,p_auto boolean default false)
returns void
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_round public.paigow_rounds_bpaigow01%rowtype;v_room public.paigow_rooms_bpaigow01%rowtype;v_player public.paigow_round_players_bpaigow01%rowtype;
  v_available bigint;v_stake bigint;v_fee bigint:=0;v_total bigint;v_cap bigint;v_num numeric;v_carry integer;
  v_settings public.paigow_settings_bpaigow01%rowtype;
begin
  if p_multiplier not in(10,50,100) then raise exception 'PAIGOW_MULTIPLIER_INVALID'; end if;
  select * into v_round from public.paigow_rounds_bpaigow01 where id=p_round_id for update;
  select * into v_room from public.paigow_rooms_bpaigow01 where id=v_round.room_id for update;
  select * into v_settings from public.paigow_settings_bpaigow01 where singleton_id=1;
  select * into v_player from public.paigow_round_players_bpaigow01 where round_id=p_round_id and character_id=p_character_id for update;
  if v_player.character_id is null or not v_player.active_in_round then raise exception 'PAIGOW_PLAYER_NOT_ACTIVE'; end if;
  if v_player.action_confirmed then return; end if;
  if v_room.duel_type='pvp' and v_room.pvp_mode='rob' and p_character_id=v_round.dealer_character_id then
    update public.paigow_round_players_bpaigow01 set action_confirmed=true where round_id=p_round_id and character_id=p_character_id;return;
  end if;
  if v_room.base_stake>9223372036854775807/p_multiplier then raise exception 'PAIGOW_STAKE_OVERFLOW'; end if;
  v_stake:=v_room.base_stake*p_multiplier;
  if v_room.duel_type='pvp' then
    v_num:=v_stake::numeric*v_settings.player_fee_bps+v_room.fee_carry_bps;
    v_fee:=floor(v_num/10000)::bigint;v_carry:=mod(v_num,10000)::integer;
  else v_fee:=0;v_carry:=v_room.fee_carry_bps; end if;
  v_total:=v_stake+v_fee;
  v_available:=public.casino_available_v1(p_character_id,v_room.stake_type);
  v_cap:=floor(v_available::numeric*0.30)::bigint;
  if v_total>v_cap or v_available<v_total then
    if p_auto then
      update public.paigow_round_players_bpaigow01 set active_in_round=false,fold_reason='insufficient_balance',action_confirmed=true
      where round_id=p_round_id and character_id=p_character_id;return;
    end if;
    raise exception 'PAIGOW_STAKE_EXCEEDS_THIRTY_PERCENT_OR_BALANCE';
  end if;
  begin
    if v_room.duel_type='pvp' then
      perform public.casino_debit_v1(p_character_id,v_room.stake_type,v_total,'duel',
        case when v_room.pvp_mode='rob' then 'paigow_rob_bpaigow01' else 'paigow_boat_bpaigow01' end);
    else
      perform public.casino_debit_v1(p_character_id,v_room.stake_type,v_stake,'duel','paigow_laohe_bpaigow01');
      perform public.casino_bankroll_apply_v1(v_room.stake_type,-v_stake,'paigow_laohe_reserve_bpaigow01',p_round_id,
        jsonb_build_object('room_id',v_room.id,'character_id',p_character_id,'stake',v_stake));
    end if;
  exception when others then
    if p_auto then
      update public.paigow_round_players_bpaigow01 set active_in_round=false,fold_reason='automatic_bet_failed',action_confirmed=true
      where round_id=p_round_id and character_id=p_character_id;return;
    end if;
    raise;
  end;
  if v_fee>0 then
    perform public.casino_bankroll_apply_v1(v_room.stake_type,v_fee,'paigow_player_fee_bpaigow01',p_round_id,
      jsonb_build_object('room_id',v_room.id,'character_id',p_character_id,'fee_bps',v_settings.player_fee_bps,'stake',v_stake));
  end if;
  update public.paigow_rooms_bpaigow01 set fee_carry_bps=v_carry,updated_at=now() where id=v_room.id;
  update public.paigow_round_players_bpaigow01
  set multiplier=p_multiplier,stake_amount=v_stake,fee_amount=v_fee,
      bankroll_reserve=case when v_room.duel_type='laohe' then v_stake else bankroll_reserve end,
      resource_before=v_available,stake_cap=v_cap,action_confirmed=true,fee_refund_amount=0
  where round_id=p_round_id and character_id=p_character_id;
end
$$;

create or replace function public.paigow_settle_round_internal_bpaigow01(p_round_id uuid)
returns void
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_round public.paigow_rounds_bpaigow01%rowtype;v_room public.paigow_rooms_bpaigow01%rowtype;v_secret public.paigow_round_secrets_bpaigow01%rowtype;
  rp record;v_cards text[];v_value jsonb;v_split jsonb;v_result integer;v_requested bigint;v_credit jsonb;v_granted bigint;v_bank_adjust bigint;
  v_dealer public.paigow_round_players_bpaigow01%rowtype;v_dealer_cards text[];v_dealer_head smallint[];v_dealer_credit bigint:=0;v_total_pool bigint;
  v_summary jsonb;v_bank bigint;v_player_count integer;v_winner_claim bigint:=0;v_loser_stakes bigint:=0;v_profit_pool bigint:=0;
  v_profit_pay_total bigint:=0;v_floor_paid bigint:=0;v_remainder bigint:=0;v_share bigint:=0;v_rank bigint:=0;v_fee_refund bigint:=0;
  v_cult_enabled boolean:=false;
begin
  select * into v_round from public.paigow_rounds_bpaigow01 where id=p_round_id for update;
  if v_round.id is null or v_round.phase in('settled','cancelled') then return; end if;
  select * into v_room from public.paigow_rooms_bpaigow01 where id=v_round.room_id for update;
  select * into v_secret from public.paigow_round_secrets_bpaigow01 where round_id=p_round_id;
  select count(*) into v_player_count from public.paigow_round_players_bpaigow01 where round_id=p_round_id and active_in_round;
  if v_player_count<(case when v_room.duel_type='laohe' then 1 else 2 end) then
    perform public.paigow_cancel_round_internal_bpaigow01(p_round_id,'not_enough_players_at_settlement');return;
  end if;

  update public.paigow_round_players_bpaigow01 set payout_amount=0,net_amount=0,fee_refund_amount=0 where round_id=p_round_id;
  for rp in select * from public.paigow_round_players_bpaigow01 where round_id=p_round_id and active_in_round order by seat_no for update loop
    v_cards:=public.paigow_jsonb_codes_bpaigow01(rp.cards);
    if v_room.game_mode='small' then
      v_value:=public.paigow_pair_value_bpaigow01(v_cards);
      update public.paigow_round_players_bpaigow01
      set result_payload=jsonb_build_object('hand',v_value,'score',(v_value->>'score')::bigint,'score_main',(v_value->>'score')::bigint)
      where round_id=p_round_id and character_id=rp.character_id;
    else
      if rp.head_indices is null then
        rp.head_indices:=public.paigow_recommended_split_bpaigow01(v_cards);
        update public.paigow_round_players_bpaigow01 set head_indices=rp.head_indices where round_id=p_round_id and character_id=rp.character_id;
      end if;
      v_split:=public.paigow_split_value_bpaigow01(v_cards,rp.head_indices);
      update public.paigow_round_players_bpaigow01
      set result_payload=jsonb_build_object('split',v_split,'head_score',(v_split->'head'->>'score')::bigint,'tail_score',(v_split->'tail'->>'score')::bigint)
      where round_id=p_round_id and character_id=rp.character_id;
    end if;
  end loop;

  if v_room.duel_type='laohe' then
    v_dealer_cards:=v_secret.laohe_cards;v_dealer_head:=v_secret.laohe_head_indices;
    for rp in select * from public.paigow_round_players_bpaigow01 where round_id=p_round_id and active_in_round order by seat_no for update loop
      v_cards:=public.paigow_jsonb_codes_bpaigow01(rp.cards);
      v_result:=public.paigow_round_compare_bpaigow01(v_room.game_mode,v_cards,rp.head_indices,v_dealer_cards,v_dealer_head);
      v_requested:=case v_result when 1 then rp.stake_amount*2 when 0 then rp.stake_amount else 0 end;
      if v_requested>0 then
        v_credit:=public.casino_credit_result_v0141(rp.character_id,v_room.stake_type,v_requested);
        v_granted:=coalesce((v_credit->>'granted_amount')::bigint,0);
      else v_granted:=0;v_credit:='{}'::jsonb; end if;
      v_bank_adjust:=rp.stake_amount*2-v_granted;
      if v_bank_adjust<>0 then
        perform public.casino_bankroll_apply_v1(v_room.stake_type,v_bank_adjust,'paigow_laohe_settlement_bpaigow01',p_round_id,
          jsonb_build_object('room_id',v_room.id,'character_id',rp.character_id,'result',v_result,'stake',rp.stake_amount,'granted',v_granted));
      end if;
      update public.paigow_round_players_bpaigow01
      set payout_amount=v_granted,net_amount=v_granted-stake_amount-fee_amount,
          result_payload=result_payload||jsonb_build_object('versus','laohe','compare_result',v_result,'requested_payout',v_requested,'credit',v_credit,
            'settlement_kind',case v_result when 1 then 'win' when 0 then 'tie' else 'loss' end)
      where round_id=p_round_id and character_id=rp.character_id;
      perform public.casino_add_ticket_v1(rp.character_id,v_room.stake_type);
    end loop;

  elsif v_room.pvp_mode='rob' then
    select * into v_dealer from public.paigow_round_players_bpaigow01
    where round_id=p_round_id and character_id=v_round.dealer_character_id for update;
    if v_dealer.character_id is null or not v_dealer.active_in_round then
      perform public.paigow_cancel_round_internal_bpaigow01(p_round_id,'dealer_missing_at_settlement');return;
    end if;
    v_dealer_cards:=public.paigow_jsonb_codes_bpaigow01(v_dealer.cards);v_dealer_head:=v_dealer.head_indices;

    -- 先统一判定，避免按座位顺序先到先得。
    for rp in select * from public.paigow_round_players_bpaigow01
      where round_id=p_round_id and active_in_round and character_id<>v_dealer.character_id order by seat_no for update
    loop
      v_cards:=public.paigow_jsonb_codes_bpaigow01(rp.cards);
      v_result:=public.paigow_round_compare_bpaigow01(v_room.game_mode,v_cards,rp.head_indices,v_dealer_cards,v_dealer_head);
      update public.paigow_round_players_bpaigow01
      set result_payload=result_payload||jsonb_build_object('versus','player_dealer','compare_result',v_result,
        'dealer_character_id',v_dealer.character_id,'settlement_kind',case v_result when 1 then 'win' when 0 then 'tie' else 'loss' end)
      where round_id=p_round_id and character_id=rp.character_id;
      if v_result=1 then v_winner_claim:=v_winner_claim+rp.stake_amount;
      elsif v_result=-1 then v_loser_stakes:=v_loser_stakes+rp.stake_amount;
      else v_fee_refund:=v_fee_refund+rp.fee_amount; end if;
    end loop;

    v_profit_pool:=v_dealer.bankroll_reserve+v_loser_stakes;
    v_profit_pay_total:=least(v_profit_pool,v_winner_claim);

    if v_winner_claim>0 and v_profit_pay_total>0 then
      select coalesce(sum(floor(x.stake_amount::numeric*v_profit_pay_total/v_winner_claim)::bigint),0)
      into v_floor_paid
      from public.paigow_round_players_bpaigow01 x
      where x.round_id=p_round_id and x.active_in_round and x.character_id<>v_dealer.character_id
        and (x.result_payload->>'compare_result')::integer=1;
      v_remainder:=v_profit_pay_total-v_floor_paid;
    end if;

    for rp in
      select x.*,
        case when v_winner_claim>0 then floor(x.stake_amount::numeric*v_profit_pay_total/v_winner_claim)::bigint else 0 end as base_share,
        row_number() over(order by
          case when (x.result_payload->>'compare_result')::integer=1 then 0 else 1 end,
          case when v_winner_claim>0 and (x.result_payload->>'compare_result')::integer=1 then mod(x.stake_amount::numeric*v_profit_pay_total,v_winner_claim::numeric) else 0 end desc,
          x.seat_no,x.character_id) as remainder_rank
      from public.paigow_round_players_bpaigow01 x
      where x.round_id=p_round_id and x.active_in_round and x.character_id<>v_dealer.character_id
      order by x.seat_no
    loop
      v_result:=(rp.result_payload->>'compare_result')::integer;
      v_share:=0;v_requested:=0;
      if v_result=1 then
        v_share:=rp.base_share+case when rp.remainder_rank<=v_remainder then 1 else 0 end;
        v_requested:=rp.stake_amount+v_share;
      elsif v_result=0 then
        v_requested:=rp.stake_amount+rp.fee_amount;
        if rp.fee_amount>0 then
          perform public.casino_bankroll_apply_v1(v_room.stake_type,-rp.fee_amount,'paigow_big_tie_fee_refund_v15',p_round_id,
            jsonb_build_object('room_id',v_room.id,'character_id',rp.character_id,'fee_refund',rp.fee_amount));
        end if;
      end if;

      if v_requested>0 then
        v_credit:=public.casino_credit_result_v0141(rp.character_id,v_room.stake_type,v_requested);
        v_granted:=coalesce((v_credit->>'granted_amount')::bigint,0);
      else v_credit:='{}'::jsonb;v_granted:=0; end if;

      update public.paigow_round_players_bpaigow01
      set payout_amount=v_granted,
          fee_refund_amount=case when v_result=0 then fee_amount else 0 end,
          net_amount=v_granted-stake_amount-fee_amount,
          result_payload=result_payload||jsonb_build_object(
            'nominal_profit',case when v_result=1 then stake_amount else 0 end,
            'profit_paid',case when v_result=1 then v_share else 0 end,
            'pro_rata',case when v_result=1 and v_winner_claim>v_profit_pool then true else false end,
            'fee_refunded',case when v_result=0 then fee_amount else 0 end,'credit',v_credit)
      where round_id=p_round_id and character_id=rp.character_id;
      perform public.casino_add_ticket_v1(rp.character_id,v_room.stake_type);
    end loop;

    v_dealer_credit:=v_profit_pool-v_profit_pay_total;
    if v_dealer_credit>0 then
      v_credit:=public.casino_credit_result_v0141(v_dealer.character_id,v_room.stake_type,v_dealer_credit);
      v_granted:=coalesce((v_credit->>'granted_amount')::bigint,0);
    else v_credit:='{}'::jsonb;v_granted:=0; end if;
    update public.paigow_round_players_bpaigow01
    set payout_amount=v_granted,net_amount=v_granted-bankroll_reserve,
        result_payload=result_payload||jsonb_build_object('dealer',true,'reserve',bankroll_reserve,'credited',v_granted,
          'winner_profit_claim',v_winner_claim,'winner_profit_paid',v_profit_pay_total,'loser_stakes',v_loser_stakes,
          'pro_rata_triggered',v_winner_claim>v_profit_pool,'credit',v_credit)
    where round_id=p_round_id and character_id=v_dealer.character_id;
    perform public.casino_add_ticket_v1(v_dealer.character_id,v_room.stake_type);

  else
    select coalesce(sum(stake_amount),0) into v_total_pool
    from public.paigow_round_players_bpaigow01 where round_id=p_round_id and active_in_round;
    if v_room.game_mode='small' then
      perform public.paigow_allocate_boat_pool_bpaigow01(p_round_id,'score_main',v_total_pool,false);
    else
      perform public.paigow_allocate_boat_pool_bpaigow01(p_round_id,'head_score',floor(v_total_pool::numeric/2)::bigint,true);
      perform public.paigow_allocate_boat_pool_bpaigow01(p_round_id,'tail_score',v_total_pool-floor(v_total_pool::numeric/2)::bigint,true);
    end if;
    for rp in select * from public.paigow_round_players_bpaigow01 where round_id=p_round_id and active_in_round order by seat_no for update loop
      if rp.payout_amount>0 then
        v_credit:=public.casino_credit_result_v0141(rp.character_id,v_room.stake_type,rp.payout_amount);
        v_granted:=coalesce((v_credit->>'granted_amount')::bigint,0);
      else v_granted:=0;v_credit:='{}'::jsonb; end if;
      update public.paigow_round_players_bpaigow01
      set payout_amount=v_granted,net_amount=v_granted-stake_amount-fee_amount,
          result_payload=result_payload||jsonb_build_object('versus','boat_pool','nominal_payout',rp.payout_amount,'credit',v_credit)
      where round_id=p_round_id and character_id=rp.character_id;
      perform public.casino_add_ticket_v1(rp.character_id,v_room.stake_type);
    end loop;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'character_id',x.character_id,'seat_no',x.seat_no,'active',x.active_in_round,'stake',x.stake_amount,'fee',x.fee_amount,
    'fee_refund',x.fee_refund_amount,'payout',x.payout_amount,'net',x.net_amount,'result',x.result_payload
  ) order by x.seat_no),'[]'::jsonb)
  into v_summary from public.paigow_round_players_bpaigow01 x where x.round_id=p_round_id;

  select balance into v_bank from public.casino_bankroll_v1 where stake_type=v_room.stake_type;
  update public.paigow_rounds_bpaigow01
  set phase='settled',settled_at=clock_timestamp(),phase_deadline=null,
      result_payload=jsonb_build_object(
        'duel_type',v_room.duel_type,'pvp_mode',v_room.pvp_mode,'game_mode',v_room.game_mode,'stake_type',v_room.stake_type,
        'players',v_summary,'player_dealer_pro_rata',v_room.duel_type='pvp' and v_room.pvp_mode='rob',
        'big_tie_fee_refund',v_room.game_mode='big','bankroll_balance_after',v_bank,
        'laohe_cards',case when v_room.duel_type='laohe' then public.paigow_tiles_json_bpaigow01(v_secret.laohe_cards) else '[]'::jsonb end,
        'laohe_head_indices',case when v_room.duel_type='laohe' then to_jsonb(v_secret.laohe_head_indices) else 'null'::jsonb end)
  where id=p_round_id;

  select coalesce(cultivation_stakes_enabled,false) into v_cult_enabled
  from public.paigow_settings_bpaigow01 where singleton_id=1;
  if v_room.stake_type='cultivation' and not v_cult_enabled then
    update public.paigow_room_members_bpaigow01
    set left_at=clock_timestamp(),ready=false,ready_deadline=null
    where room_id=v_room.id and left_at is null;
    update public.paigow_rooms_bpaigow01
    set status='closed',closed_at=clock_timestamp(),auto_start_at=null,updated_at=now()
    where id=v_room.id;
  else
    update public.paigow_rooms_bpaigow01 set status='waiting',auto_start_at=null,updated_at=now() where id=v_room.id;
    update public.paigow_room_members_bpaigow01 set ready=false where room_id=v_room.id and left_at is null and role='player';
    perform public.paigow_eject_underfunded_players_bpaigow01(v_room.id);
    perform public.paigow_prepare_waiting_room_bpaigow01(v_room.id);
  end if;
end
$$;

revoke all on function public.paigow_minimum_entry_balance_bpaigow01(bigint),
  public.paigow_eject_underfunded_players_bpaigow01(uuid),
  public.paigow_pair_compare_vs_dealer_bpaigow01(text[],text[]) from public,anon,authenticated;

comment on function public.paigow_round_compare_bpaigow01(text,text[],smallint[],text[],smallint[]) is
  'V1.5：单手完全相同和双方0点均判庄家胜；大牌九一胜一负才返回整局平局。';
comment on function public.paigow_settle_round_internal_bpaigow01(uuid) is
  'V1.5：玩家庄资金不足按所有赢家名义利润比例赔付；大牌九平局返还本金与2.5%手续费。';
comment on function public.join_paigow_room_bpaigow01(uuid,smallint,boolean) is
  'V1.5：入座需至少持有底注10倍灵石；不足仍可观战。';

notify pgrst,'reload schema';
commit;
