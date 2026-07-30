-- 九霄问道 V1.2 FIX1 CACHE38 正式发布门禁
begin;
do $$
begin
  if to_regclass('public.paigow_rooms_bpaigow01') is null then raise exception 'V1_2_FIX1_REQUIRED:rooms';end if;
  if to_regclass('public.paigow_round_secrets_bpaigow01') is null then raise exception 'V1_2_FIX1_REQUIRED:round_secrets';end if;
  if (select count(*) from public.paigow_tile_defs_bpaigow01)<>32 then raise exception 'V1_2_FIX1_REQUIRED:32_tiles';end if;
  if to_regprocedure('public.start_paigow_round_bpaigow01(uuid,uuid)') is null then raise exception 'V1_2_FIX1_REQUIRED:start_rpc';end if;
  if to_regprocedure('public.choose_paigow_rob_bpaigow01(uuid,boolean,uuid)') is null then raise exception 'V1_2_FIX1_REQUIRED:rob_rpc';end if;
  if to_regprocedure('public.choose_paigow_multiplier_bpaigow01(uuid,integer,uuid)') is null then raise exception 'V1_2_FIX1_REQUIRED:multiplier_rpc';end if;
  if to_regprocedure('public.arrange_paigow_big_bpaigow01(uuid,smallint[],uuid)') is null then raise exception 'V1_2_FIX1_REQUIRED:arrange_rpc';end if;
  if to_regprocedure('public.advance_paigow_round_bpaigow01(uuid)') is null then raise exception 'V1_2_FIX1_REQUIRED:advance_rpc';end if;
  if to_regprocedure('public.paigow_settle_round_internal_bpaigow01(uuid)') is null then raise exception 'V1_2_FIX1_REQUIRED:settlement';end if;
  if position('casino_secure_random_int_v1' in pg_get_functiondef(to_regprocedure('public.paigow_shuffle_deck_bpaigow01()')))=0 then raise exception 'V1_2_FIX1_REQUIRED:secure_shuffle';end if;
  if position('casino_bankroll_apply_v1' in pg_get_functiondef(to_regprocedure('public.paigow_settle_round_internal_bpaigow01(uuid)')))=0 then raise exception 'V1_2_FIX1_REQUIRED:existing_bankroll';end if;
  if not exists(select 1 from public.paigow_settings_bpaigow01 where singleton_id=1 and enabled and player_fee_bps=250 and small_multiplier_seconds=6 and big_multiplier_seconds=10) then raise exception 'V1_2_FIX1_REQUIRED:settings';end if;
end $$;
update public.jiuxiao_app_release_control
set release_name='V1.2 FIX1 CACHE38',cache_epoch=greatest(cache_epoch,38),
    notice_text='V1.2 FIX1：九霄灵牌正式并线，支持天地玄黄四房、牌九/大牌九、老何庄、随机抢庄与开船；安全洗牌、私牌遮罩、2.5%玩家局手续费及整桌原子结算。',updated_at=now()
where singleton_id=1;
insert into public.jiuxiao_app_release_control(singleton_id,release_name,cache_epoch,notice_text,updated_at)
select 1,'V1.2 FIX1 CACHE38',38,'V1.2 FIX1：九霄灵牌正式并线。',now()
where not exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1);
notify pgrst,'reload schema';
commit;
