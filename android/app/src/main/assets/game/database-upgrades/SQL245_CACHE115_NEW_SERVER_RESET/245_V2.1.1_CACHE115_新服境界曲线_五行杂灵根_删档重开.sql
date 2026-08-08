-- 九霄问道 · SQL245 R2 · 新服境界曲线 / 初生灵根 / ADMIN9一键删档重开
-- 生产前提：V2.1.1 CACHE114/115；SQL244 已上线并 SQL244_GATE_PASSED。
-- 重要：之前生成的 SQL245 R1 尚未上线时，直接使用本 R2；R1 不再执行。
--
-- 本次内容：
-- 1) 写入删档新服使用的42阶段累计修为门槛；不做旧角色兼容。
-- 2) 新创建/新轮回角色的“初生主灵根”固定为【五行杂灵根】。
--    命格随机、本命五行随机继续由原 create_character_v1 / 轮回逻辑负责，本SQL不改概率。
--    洗灵等后续主动改灵根不受影响：触发器只作用于“角色刚创建时”的主灵根 INSERT。
-- 3) 保留 ADMIN9 R26 境界修为专页，后续仍可逐阶段调整。
-- 4) 新增 ADMIN9 R26 系统页“一键删档重开”：永久清空玩家游戏档案，不做备份。
--    保留 auth 登录账号、profiles、GM账号、系统配置/内容配置、SQL/版本状态。
--    重置审计只保留管理员、时间、总行数和表名，不保存玩家ID/姓名。
--
-- 注意：删档是主动运维例外，因此使用显式目标表 TRUNCATE ... RESTART IDENTITY；不使用CASCADE，
--       若存在未识别FK引用会直接失败并整事务回滚，避免误删保留配置；DBCAP03日常治理规则保持不变。

begin;

do $precheck$
declare v_root_count integer;
begin
  if to_regclass('public.realm_stages') is null or to_regclass('public.realms') is null then raise exception 'SQL245_REALM_SCHEMA_MISSING'; end if;
  if to_regclass('public.player_characters') is null then raise exception 'SQL245_PLAYER_CHARACTERS_MISSING'; end if;
  if to_regclass('public.character_spirit_roots') is null or to_regclass('public.spirit_roots') is null then raise exception 'SQL245_SPIRIT_ROOT_SCHEMA_MISSING'; end if;
  if to_regprocedure('public.v210_admin_guard()') is null then raise exception 'SQL245_ADMIN_GUARD_MISSING'; end if;
  if to_regprocedure('public.bcombat01_resolve_hit_v243(jsonb,jsonb,integer,integer,integer,double precision)') is null then raise exception 'SQL245_PRECHECK_SQL244_REQUIRED'; end if;
  select count(*) into v_root_count from public.spirit_roots where name='五行杂灵根';
  if v_root_count<>1 then raise exception 'SQL245_FIVE_ELEMENT_MIXED_ROOT_NOT_UNIQUE:%',v_root_count; end if;
end
$precheck$;

-- ============================================================
-- A. 新服累计修为曲线（42阶段）
-- ============================================================
with preset(realm_code,minor_level,cultivation_required) as (
  values
    ('mortal',1,0),
    ('qi_refining',1,10000),
    ('qi_refining',2,130000),
    ('qi_refining',3,260000),
    ('qi_refining',4,420000),
    ('qi_refining',5,590000),
    ('qi_refining',6,790000),
    ('qi_refining',7,1000000),
    ('qi_refining',8,1300000),
    ('qi_refining',9,1600000),
    ('foundation',1,2000000),
    ('foundation',2,4700000),
    ('foundation',3,7900000),
    ('foundation',4,11600000),
    ('golden_core',1,15800000),
    ('golden_core',2,25200000),
    ('golden_core',3,36100000),
    ('golden_core',4,48900000),
    ('nascent_soul',1,63100000),
    ('nascent_soul',2,77600000),
    ('nascent_soul',3,94300000),
    ('nascent_soul',4,114000000),
    ('spirit_transformation',1,136000000),
    ('spirit_transformation',2,213000000),
    ('spirit_transformation',3,303000000),
    ('spirit_transformation',4,408000000),
    ('void_refining',1,525000000),
    ('void_refining',2,773000000),
    ('void_refining',3,1060000000),
    ('void_refining',4,1400000000),
    ('body_integration',1,1770000000),
    ('body_integration',2,2350000000),
    ('body_integration',3,3020000000),
    ('body_integration',4,3800000000),
    ('mahayana',1,4670000000),
    ('mahayana',2,5820000000),
    ('mahayana',3,7140000000),
    ('mahayana',4,8690000000),
    ('tribulation',1,10420000000),
    ('tribulation',2,13270000000),
    ('tribulation',3,16400000000),
    ('tribulation',4,19920000000)
), changed as (
  update public.realm_stages rs
     set cultivation_required=p.cultivation_required
    from public.realms r, preset p
   where r.id=rs.realm_id
     and r.code=p.realm_code
     and rs.minor_level=p.minor_level
  returning rs.id
)
select count(*) from changed;

