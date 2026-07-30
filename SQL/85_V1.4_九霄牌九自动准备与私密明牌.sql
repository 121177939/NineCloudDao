-- 九霄问道 V1.4 CACHE42
-- 85：九霄牌九私密明牌、10秒准备退出、全员准备2秒自动开局、房主大厅删房与结算灵石特效数据支持
-- 本脚本为追加式迁移；生产库已完成84号后直接执行。

begin;

do $$
begin
  if to_regprocedure('public.get_paigow_room_state_bpaigow01(uuid)') is null then raise exception 'V1_4_REQUIRED:room_state_rpc';end if;
  if to_regprocedure('public.start_paigow_round_bpaigow01(uuid,uuid)') is null then raise exception 'V1_4_REQUIRED:start_round_rpc';end if;
  if to_regclass('public.paigow_room_members_bpaigow01') is null then raise exception 'V1_4_REQUIRED:room_members';end if;
end
$$;

alter table public.paigow_room_members_bpaigow01
  add column if not exists ready_deadline timestamptz;

alter table public.paigow_rooms_bpaigow01
  add column if not exists auto_start_at timestamptz;

alter table public.paigow_settings_bpaigow01
  add column if not exists ready_seconds integer not null default 10 check(ready_seconds between 5 and 60),
  add column if not exists auto_start_seconds integer not null default 2 check(auto_start_seconds between 1 and 10);

update public.paigow_settings_bpaigow01
set ready_seconds=10,
    auto_start_seconds=2,
    small_multiplier_seconds=5,
    updated_at=now()
where singleton_id=1;

update public.paigow_room_members_bpaigow01
set ready_deadline=case when ready then null else clock_timestamp()+interval '10 seconds' end
where left_at is null and role='player';


create or replace function public.paigow_member_ready_deadline_v14()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_seconds integer;
begin
  select ready_seconds into v_seconds from public.paigow_settings_bpaigow01 where singleton_id=1;
  v_seconds:=coalesce(v_seconds,10);
  if new.left_at is not null or new.role<>'player' then
    new.ready_deadline:=null;
  elsif new.ready then
    new.ready_deadline:=null;
  elsif tg_op='INSERT' then
    new.ready_deadline:=clock_timestamp()+make_interval(secs=>v_seconds);
  elsif old.left_at is not null
     or old.role is distinct from new.role
     or old.ready is distinct from new.ready then
    new.ready_deadline:=clock_timestamp()+make_interval(secs=>v_seconds);
  end if;
  return new;
end
$$;

drop trigger if exists paigow_member_ready_deadline_v14 on public.paigow_room_members_bpaigow01;
create trigger paigow_member_ready_deadline_v14
before insert or update of ready,left_at,role
on public.paigow_room_members_bpaigow01
for each row execute function public.paigow_member_ready_deadline_v14();

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
begin
  select * into v_room
  from public.paigow_rooms_bpaigow01
  where id=p_room_id
  for update;

  if v_room.id is null or v_room.status<>'waiting' then return;end if;

  update public.paigow_room_members_bpaigow01
  set left_at=clock_timestamp(),ready=false,ready_deadline=null
  where room_id=p_room_id
    and left_at is null
    and role='player'
    and not ready
    and ready_deadline is not null
    and ready_deadline<=clock_timestamp();

  if not exists(
    select 1 from public.paigow_room_members_bpaigow01
    where room_id=p_room_id and character_id=v_room.owner_character_id
      and left_at is null and role='player'
  ) then
    select character_id into v_new_owner
    from public.paigow_room_members_bpaigow01
    where room_id=p_room_id and left_at is null and role='player'
    order by joined_at,seat_no
    limit 1;

    if v_new_owner is null then
      update public.paigow_rooms_bpaigow01
      set status='closed',closed_at=clock_timestamp(),auto_start_at=null,updated_at=now()
      where id=p_room_id;
      return;
    end if;

    update public.paigow_rooms_bpaigow01
    set owner_character_id=v_new_owner,updated_at=now()
    where id=p_room_id;
  end if;

  select count(*),count(*) filter (where ready)
  into v_players,v_ready
  from public.paigow_room_members_bpaigow01
  where room_id=p_room_id and left_at is null and role='player';

  v_min:=case when v_room.duel_type='laohe' then 1 else 2 end;
  select auto_start_seconds into v_auto_seconds
  from public.paigow_settings_bpaigow01 where singleton_id=1;
  v_auto_seconds:=coalesce(v_auto_seconds,2);

  if v_players>=v_min and v_ready=v_players then
    update public.paigow_rooms_bpaigow01
    set auto_start_at=coalesce(auto_start_at,clock_timestamp()+make_interval(secs=>v_auto_seconds)),
        updated_at=now()
    where id=p_room_id and status='waiting';
  else
    update public.paigow_rooms_bpaigow01
    set auto_start_at=null,updated_at=now()
    where id=p_room_id and status='waiting' and auto_start_at is not null;
  end if;
