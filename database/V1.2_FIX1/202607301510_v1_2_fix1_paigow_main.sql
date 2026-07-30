-- V1.2 FIX1 CACHE38 / 72号修复版
-- 修复 PostgreSQL PL/pgSQL 中 IF 与 CASE 表达式的解析歧义。
-- 已修复 start_paigow_round、paigow_after_multiplier、paigow_settle_round 三处人数判断。
-- 本脚本可直接替换并重新执行原 72 号脚本；全部 DDL 使用 IF NOT EXISTS / CREATE OR REPLACE / UPSERT，可安全重跑。

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
  fee_carry_start integer not null default 0 check(fee_carry_start between 0 and 9999),
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

create or replace function public.create_paigow_room_bpaigow01(
  p_duel_type text,
  p_pvp_mode text,
  p_game_mode text,
  p_stake_type text,
  p_base_stake bigint
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_character uuid := public.casino_current_character_id_v1();
  v_slot smallint;
  v_room public.paigow_rooms_bpaigow01%rowtype;
  v_min bigint;
begin
  perform public.paigow_assert_enabled_bpaigow01();
  perform public.paigow_cleanup_rooms_bpaigow01();

  if p_duel_type not in ('laohe','pvp')
     or p_game_mode not in ('small','big')
     or p_stake_type not in ('spirit_stone','cultivation') then
    raise exception 'PAIGOW_ROOM_CONFIG_INVALID';
  end if;

  if p_duel_type='pvp' and p_pvp_mode not in ('rob','boat') then
    raise exception 'PAIGOW_PVP_MODE_INVALID';
  end if;

  if p_duel_type='laohe' then
    p_pvp_mode := null;
  end if;

  v_min := case when p_stake_type='cultivation' then 5000 else 10 end;
  if p_base_stake is null
     or p_base_stake < v_min
     or p_base_stake > 9007199254740 then
    raise exception 'PAIGOW_BASE_STAKE_INVALID';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('bpaigow01-room-slots',7101));

  select s::smallint
    into v_slot
    from generate_series(1,4) as s
   where not exists (
     select 1
       from public.paigow_rooms_bpaigow01 r
      where r.slot_no=s
        and r.status in ('waiting','playing')
   )
   order by s
   limit 1;

  if v_slot is null then
    raise exception 'PAIGOW_ROOM_LIMIT_REACHED';
  end if;

  insert into public.paigow_rooms_bpaigow01(
    slot_no,
    room_name,
    owner_character_id,
    duel_type,
    pvp_mode,
    game_mode,
    stake_type,
    base_stake
  )
  values(
    v_slot,
    public.paigow_room_name_bpaigow01(v_slot),
    v_character,
    p_duel_type,
    p_pvp_mode,
    p_game_mode,
    p_stake_type,
    p_base_stake
  )
  returning * into v_room;

  -- 关键修复：显式转成 smallint，避免 PostgreSQL 按 integer 查找不存在的重载。
  perform public.join_paigow_room_bpaigow01(v_room.id, 1::smallint, false);

  return jsonb_build_object(
    'room', to_jsonb(v_room),
    'state', public.get_paigow_room_state_bpaigow01(v_room.id)
  );
end
$$;

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

-- ---------------------------------------------------------------------------
-- A线正式并线补全：服务端洗牌、私牌遮罩、幂等动作、阶段推进与整桌原子结算。
-- 正式版本：V1.2 FIX1 CACHE38。
-- ---------------------------------------------------------------------------
begin;

create table if not exists public.paigow_settings_bpaigow01(
  singleton_id smallint primary key default 1 check(singleton_id=1),
  enabled boolean not null default true,
  player_fee_bps integer not null default 250 check(player_fee_bps between 0 and 10000),
  rob_seconds integer not null default 10 check(rob_seconds between 3 and 60),
  multiplier_seconds integer not null default 10 check(multiplier_seconds between 3 and 60),
  small_multiplier_seconds integer not null default 6 check(small_multiplier_seconds between 3 and 60),
  big_multiplier_seconds integer not null default 10 check(big_multiplier_seconds between 3 and 60),
  arrange_seconds integer not null default 30 check(arrange_seconds between 10 and 120),
  head_reveal_seconds integer not null default 10 check(head_reveal_seconds between 3 and 60),
  tail_reveal_seconds integer not null default 3 check(tail_reveal_seconds between 1 and 30),
  updated_at timestamptz not null default now()
);
insert into public.paigow_settings_bpaigow01(singleton_id) values(1)
on conflict(singleton_id) do nothing;

alter table public.paigow_round_players_bpaigow01
  add column if not exists active_in_round boolean not null default true,
  add column if not exists fold_reason text,
  add column if not exists resource_before bigint not null default 0,
  add column if not exists stake_cap bigint not null default 0;

alter table public.paigow_rounds_bpaigow01
  add column if not exists fee_carry_start integer not null default 0;

create table if not exists public.paigow_round_secrets_bpaigow01(
  round_id uuid primary key references public.paigow_rounds_bpaigow01(id) on delete cascade,
  shuffled_deck text[] not null,
  laohe_cards text[] not null default '{}'::text[],
  laohe_head_indices smallint[],
  created_at timestamptz not null default now()
);

alter table public.paigow_settings_bpaigow01 enable row level security;
alter table public.paigow_round_secrets_bpaigow01 enable row level security;
revoke all on table public.paigow_settings_bpaigow01,public.paigow_round_secrets_bpaigow01 from public,anon,authenticated;

create or replace function public.paigow_assert_enabled_bpaigow01()
returns void language plpgsql stable security definer set search_path=public,pg_temp as $$
begin
  perform public.casino_assert_enabled_v1();
  if not coalesce((select enabled from public.paigow_settings_bpaigow01 where singleton_id=1),false) then
    raise exception 'PAIGOW_DISABLED';
  end if;
end $$;

create or replace function public.paigow_room_capacity_bpaigow01(p_duel_type text,p_game_mode text)
returns integer language sql immutable as $$
  select case
    when p_game_mode='big' and p_duel_type='laohe' then 7
    when p_game_mode='big' then 8
    else 9
  end
$$;

create or replace function public.paigow_jsonb_codes_bpaigow01(p_cards jsonb)
returns text[] language sql immutable as $$
  select coalesce(array_agg(e.value order by e.ord),'{}'::text[])
  from jsonb_array_elements_text(coalesce(p_cards,'[]'::jsonb)) with ordinality e(value,ord)
$$;

create or replace function public.paigow_tiles_json_bpaigow01(p_codes text[])
returns jsonb language sql stable security definer set search_path=public,pg_temp as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'code',d.physical_code,'key',d.tile_key,'name',d.tile_name,'pips',d.pip_value,
    'single_rank',d.single_rank,'pair_key',d.pair_key,'pair_rank',d.pair_rank,'face',d.face
  ) order by u.ord),'[]'::jsonb)
  from unnest(coalesce(p_codes,'{}'::text[])) with ordinality u(code,ord)
  join public.paigow_tile_defs_bpaigow01 d on d.physical_code=u.code
$$;

create or replace function public.paigow_pair_value_bpaigow01(p_cards text[])
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare
  a public.paigow_tile_defs_bpaigow01%rowtype;
  b public.paigow_tile_defs_bpaigow01%rowtype;
  v_points integer;v_score bigint;v_label text;v_category text;v_honor text;v_mate_pips integer;
  v_pair_key text;v_high integer;
