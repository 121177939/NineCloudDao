-- 九霄问道 V1.1 升级前检查（只读）
-- 前置：V1.0 FIX4 CACHE34

do $$
begin
  if to_regclass('public.battle_challenges_bcombat01') is null then raise exception 'V1_1_REQUIRED:battle_challenges_bcombat01'; end if;
  if to_regclass('public.battle_challenge_settings_bcombat01') is null then raise exception 'V1_1_REQUIRED:battle_challenge_settings_bcombat01'; end if;
  if to_regclass('public.jiuxiao_world_events') is null then raise exception 'V1_1_REQUIRED:jiuxiao_world_events'; end if;
  if to_regprocedure('public.challenge_battle_power_bcombat01(uuid,uuid)') is null then raise exception 'V1_1_REQUIRED:challenge_rpc'; end if;
  if to_regprocedure('public.get_battle_challenge_preview_bcombat01(uuid)') is null then raise exception 'V1_1_REQUIRED:preview_rpc'; end if;
  if to_regprocedure('public.get_battle_power_ranking_bcombat01(integer,integer)') is null then raise exception 'V1_1_REQUIRED:ranking_rpc'; end if;
  if coalesce((select cache_epoch>=34 from public.jiuxiao_app_release_control where singleton_id=1),false) is not true then
    raise exception 'V1_1_REQUIRED:CACHE34';
  end if;
end;
$$;
