-- 九霄问道 V1.1 FIX1：安全随机兼容修复（V1.2完整包补齐）
-- 修复生产库无法解析 gen_random_bytes(integer) 的问题。
-- 使用数据库已经依赖的 gen_random_uuid() 提取32位随机值，并继续采用拒绝采样消除取模偏差。
begin;

create or replace function public.casino_secure_random_int_v1(p_upper integer)
returns integer
language plpgsql
volatile
security definer
set search_path=pg_catalog,public,extensions,pg_temp
as $$
declare
  v_uuid uuid;
  v_bytes bytea;
  v_raw bigint;
  v_range constant bigint:=4294967296;
  v_limit bigint;
begin
  if p_upper is null or p_upper<1 then raise exception 'CASINO_RANDOM_UPPER_INVALID'; end if;
  if p_upper::bigint>v_range then raise exception 'CASINO_RANDOM_UPPER_TOO_LARGE'; end if;
  v_limit:=(v_range/p_upper::bigint)*p_upper::bigint;
  loop
    v_uuid:=gen_random_uuid();
    v_bytes:=decode(substr(replace(v_uuid::text,'-',''),1,8),'hex');
    v_raw:=get_byte(v_bytes,0)::bigint*16777216
          +get_byte(v_bytes,1)::bigint*65536
          +get_byte(v_bytes,2)::bigint*256
          +get_byte(v_bytes,3)::bigint;
    if v_raw<v_limit then return (v_raw%p_upper)::integer; end if;
  end loop;
end;
$$;

revoke all on function public.casino_secure_random_int_v1(integer) from public,anon,authenticated;
comment on function public.casino_secure_random_int_v1(integer) is
  'V1.1 FIX1兼容修复：基于gen_random_uuid的32位拒绝采样；不依赖gen_random_bytes搜索路径。';
notify pgrst,'reload schema';
commit;
