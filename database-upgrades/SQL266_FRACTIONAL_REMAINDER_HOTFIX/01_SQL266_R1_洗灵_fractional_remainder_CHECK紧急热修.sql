-- 九霄问道 SQL266 R1 HOTFIX
-- 修复：character_cultivation_state.fractional_remainder CHECK 约束导致洗灵失败
-- 目标：
--   1) 不改玩家 cultivation 总修为；
--   2) 将 fractional_remainder 统一规范到 [0,1)；
--   3) 对今后异常写入在表边界自动规范，并保留审计；
--   4) 重建为明确的标准 CHECK；
--   5) 全程事务化，Gate 不通过则回滚。
--
-- 基线：V2.2.0 CACHE137 / SQL265 R2 HOTFIX
-- NEXT：后续数据库容量治理另开版本，不与本热修混在一起。

begin;

-- ---------- PRECHECK ----------
do $precheck$
begin
  if to_regclass('public.character_cultivation_state') is null then
    raise exception 'SQL266_PRECHECK_CHARACTER_CULTIVATION_STATE_MISSING';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema='public'
      and table_name='character_cultivation_state'
      and column_name='character_id'
  ) then
    raise exception 'SQL266_PRECHECK_CHARACTER_ID_MISSING';
  end if;

  if not exists (
    select 1
    from information_schema.columns
    where table_schema='public'
      and table_name='character_cultivation_state'
      and column_name='fractional_remainder'
  ) then
    raise exception 'SQL266_PRECHECK_FRACTIONAL_REMAINDER_MISSING';
  end if;
end
$precheck$;

-- ---------- 审计表 ----------
create table if not exists public.cultivation_fractional_remainder_audit_v266 (
  id bigint generated always as identity primary key,
  character_id uuid,
  old_value numeric,
  normalized_value numeric not null,
  source text not null,
  txid bigint not null default txid_current(),
  created_at timestamptz not null default clock_timestamp()
);

revoke all on table public.cultivation_fractional_remainder_audit_v266
from anon, authenticated;

-- 短暂锁住这张很小的状态表，避免重建 CHECK 的瞬间并发写入。
lock table public.character_cultivation_state in share row exclusive mode;

-- ---------- 移除旧的 fractional_remainder CHECK ----------
-- 不硬编码旧约束名：只移除该表中“表达式明确引用 fractional_remainder”的 CHECK。
do $drop_old_fractional_checks$
declare
  r record;
begin
  for r in
    select
      c.conname,
      pg_get_expr(c.conbin, c.conrelid) as expr
    from pg_constraint c
    where c.conrelid='public.character_cultivation_state'::regclass
      and c.contype='c'
      and position(
        'fractional_remainder'
        in lower(coalesce(pg_get_expr(c.conbin, c.conrelid),''))
      ) > 0
  loop
    execute format(
      'alter table public.character_cultivation_state drop constraint %I',
      r.conname
    );
  end loop;
end
$drop_old_fractional_checks$;

-- ---------- 修正当前异常值并留审计 ----------
-- fractional_remainder 的定义就是“小数余量”，合法域应为 [0,1)。
-- 对 >=1 的值只保留小数部分；对负数/NaN/Infinity 归零。
insert into public.cultivation_fractional_remainder_audit_v266(
  character_id, old_value, normalized_value, source
)
select
  ccs.character_id,
  ccs.fractional_remainder,
  case
    when ccs.fractional_remainder is null then 0::numeric
    when ccs.fractional_remainder::text in ('NaN','Infinity','-Infinity') then 0::numeric
    when ccs.fractional_remainder < 0 then 0::numeric
    when ccs.fractional_remainder >= 1
      then ccs.fractional_remainder - floor(ccs.fractional_remainder)
    else ccs.fractional_remainder
  end,
  'SQL266_R1_PREEXISTING_NORMALIZE'
from public.character_cultivation_state ccs
where ccs.fractional_remainder is null
   or ccs.fractional_remainder::text in ('NaN','Infinity','-Infinity')
   or ccs.fractional_remainder < 0
   or ccs.fractional_remainder >= 1;

