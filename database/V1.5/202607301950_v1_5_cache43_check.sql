-- 九霄问道 V1.5 CACHE43 升级后检查（只读）
select 'release_cache43' check_name,
       exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1 and cache_epoch>=43 and release_name='V1.5 CACHE43') ok,
       '发布门禁已提升到CACHE43' detail
union all
select 'five_minute_room_close',
       exists(select 1 from public.paigow_settings_bpaigow01 where singleton_id=1 and idle_close_seconds=300)
       and position('interval ''5 minutes''' in pg_get_functiondef(to_regprocedure('public.create_paigow_room_bpaigow01(text,text,text,text,bigint)')))>0,
       '首局5分钟未开始自动关闭'
union all
select 'ten_times_entry_requirement',
       exists(select 1 from public.paigow_settings_bpaigow01 where singleton_id=1 and minimum_entry_multiplier=10)
       and position('PAIGOW_ENTRY_BALANCE_BELOW_TEN_TIMES_BASE' in pg_get_functiondef(to_regprocedure('public.join_paigow_room_bpaigow01(uuid,smallint,boolean)')))>0,
       '入座要求为底注10倍，不足仍可观战'
union all
select 'underfunded_auto_spectator',
       to_regprocedure('public.paigow_eject_underfunded_players_bpaigow01(uuid)') is not null
       and position('role=''spectator''' in pg_get_functiondef(to_regprocedure('public.paigow_eject_underfunded_players_bpaigow01(uuid)')))>0,
       '结算后余额不足自动起身转观战'
union all
select 'cultivation_paigow_disabled',
       exists(select 1 from public.paigow_settings_bpaigow01 where singleton_id=1 and cultivation_stakes_enabled=false)
       and position('PAIGOW_CULTIVATION_STAKES_TEMPORARILY_DISABLED' in pg_get_functiondef(to_regprocedure('public.create_paigow_room_bpaigow01(text,text,text,text,bigint)')))>0,
       '修为牌九入口已由前后端共同关闭'
union all
select 'single_hand_ties_to_dealer',
       position('return -1' in pg_get_functiondef(to_regprocedure('public.paigow_pair_compare_vs_dealer_bpaigow01(text[],text[])')))>0,
       '单手同牌、同分及双方0点均判庄家胜'
union all
select 'big_paigow_split_tie',
       position('return 0' in pg_get_functiondef(to_regprocedure('public.paigow_round_compare_bpaigow01(text,text[],smallint[],text[],smallint[])')))>0,
       '大牌九一胜一负保留整局平局'
union all
select 'tie_fee_refund',
       position('paigow_big_tie_fee_refund_v15' in pg_get_functiondef(to_regprocedure('public.paigow_settle_round_internal_bpaigow01(uuid)')))>0,
       '大牌九平局返还本金与2.5%手续费'
union all
select 'player_dealer_pro_rata',
       position('v_profit_pay_total:=least(v_profit_pool,v_winner_claim)' in pg_get_functiondef(to_regprocedure('public.paigow_settle_round_internal_bpaigow01(uuid)')))>0
       and position('all_available_at_selection' in pg_get_functiondef(to_regprocedure('public.paigow_choose_dealer_internal_bpaigow01(uuid)')))>0,
       '玩家庄按选庄时全部可用灵石封顶并统一比例赔付'
union all
select 'private_small_card_retained',
       position('v_visible:=''{}''::text[]' in pg_get_functiondef(to_regprocedure('public.get_paigow_room_state_bpaigow01(uuid)')))>0,
       '小牌九首张明牌仍仅牌主可见'
union all
select 'secure_shuffle_retained',
       position('casino_secure_random_int_v1' in pg_get_functiondef(to_regprocedure('public.paigow_shuffle_deck_bpaigow01()')))>0,
       '服务端安全洗牌保持不变'
union all
select 'physical_tiles_32',(select count(*)=32 from public.paigow_tile_defs_bpaigow01),'传统32张实体骨牌完整';
