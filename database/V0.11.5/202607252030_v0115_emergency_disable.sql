begin;
update public.opportunity_v3_settings
set enabled=false,updated_at=now()
where world_code='jiuxiao_world_1';
commit;

select world_code,enabled,updated_at
from public.opportunity_v3_settings
where world_code='jiuxiao_world_1';
