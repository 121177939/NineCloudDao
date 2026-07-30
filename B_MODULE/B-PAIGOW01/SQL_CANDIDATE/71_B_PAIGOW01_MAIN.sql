-- B-PAIGOW01 / 71_B_PAIGOW01_MAIN.sql
-- 九霄灵牌房间、桌位、动作与赌场资金接入候选。
-- 不创建第二套赌场资金；老何庄与玩家局手续费只调用 V1.1 FIX1 既有资金函数。
begin;

create table if not exists public.paigow_rooms_bpaigow01(
  id uuid primary key default gen_random_uuid(),
  slot_no smallint not null check(slot_no between 1 and 4),
  room_name text not null,
  owner_character_id uuid not null references public.player_characters(id) on delete cascade,
  duel_type text not null check(duel_type in('laohe','pvp')),
  pvp_mode text check((duel_type='laohe' and pvp_mode is null) or (duel_type='pvp' and pvp_mode in('rob','boat'))),
  game_mode text not null check(game_mode in('small','big')),
  stake_type text not null check(stake_type in('spirit_stone','cultivation')),
  base_stake bigint not null check(base_stake>0),
  status text not null default 'waiting' check(status in('waiting','playing','closed','disabled')),
  first_round_started_at timestamptz,
  idle_expires_at timestamptz not null default now()+interval '20 minutes',
  fee_carry_bps integer not null default 0 check(fee_carry_bps between 0 and 9999),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  closed_at timestamptz
);
create unique index if not exists paigow_room_slot_open_bpaigow01 on public.paigow_rooms_bpaigow01(slot_no) where status in('waiting','playing');
create index if not exists paigow_room_status_bpaigow01 on public.paigow_rooms_bpaigow01(status,created_at);

create table if not exists public.paigow_room_members_bpaigow01(
  room_id uuid not null references public.paigow_rooms_bpaigow01(id) on delete cascade,
  character_id uuid not null references public.player_characters(id) on delete cascade,
  seat_no smallint check(seat_no between 1 and 9),
  role text not null default 'player' check(role in('player','spectator')),
  ready boolean not null default false,
  joined_at timestamptz not null default now(),
  left_at timestamptz,
  primary key(room_id,character_id)
);
create unique index if not exists paigow_room_seat_open_bpaigow01 on public.paigow_room_members_bpaigow01(room_id,seat_no) where left_at is null and role='player';

create table if not exists public.paigow_rounds_bpaigow01(
  id uuid primary key default gen_random_uuid(),
  room_id uuid not null references public.paigow_rooms_bpaigow01(id) on delete cascade,
  round_no integer not null,
  phase text not null default 'waiting' check(phase in('waiting','rob','multiplier','arrange','head_reveal','tail_reveal','settled','cancelled')),
  dealer_character_id uuid references public.player_characters(id),
  phase_deadline timestamptz,
  started_at timestamptz not null default now(),
  settled_at timestamptz,
  result_payload jsonb not null default '{}'::jsonb,
  unique(room_id,round_no)
);
create index if not exists paigow_round_active_bpaigow01 on public.paigow_rounds_bpaigow01(room_id,started_at desc) where phase not in('settled','cancelled');

create table if not exists public.paigow_round_players_bpaigow01(
  round_id uuid not null references public.paigow_rounds_bpaigow01(id) on delete cascade,
  character_id uuid not null references public.player_characters(id) on delete cascade,
  seat_no smallint not null,
  rob_choice boolean,
  multiplier integer check(multiplier in(10,50,100)),
  stake_amount bigint not null default 0 check(stake_amount>=0),
  fee_amount bigint not null default 0 check(fee_amount>=0),
  bankroll_reserve bigint not null default 0 check(bankroll_reserve>=0),
  cards jsonb not null default '[]'::jsonb,
  head_indices smallint[],
  action_confirmed boolean not null default false,
  payout_amount bigint not null default 0 check(payout_amount>=0),
  net_amount bigint not null default 0,
  result_payload jsonb not null default '{}'::jsonb,
  primary key(round_id,character_id)
);

