-- V0.13.0超额修为校正审计（只读）
select l.character_id,pc.name,l.source_code,l.cultivation_before,l.cultivation_cap,l.cultivation_after,l.discarded_amount,l.created_at
from public.cultivation_cap_adjustment_logs l join public.player_characters pc on pc.id=l.character_id
order by l.created_at desc,l.id desc;

select count(*) remaining_over_cap
from public.player_characters pc cross join lateral(select public.character_cultivation_cap_v1(pc.realm_stage_id) cap) x
where x.cap is not null and pc.cultivation>x.cap;
