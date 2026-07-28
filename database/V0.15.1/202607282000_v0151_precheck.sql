-- 九霄问道 V0.15.1 迁移前检查
-- 目标：恢复并增强赌坊九霄界闻；鱼虾灵局改为40秒完整轮次。
select * from (values
  ('release_control',to_regclass('public.jiuxiao_app_release_control') is not null),
  ('world_event_publish',to_regprocedure('public.world_event_publish_v0140(uuid,integer,text,smallint,uuid,text,text,text,text,text,jsonb,boolean,timestamp with time zone)') is not null),
  ('house_world_event_trigger',to_regprocedure('public.world_event_from_house_game_v0140()') is not null),
  ('fish_round_table',to_regclass('public.casino_fish_rounds_v0148') is not null),
  ('fish_bet_table',to_regclass('public.casino_fish_bets_v0148') is not null),
  ('fish_create_round',to_regprocedure('public.casino_fish_create_round_v0148(bigint)') is not null),
  ('fish_settle_round',to_regprocedure('public.casino_fish_settle_round_v0148(uuid)') is not null),
  ('fish_state_rpc',to_regprocedure('public.get_fish_shrimp_state_v0148(integer)') is not null)
) as checks(check_name,passed)
order by check_name;
