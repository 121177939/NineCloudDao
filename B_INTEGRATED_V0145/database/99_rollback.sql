-- 完整回滚到V0.14.4 AB2机缘/修为行为。先停用V4，再恢复原函数与原离线节奏。
begin;
update public.character_cultivation_effects set is_active=false where source_type='opportunity_v4';
update public.opportunity_v3_settings set enabled=true,online_interval_seconds=300,offline_interval_seconds=1200,offline_catchup_limit=1,first_interval_seconds=300,updated_at=now() where world_code='jiuxiao_world_1';
create or replace function public.claim_cultivation_v1()
returns table (
  character_id uuid,
  gained bigint,
  cultivation_total bigint,
  elapsed_seconds bigint,
  current_rate_per_second numeric,
  base_rate_per_second numeric,
  root_multiplier numeric,
  qi_multiplier numeric,
  fate_bonus numeric,
  technique_flat_rate numeric,
  technique_multiplier_bonus numeric,
  effect_flat_rate numeric,
  effect_multiplier_bonus numeric,
  claimed_at timestamptz
)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_user_id uuid := auth.uid();
  v_character_id uuid;
  v_world_id uuid;
  v_realm_stage_id smallint;
  v_age integer;
  v_player_realm_order integer := 0;
  v_mainstream_realm_order integer := 0;
  v_realm_gap integer := 0;
  v_heaven_coefficient numeric := 1;
  v_cultivation_before bigint;
  v_base_rate numeric := 0;
  v_root_multiplier numeric := 1;
  v_qi_base numeric := 1;
  v_effective_qi_multiplier numeric := 1;
  v_fate_bonus numeric := 0;
  v_technique_flat numeric := 0;
  v_technique_multiplier numeric := 0;
  v_effect_flat numeric := 0;
  v_effect_multiplier numeric := 0;
  v_last_claim timestamptz;
  v_now timestamptz := clock_timestamp();
  v_cursor timestamptz;
  v_boundary timestamptz;
  v_segment_seconds numeric;
  v_segment_effect_flat numeric;
  v_segment_effect_multiplier numeric;
  v_segment_fixed_rate numeric;
  v_segment_rate numeric;
  v_exact_gain numeric := 0;
  v_fraction numeric := 0;
  v_gained bigint := 0;
  v_elapsed bigint := 0;
  v_current_fixed_rate numeric := 0;
  v_current_rate numeric := 0;
  v_cultivation_cap bigint;
  v_requested_gain bigint := 0;
  v_discarded_gain bigint := 0;
  v_insight_multiplier numeric := 1;
