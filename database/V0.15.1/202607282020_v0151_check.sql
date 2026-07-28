-- 九霄问道 V0.15.1 执行后检查
select * from (values
  ('fish_publish_helper',to_regprocedure('public.world_event_publish_fish_round_v0151(uuid)') is not null),
  ('fish_round_40_seconds',position('/40' in pg_get_functiondef('public.casino_fish_ensure_round_v0148()'::regprocedure))>0),
  ('fish_betting_30_seconds',position('30 seconds' in pg_get_functiondef('public.casino_fish_create_round_v0148(bigint)'::regprocedure))>0),
  ('fish_reveal_32_seconds',position('32 seconds' in pg_get_functiondef('public.casino_fish_create_round_v0148(bigint)'::regprocedure))>0),
  ('fish_settle_37_seconds',position('37 seconds' in pg_get_functiondef('public.casino_fish_create_round_v0148(bigint)'::regprocedure))>0),
  ('fish_end_40_seconds',position('40 seconds' in pg_get_functiondef('public.casino_fish_create_round_v0148(bigint)'::regprocedure))>0),
  ('fish_settle_publishes_feed',position('world_event_publish_fish_round_v0151' in pg_get_functiondef('public.casino_fish_settle_round_v0148(uuid)'::regprocedure))>0),
  ('house_feed_dealer_name',position('dealer_name_snapshot' in pg_get_functiondef('public.world_event_from_house_game_v0140()'::regprocedure))>0),
  ('house_feed_net_win_loss',position('净赢' in pg_get_functiondef('public.world_event_from_house_game_v0140()'::regprocedure))>0 and position('净输' in pg_get_functiondef('public.world_event_from_house_game_v0140()'::regprocedure))>0),
  ('release_cache18',(select release_name='V0.15.1 CACHE18' and cache_epoch>=18 from public.jiuxiao_app_release_control where singleton_id=1))
) as checks(check_name,passed)
order by check_name;

select release_name,cache_epoch,notice_text,updated_at
from public.jiuxiao_app_release_control
where singleton_id=1;
