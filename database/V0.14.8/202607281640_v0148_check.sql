-- 九霄问道 V0.14.8 鱼虾灵局执行后检查
select * from (values
  ('fish_round_table',to_regclass('public.casino_fish_rounds_v0148') is not null),
  ('fish_bet_table',to_regclass('public.casino_fish_bets_v0148') is not null),
  ('fish_state_rpc',to_regprocedure('public.get_fish_shrimp_state_v0148(integer)') is not null),
  ('fish_bet_rpc',to_regprocedure('public.place_fish_shrimp_bet_v0148(text,text,text,bigint)') is not null),
  ('authenticated_state',has_function_privilege('authenticated','public.get_fish_shrimp_state_v0148(integer)','execute')),
  ('authenticated_bet',has_function_privilege('authenticated','public.place_fish_shrimp_bet_v0148(text,text,text,bigint)','execute')),
  ('anon_state_denied',not has_function_privilege('anon','public.get_fish_shrimp_state_v0148(integer)','execute')),
  ('anon_bet_denied',not has_function_privilege('anon','public.place_fish_shrimp_bet_v0148(text,text,text,bigint)','execute')),
  ('release_cache12',coalesce((select release_name='V0.14.8 CACHE12' and cache_epoch>=12 from public.jiuxiao_app_release_control where singleton_id=1),false))
) as checks(check_name,ok);

select round_no,starts_at,betting_closes_at,reveal_at,settles_at,ends_at,is_settled
from public.casino_fish_rounds_v0148
order by round_no desc limit 5;