do $realm_gate$
declare v_match integer; v_total integer;
begin
  select count(*) into v_total from public.realm_stages rs join public.realms r on r.id=rs.realm_id where r.code in ('mortal','qi_refining','foundation','golden_core','nascent_soul','spirit_transformation','void_refining','body_integration','mahayana','tribulation');
  with preset(realm_code,minor_level,cultivation_required) as (values ('mortal',1,0),('qi_refining',1,10000),('qi_refining',2,130000),('qi_refining',3,260000),('qi_refining',4,420000),('qi_refining',5,590000),('qi_refining',6,790000),('qi_refining',7,1000000),('qi_refining',8,1300000),('qi_refining',9,1600000),('foundation',1,2000000),('foundation',2,4700000),('foundation',3,7900000),('foundation',4,11600000),('golden_core',1,15800000),('golden_core',2,25200000),('golden_core',3,36100000),('golden_core',4,48900000),('nascent_soul',1,63100000),('nascent_soul',2,77600000),('nascent_soul',3,94300000),('nascent_soul',4,114000000),('spirit_transformation',1,136000000),('spirit_transformation',2,213000000),('spirit_transformation',3,303000000),('spirit_transformation',4,408000000),('void_refining',1,525000000),('void_refining',2,773000000),('void_refining',3,1060000000),('void_refining',4,1400000000),('body_integration',1,1770000000),('body_integration',2,2350000000),('body_integration',3,3020000000),('body_integration',4,3800000000),('mahayana',1,4670000000),('mahayana',2,5820000000),('mahayana',3,7140000000),('mahayana',4,8690000000),('tribulation',1,10420000000),('tribulation',2,13270000000),('tribulation',3,16400000000),('tribulation',4,19920000000))
  select count(*) into v_match from preset p join public.realms r on r.code=p.realm_code join public.realm_stages rs on rs.realm_id=r.id and rs.minor_level=p.minor_level where rs.cultivation_required::numeric=p.cultivation_required::numeric;
  if v_match<>42 then raise exception 'SQL245_REALM_PRESET_GATE_FAILED:%/42',v_match; end if;
end
$realm_gate$;

-- ============================================================
-- B. 初生主灵根统一五行杂灵根；命格/本命五行继续随机
-- ============================================================
create or replace function public.enforce_newborn_five_element_mixed_root_v245()
returns trigger
language plpgsql
security definer
set search_path=''
as $$
declare
  v_root_id public.spirit_roots.id%type;
  v_created_at timestamptz;
  v_birth_year integer;
begin
  if not coalesce(new.is_primary,false) then return new; end if;
  select pc.created_at,pc.birth_year into v_created_at,v_birth_year from public.player_characters pc where pc.id=new.character_id;
  if not found then return new; end if;
  -- 只拦截“角色刚创建/刚轮回生成”这一笔主灵根；后续洗灵不受影响。
  if v_created_at < clock_timestamp()-interval '15 seconds' then return new; end if;
  select sr.id into v_root_id from public.spirit_roots sr where sr.name='五行杂灵根' limit 1;
  if v_root_id is null then raise exception 'NEWBORN_FIVE_ELEMENT_MIXED_ROOT_MISSING'; end if;
  new.spirit_root_id:=v_root_id;
  return new;
end
$$;

