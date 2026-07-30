-- B-PAIGOW01 / 00_PRECHECK.sql
-- B线候选，不是正式迁移；只能由A线在 V1.2 CACHE37 测试库执行。
do $$
begin
  if to_regclass('public.casino_bankroll_v1') is null then raise exception 'BPAIGOW01_REQUIRES_CASINO_BANKROLL_V1'; end if;
  if to_regprocedure('public.casino_bankroll_apply_v1(text,bigint,text,uuid,jsonb)') is null then raise exception 'BPAIGOW01_REQUIRES_BANKROLL_APPLY_V1'; end if;
  if to_regprocedure('public.casino_secure_random_int_v1(integer)') is null then raise exception 'BPAIGOW01_REQUIRES_SECURE_RANDOM_V1'; end if;
  if to_regprocedure('public.casino_current_character_id_v1()') is null then raise exception 'BPAIGOW01_REQUIRES_CURRENT_CHARACTER_V1'; end if;
  if to_regprocedure('public.casino_debit_v1(uuid,text,bigint,text,text)') is null then raise exception 'BPAIGOW01_REQUIRES_DEBIT_V1'; end if;
  if to_regprocedure('public.casino_credit_result_v0141(uuid,text,bigint)') is null then raise exception 'BPAIGOW01_REQUIRES_CREDIT_RESULT_V0141'; end if;
end $$;
