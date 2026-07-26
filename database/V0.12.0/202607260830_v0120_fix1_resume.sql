-- 恢复万运博弈楼新对局。
update public.casino_settings set enabled=true,updated_at=now() where singleton_id=1;
select singleton_id,enabled,updated_at from public.casino_settings where singleton_id=1;
