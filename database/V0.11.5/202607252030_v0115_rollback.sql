-- V0.11.5 FINAL 结构回滚 SQL（必须同时把前端回退到 V0.11.4）
-- 不删除玩家机缘记录、功法记录或专属功法记录；只撤销 V0.11.5 新函数、触发器和实时效果接线。
begin;

update public.opportunity_v3_settings set enabled=false,updated_at=now() where world_code='jiuxiao_world_1';

drop trigger if exists trg_refresh_opportunity_technique_effects_v1 on public.character_techniques;

update public.character_cultivation_effects
set is_active=false,expires_at=coalesce(expires_at,clock_timestamp()),updated_at=now()
where is_active and (source_key like 'opptech:%' or source_key like 'exclusive:%');

-- 恢复 V0.11.2 中普通机缘功法的原始 fixed_effects 表示。
update public.techniques set fixed_effects='{"cultivation_per_second":25,"linear_growth_per_level":0.10}'::jsonb where code='opp_hongmeng';
update public.techniques set fixed_effects='{"cultivation_multiplier":0.20,"linear_growth_per_level":0.10}'::jsonb where code='opp_dongtian';
update public.techniques set fixed_effects='{"cultivation_per_second":22,"linear_growth_per_level":0.10}'::jsonb where code='opp_cangyuan';
update public.techniques set fixed_effects='{"cultivation_multiplier":0.12,"linear_growth_per_level":0.10}'::jsonb where code='opp_liuyun';
update public.techniques set fixed_effects='{"cultivation_per_second":10,"linear_growth_per_level":0.10}'::jsonb where code='opp_zhoutian_tuna';
update public.techniques set fixed_effects='{"cultivation_multiplier":0.10,"linear_growth_per_level":0.10}'::jsonb where code='opp_qingshi';
update public.techniques set fixed_effects='{"cultivation_multiplier":0.06,"linear_growth_per_level":0.10}'::jsonb where code='opp_qianxi';
update public.techniques set fixed_effects='{"cultivation_multiplier":0.05,"linear_growth_per_level":0.10}'::jsonb where code='opp_jichu';
update public.techniques set fixed_effects='{"cultivation_per_second":4,"linear_growth_per_level":0.10}'::jsonb where code='opp_zhoutian_yangqi';
update public.techniques set fixed_effects='{"cultivation_multiplier":0.01,"linear_growth_per_level":0.10}'::jsonb where code='opp_cuqian';
update public.techniques set fixed_effects='{"cultivation_multiplier":0.01,"linear_growth_per_level":0.10}'::jsonb where code='opp_rumen';
update public.techniques set fixed_effects='{"cultivation_multiplier":0.02,"linear_growth_per_level":0.10}'::jsonb where code='opp_qingquan';

