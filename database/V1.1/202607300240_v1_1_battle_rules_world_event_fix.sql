-- 九霄问道 V1.1：双向战力挑战、阶段修为转移、20次/20分钟与界闻修复
-- 关键规则：高低战力互相挑战；低胜高1%，其余0.5%；只扣当前小境界进度；不掉段；严格等量转移。
begin;

alter table public.battle_challenge_settings_bcombat01
  add column if not exists challenge_cooldown_minutes integer not null default 20 check(challenge_cooldown_minutes between 0 and 1440),
  add column if not exists higher_power_win_rate numeric(7,6) not null default 0.005 check(higher_power_win_rate>=0 and higher_power_win_rate<=0.10),
  add column if not exists lower_power_win_rate numeric(7,6) not null default 0.01 check(lower_power_win_rate>=0 and lower_power_win_rate<=0.10);

update public.battle_challenge_settings_bcombat01
set active_challenge_daily_limit=20,
    challenge_cooldown_minutes=20,
    protection_minutes=0,
    higher_power_win_rate=0.005,
    lower_power_win_rate=0.01,
    updated_at=clock_timestamp()
where singleton_id=1;

create or replace function public.get_battle_power_ranking_bcombat01(p_limit integer default 50,p_offset integer default 0)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare v_user_id uuid:=auth.uid();v_self_id uuid;v_self jsonb;v_self_power bigint:=0;v_total integer;v_entries jsonb;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED';end if;
  if p_limit is null or p_limit<1 or p_limit>100 or p_offset is null or p_offset<0 then raise exception 'INVALID_RANKING_PAGE';end if;
  select pc.id into v_self_id from public.player_characters pc
  where pc.user_id=v_user_id and pc.status in('active','secluded','missing') order by pc.created_at desc limit 1;
  if v_self_id is null then raise exception 'NO_ACTIVE_CHARACTER';end if;
  v_self:=public.bcombat01_character_snapshot(v_self_id);
  v_self_power:=coalesce((v_self->>'power')::bigint,0);
  with source as (
    select pc.id,pc.user_id,pc.created_at,public.bcombat01_character_snapshot(pc.id) snap
    from public.player_characters pc join public.character_combat_profiles_bcombat01 cp on cp.character_id=pc.id
    where pc.status in('active','secluded','missing')
  ),valid as (select * from source where snap is not null),
  ranked as (
    select row_number() over(order by (snap->>'power')::bigint desc,(snap->>'major_order')::int desc,
      (snap->>'minor_level')::int desc,(snap->>'cultivation')::bigint desc,created_at asc,id asc)::integer rank,
      id,user_id,snap from valid
  ),page as (select * from ranked where rank>p_offset and rank<=p_offset+p_limit order by rank)
  select count(*)::integer into v_total from ranked;
  with source as (
    select pc.id,pc.user_id,pc.created_at,public.bcombat01_character_snapshot(pc.id) snap
    from public.player_characters pc join public.character_combat_profiles_bcombat01 cp on cp.character_id=pc.id
    where pc.status in('active','secluded','missing')
  ),valid as (select * from source where snap is not null),
  ranked as (
    select row_number() over(order by (snap->>'power')::bigint desc,(snap->>'major_order')::int desc,
      (snap->>'minor_level')::int desc,(snap->>'cultivation')::bigint desc,created_at asc,id asc)::integer rank,
      id,user_id,snap from valid
  ),page as (select * from ranked where rank>p_offset and rank<=p_offset+p_limit order by rank)
  select coalesce(jsonb_agg(jsonb_build_object(
    'rank',rank,'character_id',id,'name',snap->>'name','realm',snap->>'realm',
    'fate',snap->>'fate_name','generation',(snap->>'generation')::integer,
    'element',snap->>'element','element_name',snap->>'element_name',
    'power',(snap->>'power')::bigint,'is_self',user_id=v_user_id,
    'can_challenge',id<>v_self_id
  ) order by rank),'[]'::jsonb) into v_entries from page;
  return jsonb_build_object('status','ok','board_type','battle',
    'ranking_rule','高低战力可互相挑战；低战力胜高战力转移阶段进度1%，高战力胜低战力转移0.5%',
    'entries',v_entries,'total_count',v_total,'offset',p_offset,'limit',p_limit,
    'has_more',p_offset+jsonb_array_length(v_entries)<v_total,'self_power',v_self_power,'self',v_self);
