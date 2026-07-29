-- 九霄问道 V1.0 战斗挑战紧急停用
-- 仅停用主动挑战；元神属性和战力榜仍可读取。
begin;
update public.battle_challenge_settings_bcombat01
set enabled=false,updated_at=clock_timestamp()
where singleton_id=1;
notify pgrst,'reload schema';
commit;
