-- 合并模块迁移前检查
do $$
begin
  if to_regclass('public.opportunity_v3_settings') is null then raise exception 'MISSING:opportunity_v3_settings';end if;
  if to_regclass('public.techniques') is null or to_regclass('public.character_techniques') is null then raise exception 'MISSING:technique_system';end if;
  if to_regprocedure('public.award_opportunity_technique_v3(uuid,text,integer)') is null then raise exception 'MISSING:award_opportunity_technique_v3';end if;
  if to_regprocedure('public.award_cave_resource_v3(uuid,text,numeric)') is null then raise exception 'MISSING:award_cave_resource_v3';end if;
  if to_regprocedure('public.claim_cultivation_v1()') is null then raise exception 'MISSING:claim_cultivation_v1';end if;
  if to_regprocedure('public.get_auto_opportunity_v3()') is null then raise exception 'MISSING:get_auto_opportunity_v3';end if;
  if to_regclass('public.casino_settings') is null then raise exception 'MISSING:casino_settings';end if;
  if to_regprocedure('public.casino_play_player_house_v1(uuid,text,text,bigint,text)') is null then raise exception 'MISSING:casino_play_player_house_v1';end if;
end$$;
select 'PASS' result,'V0.14.4_AB2 dependencies present' detail;
