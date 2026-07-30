-- 九霄问道 V1.2 FIX1 CACHE38
-- 78：九霄灵牌开始牌局记录变量修复
-- 修复错误：record "m" is not assigned yet
-- 原因：PL/pgSQL 的 record 变量 m 与 FOR 查询中的表别名 m 同名，
--       查询解析时优先读取尚未赋值的 record 变量，导致开始本局失败。

begin;

-- 前置检查：72号主迁移必须已经建立九霄灵牌基础对象。
do $$
begin
  if to_regclass('public.paigow_rooms_bpaigow01') is null
     or to_regclass('public.paigow_round_players_bpaigow01') is null
     or to_regprocedure('public.start_paigow_round_bpaigow01(uuid,uuid)') is null then
    raise exception 'PAIGOW_START_ROUND_RPC_MISSING_RUN_72_FIRST';
  end if;
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

revoke all on function public.start_paigow_round_bpaigow01(uuid,uuid)
  from public, anon, authenticated;

grant execute on function public.start_paigow_round_bpaigow01(uuid,uuid)
  to authenticated;

comment on function public.start_paigow_round_bpaigow01(uuid,uuid)
  is 'V1.2 FIX1 HOTFIX78：修复开始牌局时 record m 与查询表别名重名导致未赋值异常。';

notify pgrst, 'reload schema';

commit;

-- 执行后检查：三项都应为 true。
select
  to_regprocedure('public.start_paigow_round_bpaigow01(uuid,uuid)') is not null
    as start_round_rpc_ok,
  position(
    'v_member record' in
    pg_get_functiondef(
      'public.start_paigow_round_bpaigow01(uuid,uuid)'::regprocedure
    )
  ) > 0 as member_record_fix_ok,
  position(
    'from public.paigow_room_members_bpaigow01 rm' in
    pg_get_functiondef(
      'public.start_paigow_round_bpaigow01(uuid,uuid)'::regprocedure
    )
  ) > 0 as member_alias_fix_ok;
