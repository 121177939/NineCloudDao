-- 九霄问道 V1.2 FIX1 CACHE38
-- 77：九霄灵牌创建房间入座类型修复
-- 修复错误：function public.join_paigow_room_bpaigow01(uuid, integer, boolean) does not exist
-- 原因：创建房间函数把常量 1 按 integer 解析，但入座函数参数为 smallint。

begin;

-- 前置检查：72号主迁移必须已经成功建立入座函数。
do $$
begin
  if to_regprocedure('public.join_paigow_room_bpaigow01(uuid,smallint,boolean)') is null then
    raise exception 'PAIGOW_JOIN_RPC_MISSING_RUN_72_FIRST';
  end if;
end
$$;

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

revoke all on function public.create_paigow_room_bpaigow01(text,text,text,text,bigint)
  from public, anon, authenticated;

grant execute on function public.create_paigow_room_bpaigow01(text,text,text,text,bigint)
  to authenticated;

comment on function public.create_paigow_room_bpaigow01(text,text,text,text,bigint)
  is 'V1.2 FIX1 HOTFIX77：修复创建九霄灵牌房间时 integer 与 smallint 入座参数不匹配。';

notify pgrst, 'reload schema';

commit;

-- 执行后检查：两项都应为 true。
select
  to_regprocedure('public.create_paigow_room_bpaigow01(text,text,text,text,bigint)') is not null as create_room_rpc_ok,
  position(
    '1::smallint' in
    pg_get_functiondef('public.create_paigow_room_bpaigow01(text,text,text,text,bigint)'::regprocedure)
  ) > 0 as seat_cast_fix_ok;
