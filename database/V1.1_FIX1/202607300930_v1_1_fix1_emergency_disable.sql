-- V1.1 FIX1 CACHE36 紧急停用：不删除数据、不清空资金与奖池。
begin;
update public.casino_settings set enabled=false,player_house_enabled=false,updated_at=now() where singleton_id=1;
revoke execute on function public.play_house_game_v1_fix4(uuid,text,text,text,bigint,text) from authenticated;
revoke execute on function public.place_fish_shrimp_bet_v1_fix4(uuid,text,text,text,bigint) from authenticated;
notify pgrst,'reload schema';
commit;
