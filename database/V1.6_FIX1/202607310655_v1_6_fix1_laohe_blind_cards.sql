-- 九霄问道 V1.6 FIX1 CACHE45
-- 94：老何庄盲牌规则。小牌九与大牌九选倍前，玩家和庄家均不获得自己的预发明牌。
begin;

do $$
begin
  if to_regprocedure('public.get_paigow_room_state_bpaigow01(uuid)') is null then raise exception 'V1_6_FIX1_REQUIRED:room_state_rpc'; end if;
  if to_regclass('public.paigow_round_secrets_bpaigow01') is null then raise exception 'V1_6_FIX1_REQUIRED:round_secrets'; end if;
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
        -- V1.6 FIX1：老何庄采用盲牌下注。小牌九下注前不显示任何牌；大牌九选倍前不显示两张预发牌，进入组牌阶段后才显示本人的四张牌。
        if v_room.duel_type='laohe' then
          if v_room.game_mode='small' then
            if v_phase='settled' then v_visible:=v_cards;else v_visible:='{}'::text[];end if;
          elsif v_room.game_mode='big' then
            if v_phase in('arrange','head_reveal','tail_reveal','settled') then v_visible:=v_cards;else v_visible:='{}'::text[];end if;
          end if;
        elsif v_room.game_mode='small' and v_phase not in('settled','cancelled') then v_visible:=v_cards[1:1];
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

comment on function public.get_paigow_room_state_bpaigow01(uuid) is 'V1.6 FIX1：纯读取房间快照；老何庄小/大牌九在选倍前均不返回玩家明牌，老何牌面只在公开阶段返回。';

revoke all on function public.get_paigow_room_state_bpaigow01(uuid) from public;
grant execute on function public.get_paigow_room_state_bpaigow01(uuid) to authenticated;
notify pgrst,'reload schema';
commit;