create table if not exists public.paigow_action_requests_bpaigow01(
  character_id uuid not null references public.player_characters(id) on delete cascade,
  request_id uuid not null,
  action_code text not null,
  request_payload jsonb not null default '{}'::jsonb,
  response_payload jsonb,
  created_at timestamptz not null default now(),
  primary key(character_id,request_id)
);

create table if not exists public.paigow_tile_defs_bpaigow01(
  physical_code text primary key,
  tile_key text not null,
  tile_name text not null,
  pip_value smallint not null check(pip_value between 2 and 12),
  single_rank smallint not null,
  pair_key text not null,
  pair_rank smallint not null,
  face jsonb not null
);

insert into public.paigow_tile_defs_bpaigow01(physical_code,tile_key,tile_name,pip_value,single_rank,pair_key,pair_rank,face) values
('teen1','teen','天牌',12,17,'teen',16,'{"top":{"w":[1,4,7],"r":[3,6,9]},"bottom":{"r":[1,4,7],"w":[3,6,9]}}'),
('teen2','teen','天牌',12,17,'teen',16,'{"top":{"w":[1,4,7],"r":[3,6,9]},"bottom":{"r":[1,4,7],"w":[3,6,9]}}'),
('day1','day','地牌',2,16,'day',15,'{"top":{"r":[2]},"bottom":{"r":[8]}}'),
('day2','day','地牌',2,16,'day',15,'{"top":{"r":[2]},"bottom":{"r":[8]}}'),
('yun1','yun','人牌',8,15,'yun',14,'{"top":{"r":[1,3,7,9]},"bottom":{"r":[1,3,7,9]}}'),
('yun2','yun','人牌',8,15,'yun',14,'{"top":{"r":[1,3,7,9]},"bottom":{"r":[1,3,7,9]}}'),
('gor1','gor','和牌',4,14,'gor',13,'{"top":{"r":[2]},"bottom":{"w":[1,5,9]}}'),
('gor2','gor','和牌',4,14,'gor',13,'{"top":{"r":[2]},"bottom":{"w":[1,5,9]}}'),
('mooy1','mooy','梅花',10,13,'mooy',12,'{"top":{"w":[1,3,5,7,9]},"bottom":{"w":[1,3,5,7,9]}}'),
('mooy2','mooy','梅花',10,13,'mooy',12,'{"top":{"w":[1,3,5,7,9]},"bottom":{"w":[1,3,5,7,9]}}'),
('chong1','chong','长三',6,12,'chong',11,'{"top":{"w":[1,5,9]},"bottom":{"w":[1,5,9]}}'),
('chong2','chong','长三',6,12,'chong',11,'{"top":{"w":[1,5,9]},"bottom":{"w":[1,5,9]}}'),
('bon1','bon','板凳',4,11,'bon',10,'{"top":{"w":[1,3]},"bottom":{"w":[7,9]}}'),
('bon2','bon','板凳',4,11,'bon',10,'{"top":{"w":[1,3]},"bottom":{"w":[7,9]}}'),
('foo1','foo','斧头',11,10,'foo',9,'{"top":{"w":[1,3,5,7,9]},"bottom":{"w":[1,3,4,6,7,9]}}'),
('foo2','foo','斧头',11,10,'foo',9,'{"top":{"w":[1,3,5,7,9]},"bottom":{"w":[1,3,4,6,7,9]}}'),
('ping1','ping','红头',10,9,'ping',8,'{"top":{"r":[1,3,7,9]},"bottom":{"w":[1,3,4,6,7,9]}}'),
('ping2','ping','红头',10,9,'ping',8,'{"top":{"r":[1,3,7,9]},"bottom":{"w":[1,3,4,6,7,9]}}'),
('tit1','tit','高脚七',7,8,'tit',7,'{"top":{"r":[2]},"bottom":{"w":[1,3,4,6,7,9]}}'),
('tit2','tit','高脚七',7,8,'tit',7,'{"top":{"r":[2]},"bottom":{"w":[1,3,4,6,7,9]}}'),
('look1','look','铜锤',6,7,'look',6,'{"top":{"r":[2]},"bottom":{"w":[1,3,5,7,9]}}'),
('look2','look','铜锤',6,7,'look',6,'{"top":{"r":[2]},"bottom":{"w":[1,3,5,7,9]}}'),
('chop9a','chop9a','杂九',9,6,'chop9',5,'{"top":{"r":[1,3,7,9]},"bottom":{"w":[1,3,5,7,9]}}'),
('chop9b','chop9b','杂九',9,6,'chop9',5,'{"top":{"w":[1,5,9]},"bottom":{"w":[1,3,4,6,7,9]}}'),
('chop8a','chop8a','杂八',8,5,'chop8',4,'{"top":{"w":[1,3]},"bottom":{"w":[1,3,4,6,7,9]}}'),
('chop8b','chop8b','杂八',8,5,'chop8',4,'{"top":{"w":[1,5,9]},"bottom":{"w":[1,3,5,7,9]}}'),
('chop7a','chop7a','杂七',7,4,'chop7',3,'{"top":{"w":[1,3]},"bottom":{"w":[1,3,5,7,9]}}'),
('chop7b','chop7b','杂七',7,4,'chop7',3,'{"top":{"w":[1,5,9]},"bottom":{"r":[1,3,7,9]}}'),
('chop5a','chop5a','杂五',5,2,'chop5',2,'{"top":{"w":[1,5,9]},"bottom":{"w":[7,9]}}'),
('chop5b','chop5b','杂五',5,2,'chop5',2,'{"top":{"r":[2]},"bottom":{"r":[1,3,7,9]}}'),
('gee3','gee3','丁三',3,1,'gee',1,'{"top":{"r":[2]},"bottom":{"w":[7,9]}}'),
('gee6','gee6','二四',6,3,'gee',1,'{"top":{"w":[1,3]},"bottom":{"r":[1,3,7,9]}}')
on conflict(physical_code) do update set tile_key=excluded.tile_key,tile_name=excluded.tile_name,pip_value=excluded.pip_value,single_rank=excluded.single_rank,pair_key=excluded.pair_key,pair_rank=excluded.pair_rank,face=excluded.face;

