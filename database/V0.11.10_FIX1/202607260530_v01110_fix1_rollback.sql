-- V0.11.10 FIX1完整回滚：恢复升级前灵根值及claim/get/attempt三个关键函数定义。
begin;

drop function if exists public.get_breakthrough_status_v1();
drop function if exists public.attempt_breakthrough_v1();

update public.spirit_roots sr
set cultivation_multiplier=b.cultivation_multiplier,
    event_luck_bonus=b.event_luck_bonus
from ncd_release_backup.v01110_fix1_spirit_roots b
where b.id=sr.id;

update public.realm_stages rs
set breakthrough_base_rate=b.breakthrough_base_rate
from ncd_release_backup.v01110_fix1_realm_rates b
where b.id=rs.id;

do $$
declare r record;
begin
  for r in
    select definition from ncd_release_backup.v01110_fix1_functions
    order by case
      when signature like 'get_breakthrough_status_v1%' then 1
      when signature like 'attempt_breakthrough_v1%' then 2
      when signature like 'claim_cultivation_v1%' then 3
      else 9 end
  loop execute r.definition; end loop;
end;
$$;

grant execute on function public.get_breakthrough_status_v1() to authenticated;
grant execute on function public.attempt_breakthrough_v1() to authenticated;
grant execute on function public.claim_cultivation_v1() to authenticated;

drop function if exists public.get_spirit_root_coefficients_v1();
drop function if exists public.character_spirit_root_combat_multiplier_v1(uuid);
drop function if exists public.realm_base_cultivation_rate_v1(smallint);
drop function if exists public.realm_stage_position_v1(smallint);
drop table if exists public.character_breakthrough_states;
alter table public.spirit_roots drop column if exists combat_multiplier;

drop schema if exists ncd_release_backup cascade;
commit;
notify pgrst,'reload schema';