end
$$;



create or replace function public.get_paigow_lobby_bpaigow01()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_character uuid:=public.casino_current_character_id_v1();
  v_rooms jsonb;v_stone bigint;v_cult bigint;v_enabled boolean;v_row record;
begin
  perform public.paigow_cleanup_rooms_bpaigow01();
  for v_row in select id from public.paigow_rooms_bpaigow01 where status='waiting'
  loop
    perform public.paigow_prepare_waiting_room_bpaigow01(v_row.id);
  end loop;

  select enabled into v_enabled from public.paigow_settings_bpaigow01 where singleton_id=1;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'slot_no',r.slot_no,'name',r.room_name,'owner_character_id',r.owner_character_id,
    'is_owner',r.owner_character_id=v_character,
    'can_delete',r.owner_character_id=v_character and r.status='waiting'
      and not exists(select 1 from public.paigow_rounds_bpaigow01 ar where ar.room_id=r.id and ar.phase not in('settled','cancelled')),
    'duel_type',r.duel_type,'pvp_mode',r.pvp_mode,'game_mode',r.game_mode,'stake_type',r.stake_type,
    'base_stake',r.base_stake,'status',r.status,'expires_at',r.idle_expires_at,'auto_start_at',r.auto_start_at,
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
    'balances',jsonb_build_object(
      'spirit_stone',public.casino_available_v1(v_character,'spirit_stone'),
      'cultivation',public.casino_available_v1(v_character,'cultivation')
    ),
    'bankrolls',jsonb_build_object('spirit_stone',v_stone,'cultivation',v_cult),
    'rules',jsonb_build_object(
      'idle_close_seconds',1200,'ready_seconds',10,'auto_start_seconds',2,
      'small_prepare_seconds',5,'player_fee_bps',250,'laohe_profit_bps',10000,
      'multipliers',jsonb_build_array(10,50,100)
    )
  );
end
$$;


