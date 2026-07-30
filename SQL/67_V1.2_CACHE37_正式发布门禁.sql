-- 九霄问道 V1.2 CACHE37 正式发布门禁
begin;
do $$
begin
  if to_regclass('public.character_talent_conflict_logs_v12') is null then raise exception 'V1_2_REQUIRED:conflict_log'; end if;
  if to_regprocedure('public.v12_is_mutant_root(smallint)') is null then raise exception 'V1_2_REQUIRED:mutant_detector'; end if;
  if to_regprocedure('public.v12_mutation_element(smallint,text,text)') is null then raise exception 'V1_2_REQUIRED:mutation_mapping'; end if;
  if to_regprocedure('public.get_my_birth_result_v12()') is null then raise exception 'V1_2_REQUIRED:birth_result'; end if;
  if not exists(select 1 from pg_trigger where tgname='trg_v12_mutant_root_conflict_guard' and not tgisinternal) then raise exception 'V1_2_REQUIRED:root_guard'; end if;
  if not exists(select 1 from pg_trigger where tgname='trg_v12_sword_heart_conflict_guard' and not tgisinternal) then raise exception 'V1_2_REQUIRED:fate_guard'; end if;
  if not exists(select 1 from public.battle_challenge_settings_bcombat01 where singleton_id=1 and mutation_bonus_enabled and mutation_final_damage_bonus=0.08) then raise exception 'V1_2_REQUIRED:mutation_bonus'; end if;
  if public.v12_mutation_label('thunder')<>'雷' or public.v12_mutation_label('ice')<>'冰' or public.v12_mutation_label('wind')<>'风' then raise exception 'V1_2_REQUIRED:mutation_labels'; end if;
  if exists(
    select 1 from public.character_spirit_roots csr
    join public.character_fates cf on cf.character_id=csr.character_id and cf.is_active
    join public.fates f on f.id=cf.fate_id and f.code='sword_heart'
    where csr.is_primary and public.v12_is_mutant_root(csr.spirit_root_id)
  ) then raise exception 'V1_2_REQUIRED:talent_conflict'; end if;
  if position('v_element*v_sword*v_mutation' in replace(pg_get_functiondef(to_regprocedure('public.bcombat01_resolve_hit(jsonb,jsonb,integer,integer,integer)')),' ',''))=0 then raise exception 'V1_2_REQUIRED:damage_layer'; end if;
end
$$;
update public.jiuxiao_app_release_control
set release_name='V1.2 CACHE37',cache_epoch=greatest(cache_epoch,37),
    notice_text='V1.2：新增变异灵根雷、风、冰，保持原五行克制；变异属性与天生剑心互斥并提供同级最终伤害8%，冲突时随机替换后获得的灵根或命格。',updated_at=now()
where singleton_id=1;
insert into public.jiuxiao_app_release_control(singleton_id,release_name,cache_epoch,notice_text,updated_at)
select 1,'V1.2 CACHE37',37,'V1.2：变异灵根雷风冰、剑心互斥、冲突随机替换与最终伤害8%。',now()
where not exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1);
notify pgrst,'reload schema';
commit;
