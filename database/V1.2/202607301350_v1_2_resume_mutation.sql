-- V1.2 CACHE37 恢复变异灵根战斗加成。
-- 请先确认68号升级后检查全部通过。
begin;
update public.battle_challenge_settings_bcombat01
set mutation_bonus_enabled=true,mutation_final_damage_bonus=0.08,updated_at=clock_timestamp() where singleton_id=1;
commit;
