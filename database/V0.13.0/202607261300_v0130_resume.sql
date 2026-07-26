-- V0.13.0恢复
begin;
update public.progression_v0130_settings set breakthrough_enabled=true,cultivation_cap_enabled=true,updated_at=now() where singleton_id=1;
commit;
notify pgrst,'reload schema';
