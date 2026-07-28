-- 九霄问道 V0.15.0 执行后检查

select * from (values
  ('fish_bet_rpc', to_regprocedure('public.place_fish_shrimp_bet_v0148(text,text,text,bigint)') is not null),
  ('house_world_event_function', to_regprocedure('public.world_event_from_house_game_v0140()') is not null),
  ('fish_world_feed_guard', position('fish_shrimp' in pg_get_functiondef('public.world_event_from_house_game_v0140()'::regprocedure)) > 0),
  ('fish_world_feed_early_return', position('return new' in pg_get_functiondef('public.world_event_from_house_game_v0140()'::regprocedure)) > 0),
  ('release_cache16', coalesce((select release_name = 'V0.15.0 CACHE16' and cache_epoch >= 16 from public.jiuxiao_app_release_control where singleton_id = 1), false)),
  ('authenticated_fish_bet', has_function_privilege('authenticated', 'public.place_fish_shrimp_bet_v0148(text,text,text,bigint)', 'execute')),
  ('anon_fish_bet_denied', not has_function_privilege('anon', 'public.place_fish_shrimp_bet_v0148(text,text,text,bigint)', 'execute'))
) as checks(check_name, ok)
order by check_name;