end$$;
revoke all on function public.get_battle_power_ranking_bcombat01(integer,integer) from public,anon,authenticated;
grant execute on function public.get_battle_power_ranking_bcombat01(integer,integer) to authenticated;

create or replace function public.get_battle_challenge_preview_bcombat01(p_target_character_id uuid)
returns jsonb language plpgsql stable security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare
  v_user_id uuid:=auth.uid();v_self_id uuid;v_self jsonb;v_target jsonb;
  v_settings public.battle_challenge_settings_bcombat01%rowtype;v_day date;
  v_active_count integer;v_last_completed timestamptz;v_cooldown_until timestamptz;
  v_self_floor bigint;v_target_floor bigint;v_self_progress bigint;v_target_progress bigint;
  v_self_win_rate numeric;v_target_win_rate numeric;v_self_loss bigint;v_target_loss bigint;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED';end if;
  select * into v_settings from public.battle_challenge_settings_bcombat01 where singleton_id=1;
  if not coalesce(v_settings.enabled,false) then raise exception 'BATTLE_CHALLENGE_DISABLED';end if;
  select pc.id into v_self_id from public.player_characters pc where pc.user_id=v_user_id
    and pc.status in('active','secluded','missing') order by pc.created_at desc limit 1;
  if v_self_id is null then raise exception 'NO_ACTIVE_CHARACTER';end if;
  if p_target_character_id is null or p_target_character_id=v_self_id then raise exception 'INVALID_CHALLENGE_TARGET';end if;
  v_self:=public.bcombat01_character_snapshot(v_self_id);v_target:=public.bcombat01_character_snapshot(p_target_character_id);
  if v_target is null then raise exception 'CHALLENGE_TARGET_NOT_FOUND';end if;
  if v_self->>'world_id'<>v_target->>'world_id' then raise exception 'CHALLENGE_WORLD_MISMATCH';end if;
  select coalesce(rs.cultivation_required,0),greatest(0,pc.cultivation-coalesce(rs.cultivation_required,0))
    into v_self_floor,v_self_progress
    from public.player_characters pc join public.realm_stages rs on rs.id=pc.realm_stage_id where pc.id=v_self_id;
  select coalesce(rs.cultivation_required,0),greatest(0,pc.cultivation-coalesce(rs.cultivation_required,0))
    into v_target_floor,v_target_progress
    from public.player_characters pc join public.realm_stages rs on rs.id=pc.realm_stage_id where pc.id=p_target_character_id;
  v_self_win_rate:=case when (v_self->>'power')::bigint<(v_target->>'power')::bigint then v_settings.lower_power_win_rate else v_settings.higher_power_win_rate end;
  v_target_win_rate:=case when (v_target->>'power')::bigint<(v_self->>'power')::bigint then v_settings.lower_power_win_rate else v_settings.higher_power_win_rate end;
  v_target_loss:=least(v_target_progress,greatest(0,floor(v_target_progress::numeric*v_self_win_rate)::bigint));
  v_self_loss:=least(v_self_progress,greatest(0,floor(v_self_progress::numeric*v_target_win_rate)::bigint));
  v_day:=(clock_timestamp() at time zone v_settings.day_timezone)::date;
  select count(*)::integer,max(completed_at) into v_active_count,v_last_completed
    from public.battle_challenges_bcombat01
    where challenger_character_id=v_self_id and day_key=v_day and status='settled';
  if v_last_completed is not null then v_cooldown_until:=v_last_completed+make_interval(mins=>v_settings.challenge_cooldown_minutes);end if;
  return jsonb_build_object(
    'status','ok','challenger',v_self,'target',v_target,
    'challenger_stage_floor',v_self_floor,'target_stage_floor',v_target_floor,
    'challenger_stage_progress',v_self_progress,'target_stage_progress',v_target_progress,
    'challenger_potential_loss',v_self_loss,'target_potential_loss',v_target_loss,
    'challenger_win_rate',v_self_win_rate,'target_win_rate',v_target_win_rate,
    'active_challenges_used',v_active_count,'active_challenges_limit',v_settings.active_challenge_daily_limit,
    'challenge_cooldown_minutes',v_settings.challenge_cooldown_minutes,'cooldown_until',v_cooldown_until,
    'can_start',v_active_count<v_settings.active_challenge_daily_limit and (v_cooldown_until is null or v_cooldown_until<=clock_timestamp()),
    'blocked_reason',case
      when v_active_count>=v_settings.active_challenge_daily_limit then '今日主动挑战20次已经用尽'
      when v_cooldown_until is not null and v_cooldown_until>clock_timestamp() then '每次挑战后需等待20分钟'
      else null end,
    'transfer_note','只转移败者当前小境界起点以上的进度；低战力胜高战力为1%，其余为0.5%；向下取整且不掉段。',
    'escrow_note','胜者触及当前境界修为上限时，超出部分进入战利修为暂存；败者实际扣除量与胜者获得总量严格相等。'
  );