begin
  if v_user_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;

  select
    pc.id, pc.world_id, pc.realm_stage_id, pc.age, pc.cultivation,
    r.major_order, cs.last_claim_at, cs.fractional_remainder
  into
    v_character_id, v_world_id, v_realm_stage_id, v_age, v_cultivation_before,
    v_player_realm_order, v_last_claim, v_fraction
  from public.player_characters pc
  join public.character_cultivation_state cs on cs.character_id = pc.id
  join public.realm_stages rs on rs.id = pc.realm_stage_id
  join public.realms r on r.id = rs.realm_id
  where pc.user_id = v_user_id
    and pc.status in ('active','secluded','missing')
  order by pc.created_at desc
  limit 1
  for update of pc, cs;

  if v_character_id is null then
    raise exception 'NO_ACTIVE_CHARACTER';
  end if;

  v_insight_multiplier := public.heavenly_insight_cultivation_multiplier_v0144(v_character_id);

  v_base_rate := coalesce(public.realm_base_cultivation_rate_v1(v_realm_stage_id), 10);
  v_last_claim := least(coalesce(v_last_claim, v_now), v_now);
  v_elapsed := greatest(0, floor(extract(epoch from (v_now - v_last_claim)))::bigint);

  select coalesce(sr.cultivation_multiplier, 1.000000)
  into v_root_multiplier
  from public.character_spirit_roots csr
  join public.spirit_roots sr on sr.id = csr.spirit_root_id
  where csr.character_id = v_character_id and csr.is_primary
  limit 1;
  v_root_multiplier := coalesce(v_root_multiplier, 1.000000);

  select coalesce(gw.spiritual_qi_level, 1.000000)
  into v_qi_base
  from public.game_worlds gw
  where gw.id = v_world_id;
  v_qi_base := coalesce(v_qi_base, 1.000000);

  select coalesce(round(avg(r.major_order))::integer, v_player_realm_order)
  into v_mainstream_realm_order
  from public.player_characters pc
  join public.realm_stages rs on rs.id = pc.realm_stage_id
  join public.realms r on r.id = rs.realm_id
  where pc.world_id = v_world_id
    and pc.status in ('active','secluded','missing');

  v_mainstream_realm_order := coalesce(v_mainstream_realm_order, v_player_realm_order);
  v_realm_gap := coalesce(v_player_realm_order, 0) - coalesce(v_mainstream_realm_order, 0);
  v_heaven_coefficient := public.heaven_balance_multiplier_v1(v_realm_gap);
  v_effective_qi_multiplier := greatest(0, v_qi_base * v_heaven_coefficient);

  select coalesce(sum(
    case
      when f.code = 'late_bloomer' then
        case
          when v_age >= coalesce((f.trigger_rules->>'late_age')::integer, 60)
            then coalesce((f.modifiers->>'late_cultivation')::numeric, 0)
          else coalesce((f.modifiers->>'early_cultivation')::numeric, 0)
        end
      else coalesce((f.modifiers->>'cultivation')::numeric, 0)
    end
  ), 0)
  into v_fate_bonus
  from public.character_fates cf
  join public.fates f on f.id = cf.fate_id
  where cf.character_id = v_character_id and cf.is_active;

  select
    coalesce(sum(coalesce((t.fixed_effects->>'cultivation_per_second')::numeric, 0) * ct.level), 0),
    coalesce(sum(greatest(coalesce((t.fixed_effects->>'cultivation_multiplier')::numeric, 1) - 1, 0)), 0)
  into v_technique_flat, v_technique_multiplier
  from public.character_techniques ct
  join public.techniques t on t.id = ct.technique_id
  where ct.character_id = v_character_id
    and ct.is_equipped
    and t.is_active;

  v_exact_gain := coalesce(v_fraction, 0);
  v_cursor := v_last_claim;

  for v_boundary in
    select boundary_at
    from (
      select v_now as boundary_at
      union
      select greatest(e.starts_at, v_last_claim)
      from public.character_cultivation_effects e
      where e.character_id = v_character_id and e.is_active
        and e.starts_at > v_last_claim and e.starts_at < v_now
      union
      select least(e.expires_at, v_now)
      from public.character_cultivation_effects e
      where e.character_id = v_character_id and e.is_active
        and e.expires_at is not null
        and e.expires_at > v_last_claim and e.expires_at < v_now
    ) boundaries
    where boundary_at > v_last_claim
    order by boundary_at
  loop
    if v_boundary <= v_cursor then continue; end if;

    select coalesce(sum(e.flat_rate_per_second), 0), coalesce(sum(e.multiplier_bonus), 0)
    into v_segment_effect_flat, v_segment_effect_multiplier
    from public.character_cultivation_effects e
    where e.character_id = v_character_id and e.is_active
      and e.starts_at <= v_cursor
      and (e.expires_at is null or e.expires_at > v_cursor);

    v_segment_seconds := greatest(0, extract(epoch from (v_boundary - v_cursor)));
    v_segment_fixed_rate := greatest(
      0,
      (v_base_rate + v_technique_flat + v_segment_effect_flat)
      * v_root_multiplier
      * greatest(0, 1 + v_fate_bonus + v_technique_multiplier + v_segment_effect_multiplier)
    );

    -- 天道动态系数是最后一层，对前面完整结果整体相乘。
    v_segment_rate := greatest(0, v_segment_fixed_rate * v_effective_qi_multiplier * v_insight_multiplier);
    v_exact_gain := v_exact_gain + (v_segment_rate * v_segment_seconds);
    v_cursor := v_boundary;
  end loop;

  v_requested_gain := floor(v_exact_gain)::bigint;
  v_gained := v_requested_gain;
  v_fraction := v_exact_gain - v_requested_gain;
  v_cultivation_cap := public.character_cultivation_cap_v1(v_realm_stage_id);
  if v_cultivation_cap is not null then
    v_gained := least(v_requested_gain, greatest(0, v_cultivation_cap - v_cultivation_before));
    v_discarded_gain := greatest(0, v_requested_gain - v_gained);
    if v_discarded_gain > 0 or v_cultivation_before >= v_cultivation_cap then
      -- 圆满后的超额修为与小数余量直接舍弃，不能带入下一境界。
      v_fraction := 0;
    end if;
  end if;

  select coalesce(sum(e.flat_rate_per_second), 0), coalesce(sum(e.multiplier_bonus), 0)
  into v_effect_flat, v_effect_multiplier
  from public.character_cultivation_effects e
  where e.character_id = v_character_id and e.is_active
    and e.starts_at <= v_now
    and (e.expires_at is null or e.expires_at > v_now);

  v_current_fixed_rate := greatest(
    0,
    (v_base_rate + v_technique_flat + v_effect_flat)
    * v_root_multiplier
    * greatest(0, 1 + v_fate_bonus + v_technique_multiplier + v_effect_multiplier)
  );
  v_current_rate := greatest(0, v_current_fixed_rate * v_effective_qi_multiplier * v_insight_multiplier);
  if v_cultivation_cap is not null and v_cultivation_before + v_gained >= v_cultivation_cap then
    v_current_rate := 0;
  end if;

  if v_gained > 0 then
    update public.player_characters
    set cultivation = cultivation + v_gained, updated_at = now()
    where id = v_character_id;
  end if;

  update public.character_cultivation_state as ccs
  set base_rate_per_second = v_base_rate,
      last_claim_at = v_now,
      fractional_remainder = v_fraction,
      total_cultivation_seconds = ccs.total_cultivation_seconds + v_elapsed,
      updated_at = now()
  where ccs.character_id = v_character_id;

  if v_gained > 0 and v_elapsed >= 300 then
    insert into public.cultivation_records (
      character_id, world_year, action_type, years_spent,
      cultivation_before, cultivation_delta, cultivation_after,
      result, calculation_snapshot
    )
    select
      v_character_id, gw.current_year, 'cultivate', 0,
      v_cultivation_before, v_gained, v_cultivation_before + v_gained,
      'success',
      jsonb_build_object(
        'mode', 'automatic_v0144_insight_total_multiplier',
        'elapsed_seconds', v_elapsed,
        'realm_base_rate', v_base_rate,
        'rate_before_heaven', v_current_fixed_rate,
        'rate_per_second', v_current_rate,
        'root_multiplier', v_root_multiplier,
        'world_qi_base', v_qi_base,
        'heaven_balance_coefficient', v_heaven_coefficient,
        'effective_qi_multiplier', v_effective_qi_multiplier,
        'heavenly_insight_multiplier', v_insight_multiplier,
        'fate_bonus', v_fate_bonus,
        'technique_flat_rate', v_technique_flat,
        'technique_multiplier_bonus', v_technique_multiplier,
        'effect_flat_rate', v_effect_flat,
        'effect_multiplier_bonus', v_effect_multiplier,
        'cultivation_cap', v_cultivation_cap,
        'requested_gain', v_requested_gain,
        'discarded_gain', v_discarded_gain,
        'cap_rule', 'v0130_hard_cap'
      )
    from public.game_worlds gw where gw.id = v_world_id;
  end if;

  return query select
    v_character_id, v_gained, v_cultivation_before + v_gained, v_elapsed,
    round(v_current_rate, 6), round(v_base_rate, 6), round(v_root_multiplier, 6),
    round(v_effective_qi_multiplier, 6), round(v_fate_bonus, 6),
    round(v_technique_flat, 6), round(v_technique_multiplier, 6),
    round(v_effect_flat, 6), round(v_effect_multiplier, 6), v_now;
