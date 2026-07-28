-- 九霄问道 B线：功法书与洞府藏经架模块
-- 唯一适配基线：V0.14.6_AB4 / Web Alpha V0.14.6 CACHE10
-- 本文件只做结构检查，不修改业务数据。

do $$
begin
  if to_regclass('public.player_characters') is null then raise exception 'PRECHECK_FAILED:player_characters'; end if;
  if to_regclass('public.character_techniques') is null then raise exception 'PRECHECK_FAILED:character_techniques'; end if;
  if to_regclass('public.character_exclusive_techniques') is null then raise exception 'PRECHECK_FAILED:character_exclusive_techniques'; end if;
  if to_regclass('public.opportunity_v4_technique_pool') is null then raise exception 'PRECHECK_FAILED:opportunity_v4_technique_pool'; end if;
  if to_regprocedure('public.settle_opportunity_v4(boolean)') is null then raise exception 'PRECHECK_FAILED:settle_opportunity_v4'; end if;
  if to_regprocedure('public.grant_cultivation_capped_v1(uuid,bigint,text,jsonb)') is null then raise exception 'PRECHECK_FAILED:grant_cultivation_capped_v1'; end if;
  if to_regprocedure('public.get_opportunity_history_v0146(integer)') is null then raise exception 'PRECHECK_FAILED:get_opportunity_history_v0146'; end if;
  if (select count(*) from public.opportunity_v4_technique_pool where is_active) <> 24 then
    raise exception 'PRECHECK_FAILED:expected_24_active_ordinary_techniques';
  end if;
  if (select count(*) from public.exclusive_technique_definitions) <> 5 then
    raise exception 'PRECHECK_FAILED:expected_5_exclusive_techniques';
  end if;
end$$;
