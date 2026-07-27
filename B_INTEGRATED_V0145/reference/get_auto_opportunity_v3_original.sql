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
