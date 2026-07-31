-- 九霄问道 V1.6 FIX1 CACHE45 正式发布门禁
begin;

do $$
declare v_def text;
begin
  if to_regprocedure('public.get_paigow_room_state_bpaigow01(uuid)') is null then raise exception 'V1_6_FIX1_REQUIRED:room_state_rpc'; end if;
  v_def:=pg_get_functiondef(to_regprocedure('public.get_paigow_room_state_bpaigow01(uuid)'));
  if position($needle$v_room.duel_type='laohe'$needle$ in v_def)=0 then raise exception 'V1_6_FIX1_REQUIRED:laohe_branch'; end if;
  if position($needle$v_phase in('arrange','head_reveal','tail_reveal','settled')$needle$ in v_def)=0 then raise exception 'V1_6_FIX1_REQUIRED:big_blind_until_arrange'; end if;
  if position($needle$if v_phase='settled' then v_visible:=v_cards;else v_visible:='{}'::text[];end if$needle$ in v_def)=0 then raise exception 'V1_6_FIX1_REQUIRED:small_blind_until_settlement'; end if;
end
$$;

update public.jiuxiao_app_release_control
set release_name='V1.6 FIX1 CACHE45',
    cache_epoch=greatest(cache_epoch,45),
    notice_text='V1.6 FIX1：老何固定庄房改为盲牌下注。小牌九结算前玩家看不到自己的任何牌；大牌九选倍前看不到预发明牌，选倍完成进入组牌阶段后才显示本人四张牌；老何牌面继续只在公开阶段显示。',
    updated_at=now()
where singleton_id=1;

insert into public.jiuxiao_app_release_control(singleton_id,release_name,cache_epoch,notice_text,updated_at)
select 1,'V1.6 FIX1 CACHE45',45,'老何庄大小牌九盲牌规则发布。',now()
where not exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1);

notify pgrst,'reload schema';
commit;
