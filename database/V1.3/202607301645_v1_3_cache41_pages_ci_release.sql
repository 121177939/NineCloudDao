-- 九霄问道 V1.3 CACHE41
-- 83：GitHub Pages可移植构建发布门禁
-- 本迁移只提升客户端发布门禁，不修改牌型、概率、洗牌、赔率、资金结算或战斗规则。

begin;

do $$
begin
  if to_regprocedure('public.get_paigow_lobby_bpaigow01()') is null then
    raise exception 'V1_3_REQUIRED:get_lobby_rpc';
  end if;
  if to_regprocedure('public.advance_paigow_round_bpaigow01(uuid)') is null then
    raise exception 'V1_3_REQUIRED:advance_round_rpc';
  end if;
  if to_regprocedure('public.create_paigow_room_bpaigow01(text,text,text,text,bigint)') is null then
    raise exception 'V1_3_REQUIRED:create_room_rpc';
  end if;
  if not exists (
    select 1 from public.paigow_settings_bpaigow01
    where singleton_id=1 and enabled and player_fee_bps=250
  ) then
    raise exception 'V1_3_REQUIRED:paigow_settings';
  end if;
end
$$;

update public.jiuxiao_app_release_control
set release_name='V1.3 CACHE41',
    cache_epoch=greatest(cache_epoch,41),
    notice_text='V1.3：修复GitHub Pages构建流程的环境依赖问题，正式CI不再依赖Playwright或固定Chromium路径；游戏规则与资金结算不变。',
    updated_at=now()
where singleton_id=1;

insert into public.jiuxiao_app_release_control(singleton_id,release_name,cache_epoch,notice_text,updated_at)
select 1,'V1.3 CACHE41',41,'V1.3：GitHub Pages可移植构建与CACHE41发布。',now()
where not exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1);

notify pgrst,'reload schema';
commit;
