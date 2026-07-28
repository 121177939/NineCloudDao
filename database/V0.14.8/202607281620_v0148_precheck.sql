-- 九霄问道 V0.14.8 鱼虾灵局执行前检查
-- 本文件只读，不修改数据。
select * from (values
  ('player_characters',to_regclass('public.player_characters') is not null),
  ('casino_settings',to_regclass('public.casino_settings') is not null),
  ('casino_pools',to_regclass('public.casino_pools') is not null),
  ('player_house_state',to_regclass('public.casino_player_house_state') is not null),
  ('v0147_house_rpc',to_regprocedure('public.play_house_game_v0147(text,text,text,bigint,text)') is not null),
  ('current_character_rpc',to_regprocedure('public.casino_current_character_id_v1()') is not null),
  ('casino_debit_rpc',to_regprocedure('public.casino_debit_v1(uuid,text,bigint,text,text)') is not null),
  ('casino_credit_rpc',to_regprocedure('public.casino_credit_result_v0141(uuid,text,bigint)') is not null),
  ('fix7a_pool_rpc',to_regprocedure('public.casino_take_pool_share_v0141_fix7a(text,bigint,integer,text)') is not null),
  ('player_house_resolver',to_regprocedure('public.casino_player_house_resolve_dealer_v1()') is not null),
  ('release_control',to_regclass('public.jiuxiao_app_release_control') is not null)
) as checks(check_name,ok);