alter table public.paigow_rooms_bpaigow01 enable row level security;
alter table public.paigow_room_members_bpaigow01 enable row level security;
alter table public.paigow_rounds_bpaigow01 enable row level security;
alter table public.paigow_round_players_bpaigow01 enable row level security;
alter table public.paigow_action_requests_bpaigow01 enable row level security;
alter table public.paigow_tile_defs_bpaigow01 enable row level security;
revoke all on table public.paigow_rooms_bpaigow01,public.paigow_room_members_bpaigow01,public.paigow_rounds_bpaigow01,public.paigow_round_players_bpaigow01,public.paigow_action_requests_bpaigow01,public.paigow_tile_defs_bpaigow01 from public,anon,authenticated;

create or replace function public.paigow_room_name_bpaigow01(p_slot smallint) returns text language sql immutable as $$
  select case p_slot when 1 then '天字一号房' when 2 then '地字二号房' when 3 then '玄字三号房' when 4 then '黄字四号房' end
$$;

create or replace function public.paigow_cleanup_rooms_bpaigow01() returns integer language plpgsql security definer set search_path=public,pg_temp as $$
declare v_count integer;
begin
  update public.paigow_rooms_bpaigow01 set status='closed',closed_at=now(),updated_at=now()
  where status='waiting' and first_round_started_at is null and idle_expires_at<=now();
  get diagnostics v_count=row_count; return v_count;
end $$;

