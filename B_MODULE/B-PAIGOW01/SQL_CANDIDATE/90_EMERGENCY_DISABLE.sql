-- B-PAIGOW01 / 90_EMERGENCY_DISABLE.sql
update public.paigow_rooms_bpaigow01 set status='disabled',closed_at=now(),updated_at=now() where status in('waiting','playing');
revoke execute on function public.create_paigow_room_bpaigow01(text,text,text,text,bigint) from authenticated;
revoke execute on function public.join_paigow_room_bpaigow01(uuid,smallint,boolean) from authenticated;
