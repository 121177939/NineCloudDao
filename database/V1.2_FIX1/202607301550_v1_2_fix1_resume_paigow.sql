-- 九霄问道 V1.2 FIX1：恢复九霄灵牌
begin;
update public.paigow_settings_bpaigow01 set enabled=true,updated_at=now() where singleton_id=1;
grant execute on function public.create_paigow_room_bpaigow01(text,text,text,text,bigint),public.join_paigow_room_bpaigow01(uuid,smallint,boolean),
  public.start_paigow_round_bpaigow01(uuid,uuid),public.choose_paigow_rob_bpaigow01(uuid,boolean,uuid),
  public.choose_paigow_multiplier_bpaigow01(uuid,integer,uuid),public.arrange_paigow_big_bpaigow01(uuid,smallint[],uuid) to authenticated;
notify pgrst,'reload schema';
commit;
