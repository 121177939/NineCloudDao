-- V1.1 恢复启用：确认50、51、52号均通过后使用
begin;
update public.battle_challenge_settings_bcombat01 set enabled=true,updated_at=clock_timestamp() where singleton_id=1;
notify pgrst,'reload schema';
commit;
