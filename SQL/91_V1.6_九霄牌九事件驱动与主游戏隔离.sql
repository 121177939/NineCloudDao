-- 九霄问道 V1.6 CACHE44
-- 91：九霄牌九事件驱动、数据库定时推进与主游戏资源隔离。
-- 生产库已完成90号时直接执行本脚本。

create extension if not exists pg_cron;

begin;

do $$
begin
  if to_regprocedure('public.get_paigow_room_state_bpaigow01(uuid)') is null then raise exception 'V1_6_REQUIRED:get_room_state'; end if;
  if to_regprocedure('public.paigow_settle_round_internal_bpaigow01(uuid)') is null then raise exception 'V1_6_REQUIRED:settlement'; end if;
  if to_regclass('realtime.messages') is null then raise exception 'V1_6_REQUIRED:realtime_messages'; end if;
end
$$;

create sequence if not exists public.paigow_lobby_event_seq_bpaigow01 as bigint start with 1 increment by 1;

create table if not exists public.paigow_room_event_versions_bpaigow01(
  room_id uuid primary key references public.paigow_rooms_bpaigow01(id) on delete cascade,
  state_version bigint not null default 0,
  last_reason text not null default 'bootstrap',
  updated_at timestamptz not null default now()
);

insert into public.paigow_room_event_versions_bpaigow01(room_id,state_version,last_reason)
select id,0,'bootstrap' from public.paigow_rooms_bpaigow01
on conflict(room_id) do nothing;

create index if not exists paigow_rooms_due_v16_idx
  on public.paigow_rooms_bpaigow01(status,idle_expires_at,auto_start_at);
create index if not exists paigow_members_ready_due_v16_idx
  on public.paigow_room_members_bpaigow01(room_id,role,left_at,ready_deadline);
create index if not exists paigow_rounds_phase_due_v16_idx
  on public.paigow_rounds_bpaigow01(room_id,phase,phase_deadline,round_no desc);

create or replace function public.paigow_emit_state_event_payload_v16_bpaigow01(
  p_room_id uuid,
  p_reason text,
  p_delta jsonb default '{}'::jsonb,
  p_snapshot_required boolean default true
)
returns bigint
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_room_version bigint;
  v_lobby_version bigint;
  v_payload jsonb;
  v_send_lobby boolean;
begin
  if p_room_id is null then return 0; end if;

  -- 物理删除／级联删除时父房间已不存在：只推进大厅版本并广播大厅变化，避免事件版本外键反向阻断删除。
  if not exists(select 1 from public.paigow_rooms_bpaigow01 where id=p_room_id) then
    v_lobby_version:=nextval('public.paigow_lobby_event_seq_bpaigow01');
    begin
      if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is not null then
        perform realtime.send(
          jsonb_build_object('room_id',p_room_id,'lobby_version',v_lobby_version,'reason',coalesce(nullif(p_reason,''),'room_deleted'),'snapshot_required',true,'emitted_at',clock_timestamp()),
          'paigow_lobby_changed','paigow:lobby',true
        );
      end if;
    exception when others then
      raise warning 'V1_6_PAIGOW_DELETE_EVENT_WARNING room=% error=%',p_room_id,sqlerrm;
    end;
    return 0;
  end if;

  insert into public.paigow_room_event_versions_bpaigow01(room_id,state_version,last_reason,updated_at)
  values(p_room_id,1,coalesce(nullif(p_reason,''),'state_changed'),clock_timestamp())
  on conflict(room_id) do update
  set state_version=public.paigow_room_event_versions_bpaigow01.state_version+1,
      last_reason=excluded.last_reason,
      updated_at=excluded.updated_at
  returning state_version into v_room_version;

  v_lobby_version:=nextval('public.paigow_lobby_event_seq_bpaigow01');
  v_payload:=jsonb_build_object(
    'room_id',p_room_id,
    'room_version',v_room_version,
    'lobby_version',v_lobby_version,
    'reason',coalesce(nullif(p_reason,''),'state_changed'),
    'snapshot_required',coalesce(p_snapshot_required,true),
    'delta',coalesce(p_delta,'{}'::jsonb),
    'emitted_at',clock_timestamp()
  );
  -- 大厅只关心房间与席位人口变化；牌局阶段和玩家动作不应让大厅客户端反复读取列表。
  v_send_lobby:=not(
    coalesce(p_reason,'') like 'round_%'
    or coalesce(p_reason,'') like 'player_action_%'
    or coalesce(p_reason,'')='member_ready_update'
  );

  begin
    if to_regprocedure('realtime.send(jsonb,text,text,boolean)') is not null then
      perform realtime.send(v_payload,'paigow_state_changed','paigow:room:'||p_room_id::text,true);
      if v_send_lobby then
        perform realtime.send(
          jsonb_build_object('room_id',p_room_id,'lobby_version',v_lobby_version,'reason',coalesce(nullif(p_reason,''),'state_changed'),'snapshot_required',true,'emitted_at',clock_timestamp()),
          'paigow_lobby_changed','paigow:lobby',true
        );
      end if;
    end if;
  exception when others then
    -- 广播故障不得破坏权威资金与牌局事务；事件版本仍然提交，客户端可在校准时恢复。
    raise warning 'V1_6_PAIGOW_EVENT_WARNING room=% reason=% error=%',p_room_id,p_reason,sqlerrm;
  end;
  return v_room_version;
