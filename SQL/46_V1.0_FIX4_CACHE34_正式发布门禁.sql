-- 九霄问道 V1.0 FIX4 CACHE34 正式发布门禁
begin;

do $$
begin
  if to_regprocedure('public.play_house_game_v1_fix4(uuid,text,text,text,bigint,text)') is null then
    raise exception 'V1_FIX4_REQUIRED:SAFE_HOUSE_RPC';
  end if;
  if to_regprocedure('public.place_fish_shrimp_bet_v1_fix4(uuid,text,text,text,bigint)') is null then
    raise exception 'V1_FIX4_REQUIRED:SAFE_FISH_RPC';
  end if;
  if to_regclass('public.casino_bet_requests_v1') is null then
    raise exception 'V1_FIX4_REQUIRED:REQUEST_TABLE';
  end if;
  if has_function_privilege('authenticated','public.play_house_game_v0147(text,text,text,bigint,text)','execute') then
    raise exception 'V1_FIX4_UNSAFE:OLD_HOUSE_RPC_STILL_OPEN';
  end if;
end $$;

update public.jiuxiao_app_release_control
set release_name='V1.0 FIX4 CACHE34',
    cache_epoch=greatest(cache_epoch,34),
    notice_text='V1.0 FIX4：赌坊单局下注限制为当前可用资源10%；玩家庄取消荷老兜底，开奖前锁定最大赔付；有效局5%进入全服造化池；重复请求不重复扣款、开奖或派奖。',
    updated_at=now()
where singleton_id=1;

insert into public.jiuxiao_app_release_control(singleton_id,release_name,cache_epoch,notice_text,updated_at)
select 1,'V1.0 FIX4 CACHE34',34,
       'V1.0 FIX4：赌坊单局下注限制为当前可用资源10%；玩家庄取消荷老兜底，开奖前锁定最大赔付；有效局5%进入全服造化池；重复请求不重复扣款、开奖或派奖。',now()
where not exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1);

notify pgrst,'reload schema';
commit;