drop trigger if exists trg_newborn_five_element_mixed_root_v245 on public.character_spirit_roots;
create trigger trg_newborn_five_element_mixed_root_v245
before insert on public.character_spirit_roots
for each row execute function public.enforce_newborn_five_element_mixed_root_v245();

revoke all on function public.enforce_newborn_five_element_mixed_root_v245() from public,anon,authenticated;
comment on function public.enforce_newborn_five_element_mixed_root_v245() is 'SQL245 R2：仅新建/新轮回角色初生主灵根固定五行杂灵根；不改变命格与本命五行随机，不拦截后续洗灵。';

-- ============================================================
-- C. ADMIN9 R26 境界突破修为专页
-- ============================================================
create table if not exists public.admin9_realm_cultivation_audit_v245(
  id bigserial primary key, request_id uuid not null, admin_user_id uuid not null,
  action_code text not null check(action_code in ('update','rollback')),
  realm_stage_id text not null, realm_id text, realm_code text, realm_name text, stage_name text, minor_level integer,
  old_cultivation_required bigint not null, new_cultivation_required bigint not null,
  reason text not null, source_audit_id bigint, created_at timestamptz not null default clock_timestamp()
);
create index if not exists admin9_realm_cultivation_audit_v245_stage_idx on public.admin9_realm_cultivation_audit_v245(realm_stage_id,created_at desc);
create index if not exists admin9_realm_cultivation_audit_v245_created_idx on public.admin9_realm_cultivation_audit_v245(created_at desc);
create table if not exists public.admin9_realm_cultivation_requests_v245(
  request_id uuid primary key, admin_user_id uuid not null, operation text not null,
  payload jsonb not null default '{}'::jsonb, result jsonb not null, created_at timestamptz not null default clock_timestamp()
);
revoke all on table public.admin9_realm_cultivation_audit_v245 from public,anon,authenticated;
revoke all on table public.admin9_realm_cultivation_requests_v245 from public,anon,authenticated;

create or replace function public.admin9_list_realm_cultivation_v245()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_items jsonb; v_value_type text;
begin
  perform public.v210_admin_guard();
  select pg_catalog.format_type(a.atttypid,a.atttypmod) into v_value_type from pg_catalog.pg_attribute a where a.attrelid=to_regclass('public.realm_stages') and a.attname='cultivation_required' and not a.attisdropped;
  select coalesce(jsonb_agg(jsonb_build_object(
    'stage_id',rs.id::text,'realm_id',rs.realm_id::text,'realm_code',r.code,'realm_name',r.name,'major_order',r.major_order,
    'minor_level',rs.minor_level,'stage_name',rs.stage_name,'cultivation_required',rs.cultivation_required::text,
    'breakthrough_base_rate',rs.breakthrough_base_rate,'lifespan_bonus',rs.lifespan_bonus,
    'player_count',(select count(*) from public.player_characters pc where pc.realm_stage_id=rs.id)
  ) order by r.major_order,rs.minor_level,rs.id),'[]'::jsonb) into v_items from public.realm_stages rs join public.realms r on r.id=rs.realm_id;
  return jsonb_build_object('success',true,'sql',245,'revision','R2_NEW_SERVER_RESET','admin9','R26','value_type',coalesce(v_value_type,'unknown'),'items',v_items,'count',jsonb_array_length(v_items),'preset','NEW_SERVER_V1');
end $$;

