-- V0.14.0 FIX2：恢复九霄界闻。
-- FIX2：配套修复 world_event_publish_v0140 直接调用的参数类型解析问题。
update public.jiuxiao_world_event_settings
set enabled=true,
    breakthrough_enabled=true,
    opportunity_enabled=true,
    casino_enabled=true,
    admin_enabled=true,
    updated_at=now()
where singleton_id=1;
