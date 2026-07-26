-- V0.11.10 FIX1 只读预检查：不会修改任何数据。
select table_name,column_name,data_type,udt_name
from information_schema.columns
where table_schema='public'
  and (table_name,column_name) in (
    ('spirit_roots','id'),('realm_stages','id'),('realms','id'),
    ('player_characters','realm_stage_id'),('character_spirit_roots','spirit_root_id')
  )
order by table_name,column_name;

select r.id,r.code,r.name,r.major_order,count(rs.id) as stage_count
from public.realms r left join public.realm_stages rs on rs.realm_id=r.id
where r.code='nascent_soul' or r.name like '元婴%'
group by r.id,r.code,r.name,r.major_order;