begin
  if coalesce(array_length(p_cards,1),0)<>2 then
    return jsonb_build_object('score',-1,'label','未成牌','points',null,'high',0,'category','invalid');
  end if;
  select * into a from public.paigow_tile_defs_bpaigow01 where physical_code=p_cards[1];
  select * into b from public.paigow_tile_defs_bpaigow01 where physical_code=p_cards[2];
  if a.physical_code is null or b.physical_code is null then raise exception 'PAIGOW_TILE_INVALID';end if;
  v_points:=(a.pip_value+b.pip_value)%10;v_high:=greatest(a.single_rank,b.single_rank);
  if a.pair_key='gee' and b.pair_key='gee' and a.physical_code<>b.physical_code then
    v_score:=100000;v_label:='至尊宝';v_category:='supreme';
  elsif a.pair_key=b.pair_key and not(a.pair_key='gee' and b.pair_key='gee') then
    v_pair_key:=a.pair_key;v_score:=90000+greatest(a.pair_rank,b.pair_rank)*100;v_category:='pair';
    v_label:=case v_pair_key
      when 'teen' then '双天' when 'day' then '双地' when 'yun' then '双人' when 'gor' then '双和'
      when 'mooy' then '双梅花' when 'chong' then '双长三' when 'bon' then '双板凳'
      when 'foo' then '双斧头' when 'ping' then '双红头' when 'tit' then '双高脚七'
      when 'look' then '双铜锤' when 'chop9' then '杂九对' when 'chop8' then '杂八对'
      when 'chop7' then '杂七对' when 'chop5' then '杂五对' else a.tile_name||'对' end;
  else
    if a.tile_key in('teen','day') then v_honor:=a.tile_key;v_mate_pips:=b.pip_value;
    elsif b.tile_key in('teen','day') then v_honor:=b.tile_key;v_mate_pips:=a.pip_value;
    else v_honor:=null;v_mate_pips:=null;end if;
    if v_honor is not null and v_mate_pips=9 then
      v_score:=80000+case when v_honor='teen' then 200 else 100 end;
      v_label:=case when v_honor='teen' then '天王' else '地王' end;v_category:='wong';
    elsif v_honor is not null and v_mate_pips=8 then
      v_score:=70000+case when v_honor='teen' then 200 else 100 end;
      v_label:=case when v_honor='teen' then '天杠' else '地杠' end;v_category:='gong';
    elsif v_honor is not null and v_mate_pips=7 then
      v_score:=60000+case when v_honor='teen' then 200 else 100 end;
      v_label:=case when v_honor='teen' then '天高九' else '地高九' end;v_category:='high-nine';
    else
      v_score:=case when v_points=0 then 0 else v_points*1000+v_high*10 end;
      v_label:=v_points||'点';v_category:='points';
    end if;
  end if;
  return jsonb_build_object('score',v_score,'label',v_label,'points',v_points,'high',v_high,'category',v_category,
    'detail',a.tile_name||'＋'||b.tile_name,'cards',public.paigow_tiles_json_bpaigow01(p_cards));
end $$;

create or replace function public.paigow_split_value_bpaigow01(p_cards text[],p_head_indices smallint[])
returns jsonb language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_head text[];v_tail text[];v_h jsonb;v_t jsonb;v_i integer;v_seen integer[]:='{}'::integer[];
begin
  if coalesce(array_length(p_cards,1),0)<>4 or coalesce(array_length(p_head_indices,1),0)<>2 then raise exception 'PAIGOW_SPLIT_INVALID';end if;
  foreach v_i in array p_head_indices loop
    if v_i<0 or v_i>3 or v_i=any(v_seen) then raise exception 'PAIGOW_SPLIT_INVALID';end if;
    v_seen:=array_append(v_seen,v_i);
  end loop;
  v_head:=array[p_cards[p_head_indices[1]+1],p_cards[p_head_indices[2]+1]];
  select array_agg(p_cards[i] order by i) into v_tail from generate_series(1,4)i where (i-1)<>all(p_head_indices);
  v_h:=public.paigow_pair_value_bpaigow01(v_head);v_t:=public.paigow_pair_value_bpaigow01(v_tail);
  return jsonb_build_object('head_indices',to_jsonb(p_head_indices),'head',v_h,'tail',v_t,
    'valid',(v_h->>'score')::bigint<=(v_t->>'score')::bigint);
end $$;

create or replace function public.paigow_recommended_split_bpaigow01(p_cards text[])
returns smallint[] language plpgsql stable security definer set search_path=public,pg_temp as $$
declare v_idx smallint[];v_split jsonb;v_best smallint[];v_h bigint:=-1;v_t bigint:=-1;v_ch bigint;v_ct bigint;
begin
  if coalesce(array_length(p_cards,1),0)<>4 then raise exception 'PAIGOW_CARDS_NOT_FOUR';end if;
  for v_idx in
    select candidate from (values(array[0,1]::smallint[]),(array[0,2]::smallint[]),(array[0,3]::smallint[])) as c(candidate)
  loop
    v_split:=public.paigow_split_value_bpaigow01(p_cards,v_idx);
    if not coalesce((v_split->>'valid')::boolean,false) then
      v_idx:=array(select (i-1)::smallint from generate_series(1,4)i where (i-1)<>all(v_idx));
      v_split:=public.paigow_split_value_bpaigow01(p_cards,v_idx);
    end if;
    v_ch:=(v_split->'head'->>'score')::bigint;v_ct:=(v_split->'tail'->>'score')::bigint;
    if v_best is null or v_ch>v_h or (v_ch=v_h and v_ct>v_t) then v_best:=v_idx;v_h:=v_ch;v_t:=v_ct;end if;
  end loop;
  return v_best;
end $$;

create or replace function public.paigow_shuffle_deck_bpaigow01()
returns text[] language plpgsql volatile security definer set search_path=public,pg_temp as $$
declare v_deck text[];v_i integer;v_j integer;v_tmp text;
begin
  select array_agg(physical_code order by physical_code) into v_deck from public.paigow_tile_defs_bpaigow01;
  if coalesce(array_length(v_deck,1),0)<>32 then raise exception 'PAIGOW_TILE_DECK_NOT_32';end if;
  v_i:=32;
  while v_i>=2 loop
    v_j:=public.casino_secure_random_int_v1(v_i)+1;
    v_tmp:=v_deck[v_i];v_deck[v_i]:=v_deck[v_j];v_deck[v_j]:=v_tmp;
    v_i:=v_i-1;
  end loop;
  return v_deck;
end $$;

create or replace function public.paigow_round_compare_bpaigow01(p_game_mode text,p_cards_a text[],p_head_a smallint[],p_cards_b text[],p_head_b smallint[])
returns integer language plpgsql stable security definer set search_path=public,pg_temp as $$
declare va jsonb;vb jsonb;ah bigint;at bigint;bh bigint;bt bigint;
begin
  if p_game_mode='small' then
    va:=public.paigow_pair_value_bpaigow01(p_cards_a);vb:=public.paigow_pair_value_bpaigow01(p_cards_b);
    return case when (va->>'score')::bigint>(vb->>'score')::bigint then 1 when (va->>'score')::bigint<(vb->>'score')::bigint then -1 else 0 end;
  end if;
  va:=public.paigow_split_value_bpaigow01(p_cards_a,p_head_a);vb:=public.paigow_split_value_bpaigow01(p_cards_b,p_head_b);
  ah:=(va->'head'->>'score')::bigint;at:=(va->'tail'->>'score')::bigint;bh:=(vb->'head'->>'score')::bigint;bt:=(vb->'tail'->>'score')::bigint;
  if ah>bh and at>bt then return 1;elsif ah<bh and at<bt then return -1;else return 0;end if;
end $$;

commit;

begin;

create or replace function public.create_paigow_room_bpaigow01(
  p_duel_type text,
  p_pvp_mode text,
  p_game_mode text,
  p_stake_type text,
  p_base_stake bigint
)
returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  v_character uuid := public.casino_current_character_id_v1();
  v_slot smallint;
  v_room public.paigow_rooms_bpaigow01%rowtype;
  v_min bigint;
