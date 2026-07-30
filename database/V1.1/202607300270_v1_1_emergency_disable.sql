-- V1.1 紧急停用：只关闭战力挑战，不删除战报和修为暂存
begin;
update public.battle_challenge_settings_bcombat01 set enabled=false,updated_at=clock_timestamp() where singleton_id=1;
notify pgrst,'reload schema';
commit;