create or replace function public.admin9_update_realm_cultivation_v245(p_changes jsonb,p_reason text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_admin uuid;v_existing jsonb;v_item jsonb;v_stage_id text;v_raw text;v_new_numeric numeric;v_new bigint;v_old bigint;v_realm_id text;v_realm_code text;v_realm_name text;v_stage_name text;v_minor integer;v_changed integer:=0;v_unchanged integer:=0;v_audit_id bigint;v_audit_ids jsonb:='[]'::jsonb;v_result jsonb;v_count integer;v_distinct_count integer;
begin
  perform public.v210_admin_guard();v_admin:=auth.uid();
  if v_admin is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  if length(trim(coalesce(p_reason,'')))<2 then raise exception 'ADMIN9_REALM_REASON_REQUIRED'; end if;
  if p_changes is null or jsonb_typeof(p_changes)<>'array' then raise exception 'ADMIN9_REALM_CHANGES_ARRAY_REQUIRED'; end if;
  v_count:=jsonb_array_length(p_changes); if v_count<1 then raise exception 'ADMIN9_REALM_NO_CHANGES'; end if; if v_count>200 then raise exception 'ADMIN9_REALM_TOO_MANY_CHANGES'; end if;
  select count(distinct trim(x->>'stage_id')) into v_distinct_count from jsonb_array_elements(p_changes) x; if v_distinct_count<>v_count then raise exception 'ADMIN9_REALM_DUPLICATE_STAGE_ID'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('sql245-realm:'||p_request_id::text,24501));
  select r.result into v_existing from public.admin9_realm_cultivation_requests_v245 r where r.request_id=p_request_id; if v_existing is not null then return v_existing||jsonb_build_object('duplicate_request',true); end if;
  for v_item in select value from jsonb_array_elements(p_changes) loop
    v_stage_id:=trim(coalesce(v_item->>'stage_id',''));v_raw:=trim(coalesce(v_item->>'cultivation_required',''));
    if v_stage_id='' then raise exception 'ADMIN9_REALM_STAGE_ID_REQUIRED'; end if;
    if v_raw='' or v_raw !~ '^[0-9]+$' then raise exception 'ADMIN9_REALM_CULTIVATION_INVALID:%',v_stage_id; end if;
    v_new_numeric:=v_raw::numeric; if v_new_numeric<0 or v_new_numeric>9223372036854775807::numeric then raise exception 'ADMIN9_REALM_CULTIVATION_OUT_OF_RANGE:%',v_stage_id; end if; v_new:=v_new_numeric::bigint;
    select rs.cultivation_required::bigint,rs.realm_id::text,r.code,r.name,rs.stage_name,rs.minor_level into v_old,v_realm_id,v_realm_code,v_realm_name,v_stage_name,v_minor from public.realm_stages rs join public.realms r on r.id=rs.realm_id where rs.id::text=v_stage_id for update of rs;
    if not found then raise exception 'ADMIN9_REALM_STAGE_NOT_FOUND:%',v_stage_id; end if;
    if v_old=v_new then v_unchanged:=v_unchanged+1;continue;end if;
    update public.realm_stages set cultivation_required=v_new where id::text=v_stage_id;
    insert into public.admin9_realm_cultivation_audit_v245(request_id,admin_user_id,action_code,realm_stage_id,realm_id,realm_code,realm_name,stage_name,minor_level,old_cultivation_required,new_cultivation_required,reason)
    values(p_request_id,v_admin,'update',v_stage_id,v_realm_id,v_realm_code,v_realm_name,v_stage_name,v_minor,v_old,v_new,trim(p_reason)) returning id into v_audit_id;
    v_audit_ids:=v_audit_ids||jsonb_build_array(v_audit_id);v_changed:=v_changed+1;
  end loop;
  if v_changed=0 then raise exception 'ADMIN9_REALM_NO_EFFECTIVE_CHANGES'; end if;
  v_result:=jsonb_build_object('success',true,'sql',245,'revision','R2_NEW_SERVER_RESET','admin9','R26','duplicate_request',false,'changed_count',v_changed,'unchanged_count',v_unchanged,'audit_ids',v_audit_ids,'next_sql',246);
  insert into public.admin9_realm_cultivation_requests_v245(request_id,admin_user_id,operation,payload,result) values(p_request_id,v_admin,'bulk_update',p_changes,v_result);
  return v_result;
end $$;

create or replace function public.admin9_list_realm_cultivation_audit_v245(p_limit integer default 50)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_limit integer:=least(200,greatest(1,coalesce(p_limit,50)));v_items jsonb;
begin
  perform public.v210_admin_guard();
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc,x.id desc),'[]'::jsonb) into v_items from (select a.* from public.admin9_realm_cultivation_audit_v245 a order by a.created_at desc,a.id desc limit v_limit) x;
  return jsonb_build_object('success',true,'items',v_items,'count',jsonb_array_length(v_items));
end $$;

