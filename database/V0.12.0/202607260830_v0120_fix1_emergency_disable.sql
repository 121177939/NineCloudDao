-- 紧急关闭新对局；已有封存赌契仍会在玩家读取市坊时正常结算，未应局赌桌仍可取消或超时返还。
update public.casino_settings set enabled=false,updated_at=now() where singleton_id=1;
select singleton_id,enabled,updated_at from public.casino_settings where singleton_id=1;