create or replace function public.get_paigow_room_state_bpaigow01(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_character uuid:=public.casino_current_character_id_v1();v_room public.paigow_rooms_bpaigow01%rowtype;v_members jsonb;v_round_rec public.paigow_rounds_bpaigow01%rowtype;
  v_players jsonb:='[]'::jsonb;v_cards text[];v_visible text[];v_head smallint[];v_public jsonb;v_self_member jsonb;v_phase text;
  v_secret public.paigow_round_secrets_bpaigow01%rowtype;v_laohe jsonb:='null'::jsonb;v_laohe_visible text[];v_laohe_public jsonb;
  rp record;v_balance bigint;v_bank bigint;v_result jsonb;
begin
  perform public.paigow_cleanup_rooms_bpaigow01();
  perform public.paigow_prepare_waiting_room_bpaigow01(p_room_id);
  select * into v_room from public.paigow_rooms_bpaigow01 where id=p_room_id;
  if v_room.id is null then raise exception 'PAIGOW_ROOM_NOT_FOUND';end if;
  select coalesce(jsonb_agg(jsonb_build_object('character_id',m.character_id,'name',pc.name,'seat_no',m.seat_no,'role',m.role,'ready',m.ready,
    'is_self',m.character_id=v_character,'is_owner',m.character_id=v_room.owner_character_id,'ready_deadline',m.ready_deadline) order by coalesce(m.seat_no,99),m.joined_at),'[]'::jsonb)
  into v_members from public.paigow_room_members_bpaigow01 m join public.player_characters pc on pc.id=m.character_id
  where m.room_id=p_room_id and m.left_at is null;
  select jsonb_build_object('seat_no',m.seat_no,'role',m.role,'ready',m.ready,'is_owner',m.character_id=v_room.owner_character_id,'ready_deadline',m.ready_deadline)
  into v_self_member from public.paigow_room_members_bpaigow01 m where m.room_id=p_room_id and m.character_id=v_character and m.left_at is null;
  select * into v_round_rec from public.paigow_rounds_bpaigow01 where room_id=p_room_id order by round_no desc limit 1;
  if v_round_rec.id is not null then
    v_phase:=v_round_rec.phase;
    select * into v_secret from public.paigow_round_secrets_bpaigow01 where round_id=v_round_rec.id;
    for rp in
      select x.*,pc.name from public.paigow_round_players_bpaigow01 x join public.player_characters pc on pc.id=x.character_id
      where x.round_id=v_round_rec.id order by x.seat_no
    loop
      v_cards:=public.paigow_jsonb_codes_bpaigow01(rp.cards);v_head:=rp.head_indices;v_visible:='{}'::text[];v_public:='{}'::jsonb;
      if rp.character_id=v_character then
        if v_room.game_mode='small' and v_phase not in('settled','cancelled') then v_visible:=v_cards[1:1];
        elsif v_room.game_mode='big' and v_phase in('rob','multiplier','waiting') then v_visible:=v_cards[1:2];
        else v_visible:=v_cards;end if;
      elsif v_room.game_mode='small' and v_phase not in('settled','cancelled') then
        -- V1.4：小牌九的“明牌”只对牌主本人可见，对手与观战者只收到牌背。
        v_visible:='{}'::text[];
      elsif v_room.game_mode='big' and v_phase='head_reveal' and v_head is not null then
        v_visible:=array[v_cards[v_head[1]+1],v_cards[v_head[2]+1]];
      elsif v_phase in('tail_reveal','settled','cancelled') then v_visible:=v_cards;
      end if;
      if v_phase='head_reveal' and v_room.game_mode='big' and v_head is not null then
        v_public:=public.paigow_pair_value_bpaigow01(array[v_cards[v_head[1]+1],v_cards[v_head[2]+1]]);
      elsif v_phase in('tail_reveal','settled') and v_room.game_mode='big' and v_head is not null then
        v_public:=public.paigow_split_value_bpaigow01(v_cards,v_head);
      elsif v_phase='settled' and v_room.game_mode='small' then v_public:=public.paigow_pair_value_bpaigow01(v_cards);end if;
      v_players:=v_players||jsonb_build_array(jsonb_build_object(
        'character_id',rp.character_id,'name',rp.name,'seat_no',rp.seat_no,'is_self',rp.character_id=v_character,
        'is_dealer',rp.character_id=v_round_rec.dealer_character_id,'active',rp.active_in_round,'fold_reason',rp.fold_reason,
        'rob_choice',case when rp.character_id=v_character or v_phase<>'rob' then rp.rob_choice else null end,
        'multiplier',rp.multiplier,'stake_amount',rp.stake_amount,'fee_amount',rp.fee_amount,'action_confirmed',rp.action_confirmed,
        'cards',public.paigow_tiles_json_bpaigow01(v_visible),'head_indices',case when rp.character_id=v_character or v_phase in('head_reveal','tail_reveal','settled') then to_jsonb(v_head) else 'null'::jsonb end,
        'public_value',v_public,'payout_amount',case when v_phase='settled' then rp.payout_amount else 0 end,
        'net_amount',case when v_phase='settled' then rp.net_amount else 0 end,'result',case when v_phase='settled' then rp.result_payload else '{}'::jsonb end
      ));
    end loop;
    if v_room.duel_type='laohe' and v_secret.round_id is not null then
      v_laohe_visible:='{}'::text[];v_laohe_public:='{}'::jsonb;
      if v_room.game_mode='small' then
        if v_phase='settled' then v_laohe_visible:=v_secret.laohe_cards;v_laohe_public:=public.paigow_pair_value_bpaigow01(v_secret.laohe_cards);
        else v_laohe_visible:='{}'::text[];end if;
      elsif v_phase='head_reveal' and v_secret.laohe_head_indices is not null then
        v_laohe_visible:=array[v_secret.laohe_cards[v_secret.laohe_head_indices[1]+1],v_secret.laohe_cards[v_secret.laohe_head_indices[2]+1]];
        v_laohe_public:=public.paigow_pair_value_bpaigow01(v_laohe_visible);
      elsif v_phase in('tail_reveal','settled') then
        v_laohe_visible:=v_secret.laohe_cards;
        v_laohe_public:=public.paigow_split_value_bpaigow01(v_secret.laohe_cards,v_secret.laohe_head_indices);
      end if;
      v_laohe:=jsonb_build_object('name','老何','is_dealer',true,'cards',public.paigow_tiles_json_bpaigow01(v_laohe_visible),
        'head_indices',case when v_phase in('head_reveal','tail_reveal','settled') then to_jsonb(v_secret.laohe_head_indices) else 'null'::jsonb end,
        'public_value',v_laohe_public);
    end if;
    v_result=jsonb_build_object('id',v_round_rec.id,'round_no',v_round_rec.round_no,'phase',v_round_rec.phase,
      'dealer_character_id',v_round_rec.dealer_character_id,'phase_deadline',v_round_rec.phase_deadline,'started_at',v_round_rec.started_at,
      'settled_at',v_round_rec.settled_at,'players',v_players,'laohe',v_laohe,
      'result_payload',case when v_round_rec.phase='settled' then v_round_rec.result_payload else '{}'::jsonb end);
  else v_result:='null'::jsonb;end if;
  v_balance:=public.casino_available_v1(v_character,v_room.stake_type);select balance into v_bank from public.casino_bankroll_v1 where stake_type=v_room.stake_type;
  return jsonb_build_object('room',to_jsonb(v_room),'members',v_members,'round',v_result,'self_character_id',v_character,'self_member',coalesce(v_self_member,'null'::jsonb),
    'self_balance',v_balance,'bankroll_balance',v_bank,'server_time',clock_timestamp());
end $$;


create or replace function public.set_paigow_ready_bpaigow01(p_room_id uuid,p_ready boolean)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_character uuid:=public.casino_current_character_id_v1();v_room public.paigow_rooms_bpaigow01%rowtype;
begin
  perform public.paigow_prepare_waiting_room_bpaigow01(p_room_id);
  select * into v_room from public.paigow_rooms_bpaigow01 where id=p_room_id and status='waiting' for update;
  if v_room.id is null then raise exception 'PAIGOW_ROOM_NOT_WAITING';end if;

  update public.paigow_room_members_bpaigow01
  set ready=coalesce(p_ready,false)
  where room_id=p_room_id and character_id=v_character and left_at is null and role='player';
  if not found then raise exception 'PAIGOW_PLAYER_NOT_SEATED_OR_READY_TIMEOUT';end if;

  perform public.paigow_prepare_waiting_room_bpaigow01(p_room_id);
  return public.get_paigow_room_state_bpaigow01(p_room_id);
end
$$;


create or replace function public.start_paigow_round_bpaigow01(
  p_room_id uuid,
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_character uuid := public.casino_current_character_id_v1();
  v_existing jsonb;
  v_room public.paigow_rooms_bpaigow01%rowtype;
  v_round public.paigow_rounds_bpaigow01%rowtype;
  v_deck text[];
  v_pos integer := 1;
  v_count integer;
  v_need integer;
  v_round_no integer;
  v_phase text;
  v_deadline timestamptz;
  v_cards text[];
  v_member record;
  v_settings public.paigow_settings_bpaigow01%rowtype;
begin
  perform public.paigow_assert_enabled_bpaigow01();

  v_existing := public.paigow_action_existing_bpaigow01(
    v_character,
    p_request_id,
    'start_round'
  );
  if v_existing is not null then
    return v_existing;
  end if;

  if not public.paigow_action_claim_bpaigow01(
    v_character,
    p_request_id,
    'start_round',
    jsonb_build_object('room_id',p_room_id)
  ) then
    raise exception 'PAIGOW_REQUEST_IN_PROGRESS';
  end if;

  select *
    into v_settings
    from public.paigow_settings_bpaigow01
   where singleton_id=1;

  perform public.paigow_prepare_waiting_room_bpaigow01(p_room_id);

  select *
    into v_room
    from public.paigow_rooms_bpaigow01
   where id=p_room_id
   for update;

  if v_room.id is null or v_room.status<>'waiting' then
    raise exception 'PAIGOW_ROOM_NOT_WAITING';
  end if;
  if v_room.auto_start_at is null or v_room.auto_start_at>clock_timestamp() then
    raise exception 'PAIGOW_AUTO_START_NOT_READY';
  end if;
  if exists(
    select 1
      from public.paigow_rounds_bpaigow01
     where room_id=p_room_id
       and phase not in ('settled','cancelled')
  ) then
    raise exception 'PAIGOW_ACTIVE_ROUND_EXISTS';
  end if;

  select count(*)
    into v_count
    from public.paigow_room_members_bpaigow01
   where room_id=p_room_id
     and left_at is null
     and role='player';

  if v_count < (
    case when v_room.duel_type='laohe' then 1 else 2 end
  ) then
    raise exception 'PAIGOW_NOT_ENOUGH_PLAYERS';
  end if;

  if v_count > public.paigow_room_capacity_bpaigow01(
    v_room.duel_type,
    v_room.game_mode
  ) then
    raise exception 'PAIGOW_TOO_MANY_PLAYERS';
  end if;

  if exists(
    select 1
      from public.paigow_room_members_bpaigow01
     where room_id=p_room_id
       and left_at is null
       and role='player'
       and not ready
  ) then
    raise exception 'PAIGOW_PLAYERS_NOT_READY';
  end if;

  select coalesce(max(round_no),0)+1
    into v_round_no
    from public.paigow_rounds_bpaigow01
   where room_id=p_room_id;

  v_phase := case
    when v_room.duel_type='pvp' and v_room.pvp_mode='rob' then 'rob'
    else 'multiplier'
  end;

  v_deadline := clock_timestamp()+make_interval(
    secs => case
      when v_phase='rob' then v_settings.rob_seconds
      when v_room.game_mode='small' then v_settings.small_multiplier_seconds
      else v_settings.big_multiplier_seconds
    end
  );

  insert into public.paigow_rounds_bpaigow01(
    room_id,
    round_no,
    phase,
    phase_deadline,
    fee_carry_start
  )
  values(
    p_room_id,
    v_round_no,
    v_phase,
    v_deadline,
    v_room.fee_carry_bps
  )
  returning * into v_round;

  v_deck := public.paigow_shuffle_deck_bpaigow01();
  v_need := case when v_room.game_mode='big' then 4 else 2 end;

  -- 关键修复：record 变量改名为 v_member，查询表别名改为 rm，避免名称冲突。
  for v_member in
    select rm.character_id, rm.seat_no
      from public.paigow_room_members_bpaigow01 as rm
     where rm.room_id=p_room_id
       and rm.left_at is null
       and rm.role='player'
     order by rm.seat_no
  loop
    v_cards := v_deck[v_pos:v_pos+v_need-1];
    v_pos := v_pos+v_need;

    insert into public.paigow_round_players_bpaigow01(
      round_id,
      character_id,
      seat_no,
      cards,
      action_confirmed
    )
    values(
      v_round.id,
      v_member.character_id,
      v_member.seat_no,
      to_jsonb(v_cards),
      false
    );
  end loop;

  if v_room.duel_type='laohe' then
    v_cards := v_deck[v_pos:v_pos+v_need-1];
    v_pos := v_pos+v_need;

    insert into public.paigow_round_secrets_bpaigow01(
      round_id,
      shuffled_deck,
      laohe_cards,
      laohe_head_indices
    )
    values(
      v_round.id,
      v_deck,
      v_cards,
      case
        when v_room.game_mode='big'
          then public.paigow_recommended_split_bpaigow01(v_cards)
        else null
      end
    );
  else
    insert into public.paigow_round_secrets_bpaigow01(
      round_id,
      shuffled_deck
    )
    values(v_round.id,v_deck);
  end if;

  update public.paigow_rooms_bpaigow01
     set status='playing',
         first_round_started_at=coalesce(first_round_started_at,clock_timestamp()),
         auto_start_at=null,
         updated_at=now()
   where id=p_room_id;

  return public.paigow_action_finish_bpaigow01(
    v_character,
    p_request_id,
    'start_round',
    public.get_paigow_room_state_bpaigow01(p_room_id)
  );
end
$$;

create or replace function public.advance_paigow_round_bpaigow01(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_room public.paigow_rooms_bpaigow01%rowtype;v_round public.paigow_rounds_bpaigow01%rowtype;rp record;v_pending integer;v_seconds integer;
begin
  perform public.paigow_assert_enabled_bpaigow01();
  perform public.paigow_prepare_waiting_room_bpaigow01(p_room_id);
  select * into v_room from public.paigow_rooms_bpaigow01 where id=p_room_id for update;
  if v_room.id is null then raise exception 'PAIGOW_ROOM_NOT_FOUND';end if;
  if v_room.status='closed' then return public.get_paigow_room_state_bpaigow01(p_room_id);end if;
  if v_room.status='waiting' then
    if v_room.auto_start_at is not null and v_room.auto_start_at<=clock_timestamp() then
      return public.start_paigow_round_bpaigow01(p_room_id,gen_random_uuid());
    end if;
    return public.get_paigow_room_state_bpaigow01(p_room_id);
  end if;
  select * into v_round from public.paigow_rounds_bpaigow01 where room_id=p_room_id order by round_no desc limit 1 for update;
  if v_round.id is null or v_round.phase in('settled','cancelled') then return public.get_paigow_room_state_bpaigow01(p_room_id);end if;
  if v_round.phase='rob' then
    select count(*) into v_pending from public.paigow_round_players_bpaigow01 where round_id=v_round.id and active_in_round and rob_choice is null;
    if v_pending=0 or v_round.phase_deadline<=clock_timestamp() then
      update public.paigow_round_players_bpaigow01 set rob_choice=false where round_id=v_round.id and active_in_round and rob_choice is null;
      perform public.paigow_choose_dealer_internal_bpaigow01(v_round.id);
    end if;
  elsif v_round.phase='multiplier' and v_round.phase_deadline<=clock_timestamp() then
    for rp in select x.character_id from public.paigow_round_players_bpaigow01 x join public.paigow_rounds_bpaigow01 r on r.id=x.round_id join public.paigow_rooms_bpaigow01 rm on rm.id=r.room_id
      where x.round_id=v_round.id and x.active_in_round and not x.action_confirmed and not(rm.duel_type='pvp' and rm.pvp_mode='rob' and x.character_id=r.dealer_character_id) order by x.seat_no loop
      perform public.paigow_apply_multiplier_internal_bpaigow01(v_round.id,rp.character_id,10,true);
    end loop;
    perform public.paigow_after_multiplier_internal_bpaigow01(v_round.id);
  elsif v_round.phase='arrange' then
    select count(*) into v_pending from public.paigow_round_players_bpaigow01 where round_id=v_round.id and active_in_round and not action_confirmed;
    if v_pending=0 or v_round.phase_deadline<=clock_timestamp() then perform public.paigow_begin_head_reveal_internal_bpaigow01(v_round.id);end if;
  elsif v_round.phase='head_reveal' and v_round.phase_deadline<=clock_timestamp() then
    select tail_reveal_seconds into v_seconds from public.paigow_settings_bpaigow01 where singleton_id=1;
    update public.paigow_rounds_bpaigow01 set phase='tail_reveal',phase_deadline=clock_timestamp()+make_interval(secs=>v_seconds) where id=v_round.id;
  elsif v_round.phase='tail_reveal' and v_round.phase_deadline<=clock_timestamp() then
    perform public.paigow_settle_round_internal_bpaigow01(v_round.id);
  end if;
  return public.get_paigow_room_state_bpaigow01(p_room_id);
end $$;


create or replace function public.leave_paigow_room_bpaigow01(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_character uuid:=public.casino_current_character_id_v1();
  v_room public.paigow_rooms_bpaigow01%rowtype;
  v_role text;
begin
  select * into v_room from public.paigow_rooms_bpaigow01 where id=p_room_id for update;
  if v_room.id is null then raise exception 'PAIGOW_ROOM_NOT_FOUND';end if;
  select role into v_role from public.paigow_room_members_bpaigow01
  where room_id=p_room_id and character_id=v_character and left_at is null;

  if v_room.status='playing' and v_role='player' then
    raise exception 'PAIGOW_CANNOT_LEAVE_ACTIVE_ROUND';
  end if;

  update public.paigow_room_members_bpaigow01
  set left_at=clock_timestamp(),ready=false,ready_deadline=null
  where room_id=p_room_id and character_id=v_character and left_at is null;

  if v_room.status='waiting' then
    perform public.paigow_prepare_waiting_room_bpaigow01(p_room_id);
  end if;

  return jsonb_build_object('left',true,'room_id',p_room_id);
end
$$;

create or replace function public.delete_paigow_room_bpaigow01(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_character uuid:=public.casino_current_character_id_v1();
  v_room public.paigow_rooms_bpaigow01%rowtype;
begin
  select * into v_room from public.paigow_rooms_bpaigow01 where id=p_room_id for update;
  if v_room.id is null then raise exception 'PAIGOW_ROOM_NOT_FOUND';end if;
  if v_room.owner_character_id<>v_character then raise exception 'PAIGOW_ONLY_OWNER_DELETES';end if;
  if v_room.status='playing' or exists(
    select 1 from public.paigow_rounds_bpaigow01
    where room_id=p_room_id and phase not in('settled','cancelled')
  ) then
    raise exception 'PAIGOW_CANNOT_DELETE_ACTIVE_ROOM';
  end if;
  if v_room.status<>'waiting' then raise exception 'PAIGOW_ROOM_NOT_WAITING';end if;

  update public.paigow_room_members_bpaigow01
  set left_at=clock_timestamp(),ready=false,ready_deadline=null
  where room_id=p_room_id and left_at is null;

  update public.paigow_rooms_bpaigow01
  set status='closed',closed_at=clock_timestamp(),auto_start_at=null,updated_at=now()
  where id=p_room_id;

  return public.get_paigow_lobby_bpaigow01();
end
$$;


revoke all on function public.paigow_member_ready_deadline_v14(),public.paigow_prepare_waiting_room_bpaigow01(uuid),
  public.delete_paigow_room_bpaigow01(uuid) from public,anon,authenticated;
grant execute on function public.delete_paigow_room_bpaigow01(uuid) to authenticated;

comment on function public.get_paigow_room_state_bpaigow01(uuid) is 'V1.4：小牌九首张明牌只向牌主本人返回；对手与观战者只收到牌背。';
comment on function public.advance_paigow_round_bpaigow01(uuid) is 'V1.4：处理10秒准备超时退出、全员准备2秒自动开局及既有牌局阶段推进。';
comment on function public.delete_paigow_room_bpaigow01(uuid) is 'V1.4：房主可在大厅删除等待房间；进行中牌局禁止删除。';

notify pgrst,'reload schema';
commit;
