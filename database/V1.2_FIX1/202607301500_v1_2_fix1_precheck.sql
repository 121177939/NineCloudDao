-- 九霄问道 V1.2 FIX1 CACHE38 升级前检查（只读）
do $$
begin
  if to_regclass('public.casino_bankroll_v1') is null then raise exception 'V1_2_FIX1_REQUIRED:casino_bankroll_v1';end if;
  if to_regprocedure('public.casino_bankroll_apply_v1(text,bigint,text,uuid,jsonb)') is null then raise exception 'V1_2_FIX1_REQUIRED:bankroll_apply';end if;
  if to_regprocedure('public.casino_secure_random_int_v1(integer)') is null then raise exception 'V1_2_FIX1_REQUIRED:secure_random';end if;
  if to_regprocedure('public.casino_debit_v1(uuid,text,bigint,text,text)') is null then raise exception 'V1_2_FIX1_REQUIRED:casino_debit';end if;
  if to_regprocedure('public.casino_credit_result_v0141(uuid,text,bigint)') is null then raise exception 'V1_2_FIX1_REQUIRED:casino_credit';end if;
  if to_regprocedure('public.get_my_birth_result_v12()') is null then raise exception 'V1_2_FIX1_REQUIRED:v1_2_mutation';end if;
  if not exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1 and cache_epoch>=37) then raise exception 'V1_2_FIX1_REQUIRED:CACHE37';end if;
end $$;
select 'release_baseline' check_name,exists(select 1 from public.jiuxiao_app_release_control where singleton_id=1 and cache_epoch>=37) ok,'数据库至少为V1.2 CACHE37' detail
union all select 'casino_bankroll_rows',(select count(*)=2 from public.casino_bankroll_v1 where stake_type in('spirit_stone','cultivation')),'复用现有灵石/修为赌场资金'
union all select 'secure_rng_compat',position('gen_random_bytes' in lower(pg_get_functiondef(to_regprocedure('public.casino_secure_random_int_v1(integer)'))))=0,'安全随机兼容修复已生效'
union all select 'paigow_namespace_available',to_regclass('public.paigow_rooms_bpaigow01') is null,'正式并线前不应存在旧B候选牌九表；若为测试库重复部署，请先清理候选对象';
