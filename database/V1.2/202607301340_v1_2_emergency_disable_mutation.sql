-- V1.2 CACHE37 紧急停用变异灵根战斗加成。
-- 不删除变异状态、不回滚冲突替换结果；原五行与天生剑心继续工作。
begin;
update public.battle_challenge_settings_bcombat01
set mutation_bonus_enabled=false,updated_at=clock_timestamp() where singleton_id=1;
commit;