create or replace function public.get_paigow_lobby_bpaigow01() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_character uuid:=public.casino_current_character_id_v1();v_rooms jsonb;v_stone bigint;v_cult bigint;
begin
  perform public.paigow_cleanup_rooms_bpaigow01();
  select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'slot_no',r.slot_no,'name',r.room_name,'duel_type',r.duel_type,'pvp_mode',r.pvp_mode,'game_mode',r.game_mode,'stake_type',r.stake_type,'base_stake',r.base_stake,'status',r.status,'expires_at',r.idle_expires_at,'players',(select count(*) from public.paigow_room_members_bpaigow01 m where m.room_id=r.id and m.left_at is null and m.role='player'),'spectators',(select count(*) from public.paigow_room_members_bpaigow01 m where m.room_id=r.id and m.left_at is null and m.role='spectator')) order by r.slot_no),'[]'::jsonb) into v_rooms from public.paigow_rooms_bpaigow01 r where r.status in('waiting','playing');
  select balance into v_stone from public.casino_bankroll_v1 where stake_type='spirit_stone';
  select balance into v_cult from public.casino_bankroll_v1 where stake_type='cultivation';
  return jsonb_build_object('status','active','rooms',v_rooms,'room_limit',4,'character_id',v_character,'balances',jsonb_build_object('spirit_stone',public.casino_available_v1(v_character,'spirit_stone'),'cultivation',public.casino_available_v1(v_character,'cultivation')),'bankrolls',jsonb_build_object('spirit_stone',v_stone,'cultivation',v_cult),'rules',jsonb_build_object('idle_close_seconds',1200,'player_fee_bps',250,'laohe_profit_bps',10000));
end $$;

create or replace function public.create_paigow_room_bpaigow01(p_duel_type text,p_pvp_mode text,p_game_mode text,p_stake_type text,p_base_stake bigint) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_character uuid:=public.casino_current_character_id_v1();v_slot smallint;v_room public.paigow_rooms_bpaigow01%rowtype;
begin
  perform public.casino_assert_enabled_v1();perform public.paigow_cleanup_rooms_bpaigow01();
  if p_duel_type not in('laohe','pvp') or p_game_mode not in('small','big') or p_stake_type not in('spirit_stone','cultivation') then raise exception 'PAIGOW_ROOM_CONFIG_INVALID';end if;
  if p_duel_type='pvp' and p_pvp_mode not in('rob','boat') then raise exception 'PAIGOW_PVP_MODE_INVALID';end if;
  if p_duel_type='laohe' then p_pvp_mode:=null;end if;
  if p_base_stake is null or p_base_stake<1 then raise exception 'PAIGOW_BASE_STAKE_INVALID';end if;
  perform pg_advisory_xact_lock(hashtextextended('bpaigow01-room-slots',7101));
  select s into v_slot from generate_series(1,4) s where not exists(select 1 from public.paigow_rooms_bpaigow01 r where r.slot_no=s and r.status in('waiting','playing')) order by s limit 1;
  if v_slot is null then raise exception 'PAIGOW_ROOM_LIMIT_REACHED';end if;
  insert into public.paigow_rooms_bpaigow01(slot_no,room_name,owner_character_id,duel_type,pvp_mode,game_mode,stake_type,base_stake)
  values(v_slot,public.paigow_room_name_bpaigow01(v_slot),v_character,p_duel_type,p_pvp_mode,p_game_mode,p_stake_type,p_base_stake) returning * into v_room;
  return jsonb_build_object('room',to_jsonb(v_room));
end $$;

create or replace function public.join_paigow_room_bpaigow01(p_room_id uuid,p_seat_no smallint default null,p_spectator boolean default false) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_character uuid:=public.casino_current_character_id_v1();v_room public.paigow_rooms_bpaigow01%rowtype;v_limit integer;v_players integer;
begin
  perform public.paigow_cleanup_rooms_bpaigow01();select * into v_room from public.paigow_rooms_bpaigow01 where id=p_room_id and status in('waiting','playing') for update;
  if v_room.id is null then raise exception 'PAIGOW_ROOM_NOT_AVAILABLE';end if;
  v_limit:=case when v_room.game_mode='big' then 8 else 9 end;
  select count(*) into v_players from public.paigow_room_members_bpaigow01 where room_id=p_room_id and left_at is null and role='player';
  if p_spectator or v_players>=v_limit then
    insert into public.paigow_room_members_bpaigow01(room_id,character_id,seat_no,role,left_at,ready) values(p_room_id,v_character,null,'spectator',null,false)
    on conflict(room_id,character_id) do update set seat_no=null,role='spectator',left_at=null,ready=false,joined_at=now();
  else
    if p_seat_no is null or p_seat_no not between 1 and 9 then raise exception 'PAIGOW_SEAT_INVALID';end if;
    if v_room.game_mode='big' and p_seat_no=9 then raise exception 'PAIGOW_BIG_SEAT_NINE_SPECTATOR_ONLY';end if;
    insert into public.paigow_room_members_bpaigow01(room_id,character_id,seat_no,role,left_at,ready) values(p_room_id,v_character,p_seat_no,'player',null,false)
    on conflict(room_id,character_id) do update set seat_no=excluded.seat_no,role='player',left_at=null,ready=false,joined_at=now();
  end if;
  return public.get_paigow_room_state_bpaigow01(p_room_id);
