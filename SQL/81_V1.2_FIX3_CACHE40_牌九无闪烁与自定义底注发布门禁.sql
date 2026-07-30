-- 九霄问道 V1.2 FIX3 CACHE40
-- 81：九霄牌九无闪烁轮询与自定义底注客户端发布门禁
-- 本迁移不修改牌型、概率、洗牌、赔率或资金结算，仅提升客户端缓存版本并验证既有服务端接口。

begin;

do $$
begin
  if to_regprocedure('public.get_paigow_lobby_bpaigow01()') is null then
    raise exception 'V1_2_FIX3_REQUIRED:get_lobby_rpc';
  end if;
  if to_regprocedure('public.advance_paigow_round_bpaigow01(uuid)') is null then
    raise exception 'V1_2_FIX3_REQUIRED:advance_round_rpc';
  end if;
  if to_regprocedure('public.create_paigow_room_bpaigow01(text,text,text,text,bigint)') is null then
    raise exception 'V1_2_FIX3_REQUIRED:create_room_rpc';
  end if;
  if not exists (
    select 1 from public.paigow_settings_bpaigow01
    where singleton_id=1 and enabled and player_fee_bps=250
  ) then
    raise exception 'V1_2_FIX3_REQUIRED:paigow_settings';
  end if;
end
$$;

update public.jiuxiao_app_release_control
set release_name='V1.2 FIX3 CACHE40',
    cache_epoch=greatest(cache_epoch,40),
    notice_text='V1.2 FIX3：修复九霄牌九大厅与牌桌自动轮询导致的整体闪烁；创建房间表单保留自定义底注，不再被刷新复位。牌型、概率和资金规则不变。',
    updated_at=now()
where singleton_id=1;

insert into public.jiuxiao_app_release_control(singleton_id,release_name,cache_epoch,notice_text,updated_at)
select 1,'V1.2 FIX3 CACHE40',40,'V1.2 FIX3：九霄牌九无闪烁轮询与自定义底注修复发布。',now()
where not exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1);

notify pgrst,'reload schema';
commit;
