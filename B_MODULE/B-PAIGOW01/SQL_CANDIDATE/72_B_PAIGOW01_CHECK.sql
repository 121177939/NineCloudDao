-- B-PAIGOW01 / 72_B_PAIGOW01_CHECK.sql
select to_regclass('public.paigow_rooms_bpaigow01') as rooms_table,
       to_regclass('public.paigow_room_members_bpaigow01') as members_table,
       to_regclass('public.paigow_tile_defs_bpaigow01') as tiles_table,
       (select count(*) from public.paigow_tile_defs_bpaigow01) as physical_tile_count,
       to_regprocedure('public.get_paigow_lobby_bpaigow01()') as lobby_rpc,
       to_regprocedure('public.create_paigow_room_bpaigow01(text,text,text,text,bigint)') as create_rpc,
       to_regprocedure('public.paigow_settle_laohe_one_bpaigow01(uuid,uuid,text,bigint,integer,uuid)') as laohe_settle_helper,
       (select count(*) from public.casino_bankroll_v1 where stake_type in('spirit_stone','cultivation')) as reused_bankroll_rows;