revoke all on function public.admin9_list_realm_cultivation_v245() from public,anon; grant execute on function public.admin9_list_realm_cultivation_v245() to authenticated;
revoke all on function public.admin9_update_realm_cultivation_v245(jsonb,text,uuid) from public,anon; grant execute on function public.admin9_update_realm_cultivation_v245(jsonb,text,uuid) to authenticated;
revoke all on function public.admin9_list_realm_cultivation_audit_v245(integer) from public,anon; grant execute on function public.admin9_list_realm_cultivation_audit_v245(integer) to authenticated;

-- ============================================================
-- D. 一键删档重开：目标表自动识别 + 只读预览 + 永久执行
-- ============================================================
create table if not exists public.admin9_game_reset_audit_v245(
  id bigserial primary key,
  request_id uuid not null unique,
  admin_user_id uuid not null,
  reason text not null,
  player_count_before bigint not null,
  total_rows_before bigint not null,
  target_table_count integer not null,
  target_tables jsonb not null,
  auth_accounts_deleted boolean not null default false,
  player_backup_created boolean not null default false,
  created_at timestamptz not null default clock_timestamp()
);
revoke all on table public.admin9_game_reset_audit_v245 from public,anon,authenticated;

create or replace function public.admin9_game_reset_target_tables_v245()
returns table(table_name text)
language sql stable security definer set search_path='' as $$
with recursive
rels as (
  select c.oid,c.relname
  from pg_catalog.pg_class c
  join pg_catalog.pg_namespace n on n.oid=c.relnamespace
  where n.nspname='public' and c.relkind in ('r','p')
),
-- 直接带角色/账号归属字段的表，视为玩家档案数据。
owned as (
  select distinct r.oid
  from rels r
  join pg_catalog.pg_attribute a on a.attrelid=r.oid and a.attnum>0 and not a.attisdropped
  where a.attname in (
    'character_id','player_character_id','owner_character_id','challenger_character_id','target_character_id',
    'attacker_character_id','defender_character_id','creator_character_id','member_character_id',
    'user_id','owner_user_id','creator_user_id','seller_user_id','buyer_user_id'
  )
),
-- 无直接角色外键但属于运行态/历史态的玩家系统表。
runtime_named as (
  select oid from rels
  where (
       relname ~ '^(world_boss_|battle_|paigow_|casino_|duel_|fish_shrimp_|spirit_dice_)'
       or relname in (
         'history_logs','jiuxiao_world_events','opportunity_v3_results','opportunity_v3_effect_ledger',
         'opportunity_v4_settlement_batches','equipment_v210_request_ledger'
       )
     )
    and relname !~ '(settings|config|definition|definitions|template|templates|catalog|grade_config|level_config|attribute_pool)'
),
-- 新服重开时旧GM操作/请求历史也清空，避免旧玩家ID/姓名残留。
-- 但本次 reset 审计本身必须保留，并且任何 settings/config/catalog 等配置表都不进入。
admin_history as (
  select oid from rels
  where relname ~ '^admin9_.*(audit|request)'
    and relname <> 'admin9_game_reset_audit_v245'
),
seed0 as (
  select oid from owned
  union select oid from runtime_named
  union select oid from admin_history
  union select to_regclass('public.player_characters')::oid
),
seed as (
  select r.oid
  from seed0 s
  join rels r on r.oid=s.oid
  where r.relname not in (
    'profiles','game_worlds','realms','realm_stages','spirit_roots','fates','techniques','item_definitions','opportunity_results',
    'jiuxiao_app_release_control','jiuxiao_auto_cleanup_config_v210','jiuxiao_cleanup_runs_v210','jiuxiao_cleanup_monthly_summary_v210','jiuxiao_db_health_snapshots_v242',
    'combat_realm_stats_bcombat01','battle_challenge_settings_bcombat01','world_boss_settings_bwboss01','world_boss_definitions_bwboss01',
    'equipment_templates_bequipment01','equipment_socket_settings_v210','equipment_socket_level_config_v210','equipment_upgrade_settings_v210',
    'secret_realm_settings_bsecretrealm01','secret_realm_monsters_bsecretrealm01','secret_realm_material_drops_bsecretrealm01','secret_realm_equipment_drops_bsecretrealm01',
    'admin9_game_reset_audit_v245'
  )
  and r.relname !~ '^sect_event_templates'
),
-- 从玩家根表/运行表向下追所有FK子表；只追“引用玩家数据的子表”，绝不把玩家表引用的境界/世界等父配置表加入。
deps(oid) as (
  select oid from seed
  union
  select c.conrelid
  from pg_catalog.pg_constraint c
  join deps d on d.oid=c.confrelid
  join rels rr on rr.oid=c.conrelid
  where c.contype='f'
)
select distinct r.relname::text
from deps d
join rels r on r.oid=d.oid
where r.relname not in (
    'profiles','game_worlds','realms','realm_stages','spirit_roots','fates','techniques','item_definitions','opportunity_results',
    'jiuxiao_app_release_control','jiuxiao_auto_cleanup_config_v210','jiuxiao_cleanup_runs_v210','jiuxiao_cleanup_monthly_summary_v210','jiuxiao_db_health_snapshots_v242',
    'combat_realm_stats_bcombat01','battle_challenge_settings_bcombat01','world_boss_settings_bwboss01','world_boss_definitions_bwboss01',
    'equipment_templates_bequipment01','equipment_socket_settings_v210','equipment_socket_level_config_v210','equipment_upgrade_settings_v210',
    'secret_realm_settings_bsecretrealm01','secret_realm_monsters_bsecretrealm01','secret_realm_material_drops_bsecretrealm01','secret_realm_equipment_drops_bsecretrealm01',
    'admin9_game_reset_audit_v245'
  )
  and r.relname !~ '^sect_event_templates'
