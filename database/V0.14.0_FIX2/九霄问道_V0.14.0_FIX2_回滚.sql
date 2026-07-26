-- V0.14.0 FIX2 安全回滚：移除触发器与公开RPC，保留 jiuxiao_world_events 历史数据供审计。
-- FIX2：配套修复 world_event_publish_v0140 直接调用的参数类型解析问题。
begin;
update public.jiuxiao_world_event_settings set enabled=false,breakthrough_enabled=false,opportunity_enabled=false,casino_enabled=false,admin_enabled=false,updated_at=now() where singleton_id=1;

drop trigger if exists trg_world_event_breakthrough_v0140 on public.cultivation_records;
drop trigger if exists trg_world_event_opportunity_v0140 on public.opportunity_v3_results;
drop trigger if exists trg_world_event_house_game_v0140 on public.casino_house_games;
drop trigger if exists trg_world_event_duel_v0140 on public.casino_duels;
drop trigger if exists trg_world_event_casino_draw_v0140 on public.casino_draws;

drop function if exists public.world_event_from_breakthrough_v0140();
drop function if exists public.world_event_from_opportunity_v0140();
drop function if exists public.world_event_from_house_game_v0140();
drop function if exists public.world_event_from_duel_v0140();
drop function if exists public.world_event_from_casino_draw_v0140();
drop function if exists public.get_world_events_v1(integer);
drop function if exists public.admin_publish_account_erasure_v1(text,text,text,text);
drop function if exists public.world_event_publish_v0140(uuid,integer,text,smallint,uuid,text,text,text,text,text,jsonb,boolean,timestamptz);
commit;