begin
  perform public.paigow_assert_enabled_bpaigow01();
  perform public.paigow_cleanup_rooms_bpaigow01();

  if p_duel_type not in ('laohe','pvp')
     or p_game_mode not in ('small','big')
     or p_stake_type not in ('spirit_stone','cultivation') then
    raise exception 'PAIGOW_ROOM_CONFIG_INVALID';
  end if;

  if p_duel_type='pvp' and p_pvp_mode not in ('rob','boat') then
    raise exception 'PAIGOW_PVP_MODE_INVALID';
  end if;

  if p_duel_type='laohe' then
    p_pvp_mode := null;
  end if;

  v_min := case when p_stake_type='cultivation' then 5000 else 10 end;
  if p_base_stake is null
     or p_base_stake < v_min
     or p_base_stake > 9007199254740 then
    raise exception 'PAIGOW_BASE_STAKE_INVALID';
  end if;

  perform pg_advisory_xact_lock(hashtextextended('bpaigow01-room-slots',7101));

  select s::smallint
    into v_slot
    from generate_series(1,4) as s
   where not exists (
     select 1
       from public.paigow_rooms_bpaigow01 r
      where r.slot_no=s
        and r.status in ('waiting','playing')
   )
   order by s
   limit 1;

  if v_slot is null then
    raise exception 'PAIGOW_ROOM_LIMIT_REACHED';
  end if;

  insert into public.paigow_rooms_bpaigow01(
    slot_no,
    room_name,
    owner_character_id,
    duel_type,
    pvp_mode,
    game_mode,
    stake_type,
    base_stake
  )
  values(
    v_slot,
    public.paigow_room_name_bpaigow01(v_slot),
    v_character,
    p_duel_type,
    p_pvp_mode,
    p_game_mode,
    p_stake_type,
    p_base_stake
  )
  returning * into v_room;

  -- 关键修复：显式转成 smallint，避免 PostgreSQL 按 integer 查找不存在的重载。
  perform public.join_paigow_room_bpaigow01(v_room.id, 1::smallint, false);

  return jsonb_build_object(
    'room', to_jsonb(v_room),
    'state', public.get_paigow_room_state_bpaigow01(v_room.id)
  );
end
$$;

create or replace function public.join_paigow_room_bpaigow01(p_room_id uuid,p_seat_no smallint default null,p_spectator boolean default false)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_character uuid:=public.casino_current_character_id_v1();v_room public.paigow_rooms_bpaigow01%rowtype;v_limit integer;v_players integer;v_existing_role text;
begin
  perform public.paigow_assert_enabled_bpaigow01();perform public.paigow_cleanup_rooms_bpaigow01();
  select * into v_room from public.paigow_rooms_bpaigow01 where id=p_room_id and status in('waiting','playing') for update;
  if v_room.id is null then raise exception 'PAIGOW_ROOM_NOT_AVAILABLE';end if;
  select role into v_existing_role from public.paigow_room_members_bpaigow01 where room_id=p_room_id and character_id=v_character and left_at is null;
  if v_room.status='playing' and v_existing_role='player' then return public.get_paigow_room_state_bpaigow01(p_room_id);end if;
  if v_room.status='playing' and not p_spectator then raise exception 'PAIGOW_ROUND_ALREADY_PLAYING';end if;
  v_limit:=public.paigow_room_capacity_bpaigow01(v_room.duel_type,v_room.game_mode);
  select count(*) into v_players from public.paigow_room_members_bpaigow01 where room_id=p_room_id and left_at is null and role='player';
  if p_spectator or (v_players>=v_limit and coalesce(v_existing_role,'')<>'player') then
    insert into public.paigow_room_members_bpaigow01(room_id,character_id,seat_no,role,left_at,ready)
    values(p_room_id,v_character,null,'spectator',null,false)
    on conflict(room_id,character_id) do update set seat_no=null,role='spectator',left_at=null,ready=false,joined_at=now();
  else
    if p_seat_no is null or p_seat_no not between 1 and 9 then raise exception 'PAIGOW_SEAT_INVALID';end if;
    if p_seat_no>v_limit then raise exception 'PAIGOW_SEAT_NOT_ACTIVE_FOR_MODE';end if;
    if exists(select 1 from public.paigow_room_members_bpaigow01 where room_id=p_room_id and seat_no=p_seat_no and left_at is null and role='player' and character_id<>v_character) then raise exception 'PAIGOW_SEAT_OCCUPIED';end if;
    insert into public.paigow_room_members_bpaigow01(room_id,character_id,seat_no,role,left_at,ready)
    values(p_room_id,v_character,p_seat_no,'player',null,false)
    on conflict(room_id,character_id) do update set seat_no=excluded.seat_no,role='player',left_at=null,ready=false,joined_at=now();
  end if;
  return public.get_paigow_room_state_bpaigow01(p_room_id);
end $$;

create or replace function public.get_paigow_lobby_bpaigow01()
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_character uuid:=public.casino_current_character_id_v1();v_rooms jsonb;v_stone bigint;v_cult bigint;v_enabled boolean;
begin
  perform public.paigow_cleanup_rooms_bpaigow01();
  select enabled into v_enabled from public.paigow_settings_bpaigow01 where singleton_id=1;
  select coalesce(jsonb_agg(jsonb_build_object(
    'id',r.id,'slot_no',r.slot_no,'name',r.room_name,'owner_character_id',r.owner_character_id,'duel_type',r.duel_type,'pvp_mode',r.pvp_mode,
    'game_mode',r.game_mode,'stake_type',r.stake_type,'base_stake',r.base_stake,'status',r.status,'expires_at',r.idle_expires_at,
    'players',(select count(*) from public.paigow_room_members_bpaigow01 m where m.room_id=r.id and m.left_at is null and m.role='player'),
    'capacity',public.paigow_room_capacity_bpaigow01(r.duel_type,r.game_mode),
    'spectators',(select count(*) from public.paigow_room_members_bpaigow01 m where m.room_id=r.id and m.left_at is null and m.role='spectator'),
    'joined',exists(select 1 from public.paigow_room_members_bpaigow01 m where m.room_id=r.id and m.character_id=v_character and m.left_at is null)
  ) order by r.slot_no),'[]'::jsonb) into v_rooms
  from public.paigow_rooms_bpaigow01 r where r.status in('waiting','playing');
  select balance into v_stone from public.casino_bankroll_v1 where stake_type='spirit_stone';
  select balance into v_cult from public.casino_bankroll_v1 where stake_type='cultivation';
  return jsonb_build_object('status',case when v_enabled then 'active' else 'disabled' end,'rooms',v_rooms,'room_limit',4,'character_id',v_character,
    'balances',jsonb_build_object('spirit_stone',public.casino_available_v1(v_character,'spirit_stone'),'cultivation',public.casino_available_v1(v_character,'cultivation')),
    'bankrolls',jsonb_build_object('spirit_stone',v_stone,'cultivation',v_cult),
    'rules',jsonb_build_object('idle_close_seconds',1200,'player_fee_bps',250,'laohe_profit_bps',10000,'multipliers',jsonb_build_array(10,50,100)));
end $$;

