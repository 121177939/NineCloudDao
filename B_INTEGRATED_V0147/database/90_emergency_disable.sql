-- 紧急止损：暂停整个自动机缘系统，阻止继续生成机缘与道卷。
-- 仅在新模块出现严重线上异常时使用；不会删除已有道卷。
update public.opportunity_v3_settings
set enabled=false,updated_at=now()
where world_code='jiuxiao_world_1';
