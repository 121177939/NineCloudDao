-- 部署后静态/结构检查。所有 ok 应为 true。
select 'book_table' as check_name,to_regclass('public.character_technique_books') is not null as ok
union all select 'book_library_rpc',to_regprocedure('public.get_technique_library_v1()') is not null
union all select 'book_use_rpc',to_regprocedure('public.use_technique_book_v1(uuid)') is not null
union all select 'book_add_helper',to_regprocedure('public.technique_book_add_v1(uuid,text,text,integer,timestamptz,jsonb)') is not null
union all select 'ordinary_award_override',position('technique_book_add_v1' in pg_get_functiondef(to_regprocedure('public.opportunity_v4_award_ordinary_technique(uuid,uuid,integer,text,timestamptz)')))>0
union all select 'ordinary_no_auto_learn',position('award_opportunity_technique_v3' in pg_get_functiondef(to_regprocedure('public.opportunity_v4_award_ordinary_technique(uuid,uuid,integer,text,timestamptz)')))=0
union all select 'settle_uses_books',position('technique_book_summary_add_v1' in pg_get_functiondef(to_regprocedure('public.settle_opportunity_v4(boolean)')))>0
union all select 'ordinary_pool_24',(select count(*)=24 from public.opportunity_v4_technique_pool where is_active)
union all select 'exclusive_pool_5',(select count(*)=5 from public.exclusive_technique_definitions);

select book_kind,count(*) as row_count,coalesce(sum(quantity),0) as total_books
from public.character_technique_books group by book_kind order by book_kind;