end;
$$;
create or replace function public.get_auto_opportunity_v3()
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  u uuid:=auth.uid();
  c public.player_characters%rowtype;
  st public.character_opportunity_v3_state%rowtype;
  cfg public.opportunity_v3_settings%rowtype;
  ev public.opportunity_v3_catalog%rowtype;
  nowv timestamptz:=clock_timestamp();
  v_due boolean:=false;
  v_offline boolean:=false;
  v_gap_seconds numeric:=0;
  v_next timestamptz;
  v_roll numeric;
  v_total numeric;
  v_w_ex numeric:=0.2;
  v_w_im numeric:=0.5;
  v_w_he numeric:=1.5;
  v_w_ea numeric:=8;
  v_w_my numeric:=25;
  v_w_ye numeric:=64.8;
  v_boost numeric:=1;
  v_rarity text;
  v_path text;
  v_result_id uuid;
  v_catalog_code text;
  v_title text;
  v_story text;
  v_positive text;
  v_negative text;
  v_fate_code text;
  v_fate_has_definition boolean:=false;
  v_has_own boolean:=false;
  v_pity numeric:=20;
  v_other_weight numeric:=20;
  v_pick numeric;
  v_running numeric:=0;
  v_exclusive record;
  v_acquired jsonb;
  v_applied jsonb;
  v_effect_positive text:='';
  v_effect_negative text:='';
  v_auspicious_probability numeric:=50;
  v_negative_hours integer:=0;
  v_lucky_fate boolean:=false;
