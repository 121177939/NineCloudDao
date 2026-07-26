-- V0.13.0紧急停用：关闭新的突破请求；修为硬上限继续开启，避免再次产生溢出。
begin;
update public.progression_v0130_settings set breakthrough_enabled=false,cultivation_cap_enabled=true,updated_at=now() where singleton_id=1;
commit;
notify pgrst,'reload schema';