order by 1
$$;
revoke all on function public.admin9_game_reset_target_tables_v245() from public,anon,authenticated;

create or replace function public.admin9_game_reset_preview_v245()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare r record;v_count bigint;v_total bigint:=0;v_tables jsonb:='[]'::jsonb;v_players bigint;
begin
  perform public.v210_admin_guard();
  select count(*) into v_players from public.player_characters;
  for r in select table_name from public.admin9_game_reset_target_tables_v245() loop
    execute pg_catalog.format('select count(*) from public.%I',r.table_name) into v_count;
    v_total:=v_total+v_count;
    v_tables:=v_tables||jsonb_build_array(jsonb_build_object('table',r.table_name,'rows',v_count));
  end loop;
  return jsonb_build_object(
    'success',true,'sql',245,'revision','R2_NEW_SERVER_RESET','mode','PREVIEW_ONLY',
    'player_count',v_players,'target_table_count',jsonb_array_length(v_tables),'total_rows',v_total,'tables',v_tables,
    'will_delete','全部玩家游戏档案及其历史/战斗/宗门/秘境/赌场等玩家状态','will_keep','auth登录账号、profiles、GM账号、系统配置、内容配置、版本/SQL状态',
    'backup_created',false,'confirm_text','永久删档重开'
  );
end $$;

