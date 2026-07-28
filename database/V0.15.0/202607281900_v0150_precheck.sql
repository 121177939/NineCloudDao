-- 九霄问道 V0.15.0 执行前检查
-- 目标：鱼虾灵局连续落注前端升级；鱼虾灵局不进入九霄界闻。

select * from (values
  ('player_characters', to_regclass('public.player_characters') is not null),
  ('casino_house_games', to_regclass('public.casino_house_games') is not null),
  ('world_event_settings', to_regclass('public.jiuxiao_world_event_settings') is not null),
  ('world_event_publish_rpc', to_regprocedure('public.world_event_publish_v0140(uuid,integer,text,smallint,uuid,text,text,text,text,text,jsonb,boolean,timestamp with time zone)') is not null),
  ('house_world_event_trigger_function', to_regprocedure('public.world_event_from_house_game_v0140()') is not null),
  ('release_control', to_regclass('public.jiuxiao_app_release_control') is not null),
  ('fish_bet_rpc', to_regprocedure('public.place_fish_shrimp_bet_v0148(text,text,text,bigint)') is not null)
) as checks(check_name, ok)
order by check_name;
