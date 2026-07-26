-- 《九霄问道》V0.14.0 FIX3
-- 功能：当管理员在 Supabase Authentication > Users 中直接删除账号时，
--       自动在“九霄界闻”写入一条中性的【名籍除却】播报。
-- 说明：Supabase 的直接删除按钮没有“处罚原因”输入项，因此本触发器不会擅自指控玩家违规。
--       需要指定“扰乱因果 / 篡改命数”等原因时，仍应先调用 admin_publish_account_erasure_v1，再删除账号。
-- 安全：触发器采用异常隔离；即使界闻写入异常，也不会阻断账号删除。

begin;

-- 必要对象检查：FIX2 必须已经成功部署。
do $$
begin
  if to_regclass('public.jiuxiao_world_events') is null then
    raise exception 'FIX3_REQUIRES_V0140_FIX2: public.jiuxiao_world_events 不存在';
  end if;
  if to_regclass('public.jiuxiao_world_event_settings') is null then
    raise exception 'FIX3_REQUIRES_V0140_FIX2: public.jiuxiao_world_event_settings 不存在';
  end if;
  if to_regprocedure('public.world_event_publish_v0140(uuid,integer,text,smallint,uuid,text,text,text,text,text,jsonb,boolean,timestamptz)') is null then
    raise exception 'FIX3_REQUIRES_V0140_FIX2: world_event_publish_v0140 不存在';
  end if;
  if to_regclass('auth.users') is null then
    raise exception 'AUTH_USERS_MISSING: auth.users 不存在';
  end if;
end
$$;

create or replace function public.world_event_from_auth_user_delete_v0140()
returns trigger
language plpgsql
security definer
set search_path = public, auth, pg_temp
as $$
declare
  v_character record;
  v_enabled boolean := true;
  v_fallback_world_id uuid;
  v_fallback_world_year integer;
begin
  -- 必须始终允许 auth.users 的 DELETE 继续执行。
  begin
    select coalesce(s.enabled, true) and coalesce(s.admin_enabled, true)
      into v_enabled
    from public.jiuxiao_world_event_settings s
    where s.singleton_id = 1;

    if not coalesce(v_enabled, true) then
      return old;
    end if;

    select gw.id, gw.current_year
      into v_fallback_world_id, v_fallback_world_year
    from public.game_worlds gw
    order by gw.id
    limit 1;

    -- BEFORE DELETE 时角色记录尚未被级联删除，因此可以保存角色名快照。
    for v_character in
      select
        pc.id as character_id,
        pc.name as character_name,
        coalesce(pc.world_id, v_fallback_world_id) as world_id,
        coalesce(gw.current_year, v_fallback_world_year) as world_year
      from public.player_characters pc
      left join public.game_worlds gw on gw.id = pc.world_id
      where pc.user_id = old.id
      order by pc.created_at desc
    loop
      perform public.world_event_publish_v0140(
        v_character.world_id,
        v_character.world_year,
        'admin_account_erasure_auto'::text,
        4::smallint,
        v_character.character_id,
        v_character.character_name,
        '名籍除却'::text,
        format('修士【%s】命籍已被天道收回，其存在痕迹自九霄界中渐次消散。', v_character.character_name),
        'auth.users'::text,
        format('delete:%s:%s', old.id, v_character.character_id),
        jsonb_build_object(
          'deletion_source', 'supabase_auth_users',
          'user_id', old.id,
          'character_id', v_character.character_id,
          'automatic', true
        ),
        true,
        null::timestamptz
      );
    end loop;
  exception
    when others then
      -- 账号删除优先；界闻异常只记警告，不得阻断 Auth 删除事务。
      raise warning 'V0.14.0 FIX3 account-erasure broadcast skipped: %', sqlerrm;
  end;

  return old;
end;
$$;

revoke all on function public.world_event_from_auth_user_delete_v0140()
  from public, anon, authenticated;

drop trigger if exists trg_world_event_auth_user_delete_v0140 on auth.users;
create trigger trg_world_event_auth_user_delete_v0140
before delete on auth.users
for each row
execute function public.world_event_from_auth_user_delete_v0140();

comment on function public.world_event_from_auth_user_delete_v0140()
  is 'V0.14.0 FIX3：监听 auth.users 直接删除，在角色级联清除前保存名称快照并写入中性名籍除却播报；异常不阻断删号。';

commit;

-- 执行结果检查：应返回三行且 ok 全为 true。
select 'delete_trigger' as name,
       exists (
         select 1
         from pg_trigger t
         join pg_class c on c.oid = t.tgrelid
         join pg_namespace n on n.oid = c.relnamespace
         where n.nspname = 'auth'
           and c.relname = 'users'
           and t.tgname = 'trg_world_event_auth_user_delete_v0140'
           and not t.tgisinternal
       ) as ok,
       'auth.users 删除触发器存在' as detail
union all
select 'delete_trigger_function',
       to_regprocedure('public.world_event_from_auth_user_delete_v0140()') is not null,
       '账号删除播报函数存在'
union all
select 'feed_opening_still_exists',
       exists (
         select 1 from public.jiuxiao_world_events
         where event_type = 'system_world_feed_open'
       ),
       '既有九霄界闻数据仍然保留';
