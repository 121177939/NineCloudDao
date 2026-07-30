-- 九霄问道 V1.2 FIX2 CACHE39
-- 79：九霄牌九 V26 预览界面正式发布门禁
-- 本迁移不修改牌局概率或结算规则，仅确认77/78热修复并提升客户端缓存版本。

begin;

do $$
begin
  if to_regprocedure('public.create_paigow_room_bpaigow01(text,text,text,text,bigint)') is null then
    raise exception 'V1_2_FIX2_REQUIRED:create_room_rpc';
  end if;
  if to_regprocedure('public.start_paigow_round_bpaigow01(uuid,uuid)') is null then
    raise exception 'V1_2_FIX2_REQUIRED:start_round_rpc';
  end if;
  if position(
    '1::smallint' in
    pg_get_functiondef('public.create_paigow_room_bpaigow01(text,text,text,text,bigint)'::regprocedure)
  ) = 0 then
    raise exception 'V1_2_FIX2_REQUIRED:run_hotfix_77';
  end if;
  if position(
    'v_member record' in
    pg_get_functiondef('public.start_paigow_round_bpaigow01(uuid,uuid)'::regprocedure)
  ) = 0 then
    raise exception 'V1_2_FIX2_REQUIRED:run_hotfix_78';
  end if;
  if position(
    'from public.paigow_room_members_bpaigow01 as rm' in
    pg_get_functiondef('public.start_paigow_round_bpaigow01(uuid,uuid)'::regprocedure)
  ) = 0 then
    raise exception 'V1_2_FIX2_REQUIRED:start_round_alias_fix';
  end if;
  if not exists (
    select 1 from public.paigow_settings_bpaigow01
    where singleton_id=1 and enabled and player_fee_bps=250
  ) then
    raise exception 'V1_2_FIX2_REQUIRED:paigow_settings';
  end if;
end
$$;

update public.jiuxiao_app_release_control
set release_name='V1.2 FIX2 CACHE39',
    cache_epoch=greatest(cache_epoch,39),
    notice_text='V1.2 FIX2：九霄牌九前端按V26九霄风格重制大厅、九席选座与正式牌桌；保留服务端安全洗牌、私牌遮罩及原资金结算规则。',
    updated_at=now()
where singleton_id=1;

insert into public.jiuxiao_app_release_control(singleton_id,release_name,cache_epoch,notice_text,updated_at)
select 1,'V1.2 FIX2 CACHE39',39,'V1.2 FIX2：九霄牌九V26九霄风格界面正式发布。',now()
where not exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1);

notify pgrst,'reload schema';
commit;