create or replace function public.get_paigow_room_state_bpaigow01(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_character uuid:=public.casino_current_character_id_v1();v_room public.paigow_rooms_bpaigow01%rowtype;v_members jsonb;v_round_rec public.paigow_rounds_bpaigow01%rowtype;
  v_players jsonb:='[]'::jsonb;v_cards text[];v_visible text[];v_head smallint[];v_public jsonb;v_self_member jsonb;v_phase text;
  v_secret public.paigow_round_secrets_bpaigow01%rowtype;v_laohe jsonb:='null'::jsonb;v_laohe_visible text[];v_laohe_public jsonb;
  rp record;v_balance bigint;v_bank bigint;v_result jsonb;
begin
  perform public.paigow_cleanup_rooms_bpaigow01();
  select * into v_room from public.paigow_rooms_bpaigow01 where id=p_room_id;
  if v_room.id is null then raise exception 'PAIGOW_ROOM_NOT_FOUND';end if;
  select coalesce(jsonb_agg(jsonb_build_object('character_id',m.character_id,'name',pc.name,'seat_no',m.seat_no,'role',m.role,'ready',m.ready,
    'is_self',m.character_id=v_character,'is_owner',m.character_id=v_room.owner_character_id) order by coalesce(m.seat_no,99),m.joined_at),'[]'::jsonb)
  into v_members from public.paigow_room_members_bpaigow01 m join public.player_characters pc on pc.id=m.character_id
  where m.room_id=p_room_id and m.left_at is null;
  select jsonb_build_object('seat_no',m.seat_no,'role',m.role,'ready',m.ready,'is_owner',m.character_id=v_room.owner_character_id)
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
        v_visible:=v_cards[1:1];
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
        else v_laohe_visible:=v_secret.laohe_cards[1:1];end if;
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

create or replace function public.paigow_action_existing_bpaigow01(p_character uuid,p_request uuid,p_action text)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_response jsonb;
begin
  if p_request is null then raise exception 'PAIGOW_REQUEST_ID_REQUIRED';end if;
  select response_payload into v_response from public.paigow_action_requests_bpaigow01 where character_id=p_character and request_id=p_request and action_code=p_action;
  return v_response;
end $$;

create or replace function public.paigow_action_claim_bpaigow01(p_character uuid,p_request uuid,p_action text,p_payload jsonb)
returns boolean language plpgsql security definer set search_path=public,pg_temp as $$
declare v_rows integer;
begin
  if p_request is null then raise exception 'PAIGOW_REQUEST_ID_REQUIRED';end if;
  insert into public.paigow_action_requests_bpaigow01(character_id,request_id,action_code,request_payload)
  values(p_character,p_request,p_action,coalesce(p_payload,'{}'::jsonb)) on conflict(character_id,request_id) do nothing;
  get diagnostics v_rows=row_count;
  if v_rows=0 and not exists(select 1 from public.paigow_action_requests_bpaigow01 where character_id=p_character and request_id=p_request and action_code=p_action) then
    raise exception 'PAIGOW_REQUEST_ID_REUSED';
  end if;
  return v_rows=1;
end $$;

create or replace function public.paigow_action_finish_bpaigow01(p_character uuid,p_request uuid,p_action text,p_response jsonb)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
begin
  update public.paigow_action_requests_bpaigow01 set response_payload=p_response where character_id=p_character and request_id=p_request and action_code=p_action;
  return p_response;
end $$;

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

  select *
    into v_room
    from public.paigow_rooms_bpaigow01
   where id=p_room_id
   for update;

  if v_room.id is null or v_room.status<>'waiting' then
    raise exception 'PAIGOW_ROOM_NOT_WAITING';
  end if;
  if v_room.owner_character_id<>v_character then
    raise exception 'PAIGOW_ONLY_OWNER_STARTS';
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

commit;

begin;

create or replace function public.paigow_cancel_round_internal_bpaigow01(p_round_id uuid,p_reason text)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_round public.paigow_rounds_bpaigow01%rowtype;v_room public.paigow_rooms_bpaigow01%rowtype;rp record;
begin
  select * into v_round from public.paigow_rounds_bpaigow01 where id=p_round_id for update;
  if v_round.id is null or v_round.phase in('settled','cancelled') then return;end if;
  select * into v_room from public.paigow_rooms_bpaigow01 where id=v_round.room_id for update;
  for rp in select * from public.paigow_round_players_bpaigow01 where round_id=p_round_id for update loop
    if rp.stake_amount+rp.fee_amount>0 then
      perform public.casino_credit_result_v0141(rp.character_id,v_room.stake_type,rp.stake_amount+rp.fee_amount);
    end if;
    if rp.fee_amount>0 then
      perform public.casino_bankroll_apply_v1(v_room.stake_type,-rp.fee_amount,'paigow_fee_refund_bpaigow01',p_round_id,
        jsonb_build_object('room_id',v_room.id,'character_id',rp.character_id,'reason',p_reason));
    end if;
    if v_room.duel_type='laohe' and rp.bankroll_reserve>0 then
      perform public.casino_bankroll_apply_v1(v_room.stake_type,rp.bankroll_reserve,'paigow_laohe_reserve_release_bpaigow01',p_round_id,
        jsonb_build_object('room_id',v_room.id,'character_id',rp.character_id,'reason',p_reason));
    elsif v_room.duel_type='pvp' and v_room.pvp_mode='rob' and rp.character_id=v_round.dealer_character_id and rp.bankroll_reserve>0 then
      perform public.casino_credit_result_v0141(rp.character_id,v_room.stake_type,rp.bankroll_reserve);
    end if;
    update public.paigow_round_players_bpaigow01 set payout_amount=stake_amount+fee_amount,
      net_amount=0,result_payload=jsonb_build_object('cancelled',true,'reason',p_reason) where round_id=p_round_id and character_id=rp.character_id;
  end loop;
  update public.paigow_rooms_bpaigow01 set fee_carry_bps=v_round.fee_carry_start where id=v_room.id;
  update public.paigow_rounds_bpaigow01 set phase='cancelled',settled_at=clock_timestamp(),phase_deadline=null,
    result_payload=jsonb_build_object('cancelled',true,'reason',p_reason) where id=p_round_id;
  update public.paigow_rooms_bpaigow01 set status='waiting',updated_at=now() where id=v_room.id and status<>'disabled';
  update public.paigow_room_members_bpaigow01 set ready=false where room_id=v_room.id and left_at is null;
end $$;

create or replace function public.paigow_choose_dealer_internal_bpaigow01(p_round_id uuid)
returns uuid language plpgsql security definer set search_path=public,pg_temp as $$
declare v_round public.paigow_rounds_bpaigow01%rowtype;v_room public.paigow_rooms_bpaigow01%rowtype;v_candidates uuid[];v_dealer uuid;v_seconds integer;
begin
  select * into v_round from public.paigow_rounds_bpaigow01 where id=p_round_id for update;
  select * into v_room from public.paigow_rooms_bpaigow01 where id=v_round.room_id;
  if v_round.phase<>'rob' then return v_round.dealer_character_id;end if;
  select array_agg(character_id order by seat_no) into v_candidates from public.paigow_round_players_bpaigow01 where round_id=p_round_id and active_in_round and rob_choice is true;
  if coalesce(array_length(v_candidates,1),0)=0 then
    select array_agg(character_id order by seat_no) into v_candidates from public.paigow_round_players_bpaigow01 where round_id=p_round_id and active_in_round;
  end if;
  if coalesce(array_length(v_candidates,1),0)<1 then perform public.paigow_cancel_round_internal_bpaigow01(p_round_id,'not_enough_players_after_rob');return null;end if;
  v_dealer:=v_candidates[public.casino_secure_random_int_v1(array_length(v_candidates,1))+1];
  select case when v_room.game_mode='small' then small_multiplier_seconds else big_multiplier_seconds end into v_seconds from public.paigow_settings_bpaigow01 where singleton_id=1;
  update public.paigow_rounds_bpaigow01 set dealer_character_id=v_dealer,phase='multiplier',phase_deadline=clock_timestamp()+make_interval(secs=>v_seconds) where id=p_round_id;
  update public.paigow_round_players_bpaigow01 set action_confirmed=(character_id=v_dealer),multiplier=null where round_id=p_round_id;
  return v_dealer;
end $$;

create or replace function public.paigow_apply_multiplier_internal_bpaigow01(p_round_id uuid,p_character_id uuid,p_multiplier integer,p_auto boolean default false)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_round public.paigow_rounds_bpaigow01%rowtype;v_room public.paigow_rooms_bpaigow01%rowtype;v_player public.paigow_round_players_bpaigow01%rowtype;
  v_dealer public.paigow_round_players_bpaigow01%rowtype;v_available bigint;v_stake bigint;v_fee bigint:=0;v_total bigint;v_cap bigint;
  v_num numeric;v_carry integer;v_settings public.paigow_settings_bpaigow01%rowtype;
begin
  if p_multiplier not in(10,50,100) then raise exception 'PAIGOW_MULTIPLIER_INVALID';end if;
  select * into v_round from public.paigow_rounds_bpaigow01 where id=p_round_id for update;
  select * into v_room from public.paigow_rooms_bpaigow01 where id=v_round.room_id for update;
  select * into v_settings from public.paigow_settings_bpaigow01 where singleton_id=1;
  select * into v_player from public.paigow_round_players_bpaigow01 where round_id=p_round_id and character_id=p_character_id for update;
  if v_player.character_id is null or not v_player.active_in_round then raise exception 'PAIGOW_PLAYER_NOT_ACTIVE';end if;
  if v_player.action_confirmed then return;end if;
  if v_room.duel_type='pvp' and v_room.pvp_mode='rob' and p_character_id=v_round.dealer_character_id then
    update public.paigow_round_players_bpaigow01 set action_confirmed=true where round_id=p_round_id and character_id=p_character_id;return;
  end if;
  if v_room.base_stake>9223372036854775807/p_multiplier then raise exception 'PAIGOW_STAKE_OVERFLOW';end if;
  v_stake:=v_room.base_stake*p_multiplier;
  if v_room.duel_type='pvp' then
    v_num:=v_stake::numeric*v_settings.player_fee_bps+v_room.fee_carry_bps;
    v_fee:=floor(v_num/10000)::bigint;v_carry:=mod(v_num,10000)::integer;
  else v_fee:=0;v_carry:=v_room.fee_carry_bps;end if;
  v_total:=v_stake+v_fee;v_available:=public.casino_available_v1(p_character_id,v_room.stake_type);v_cap:=floor(v_available::numeric*0.30)::bigint;
  if v_total>v_cap or v_available<v_total then
    if p_auto then update public.paigow_round_players_bpaigow01 set active_in_round=false,fold_reason='insufficient_balance',action_confirmed=true where round_id=p_round_id and character_id=p_character_id;return;
    else raise exception 'PAIGOW_STAKE_EXCEEDS_THIRTY_PERCENT_OR_BALANCE';end if;
  end if;
  begin
    if v_room.duel_type='pvp' and v_room.pvp_mode='rob' then
      select * into v_dealer from public.paigow_round_players_bpaigow01 where round_id=p_round_id and character_id=v_round.dealer_character_id for update;
      if v_dealer.character_id is null then raise exception 'PAIGOW_DEALER_MISSING';end if;
      if v_dealer.resource_before=0 then
        v_dealer.resource_before:=public.casino_available_v1(v_dealer.character_id,v_room.stake_type);
        v_dealer.stake_cap:=floor(v_dealer.resource_before::numeric*0.30)::bigint;
        update public.paigow_round_players_bpaigow01 set resource_before=v_dealer.resource_before,stake_cap=v_dealer.stake_cap where round_id=p_round_id and character_id=v_dealer.character_id;
      end if;
      if v_dealer.bankroll_reserve+v_stake>v_dealer.stake_cap then
        if p_auto then update public.paigow_round_players_bpaigow01 set active_in_round=false,fold_reason='dealer_liability_limit',action_confirmed=true where round_id=p_round_id and character_id=p_character_id;return;
        else raise exception 'PAIGOW_DEALER_LIABILITY_LIMIT';end if;
      end if;
      perform public.casino_debit_v1(p_character_id,v_room.stake_type,v_total,'duel','paigow_rob_bpaigow01');
      perform public.casino_debit_v1(v_dealer.character_id,v_room.stake_type,v_stake,'duel','paigow_dealer_reserve_bpaigow01');
      update public.paigow_round_players_bpaigow01 set bankroll_reserve=bankroll_reserve+v_stake where round_id=p_round_id and character_id=v_dealer.character_id;
    elsif v_room.duel_type='pvp' then
      perform public.casino_debit_v1(p_character_id,v_room.stake_type,v_total,'duel','paigow_boat_bpaigow01');
    else
      perform public.casino_debit_v1(p_character_id,v_room.stake_type,v_stake,'duel','paigow_laohe_bpaigow01');
      perform public.casino_bankroll_apply_v1(v_room.stake_type,-v_stake,'paigow_laohe_reserve_bpaigow01',p_round_id,
        jsonb_build_object('room_id',v_room.id,'character_id',p_character_id,'stake',v_stake));
    end if;
  exception when others then
    if p_auto then
      update public.paigow_round_players_bpaigow01 set active_in_round=false,fold_reason='automatic_bet_failed',action_confirmed=true where round_id=p_round_id and character_id=p_character_id;return;
    end if;
    raise;
  end;
  if v_fee>0 then
    perform public.casino_bankroll_apply_v1(v_room.stake_type,v_fee,'paigow_player_fee_bpaigow01',p_round_id,
      jsonb_build_object('room_id',v_room.id,'character_id',p_character_id,'fee_bps',v_settings.player_fee_bps,'stake',v_stake));
  end if;
  update public.paigow_rooms_bpaigow01 set fee_carry_bps=v_carry,updated_at=now() where id=v_room.id;
  update public.paigow_round_players_bpaigow01 set multiplier=p_multiplier,stake_amount=v_stake,fee_amount=v_fee,bankroll_reserve=case when v_room.duel_type='laohe' then v_stake else bankroll_reserve end,
    resource_before=v_available,stake_cap=v_cap,action_confirmed=true where round_id=p_round_id and character_id=p_character_id;
end $$;

create or replace function public.paigow_after_multiplier_internal_bpaigow01(p_round_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_round public.paigow_rounds_bpaigow01%rowtype;v_room public.paigow_rooms_bpaigow01%rowtype;v_active integer;v_pending integer;v_seconds integer;
begin
  select * into v_round from public.paigow_rounds_bpaigow01 where id=p_round_id for update;select * into v_room from public.paigow_rooms_bpaigow01 where id=v_round.room_id;
  select count(*) into v_pending from public.paigow_round_players_bpaigow01 where round_id=p_round_id and active_in_round and not action_confirmed
    and not(v_room.duel_type='pvp' and v_room.pvp_mode='rob' and character_id=v_round.dealer_character_id);
  if v_pending>0 then return;end if;
  select count(*) into v_active from public.paigow_round_players_bpaigow01 where round_id=p_round_id and active_in_round;
  if v_active < (case when v_room.duel_type='laohe' then 1 else 2 end) then perform public.paigow_cancel_round_internal_bpaigow01(p_round_id,'not_enough_funded_players');return;end if;
  if v_room.game_mode='small' then perform public.paigow_settle_round_internal_bpaigow01(p_round_id);return;end if;
  select arrange_seconds into v_seconds from public.paigow_settings_bpaigow01 where singleton_id=1;
  update public.paigow_rounds_bpaigow01 set phase='arrange',phase_deadline=clock_timestamp()+make_interval(secs=>v_seconds) where id=p_round_id;
  update public.paigow_round_players_bpaigow01 set action_confirmed=false where round_id=p_round_id and active_in_round;
end $$;

create or replace function public.choose_paigow_rob_bpaigow01(p_room_id uuid,p_rob boolean,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_character uuid:=public.casino_current_character_id_v1();v_existing jsonb;v_round public.paigow_rounds_bpaigow01%rowtype;v_pending integer;
begin
  perform public.paigow_assert_enabled_bpaigow01();v_existing:=public.paigow_action_existing_bpaigow01(v_character,p_request_id,'rob');if v_existing is not null then return v_existing;end if;
  if not public.paigow_action_claim_bpaigow01(v_character,p_request_id,'rob',jsonb_build_object('room_id',p_room_id,'rob',p_rob)) then raise exception 'PAIGOW_REQUEST_IN_PROGRESS';end if;
  select * into v_round from public.paigow_rounds_bpaigow01 where room_id=p_room_id and phase='rob' order by round_no desc limit 1 for update;
  if v_round.id is null then raise exception 'PAIGOW_NOT_IN_ROB_PHASE';end if;
  update public.paigow_round_players_bpaigow01 set rob_choice=coalesce(p_rob,false) where round_id=v_round.id and character_id=v_character and active_in_round;
  if not found then raise exception 'PAIGOW_PLAYER_NOT_ACTIVE';end if;
  select count(*) into v_pending from public.paigow_round_players_bpaigow01 where round_id=v_round.id and active_in_round and rob_choice is null;
  if v_pending=0 then perform public.paigow_choose_dealer_internal_bpaigow01(v_round.id);end if;
  return public.paigow_action_finish_bpaigow01(v_character,p_request_id,'rob',public.get_paigow_room_state_bpaigow01(p_room_id));
end $$;

create or replace function public.choose_paigow_multiplier_bpaigow01(p_room_id uuid,p_multiplier integer,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_character uuid:=public.casino_current_character_id_v1();v_existing jsonb;v_round public.paigow_rounds_bpaigow01%rowtype;
begin
  perform public.paigow_assert_enabled_bpaigow01();v_existing:=public.paigow_action_existing_bpaigow01(v_character,p_request_id,'multiplier');if v_existing is not null then return v_existing;end if;
  if not public.paigow_action_claim_bpaigow01(v_character,p_request_id,'multiplier',jsonb_build_object('room_id',p_room_id,'multiplier',p_multiplier)) then raise exception 'PAIGOW_REQUEST_IN_PROGRESS';end if;
  select * into v_round from public.paigow_rounds_bpaigow01 where room_id=p_room_id and phase='multiplier' order by round_no desc limit 1 for update;
  if v_round.id is null then raise exception 'PAIGOW_NOT_IN_MULTIPLIER_PHASE';end if;
  perform public.paigow_apply_multiplier_internal_bpaigow01(v_round.id,v_character,p_multiplier,false);perform public.paigow_after_multiplier_internal_bpaigow01(v_round.id);
  return public.paigow_action_finish_bpaigow01(v_character,p_request_id,'multiplier',public.get_paigow_room_state_bpaigow01(p_room_id));
end $$;

create or replace function public.paigow_begin_head_reveal_internal_bpaigow01(p_round_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare rp record;v_cards text[];v_seconds integer;
begin
  for rp in select * from public.paigow_round_players_bpaigow01 where round_id=p_round_id and active_in_round and head_indices is null for update loop
    v_cards:=public.paigow_jsonb_codes_bpaigow01(rp.cards);
    update public.paigow_round_players_bpaigow01 set head_indices=public.paigow_recommended_split_bpaigow01(v_cards),action_confirmed=true where round_id=p_round_id and character_id=rp.character_id;
  end loop;
  select head_reveal_seconds into v_seconds from public.paigow_settings_bpaigow01 where singleton_id=1;
  update public.paigow_rounds_bpaigow01 set phase='head_reveal',phase_deadline=clock_timestamp()+make_interval(secs=>v_seconds) where id=p_round_id;
end $$;

create or replace function public.arrange_paigow_big_bpaigow01(p_room_id uuid,p_head_indices smallint[],p_request_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_character uuid:=public.casino_current_character_id_v1();v_existing jsonb;v_round public.paigow_rounds_bpaigow01%rowtype;v_cards text[];v_split jsonb;v_pending integer;
begin
  perform public.paigow_assert_enabled_bpaigow01();v_existing:=public.paigow_action_existing_bpaigow01(v_character,p_request_id,'arrange');if v_existing is not null then return v_existing;end if;
  if not public.paigow_action_claim_bpaigow01(v_character,p_request_id,'arrange',jsonb_build_object('room_id',p_room_id,'head_indices',to_jsonb(p_head_indices))) then raise exception 'PAIGOW_REQUEST_IN_PROGRESS';end if;
  select * into v_round from public.paigow_rounds_bpaigow01 where room_id=p_room_id and phase='arrange' order by round_no desc limit 1 for update;
  if v_round.id is null then raise exception 'PAIGOW_NOT_IN_ARRANGE_PHASE';end if;
  select public.paigow_jsonb_codes_bpaigow01(cards) into v_cards from public.paigow_round_players_bpaigow01 where round_id=v_round.id and character_id=v_character and active_in_round for update;
  if v_cards is null then raise exception 'PAIGOW_PLAYER_NOT_ACTIVE';end if;
  v_split:=public.paigow_split_value_bpaigow01(v_cards,p_head_indices);if not coalesce((v_split->>'valid')::boolean,false) then raise exception 'PAIGOW_HEAD_MUST_NOT_EXCEED_TAIL';end if;
  update public.paigow_round_players_bpaigow01 set head_indices=p_head_indices,action_confirmed=true where round_id=v_round.id and character_id=v_character;
  select count(*) into v_pending from public.paigow_round_players_bpaigow01 where round_id=v_round.id and active_in_round and not action_confirmed;
  if v_pending=0 then perform public.paigow_begin_head_reveal_internal_bpaigow01(v_round.id);end if;
  return public.paigow_action_finish_bpaigow01(v_character,p_request_id,'arrange',public.get_paigow_room_state_bpaigow01(p_room_id));
end $$;

create or replace function public.advance_paigow_round_bpaigow01(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_round public.paigow_rounds_bpaigow01%rowtype;rp record;v_pending integer;v_seconds integer;
begin
  perform public.paigow_assert_enabled_bpaigow01();
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

commit;

begin;

create or replace function public.paigow_allocate_boat_pool_bpaigow01(p_round_id uuid,p_score_key text,p_pool bigint,p_half boolean)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare v_remaining bigint:=greatest(0,coalesce(p_pool,0));v_score bigint;v_demand bigint;v_base bigint;v_alloc bigint;v_left bigint;v_unit bigint;rp record;
begin
  for v_score in select distinct (result_payload->>p_score_key)::bigint from public.paigow_round_players_bpaigow01
    where round_id=p_round_id and active_in_round order by 1 desc
  loop
    select coalesce(sum((case when p_half then stake_amount/2 else stake_amount end)*2),0),
           coalesce(sum(case when p_half then stake_amount/2 else stake_amount end),0)
    into v_demand,v_base from public.paigow_round_players_bpaigow01
    where round_id=p_round_id and active_in_round and (result_payload->>p_score_key)::bigint=v_score;
    if v_remaining<=0 or v_base<=0 then continue;end if;
    if v_remaining>=v_demand then
      update public.paigow_round_players_bpaigow01 set payout_amount=payout_amount+(case when p_half then stake_amount else stake_amount*2 end)
      where round_id=p_round_id and active_in_round and (result_payload->>p_score_key)::bigint=v_score;
      v_remaining:=v_remaining-v_demand;
    else
      update public.paigow_round_players_bpaigow01 set payout_amount=payout_amount+floor(v_remaining::numeric*(case when p_half then stake_amount/2 else stake_amount end)/v_base)::bigint
      where round_id=p_round_id and active_in_round and (result_payload->>p_score_key)::bigint=v_score;
      select coalesce(sum(floor(v_remaining::numeric*(case when p_half then stake_amount/2 else stake_amount end)/v_base)::bigint),0)
      into v_alloc from public.paigow_round_players_bpaigow01
      where round_id=p_round_id and active_in_round and (result_payload->>p_score_key)::bigint=v_score;
      v_left:=v_remaining-v_alloc;
      for rp in select character_id from public.paigow_round_players_bpaigow01
        where round_id=p_round_id and active_in_round and (result_payload->>p_score_key)::bigint=v_score order by seat_no
      loop
        exit when v_left<=0;
        update public.paigow_round_players_bpaigow01 set payout_amount=payout_amount+1 where round_id=p_round_id and character_id=rp.character_id;
        v_left:=v_left-1;
      end loop;
      v_remaining:=0;
    end if;
  end loop;
end $$;

create or replace function public.paigow_settle_round_internal_bpaigow01(p_round_id uuid)
returns void language plpgsql security definer set search_path=public,pg_temp as $$
declare
  v_round public.paigow_rounds_bpaigow01%rowtype;v_room public.paigow_rooms_bpaigow01%rowtype;v_secret public.paigow_round_secrets_bpaigow01%rowtype;
  rp record;v_cards text[];v_value jsonb;v_split jsonb;v_result integer;v_requested bigint;v_credit jsonb;v_granted bigint;v_bank_adjust bigint;
  v_dealer public.paigow_round_players_bpaigow01%rowtype;v_dealer_cards text[];v_dealer_head smallint[];v_dealer_credit bigint:=0;v_total_pool bigint;
  v_summary jsonb;v_bank bigint;v_player_count integer;
begin
  select * into v_round from public.paigow_rounds_bpaigow01 where id=p_round_id for update;
  if v_round.id is null or v_round.phase in('settled','cancelled') then return;end if;
  select * into v_room from public.paigow_rooms_bpaigow01 where id=v_round.room_id for update;
  select * into v_secret from public.paigow_round_secrets_bpaigow01 where round_id=p_round_id;
  select count(*) into v_player_count from public.paigow_round_players_bpaigow01 where round_id=p_round_id and active_in_round;
  if v_player_count < (case when v_room.duel_type='laohe' then 1 else 2 end) then perform public.paigow_cancel_round_internal_bpaigow01(p_round_id,'not_enough_players_at_settlement');return;end if;

  update public.paigow_round_players_bpaigow01 set payout_amount=0,net_amount=0 where round_id=p_round_id;
  for rp in select * from public.paigow_round_players_bpaigow01 where round_id=p_round_id and active_in_round order by seat_no for update loop
    v_cards:=public.paigow_jsonb_codes_bpaigow01(rp.cards);
    if v_room.game_mode='small' then
      v_value:=public.paigow_pair_value_bpaigow01(v_cards);
      update public.paigow_round_players_bpaigow01 set result_payload=jsonb_build_object('hand',v_value,'score',(v_value->>'score')::bigint,'score_main',(v_value->>'score')::bigint)
      where round_id=p_round_id and character_id=rp.character_id;
    else
      if rp.head_indices is null then rp.head_indices:=public.paigow_recommended_split_bpaigow01(v_cards);update public.paigow_round_players_bpaigow01 set head_indices=rp.head_indices where round_id=p_round_id and character_id=rp.character_id;end if;
      v_split:=public.paigow_split_value_bpaigow01(v_cards,rp.head_indices);
      update public.paigow_round_players_bpaigow01 set result_payload=jsonb_build_object('split',v_split,'head_score',(v_split->'head'->>'score')::bigint,'tail_score',(v_split->'tail'->>'score')::bigint)
      where round_id=p_round_id and character_id=rp.character_id;
    end if;
  end loop;

  if v_room.duel_type='laohe' then
    v_dealer_cards:=v_secret.laohe_cards;v_dealer_head:=v_secret.laohe_head_indices;
    for rp in select * from public.paigow_round_players_bpaigow01 where round_id=p_round_id and active_in_round order by seat_no for update loop
      v_cards:=public.paigow_jsonb_codes_bpaigow01(rp.cards);
      v_result:=public.paigow_round_compare_bpaigow01(v_room.game_mode,v_cards,rp.head_indices,v_dealer_cards,v_dealer_head);
      v_requested:=case v_result when 1 then rp.stake_amount*2 when 0 then rp.stake_amount else 0 end;
      if v_requested>0 then v_credit:=public.casino_credit_result_v0141(rp.character_id,v_room.stake_type,v_requested);v_granted:=coalesce((v_credit->>'granted_amount')::bigint,0);else v_granted:=0;v_credit:='{}'::jsonb;end if;
      v_bank_adjust:=rp.stake_amount*2-v_granted;
      if v_bank_adjust<>0 then perform public.casino_bankroll_apply_v1(v_room.stake_type,v_bank_adjust,'paigow_laohe_settlement_bpaigow01',p_round_id,
        jsonb_build_object('room_id',v_room.id,'character_id',rp.character_id,'result',v_result,'stake',rp.stake_amount,'granted',v_granted));end if;
      update public.paigow_round_players_bpaigow01 set payout_amount=v_granted,net_amount=v_granted-stake_amount-fee_amount,
        result_payload=result_payload||jsonb_build_object('versus','laohe','compare_result',v_result,'requested_payout',v_requested,'credit',v_credit)
      where round_id=p_round_id and character_id=rp.character_id;
      perform public.casino_add_ticket_v1(rp.character_id,v_room.stake_type);
    end loop;
  elsif v_room.pvp_mode='rob' then
    select * into v_dealer from public.paigow_round_players_bpaigow01 where round_id=p_round_id and character_id=v_round.dealer_character_id for update;
    if v_dealer.character_id is null or not v_dealer.active_in_round then perform public.paigow_cancel_round_internal_bpaigow01(p_round_id,'dealer_missing_at_settlement');return;end if;
    v_dealer_cards:=public.paigow_jsonb_codes_bpaigow01(v_dealer.cards);v_dealer_head:=v_dealer.head_indices;
    for rp in select * from public.paigow_round_players_bpaigow01 where round_id=p_round_id and active_in_round and character_id<>v_dealer.character_id order by seat_no for update loop
      v_cards:=public.paigow_jsonb_codes_bpaigow01(rp.cards);
      v_result:=public.paigow_round_compare_bpaigow01(v_room.game_mode,v_cards,rp.head_indices,v_dealer_cards,v_dealer_head);
      if v_result=1 then
        v_credit:=public.casino_credit_result_v0141(rp.character_id,v_room.stake_type,rp.stake_amount*2);v_granted:=coalesce((v_credit->>'granted_amount')::bigint,0);
      elsif v_result=0 then
        v_credit:=public.casino_credit_result_v0141(rp.character_id,v_room.stake_type,rp.stake_amount);v_granted:=coalesce((v_credit->>'granted_amount')::bigint,0);
        v_credit:=public.casino_credit_result_v0141(v_dealer.character_id,v_room.stake_type,rp.stake_amount);v_dealer_credit:=v_dealer_credit+coalesce((v_credit->>'granted_amount')::bigint,0);
      else
        v_granted:=0;v_credit:=public.casino_credit_result_v0141(v_dealer.character_id,v_room.stake_type,rp.stake_amount*2);v_dealer_credit:=v_dealer_credit+coalesce((v_credit->>'granted_amount')::bigint,0);
      end if;
      update public.paigow_round_players_bpaigow01 set payout_amount=v_granted,net_amount=v_granted-stake_amount-fee_amount,
        result_payload=result_payload||jsonb_build_object('versus','player_dealer','compare_result',v_result,'dealer_character_id',v_dealer.character_id)
      where round_id=p_round_id and character_id=rp.character_id;
      perform public.casino_add_ticket_v1(rp.character_id,v_room.stake_type);
    end loop;
    update public.paigow_round_players_bpaigow01 set payout_amount=v_dealer_credit,net_amount=v_dealer_credit-bankroll_reserve,
      result_payload=result_payload||jsonb_build_object('dealer',true,'reserve',bankroll_reserve,'credited',v_dealer_credit)
    where round_id=p_round_id and character_id=v_dealer.character_id;
    perform public.casino_add_ticket_v1(v_dealer.character_id,v_room.stake_type);
  else
    select coalesce(sum(stake_amount),0) into v_total_pool from public.paigow_round_players_bpaigow01 where round_id=p_round_id and active_in_round;
    if v_room.game_mode='small' then
      perform public.paigow_allocate_boat_pool_bpaigow01(p_round_id,'score_main',v_total_pool,false);
    else
      perform public.paigow_allocate_boat_pool_bpaigow01(p_round_id,'head_score',floor(v_total_pool::numeric/2)::bigint,true);
      perform public.paigow_allocate_boat_pool_bpaigow01(p_round_id,'tail_score',v_total_pool-floor(v_total_pool::numeric/2)::bigint,true);
    end if;
    for rp in select * from public.paigow_round_players_bpaigow01 where round_id=p_round_id and active_in_round order by seat_no for update loop
      if rp.payout_amount>0 then v_credit:=public.casino_credit_result_v0141(rp.character_id,v_room.stake_type,rp.payout_amount);v_granted:=coalesce((v_credit->>'granted_amount')::bigint,0);else v_granted:=0;v_credit:='{}'::jsonb;end if;
      update public.paigow_round_players_bpaigow01 set payout_amount=v_granted,net_amount=v_granted-stake_amount-fee_amount,
        result_payload=result_payload||jsonb_build_object('versus','boat_pool','nominal_payout',rp.payout_amount,'credit',v_credit)
      where round_id=p_round_id and character_id=rp.character_id;
      perform public.casino_add_ticket_v1(rp.character_id,v_room.stake_type);
    end loop;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('character_id',x.character_id,'seat_no',x.seat_no,'active',x.active_in_round,'stake',x.stake_amount,'fee',x.fee_amount,
    'payout',x.payout_amount,'net',x.net_amount,'result',x.result_payload) order by x.seat_no),'[]'::jsonb)
  into v_summary from public.paigow_round_players_bpaigow01 x where x.round_id=p_round_id;
  select balance into v_bank from public.casino_bankroll_v1 where stake_type=v_room.stake_type;
  update public.paigow_rounds_bpaigow01 set phase='settled',settled_at=clock_timestamp(),phase_deadline=null,
    result_payload=jsonb_build_object('duel_type',v_room.duel_type,'pvp_mode',v_room.pvp_mode,'game_mode',v_room.game_mode,'stake_type',v_room.stake_type,
      'players',v_summary,'laohe_cards',case when v_room.duel_type='laohe' then public.paigow_tiles_json_bpaigow01(v_secret.laohe_cards) else '[]'::jsonb end,
      'laohe_head_indices',case when v_room.duel_type='laohe' then to_jsonb(v_secret.laohe_head_indices) else 'null'::jsonb end,'bankroll_balance_after',v_bank)
  where id=p_round_id;
  update public.paigow_rooms_bpaigow01 set status='waiting',updated_at=now() where id=v_room.id;
  update public.paigow_room_members_bpaigow01 set ready=false where room_id=v_room.id and left_at is null;
end $$;

create or replace function public.settle_paigow_round_bpaigow01(p_room_id uuid,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_character uuid:=public.casino_current_character_id_v1();v_existing jsonb;v_round public.paigow_rounds_bpaigow01%rowtype;
begin
  perform public.paigow_assert_enabled_bpaigow01();v_existing:=public.paigow_action_existing_bpaigow01(v_character,p_request_id,'settle');if v_existing is not null then return v_existing;end if;
  if not public.paigow_action_claim_bpaigow01(v_character,p_request_id,'settle',jsonb_build_object('room_id',p_room_id)) then raise exception 'PAIGOW_REQUEST_IN_PROGRESS';end if;
  select * into v_round from public.paigow_rounds_bpaigow01 where room_id=p_room_id order by round_no desc limit 1 for update;
  if v_round.id is null then raise exception 'PAIGOW_ROUND_NOT_FOUND';end if;
  if v_round.phase<>'tail_reveal' or v_round.phase_deadline>clock_timestamp() then raise exception 'PAIGOW_SETTLEMENT_NOT_READY';end if;
  perform public.paigow_settle_round_internal_bpaigow01(v_round.id);
  return public.paigow_action_finish_bpaigow01(v_character,p_request_id,'settle',public.get_paigow_room_state_bpaigow01(p_room_id));
end $$;

create or replace function public.leave_paigow_room_bpaigow01(p_room_id uuid)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare v_character uuid:=public.casino_current_character_id_v1();v_room public.paigow_rooms_bpaigow01%rowtype;v_role text;
begin
  select * into v_room from public.paigow_rooms_bpaigow01 where id=p_room_id for update;
  select role into v_role from public.paigow_room_members_bpaigow01 where room_id=p_room_id and character_id=v_character and left_at is null;
  if v_room.status='playing' and v_role='player' then raise exception 'PAIGOW_CANNOT_LEAVE_ACTIVE_ROUND';end if;
  update public.paigow_room_members_bpaigow01 set left_at=now(),ready=false where room_id=p_room_id and character_id=v_character and left_at is null;
  if v_room.owner_character_id=v_character and v_room.status='waiting' then
    update public.paigow_rooms_bpaigow01 set status='closed',closed_at=now(),updated_at=now() where id=p_room_id;
  end if;
  return jsonb_build_object('left',true,'room_id',p_room_id);
end $$;

revoke all on function public.paigow_assert_enabled_bpaigow01(),public.paigow_room_capacity_bpaigow01(text,text),
  public.paigow_jsonb_codes_bpaigow01(jsonb),public.paigow_tiles_json_bpaigow01(text[]),public.paigow_pair_value_bpaigow01(text[]),
  public.paigow_split_value_bpaigow01(text[],smallint[]),public.paigow_recommended_split_bpaigow01(text[]),public.paigow_shuffle_deck_bpaigow01(),
  public.paigow_round_compare_bpaigow01(text,text[],smallint[],text[],smallint[]),public.paigow_action_existing_bpaigow01(uuid,uuid,text),
  public.paigow_action_claim_bpaigow01(uuid,uuid,text,jsonb),public.paigow_action_finish_bpaigow01(uuid,uuid,text,jsonb),
  public.paigow_cancel_round_internal_bpaigow01(uuid,text),public.paigow_choose_dealer_internal_bpaigow01(uuid),
  public.paigow_apply_multiplier_internal_bpaigow01(uuid,uuid,integer,boolean),public.paigow_after_multiplier_internal_bpaigow01(uuid),
  public.paigow_begin_head_reveal_internal_bpaigow01(uuid),public.paigow_allocate_boat_pool_bpaigow01(uuid,text,bigint,boolean),
  public.paigow_settle_round_internal_bpaigow01(uuid) from public,anon,authenticated;

revoke all on function public.start_paigow_round_bpaigow01(uuid,uuid),public.choose_paigow_rob_bpaigow01(uuid,boolean,uuid),
  public.choose_paigow_multiplier_bpaigow01(uuid,integer,uuid),public.arrange_paigow_big_bpaigow01(uuid,smallint[],uuid),
  public.advance_paigow_round_bpaigow01(uuid),public.settle_paigow_round_bpaigow01(uuid,uuid) from public,anon,authenticated;
grant execute on function public.start_paigow_round_bpaigow01(uuid,uuid),public.choose_paigow_rob_bpaigow01(uuid,boolean,uuid),
  public.choose_paigow_multiplier_bpaigow01(uuid,integer,uuid),public.arrange_paigow_big_bpaigow01(uuid,smallint[],uuid),
  public.advance_paigow_round_bpaigow01(uuid),public.settle_paigow_round_bpaigow01(uuid,uuid) to authenticated;

comment on function public.start_paigow_round_bpaigow01(uuid,uuid) is 'V1.2 FIX1：服务端安全洗牌并启动九霄灵牌回合。';
comment on function public.advance_paigow_round_bpaigow01(uuid) is 'V1.2 FIX1：按数据库时间推进抢庄、倍率、头尾亮牌与结算。';
comment on function public.paigow_settle_round_internal_bpaigow01(uuid) is 'V1.2 FIX1：整桌单事务结算；老何使用现有赌场资金，玩家局系统零兜底。';
notify pgrst,'reload schema';
commit;