begin
  if u is null then raise exception 'AUTH_REQUIRED'; end if;

  select * into c from public.player_characters
   where user_id=u and status in('active','secluded','missing')
   order by created_at desc limit 1;
  if c.id is null then raise exception 'CHARACTER_NOT_FOUND'; end if;

  select * into cfg from public.opportunity_v3_settings
   where world_code='jiuxiao_world_1' limit 1;
  if cfg.world_code is null then raise exception 'OPPORTUNITY_V3_SETTINGS_MISSING'; end if;
  if not cfg.enabled then
    return jsonb_build_object('status','disabled','automatic',false,'message','自动机缘已由维护者紧急停用');
  end if;

  insert into public.character_opportunity_v3_state(character_id)
  values(c.id) on conflict do nothing;
  select * into st from public.character_opportunity_v3_state where character_id=c.id for update;

  select f.code into v_fate_code
    from public.character_fates cf join public.fates f on f.id=cf.fate_id
   where cf.character_id=c.id and cf.is_active
   order by cf.created_at limit 1;
  v_lucky_fate:=coalesce(v_fate_code='lucky_encounter',false);
  v_auspicious_probability:=public.opportunity_v3_auspicious_probability_v1(
    c.luck,c.mindset,v_lucky_fate
  );

  v_gap_seconds:=greatest(0,extract(epoch from nowv-st.last_seen_at));
  v_offline:=v_gap_seconds>greatest(60,least(180,cfg.online_interval_seconds/2));

  if v_offline then
    v_due:=v_gap_seconds>=cfg.offline_interval_seconds;
    if not v_due then
      v_next:=st.last_seen_at+make_interval(secs=>cfg.offline_interval_seconds);
      update public.character_opportunity_v3_state
         set next_available_at=v_next,last_seen_at=nowv,updated_at=nowv
       where character_id=c.id;
    end if;
  else
    v_due:=nowv>=st.next_available_at;
  end if;

  if v_due then
    if v_lucky_fate then v_boost:=1.10; end if;
    v_w_ex:=v_w_ex*v_boost;
    v_w_im:=v_w_im*v_boost;
    v_w_he:=v_w_he*v_boost;
    v_w_ea:=v_w_ea*v_boost;
    v_total:=v_w_ex+v_w_im+v_w_he+v_w_ea+v_w_my+v_w_ye;
    v_roll:=random()*v_total;

    if v_roll<v_w_ex then v_rarity:='专属';
    elsif v_roll<v_w_ex+v_w_im then v_rarity:='仙品';
    elsif v_roll<v_w_ex+v_w_im+v_w_he then v_rarity:='天品';
    elsif v_roll<v_w_ex+v_w_im+v_w_he+v_w_ea then v_rarity:='地品';
    elsif v_roll<v_w_ex+v_w_im+v_w_he+v_w_ea+v_w_my then v_rarity:='玄品';
    else v_rarity:='黄品'; end if;

    v_path:=case when random()*100<v_auspicious_probability then 'auspicious' else 'risk' end;
    v_catalog_code:=null;

    if v_rarity='专属' then
      if v_path='risk' then
        v_title:='专属机缘·天机逆流';
        v_story:='专属天机将要落下时忽然逆转，道脉受到短暂冲击。';
        v_positive:='';
        v_negative:='24 小时内修炼速度 - 5%';
      else
      select exists(select 1 from public.exclusive_technique_definitions where fate_code=v_fate_code)
        into v_fate_has_definition;
      select exists(
        select 1 from public.character_exclusive_techniques cet
        join public.exclusive_technique_definitions etd on etd.code=cet.exclusive_code
        where cet.character_id=c.id and etd.fate_code=v_fate_code
      ) into v_has_own;

      if v_fate_has_definition then
        v_pity:=greatest(20,least(100,coalesce((st.exclusive_pity->>v_fate_code)::numeric,20)));
        if v_has_own then v_pity:=0; end if;
        v_other_weight:=case when v_has_own then 25 else (100-v_pity)/4 end;
      else
        v_pity:=0;
        v_other_weight:=20;
      end if;

      v_pick:=random()*100;
      v_running:=0;
      for v_exclusive in
        select etd.*,
          case
            when etd.fate_code=v_fate_code then v_pity
            else v_other_weight
          end as draw_weight
        from public.exclusive_technique_definitions etd
        order by etd.code
      loop
        v_running:=v_running+v_exclusive.draw_weight;
        if v_pick<=v_running then exit; end if;
      end loop;

      if v_exclusive.fate_code=v_fate_code and not v_has_own then
        update public.character_exclusive_techniques set equipped=false where character_id=c.id;
        insert into public.character_exclusive_techniques(character_id,exclusive_code,level,equipped)
        values(c.id,v_exclusive.code,1,true)
        on conflict(character_id,exclusive_code) do update set equipped=true;

        v_acquired:=coalesce(st.acquired_exclusive_codes,'[]'::jsonb);
        if not (v_acquired@>jsonb_build_array(v_exclusive.code)) then
          v_acquired:=v_acquired||jsonb_build_array(v_exclusive.code);
        end if;
        update public.character_opportunity_v3_state
           set acquired_exclusive_codes=v_acquired,
               exclusive_pity=jsonb_set(coalesce(exclusive_pity,'{}'::jsonb),array[v_fate_code],to_jsonb(20),true),
               updated_at=nowv
         where character_id=c.id;
        perform public.refresh_exclusive_technique_effects_v1(c.id);

        v_title:='专属功法·'||v_exclusive.name;
        v_story:='天命牵引，一卷与你命格完全契合的道法自虚空垂落，直接归入独立专属槽。';
        v_positive:='获得专属功法《'||v_exclusive.name||'》，一级修炼速度+30%，效果已实际生效。';
        v_negative:='';
      else
        if v_fate_has_definition and not v_has_own then
          v_pity:=least(100,v_pity+2);
          update public.character_opportunity_v3_state
             set exclusive_pity=jsonb_set(coalesce(exclusive_pity,'{}'::jsonb),array[v_fate_code],to_jsonb(v_pity),true),
                 updated_at=nowv
           where character_id=c.id;
        end if;
        v_title:='专属机缘·天道收回';
        v_story:='天机一转，落下的是《'||v_exclusive.name||'》，却与你命格并不相合，被天道收回。';
        v_positive:='补偿灵石（100）'||case when v_fate_has_definition and not v_has_own then '；下一次本命专属概率提升至'||v_pity||'%' else '' end;
        v_negative:='';
      end if;
      end if;
    else
      select * into ev from public.opportunity_v3_catalog
       where grade=v_rarity and is_active order by random() limit 1;
      if ev.code is null then raise exception 'OPPORTUNITY_CONTENT_MISSING'; end if;
      v_catalog_code:=ev.code;
      v_title:=ev.title;
      v_story:=ev.story;
      v_positive:=ev.positive_text;
      v_negative:=ev.negative_text;
    end if;

    if v_path='auspicious' then
      v_effect_positive:=coalesce(v_positive,'');
      v_effect_negative:='';
    else
      v_effect_positive:='';
      v_effect_negative:=coalesce(v_negative,'');
    end if;
    v_negative_hours:=public.opportunity_v3_negative_duration_hours_v1(v_effect_negative);

    insert into public.opportunity_v3_results(
      character_id,catalog_code,rarity,path_key,reward_text,penalty_text,result_data
    ) values (
      c.id,v_catalog_code,v_rarity,v_path,v_effect_positive,nullif(v_effect_negative,''),
      jsonb_build_object(
        'title',v_title,'story',v_story,
        'auspicious_probability',v_auspicious_probability,
        'risk_probability',100-v_auspicious_probability
      )
    ) returning id into v_result_id;

    v_applied:=public.apply_opportunity_v3_effects_v1(
      c.id,c.lineage_id,greatest(1,c.birth_year+c.age),v_result_id,v_catalog_code,
      v_rarity,v_effect_positive,v_effect_negative,nowv
    );

    insert into public.opportunity_v3_effect_ledger(
      character_id,result_id,effect_type,amount,expires_at,metadata
    ) values (
      c.id,v_result_id,'resolved',0,
      case when v_negative_hours>0 then nowv+make_interval(hours=>v_negative_hours) else null end,
      jsonb_build_object(
        'applied',v_applied,'polarity',v_path,
        'positive',v_effect_positive,'negative',v_effect_negative,
        'auspicious_probability',v_auspicious_probability
      )
    );

    insert into public.history_logs(
      world_id,world_year,scope_type,scope_id,event_type,title,content,importance,visibility,metadata
    ) values (
      c.world_id,greatest(1,c.birth_year+c.age),'character',c.id,'opportunity',
      '机缘·'||coalesce(v_title,v_rarity),
      coalesce(v_story,'')||case when v_path='auspicious'
        then '【趋吉所得】'||coalesce(v_effect_positive,'')
        else '【涉险代价】'||coalesce(v_effect_negative,'') end,
      case v_rarity when '专属' then 5 when '仙品' then 5 when '天品' then 4 when '地品' then 3 when '玄品' then 2 else 1 end,
      'owner',jsonb_build_object(
        'v','0.11.6','result_id',v_result_id,'path',v_path,'applied',v_applied,
        'auspicious_probability',v_auspicious_probability
      )
    );

    v_next:=nowv+make_interval(secs=>cfg.online_interval_seconds);
    update public.character_opportunity_v3_state
       set next_available_at=v_next,last_seen_at=nowv,total_resolved=total_resolved+1,
           last_result=jsonb_build_object(
             'result_id',v_result_id,'title',v_title,'content',v_story,
             'reward_text',v_effect_positive,'penalty_text',v_effect_negative,
             'rarity',v_rarity,'rarity_name',v_rarity,
             'path_name',case v_path when 'auspicious' then '趋吉' else '涉险' end,
             'auspicious_probability',v_auspicious_probability,
             'risk_probability',100-v_auspicious_probability,
             'lucky_auspicious_bonus',case when v_lucky_fate then 5 else 0 end,
             'applied',v_applied,'created_at',nowv
           ),updated_at=nowv
     where character_id=c.id;
  else
    update public.character_opportunity_v3_state set last_seen_at=nowv,updated_at=nowv where character_id=c.id;
  end if;

  select * into st from public.character_opportunity_v3_state where character_id=c.id;
  return jsonb_build_object(
    'status','waiting','automatic',true,'next_available_at',st.next_available_at,
    'seconds_until_next',greatest(0,extract(epoch from st.next_available_at-nowv)::int),
    'last_result',st.last_result,
    'auspicious_probability',v_auspicious_probability,
    'risk_probability',100-v_auspicious_probability,
    'lucky_auspicious_bonus',case when v_lucky_fate then 5 else 0 end,
    'online_interval_seconds',cfg.online_interval_seconds,
    'offline_interval_seconds',cfg.offline_interval_seconds,
    'offline_catchup_limit',cfg.offline_catchup_limit
  );
