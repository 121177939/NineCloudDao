-- 九霄问道 · V2.1.1 CACHE109 · SQL238
-- 装备详情孔位展示客户端热修发布准备。
-- 本SQL不改变装备数值、孔位规则、世界BOSS奖励或GM配置。
-- 为兼容此前可能尚未执行的SQL237，同时幂等确保世界BOSS镇魔令 numeric 发奖重载存在。
-- 执行顺序：先部署V2.1.1 CACHE109游戏文件，再执行本SQL，成功后执行配套制度门禁SQL。

begin;
lock table public.jiuxiao_app_release_control in row exclusive mode;

do $precheck$
declare v_cache integer; v_release text;
begin
  if to_regclass('public.jiuxiao_app_release_control') is null then
    raise exception 'SQL238_PRECHECK_RELEASE_CONTROL_MISSING';
  end if;
  if to_regclass('public.equipment_socket_affixes_v210') is null
     or to_regclass('public.equipment_socket_level_config_v210') is null then
    raise exception 'SQL238_PRECHECK_EQUIPMENT_SOCKET_V210_MISSING_SQL233_REQUIRED';
  end if;
  if to_regprocedure('public.get_equipment_forge_overview_v210()') is null then
    raise exception 'SQL238_PRECHECK_FORGE_OVERVIEW_RPC_MISSING_SQL233_REQUIRED';
  end if;
  if to_regprocedure('public.bwboss01_grant_token(uuid,bigint)') is null then
    raise exception 'SQL238_PRECHECK_WBOSS_BIGINT_GRANT_MISSING_SQL233_REQUIRED';
  end if;
  select release_name,cache_epoch into v_release,v_cache
  from public.jiuxiao_app_release_control where singleton_id=1 for update;
  if not found then raise exception 'SQL238_PRECHECK_RELEASE_ROW_MISSING'; end if;
  if coalesce(v_cache,-1)>109 then
    raise exception 'SQL238_PRECHECK_NEWER_RELEASE_BLOCK:%/%',v_release,v_cache;
  end if;
end
$precheck$;

-- 幂等吸收SQL237：如果已执行SQL237，则只是create or replace同等兼容入口；若未执行，则本SQL补齐。
create or replace function public.bwboss01_grant_token(p_character_id uuid,p_amount numeric)
returns bigint
language plpgsql
security definer
set search_path=''
as $$
declare v_amount bigint;
begin
  if p_amount is null or p_amount<=0 then return 0; end if;
  v_amount:=floor(p_amount)::bigint;
  if v_amount<=0 then return 0; end if;
  return public.bwboss01_grant_token(p_character_id,v_amount);
end $$;

comment on function public.bwboss01_grant_token(uuid,numeric) is
'SQL238 V2.1.1 CACHE109 EQUIPMENT_DETAIL1: retains BWBOSS numeric->bigint token compatibility while releasing client equipment socket detail UI.';
revoke all on function public.bwboss01_grant_token(uuid,numeric) from public,anon,authenticated;

commit;
notify pgrst,'reload schema';

select jsonb_build_object(
  'success',true,
  'sql',238,
  'feature','EQUIPMENT_DETAIL_SOCKET_LIST_CLIENT_RELEASE',
  'forge_overview_ready',to_regprocedure('public.get_equipment_forge_overview_v210()') is not null,
  'boss_token_numeric_compat',to_regprocedure('public.bwboss01_grant_token(uuid,numeric)') is not null,
  'release_control_unchanged',(select release_name from public.jiuxiao_app_release_control where singleton_id=1),
  'cache_epoch_unchanged',(select cache_epoch from public.jiuxiao_app_release_control where singleton_id=1),
  'next','RUN_V2.1.1_CACHE109_SQL238_GATE',
  'next_sql',239
) as sql238_install_result;
