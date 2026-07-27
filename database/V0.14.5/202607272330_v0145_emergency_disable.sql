begin;
update public.opportunity_v3_settings set enabled=false,updated_at=now() where world_code='jiuxiao_world_1';
update public.casino_settings set player_house_enabled=false where singleton_id=1;
commit;
