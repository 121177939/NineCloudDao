-- V0.11.6结构回滚：恢复V0.11.5机缘结算函数。历史结果和玩家数据不删除。
begin;
alter table public.opportunity_v3_results drop constraint if exists opportunity_v3_results_v0116_polarity_check;
create or replace function public.apply_opportunity_v3_effects_v1(
  p_character_id uuid,
  p_lineage_id uuid,
  p_world_year integer,
  p_result_id uuid,
  p_catalog_code text,
  p_rarity text,
  p_positive_text text,
  p_negative_text text,
  p_now timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  m text[];
  v_amount numeric;
  v_hours integer;
  v_name text;
  v_applied jsonb := '[]'::jsonb;
  v_technique jsonb;
  v_cave jsonb;
begin
  -- 即时修为。
  m := regexp_match(coalesce(p_positive_text, ''), '修为（([0-9]+)）');
  if m is not null then
    v_amount := m[1]::numeric;
    update public.player_characters set cultivation = cultivation + v_amount::bigint where id = p_character_id;
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('type','instant_cultivation','amount',v_amount));
  end if;

  -- 灵石。
  m := regexp_match(coalesce(p_positive_text, ''), '灵石（([0-9]+)）');
  if m is not null then
    v_amount := m[1]::numeric;
    perform public.award_spirit_stones_v3(p_character_id, v_amount::bigint);
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('type','spirit_stone','amount',v_amount));
  end if;

  -- 永久修炼速度。
  m := regexp_match(coalesce(p_positive_text, ''), '永久修炼速度[[:space:]]*\+[[:space:]]*([0-9]+(?:\.[0-9]+)?)%');
  if m is not null then
    v_amount := m[1]::numeric / 100;
    insert into public.character_cultivation_effects(
      character_id, source_type, source_key, display_name,
      flat_rate_per_second, multiplier_bonus, starts_at, expires_at, is_active, metadata
    ) values (
      p_character_id, 'opportunity', 'opportunity_v3:'||p_result_id::text||':permanent_multiplier',
      '机缘·永久修炼速度', 0, v_amount, p_now, null, true,
      jsonb_build_object('result_id',p_result_id,'rarity',p_rarity)
    );
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('type','permanent_multiplier','amount',v_amount));
  end if;

  -- 永久每秒修为。
  m := regexp_match(coalesce(p_positive_text, ''), '永久每秒修为[[:space:]]*\+[[:space:]]*([0-9]+(?:\.[0-9]+)?)');
  if m is not null then
    v_amount := m[1]::numeric;
    insert into public.character_cultivation_effects(
      character_id, source_type, source_key, display_name,
      flat_rate_per_second, multiplier_bonus, starts_at, expires_at, is_active, metadata
    ) values (
      p_character_id, 'opportunity', 'opportunity_v3:'||p_result_id::text||':permanent_flat',
      '机缘·永久每秒修为', v_amount, 0, p_now, null, true,
      jsonb_build_object('result_id',p_result_id,'rarity',p_rarity)
    );
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('type','permanent_flat','amount',v_amount));
  end if;

  -- 临时修炼速度。
  m := regexp_match(coalesce(p_positive_text, ''), '修炼速度临时[[:space:]]*\+[[:space:]]*([0-9]+(?:\.[0-9]+)?)[%％][^0-9]+([0-9]+)[[:space:]]*小时');
  if m is not null then
    v_amount := m[1]::numeric / 100;
    v_hours := m[2]::integer;
    insert into public.character_cultivation_effects(
      character_id, source_type, source_key, display_name,
      flat_rate_per_second, multiplier_bonus, starts_at, expires_at, is_active, metadata
    ) values (
      p_character_id, 'opportunity', 'opportunity_v3:'||p_result_id::text||':temporary_multiplier',
      '机缘·临时修炼速度', 0, v_amount, p_now, p_now + make_interval(hours=>v_hours), true,
      jsonb_build_object('result_id',p_result_id,'rarity',p_rarity,'hours',v_hours)
    );
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('type','temporary_multiplier','amount',v_amount,'hours',v_hours));
  end if;

  -- 功法奖励。
  m := regexp_match(coalesce(p_positive_text, ''), '习得功法《([^》]+)》');
  if m is not null then
    v_name := m[1];
    v_technique := public.award_opportunity_technique_v3(p_character_id, v_name, p_world_year);
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('type','technique','detail',v_technique));
  end if;

  -- 洞府奖励映射。
  m := regexp_match(coalesce(p_positive_text, ''), '日增[[:space:]]*([0-9]+)[[:space:]]*灵石');
  if m is not null then
    v_amount := m[1]::numeric;
    v_cave := public.award_cave_resource_v3(p_lineage_id, p_catalog_code, v_amount);
    v_applied := v_applied || jsonb_build_array(jsonb_build_object('type','cave_resource_mapping','detail',v_cave));
  end if;

  -- 天机迟滞：以最终规则为准，黄0、玄1、地6、天12、仙/专属24小时。
  v_hours := public.opportunity_v3_penalty_hours(p_rarity);
  if v_hours > 0 then
    m := regexp_match(coalesce(p_negative_text, ''), '修炼速度[[:space:]]*-[[:space:]]*([0-9]+(?:\.[0-9]+)?)[%％]');
    if m is not null then
      v_amount := -(m[1]::numeric / 100);
      insert into public.character_cultivation_effects(
        character_id, source_type, source_key, display_name,
        flat_rate_per_second, multiplier_bonus, starts_at, expires_at, is_active, metadata
      ) values (
        p_character_id, 'opportunity', 'opportunity_v3:'||p_result_id::text||':penalty',
        '天机迟滞·'||p_rarity, 0, v_amount, p_now, p_now + make_interval(hours=>v_hours), true,
        jsonb_build_object('result_id',p_result_id,'rarity',p_rarity,'hours',v_hours)
      );
      v_applied := v_applied || jsonb_build_array(jsonb_build_object('type','penalty_multiplier','amount',v_amount,'hours',v_hours));
    end if;
  end if;

  return v_applied;