end
$$;

create or replace function public.paigow_emit_state_event_v16_bpaigow01(
  p_room_id uuid,
  p_reason text
)
returns bigint
language sql
security definer
set search_path=public,pg_temp
as $$
  select public.paigow_emit_state_event_payload_v16_bpaigow01($1,$2,'{}'::jsonb,true)
$$;

create or replace function public.paigow_room_event_trigger_v16_bpaigow01()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_room_id uuid;v_row jsonb;
begin
  v_room_id:=case when tg_op='DELETE' then old.id else new.id end;
  v_row:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
  perform public.paigow_emit_state_event_payload_v16_bpaigow01(
    v_room_id,'room_'||lower(tg_op),
    jsonb_build_object('kind','room','op',lower(tg_op),'room',v_row),
    tg_op<>'UPDATE'
  );
  if tg_op='DELETE' then return old; end if;
  return new;
end
$$;

create or replace function public.paigow_member_event_trigger_v16_bpaigow01()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_room_id uuid;v_character_id uuid;v_name text;v_reason text;v_before jsonb:='null'::jsonb;v_after jsonb:='null'::jsonb;
begin
  v_room_id:=case when tg_op='DELETE' then old.room_id else new.room_id end;
  v_character_id:=case when tg_op='DELETE' then old.character_id else new.character_id end;
  select name into v_name from public.player_characters where id=v_character_id;
  if tg_op in('UPDATE','DELETE') then
    v_before:=jsonb_build_object('character_id',old.character_id,'name',v_name,'seat_no',old.seat_no,'role',old.role,'ready',old.ready,'ready_deadline',old.ready_deadline,'left_at',old.left_at);
  end if;
  if tg_op in('INSERT','UPDATE') then
    v_after:=jsonb_build_object('character_id',new.character_id,'name',v_name,'seat_no',new.seat_no,'role',new.role,'ready',new.ready,'ready_deadline',new.ready_deadline,'left_at',new.left_at);
  end if;
  v_reason:=case
    when tg_op='UPDATE'
      and old.seat_no is not distinct from new.seat_no
      and old.role is not distinct from new.role
      and old.left_at is not distinct from new.left_at
      then 'member_ready_update'
    else 'member_'||lower(tg_op)
  end;
  perform public.paigow_emit_state_event_payload_v16_bpaigow01(
    v_room_id,v_reason,
    jsonb_build_object('kind','member','op',lower(tg_op),'character_id',v_character_id,'before',v_before,'after',v_after),
    false
  );
  if tg_op='DELETE' then return old; end if;
  return new;
end
$$;

create or replace function public.paigow_round_event_trigger_v16_bpaigow01()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_room_id uuid;v_row jsonb;
begin
  v_room_id:=case when tg_op='DELETE' then old.room_id else new.room_id end;
  v_row:=case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
  perform public.paigow_emit_state_event_payload_v16_bpaigow01(
    v_room_id,'round_'||lower(tg_op),
    jsonb_build_object('kind','round','op',lower(tg_op),'round',v_row),
    true
  );
  if tg_op='DELETE' then return old; end if;
  return new;
end
$$;

create or replace function public.paigow_round_player_event_trigger_v16_bpaigow01()
returns trigger
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare v_round_id uuid;v_room_id uuid;v_character_id uuid;v_before jsonb:='null'::jsonb;v_after jsonb:='null'::jsonb;
begin
  v_round_id:=case when tg_op='DELETE' then old.round_id else new.round_id end;
  v_character_id:=case when tg_op='DELETE' then old.character_id else new.character_id end;
  select room_id into v_room_id from public.paigow_rounds_bpaigow01 where id=v_round_id;
  if tg_op in('UPDATE','DELETE') then
    v_before:=jsonb_build_object('character_id',old.character_id,'active',old.active_in_round,'fold_reason',old.fold_reason,'multiplier',old.multiplier,'action_confirmed',old.action_confirmed);
  end if;
  if tg_op in('INSERT','UPDATE') then
    v_after:=jsonb_build_object('character_id',new.character_id,'active',new.active_in_round,'fold_reason',new.fold_reason,'multiplier',new.multiplier,'action_confirmed',new.action_confirmed);
  end if;
  if v_room_id is not null then
    perform public.paigow_emit_state_event_payload_v16_bpaigow01(
      v_room_id,'player_action_'||lower(tg_op),
      jsonb_build_object('kind','round_player','op',lower(tg_op),'round_id',v_round_id,'character_id',v_character_id,'before',v_before,'after',v_after),
      false
    );
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end
$$;