create or replace function public.admin9_game_reset_v245(p_confirm_text text,p_expected_player_count bigint,p_reason text,p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_admin uuid;v_current bigint;v_total bigint:=0;v_count bigint;v_table_count integer;v_list text;v_tables jsonb;v_existing jsonb;r record;v_result jsonb;
begin
  perform public.v210_admin_guard(); v_admin:=auth.uid();
  if v_admin is null then raise exception 'AUTH_REQUIRED'; end if;
  if p_request_id is null then raise exception 'REQUEST_ID_REQUIRED'; end if;
  if trim(coalesce(p_confirm_text,''))<>'永久删档重开' then raise exception 'ADMIN9_RESET_CONFIRM_TEXT_MISMATCH'; end if;
  if length(trim(coalesce(p_reason,'')))<4 then raise exception 'ADMIN9_RESET_REASON_REQUIRED'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('admin9-game-reset-v245',24599));

  select jsonb_build_object('success',true,'duplicate_request',true,'reset_id',a.id,'player_count_before',a.player_count_before,'total_rows_before',a.total_rows_before,'next_sql',246)
  into v_existing from public.admin9_game_reset_audit_v245 a where a.request_id=p_request_id;
  if v_existing is not null then return v_existing; end if;

  lock table public.player_characters in access exclusive mode;
  select count(*) into v_current from public.player_characters;
  if p_expected_player_count is null or p_expected_player_count<>v_current then raise exception 'ADMIN9_RESET_PLAYER_COUNT_CHANGED:%:%',p_expected_player_count,v_current; end if;

  v_tables:='[]'::jsonb;
  for r in select table_name from public.admin9_game_reset_target_tables_v245() loop
    execute pg_catalog.format('select count(*) from public.%I',r.table_name) into v_count;
    v_total:=v_total+v_count;
    v_tables:=v_tables||jsonb_build_array(r.table_name);
  end loop;
  v_table_count:=jsonb_array_length(v_tables);
  select string_agg(pg_catalog.format('public.%I',table_name),', ' order by table_name) into v_list from public.admin9_game_reset_target_tables_v245();
  if coalesce(v_list,'')='' then raise exception 'ADMIN9_RESET_TARGET_TABLES_EMPTY'; end if;

  execute 'truncate table '||v_list||' restart identity';

  if (select count(*) from public.player_characters)<>0 then raise exception 'ADMIN9_RESET_VERIFY_PLAYER_CHARACTERS_NOT_EMPTY'; end if;
  for r in select table_name from public.admin9_game_reset_target_tables_v245() loop
    execute pg_catalog.format('select count(*) from public.%I',r.table_name) into v_count;
    if v_count<>0 then raise exception 'ADMIN9_RESET_VERIFY_TABLE_NOT_EMPTY:%:%',r.table_name,v_count; end if;
  end loop;

  insert into public.admin9_game_reset_audit_v245(request_id,admin_user_id,reason,player_count_before,total_rows_before,target_table_count,target_tables,auth_accounts_deleted,player_backup_created)
  values(p_request_id,v_admin,trim(p_reason),v_current,v_total,v_table_count,v_tables,false,false)
  returning jsonb_build_object('success',true,'sql',245,'revision','R2_NEW_SERVER_RESET','reset_id',id,'player_count_before',player_count_before,'total_rows_before',total_rows_before,'target_table_count',target_table_count,'auth_accounts_deleted',false,'player_backup_created',false,'gate','GAME_RESET_COMPLETED','next_sql',246) into v_result;
  return v_result;
end $$;

create or replace function public.admin9_list_game_reset_audit_v245(p_limit integer default 20)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare v_items jsonb;
begin
  perform public.v210_admin_guard();
  select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc),'[]'::jsonb) into v_items from (select id,request_id,admin_user_id,reason,player_count_before,total_rows_before,target_table_count,auth_accounts_deleted,player_backup_created,created_at from public.admin9_game_reset_audit_v245 order by created_at desc limit least(100,greatest(1,coalesce(p_limit,20)))) x;
  return jsonb_build_object('success',true,'items',v_items);
end $$;

revoke all on function public.admin9_game_reset_preview_v245() from public,anon; grant execute on function public.admin9_game_reset_preview_v245() to authenticated;
revoke all on function public.admin9_game_reset_v245(text,bigint,text,uuid) from public,anon; grant execute on function public.admin9_game_reset_v245(text,bigint,text,uuid) to authenticated;
revoke all on function public.admin9_list_game_reset_audit_v245(integer) from public,anon; grant execute on function public.admin9_list_game_reset_audit_v245(integer) to authenticated;

comment on function public.admin9_game_reset_v245(text,bigint,text,uuid) is 'SQL245 R2 / ADMIN9 R26：不可逆玩家游戏档案删档；不备份；保留auth账号/GM/系统和内容配置。';