create or replace function public.get_auto_opportunity_v3() returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare u uuid:=auth.uid(); c public.player_characters%rowtype; st public.character_opportunity_v3_state%rowtype; nowv timestamptz:=clock_timestamp(); due boolean; ev public.opportunity_v3_catalog%rowtype; roll numeric; rarity text; path text; res uuid; fatecode text; boost numeric:=1; nextv timestamptz;
begin
 if u is null then raise exception 'AUTH_REQUIRED'; end if;
 select * into c from public.player_characters where user_id=u and status in('active','secluded','missing') order by created_at desc limit 1;
 if c.id is null then raise exception 'CHARACTER_NOT_FOUND'; end if;
 insert into public.character_opportunity_v3_state(character_id) values(c.id) on conflict do nothing;
 select * into st from public.character_opportunity_v3_state where character_id=c.id for update;
 if exists(select 1 from public.character_fates cf join public.fates f on f.id=cf.fate_id where cf.character_id=c.id and cf.is_active and f.code='lucky_encounter') then boost:=1.10; end if;
 due:=nowv>=st.next_available_at;
 if due then
   roll:=random()*100;
   if roll<0.2*boost then rarity:='专属'; elsif roll<0.2*boost+0.5*boost then rarity:='仙品'; elsif roll<0.2*boost+0.5*boost+1.5*boost then rarity:='天品'; elsif roll<0.2*boost+0.5*boost+1.5*boost+8*boost then rarity:='地品'; elsif roll<35 then rarity:='玄品'; else rarity:='黄品'; end if;
   path:=case when (c.luck+c.mindset+random()*100)>=110 then 'auspicious' else 'risk' end;
   if rarity='专属' then
      select f.code into fatecode from public.character_fates cf join public.fates f on f.id=cf.fate_id where cf.character_id=c.id and cf.is_active order by cf.created_at limit 1;
      select ('专属功法·'||name)::text as title, ('天命牵引，一卷本命道法自虚空落下。')::text as story, ('获得专属功法《'||name||'》，一级修炼速度+30%；独立专属槽。')::text as positive_text, ('若命格不符，天道收回并补偿100灵石；本命权重永久累积。')::text as negative_text into ev.title,ev.story,ev.positive_text,ev.negative_text from public.exclusive_technique_definitions order by random() limit 1;
   else select * into ev from public.opportunity_v3_catalog where grade=rarity and is_active order by random() limit 1; end if;
   insert into public.opportunity_v3_results(character_id,catalog_code,rarity,path_key,reward_text,penalty_text,result_data) values(c.id,ev.code,rarity,path,ev.positive_text,case when public.opportunity_v3_penalty_hours(rarity)>0 then format('天机迟滞%s小时；%s',public.opportunity_v3_penalty_hours(rarity),ev.negative_text) else ev.negative_text end,jsonb_build_object('title',ev.title,'story',ev.story)) returning id into res;
   if ev.positive_text ~ '修为（([0-9]+)）' then update public.player_characters set cultivation=cultivation+((regexp_match(ev.positive_text,'修为（([0-9]+)）'))[1])::bigint where id=c.id; end if;
   if ev.positive_text ~ '灵石（([0-9]+)）' then perform public.award_spirit_stones_v3(c.id,((regexp_match(ev.positive_text,'灵石（([0-9]+)）'))[1])::bigint); end if;
   insert into public.opportunity_v3_effect_ledger(character_id,result_id,effect_type,amount,expires_at,metadata) values(c.id,res,'resolved',0,case when public.opportunity_v3_penalty_hours(rarity)>0 then nowv+make_interval(hours=>public.opportunity_v3_penalty_hours(rarity)) else null end,jsonb_build_object('positive',ev.positive_text,'negative',ev.negative_text,'cave_mapping',jsonb_build_array('cave_qi','spirit_herb','spirit_ore')));
   insert into public.history_logs(world_id,world_year,scope_type,scope_id,event_type,title,content,importance,visibility,metadata) values(c.world_id,greatest(1,c.birth_year+c.age),'character',c.id,'opportunity','机缘·'||coalesce(ev.title,rarity),coalesce(ev.story,'')||'【所得】'||ev.positive_text||'【代价】'||ev.negative_text,case rarity when '仙品' then 5 when '天品' then 4 when '地品' then 3 when '玄品' then 2 else 1 end,'owner',jsonb_build_object('v','0.11.2','result_id',res,'path',path));
   nextv:=nowv+interval '5 minutes'; update public.character_opportunity_v3_state set next_available_at=nextv,last_seen_at=nowv,total_resolved=total_resolved+1,last_result=jsonb_build_object('result_id',res,'title',ev.title,'content',ev.story,'reward_text',ev.positive_text,'penalty_text',ev.negative_text,'rarity',rarity,'rarity_name',rarity,'path_name',case path when 'auspicious' then '趋吉' else '涉险' end,'created_at',nowv),updated_at=nowv where character_id=c.id;
 else update public.character_opportunity_v3_state set last_seen_at=nowv,updated_at=nowv where character_id=c.id; end if;
 select * into st from public.character_opportunity_v3_state where character_id=c.id;
 return jsonb_build_object('status','waiting','automatic',true,'next_available_at',st.next_available_at,'seconds_until_next',greatest(0,extract(epoch from st.next_available_at-nowv)::int),'last_result',st.last_result,'online_interval_seconds',300,'offline_interval_seconds',1200,'offline_catchup_limit',1);
end$$;

create or replace function public.upgrade_exclusive_technique_v1(p_character_exclusive_id uuid) returns jsonb language plpgsql security definer set search_path=public,pg_temp as $$
declare u uuid:=auth.uid(); r record; cost bigint; begin select cet.*,pc.user_id into r from public.character_exclusive_techniques cet join public.player_characters pc on pc.id=cet.character_id where cet.id=p_character_exclusive_id and pc.user_id=u for update; if r.id is null then raise exception 'NOT_FOUND'; end if; if r.level>=36 then raise exception 'MAX_LEVEL'; end if; cost:=1050*r.level*r.level; select ci.quantity into r.spirit_stones from public.character_inventory ci join public.item_definitions i on i.id=ci.item_definition_id where ci.character_id=r.character_id and i.code='spirit_stone' for update; if coalesce(r.spirit_stones,0)<cost then raise exception 'INSUFFICIENT_SPIRIT_STONES'; end if; update public.character_inventory ci set quantity=quantity-cost,updated_at=now() from public.item_definitions i where ci.item_definition_id=i.id and ci.character_id=r.character_id and i.code='spirit_stone'; update public.character_exclusive_techniques set level=level+1 where id=r.id; return jsonb_build_object('success',true,'level',r.level+1,'cost',cost); end$$;



drop function if exists public.get_exclusive_technique_system_v1();
drop function if exists public.set_exclusive_technique_slot_v1(uuid);
drop function if exists public.apply_opportunity_v3_effects_v1(uuid,uuid,integer,uuid,text,text,text,text,timestamptz);
drop function if exists public.award_cave_resource_v3(uuid,text,numeric);
drop function if exists public.award_opportunity_technique_v3(uuid,text,integer);
drop function if exists public.refresh_exclusive_technique_effects_v1(uuid);
drop function if exists public.trg_refresh_opportunity_technique_effects_v1();
drop function if exists public.refresh_opportunity_technique_effects_v1(uuid);
drop function if exists public.exclusive_technique_effect_bonus_v1(integer,numeric);
drop function if exists public.v0115_linear_effect_v1(numeric,integer,numeric);

update public.opportunity_v3_settings set enabled=true,updated_at=now() where world_code='jiuxiao_world_1';
commit;
