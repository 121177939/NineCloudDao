-- B-COMBAT01 紧急停用
begin;
update public.battle_challenge_settings_bcombat01
set enabled=false,updated_at=clock_timestamp()
where singleton_id=1;
notify pgrst,'reload schema';
commit;
