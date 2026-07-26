-- 紧急停用九霄界闻。不会影响突破、机缘或赌坊结算。
update public.world_event_settings
set enabled=false,
    breakthrough_enabled=false,
    opportunity_enabled=false,
    casino_enabled=false,
    admin_enabled=false,
    updated_at=now()
where singleton_id=1;
