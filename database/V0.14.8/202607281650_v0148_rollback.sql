-- 九霄问道 V0.14.8 鱼虾灵局结构回滚
-- 安全门禁：只允许在尚无任何鱼虾灵局下注记录时执行。
-- 若已有下注或结算记录，本脚本会主动拒绝，避免删除审计与资源结算证据。
begin;

do $$
begin
  if to_regclass('public.casino_fish_bets_v0148') is not null
     and exists(select 1 from public.casino_fish_bets_v0148 limit 1) then
    raise exception 'V0148_ROLLBACK_REFUSED:FISH_BET_HISTORY_EXISTS';
  end if;
end;
$$;

drop function if exists public.place_fish_shrimp_bet_v0148(text,text,text,bigint);
drop function if exists public.get_fish_shrimp_state_v0148(integer);
drop function if exists public.casino_fish_round_summary_v0148(uuid,uuid);
drop function if exists public.casino_fish_ensure_round_v0148();
drop function if exists public.casino_fish_settle_round_v0148(uuid);
drop function if exists public.casino_fish_create_round_v0148(bigint);
drop function if exists public.casino_fish_symbol_name_v0148(text);
drop table if exists public.casino_fish_bets_v0148;
drop table if exists public.casino_fish_rounds_v0148;

update public.jiuxiao_app_release_control
set release_name='V0.14.7 CACHE11',
    notice_text='鱼虾灵局结构已回滚，请同步回滚前端源码。',
    updated_at=now()
where singleton_id=1;

commit;
notify pgrst,'reload schema';