end$$;
revoke all on function public.get_battle_challenge_preview_bcombat01(uuid) from public,anon,authenticated;
grant execute on function public.get_battle_challenge_preview_bcombat01(uuid) to authenticated;

create or replace function public.challenge_battle_power_bcombat01(
  p_target_character_id uuid,p_request_id uuid default gen_random_uuid()
)
returns jsonb language plpgsql volatile security definer set search_path=pg_catalog,public,auth,pg_temp as $$
declare
  v_user_id uuid:=auth.uid();v_self_id uuid;v_settings public.battle_challenge_settings_bcombat01%rowtype;
  v_existing jsonb;v_challenger_row public.player_characters%rowtype;v_target_row public.player_characters%rowtype;
  v_challenger jsonb;v_target jsonb;v_day date;v_active_count integer;
  v_last_completed timestamptz;v_cooldown_until timestamptz;v_first_challenger boolean;v_round integer:=0;v_sequence integer:=0;
  v_challenger_hp integer;v_target_hp integer;v_hit jsonb;v_actions jsonb:='[]'::jsonb;
  v_winner_id uuid;v_loser_id uuid;v_winner jsonb;v_loser jsonb;
  v_transfer bigint;v_granted bigint;v_escrow bigint;v_cap bigint;v_winner_before bigint;v_loser_before bigint;
  v_winner_after bigint;v_loser_after bigint;v_loser_stage_floor bigint;v_loser_stage_progress bigint;
  v_transfer_rate numeric;v_transfer_rate_bps integer;v_challenge_id uuid:=gen_random_uuid();v_event_id uuid;v_world_year integer:=1;
  v_title text;v_content text;v_result jsonb;v_winner_is_challenger boolean;v_story_variant integer;