update public.character_cultivation_state ccs
set fractional_remainder =
  case
    when ccs.fractional_remainder is null then 0::numeric
    when ccs.fractional_remainder::text in ('NaN','Infinity','-Infinity') then 0::numeric
    when ccs.fractional_remainder < 0 then 0::numeric
    when ccs.fractional_remainder >= 1
      then ccs.fractional_remainder - floor(ccs.fractional_remainder)
    else ccs.fractional_remainder
  end
where ccs.fractional_remainder is null
   or ccs.fractional_remainder::text in ('NaN','Infinity','-Infinity')
   or ccs.fractional_remainder < 0
   or ccs.fractional_remainder >= 1;

-- ---------- 表边界保护 ----------
-- SQL265 R2 的 claim_cultivation_v1 已经主动 clamp；
-- 这里再给所有其它旧 RPC（例如洗灵链）加最后一道数据边界保护。
create or replace function public.normalize_cultivation_fractional_remainder_v266()
returns trigger
language plpgsql
security definer
set search_path=''
as $body$
declare
  v_old numeric;
  v_new numeric;
begin
  v_old := new.fractional_remainder;

  v_new :=
    case
      when v_old is null then 0::numeric
      when v_old::text in ('NaN','Infinity','-Infinity') then 0::numeric
      when v_old < 0 then 0::numeric
      when v_old >= 1 then v_old - floor(v_old)
      else v_old
    end;

  if v_new is distinct from v_old then
    insert into public.cultivation_fractional_remainder_audit_v266(
      character_id, old_value, normalized_value, source
    )
    values(
      new.character_id,
      v_old,
      v_new,
      'SQL266_R1_WRITE_GUARD'
    );

    new.fractional_remainder := v_new;
  end if;

  return new;
end
$body$;

revoke all on function public.normalize_cultivation_fractional_remainder_v266()
from public, anon, authenticated;

drop trigger if exists trg_normalize_cultivation_fractional_remainder_v266
on public.character_cultivation_state;

create trigger trg_normalize_cultivation_fractional_remainder_v266
before insert or update of fractional_remainder
on public.character_cultivation_state
for each row
execute function public.normalize_cultivation_fractional_remainder_v266();

-- ---------- 重建标准 CHECK ----------
alter table public.character_cultivation_state
add constraint character_cultivation_state_fractional_remainder_check
check (
  fractional_remainder >= 0::numeric
  and fractional_remainder < 1::numeric
);

-- ---------- GATE ----------
do $gate$
declare
  v_bad bigint;
  v_constraint_expr text;
  v_trigger_count integer;
begin
  select count(*)
    into v_bad
  from public.character_cultivation_state
  where fractional_remainder is null
     or fractional_remainder::text in ('NaN','Infinity','-Infinity')
     or fractional_remainder < 0
     or fractional_remainder >= 1;

  if v_bad <> 0 then
    raise exception 'SQL266_GATE_INVALID_FRACTIONAL_REMAINDER_ROWS:%', v_bad;
  end if;

  select pg_get_expr(c.conbin,c.conrelid)
    into v_constraint_expr
  from pg_constraint c
  where c.conrelid='public.character_cultivation_state'::regclass
    and c.contype='c'
    and c.conname='character_cultivation_state_fractional_remainder_check'
  limit 1;

  if v_constraint_expr is null then
    raise exception 'SQL266_GATE_FRACTIONAL_CHECK_MISSING';
  end if;

  select count(*)
    into v_trigger_count
  from pg_trigger t
  where t.tgrelid='public.character_cultivation_state'::regclass
    and t.tgname='trg_normalize_cultivation_fractional_remainder_v266'
    and not t.tgisinternal;

  if v_trigger_count <> 1 then
    raise exception 'SQL266_GATE_WRITE_GUARD_MISSING';
  end if;

  raise notice 'SQL266_GATE_PASSED';
  raise notice 'fractional_remainder CHECK = %', v_constraint_expr;
end
$gate$;

commit;

-- ---------- 执行后可选观察 ----------
-- 看热修前/后是否捕获过异常余量：
-- select *
-- from public.cultivation_fractional_remainder_audit_v266
-- order by created_at desc
-- limit 50;