-- ============================================================
-- E. SQL245 R2 安装门禁（SQL Editor不调用需要登录态的GM RPC）
-- ============================================================
do $gate$
declare v_reset_def text;v_root_def text;v_match integer;v_targets integer;
begin
  if to_regprocedure('public.admin9_list_realm_cultivation_v245()') is null or to_regprocedure('public.admin9_update_realm_cultivation_v245(jsonb,text,uuid)') is null then raise exception 'SQL245_GATE_REALM_RPC_MISSING'; end if;
  if to_regprocedure('public.admin9_game_reset_preview_v245()') is null or to_regprocedure('public.admin9_game_reset_v245(text,bigint,text,uuid)') is null then raise exception 'SQL245_GATE_RESET_RPC_MISSING'; end if;
  if to_regprocedure('public.enforce_newborn_five_element_mixed_root_v245()') is null then raise exception 'SQL245_GATE_NEWBORN_ROOT_FUNCTION_MISSING'; end if;
  if not exists(select 1 from pg_catalog.pg_trigger where tgrelid=to_regclass('public.character_spirit_roots') and tgname='trg_newborn_five_element_mixed_root_v245' and not tgisinternal) then raise exception 'SQL245_GATE_NEWBORN_ROOT_TRIGGER_MISSING'; end if;
  v_reset_def:=lower(pg_get_functiondef(to_regprocedure('public.admin9_game_reset_v245(text,bigint,text,uuid)')));
  if position('v210_admin_guard' in v_reset_def)=0 or position('永久删档重开' in v_reset_def)=0 or position('truncate table' in v_reset_def)=0 then raise exception 'SQL245_GATE_RESET_SAFETY_MISSING'; end if;
  if position('player_backup_created' in v_reset_def)=0 then raise exception 'SQL245_GATE_NO_BACKUP_MARKER_MISSING'; end if;
  select count(*) into v_targets from public.admin9_game_reset_target_tables_v245(); if v_targets<1 then raise exception 'SQL245_GATE_RESET_TARGETS_EMPTY'; end if;
  if not exists(select 1 from public.admin9_game_reset_target_tables_v245() where table_name='player_characters') then raise exception 'SQL245_GATE_PLAYER_CHARACTERS_NOT_TARGETED'; end if;
  if exists(select 1 from public.admin9_game_reset_target_tables_v245() where table_name in ('profiles','realms','realm_stages','spirit_roots','fates','techniques','item_definitions','jiuxiao_app_release_control','admin9_game_reset_audit_v245')) then raise exception 'SQL245_GATE_PRESERVED_TABLE_TARGETED'; end if;
  with preset(realm_code,minor_level,cultivation_required) as (values ('mortal',1,0),('qi_refining',1,10000),('qi_refining',2,130000),('qi_refining',3,260000),('qi_refining',4,420000),('qi_refining',5,590000),('qi_refining',6,790000),('qi_refining',7,1000000),('qi_refining',8,1300000),('qi_refining',9,1600000),('foundation',1,2000000),('foundation',2,4700000),('foundation',3,7900000),('foundation',4,11600000),('golden_core',1,15800000),('golden_core',2,25200000),('golden_core',3,36100000),('golden_core',4,48900000),('nascent_soul',1,63100000),('nascent_soul',2,77600000),('nascent_soul',3,94300000),('nascent_soul',4,114000000),('spirit_transformation',1,136000000),('spirit_transformation',2,213000000),('spirit_transformation',3,303000000),('spirit_transformation',4,408000000),('void_refining',1,525000000),('void_refining',2,773000000),('void_refining',3,1060000000),('void_refining',4,1400000000),('body_integration',1,1770000000),('body_integration',2,2350000000),('body_integration',3,3020000000),('body_integration',4,3800000000),('mahayana',1,4670000000),('mahayana',2,5820000000),('mahayana',3,7140000000),('mahayana',4,8690000000),('tribulation',1,10420000000),('tribulation',2,13270000000),('tribulation',3,16400000000),('tribulation',4,19920000000))
  select count(*) into v_match from preset p join public.realms r on r.code=p.realm_code join public.realm_stages rs on rs.realm_id=r.id and rs.minor_level=p.minor_level where rs.cultivation_required::numeric=p.cultivation_required::numeric;
  if v_match<>42 then raise exception 'SQL245_GATE_REALM_PRESET_MISMATCH:%',v_match; end if;
end
$gate$;

commit;
notify pgrst,'reload schema';

select jsonb_build_object(
  'success',true,'sql',245,'gate','SQL245_GATE_PASSED','revision','R2_NEW_SERVER_RESET',
  'realm_preset','NEW_SERVER_V1_42_STAGES','newborn_spirit_root','五行杂灵根',
  'fate_rule','RANDOM_UNCHANGED','innate_element_rule','RANDOM_UNCHANGED',
  'admin9','R26','reset_feature','PERMANENT_PLAYER_GAME_DATA_WIPE_NO_BACKUP',
  'auth_accounts_preserved',true,'release_changed',false,'next_sql',246
) as sql245_gate_result;
