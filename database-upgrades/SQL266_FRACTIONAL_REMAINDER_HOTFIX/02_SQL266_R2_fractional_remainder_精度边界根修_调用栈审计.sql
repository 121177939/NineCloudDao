-- 九霄问道 SQL266 R2 HOTFIX
-- 主题：fractional_remainder 边界根修（修正 SQL265 R2 的 0.999999999999 在低精度列上被舍入为 1.000000）
-- 基线：V2.2.0 CACHE137 / SQL265 R2 HOTFIX / SQL266 R1 已部署
--
-- 说明：
-- 1) 自动读取 character_cultivation_state.fractional_remainder 的 numeric_scale；
-- 2) 计算该列能表示的最大合法余数：1 - 10^(-scale)；
-- 3) 修正 SQL266 R1 写入保护：精确 1 不再归零，而是压到安全上限；
-- 4) 动态修补当前数据库里的 public.claim_cultivation_v1 定义，
--    将 SQL265 R2 中硬编码的 0.999999999999 替换为当前列安全上限；
-- 5) 给审计表增加 call_context，今后如果仍有其它 RPC 写出非法余数，可直接看到调用栈；
-- 6) 不修改玩家 cultivation 总修为，不动灵根、背包、道侣等业务数据。

begin;

-- ---------- PRECHECK ----------
do $precheck$
declare
  v_type text;
  v_scale integer;
begin
  if to_regclass('public.character_cultivation_state') is null then
    raise exception 'SQL266_R2_PRECHECK_CHARACTER_CULTIVATION_STATE_MISSING';
  end if;

  select data_type, numeric_scale
    into v_type, v_scale
  from information_schema.columns
  where table_schema='public'
    and table_name='character_cultivation_state'
    and column_name='fractional_remainder';

  if v_type is null then
    raise exception 'SQL266_R2_PRECHECK_FRACTIONAL_REMAINDER_MISSING';
  end if;

  if v_type <> 'numeric' then
    raise exception 'SQL266_R2_PRECHECK_UNEXPECTED_TYPE:%', v_type;
  end if;

  if v_scale is null or v_scale < 1 or v_scale > 30 then
    raise exception 'SQL266_R2_PRECHECK_UNEXPECTED_NUMERIC_SCALE:%', v_scale;
  end if;
end
$precheck$;

-- ---------- 审计表补充调用栈 ----------
alter table public.cultivation_fractional_remainder_audit_v266
  add column if not exists call_context text;

-- ---------- 当前表加锁，避免切换保护逻辑时并发写 ----------
lock table public.character_cultivation_state in share row exclusive mode;

-- ---------- 根据真实 numeric_scale 重建写入保护 ----------
do $rebuild_guard$
declare
  v_scale integer;
  v_cap numeric;
  v_sql text;
begin
  select numeric_scale
    into v_scale
  from information_schema.columns
  where table_schema='public'
    and table_name='character_cultivation_state'
    and column_name='fractional_remainder';

  v_cap := 1::numeric - power(10::numeric, -v_scale);

  v_sql := format($fn$
create or replace function public.normalize_cultivation_fractional_remainder_v266()
returns trigger
language plpgsql
security definer
set search_path=''
as $body$
declare
  v_old numeric;
  v_new numeric;
  v_frac numeric;
  v_context text;
  v_cap constant numeric := %L::numeric;
begin
  v_old := new.fractional_remainder;

  if v_old is null
     or v_old::text in ('NaN','Infinity','-Infinity') then
    v_new := 0::numeric;

  elsif v_old < 0 then
    v_new := 0::numeric;

  -- 关键修复：
  -- SQL265 R2 可能计算出 0.999999999999，
  -- 若列只有 6 位小数，进入 BEFORE trigger 前已被列类型舍入成 1.000000。
  -- 这种“精确 1”应压到该列最大合法值，而不是归零。
  elsif v_old = 1::numeric then
    v_new := v_cap;

  elsif v_old > 1::numeric then
    -- 对真正大于 1 的异常值，只保留其小数部分；
    -- 若恰好为整数，则回到 0，避免伪造额外修为。
    v_frac := v_old - floor(v_old);
    v_new := least(v_cap, greatest(0::numeric, v_frac));

  else
    v_new := least(v_cap, greatest(0::numeric, v_old));
  end if;

  if v_new is distinct from v_old then
    get diagnostics v_context = pg_context;

    insert into public.cultivation_fractional_remainder_audit_v266(
      character_id,
      old_value,
      normalized_value,
      source,
      call_context
    )
    values(
      new.character_id,
      v_old,
      v_new,
      'SQL266_R2_WRITE_GUARD',
      v_context
    );

    new.fractional_remainder := v_new;
  end if;

  return new;
end
$body$;
$fn$, v_cap::text);

  execute v_sql;

  raise notice 'SQL266_R2_SAFE_CAP scale=% cap=%', v_scale, v_cap;
end
$rebuild_guard$;

revoke all on function public.normalize_cultivation_fractional_remainder_v266()
from public, anon, authenticated;

drop trigger if exists trg_normalize_cultivation_fractional_remainder_v266
on public.character_cultivation_state;

create trigger trg_normalize_cultivation_fractional_remainder_v266
before insert or update of fractional_remainder
on public.character_cultivation_state
for each row
execute function public.normalize_cultivation_fractional_remainder_v266();