end$$;

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
    select f.code into v_fate_code
      from public.character_fates cf join public.fates f on f.id=cf.fate_id
     where cf.character_id=c.id and cf.is_active
     order by cf.created_at limit 1;

    if v_fate_code='lucky_encounter' then v_boost:=1.10; end if;
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

    v_path:=case when (c.luck+c.mindset+random()*100)>=110 then 'auspicious' else 'risk' end;
    v_catalog_code:=null;

    if v_rarity='专属' then
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
        v_negative:='本命专属已获得，后续不会重复获得本命专属。';
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
        v_negative:='此次未真正获得专属功法。';
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

    insert into public.opportunity_v3_results(
      character_id,catalog_code,rarity,path_key,reward_text,penalty_text,result_data
    ) values (
      c.id,v_catalog_code,v_rarity,v_path,v_positive,
      case when public.opportunity_v3_penalty_hours(v_rarity)>0
           then format('天机迟滞%s小时；%s',public.opportunity_v3_penalty_hours(v_rarity),coalesce(v_negative,''))
           else coalesce(v_negative,'') end,
      jsonb_build_object('title',v_title,'story',v_story)
    ) returning id into v_result_id;

    v_applied:=public.apply_opportunity_v3_effects_v1(
      c.id,c.lineage_id,greatest(1,c.birth_year+c.age),v_result_id,v_catalog_code,
      v_rarity,v_positive,v_negative,nowv
    );

    insert into public.opportunity_v3_effect_ledger(
      character_id,result_id,effect_type,amount,expires_at,metadata
    ) values (
      c.id,v_result_id,'resolved',0,
      case when public.opportunity_v3_penalty_hours(v_rarity)>0
           then nowv+make_interval(hours=>public.opportunity_v3_penalty_hours(v_rarity)) else null end,
      jsonb_build_object('applied',v_applied,'positive',v_positive,'negative',v_negative)
    );

    insert into public.history_logs(
      world_id,world_year,scope_type,scope_id,event_type,title,content,importance,visibility,metadata
    ) values (
      c.world_id,greatest(1,c.birth_year+c.age),'character',c.id,'opportunity',
      '机缘·'||coalesce(v_title,v_rarity),
      coalesce(v_story,'')||'【所得】'||coalesce(v_positive,'')||'【代价】'||coalesce(v_negative,''),
      case v_rarity when '专属' then 5 when '仙品' then 5 when '天品' then 4 when '地品' then 3 when '玄品' then 2 else 1 end,
      'owner',jsonb_build_object('v','0.11.5','result_id',v_result_id,'path',v_path,'applied',v_applied)
    );

    v_next:=nowv+make_interval(secs=>cfg.online_interval_seconds);
    update public.character_opportunity_v3_state
       set next_available_at=v_next,last_seen_at=nowv,total_resolved=total_resolved+1,
           last_result=jsonb_build_object(
             'result_id',v_result_id,'title',v_title,'content',v_story,
             'reward_text',v_positive,'penalty_text',v_negative,
             'rarity',v_rarity,'rarity_name',v_rarity,
             'path_name',case v_path when 'auspicious' then '趋吉' else '涉险' end,
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
    'online_interval_seconds',cfg.online_interval_seconds,
    'offline_interval_seconds',cfg.offline_interval_seconds,
    'offline_catchup_limit',cfg.offline_catchup_limit
  );
end$$;
drop function if exists public.opportunity_v3_auspicious_probability_v1(numeric,numeric,boolean);
drop function if exists public.opportunity_v3_negative_duration_hours_v1(text);
revoke all on function public.apply_opportunity_v3_effects_v1(uuid,uuid,integer,uuid,text,text,text,text,timestamptz) from public,anon,authenticated;
revoke all on function public.get_auto_opportunity_v3() from public,anon;
grant execute on function public.get_auto_opportunity_v3() to authenticated;
commit;