begin
  if v_user_id is null then raise exception 'AUTH_REQUIRED';end if;
  if p_request_id is null then raise exception 'INVALID_REQUEST_ID';end if;
  perform pg_advisory_xact_lock(hashtext('B-COMBAT01:'||p_request_id::text));
  select result into v_existing from public.battle_challenges_bcombat01
    where request_id=p_request_id and challenger_character_id in(
      select id from public.player_characters where user_id=v_user_id
    );
  if v_existing is not null then return v_existing;end if;
  select * into v_settings from public.battle_challenge_settings_bcombat01 where singleton_id=1;
  if not coalesce(v_settings.enabled,false) then raise exception 'BATTLE_CHALLENGE_DISABLED';end if;
  select pc.id into v_self_id from public.player_characters pc where pc.user_id=v_user_id
    and pc.status in('active','secluded','missing') order by pc.created_at desc limit 1;
  if v_self_id is null then raise exception 'NO_ACTIVE_CHARACTER';end if;
  if p_target_character_id is null or p_target_character_id=v_self_id then raise exception 'INVALID_CHALLENGE_TARGET';end if;
  perform 1 from public.player_characters where id in(v_self_id,p_target_character_id) order by id for update;
  select * into v_challenger_row from public.player_characters where id=v_self_id;
  select * into v_target_row from public.player_characters where id=p_target_character_id;
  if v_target_row.id is null or v_target_row.status not in('active','secluded','missing') then raise exception 'CHALLENGE_TARGET_NOT_FOUND';end if;
  if v_challenger_row.world_id<>v_target_row.world_id then raise exception 'CHALLENGE_WORLD_MISMATCH';end if;
  perform public.bcombat01_assign_element(v_self_id);perform public.bcombat01_assign_element(p_target_character_id);
  v_challenger:=public.bcombat01_character_snapshot(v_self_id);v_target:=public.bcombat01_character_snapshot(p_target_character_id);
  if v_challenger is null or v_target is null then raise exception 'COMBAT_STATS_NOT_CONFIGURED';end if;
  v_day:=(clock_timestamp() at time zone v_settings.day_timezone)::date;
  select count(*)::integer,max(completed_at) into v_active_count,v_last_completed
    from public.battle_challenges_bcombat01
    where challenger_character_id=v_self_id and day_key=v_day and status='settled';
  if v_active_count>=v_settings.active_challenge_daily_limit then raise exception 'ACTIVE_CHALLENGE_DAILY_LIMIT';end if;
  if v_last_completed is not null then
    v_cooldown_until:=v_last_completed+make_interval(mins=>v_settings.challenge_cooldown_minutes);
    if v_cooldown_until>clock_timestamp() then raise exception 'CHALLENGE_COOLDOWN:%',v_cooldown_until;end if;
  end if;
  v_challenger_hp:=(v_challenger->>'vitality')::integer;v_target_hp:=(v_target->>'vitality')::integer;
  if (v_challenger->>'agility')::integer=(v_target->>'agility')::integer then
    v_first_challenger:=random()<0.5;
  else v_first_challenger:=(v_challenger->>'agility')::integer>(v_target->>'agility')::integer;end if;
  while v_challenger_hp>0 and v_target_hp>0 and v_round<100 loop
    v_round:=v_round+1;
    if v_first_challenger then
      v_sequence:=v_sequence+1;v_hit:=public.bcombat01_resolve_hit(v_challenger,v_target,v_target_hp,v_round,v_sequence);
      v_target_hp:=(v_hit->>'hp_after')::integer;v_actions:=v_actions||jsonb_build_array(v_hit);
      if v_target_hp<=0 then exit;end if;
      v_sequence:=v_sequence+1;v_hit:=public.bcombat01_resolve_hit(v_target,v_challenger,v_challenger_hp,v_round,v_sequence);
      v_challenger_hp:=(v_hit->>'hp_after')::integer;v_actions:=v_actions||jsonb_build_array(v_hit);
    else
      v_sequence:=v_sequence+1;v_hit:=public.bcombat01_resolve_hit(v_target,v_challenger,v_challenger_hp,v_round,v_sequence);
      v_challenger_hp:=(v_hit->>'hp_after')::integer;v_actions:=v_actions||jsonb_build_array(v_hit);
      if v_challenger_hp<=0 then exit;end if;
      v_sequence:=v_sequence+1;v_hit:=public.bcombat01_resolve_hit(v_challenger,v_target,v_target_hp,v_round,v_sequence);
      v_target_hp:=(v_hit->>'hp_after')::integer;v_actions:=v_actions||jsonb_build_array(v_hit);
    end if;
  end loop;
  if v_challenger_hp<=0 then
    v_winner_id:=p_target_character_id;v_loser_id:=v_self_id;v_winner:=v_target;v_loser:=v_challenger;v_winner_is_challenger:=false;
  else
    v_winner_id:=v_self_id;v_loser_id:=p_target_character_id;v_winner:=v_challenger;v_loser:=v_target;v_winner_is_challenger:=true;
  end if;
  select cultivation into v_winner_before from public.player_characters where id=v_winner_id;
  select pc.cultivation,coalesce(rs.cultivation_required,0)
    into v_loser_before,v_loser_stage_floor
  from public.player_characters pc join public.realm_stages rs on rs.id=pc.realm_stage_id
  where pc.id=v_loser_id;
  v_loser_stage_progress:=greatest(0,v_loser_before-v_loser_stage_floor);
  if (v_winner->>'power')::bigint<(v_loser->>'power')::bigint then
    v_transfer_rate:=v_settings.lower_power_win_rate;
  else
    v_transfer_rate:=v_settings.higher_power_win_rate;
  end if;
  v_transfer_rate_bps:=round(v_transfer_rate*10000)::integer;
  v_transfer:=least(v_loser_stage_progress,greatest(0,floor(v_loser_stage_progress::numeric*v_transfer_rate)::bigint));
  v_cap:=public.character_cultivation_cap_v1((select realm_stage_id from public.player_characters where id=v_winner_id));
  v_granted:=least(v_transfer,greatest(0,coalesce(v_cap,9223372036854775807::bigint)-v_winner_before));
  v_escrow:=v_transfer-v_granted;
  update public.player_characters
     set cultivation=greatest(v_loser_stage_floor,cultivation-v_transfer),updated_at=clock_timestamp()
   where id=v_loser_id;
  update public.player_characters set cultivation=cultivation+v_granted,updated_at=clock_timestamp() where id=v_winner_id;
  if v_escrow>0 then
    insert into public.character_battle_cultivation_escrow_bcombat01(character_id,pending_cultivation)
    values(v_winner_id,v_escrow)
    on conflict(character_id) do update set
      pending_cultivation=public.character_battle_cultivation_escrow_bcombat01.pending_cultivation+excluded.pending_cultivation,
      updated_at=clock_timestamp();
  end if;
  v_winner_after:=v_winner_before+v_granted;v_loser_after:=greatest(v_loser_stage_floor,v_loser_before-v_transfer);
  select coalesce(gw.current_year,1) into v_world_year from public.game_worlds gw where gw.id=v_challenger_row.world_id;
  v_story_variant:=1+floor(random()*4)::integer;
  v_title:='战力争锋';
  v_content:=format('%s向%s发起挑战，双方鏖战%s回合，最终%s取胜，%s被转移%s点当前境界修为。',
    v_challenger->>'name',v_target->>'name',v_round,v_winner->>'name',v_loser->>'name',v_transfer);
  v_result:=jsonb_build_object('status','settled','battle_id',v_challenge_id,
    'winner_id',v_winner_id,'winner_name',v_winner->>'name','loser_id',v_loser_id,'loser_name',v_loser->>'name',
    'challenger_won',v_winner_is_challenger,'battle_rounds',v_round,
    'first_actor_id',case when v_first_challenger then v_self_id else p_target_character_id end,
    'challenger',v_challenger,'target',v_target,'actions',v_actions,
    'challenger_hp_after',greatest(0,v_challenger_hp),'target_hp_after',greatest(0,v_target_hp),
    'cultivation_transferred',v_transfer,'cultivation_granted_now',v_granted,'cultivation_escrowed',v_escrow,
    'transfer_rate',v_transfer_rate,'transfer_rate_bps',v_transfer_rate_bps,
    'loser_stage_floor',v_loser_stage_floor,'loser_stage_progress_before',v_loser_stage_progress,
    'winner_cultivation_after',v_winner_after,'loser_cultivation_after',v_loser_after,
    'self_cultivation_after',case when v_self_id=v_winner_id then v_winner_after else v_loser_after end,
    'challenge_cooldown_minutes',v_settings.challenge_cooldown_minutes,
    'cooldown_until',clock_timestamp()+make_interval(mins=>v_settings.challenge_cooldown_minutes),
    'active_challenges_remaining',greatest(0,v_settings.active_challenge_daily_limit-v_active_count-1));
  insert into public.battle_challenges_bcombat01(
    id,request_id,world_id,day_key,challenger_character_id,target_character_id,winner_character_id,loser_character_id,
    challenger_power,target_power,challenger_snapshot,target_snapshot,battle_actions,battle_rounds,
    requested_cultivation_transfer,cultivation_granted_now,cultivation_escrowed,
    winner_cultivation_before,winner_cultivation_after,loser_cultivation_before,loser_cultivation_after,result
  ) values(
    v_challenge_id,p_request_id,v_challenger_row.world_id,v_day,v_self_id,p_target_character_id,v_winner_id,v_loser_id,
    (v_challenger->>'power')::bigint,(v_target->>'power')::bigint,v_challenger,v_target,v_actions,v_round,
    v_transfer,v_granted,v_escrow,v_winner_before,v_winner_after,v_loser_before,v_loser_after,v_result);
  v_event_id:=public.world_event_publish_v0140(
    v_challenger_row.world_id,v_world_year,'battle_challenge',(case when v_winner_is_challenger then 3 else 2 end)::smallint,
    v_winner_id,v_winner->>'name',v_title,v_content,'battle_challenges_bcombat01',v_challenge_id::text,
    jsonb_build_object('winner_id',v_winner_id,'loser_id',v_loser_id,'rounds',v_round,
      'cultivation_transferred',v_transfer,'transfer_rate_bps',v_transfer_rate_bps,
      'loser_stage_progress_before',v_loser_stage_progress,
      'challenger_power',(v_challenger->>'power')::bigint,
      'target_power',(v_target->>'power')::bigint),false,null::timestamptz);
  if v_event_id is not null then
    update public.battle_challenges_bcombat01 set world_event_id=v_event_id,
      result=jsonb_set(result,'{world_event_id}',to_jsonb(v_event_id::text),true)
    where id=v_challenge_id returning result into v_result;
  end if;
  return v_result;
