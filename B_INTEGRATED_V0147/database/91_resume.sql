-- 故障排除后恢复自动机缘。
update public.opportunity_v3_settings
set enabled=true,updated_at=now()
where world_code='jiuxiao_world_1';
