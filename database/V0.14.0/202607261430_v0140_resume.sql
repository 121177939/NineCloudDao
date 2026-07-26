-- 恢复九霄界闻。
update public.world_event_settings
set enabled=true,
    breakthrough_enabled=true,
    opportunity_enabled=true,
    casino_enabled=true,
    admin_enabled=true,
    updated_at=now()
where singleton_id=1;