end$$;
revoke all on function public.challenge_battle_power_bcombat01(uuid,uuid) from public,anon,authenticated;
grant execute on function public.challenge_battle_power_bcombat01(uuid,uuid) to authenticated;

create or replace function public.bcombat01_world_event_story_v11(
  p_challenger jsonb,p_target jsonb,p_winner_id uuid,p_rounds integer,p_transfer bigint,p_result jsonb
)
returns jsonb language plpgsql volatile security definer set search_path=pg_catalog,public,pg_temp as $$
declare
  c_name text:=coalesce(nullif(btrim(p_challenger->>'name'),''),'无名修士');
  t_name text:=coalesce(nullif(btrim(p_target->>'name'),''),'无名修士');
  c_weapon text:=coalesce(nullif(btrim(p_challenger->>'weapon_name'),''),'赤手空拳');
  t_weapon text:=coalesce(nullif(btrim(p_target->>'weapon_name'),''),'赤手空拳');
  c_unarmed boolean:=coalesce(nullif(p_challenger->>'is_unarmed','')::boolean,true);
  t_unarmed boolean:=coalesce(nullif(p_target->>'is_unarmed','')::boolean,true);
  c_power bigint:=coalesce(nullif(p_challenger->>'power','')::bigint,0);
  t_power bigint:=coalesce(nullif(p_target->>'power','')::bigint,0);
  c_won boolean:=p_winner_id=(p_challenger->>'character_id')::uuid;
  winner_name text;loser_name text;winner_weapon text;winner_unarmed boolean;
  winner_power bigint;loser_power bigint;winner_lower boolean;
  opening text;finisher text;title text;content text;
  variant integer:=1+floor(random()*5)::integer;
  rounds integer:=greatest(1,coalesce(p_rounds,1));transfer bigint:=greatest(0,coalesce(p_transfer,0));
  winner_hp numeric:=0;winner_max_hp numeric:=1;close_fight boolean:=false;element_advantage boolean:=false;