drop trigger if exists paigow_room_event_v16 on public.paigow_rooms_bpaigow01;
create trigger paigow_room_event_v16
after insert or update or delete on public.paigow_rooms_bpaigow01
for each row execute function public.paigow_room_event_trigger_v16_bpaigow01();

drop trigger if exists paigow_member_event_v16 on public.paigow_room_members_bpaigow01;
create trigger paigow_member_event_v16
after insert or update or delete on public.paigow_room_members_bpaigow01
for each row execute function public.paigow_member_event_trigger_v16_bpaigow01();

drop trigger if exists paigow_round_event_v16 on public.paigow_rounds_bpaigow01;
create trigger paigow_round_event_v16
after insert or update or delete on public.paigow_rounds_bpaigow01
for each row execute function public.paigow_round_event_trigger_v16_bpaigow01();

drop trigger if exists paigow_round_player_event_v16 on public.paigow_round_players_bpaigow01;
create trigger paigow_round_player_event_v16
after insert or delete or update of rob_choice,multiplier,action_confirmed,head_indices,payout_amount,net_amount,active_in_round,fold_reason
on public.paigow_round_players_bpaigow01
for each row execute function public.paigow_round_player_event_trigger_v16_bpaigow01();

-- 读取函数从V1.6开始严格只读：超时维护与阶段推进交给全局调度器。
create or replace function public.get_paigow_lobby_bpaigow01()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_character uuid:=public.casino_current_character_id_v1();
  v_rooms jsonb;v_stone bigint;v_cult bigint;v_enabled boolean;v_stone_available bigint;v_event_version bigint:=0;
