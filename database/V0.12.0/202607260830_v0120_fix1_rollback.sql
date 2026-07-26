-- V0.12.0 FIX1 安全回滚
-- 会先退还所有尚未结算的赌注，再移除赌场RPC和结构。
begin;

create schema if not exists ncd_release_backup;
revoke all on schema ncd_release_backup from public;

drop table if exists ncd_release_backup.v0120_fix1_casino_settings;
create table ncd_release_backup.v0120_fix1_casino_settings as select * from public.casino_settings with no data;
drop table if exists ncd_release_backup.v0120_fix1_casino_pools;
create table ncd_release_backup.v0120_fix1_casino_pools as select * from public.casino_pools with no data;
drop table if exists ncd_release_backup.v0120_fix1_casino_duels;
create table ncd_release_backup.v0120_fix1_casino_duels as select * from public.casino_duels with no data;
drop table if exists ncd_release_backup.v0120_fix1_casino_house_games;
create table ncd_release_backup.v0120_fix1_casino_house_games as select * from public.casino_house_games with no data;
drop table if exists ncd_release_backup.v0120_fix1_casino_daily_activity;
create table ncd_release_backup.v0120_fix1_casino_daily_activity as select * from public.casino_daily_activity with no data;
drop table if exists ncd_release_backup.v0120_fix1_casino_tickets;
create table ncd_release_backup.v0120_fix1_casino_tickets as select * from public.casino_tickets with no data;
drop table if exists ncd_release_backup.v0120_fix1_casino_draws;
create table ncd_release_backup.v0120_fix1_casino_draws as select * from public.casino_draws with no data;


insert into ncd_release_backup.v0120_fix1_casino_settings select * from public.casino_settings;
insert into ncd_release_backup.v0120_fix1_casino_pools select * from public.casino_pools;
insert into ncd_release_backup.v0120_fix1_casino_duels select * from public.casino_duels;
insert into ncd_release_backup.v0120_fix1_casino_house_games select * from public.casino_house_games;
insert into ncd_release_backup.v0120_fix1_casino_daily_activity select * from public.casino_daily_activity;
insert into ncd_release_backup.v0120_fix1_casino_tickets select * from public.casino_tickets;
insert into ncd_release_backup.v0120_fix1_casino_draws select * from public.casino_draws;

do $$
declare d record;
begin
  if to_regclass('public.casino_duels') is not null then
    for d in select * from public.casino_duels where status in('open','sealed') for update loop
      if d.stake_type='spirit_stone' then
        perform public.award_spirit_stones_v3(d.creator_character_id,d.stake_amount);
        if d.status='sealed' and d.opponent_character_id is not null then perform public.award_spirit_stones_v3(d.opponent_character_id,d.stake_amount); end if;
      else
        update public.player_characters set cultivation=cultivation+d.stake_amount,updated_at=now() where id=d.creator_character_id;
        if d.status='sealed' and d.opponent_character_id is not null then update public.player_characters set cultivation=cultivation+d.stake_amount,updated_at=now() where id=d.opponent_character_id; end if;
      end if;
    end loop;
  end if;
end$$;

drop function if exists public.get_market_v1();
drop function if exists public.play_house_game_v1(text,text,bigint,text);
drop function if exists public.create_duel_v1(text,text,bigint,text);
drop function if exists public.join_duel_v1(uuid,text);
drop function if exists public.cancel_duel_v1(uuid);
drop function if exists public.casino_process_v1();
drop function if exists public.casino_draw_pools_v1();
drop function if exists public.casino_settle_duels_v1();
drop function if exists public.casino_expire_open_duels_v1();
drop function if exists public.casino_add_ticket_v1(uuid,text);
drop function if exists public.casino_record_activity_v1(uuid,text,text);
drop function if exists public.casino_assert_activity_allowed_v1(uuid,text,text);
drop function if exists public.casino_realign_after_loss_v1(uuid);
drop function if exists public.casino_credit_v1(uuid,text,bigint);
drop function if exists public.casino_debit_v1(uuid,text,bigint,text,text);
drop function if exists public.casino_result_v1(text,text,text);
drop function if exists public.casino_choice_name_v1(text,text);
drop function if exists public.casino_validate_choice_v1(text,text);
drop function if exists public.casino_available_v1(uuid,text);
drop function if exists public.casino_nascent_major_order_v1();
drop function if exists public.casino_stone_item_id_v1();
drop function if exists public.casino_current_character_id_v1();
drop function if exists public.casino_assert_enabled_v1();

drop table if exists public.casino_draws;
drop table if exists public.casino_tickets;
drop table if exists public.casino_daily_activity;
drop table if exists public.casino_house_games;
drop table if exists public.casino_duels;
drop table if exists public.casino_pools;
drop table if exists public.casino_settings;

commit;