begin
  if c_won then
    winner_name:=c_name;loser_name:=t_name;winner_weapon:=c_weapon;winner_unarmed:=c_unarmed;
    winner_power:=c_power;loser_power:=t_power;
    winner_hp:=greatest(0,coalesce(nullif(p_result->>'challenger_hp_after','')::numeric,0));
    winner_max_hp:=greatest(1,coalesce(nullif(p_challenger->>'vitality','')::numeric,1));
  else
    winner_name:=t_name;loser_name:=c_name;winner_weapon:=t_weapon;winner_unarmed:=t_unarmed;
    winner_power:=t_power;loser_power:=c_power;
    winner_hp:=greatest(0,coalesce(nullif(p_result->>'target_hp_after','')::numeric,0));
    winner_max_hp:=greatest(1,coalesce(nullif(p_target->>'vitality','')::numeric,1));
  end if;
  winner_lower:=winner_power<loser_power;
  close_fight:=winner_hp/winner_max_hp<=0.25;
  element_advantage:=case when c_won then
    (p_challenger->>'element',p_target->>'element') in (('metal','wood'),('wood','earth'),('earth','water'),('water','fire'),('fire','metal'))
  else
    (p_target->>'element',p_challenger->>'element') in (('metal','wood'),('wood','earth'),('earth','water'),('water','fire'),('fire','metal')) end;
  opening:=case when c_unarmed then format('%s未携兵刃，只以一双肉掌向%s发起挑战',c_name,t_name)
    else format('%s执%s向%s发起挑战',c_name,c_weapon,t_name) end;
  finisher:=case when winner_unarmed then case variant when 1 then '掌中真元' when 2 then '一记重掌' when 3 then '拳意' when 4 then '并指剑气' else '护体罡劲' end else winner_weapon end;

  if c_won then
    if winner_lower then title:=case variant when 1 then '越阶破敌' when 2 then '逆势夺修' when 3 then '以弱胜强' when 4 then '天命逆转' else '越榜扬名' end;
    else title:=case variant when 1 then '强者镇压' when 2 then '一击定胜' when 3 then '道争得胜' when 4 then '锋芒破敌' else '战力碾压' end;end if;
    if rounds<=3 then
      content:=format('%s。%s攻势如雷，不过%s回合便震散%s的护体灵光。%s体力不支，惨败于%s下，被夺走%s点修为。',opening,c_name,rounds,t_name,t_name,finisher,transfer);
    elsif close_fight then
      content:=format('%s。双方鏖战%s回合，皆已灵力将尽。%s强提一口真元，以%s抢得最后半招；%s终因体力不支落败，被夺走%s点修为。',opening,rounds,c_name,finisher,t_name,transfer);
    elsif element_advantage then
      content:=format('%s。交锋之间五行之势渐显，%s借属性相克催动%s，破去%s周身灵障。%s败下阵来，被夺走%s点修为。',opening,c_name,finisher,t_name,t_name,transfer);
    else
      content:=format('%s。双方斗法%s回合，%s寻得气机破绽，以%s击溃%s护体灵光。%s体力不支，败于%s下，被夺走%s点修为。',opening,rounds,c_name,finisher,t_name,t_name,finisher,transfer);
    end if;
  else
    if winner_lower then title:=case variant when 1 then '以弱守擂' when 2 then '逆势退敌' when 3 then '守榜奇胜' when 4 then '绝境反击' else '弱胜强敌' end;
    else title:=case variant when 1 then '守榜退敌' when 2 then '强者镇榜' when 3 then '道途受挫' when 4 then '挑战折戟' else '天命未改' end;end if;
    if rounds<=3 then
      content:=format('%s，却未能撼动%s根基。%s仅用%s回合便以%s震散其攻势；%s挑战失败，惨败于%s下，被夺走%s点修为。',opening,t_name,t_name,rounds,finisher,c_name,finisher,transfer);
    elsif close_fight then
      content:=format('%s。双方鏖战%s回合，%s几乎攻破对方防线，奈何最后一式未能建功。%s强撑伤势，以%s反击定胜；%s挑战失败，被夺走%s点修为。',opening,rounds,c_name,t_name,finisher,c_name,transfer);
    elsif element_advantage then
      content:=format('%s。%s借五行之势稳守不退，待%s攻势渐衰，以%s反压灵机。%s挑战失败，败退后被夺走%s点修为。',opening,t_name,c_name,finisher,c_name,transfer);
    else
      content:=format('%s。%s沉着应对，任其连攻%s回合而道心不乱，随后以%s反击破敌。%s挑战失败，败于%s下，被夺走%s点修为。',opening,t_name,rounds,finisher,c_name,finisher,transfer);
    end if;
  end if;
  return jsonb_build_object('title',title,'content',content,'challenger_name',c_name,'target_name',t_name,
    'winner_name',winner_name,'loser_name',loser_name,'winner_lower_power',winner_lower,'story_revision','V1.1');
