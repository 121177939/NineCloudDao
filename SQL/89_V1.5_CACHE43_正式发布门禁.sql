-- 九霄问道 V1.5 CACHE43 正式发布门禁
begin;

do $$
begin
  if to_regprocedure('public.paigow_minimum_entry_balance_bpaigow01(bigint)') is null then raise exception 'V1_5_REQUIRED:entry_requirement'; end if;
  if to_regprocedure('public.paigow_pair_compare_vs_dealer_bpaigow01(text[],text[])') is null then raise exception 'V1_5_REQUIRED:dealer_compare'; end if;
  if not exists(select 1 from public.paigow_settings_bpaigow01 where singleton_id=1 and idle_close_seconds=300 and minimum_entry_multiplier=10 and cultivation_stakes_enabled=false) then
    raise exception 'V1_5_REQUIRED:settings';
  end if;
  if position('v_winner_claim>v_profit_pool' in pg_get_functiondef(to_regprocedure('public.paigow_settle_round_internal_bpaigow01(uuid)')))=0 then
    raise exception 'V1_5_REQUIRED:pro_rata_settlement';
  end if;
  if position('PAIGOW_CULTIVATION_STAKES_TEMPORARILY_DISABLED' in pg_get_functiondef(to_regprocedure('public.create_paigow_room_bpaigow01(text,text,text,text,bigint)')))=0 then
    raise exception 'V1_5_REQUIRED:cultivation_switch';
  end if;
end
$$;

update public.jiuxiao_app_release_control
set release_name='V1.5 CACHE43',
    cache_epoch=greatest(cache_epoch,43),
    notice_text='V1.5：牌九房5分钟未开首局自动关闭；入座需底注10倍灵石；结算后余额不足自动转观战；玩家庄按资金比例赔付；单手同牌庄赢；大牌九一胜一负平局并退手续费；修为牌九暂时关闭。',
    updated_at=now()
where singleton_id=1;

insert into public.jiuxiao_app_release_control(singleton_id,release_name,cache_epoch,notice_text,updated_at)
select 1,'V1.5 CACHE43',43,'V1.5牌九资金门槛、庄家比例结算、牌型胜负与修为开关发布。',now()
where not exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1);

notify pgrst,'reload schema';
commit;
