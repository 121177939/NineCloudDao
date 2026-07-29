-- 九霄问道 V1.0 FIX4 升级前检查
-- 前置：V1.0 FIX3 CACHE33

do $$
begin
  if to_regclass('public.casino_settings') is null then raise exception 'V1_FIX4_REQUIRED:casino_settings'; end if;
  if to_regclass('public.casino_house_games') is null then raise exception 'V1_FIX4_REQUIRED:casino_house_games'; end if;
  if to_regclass('public.casino_fish_bets_v0148') is null then raise exception 'V1_FIX4_REQUIRED:casino_fish_bets_v0148'; end if;
  if to_regprocedure('public.play_house_game_v0147(text,text,text,bigint,text)') is null then raise exception 'V1_FIX4_REQUIRED:play_house_game_v0147'; end if;
  if to_regprocedure('public.play_system_house_game_v0141_fix7a(text,text,bigint,text)') is null then raise exception 'V1_FIX4_REQUIRED:system_house'; end if;
  if to_regprocedure('public.casino_player_house_draw_result_v1(text,text)') is null then raise exception 'V1_FIX4_REQUIRED:player_draw'; end if;
  if to_regprocedure('public.casino_take_pool_share_v0141_fix7a(text,bigint,integer,text)') is null then raise exception 'V1_FIX4_REQUIRED:pool_share'; end if;
  if to_regprocedure('public.world_event_publish_fish_round_v0151(uuid)') is null then raise exception 'V1_FIX4_REQUIRED:fish_world_feed'; end if;
  if coalesce((select cache_epoch>=33 from public.jiuxiao_app_release_control where singleton_id=1),false) is not true then
    raise exception 'V1_FIX4_REQUIRED:CACHE33';
  end if;
end;
$$;
