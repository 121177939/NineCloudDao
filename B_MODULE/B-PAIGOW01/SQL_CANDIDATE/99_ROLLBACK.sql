-- B-PAIGOW01 / 99_ROLLBACK.sql
begin;
drop function if exists public.paigow_settle_laohe_one_bpaigow01(uuid,uuid,text,bigint,integer,uuid);
drop function if exists public.paigow_take_player_fee_bpaigow01(uuid,uuid,text,bigint,uuid);
drop function if exists public.set_paigow_ready_bpaigow01(uuid,boolean);
drop function if exists public.get_paigow_room_state_bpaigow01(uuid);
drop function if exists public.leave_paigow_room_bpaigow01(uuid);
drop function if exists public.join_paigow_room_bpaigow01(uuid,smallint,boolean);
drop function if exists public.create_paigow_room_bpaigow01(text,text,text,text,bigint);
drop function if exists public.get_paigow_lobby_bpaigow01();
drop function if exists public.paigow_cleanup_rooms_bpaigow01();
drop function if exists public.paigow_room_name_bpaigow01(smallint);
drop table if exists public.paigow_action_requests_bpaigow01;
drop table if exists public.paigow_round_players_bpaigow01;
drop table if exists public.paigow_rounds_bpaigow01;
drop table if exists public.paigow_room_members_bpaigow01;
drop table if exists public.paigow_tile_defs_bpaigow01;
drop table if exists public.paigow_rooms_bpaigow01;
-- 不触碰 casino_bankroll_v1 及其账本、周期、随机函数。
commit;
