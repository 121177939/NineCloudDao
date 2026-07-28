-- 九霄问道 V0.15.1 CACHE18 节奏修正后检查
select * from (values
  ('fish_round_40_seconds',position('/40' in pg_get_functiondef('public.casino_fish_ensure_round_v0148()'::regprocedure))>0),
  ('fish_betting_30_seconds',position('30 seconds' in pg_get_functiondef('public.casino_fish_create_round_v0148(bigint)'::regprocedure))>0),
  ('fish_reveal_32_seconds',position('32 seconds' in pg_get_functiondef('public.casino_fish_create_round_v0148(bigint)'::regprocedure))>0),
  ('fish_settle_37_seconds',position('37 seconds' in pg_get_functiondef('public.casino_fish_create_round_v0148(bigint)'::regprocedure))>0),
  ('fish_end_40_seconds',position('40 seconds' in pg_get_functiondef('public.casino_fish_create_round_v0148(bigint)'::regprocedure))>0),
  ('fish_rules_30_2_5_3',position("'betting_seconds', 30" in replace(pg_get_functiondef('public.get_fish_shrimp_state_v0148(integer)'::regprocedure),E'\n',' '))>0
    and position("'lock_seconds', 2" in replace(pg_get_functiondef('public.get_fish_shrimp_state_v0148(integer)'::regprocedure),E'\n',' '))>0
    and position("'reveal_seconds', 5" in replace(pg_get_functiondef('public.get_fish_shrimp_state_v0148(integer)'::regprocedure),E'\n',' '))>0
    and position("'settlement_seconds', 3" in replace(pg_get_functiondef('public.get_fish_shrimp_state_v0148(integer)'::regprocedure),E'\n',' '))>0),
  ('fish_current_round_timing',not exists(
    select 1 from public.casino_fish_rounds_v0148
    where not is_settled and ends_at>now() and (
      betting_closes_at<>starts_at+interval '30 seconds' or
      reveal_at<>starts_at+interval '32 seconds' or
      settles_at<>starts_at+interval '37 seconds' or
      ends_at<>starts_at+interval '40 seconds'
    )
  )),
  ('fish_feed_still_enabled',to_regprocedure('public.world_event_publish_fish_round_v0151(uuid)') is not null
    and position('world_event_publish_fish_round_v0151' in pg_get_functiondef('public.casino_fish_settle_round_v0148(uuid)'::regprocedure))>0),
  ('release_cache18',(select release_name='V0.15.1 CACHE18' and cache_epoch>=18 from public.jiuxiao_app_release_control where singleton_id=1))
) as checks(check_name,passed)
order by check_name;

select release_name,cache_epoch,notice_text,updated_at
from public.jiuxiao_app_release_control
where singleton_id=1;
