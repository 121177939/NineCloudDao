-- 回滚到V0.14.6_AB4原始功法获得逻辑。
-- 注意：character_technique_books表和已获得道卷故意保留，避免数据丢失；回滚后前端不再展示，后续重新接入可继续使用。

begin;
drop function if exists public.use_technique_book_v1(uuid);
drop function if exists public.get_technique_library_v1();
drop function if exists public.apply_technique_book_first_rewards_v1(uuid,uuid,text,timestamptz);

-- 恢复V0.14.6_AB4的普通功法即时学习函数。
create or replace function public.opportunity_v4_award_ordinary_technique(
  p_character_id uuid,
  p_lineage_id uuid,
  p_world_year integer,
  p_technique_code text,
  p_scheduled_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path=public,pg_temp
as $$
declare
  p record;t record;v_existed boolean:=false;v_award jsonb;v_basis jsonb;v_b numeric:=1;v_s numeric:=100;
  v_spec jsonb:='{}'::jsonb;v_cgain bigint:=0;v_sgain bigint:=0;v_delta bigint:=0;v_mastery integer:=0;
  v_permanent jsonb:='[]'::jsonb;v_items jsonb:='{}'::jsonb;v_cave jsonb;v_amount numeric:=0;
begin
  select * into p from public.opportunity_v4_technique_pool where technique_code=p_technique_code and is_active;
  select id,code,name,grade,category into t from public.techniques where code=p_technique_code and is_active limit 1;
  if p.technique_code is null or t.id is null then
    return jsonb_build_object('awarded',false,'reason','TECHNIQUE_POOL_OR_DEFINITION_MISSING','technique_code',p_technique_code);
  end if;
  select exists(select 1 from public.character_techniques where character_id=p_character_id and technique_id=t.id) into v_existed;
  v_award:=public.award_opportunity_technique_v3(p_character_id,t.name,p_world_year);
  if v_existed then
    v_mastery:=case t.grade when 'immortal' then 80 when 'heaven' then 65 when 'earth' then 50 when 'mystic' then 40 when 'yellow' then 30 else 25 end;
    return jsonb_build_object(
      'awarded',true,'is_new',false,'technique_code',t.code,'technique_name',t.name,'grade',p.grade,'grade_code',t.grade,'category',t.category,
      'mastery_points',v_mastery,'permanent_effects','[]'::jsonb,'items','{}'::jsonb,
      'applied',jsonb_build_object('cultivation_gain_requested',0,'cultivation_loss_requested',0,'spirit_gain',0,'spirit_loss',0,'speed_bonus',0,'duration_minutes',0),
      'narrative','再次参悟《'||t.name||'》，重复传承已转化为'||v_mastery||'点传承点。'
    );
  end if;

  v_spec:=coalesce(p.first_reward_spec,'{}'::jsonb);
  v_basis:=public.opportunity_v4_stage_basis(p_character_id);
  v_b:=greatest(1,coalesce((v_basis->>'cultivation_basis')::numeric,1));
  v_s:=greatest(1,coalesce((v_basis->>'spirit_stone_basis')::numeric,100));
  if v_spec ? 'cultivation_gain_fixed' then v_cgain:=v_cgain+greatest(0,(v_spec->>'cultivation_gain_fixed')::bigint);end if;
  if v_spec ? 'cultivation_gain_pct' then v_cgain:=v_cgain+greatest(0,round(v_b*(v_spec->>'cultivation_gain_pct')::numeric)::bigint);end if;
  if v_spec ? 'spirit_gain_fixed' then v_sgain:=v_sgain+greatest(0,(v_spec->>'spirit_gain_fixed')::bigint);end if;
  if v_spec ? 'spirit_gain_mult' then v_sgain:=v_sgain+greatest(0,round(v_s*(v_spec->>'spirit_gain_mult')::numeric)::bigint);end if;
  if v_sgain>0 then v_delta:=public.opportunity_v4_adjust_spirit_stones(p_character_id,v_sgain);v_sgain:=greatest(0,v_delta);end if;

  if v_spec ? 'permanent_speed_bonus' then
    v_amount:=(v_spec->>'permanent_speed_bonus')::numeric;
    insert into public.character_cultivation_effects(character_id,source_type,source_key,display_name,flat_rate_per_second,multiplier_bonus,starts_at,expires_at,is_active,metadata)
    values(p_character_id,'opportunity','opportunity_v4:first:'||t.code||':multiplier','机缘功法初得·'||t.name,0,v_amount,p_scheduled_at,null,true,jsonb_build_object('kind','technique_first_reward','technique_code',t.code,'grade',p.grade));
    v_permanent:=v_permanent||jsonb_build_array('《'||t.name||'》初得：永久修炼速度+'||trim(to_char(v_amount*100,'FM999990.##'))||'%');
  end if;
  if v_spec ? 'permanent_flat_rate' then
    v_amount:=(v_spec->>'permanent_flat_rate')::numeric;
    insert into public.character_cultivation_effects(character_id,source_type,source_key,display_name,flat_rate_per_second,multiplier_bonus,starts_at,expires_at,is_active,metadata)
    values(p_character_id,'opportunity','opportunity_v4:first:'||t.code||':flat','机缘功法初得·'||t.name,v_amount,0,p_scheduled_at,null,true,jsonb_build_object('kind','technique_first_reward','technique_code',t.code,'grade',p.grade));
    v_permanent:=v_permanent||jsonb_build_array('《'||t.name||'》初得：永久每秒修为+'||trim(to_char(v_amount,'FM999990.###')));
  end if;
  if v_spec ? 'cave_daily_spirit_mapping' then
    v_cave:=public.award_cave_resource_v3(p_lineage_id,t.code,(v_spec->>'cave_daily_spirit_mapping')::numeric);
    if coalesce((v_cave->>'awarded')::boolean,false) then
      v_items:=jsonb_build_object(v_cave->>'resource_name',(v_cave->>'amount')::numeric);
    end if;
  end if;
  return jsonb_build_object(
    'awarded',true,'is_new',true,'technique_code',t.code,'technique_name',t.name,'grade',p.grade,'grade_code',t.grade,'category',t.category,
    'mastery_points',0,'permanent_effects',v_permanent,'items',v_items,
    'applied',jsonb_build_object('cultivation_gain_requested',v_cgain,'cultivation_loss_requested',0,'spirit_gain',v_sgain,'spirit_loss',0,'speed_bonus',0,'duration_minutes',0,'basis',v_basis),
    'narrative',p.acquisition_narrative||' 获得'||case when t.category='support' then '辅修' else '主修' end||'功法《'||t.name||'》。'
  );
end$$;
-- 恢复V0.14.6_AB4的机缘结算函数（本命直接获得、异命回收）。
create or replace function public.settle_opportunity_v4(p_settle_cultivation boolean default true)
returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare
  u uuid:=auth.uid();c public.player_characters%rowtype;st public.character_opportunity_v3_state%rowtype;cfg public.opportunity_v3_settings%rowtype;
  nowv timestamptz:=clock_timestamp();v_period_start timestamptz;v_event_at timestamptz;v_due integer:=0;v_capped integer:=0;v_gap numeric:=0;v_offline boolean:=false;
  v_batch uuid:=gen_random_uuid();v_grade text;v_path text;v_story record;v_result record;v_effect jsonb;v_applied jsonb;v_result_id uuid;
  v_fate_code text;v_lucky boolean:=false;v_ausp numeric:=50;v_roll numeric;v_total numeric;v_boost numeric:=1;
  w_ex numeric:=0.2;w_im numeric:=0.5;w_he numeric:=1.5;w_ea numeric:=8;w_my numeric:=25;w_ye numeric:=64.8;
  v_grade_counts jsonb:='{"黄品":0,"玄品":0,"地品":0,"天品":0,"仙品":0,"专属":0}'::jsonb;
  v_path_counts jsonb:='{"趋吉":0,"涉险":0}'::jsonb;
  v_cgain_req bigint:=0;v_closs_req bigint:=0;v_sgain bigint:=0;v_sloss bigint:=0;v_actual_gain bigint:=0;v_actual_loss bigint:=0;
  v_claim jsonb:=null;v_summary jsonb:=null;v_latest jsonb:=null;v_remaining jsonb:='{}'::jsonb;v_floor bigint:=0;v_before bigint;v_grant record;
  v_fate_has boolean:=false;v_has_own boolean:=false;v_pity numeric:=20;v_other numeric:=20;v_pick numeric;v_running numeric;v_exclusive record;v_acquired jsonb;
  v_rates record;v_tech_category text;v_tech_pool record;v_tech_award jsonb;v_tech_new jsonb:='[]'::jsonb;v_tech_dup jsonb:='[]'::jsonb;
  v_mastery integer:=0;v_permanent jsonb:='[]'::jsonb;v_items_gain jsonb:='{}'::jsonb;v_item record;v_item_amount numeric;
begin
  if u is null then raise exception 'AUTH_REQUIRED'; end if;
  select * into c from public.player_characters where user_id=u and status in('active','secluded','missing') order by created_at desc limit 1 for update;
  if c.id is null then raise exception 'NO_ACTIVE_CHARACTER'; end if;
  select * into cfg from public.opportunity_v3_settings where world_code='jiuxiao_world_1';
  if cfg.world_code is null then raise exception 'OPPORTUNITY_SETTINGS_MISSING'; end if;
  insert into public.character_opportunity_v3_state(character_id,next_available_at,last_seen_at)
  values(c.id,nowv+interval '5 minutes',nowv) on conflict(character_id) do nothing;
  select * into st from public.character_opportunity_v3_state where character_id=c.id for update;
  select f.code into v_fate_code from public.character_fates cf join public.fates f on f.id=cf.fate_id where cf.character_id=c.id and cf.is_active order by cf.created_at limit 1;
  v_lucky:=coalesce(v_fate_code='lucky_encounter',false);
  v_ausp:=public.opportunity_v3_auspicious_probability_v1(c.luck,c.mindset,v_lucky);
  v_period_start:=least(coalesce(st.last_seen_at,nowv),nowv);v_gap:=greatest(0,extract(epoch from(nowv-v_period_start)));v_offline:=v_gap>=300;
  if cfg.enabled and nowv>=st.next_available_at then
    v_due:=floor(extract(epoch from(nowv-st.next_available_at))/300)::integer+1;
    v_capped:=greatest(0,v_due-least(v_due,coalesce(cfg.offline_catchup_limit,864)));v_due:=least(v_due,coalesce(cfg.offline_catchup_limit,864));
  end if;

  if v_due>0 then
    for i in 0..v_due-1 loop
      v_event_at:=st.next_available_at+make_interval(secs=>300*i);
      if v_lucky then v_boost:=1.10; else v_boost:=1; end if;
      w_ex:=0.2*v_boost;w_im:=0.5*v_boost;w_he:=1.5*v_boost;w_ea:=8*v_boost;w_my:=25;w_ye:=64.8;v_total:=w_ex+w_im+w_he+w_ea+w_my+w_ye;v_roll:=random()*v_total;
      if v_roll<w_ex then v_grade:='专属';elsif v_roll<w_ex+w_im then v_grade:='仙品';elsif v_roll<w_ex+w_im+w_he then v_grade:='天品';elsif v_roll<w_ex+w_im+w_he+w_ea then v_grade:='地品';elsif v_roll<w_ex+w_im+w_he+w_ea+w_my then v_grade:='玄品';else v_grade:='黄品';end if;
      v_path:=case when random()*100<v_ausp then 'auspicious' else 'risk' end;
      select * into v_story from public.opportunity_v4_story_pool where grade=v_grade and polarity=v_path and is_active order by -ln(greatest(random(),0.000001))/weight limit 1;
      if v_story.code is null then raise exception 'OPPORTUNITY_V4_STORY_MISSING:%:%',v_grade,v_path; end if;
      v_grade_counts:=jsonb_set(v_grade_counts,array[v_grade],to_jsonb(coalesce((v_grade_counts->>v_grade)::int,0)+1),true);
      v_path_counts:=jsonb_set(v_path_counts,array[case when v_path='auspicious' then '趋吉' else '涉险' end],to_jsonb(coalesce((v_path_counts->>(case when v_path='auspicious' then '趋吉' else '涉险' end))::int,0)+1),true);
      v_tech_award:=null;v_tech_category:=null;

      if v_grade='专属' and v_path='auspicious' then
        select exists(select 1 from public.exclusive_technique_definitions where fate_code=v_fate_code) into v_fate_has;
        select exists(select 1 from public.character_exclusive_techniques cet join public.exclusive_technique_definitions etd on etd.code=cet.exclusive_code where cet.character_id=c.id and etd.fate_code=v_fate_code) into v_has_own;
        if v_fate_has then v_pity:=greatest(20,least(100,coalesce((st.exclusive_pity->>v_fate_code)::numeric,20)));if v_has_own then v_pity:=0;end if;v_other:=case when v_has_own then 25 else(100-v_pity)/4 end;else v_pity:=0;v_other:=20;end if;
        v_pick:=random()*100;v_running:=0;
        for v_exclusive in select etd.*,case when etd.fate_code=v_fate_code then v_pity else v_other end draw_weight from public.exclusive_technique_definitions etd order by etd.code loop v_running:=v_running+v_exclusive.draw_weight;if v_pick<=v_running then exit;end if;end loop;
        if v_exclusive.fate_code=v_fate_code and not v_has_own then
          select * into v_result from public.opportunity_v4_result_pool where grade='专属' and polarity='auspicious' and effect_spec->>'exclusive_outcome'='success' and is_active order by random() limit 1;
          update public.character_exclusive_techniques set equipped=false where character_id=c.id;
          insert into public.character_exclusive_techniques(character_id,exclusive_code,level,equipped) values(c.id,v_exclusive.code,1,true) on conflict(character_id,exclusive_code) do update set equipped=true;
          v_acquired:=coalesce(st.acquired_exclusive_codes,'[]'::jsonb);if not(v_acquired@>jsonb_build_array(v_exclusive.code)) then v_acquired:=v_acquired||jsonb_build_array(v_exclusive.code);end if;
          st.acquired_exclusive_codes:=v_acquired;st.exclusive_pity:=jsonb_set(coalesce(st.exclusive_pity,'{}'::jsonb),array[v_fate_code],to_jsonb(20),true);
          update public.character_opportunity_v3_state set acquired_exclusive_codes=st.acquired_exclusive_codes,exclusive_pity=st.exclusive_pity,updated_at=nowv where character_id=c.id;
          perform public.refresh_exclusive_technique_effects_v1(c.id);
          v_result.title:='专属功法·'||v_exclusive.name;v_result.narrative:=v_result.narrative||' 获得专属功法《'||v_exclusive.name||'》，已进入独立专属槽并立即生效。';v_effect='{}'::jsonb;
          v_tech_new:=v_tech_new||jsonb_build_array(jsonb_build_object('name',v_exclusive.name,'grade','专属','category','exclusive'));
        else
          select * into v_result from public.opportunity_v4_result_pool where grade='专属' and polarity='auspicious' and effect_spec->>'exclusive_outcome'='mismatch' and is_active order by random() limit 1;
          if v_fate_has and not v_has_own then v_pity:=least(100,v_pity+2);st.exclusive_pity:=jsonb_set(coalesce(st.exclusive_pity,'{}'::jsonb),array[v_fate_code],to_jsonb(v_pity),true);update public.character_opportunity_v3_state set exclusive_pity=st.exclusive_pity,updated_at=nowv where character_id=c.id;end if;
          v_result.title:='专属机缘·天道收回';v_result.narrative:=v_result.narrative||' 落下的是《'||v_exclusive.name||'》，却与你命格不合，被天道收回。';v_effect=jsonb_build_object('spirit_gain_fixed',100);
        end if;
      elsif v_path='auspicious' and v_grade in('玄品','地品','天品','仙品') then
        select * into v_rates from public.opportunity_v4_technique_drop_rates where grade=v_grade;
        v_roll:=random();
        if v_roll<coalesce(v_rates.main_rate,0) then v_tech_category:='main';
        elsif v_roll<coalesce(v_rates.main_rate,0)+coalesce(v_rates.support_rate,0) then v_tech_category:='support';end if;
        if v_tech_category is not null then
          select * into v_tech_pool from public.opportunity_v4_technique_pool where grade=v_grade and category=v_tech_category and is_active order by -ln(greatest(random(),0.000001))/weight limit 1;
          if v_tech_pool.technique_code is null then raise exception 'OPPORTUNITY_V4_TECHNIQUE_POOL_MISSING:%:%',v_grade,v_tech_category;end if;
          v_tech_award:=public.opportunity_v4_award_ordinary_technique(c.id,c.lineage_id,greatest(1,c.birth_year+c.age),v_tech_pool.technique_code,v_event_at);
          select ('technique:'||v_tech_pool.technique_code)::text as code,('功法·'||v_tech_pool.technique_name)::text as title,(v_tech_award->>'narrative')::text as narrative,'{}'::jsonb as effect_spec into v_result;
          v_effect:='{}'::jsonb;v_applied:=coalesce(v_tech_award->'applied','{}'::jsonb);
          if coalesce((v_tech_award->>'is_new')::boolean,false) then
            v_tech_new:=v_tech_new||jsonb_build_array(jsonb_build_object('name',v_tech_award->>'technique_name','code',v_tech_award->>'technique_code','grade',v_tech_award->>'grade','category',v_tech_award->>'category'));
          else
            v_tech_dup:=v_tech_dup||jsonb_build_array(jsonb_build_object('name',v_tech_award->>'technique_name','code',v_tech_award->>'technique_code','grade',v_tech_award->>'grade','category',v_tech_award->>'category','mastery_points',coalesce((v_tech_award->>'mastery_points')::int,0)));
            v_mastery:=v_mastery+coalesce((v_tech_award->>'mastery_points')::int,0);
          end if;
          v_permanent:=v_permanent||coalesce(v_tech_award->'permanent_effects','[]'::jsonb);
          for v_item in select key,value from jsonb_each_text(coalesce(v_tech_award->'items','{}'::jsonb)) loop
            v_item_amount:=coalesce((v_items_gain->>v_item.key)::numeric,0)+coalesce(v_item.value::numeric,0);
            v_items_gain:=jsonb_set(v_items_gain,array[v_item.key],to_jsonb(v_item_amount),true);
          end loop;
        else
          select * into v_result from public.opportunity_v4_result_pool where grade=v_grade and polarity=v_path and is_active order by -ln(greatest(random(),0.000001))/weight limit 1;
          v_effect:=v_result.effect_spec;
        end if;
      else
        select * into v_result from public.opportunity_v4_result_pool where grade=v_grade and polarity=v_path and is_active order by -ln(greatest(random(),0.000001))/weight limit 1;
        v_effect:=v_result.effect_spec;
      end if;

      if v_tech_award is null then
        if v_effect ? 'spirit_gain_fixed' then
          v_applied:=jsonb_build_object('cultivation_gain_requested',0,'cultivation_loss_requested',0,'spirit_gain',greatest(0,public.opportunity_v4_adjust_spirit_stones(c.id,(v_effect->>'spirit_gain_fixed')::bigint)),'spirit_loss',0,'speed_bonus',0,'duration_minutes',0);
        else
          v_applied:=public.opportunity_v4_prepare_effect(c.id,gen_random_uuid(),v_grade,v_path,v_effect,v_event_at);
        end if;
      end if;
      insert into public.opportunity_v3_results(character_id,catalog_code,rarity,path_key,reward_text,penalty_text,result_data,settlement_batch_id,scheduled_at)
      values(c.id,null,v_grade,v_path,case when v_path='auspicious' then v_result.narrative else '' end,case when v_path='risk' then v_result.narrative else null end,
        jsonb_build_object('v','opportunity_v4','story_code',v_story.code,'result_code',v_result.code,'title',v_result.title,'story',v_story.story,'applied',v_applied,'effect_spec',v_effect,'technique',v_tech_award),v_batch,v_event_at)
      returning id into v_result_id;
      update public.character_cultivation_effects set source_key='opportunity_v4:'||v_result_id::text,metadata=jsonb_set(metadata,'{result_id}',to_jsonb(v_result_id),true) where character_id=c.id and source_type='opportunity_v4' and starts_at=v_event_at and source_key like 'opportunity_v4:%' and metadata->>'grade'=v_grade;
      v_cgain_req:=v_cgain_req+coalesce((v_applied->>'cultivation_gain_requested')::bigint,0);v_closs_req:=v_closs_req+coalesce((v_applied->>'cultivation_loss_requested')::bigint,0);v_sgain:=v_sgain+coalesce((v_applied->>'spirit_gain')::bigint,0);v_sloss:=v_sloss+coalesce((v_applied->>'spirit_loss')::bigint,0);
      v_latest:=jsonb_build_object('result_id',v_result_id,'title',v_result.title,'content',v_story.story,'result_text',v_result.narrative,'rarity',v_grade,'rarity_name',v_grade,'path_name',case when v_path='auspicious' then '趋吉' else '涉险' end,'applied',v_applied,'created_at',v_event_at);
      if v_grade in('天品','仙品','专属') then
        insert into public.history_logs(world_id,world_year,scope_type,scope_id,event_type,title,content,importance,visibility,metadata)
        values(c.world_id,greatest(1,c.birth_year+c.age),'character',c.id,'opportunity','机缘·'||v_result.title,v_story.story||'【'||case when v_path='auspicious' then '趋吉所得' else '涉险结果' end||'】'||v_result.narrative,
          case v_grade when '专属' then 5 when '仙品' then 5 else 4 end,'owner',jsonb_build_object('v','opportunity_v4','result_id',v_result_id,'batch_id',v_batch,'scheduled_at',v_event_at,'applied',v_applied));
      end if;
    end loop;
  end if;

  if v_due>0 then
    update public.character_opportunity_v3_state set next_available_at=case when v_capped>0 then nowv+interval '5 minutes' else st.next_available_at+make_interval(secs=>300*v_due) end,last_seen_at=nowv,total_resolved=total_resolved+v_due,last_result=v_latest,updated_at=nowv where character_id=c.id;
  else update public.character_opportunity_v3_state set last_seen_at=nowv,updated_at=nowv where character_id=c.id;end if;

  if p_settle_cultivation then select to_jsonb(x) into v_claim from public.claim_cultivation_v1() x;end if;
  select pc.cultivation,coalesce(rs.cultivation_required,0) into v_before,v_floor from public.player_characters pc join public.realm_stages rs on rs.id=pc.realm_stage_id where pc.id=c.id for update;
  v_actual_loss:=least(v_closs_req,greatest(0,v_before-v_floor));if v_actual_loss>0 then update public.player_characters set cultivation=cultivation-v_actual_loss,updated_at=now() where id=c.id;end if;
  if v_cgain_req>0 then select * into v_grant from public.grant_cultivation_capped_v1(c.id,v_cgain_req,'opportunity_v4',jsonb_build_object('batch_id',v_batch));v_actual_gain:=coalesce(v_grant.granted_amount,0);end if;
  v_remaining:=public.opportunity_v4_remaining_effects(c.id,nowv);
  if v_due>0 then
    insert into public.opportunity_v4_settlement_batches(id,character_id,period_started_at,period_ended_at,event_count,is_offline,capped_event_count,grade_counts,polarity_counts,gains,losses,net_result,remaining_effects,cultivation_claim,shown_at)
    values(v_batch,c.id,v_period_start,nowv,v_due,v_offline,v_capped,v_grade_counts,v_path_counts,
      jsonb_build_object('cultivation_direct',v_actual_gain,'spirit_stones',v_sgain,'items',v_items_gain,'techniques_new',v_tech_new,'techniques_duplicate',v_tech_dup,'mastery_points',v_mastery,'permanent_effects',v_permanent),
      jsonb_build_object('cultivation_direct',v_actual_loss,'spirit_stones',v_sloss,'items','{}'::jsonb),
      jsonb_build_object('cultivation',coalesce((v_claim->>'gained')::bigint,0)+v_actual_gain-v_actual_loss,'spirit_stones',v_sgain-v_sloss,'items',v_items_gain,'effects',v_remaining,'techniques_new',v_tech_new,'techniques_duplicate',v_tech_dup,'mastery_points',v_mastery,'permanent_effects',v_permanent),
      v_remaining,v_claim,case when v_offline then null else nowv end);
  end if;
  select to_jsonb(b) into v_summary from public.opportunity_v4_settlement_batches b where b.character_id=c.id and b.shown_at is null order by b.created_at desc limit 1;
  select * into st from public.character_opportunity_v3_state where character_id=c.id;
  if v_claim is not null then
    v_claim:=jsonb_set(v_claim,'{gained}',to_jsonb(coalesce((v_claim->>'gained')::bigint,0)+v_actual_gain-v_actual_loss),true);
    v_claim:=jsonb_set(v_claim,'{cultivation_total}',(select to_jsonb(cultivation) from public.player_characters where id=c.id),true);
  end if;
  return jsonb_build_object(
    'opportunity',jsonb_build_object('status','waiting','automatic',true,'next_available_at',st.next_available_at,'seconds_until_next',greatest(0,extract(epoch from(st.next_available_at-nowv))::int),'last_result',st.last_result,'auspicious_probability',v_ausp,'risk_probability',100-v_ausp,'lucky_auspicious_bonus',case when v_lucky then 5 else 0 end,'online_interval_seconds',300,'offline_interval_seconds',300,'offline_catchup_limit',864),
    'cultivation',v_claim,'offline_summary',v_summary,'events_resolved',v_due,'capped_events',v_capped
  );
end$$;
revoke all on function public.settle_opportunity_v4(boolean) from public,anon;
grant execute on function public.settle_opportunity_v4(boolean) to authenticated;

drop function if exists public.technique_book_summary_add_v1(jsonb,jsonb);
drop function if exists public.technique_book_add_v1(uuid,text,text,integer,timestamptz,jsonb);

notify pgrst,'reload schema';
commit;