begin
  select enabled into v_enabled from public.paigow_settings_bpaigow01 where singleton_id=1;
  select last_value into v_event_version from public.paigow_lobby_event_seq_bpaigow01;
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
    'event_version',coalesce(v_event_version,0),'sync_mode','realtime_broadcast',
    'rooms',v_rooms,'room_limit',4,'character_id',v_character,
    'balances',jsonb_build_object('spirit_stone',v_stone_available,'cultivation',public.casino_available_v1(v_character,'cultivation')),
    'bankrolls',jsonb_build_object('spirit_stone',v_stone,'cultivation',v_cult),
    'rules',jsonb_build_object(
      'idle_close_seconds',300,'ready_seconds',10,'auto_start_seconds',2,'small_prepare_seconds',5,
      'minimum_entry_multiplier',10,'cultivation_stakes_enabled',false,'player_fee_bps',250,
      'player_dealer_pro_rata',true,'big_tie_fee_refund',true,'sync_mode','realtime_broadcast',
      'safety_resync_seconds',60,'multipliers',jsonb_build_array(10,50,100)
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
  rp record;v_balance bigint;v_bank bigint;v_result jsonb;v_event_version bigint:=0;
begin
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
  select coalesce(state_version,0) into v_event_version from public.paigow_room_event_versions_bpaigow01 where room_id=p_room_id;
  return jsonb_build_object('event_version',coalesce(v_event_version,0),'sync_mode','realtime_broadcast','room',to_jsonb(v_room),'members',v_members,'round',v_result,'self_character_id',v_character,'self_member',coalesce(v_self_member,'null'::jsonb),
    'self_balance',v_balance,'bankroll_balance',v_bank,'server_time',clock_timestamp());
end $$;


-- 自动开局内部函数不依赖用户JWT，供数据库调度器安全调用。
create or replace function public.paigow_start_round_internal_v16_bpaigow01(
  p_room_id uuid
)
returns uuid
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
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

  return v_round.id;
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
  v_character uuid:=public.casino_current_character_id_v1();
  v_existing jsonb;
begin
  perform public.paigow_assert_enabled_bpaigow01();
  v_existing:=public.paigow_action_existing_bpaigow01(v_character,p_request_id,'start_round');
  if v_existing is not null then return v_existing; end if;
  if not public.paigow_action_claim_bpaigow01(v_character,p_request_id,'start_round',jsonb_build_object('room_id',p_room_id)) then
    raise exception 'PAIGOW_REQUEST_IN_PROGRESS';
  end if;
  perform public.paigow_start_round_internal_v16_bpaigow01(p_room_id);
  return public.paigow_action_finish_bpaigow01(v_character,p_request_id,'start_round',public.get_paigow_room_state_bpaigow01(p_room_id));
end
$$;

create or replace function public.paigow_advance_room_internal_v16_bpaigow01(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_room public.paigow_rooms_bpaigow01%rowtype;
  v_round public.paigow_rounds_bpaigow01%rowtype;
  rp record;
  v_pending integer;
  v_seconds integer;
  v_before text;
begin
  perform public.paigow_assert_enabled_bpaigow01();
  perform public.paigow_prepare_waiting_room_bpaigow01(p_room_id);
  select * into v_room from public.paigow_rooms_bpaigow01 where id=p_room_id for update;
  if v_room.id is null then return jsonb_build_object('status','missing','room_id',p_room_id); end if;
  if v_room.status='closed' then return jsonb_build_object('status','closed','room_id',p_room_id); end if;

  if v_room.status='waiting' then
    if v_room.auto_start_at is not null and v_room.auto_start_at<=clock_timestamp() then
      perform public.paigow_start_round_internal_v16_bpaigow01(p_room_id);
      return jsonb_build_object('status','started','room_id',p_room_id);
    end if;
    return jsonb_build_object('status','waiting','room_id',p_room_id);
  end if;

  select * into v_round from public.paigow_rounds_bpaigow01
  where room_id=p_room_id order by round_no desc limit 1 for update;
  if v_round.id is null or v_round.phase in('settled','cancelled') then
    return jsonb_build_object('status','idle','room_id',p_room_id);
  end if;
  v_before:=v_round.phase;

  if v_round.phase='rob' then
    select count(*) into v_pending from public.paigow_round_players_bpaigow01
    where round_id=v_round.id and active_in_round and rob_choice is null;
    if v_pending=0 or v_round.phase_deadline<=clock_timestamp() then
      update public.paigow_round_players_bpaigow01 set rob_choice=false
      where round_id=v_round.id and active_in_round and rob_choice is null;
      perform public.paigow_choose_dealer_internal_bpaigow01(v_round.id);
    end if;
  elsif v_round.phase='multiplier' and v_round.phase_deadline<=clock_timestamp() then
    for rp in
      select x.character_id
      from public.paigow_round_players_bpaigow01 x
      join public.paigow_rounds_bpaigow01 r on r.id=x.round_id
      join public.paigow_rooms_bpaigow01 rm on rm.id=r.room_id
      where x.round_id=v_round.id and x.active_in_round and not x.action_confirmed
        and not(rm.duel_type='pvp' and rm.pvp_mode='rob' and x.character_id=r.dealer_character_id)
      order by x.seat_no
    loop
      perform public.paigow_apply_multiplier_internal_bpaigow01(v_round.id,rp.character_id,10,true);
    end loop;
    perform public.paigow_after_multiplier_internal_bpaigow01(v_round.id);
  elsif v_round.phase='arrange' then
    select count(*) into v_pending from public.paigow_round_players_bpaigow01
    where round_id=v_round.id and active_in_round and not action_confirmed;
    if v_pending=0 or v_round.phase_deadline<=clock_timestamp() then
      perform public.paigow_begin_head_reveal_internal_bpaigow01(v_round.id);
    end if;
  elsif v_round.phase='head_reveal' and v_round.phase_deadline<=clock_timestamp() then
    select tail_reveal_seconds into v_seconds from public.paigow_settings_bpaigow01 where singleton_id=1;
    update public.paigow_rounds_bpaigow01
    set phase='tail_reveal',phase_deadline=clock_timestamp()+make_interval(secs=>v_seconds)
    where id=v_round.id;
  elsif v_round.phase='tail_reveal' and v_round.phase_deadline<=clock_timestamp() then
    perform public.paigow_settle_round_internal_bpaigow01(v_round.id);
  end if;

  return jsonb_build_object('status','advanced','room_id',p_room_id,'phase_before',v_before);
end
$$;

create or replace function public.advance_paigow_round_bpaigow01(p_room_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
begin
  perform public.paigow_advance_room_internal_v16_bpaigow01(p_room_id);
  return public.get_paigow_room_state_bpaigow01(p_room_id);
end
$$;

create or replace function public.paigow_tick_due_rooms_bpaigow01()
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_room_id uuid;
  v_checked integer:=0;
  v_advanced integer:=0;
  v_errors jsonb:='[]'::jsonb;
  v_result jsonb;
  v_message text;
begin
  for v_room_id in
    select r.id
    from public.paigow_rooms_bpaigow01 r
    left join lateral (
      select rr.phase,rr.phase_deadline
      from public.paigow_rounds_bpaigow01 rr
      where rr.room_id=r.id
      order by rr.round_no desc
      limit 1
    ) latest on true
    where
      (r.status='waiting' and (
        (r.first_round_started_at is null and r.idle_expires_at<=clock_timestamp())
        or r.auto_start_at<=clock_timestamp()
        or exists(
          select 1 from public.paigow_room_members_bpaigow01 m
          where m.room_id=r.id and m.left_at is null and m.role='player' and not m.ready
            and m.ready_deadline is not null and m.ready_deadline<=clock_timestamp()
        )
      ))
      or (r.status='playing' and latest.phase not in('settled','cancelled') and latest.phase_deadline<=clock_timestamp())
    order by coalesce(latest.phase_deadline,r.auto_start_at,r.idle_expires_at),r.slot_no
    limit 16
  loop
    v_checked:=v_checked+1;
    if not pg_try_advisory_xact_lock(hashtextextended('bpaigow01-v16-tick:'||v_room_id::text,7103)) then
      continue;
    end if;
    begin
      v_result:=public.paigow_advance_room_internal_v16_bpaigow01(v_room_id);
      v_advanced:=v_advanced+1;
    exception when others then
      get stacked diagnostics v_message=message_text;
      v_errors:=v_errors||jsonb_build_array(jsonb_build_object('room_id',v_room_id,'error',v_message));
    end;
  end loop;
  return jsonb_build_object('checked',v_checked,'advanced',v_advanced,'errors',v_errors,'server_time',clock_timestamp());
end
$$;

-- Realtime私有频道只广播房间ID、版本号和变化原因，绝不包含私牌或资金密钥。
drop policy if exists paigow_v16_authenticated_receive on realtime.messages;
create policy paigow_v16_authenticated_receive
on realtime.messages
for select
to authenticated
using (
  realtime.messages.extension='broadcast'
  and (
    (select realtime.topic())='paigow:lobby'
    or (select realtime.topic()) ~ '^paigow:room:[0-9a-fA-F-]{36}$'
  )
);

-- 客户端不允许直接向权威牌局频道广播游戏动作；所有动作继续走事务RPC。
drop policy if exists paigow_v16_authenticated_send on realtime.messages;

revoke all on function public.paigow_emit_state_event_v16_bpaigow01(uuid,text),
  public.paigow_emit_state_event_payload_v16_bpaigow01(uuid,text,jsonb,boolean),
  public.paigow_start_round_internal_v16_bpaigow01(uuid),
  public.paigow_advance_room_internal_v16_bpaigow01(uuid),
  public.paigow_tick_due_rooms_bpaigow01() from public,anon,authenticated;

grant execute on function public.get_paigow_lobby_bpaigow01(),
  public.get_paigow_room_state_bpaigow01(uuid),
  public.advance_paigow_round_bpaigow01(uuid),
  public.start_paigow_round_bpaigow01(uuid,uuid) to authenticated;

comment on function public.get_paigow_lobby_bpaigow01() is 'V1.6：纯读取大厅快照，不再轮询时写库或遍历推进房间。';
comment on function public.get_paigow_room_state_bpaigow01(uuid) is 'V1.6：纯读取房间快照；私牌仍按登录身份隔离。';
comment on function public.paigow_tick_due_rooms_bpaigow01() is 'V1.6：全局秒级调度器，每个到期房间只推进一次。';
comment on function public.advance_paigow_round_bpaigow01(uuid) is 'V1.6：仅用于手动刷新与Realtime/Cron故障兜底，不再由每名玩家每秒调用。';

-- 使用单一数据库作业处理全部牌九房间的阶段到期；不存在每个玩家各自的1秒轮询。
do $$
declare v_job_id bigint;
begin
  for v_job_id in select jobid from cron.job where jobname='jiuxiao-paigow-v16-tick' loop
    perform cron.unschedule(v_job_id);
  end loop;
  perform cron.schedule(
    'jiuxiao-paigow-v16-tick',
    '1 second',
    $job$select public.paigow_tick_due_rooms_bpaigow01();$job$
  );
end
$$;

select public.paigow_emit_state_event_v16_bpaigow01(id,'v1_6_bootstrap')
from public.paigow_rooms_bpaigow01
where status in('waiting','playing');

notify pgrst,'reload schema';
commit;