end $$;

create or replace function public.leave_paigow_room_bpaigow01(p_room_id uuid) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_character uuid:=public.casino_current_character_id_v1();
begin
  update public.paigow_room_members_bpaigow01 set left_at=now(),ready=false where room_id=p_room_id and character_id=v_character and left_at is null;
  return jsonb_build_object('left',true,'room_id',p_room_id);
end $$;

create or replace function public.get_paigow_room_state_bpaigow01(p_room_id uuid) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_character uuid:=public.casino_current_character_id_v1();v_room public.paigow_rooms_bpaigow01%rowtype;v_members jsonb;v_round jsonb;
begin
  perform public.paigow_cleanup_rooms_bpaigow01();select * into v_room from public.paigow_rooms_bpaigow01 where id=p_room_id;
  if v_room.id is null then raise exception 'PAIGOW_ROOM_NOT_FOUND';end if;
  select coalesce(jsonb_agg(jsonb_build_object('character_id',m.character_id,'name',pc.name,'seat_no',m.seat_no,'role',m.role,'ready',m.ready,'is_self',m.character_id=v_character) order by coalesce(m.seat_no,99),m.joined_at),'[]'::jsonb) into v_members from public.paigow_room_members_bpaigow01 m join public.player_characters pc on pc.id=m.character_id where m.room_id=p_room_id and m.left_at is null;
  select to_jsonb(x) into v_round from (select id,round_no,phase,dealer_character_id,phase_deadline,started_at,settled_at,result_payload from public.paigow_rounds_bpaigow01 where room_id=p_room_id order by round_no desc limit 1)x;
  return jsonb_build_object('room',to_jsonb(v_room),'members',v_members,'round',coalesce(v_round,'null'::jsonb),'self_character_id',v_character);
end $$;

create or replace function public.set_paigow_ready_bpaigow01(p_room_id uuid,p_ready boolean) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_character uuid:=public.casino_current_character_id_v1();v_room public.paigow_rooms_bpaigow01%rowtype;
begin
  select * into v_room from public.paigow_rooms_bpaigow01 where id=p_room_id and status='waiting' for update;
  if v_room.id is null then raise exception 'PAIGOW_ROOM_NOT_WAITING';end if;
  update public.paigow_room_members_bpaigow01 set ready=coalesce(p_ready,false) where room_id=p_room_id and character_id=v_character and left_at is null and role='player';
  if not found then raise exception 'PAIGOW_PLAYER_NOT_SEATED';end if;
  return public.get_paigow_room_state_bpaigow01(p_room_id);
end $$;

