-- V1.1 FIX1 CACHE36 恢复启用：请先确认61号检查全部通过。
begin;
do $$
begin
  if to_regprocedure('public.casino_settle_bankroll_periods_v1()') is null then raise exception 'V1_1_FIX1_NOT_DEPLOYED'; end if;
  if not exists(select 1 from public.casino_settings where singleton_id=1 and house_stake_limit_bps=3000 and player_house_win_commission_bps=250) then raise exception 'V1_1_FIX1_SETTINGS_INVALID'; end if;
end;
$$;
update public.casino_settings set enabled=true,player_house_enabled=true,updated_at=now() where singleton_id=1;
grant execute on function public.play_house_game_v1_fix4(uuid,text,text,text,bigint,text) to authenticated;
grant execute on function public.place_fish_shrimp_bet_v1_fix4(uuid,text,text,text,bigint) to authenticated;
notify pgrst,'reload schema';
commit;
