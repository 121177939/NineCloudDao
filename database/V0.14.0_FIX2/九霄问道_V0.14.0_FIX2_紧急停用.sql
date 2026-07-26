-- V0.14.0 FIX2：紧急停用九霄界闻。不会影响突破、机缘或赌坊结算。
-- FIX2：配套修复 world_event_publish_v0140 直接调用的参数类型解析问题。
update public.jiuxiao_world_event_settings
set enabled=false,
    breakthrough_enabled=false,
    opportunity_enabled=false,
    casino_enabled=false,
    admin_enabled=false,
    updated_at=now()
where singleton_id=1;