end$$;
revoke all on function public.bcombat01_world_event_story_v11(jsonb,jsonb,uuid,integer,bigint,jsonb) from public,anon,authenticated;

create or replace function public.bcombat01_refresh_world_event_v11()
returns trigger language plpgsql security definer set search_path=pg_catalog,public,pg_temp as $$
declare s jsonb;
begin
  if new.world_event_id is null then return new;end if;
  begin
    s:=public.bcombat01_world_event_story_v11(new.challenger_snapshot,new.target_snapshot,new.winner_character_id,new.battle_rounds,new.requested_cultivation_transfer,new.result);
    update public.jiuxiao_world_events
       set title=left(s->>'title',80),content=left(s->>'content',1200),
           metadata=coalesce(metadata,'{}'::jsonb)||jsonb_build_object(
             'challenger_id',new.challenger_character_id,'target_id',new.target_character_id,
             'winner_id',new.winner_character_id,'loser_id',new.loser_character_id,
             'transfer_rate_bps',coalesce((new.result->>'transfer_rate_bps')::integer,0),
             'story_revision','V1.1')
     where id=new.world_event_id and event_type='battle_challenge';
  exception when others then return new;end;
  return new;
end$$;
revoke all on function public.bcombat01_refresh_world_event_v11() from public,anon,authenticated;

drop trigger if exists trg_bcombat01_refresh_world_event_fix3 on public.battle_challenges_bcombat01;
drop trigger if exists trg_bcombat01_refresh_world_event_v11 on public.battle_challenges_bcombat01;
create trigger trg_bcombat01_refresh_world_event_v11
after insert or update of world_event_id on public.battle_challenges_bcombat01
for each row when (new.world_event_id is not null)
execute function public.bcombat01_refresh_world_event_v11();

update public.battle_challenges_bcombat01 set world_event_id=world_event_id where world_event_id is not null;

notify pgrst,'reload schema';
commit;