-- Exact long-run 2.5% fee with integer currency: carry fractional basis points on the room.
create or replace function public.paigow_take_player_fee_bpaigow01(p_room_id uuid,p_character_id uuid,p_stake_type text,p_stake bigint,p_reference uuid) returns bigint language plpgsql security definer set search_path=public,pg_temp as $$
declare v_room public.paigow_rooms_bpaigow01%rowtype;v_numerator bigint;v_fee bigint;v_carry integer;
begin
  if p_stake is null or p_stake<0 then raise exception 'PAIGOW_STAKE_INVALID';end if;
  select * into v_room from public.paigow_rooms_bpaigow01 where id=p_room_id for update;
  if v_room.id is null or v_room.duel_type<>'pvp' then return 0;end if;
  v_numerator:=p_stake*250+v_room.fee_carry_bps;v_fee:=floor(v_numerator::numeric/10000)::bigint;v_carry:=(v_numerator%10000)::integer;
  update public.paigow_rooms_bpaigow01 set fee_carry_bps=v_carry,updated_at=now() where id=p_room_id;
  if v_fee>0 then
    perform public.casino_debit_v1(p_character_id,p_stake_type,v_fee,'house','paigow_fee_bpaigow01');
    perform public.casino_bankroll_apply_v1(p_stake_type,v_fee,'paigow_player_fee_bpaigow01',p_reference,jsonb_build_object('room_id',p_room_id,'character_id',p_character_id,'fee_bps',250));
  end if;
  return v_fee;
end $$;

-- Laohe 100:100 settlement helper. p_result: 1 player win, 0 tie, -1 player loss.
create or replace function public.paigow_settle_laohe_one_bpaigow01(p_room_id uuid,p_character_id uuid,p_stake_type text,p_stake bigint,p_result integer,p_reference uuid) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_bank bigint;v_credit jsonb;v_payout bigint:=0;
begin
  if p_result not in(-1,0,1) or p_stake is null or p_stake<=0 then raise exception 'PAIGOW_SETTLEMENT_INVALID';end if;
  perform public.casino_debit_v1(p_character_id,p_stake_type,p_stake,'house','paigow_laohe_bpaigow01');
  if p_result=1 then
    if public.casino_bankroll_available_v1(p_stake_type)<p_stake then raise exception 'CASINO_BANKROLL_INSUFFICIENT';end if;
    v_bank:=public.casino_bankroll_apply_v1(p_stake_type,-p_stake,'paigow_laohe_player_win_bpaigow01',p_reference,jsonb_build_object('room_id',p_room_id,'character_id',p_character_id,'odds','100:100'));
    v_payout:=p_stake*2;v_credit:=public.casino_credit_result_v0141(p_character_id,p_stake_type,v_payout);
  elsif p_result=0 then
    v_payout:=p_stake;v_credit:=public.casino_credit_result_v0141(p_character_id,p_stake_type,v_payout);select balance into v_bank from public.casino_bankroll_v1 where stake_type=p_stake_type;
  else
    v_bank:=public.casino_bankroll_apply_v1(p_stake_type,p_stake,'paigow_laohe_player_loss_bpaigow01',p_reference,jsonb_build_object('room_id',p_room_id,'character_id',p_character_id,'odds','100:100'));
  end if;
  return jsonb_build_object('result',p_result,'stake',p_stake,'payout',v_payout,'credit',coalesce(v_credit,'{}'::jsonb),'bankroll_balance_after',v_bank,'settlement_rule','laohe_100_to_100_existing_bankroll');
end $$;

revoke all on function public.paigow_room_name_bpaigow01(smallint),public.paigow_cleanup_rooms_bpaigow01(),public.get_paigow_lobby_bpaigow01(),public.create_paigow_room_bpaigow01(text,text,text,text,bigint),public.join_paigow_room_bpaigow01(uuid,smallint,boolean),public.leave_paigow_room_bpaigow01(uuid),public.get_paigow_room_state_bpaigow01(uuid),public.set_paigow_ready_bpaigow01(uuid,boolean),public.paigow_take_player_fee_bpaigow01(uuid,uuid,text,bigint,uuid),public.paigow_settle_laohe_one_bpaigow01(uuid,uuid,text,bigint,integer,uuid) from public,anon,authenticated;
grant execute on function public.get_paigow_lobby_bpaigow01(),public.create_paigow_room_bpaigow01(text,text,text,text,bigint),public.join_paigow_room_bpaigow01(uuid,smallint,boolean),public.leave_paigow_room_bpaigow01(uuid),public.get_paigow_room_state_bpaigow01(uuid),public.set_paigow_ready_bpaigow01(uuid,boolean) to authenticated;

commit;
