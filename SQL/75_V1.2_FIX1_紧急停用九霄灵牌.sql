-- 九霄问道 V1.2 FIX1：紧急停用九霄灵牌并退款所有未结算回合
begin;
do $$ declare r record;begin
  if to_regprocedure('public.paigow_cancel_round_internal_bpaigow01(uuid,text)') is not null then
    for r in select id from public.paigow_rounds_bpaigow01 where phase not in('settled','cancelled') for update loop
      perform public.paigow_cancel_round_internal_bpaigow01(r.id,'emergency_disable');
    end loop;
  end if;
end $$;
update public.paigow_settings_bpaigow01 set enabled=false,updated_at=now() where singleton_id=1;
update public.paigow_rooms_bpaigow01 set status='disabled',closed_at=now(),updated_at=now() where status in('waiting','playing');
revoke execute on function public.create_paigow_room_bpaigow01(text,text,text,text,bigint),public.join_paigow_room_bpaigow01(uuid,smallint,boolean),
  public.start_paigow_round_bpaigow01(uuid,uuid),public.choose_paigow_rob_bpaigow01(uuid,boolean,uuid),
  public.choose_paigow_multiplier_bpaigow01(uuid,integer,uuid),public.arrange_paigow_big_bpaigow01(uuid,smallint[],uuid) from authenticated;
notify pgrst,'reload schema';
commit;