end$$;
drop function if exists public.ack_opportunity_v4_summary(uuid);
drop function if exists public.settle_opportunity_v4(boolean);
drop function if exists public.opportunity_v4_remaining_effects(uuid,timestamptz);
drop function if exists public.opportunity_v4_prepare_effect(uuid,uuid,text,text,jsonb,timestamptz);
drop function if exists public.opportunity_v4_adjust_spirit_stones(uuid,bigint);
drop function if exists public.opportunity_v4_stage_basis(uuid);
drop table if exists public.opportunity_v4_settlement_batches cascade;
drop table if exists public.opportunity_v4_result_pool cascade;
drop table if exists public.opportunity_v4_story_pool cascade;

-- 删除新增辅修持有记录与定义（正式回滚前必须备份）。
delete from public.character_techniques where technique_id in(select id from public.techniques where code like 'opp_support_%');
delete from public.techniques where code like 'opp_support_%';
drop function if exists public.opportunity_v4_award_ordinary_technique(uuid,uuid,integer,text,timestamptz);
drop table if exists public.opportunity_v4_technique_pool;
drop table if exists public.opportunity_v4_technique_drop_rates;
update public.character_cultivation_effects set is_active=false,expires_at=coalesce(expires_at,now()),updated_at=now() where source_key like 'opportunity_v4:first:%' and is_active;
-- 行为回滚：恢复V0.14.4玩家庄零抽成。
-- 为避免破坏已经写入的佣金流水审计，本回滚保留配置字段和历史fee_amount，仅把后续佣金设为0。
-- A线同时反向应用 patches/app.js.patch，即完成界面回滚。
update public.casino_settings
set player_house_win_commission_bps=0
where singleton_id=1;

comment on function public.play_house_game_v1(text,text,bigint,text) is
  '统一大堂入口：玩家庄佣金配置已回滚为0；系统庄仍完整调用原FIX7A。';

commit;