-- ---------- 根修当前 claim_cultivation_v1 ----------
-- 不重写整份函数，直接读取生产库当前定义并只替换已知危险上限常量，
-- 最大限度保留当前已部署的 SQL265 R2 其它逻辑。
do $patch_claim$
declare
  r record;
  v_scale integer;
  v_cap numeric;
  v_def text;
  v_new_def text;
  v_patched integer := 0;
begin
  select numeric_scale
    into v_scale
  from information_schema.columns
  where table_schema='public'
    and table_name='character_cultivation_state'
    and column_name='fractional_remainder';

  v_cap := 1::numeric - power(10::numeric, -v_scale);

  for r in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='public'
      and p.proname='claim_cultivation_v1'
  loop
    v_def := pg_get_functiondef(r.oid);

    -- SQL264/265 R2 已知使用此硬编码上限；若生产定义中存在则替换。
    if position('0.999999999999' in v_def) > 0 then
      v_new_def := replace(v_def, '0.999999999999', v_cap::text);
      execute v_new_def;
      v_patched := v_patched + 1;
    end if;
  end loop;

  raise notice 'SQL266_R2_CLAIM_FUNCTIONS_PATCHED=%', v_patched;
end
$patch_claim$;

-- ---------- 清理当前仍不合法的行 ----------
-- R1 已经处理过；这里只作为 R2 自洽保护。
do $normalize_existing$
declare
  v_scale integer;
  v_cap numeric;
begin
  select numeric_scale
    into v_scale
  from information_schema.columns
  where table_schema='public'
    and table_name='character_cultivation_state'
    and column_name='fractional_remainder';

  v_cap := 1::numeric - power(10::numeric, -v_scale);

  update public.character_cultivation_state
  set fractional_remainder =
    case
      when fractional_remainder is null
        or fractional_remainder::text in ('NaN','Infinity','-Infinity')
        or fractional_remainder < 0
        then 0::numeric
      when fractional_remainder = 1::numeric
        then v_cap
      when fractional_remainder > 1::numeric
        then least(v_cap, greatest(0::numeric, fractional_remainder - floor(fractional_remainder)))
      else least(v_cap, fractional_remainder)
    end
  where fractional_remainder is null
     or fractional_remainder::text in ('NaN','Infinity','-Infinity')
     or fractional_remainder < 0
     or fractional_remainder >= 1;
end
$normalize_existing$;

-- ---------- CHECK 保持标准 [0,1) ----------
do $ensure_check$
declare
  r record;
begin
  for r in
    select c.conname
    from pg_constraint c
    where c.conrelid='public.character_cultivation_state'::regclass
      and c.contype='c'
      and position(
        'fractional_remainder'
        in lower(coalesce(pg_get_expr(c.conbin,c.conrelid),''))
      ) > 0
  loop
    execute format(
      'alter table public.character_cultivation_state drop constraint %I',
      r.conname
    );
  end loop;

  alter table public.character_cultivation_state
    add constraint character_cultivation_state_fractional_remainder_check
    check (
      fractional_remainder >= 0::numeric
      and fractional_remainder < 1::numeric
    );
end
$ensure_check$;

-- ---------- GATE ----------
do $gate$
declare
  v_scale integer;
  v_cap numeric;
  v_bad bigint;
  v_trigger_count integer;
  v_old_literal_count integer;
begin
  select numeric_scale
    into v_scale
  from information_schema.columns
  where table_schema='public'
    and table_name='character_cultivation_state'
    and column_name='fractional_remainder';

  v_cap := 1::numeric - power(10::numeric, -v_scale);

  select count(*)
    into v_bad
  from public.character_cultivation_state
  where fractional_remainder is null
     or fractional_remainder::text in ('NaN','Infinity','-Infinity')
     or fractional_remainder < 0
     or fractional_remainder >= 1;

  if v_bad <> 0 then
    raise exception 'SQL266_R2_GATE_BAD_REMAINDER_ROWS:%', v_bad;
  end if;

  select count(*)
    into v_trigger_count
  from pg_trigger
  where tgrelid='public.character_cultivation_state'::regclass
    and tgname='trg_normalize_cultivation_fractional_remainder_v266'
    and not tgisinternal;

  if v_trigger_count <> 1 then
    raise exception 'SQL266_R2_GATE_WRITE_GUARD_MISSING';
  end if;

  select count(*)
    into v_old_literal_count
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='claim_cultivation_v1'
    and position('0.999999999999' in pg_get_functiondef(p.oid)) > 0;

  if v_old_literal_count <> 0 then
    raise exception 'SQL266_R2_GATE_OLD_UNSAFE_CAP_STILL_PRESENT:%', v_old_literal_count;
  end if;

  raise notice 'SQL266_R2_GATE_PASSED';
  raise notice 'numeric_scale=% safe_cap=%', v_scale, v_cap;
end
$gate$;

commit;

-- ---------- 执行后观察 ----------
-- 1) 确认字段精度：
-- select data_type, numeric_precision, numeric_scale
-- from information_schema.columns
-- where table_schema='public'
--   and table_name='character_cultivation_state'
--   and column_name='fractional_remainder';
--
-- 2) 再用洗灵丹测试后，看最新审计：
-- select
--   character_id,
--   old_value,
--   normalized_value,
--   source,
--   call_context,
--   created_at
-- from public.cultivation_fractional_remainder_audit_v266
-- order by created_at desc
-- limit 20;
